# DoubleEdge

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey.svg" alt="Platform: Linux">
  <img src="https://img.shields.io/badge/tmux-v3.0+-green.svg?logo=tmux&logoColor=white" alt="tmux">
  <img src="https://img.shields.io/badge/DeepSeek-V4%20Pro-blue?logo=deepseek&logoColor=white" alt="DeepSeek">
  <img src="https://img.shields.io/badge/Gemini-3.5%20Flash-orange?logo=google-gemini&logoColor=white" alt="Gemini">
  <img src="https://img.shields.io/badge/Claude-Code%20(BLADE)-purple?logo=anthropic&logoColor=white" alt="Claude">
</p>

**DoubleEdge** は、`tmux` を基盤としたマルチエージェント・オーケストレーション・ループです。

DS（DeepSeek V4 Pro）をコントロールプレーンに、AG×3（Antigravity CLI）を並列実行エンジンに、Claude Code を整合・結合・却下レイヤー（BLADE）に据え、GOZEN式敵対ロール付与によりグループシンク（集団思考の罠）を回避する強固な自律開発ループを実現します。

---

## 📌 コンセプト

> [!NOTE]
> **「両刃 of 剣 (DoubleEdge)」としての設計**
> DeepSeekによる指揮のもと、Antigravity（Gemini）並列ループが万が一想定外の動作をしたりエラーを起こしたりしても、堅牢な Claude Code がバックアップおよび最終チェック（整合・結合・却下）を担うことで、安全性と開発速度を極限まで両立させます。

---

## 🏗 アーキテクチャ

DoubleEdge は、単一の `tmux` セッション内で6つのペインを連携させて稼働します。

```
tmux session: doubleedge
 ├── pane 0 : DS (DeepSeek V4 Pro)   -> コントロールプレーン / 指揮・計画 (.clinerules)
 ├── pane 1 : BLADE (Claude Code)    -> 整合・結合・却下（品質管理・判定）
 ├── pane 2 : AG-1 (Implementer)     -> 実装者（速度・動くロジック優先）
 ├── pane 3 : AG-2 (Auditor)         -> 監査者（セキュリティ・エッジケース指摘）
 ├── pane 4 : AG-3 (Alternative)     -> 代替提案（異なるアプローチの模索）
 └── pane 5 : WATCH (Watchdog)       -> クォータ監視（トークンコストゼロのテキスト監視）
```

### エージェント連携フロー

```mermaid
graph TD
    Human([ユーザー / CLI]) --> DS[pane 0: DS / コントロールプレーン]
    DS -->|タスク分解・並列投入| AG_Group{並列実行部隊}
    
    subgraph Parallel Engines [pane 2-4: Antigravity CLI]
        AG_Group --> AG1[AG-1: Implementer]
        AG_Group --> AG2[AG-2: Auditor]
        AG_Group --> AG3[AG-3: Alternative]
    end

    AG1 -->|実装コード| BLADE[pane 1: BLADE / Claude Code]
    AG2 -->|指摘事項| BLADE
    AG3 -->|代替アプローチ| BLADE
    
    BLADE -->|整合性検証・マージ判定| DS
    DS -->|最終統合| Human

    %% クォータ監視
    WATCH[pane 5: WATCH / Watchdog] -.->|API制限を監視| Parallel Engines
    WATCH -.->|制限検知時に STOP_SIGNAL 送信| DS
```

### 動作モード

#### 1. 設計モード (Design Mode)
DS と AG（実装者 / 監査者）による2者検証ループを実行。議論が不一致のまま3回に達した場合、BLADE（Claude Code）が介入して最終裁定を下します。

#### 2. 実装モード (Implementation Mode)
DS がタスクをサブタスクに分解して AG×3 に並列投入。全ペインの処理完了後、BLADE がコードの整合性チェックおよびマージ可否（`ACCEPT` / `PARTIAL` / `REJECT`）を判定し、DS が最終統合を行います。

---

