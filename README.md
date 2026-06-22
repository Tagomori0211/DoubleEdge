# DoubleEdge

tmux-based multi-agent orchestration loop.

DS（DeepSeek V4 Pro）をコントロールプレーンに、AG×3（Antigravity CLI）を並列実行エンジンに、Claude Code を整合・結合・却下レイヤーに据えた、GOZEN式敵対ロール付与によるグループシンク回避エージェントループ。

## コンセプト

```
盾（DS制御）× 剣（AG実行）= DoubleEdge
```

設計フェーズと実装フェーズを明示的に分離し、それぞれで異なるエージェント構成を使う。

## アーキテクチャ

```
tmux session: doubleedge
 pane 0  DS      DeepSeek V4 Pro   コントロールプレーン / .clinerules
 pane 1  BLADE   Claude Code        整合・結合・却下レイヤー（subscription quota）
 pane 2  AG-1    agy Implementer   実装者ロール（速度優先）
 pane 3  AG-2    agy Auditor        監査者ロール（GOZEN式敵対）
 pane 4  AG-3    agy Alternative   代替アプローチロール
 pane 5  WATCH   watchdog           quota grep（トークンコストゼロ）
```

### 設計モード

DS + AG（A:実装者 / B:監査者）の2者検証ループ。不一致3回で BLADE（Claude Code）が fallback 裁定を行う。

### 実装モード

DS がタスクを分解し AG×3 に並列投入。全 pane 完了後 BLADE が整合チェック・ACCEPT / PARTIAL / REJECT を判定。DS が最終統合して Human に返す。

## 必要コマンド

| コマンド | 用途 |
|----------|------|
| `cline` | DS コントロールプレーン |
| `agy` | Antigravity CLI（AG×3） |
| `claude` | Claude Code（BLADE） |
| `tmux` | セッション管理 |

## セットアップ

```bash
git clone https://github.com/Tagomori0211/doubleedge
cd doubleedge
chmod +x setup-doubleedge.sh
./setup-doubleedge.sh
```

## 使い方

```bash
./setup-doubleedge.sh              # 起動（デフォルトセッション名: doubleedge）
./setup-doubleedge.sh my-session   # セッション名指定
./setup-doubleedge.sh --kill       # セッション破棄
tmux attach-session -t doubleedge  # 再アタッチ
```

## ディレクトリ構成

```
doubleedge/
├── setup-doubleedge.sh       起動スクリプト
├── CLAUDE.md                 Claude Code 向けコンテキスト
├── README.md
├── .clinerules/
│   ├── 00-base.md            共通ルール・tmux操作定義
│   ├── 01-design-mode.md     設計モード（2者検証ループ）
│   ├── 02-impl-mode.md       実装モード（AG×3並列 + BLADE整合）
│   ├── 03-roles.md           AG ロール定義（GOZEN式）
│   └── 04-stop-handler.md    STOP_SIGNAL ハンドラ
├── .doubleedge/
│   ├── logs/                 watchdog ログ
│   └── stop_signal           quota 枯渇シグナルファイル
├── docs/
│   └── architecture.md       設計メモ
└── scripts/
    └── watchdog.sh           watchdog 本体（setup時に自動生成）
```

## クォータ管理

AG は Antigravity CLI Pro プラン。並列3展開で運用。watchdog（pane 5）が30秒ごとに全paneを監視し、クォータ枯渇文字列を検知したら DS に `STOP_SIGNAL` を送信する。

Claude Code は `claude`（インタラクティブモード）で起動し subscription quota を使用。`-p` フラグ不使用。

## ライセンス

MIT
