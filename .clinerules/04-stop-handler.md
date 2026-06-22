# 04-stop-handler — STOP_SIGNAL ハンドラ

## STOP_SIGNALの形式

watchdog（pane 5）から以下の形式で届く：

```
[DoubleEdge watchdog] STOP_SIGNAL:QUOTA pane=<N> tool=<name> pattern='<検出文字列>' Resets in Xh Ym Zs.
```

## DeepSeek(DS)のハンドラロジック

### 受信時の即時アクション

1. **進行中のループを一時停止する**（次の `send-keys` を止める）
2. **枯渇したpaneを特定する**（pane番号とツール名を記録）
3. **収集済みの出力を保存する**（`capture-pane -p` で現時点の出力を取得）

### pane別の対応

| 枯渇pane | 対応 |
|----------|------|
| AG-1（pane 2） | AG-2/AG-3 の出力のみで PARTIAL として BLADE に渡す |
| AG-2（pane 3） | 監査なしで AG-1/AG-3 の出力を BLADE に渡す（監査省略を明示） |
| AG-3（pane 4） | AG-1/AG-2 の出力のみで BLADE に渡す |
| BLADE（pane 1）| AG出力を DS が直接統合してHumanに返す（整合チェック省略） |
| AG-1+AG-2同時 | AG-3 のみで継続 or Humanに判断を委ねる |

### BLADEへの通知（AG枯渇時）

```bash
tmux send-keys -t doubleedge:0.1 \
  "[BLADE] integrate: AG-1=<出力or'QUOTA_EXHAUSTED'> AG-2=<出力or'QUOTA_EXHAUSTED'> AG-3=<出力or'QUOTA_EXHAUSTED'> note=partial_due_to_quota" Enter
```

### Humanへの通知

枯渇が発生した場合、DSは以下の情報をHumanに提示する：

```
[DoubleEdge] QUOTA ALERT
  枯渇ツール: <ツール名>（pane <N>）
  検出パターン: <文字列>
  リセット予測: <Resets in ...>
  現在の状態: <継続中 / 一時停止 / 部分結果>
  推奨アクション: <リセット待ち / 他ツールで継続 / Human判断>
```

## STOP_SIGNALへの例外（継続可能なケース）

以下の場合はSTOPせず継続する：

- 枯渇したpaneがタスクのクリティカルパスでない
- 残り2つのAGで十分な出力が得られている
- BLADEが PARTIAL 判定で採用しないpaneが枯渇した

## リセット後の再開

Human から「再開」指示が来た場合：

1. 枯渇paneで `agy` または `claude` を再起動
2. 中断したタスクの要約を再送信
3. ループを再開する

```bash
# AG-2 再起動例
tmux send-keys -t doubleedge:0.3 "agy" Enter
sleep 3
tmux send-keys -t doubleedge:0.3 \
  "[ROLE: Auditor][再開] 前回の監査タスクを再開: <タスク要約>" Enter
```

## ログ

全 STOP_SIGNAL は `.doubleedge/logs/watchdog.log` に記録される。
DSは次回起動時にこのログを参照して前回の枯渇状況を把握できる。
