'use client';

import { useState, useEffect, useRef } from 'react';
import styles from './page.module.css';
const API_BASE = 'http://127.0.0.1:3001';

const PANE_METADATA = [
  { index: 0, title: 'DS (DeepSeek V4 Pro)', role: 'Control Plane / Cline', badge: 'DS' },
  { index: 1, title: 'BLADE (Claude Code)', role: 'Quality Gate / Integration', badge: 'Blade' },
  { index: 2, title: 'AG-1 (Implementer)', role: 'speed-first / Implementer', badge: 'AG-1' },
  { index: 3, title: 'AG-2 (Auditor)', role: 'security & edge-cases / Auditor', badge: 'AG-2' },
  { index: 4, title: 'AG-3 (Alternative)', role: 'different approach / Alternative', badge: 'AG-3' },
  { index: 5, title: 'WATCH (Watchdog)', role: 'quota watchdog', badge: 'Watch' }
];

export default function Home() {
  const [status, setStatus] = useState({ running: false, session: 'doubleedge', panes: [] });
  const [logs, setLogs] = useState({ 0: '', 1: '', 2: '', 3: '', 4: '', 5: '' });
  const [actionLoading, setActionLoading] = useState(false);
  const [repositories, setRepositories] = useState([]);
  const [selectedRepo, setSelectedRepo] = useState('');
  const [inputText, setInputText] = useState('');
  const [inputSending, setInputSending] = useState(false);
  const consoleRefs = useRef({});

  // 1. セッションステータスの取得（ポーリング）
  const fetchStatus = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/status`);
      if (res.ok) {
        const data = await res.json();
        setStatus(data);
        if (data.running && data.workdir) {
          setSelectedRepo(data.workdir);
        }
      }
    } catch (err) {
      console.error('Failed to fetch status:', err);
      setStatus({ running: false, session: 'doubleedge', panes: [] });
    }
  };

  // 1.1 リポジトリ一覧の取得
  const fetchRepositories = async () => {
    try {
      const res = await fetch(`${API_BASE}/api/repositories`);
      if (res.ok) {
        const data = await res.json();
        setRepositories(data.repositories || []);
        if (data.repositories && data.repositories.length > 0) {
          setSelectedRepo(data.repositories[0]);
        }
      }
    } catch (err) {
      console.error('Failed to fetch repositories:', err);
    }
  };

  useEffect(() => {
    console.log('Dashboard mounted, API_BASE:', API_BASE);
    fetchStatus();
    fetchRepositories();
    const interval = setInterval(fetchStatus, 3000);
    return () => clearInterval(interval);
  }, []);

  // 2. ログ取得（短時間ポーリングによる取得。同時接続数制限回避のため）
  const fetchLogs = async () => {
    if (!status.running) return;
    try {
      const res = await fetch(`${API_BASE}/api/logs`);
      if (res.ok) {
        const data = await res.json();
        if (data.logs) {
          setLogs(prev => {
            let changed = false;
            const nextLogs = { ...prev };
            Object.keys(data.logs).forEach(key => {
              if (prev[key] !== data.logs[key]) {
                nextLogs[key] = data.logs[key];
                changed = true;
              }
            });
            return changed ? nextLogs : prev;
          });
        }
      }
    } catch (err) {
      console.error('Failed to fetch logs:', err);
    }
  };

  useEffect(() => {
    if (!status.running) {
      setLogs({ 0: '', 1: '', 2: '', 3: '', 4: '', 5: '' });
      return;
    }

    fetchLogs();
    const interval = setInterval(fetchLogs, 1500); // 1.5秒ごとにログ取得
    return () => clearInterval(interval);
  }, [status.running]);

  // 3. ログの自動スクロール
  useEffect(() => {
    Object.keys(logs).forEach(paneIndex => {
      const el = consoleRefs.current[paneIndex];
      if (el) {
        el.scrollTop = el.scrollHeight;
      }
    });
  }, [logs]);

  // 4. セッションの起動・停止コントロール
  const handleControl = async (action) => {
    setActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/api/control`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, workdir: selectedRepo })
      });
      if (res.ok) {
        setTimeout(fetchStatus, 1500);
      } else {
        const err = await res.json();
        alert(`エラーが発生しました: ${err.error || '不明なエラー'}`);
      }
    } catch (err) {
      alert(`API接続エラー: ${err.message}`);
    } finally {
      setActionLoading(false);
    }
  };

  // 5. 特定のペインへの指示送信 (割り込み)
  const sendInput = async (paneIndex) => {
    if (!inputText.trim()) return;
    setInputSending(true);
    try {
      const res = await fetch(`${API_BASE}/api/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pane: paneIndex, text: inputText })
      });
      if (res.ok) {
        setInputText('');
      } else {
        const err = await res.json();
        alert(`送信に失敗しました: ${err.error || '不明なエラー'}`);
      }
    } catch (err) {
      alert(`API接続エラー: ${err.message}`);
    } finally {
      setInputSending(false);
    }
  };

  return (
    <main className={styles.container}>
      <header className={styles.header}>
        <div className={styles.titleArea}>
          <h1>DoubleEdge Workspace Dashboard</h1>
          <span className={styles.subtitle}>
            Session: <code>{status.session}</code> | Multi-Agent Orchestration Controller
          </span>
        </div>
        
        <div className={styles.controlArea}>
          <div className={styles.repoSelectorWrapper}>
            <label htmlFor="repo-select" className={styles.repoLabel}>Target Directory:</label>
            <select
              id="repo-select"
              className={styles.select}
              value={selectedRepo}
              onChange={(e) => setSelectedRepo(e.target.value)}
              disabled={status.running || actionLoading}
            >
              {repositories.length > 0 ? (
                repositories.map((repo, idx) => (
                  <option key={idx} value={repo}>
                    {repo.substring(repo.lastIndexOf('\\') + 1) || repo.substring(repo.lastIndexOf('/') + 1) || repo}
                  </option>
                ))
              ) : (
                <option value="">No Repositories Configured</option>
              )}
            </select>
          </div>

          <div className={styles.statusIndicator}>
            <span className={`${styles.statusDot} ${status.running ? styles.statusDotActive : styles.statusDotInactive}`} />
            <span>{status.running ? 'RUNNING' : 'STOPPED'}</span>
          </div>

          {!status.running ? (
            <button
              id="btn-session-start"
              className={`${styles.btn} ${styles.btnStart}`}
              onClick={() => handleControl('start')}
              disabled={actionLoading || !selectedRepo}
            >
              {actionLoading ? 'Initializing...' : 'Start Session'}
            </button>
          ) : (
            <button
              id="btn-session-stop"
              className={`${styles.btn} ${styles.btnStop}`}
              onClick={() => handleControl('stop')}
              disabled={actionLoading}
            >
              {actionLoading ? 'Terminating...' : 'Stop Session'}
            </button>
          )}
        </div>
      </header>

      <section className={styles.grid}>
        {PANE_METADATA.map(pane => {
          const isPaneActive = status.running;
          return (
            <div key={pane.index} className={`${styles.card} ${styles[`pane${pane.index}`]}`}>
              <div className={styles.cardHeader}>
                <div className={styles.cardTitle}>
                  <span>{pane.title}</span>
                </div>
                <span className={styles.cardBadge}>{pane.badge}</span>
              </div>
              
              {isPaneActive ? (
                <>
                  <div
                    ref={el => consoleRefs.current[pane.index] = el}
                    className={styles.console}
                  >
                    {logs[pane.index] || 'Connecting to stream...'}
                    <span className="terminal-cursor" />
                  </div>
                  {pane.index === 0 && (
                    <div className={styles.chatInputWrapper}>
                      <input
                        type="text"
                        placeholder="Cline (DS) に指示を入力して割り込み (Enterで送信)"
                        className={styles.chatInput}
                        value={inputText}
                        onChange={(e) => setInputText(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && !e.nativeEvent.isComposing) {
                            sendInput(pane.index);
                          }
                        }}
                        disabled={inputSending}
                      />
                      <button
                        className={styles.chatSendBtn}
                        onClick={() => sendInput(pane.index)}
                        disabled={inputSending || !inputText.trim()}
                      >
                        {inputSending ? '...' : '送信'}
                      </button>
                    </div>
                  )}
                </>
              ) : (
                <div className={styles.offlineMessage}>
                  <span className={styles.offlineIcon}>🔌</span>
                  <span>SESSION OFFLINE</span>
                  <span style={{ fontSize: '0.8rem', opacity: 0.7 }}>{pane.role}</span>
                </div>
              )}
            </div>
          );
        })}
      </section>

      <footer className={styles.footer}>
        DoubleEdge Dashboard — Empowered by DeepSeek V4 Pro, Claude Code & Antigravity (Gemini 3.5 Flash)
      </footer>
    </main>
  );
}