## 🛠 テックスタック

| コンポーネント | 技術・ツール | バージョン/プラン | 役割 |
| :--- | :--- | :--- | :--- |
| **Orchestration** | `tmux` | v3.0+ | マルチプロセス管理 / 画面分割 |
| **Control Plane** | `cline` (DeepSeek V4 Pro) | API / Web | 指揮・プランニング |
| **Execution Engines** | `agy` (Gemini 3.5 Flash) | Pro プラン | 役割分散した並列開発・レビュー |
| **Quality Gate** | `claude` (Claude Code) | Subscription | コード整合性チェック・最終合意 |
| **Watcher** | `bash` / `grep` | - | クォータ枯渇監視（Watchdog） |

---

## 🚀 セットアップ

### 前提条件

- **OS**: Ubuntu 20.04 LTS 以上 (推奨)
- **ツール**: `tmux`, `git`, `curl` がインストールされていること
- **各種CLI**: `cline`, `agy`, `claude` がグローバルにインストールされ、APIキーなどの初期設定が完了していること

### インストール手順

```bash
# リポジトリのクローン
git clone https://github.com/Tagomori0211/doubleedge
cd doubleedge

# 起動スクリプトへの実行権限付与
chmod +x setup-doubleedge.sh

# セットアップと起動
./setup-doubleedge.sh
```

---

## 📖 使い方

```bash
# デフォルト名 (doubleedge) でセッションを起動
./setup-doubleedge.sh

# 任意のセッション名で起動
./setup-doubleedge.sh custom-session

# 既存のセッションに再アタッチ
tmux attach-session -t doubleedge

# セッションを破棄 (終了)
./setup-doubleedge.sh --kill
```

---

## 📁 ディレクトリ構成

```
DoubleEdge/
├── setup-doubleedge.sh       # tmuxセッションの初期化・起動スクリプト
├── CLAUDE.md                 # Claude Code (BLADE) 向けのコンテキスト定義
├── README.md                 # 本ドキュメント
├── .clinerules/              # エージェント連携の動作ルール群
│   ├── 00-base.md            # 共通基本ルール・tmux操作定義
│   ├── 01-design-mode.md     # 設計モードのライフサイクル
│   ├── 02-impl-mode.md       # 実装モードのパラレル実行ライフサイクル
│   ├── 03-roles.md           # AGのエージェントロール定義（GOZEN式）
│   └── 04-stop-handler.md    # クォータ制限時の停止シグナルハンドラ
├── .doubleedge/              # 実行時の一時ファイル・シグナル管理
│   ├── logs/                 # watchdogのログ保存先
│   └── stop_signal           # クォータ枯渇時に配置されるトリガーファイル
├── docs/                     # ドキュメンテーション
│   └── architecture.md       # 設計詳細メモ
└── scripts/                  # 補助スクリプト
    └── watchdog.sh           # クォータ監視スクリプト（起動時に自動生成）
```

---

## ⏱ クォータ・コスト管理 (Watchdog)

DoubleEdge は、API クォータやトークン消費に配慮した自律セーフティ機能を備えています。

- **AG (Antigravity CLI)**:
  3つのペインで並列動作するため、クォータの消費速度が速くなります。そのため、`watchdog.sh` (pane 5) が30秒おきにログや出力を監視し、クォータ制限の兆候（APIエラーや枯渇を示す文字列）を検知すると、直ちに `.doubleedge/stop_signal` を生成して DS に `STOP_SIGNAL` を送ります。
- **Claude Code (BLADE)**:
  `claude` インタラクティブモードで動作し、サブスクリプション枠を最大限効率的に活用します。

---

## 🤝 コントリビューション

バグ報告や機能提案は、Issue または Pull Request にて歓迎いたします。
コントリビューションを行う際は、`.clinerules/` 内の連携規約に反しないようにご注意ください。

---

## ⚖️ ライセンス

このプロジェクトは [MIT License](LICENSE) のもとで公開されています。
