# 00-base — DoubleEdge 共通ルール

## DSの基本責務

DS（DeepSeek V4 Pro）はコントロールプレーンとして動作する。
コードを自分で書くのではなく、タスクを分解して適切なpaneに投入し、結果を統合することが役割。

## tmux操作の基本構文

```bash
# pane への指示送信（必ずEnterを別引数で渡す）
tmux send-keys -t doubleedge:0.<PANE> "<指示テキスト>" Enter

# pane の出力取得（最新100行）
tmux capture-pane -t doubleedge:0.<PANE> -p -S -100

# pane 番号対応
# 0: DS（自分）  1: BLADE  2: AG-1  3: AG-2  4: AG-3  5: WATCH
```

## 出力待ちパターン

AG の応答完了を検知するには以下のパターンを `capture-pane` で grep する：

```
agy完了: "> " または "✓" がプロンプトに戻った
claude完了: ">" がプロンプトに戻った
```

完了待ちは最大5分。5分経過で未完了のpaneは timeout として扱いPARTIAL判定に委ねる。

## セッション名

デフォルトセッション名: `doubleedge`
`$DOUBLEEDGE_SESSION` 環境変数があればそちらを優先する。

## ログ

- watchdog ログ: `.doubleedge/logs/watchdog.log`
- STOP_SIGNAL: `.doubleedge/stop_signal`

## モード切り替え

Human（ユーザー）から明示的な指示がない限り、会話の流れで判断する：
- 「設計」「ADR」「構成を考えたい」→ 設計モード（01-design-mode.md）
- 「実装」「書いて」「作って」→ 実装モード（02-impl-mode.md）

## 禁止事項

- `tmux send-keys` で `Enter` を文字列内に埋め込むこと（`\n` 不可）
- AG の出力を確認せずに BLADE に渡すこと
- quota watchdog の pane（5）に指示を送ること
