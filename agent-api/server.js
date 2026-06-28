const express = require('express');
const cors = require('cors');
const { exec, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3001;
const SESSION_NAME = process.env.SESSION_NAME || 'doubleedge';

// プロジェクトのルートパスを取得
const ROOT_DIR = path.resolve(__dirname, '..');

// 簡易 .env 読み込み処理（dotenv依存なしで動作させるため）
const dotenvPath = path.join(ROOT_DIR, '.env');
if (fs.existsSync(dotenvPath)) {
    const content = fs.readFileSync(dotenvPath, 'utf8');
    content.split(/\r?\n/).forEach(line => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) return;
        const match = trimmed.match(/^([^=]+)=(.*)$/);
        if (match) {
            const key = match[1].trim();
            let val = match[2].trim();
            if (val.startsWith('"') && val.endsWith('"')) {
                val = val.substring(1, val.length - 1);
            } else if (val.startsWith("'") && val.endsWith("'")) {
                val = val.substring(1, val.length - 1);
            }
            process.env[key] = val;
        }
    });
}

// デバッグ用のモックモードフラグ
const MOCK_MODE = process.env.MOCK_MODE === 'true' || false;

app.use(cors());
app.use(express.json());

// リクエストログ出力ミドルウェア
app.use((req, res, next) => {
    console.log(`[API Log] ${req.method} ${req.url} - ${new Date().toISOString()}`);
    next();
});

// モック用の状態管理
let isMockRunning = false;
let mockActiveWorkdir = ROOT_DIR;
let mockLogs = {};

function initMockLogs() {
    mockLogs = {
        0: `[DS] DeepSeek V4 Pro — control plane ready (Workspace: ${mockActiveWorkdir})\n`,
        1: `[BLADE] Claude Code — integration layer ready\n`,
        2: `[AG-1] agy Implementer — standby\n`,
        3: `[AG-2] agy Auditor (GOZEN) — standby\n`,
        4: `[AG-3] agy Alternative — standby\n`,
        5: `[watchdog] started - interval 30s, watching panes 1-4\n`
    };
}
initMockLogs();

const mockTemplates = {
    0: [
        '[DS] Analyzing user request: "Implement WebUI dashboard"',
        '[DS] Decomposing tasks for subagents...',
        '[DS] Dispatching implementation subtask to AG-1',
        '[DS] Waiting for auditor review from AG-2...',
        '[DS] Review received. AG-2 approved the changes.',
        '[DS] Invoking BLADE (Claude Code) for integration...',
        '[DS] Integration completed successfully. Task done.'
    ],
    1: [
        '[BLADE] Scanning files for security vulnerability...',
        '[BLADE] Run static analyzer... OK',
        '[BLADE] Verifying code integrity and style consistency...',
        '[BLADE] Diff check: +4 lines, -2 lines in page.js',
        '[BLADE] Status: ACCEPTED'
    ],
    2: [
        '[AG-1] [ROLE: Implementer] Active',
        '[AG-1] Writing CSS classes in page.module.css...',
        '[AG-1] Designing 3x2 grid layout and glassmorphism cards...',
        '[AG-1] WebUI page.js file updated.',
        '[AG-1] [DONE: AG-1] WebUI implementation complete'
    ],
    3: [
        '[AG-2] [ROLE: Auditor] Active',
        '[AG-2] Auditing implementer\'s proposed changes...',
        '[AG-2] Check: check for memory leak in EventSource hooks... OK',
        '[AG-2] Check: viewport responsiveness... OK',
        '[AG-2] [DONE: AG-2] LGTM. No critical vulnerabilities found.'
    ],
    4: [
        '[AG-3] [ROLE: Alternative] Active',
        '[AG-3] Exploring alternative layout using TailwindCSS...',
        '[AG-3] Compared with Vanilla CSS. Vanilla CSS chosen for better flexibility.',
        '[AG-3] [DONE: AG-3] Alternative design notes documented.'
    ],
    5: [
        '[watchdog] check quota: ok (Gemini Pro token remaining: 84%)',
        '[watchdog] check quota: ok (Gemini Pro token remaining: 81%)',
        '[watchdog] check quota: ok (Gemini Pro token remaining: 79%)',
        '[watchdog] check quota: ok (Gemini Pro token remaining: 79%)'
    ]
};

// モックの自動ログ生成ループ
let mockInterval = null;
function startMockLogs(workdir) {
    mockActiveWorkdir = workdir;
    initMockLogs();
    
    if (mockInterval) clearInterval(mockInterval);
    
    let step = 0;
    mockInterval = setInterval(() => {
        if (!isMockRunning) return;
        
        const timestamp = new Date().toLocaleTimeString();
        
        Object.keys(mockTemplates).forEach(paneIndex => {
            const templates = mockTemplates[paneIndex];
            const logLine = templates[step % templates.length];
            mockLogs[paneIndex] += `[${timestamp}] ${logLine}\n`;
        });
        step++;
    }, 3000);
}

