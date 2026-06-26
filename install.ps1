# ============================================================
# DoubleEdge — Windows environment bootstrap (install.ps1)
#
# requirements.txt を解析し、不足している依存（system / npm / manual）を
# 検証・導入補助します。さらに .env.example から .env を作成します。
#
# 使い方:
#   .\install.ps1
#   .\install.ps1 -CheckOnly
#   .\install.ps1 -Force
# ============================================================

param (
    [switch]$CheckOnly,
    [switch]$Force
)

# ── 設定 ──────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReqFile = Join-Path $ScriptDir "requirements.txt"
$EnvFile = Join-Path $ScriptDir ".env"
$EnvExample = Join-Path $ScriptDir ".env.example"

# ── 色出力用ヘルパー ────────────────────────────────────────
function Log-Info {
    param([string]$Message)
    Write-Host "[install] $Message" -ForegroundColor Cyan
}

function Log-Ok {
    param([string]$Message)
    Write-Host "[ ok ] $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Log-Error {
    param([string]$Message)
    Write-Error "[fail] $Message"
}

if (-not (Test-Path $ReqFile)) {
    Log-Error "requirements.txt が見つかりません: $ReqFile"
    exit 1
}

# ── パッケージマネージャの検出 ──────────────────────────────
$HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$HasScoop = $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)

# ── 確認プロンプトヘルパー ──────────────────────────────────
function Confirm-Action {
    param([string]$Message)
    if ($Force) { return $true }
    $ans = Read-Host "  $Message [Y/N]"
    return ($ans -match '^[Yy]$' -or $ans -eq '')
}

# ── トラッキング変数 ────────────────────────────────────────
$Missing = @()
$Installed = @()
$Manual = @()
$Failed = @()

# ── 個別インストーラー ──────────────────────────────────────
function Install-System {
    param([string]$Name, [string]$Pkg)
    
    # Windows上で winget または scoop があればそれを使ってインストールを案内
    if ($CheckOnly) {
        $Missing += "$Name ($Pkg)"
        return
    }

    if (Confirm-Action "winget / scoop を使用して $Name をインストールしますか？") {
        $success = $false
        if ($HasWinget) {
            Log-Info "winget を使用して $Name をインストール中..."
            # パッケージ名マッピングの簡易調整
            $wingetPkg = $Pkg
            if ($Pkg -eq "tmux") { $wingetPkg = "MSYS2.MSYS2" } # tmux自体はMSYS2経由
            
            Start-Process winget -ArgumentList "install --silent --accept-source-agreements --accept-package-agreements $wingetPkg" -Wait
            $success = $true
        } elseif ($HasScoop) {
            Log-Info "scoop を使用して $Name をインストール中..."
            Start-Process scoop -ArgumentList "install $Pkg" -Wait
            $success = $true
        }

        if ($success) {
            $Installed += $Name
            Log-Ok "$Name のインストールコマンドを送信しました。"
        } else {
            $Failed += $Name
            Log-Warn "パッケージマネージャ (winget / scoop) が見つからないため、$Name の自動インストールをスキップしました。手動で導入してください。"
            $Manual += "$Name ($Pkg)"
        }
    } else {
        $Manual += "$Name ($Pkg)"
    }
}

function Install-Npm {
    param([string]$Name, [string]$Pkg)
    
    # npm コマンドの存在確認
    $hasNpm = $null -ne (Get-Command npm -ErrorAction SilentlyContinue)
    if (-not $hasNpm) {
        Log-Warn "npm が見つかりません。先に Node.js をインストールしてください ($Name に必要)。"
        $Manual += "$Name (npm: $Pkg; Node.js を先にインストール)"
        return
    }

    if ($CheckOnly) {
        $Missing += "$Name (npm: $Pkg)"
        return
    }

    if (Confirm-Action "npm install -g $Pkg を実行して $Name をインストールしますか？") {
        Log-Info "npm を使用して $Name をインストール中..."
        # Windows PowerShellでは npm.cmd を明示的に呼ぶ必要がある場合がある
        $npmCmd = "npm"
        if ($IsWindows) { $npmCmd = "npm.cmd" }
        
        $proc = Start-Process $npmCmd -ArgumentList "install -g $Pkg" -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -eq 0) {
            $Installed += $Name
            Log-Ok "$Name をグローバルインストールしました。"
        } else {
            $Failed += $Name
            Log-Error "$Name のインストールに失敗しました。"
        }
    } else {
        $Manual += "$Name (npm: $Pkg)"
    }
}

function Install-Manual {
    param([string]$Name, [string]$Hint)
    Log-Warn "${Name}: 手動インストールが必要です — $Hint"
    $Manual += "$Name ($Hint)"
}

