# ============================================================
# DoubleEdge — tmux-based multi-agent orchestration loop (setup-doubleedge.ps1)
#
# Windows (PowerShell) 環境用の起動・管理スクリプトです。
# MSYS2 の tmux を呼び出して 6つのペインを連携させます。
#
# 使い方:
#   .\setup-doubleedge.ps1 [session_name]   # 既定: doubleedge
#   .\setup-doubleedge.ps1 -Kill            # セッションの破棄
# ============================================================

param (
    [string]$Session = "doubleedge",
    [string]$WorkDir = "",
    [switch]$Kill
)

# ── 設定 ──────────────────────────────────────────────────
$WORKDIR = if ($WorkDir) { Resolve-Path $WorkDir } else { $PWD.Path }
$WATCH_INTERVAL = 30   # クォータ監視の間隔（秒）
$LogDir = Join-Path $WORKDIR ".doubleedge\logs"
$SignalFile = Join-Path $WORKDIR ".doubleedge\stop_signal"
$WatchdogScript = Join-Path $WORKDIR ".doubleedge\watchdog.sh"

# ── 色出力用ヘルパー ────────────────────────────────────────
function Log-Info {
    param([string]$Message)
    Write-Host "[DoubleEdge] $Message" -ForegroundColor Cyan
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Log-Error {
    param([string]$Message)
    Write-Error "[ERROR] $Message"
}

# ── セッション破棄処理 ──────────────────────────────────────
if ($Kill) {
    Log-Info "Destroying session '${Session}'..."
    tmux kill-session -t "${Session}" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Log-Info "Done."
    } else {
        Log-Warn "Session not found."
    }
    exit 0
}

# ── パス変換ヘルパー (Windows -> MSYS/Unix) ──────────────────
function Convert-ToMsysPath {
    param([string]$WindowsPath)
    if (-not $WindowsPath) { return "" }
    $path = $WindowsPath.Replace('\', '/')
    # ドライブレター (C:) を /c に置換
    if ($path -match '^([A-Za-z]):(.*)') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2]
        return "/$drive$rest"
    }
    return $path
}

# ── .env ファイルのロード ────────────────────────────────────
$EnvFile = Join-Path $WORKDIR ".env"
if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile
    foreach ($line in $envContent) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            # 引用符の除去
            if ($val -match '^"(.*)"$|^''(.*)''$') {
                $val = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            }
            [System.Environment]::SetEnvironmentVariable($key, $val, [System.EnvironmentVariableTarget]::Process)
        }
    }
    Log-Info "Loaded secrets from .env"
} else {
    Log-Warn ".env not found — run .\install.ps1 or 'cp .env.example .env' and set DEEPSEEK_API_KEY"
}

# OpenAI互換 API のための環境変数エイリアス設定
if ($env:DEEPSEEK_API_KEY) {
    $env:OPENAI_API_KEY = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { $env:DEEPSEEK_API_KEY }
    $env:OPENAI_BASE_URL = if ($env:OPENAI_BASE_URL) { $env:OPENAI_BASE_URL } else { if ($env:DEEPSEEK_BASE_URL) { $env:DEEPSEEK_BASE_URL } else { "https://api.deepseek.com" } }
} else {
    Log-Warn "DEEPSEEK_API_KEY is empty — DS (cline) may fail to authenticate"
}

# ── 依存関係チェック ────────────────────────────────────────
$dependencies = @(
    @{ Name = "git"; Cmd = "git" },
    @{ Name = "curl"; Cmd = "curl.exe" },
    @{ Name = "cline"; Cmd = "cline" },
    @{ Name = "claude"; Cmd = "claude" },
    @{ Name = "agy"; Cmd = "agy" },
    @{ Name = "tmux"; Cmd = "tmux" }
)
foreach ($dep in $dependencies) {
    if (-not (Get-Command $dep.Cmd -ErrorAction SilentlyContinue)) {
        Log-Error "$($dep.Name) が見つかりません。.\install.ps1 を実行して依存関係を確認・インストールしてください。"
        exit 1
    }
}

