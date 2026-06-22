# 02-impl-mode — 実装モード

## 起動条件

Human が実装・コード生成・ファイル作成を依頼した場合に適用。

## エージェント構成（全pane稼働）

```
pane 0: DS（タスク分解・コントロール）
pane 1: BLADE（整合・結合・却下）
pane 2: AG-1 Implementer（速度優先実装）
pane 3: AG-2 Auditor（GOZEN式監査）
pane 4: AG-3 Alternative（別アプローチ）
```

## タスク分解ルール

Human の要求を以下の観点で3つに分解して各AGに割り振る：

| pane | ロール | 割り振るサブタスク |
|------|--------|------------------|
| AG-1 | Implementer | 最速で動くコアロジックの実装 |
| AG-2 | Auditor | セキュリティ・エラーハンドリング・エッジケースの検証 |
| AG-3 | Alternative | 異なるアプローチまたはAG-1の改良案 |

分解が難しい場合は「全員が同じタスクを異なる視点で実装」とする。

## 並列発火フロー

### Step 1: AG×3 並列発火

```bash
# AG-1: Implementer
tmux send-keys -t doubleedge:0.2 \
  "[IMPL/Implementer] <サブタスク1>。速度と動作優先で実装せよ。" Enter

# AG-2: Auditor
tmux send-keys -t doubleedge:0.3 \
  "[IMPL/Auditor] <サブタスク2>。セキュリティ・エッジケースを重視せよ。" Enter

# AG-3: Alternative
tmux send-keys -t doubleedge:0.4 \
  "[IMPL/Alternative] <サブタスク3>。AG-1とは異なるアプローチで実装せよ。" Enter
```

3つを連続して発火する（並列実行が目的）。

### Step 2: 完了待ち

各paneを最大5分ポーリングして完了を確認：

```bash
# 完了確認ループ（疑似コード）
for pane in 2 3 4:
  wait for "> " prompt OR timeout 300s
  collect output
```

タイムアウトしたpaneは `TIMEOUT` フラグを立てて BLADE に PARTIAL として渡す。

### Step 3: BLADE に整合チェックを依頼

```bash
AG1_SUMMARY="<AG-1出力の要約（300字以内）>"
AG2_SUMMARY="<AG-2出力の要約（300字以内）>"
AG3_SUMMARY="<AG-3出力の要約（300字以内）>"

tmux send-keys -t doubleedge:0.1 \
  "[BLADE] integrate: AG-1=${AG1_SUMMARY} AG-2=${AG2_SUMMARY} AG-3=${AG3_SUMMARY}" Enter
```

### Step 4: BLADE 判定の処理

```
ACCEPT        → 全AG出力を結合してHumanに返す
PARTIAL:<N>   → 採用paneの出力のみ使用
REJECT:<理由> → DSがタスクを再分解してAG×3に再投入（最大2回まで）
```

REJECT が2回続いた場合はDSが自力で回答するか、Humanに判断を委ねる。

## 出力の結合

ACCEPT / PARTIAL の場合、DSが各paneの採用出力を以下の順で結合する：

1. AG-1の実装コード（コアロジック）
2. AG-2の指摘を反映した修正点
3. AG-3の代替案（参考として付記）

結合した成果物をHumanに提示する。