# ── requirements.txt の解析と検証 ───────────────────────────
Log-Info "Reading requirements from $ReqFile"
Log-Info "Package manager: Winget: $(if($HasWinget){'Yes'}else{'No'}), Scoop: $(if($HasScoop){'Yes'}else{'No'})"
Write-Host ""

# requirements.txt の各行をループ
Get-Content $ReqFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) {
        return # 空行やコメントはスキップ
    }

    # 行をスペースで分割
    # 例: tmux    system  tmux    3.0
    $parts = $line -split '\s+'
    if ($parts.Length -lt 3) { return }

    $name = $parts[0]
    $method = $parts[1]
    $pkg = $parts[2]
    
    # インラインコメントの除去
    if ($pkg.Contains("#")) {
        $pkg = ($pkg -split "#")[0].Trim()
    }

    # コマンドの存在確認
    # Windows の場合、curl は標準のエイリアス (Invoke-WebRequest) と競合するため、curl.exe で検証する
    $chkCmd = $name
    if ($name -eq "curl") { $chkCmd = "curl.exe" }
    
    $hasCommand = $null -ne (Get-Command $chkCmd -ErrorAction SilentlyContinue)

    if ($hasCommand) {
        Log-Ok "$name present"
        return
    }

    Log-Warn "$name missing"
    switch ($method) {
        "system" { Install-System $name $pkg }
        "npm"    { Install-Npm $name $pkg }
        "manual" { Install-Manual $name $pkg }
        default  { Log-Warn "未知のインストール方法: $method ($name)" }
    }
}

# ── .env ファイルのセットアップ ──────────────────────────────
Write-Host ""
Log-Info "Checking .env"
if (Test-Path $EnvFile) {
    Log-Ok ".env already exists"
    $envContent = Get-Content $EnvFile
    $hasKey = $false
    foreach ($line in $envContent) {
        if ($line -match '^DEEPSEEK_API_KEY=.+$') {
            $hasKey = $true
            break
        }
    }
    if ($hasKey) {
        Log-Ok "DEEPSEEK_API_KEY is set"
    } else {
        Log-Warn "DEEPSEEK_API_KEY が .env に設定されていません。DS (cline) の認証に失敗する可能性があります。"
    }
} elseif (Test-Path $EnvExample) {
    if ($CheckOnly) {
        Log-Warn ".env が見つかりません (CheckOnlyモードを外して作成してください)"
    } else {
        Copy-Item $EnvExample $EnvFile
        Log-Ok "created .env from .env.example"
        Log-Warn ".env を編集し、DEEPSEEK_API_KEY を設定してから setup-doubleedge.ps1 を実行してください。"
    }
} else {
    Log-Warn ".env.example が見つからないため、.env を作成できませんでした。"
}

# ── 概要出力 ────────────────────────────────────────────────
Write-Host ""
Write-Host "── summary ──────────────────────────────────"
if ($Installed.Count -gt 0) {
    Write-Host "installed:" -ForegroundColor Green
    foreach ($item in $Installed) { Write-Host "  - $item" }
}
if ($Missing.Count -gt 0) {
    Write-Host "missing  :" -ForegroundColor Yellow
    foreach ($item in $Missing) { Write-Host "  - $item" }
}
if ($Manual.Count -gt 0) {
    Write-Host "manual   :" -ForegroundColor Yellow
    foreach ($item in $Manual) { Write-Host "  - $item" }
}
if ($Failed.Count -gt 0) {
    Write-Host "failed   :" -ForegroundColor Red
    foreach ($item in $Failed) { Write-Host "  - $item" }
}

if ($Failed.Count -gt 0) {
    Log-Error "一部のツールのインストールに失敗しました。上記を確認してください。"
    exit 1
}

# tmux (MSYS2) が見つからない場合の追加警告
$hasTmux = $null -ne (Get-Command tmux -ErrorAction SilentlyContinue)
if (-not $hasTmux) {
    Write-Host ""
    Log-Warn "【重要】Windows 上で tmux を動作させるための準備："
    Write-Host "  1. MSYS2 をインストールしてください（winget install MSYS2.MSYS2 または scoop install msys2）"
    Write-Host "  2. MSYS2 MSYS ターミナルを開き、'pacman -S tmux' を実行して tmux を導入してください。"
    Write-Host "  3. MSYS2 の bin パス（例: C:\msys64\usr\bin）をシステム環境変数 PATH に追加し、PowerShell を再起動してください。"
    Write-Host ""
}

Write-Host ""
Log-Ok "done. next: .env を編集後、.\setup-doubleedge.ps1 を実行してください。"