# ── 既存セッションの確認 ────────────────────────────────────
tmux has-session -t "${Session}" 2>$null
if ($LASTEXITCODE -eq 0) {
    Log-Warn "Session '${Session}' already exists."
    # APIサーバー等の非対話的なバックグラウンド起動環境を考慮し、Read-Host のフリーズを回避
    if ($env:DE_NON_INTERACTIVE -eq "true" -or -not [Environment]::UserInteractive) {
        Log-Info "Non-interactive environment detected. Recreating session '${Session}'..."
        tmux kill-session -t "${Session}" 2>$null
    } else {
        $ans = Read-Host "  Attach to existing session? [Y/n]"
        if ($ans -match '^[Yy]$' -or $ans -eq '') {
            tmux attach-session -t "${Session}"
            exit 0
        } else {
            tmux kill-session -t "${Session}" 2>$null
            Log-Info "Old session destroyed. Recreating..."
        }
    }
}

# ── ディレクトリ準備 ────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $LogDir > $null
if (Test-Path $SignalFile) { Remove-Item $SignalFile -Force }

# ── watchdog.sh の生成 ──────────────────────────────────────
$WatchdogContent = @'
#!/usr/bin/env bash
# DoubleEdge watchdog — quota sentinel
# Runs in pane 5. No LLM calls, no token cost.

SESSION="$1"
INTERVAL="$2"
SIGNAL_FILE="$3"
LOG_DIR="$4"

QUOTA_PATTERNS=(
  "Individual quota reached"
  "quota reached"
  "You've hit your session limit"
  "You've hit your weekly limit"
  "You've hit your Opus limit"
)

# pane index → friendly name
declare -A PANE_NAME=([1]="BLADE(Claude)" [2]="AG-1" [3]="AG-2" [4]="AG-3")

ts() { date '+%H:%M:%S'; }

echo "[watchdog] $(ts) started — interval ${INTERVAL}s, watching panes 1-4"

while true; do
  sleep "${INTERVAL}"

  for idx in 1 2 3 4; do
    output=$(tmux capture-pane -t "${SESSION}:0.${idx}" -p 2>/dev/null) || continue
    [[ -z "$output" ]] && continue

    for pattern in "${QUOTA_PATTERNS[@]}"; do
      if echo "$output" | grep -qF "$pattern"; then
        name="${PANE_NAME[$idx]:-pane${idx}}"
        reset_hint=$(echo "$output" | grep -oP 'Resets in [^\n]+' | head -1 || \
                     echo "$output" | grep -oP 'resets [^\n]+' | head -1 || \
                     echo "reset time unknown")

        msg="STOP_SIGNAL:QUOTA pane=${idx} tool=${name} pattern='${pattern}' ${reset_hint}"

        # write to signal file
        echo "$(ts) ${msg}" >> "${SIGNAL_FILE}"
        echo "$(ts) ${msg}" >> "${LOG_DIR}/watchdog.log"

        # notify DS pane (pane 0) via send-keys
        tmux send-keys -t "${SESSION}:0.0" "" ""   # wake cursor
        tmux send-keys -t "${SESSION}:0.0" \
          "[DoubleEdge watchdog] ${msg}" Enter

        echo "[watchdog] $(ts) STOP_SIGNAL sent for ${name}"
        break
      fi
    done
  done
done
'@
[System.IO.File]::WriteAllText($WatchdogScript, $WatchdogContent)

# ── MSYS用パスへの変換 ──────────────────────────────────────
$MsysWorkdir = Convert-ToMsysPath $WORKDIR
$MsysWatchdogScript = Convert-ToMsysPath $WatchdogScript
$MsysSignalFile = Convert-ToMsysPath $SignalFile
$MsysLogDir = Convert-ToMsysPath $LogDir

# ── tmux セッション構築 ─────────────────────────────────────
# MSYS2 が Windows の PATH を引き継げるようにする（cline 等の呼び出しに必須）
$env:MSYS2_PATH_TYPE = "inherit"