function stopMockLogs() {
    if (mockInterval) {
        clearInterval(mockInterval);
        mockInterval = null;
    }
    mockActiveWorkdir = ROOT_DIR;
    initMockLogs();
}

// tmux コマンドのラッパーヘルパー
function runTmux(args, cwd = ROOT_DIR) {
    return new Promise((resolve) => {
        const env = { ...process.env };
        exec(`tmux ${args}`, { env, cwd }, (error, stdout, stderr) => {
            if (error) {
                resolve({ success: false, code: error.code, stdout, stderr });
            } else {
                resolve({ success: true, code: 0, stdout, stderr });
            }
        });
    });
}

// 1. セッションステータスの取得
app.get('/api/status', async (req, res) => {
    if (MOCK_MODE) {
        const panes = [0, 1, 2, 3, 4, 5].map(index => ({
            index,
            title: ['DS', 'BLADE', 'AG-1', 'AG-2', 'AG-3', 'WATCH'][index],
            active: isMockRunning
        }));
        return res.json({
            running: isMockRunning,
            session: SESSION_NAME,
            workdir: mockActiveWorkdir,
            panes
        });
    }

    const check = await runTmux(`has-session -t ${SESSION_NAME}`);
    if (!check.success) {
        return res.json({
            running: false,
            session: SESSION_NAME,
            workdir: ROOT_DIR,
            panes: []
        });
    }

    const panesCheck = await runTmux(`list-panes -t ${SESSION_NAME}:0 -F "#{pane_index}:#{pane_title}:#{pane_active}"`);
    if (!panesCheck.success) {
        return res.json({
            running: true,
            session: SESSION_NAME,
            workdir: ROOT_DIR,
            panes: []
        });
    }

    const panes = panesCheck.stdout.trim().split('\n').map(line => {
        const [index, title, active] = line.split(':');
        return {
            index: parseInt(index, 10),
            title: title || `Pane ${index}`,
            active: active === '1'
        };
    });

    res.json({
        running: true,
        session: SESSION_NAME,
        workdir: ROOT_DIR, // 本番モード時も本来はプロセス開始CWD等を取得する
        panes
    });
});

// 2. リポジトリ一覧の取得
app.get('/api/repositories', (req, res) => {
    const reposStr = process.env.DOUBLEEDGE_REPOSITORIES || '';
    const repositories = reposStr ? reposStr.split(',').map(p => p.trim()) : [];
    res.json({ repositories });
});

// 3. 全ペインのログをまとめて取得する (ポーリング用)
app.get('/api/logs', async (req, res) => {
    const logs = {};
    if (MOCK_MODE) {
        if (!isMockRunning) {
            return res.json({ error: 'Session not running', logs: {} });
        }
        for (let i = 0; i <= 5; i++) {
            logs[i] = mockLogs[i] || '';
        }
        return res.json({ logs });
    }

    const check = await runTmux(`has-session -t ${SESSION_NAME}`);
    if (!check.success) {
        return res.json({ error: 'Session not running', logs: {} });
    }

    try {
        const promises = [];
        for (let i = 0; i <= 5; i++) {
            promises.push(runTmux(`capture-pane -t ${SESSION_NAME}:0.${i} -p`));
        }
        const results = await Promise.all(promises);
        for (let i = 0; i <= 5; i++) {
            logs[i] = results[i].success ? results[i].stdout : '';
        }
        res.json({ logs });
    } catch (err) {
        console.error('Failed to capture logs:', err);
        res.status(500).json({ error: 'Failed to capture logs' });
    }
});

