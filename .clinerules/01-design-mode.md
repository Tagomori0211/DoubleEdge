# 01-design-mode — 設計モード

## 起動条件

Human が設計・構成・ADR・アーキテクチャについて話している場合に適用。

## エージェント構成

```
pane 0: DS（司令塔）
pane 2: AG-1（A: 実装者ロール）
pane 3: AG-2（B: 監査者ロール）
pane 1: BLADE（fallback 裁定専用）
```

AG-3（pane 4）は設計モードでは待機。

## 検証ループフロー

### Step 1: 初期提案

```bash
# AG-1（実装者）に設計提案を依頼
tmux send-keys -t doubleedge:0.2 \
  "[DESIGN/A] 以下のタスクに対する設計を提案せよ: <タスク内容>" Enter
```

### Step 2: 反論

AG-1の出力を取得後、AG-2（監査者）に渡す：

```bash
# AG-1出力取得
A_OUTPUT=$(tmux capture-pane -t doubleedge:0.2 -p -S -100)

# AG-2（監査者）に反論を依頼
tmux send-keys -t doubleedge:0.3 \
  "[DESIGN/B] 以下の設計提案に対して問題点・リスクを指摘せよ: <AG-1出力の要約>" Enter
```

### Step 3: 不一致カウントと再提示

```
不一致カウント < 3:
  → DSがAの提案にBの指摘を反映させて再提示
  → Step 1 に戻る（カウント+1）

不一致カウント == 3:
  → BLADEに fallback 裁定を依頼（Step 4へ）

一致検出（Bが「LGTM」「問題なし」「同意」を含む）:
  → 即採用、Humanに返答
```

### Step 4: fallback 裁定（不一致3回到達時）

```bash
tmux send-keys -t doubleedge:0.1 \
  "[BLADE] fallback: AG-A=<最終A提案の要約> AG-B=<最終B反論の要約> disagreement_count=3" Enter
```

BLADEの返答（`ACCEPT` / `PARTIAL:N` / `REJECT:reason`）をDSが受け取り最終回答とする。

## 不一致の判定基準

AG-2の出力に以下が含まれる場合を「不一致」とカウント：
- 「問題」「リスク」「懸念」「不適切」「欠陥」「考慮不足」
- "issue" / "risk" / "concern" / "flaw" / "problem"

AG-2の出力に以下が含まれる場合を「一致」とみなす：
- 「同意」「問題なし」「LGTM」「承認」「妥当」
- "agree" / "LGTM" / "approved" / "looks good"