Log-Info "Creating tmux session '${Session}' in ${MsysWorkdir}..."

# pane 0: DS / Cline
tmux new-session -d -s "${Session}" -n "main" -c "${MsysWorkdir}"

# pane 1: BLADE — Claude Code
tmux split-window -t "${Session}:0" -v -c "${MsysWorkdir}"

# pane 2: AG-1 Implementer
tmux split-window -t "${Session}:0" -h -c "${MsysWorkdir}"

# pane 3: AG-2 Auditor
tmux select-pane -t "${Session}:0.0"
tmux split-window -t "${Session}:0" -h -c "${MsysWorkdir}"

# pane 4: AG-3 Alternative
tmux select-pane -t "${Session}:0.1"
tmux split-window -t "${Session}:0.1" -h -c "${MsysWorkdir}"

# pane 5: watchdog
tmux select-pane -t "${Session}:0.0"
tmux split-window -t "${Session}:0" -v -l 4 -c "${MsysWorkdir}"

# レイアウト整理
tmux select-layout -t "${Session}:0" tiled

# ペインのタイトル設定
tmux select-pane -t "${Session}:0.0" -T "DS | DeepSeek V4 Pro"
tmux select-pane -t "${Session}:0.1" -T "BLADE | Claude Code"
tmux select-pane -t "${Session}:0.2" -T "AG-1 | Implementer"
tmux select-pane -t "${Session}:0.3" -T "AG-2 | Auditor (GOZEN)"
tmux select-pane -t "${Session}:0.4" -T "AG-3 | Alternative"
tmux select-pane -t "${Session}:0.5" -T "WATCH | quota watchdog"

# ── 各エージェントの起動 ────────────────────────────────────
Log-Info "Starting DS (Cline) in pane 0..."
tmux send-keys -t "${Session}:0.0" "echo '[DS] DeepSeek V4 Pro — control plane ready'; cline" Enter

Log-Info "Starting Claude Code (interactive) in pane 1..."
tmux send-keys -t "${Session}:0.1" "echo '[BLADE] Claude Code — integration layer ready'; claude" Enter

Log-Info "Starting agy AG-1 (Implementer) in pane 2..."
tmux send-keys -t "${Session}:0.2" "echo '[AG-1] agy Implementer — standby'; agy" Enter

Log-Info "Starting agy AG-2 (Auditor) in pane 3..."
tmux send-keys -t "${Session}:0.3" "echo '[AG-2] agy Auditor (GOZEN) — standby'; agy" Enter

Log-Info "Starting agy AG-3 (Alternative) in pane 4..."
tmux send-keys -t "${Session}:0.4" "echo '[AG-3] agy Alternative — standby'; agy" Enter

Log-Info "Starting quota watchdog in pane 5..."
tmux send-keys -t "${Session}:0.5" "bash '${MsysWatchdogScript}' '${Session}' '${WATCH_INTERVAL}' '${MsysSignalFile}' '${MsysLogDir}'" Enter

# フォーカスを DS (pane 0) に戻す
tmux select-pane -t "${Session}:0.0"

Write-Host ""
Write-Host "DoubleEdge session '${Session}' ready." -ForegroundColor Green
Write-Host "  pane 0  DS      DeepSeek V4 Pro  (Cline / .clinerules)" -ForegroundColor Cyan
Write-Host "  pane 1  BLADE   Claude Code      (interactive)" -ForegroundColor Cyan
Write-Host "  pane 2  AG-1    agy Implementer  (speed-first)" -ForegroundColor Cyan
Write-Host "  pane 3  AG-2    agy Auditor       (GOZEN)" -ForegroundColor Cyan
Write-Host "  pane 4  AG-3    agy Alternative  (alternative)" -ForegroundColor Cyan
Write-Host "  pane 5  WATCH   quota watchdog" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Attach:  tmux attach-session -t ${Session}" -ForegroundColor Green
Write-Host "  Kill:    .\setup-doubleedge.ps1 -Kill" -ForegroundColor Red
Write-Host ""

# セッションへアタッチ
tmux attach-session -t "${Session}"