// 4. セッションの起動・停止
app.post('/api/control', async (req, res) => {
    const { action, workdir } = req.body;
    console.log(`[API Control] Received action: ${action}, workdir: ${workdir} (MOCK_MODE: ${MOCK_MODE})`);
    
    // 指定されたリポジトリパス。なければROOT_DIR
    const targetDir = workdir || ROOT_DIR;

    if (MOCK_MODE) {
        if (action === 'start') {
            if (isMockRunning) {
                return res.status(400).json({ error: 'Session already running' });
            }
            isMockRunning = true;
            startMockLogs(targetDir);
            console.log(`[API Control] Mock Session Started on: ${targetDir}`);
            return res.json({ message: 'Mock Session start initiated', workdir: targetDir });
        } else if (action === 'stop') {
            if (!isMockRunning) {
                return res.status(400).json({ error: 'Session not running' });
            }
            isMockRunning = false;
            stopMockLogs();
            console.log(`[API Control] Mock Session Stopped`);
            return res.json({ message: 'Mock Session stopped successfully' });
        } else {
            return res.status(400).json({ error: 'Invalid action' });
        }
    }

    if (action === 'start') {
        const check = await runTmux(`has-session -t ${SESSION_NAME}`, targetDir);
        if (check.success) {
            console.log(`[API Control] Start failed: Session ${SESSION_NAME} already running`);
            return res.status(400).json({ error: 'Session already running' });
        }

        try {
            console.log(`[API Control] Spawning setup-doubleedge.ps1 on ${targetDir}`);
            const ps = spawn('powershell.exe', [
                '-ExecutionPolicy', 'Bypass',
                '-File', path.join(ROOT_DIR, 'setup-doubleedge.ps1'),
                '-Session', SESSION_NAME,
                '-WorkDir', targetDir
            ], {
                cwd: targetDir,
                detached: true,
                stdio: 'ignore'
            });

            ps.on('error', (err) => {
                console.error(`[API Control] Spawn process error:`, err);
            });

            ps.unref();
            console.log(`[API Control] Process spawned successfully.`);
            return res.json({ message: 'Session start initiated', workdir: targetDir });
        } catch (e) {
            console.error(`[API Control] Exception during spawn:`, e);
            return res.status(500).json({ error: 'Failed to launch session', details: e.message });
        }

    } else if (action === 'stop') {
        console.log(`[API Control] Stopping session ${SESSION_NAME}...`);
        const check = await runTmux(`has-session -t ${SESSION_NAME}`, targetDir);
        if (!check.success) {
            console.log(`[API Control] Stop failed: Session not running`);
            return res.status(400).json({ error: 'Session not running' });
        }

        exec(`powershell.exe -ExecutionPolicy Bypass -File "${path.join(ROOT_DIR, 'setup-doubleedge.ps1')}" -Kill`, { cwd: targetDir }, (error, stdout, stderr) => {
            if (error) {
                console.error(`[API Control] Stop error:`, stderr);
                return res.status(500).json({ error: 'Failed to stop session', details: stderr });
            }
            console.log(`[API Control] Session stopped successfully.`);
            res.json({ message: 'Session stopped successfully', output: stdout });
        });

    } else {
        console.log(`[API Control] Invalid action: ${action}`);
        res.status(400).json({ error: 'Invalid action' });
    }
});

// 5. 特定のペインへの指示の送信 (send-keys)
app.post('/api/input', async (req, res) => {
    const { pane, text } = req.body;
    const paneIndex = parseInt(pane, 10);
    console.log(`[API Input] Received input for pane: ${paneIndex}, text: "${text}" (MOCK_MODE: ${MOCK_MODE})`);

    if (isNaN(paneIndex) || paneIndex < 0 || paneIndex > 5) {
        return res.status(400).json({ error: 'Invalid pane index' });
    }
    if (!text || text.trim() === '') {
        return res.status(400).json({ error: 'Empty input text' });
    }

    if (MOCK_MODE) {
        if (!isMockRunning) {
            return res.status(400).json({ error: 'Session not running' });
        }
        // ユーザー入力を該当ペインのモックログに反映させる
        const timestamp = new Date().toLocaleTimeString();
        mockLogs[paneIndex] += `[${timestamp}] [User Input]: ${text}\n`;
        
        // Cline 割り込みのシミュレート：自動で日本語で肯定的なモック返答を流す
        setTimeout(() => {
            if (isMockRunning) {
                const replyTimestamp = new Date().toLocaleTimeString();
                let mockResponse = '';
                if (paneIndex === 0) {
                    mockResponse = `[DS] [ユーザーからの割り込み指示受信]: "${text}"\n[DS] 了解しました。指示内容に基づき、タスクを再構成して実行します。\n`;
                } else {
                    mockResponse = `[Pane ${paneIndex}] [割り込み指示受信]: "${text}" を処理中...\n`;
                }
                mockLogs[paneIndex] += `[${replyTimestamp}] ${mockResponse}`;
            }
        }, 1500);

        return res.json({ message: 'Mock input accepted and processed' });
    }

    const check = await runTmux(`has-session -t ${SESSION_NAME}`);
    if (!check.success) {
        return res.status(400).json({ error: 'Session not running' });
    }

    // Windows PowerShell経由で tmux send-keys を実行
    // 改行を含まずに送信し、最後に Enter を送信
    const sendCommand = `send-keys -t ${SESSION_NAME}:0.${paneIndex} "${text.replace(/"/g, '\\"')}" Enter`;
    const sendResult = await runTmux(sendCommand);
    
    if (sendResult.success) {
        console.log(`[API Input] Successfully sent keys to pane ${paneIndex}.`);
        res.json({ message: 'Input sent successfully' });
    } else {
        console.error(`[API Input] Failed to send keys to pane ${paneIndex}:`, sendResult.stderr);
        res.status(500).json({ error: 'Failed to send input to session', details: sendResult.stderr });
    }
});

// サーバー起動
app.listen(PORT, '127.0.0.1', () => {
    console.log(`DoubleEdge Agent API listening on port ${PORT} (MOCK_MODE: ${MOCK_MODE})`);
    console.log(`Root workspace directory: ${ROOT_DIR}`);
});
