# DoubleEdge アーキテクチャ設計メモ

## 設計思想

### デュアルスタック戦略との接続

「盾（インフラ）× 剣（クリエイティブ）」という田籠の哲学を
エージェントループとして実装したもの。

- DS（DeepSeek V4 Pro）= 盾の指揮官。コスト安・オープンウェイト・コントロールプレーンに最適。
- AG×3（Antigravity CLI）= 剣の実行部隊。Gemini 3.5 Flash の並列速度を活用。
- BLADE（Claude Code）= 品質管理。prompt injection 耐性・整合判定専任。

### Project GOZEN から継承した敵対フレーム

同一モデル（Gemini 3.5 Flash）でもロール付与で敵対が成立する。
`[ROLE: Auditor]` を先頭に付与するだけでグループシンクを回避できることは
GOZEN（Claude海軍参謀 × Gemini陸軍参謀）の実験で確認済み。

### なぜ Cline CLI をベースにするか

- Apache 2.0 ライセンスでフォーク・改変・商用利用が可能
- `.clinerules` で全挙動をバージョン管理できる
- 30+ プロバイダー対応で DS（OpenAI互換 API）が使える
- `npm i -g cline` でどこでも再現できる

## コスト設計

| ツール | 料金モデル | 並列数 | リスク |
|--------|-----------|--------|--------|
| DS API | $0.435/$0.87 per 1M tok | 1（司令塔）| 低 |
| AG | Antigravity Pro サブスク | 3 | クォータ枯渇リスクあり |
| BLADE | Claude Code サブスク | 1 | session limit 5時間枠 |

AG の Pro プランでは 3 並列が現実的な上限。
5並列は Ultra プランを推奨。

## 既知の制約と回避策

### agy の stdout bug（非TTY環境）

`agy -p` をsubprocess/pipeで叩くと stdout が無音で drop される（issue #76）。
**回避**: tmux pane 内（TTY環境）で `agy` をインタラクティブに起動し、
`tmux send-keys ... Enter` でプロンプトを送る。transcript.jsonl の読み取り不要。

### Claude Code の programmatic input 制限

`tmux send-keys -t pane "text\n"` では Ink の raw mode により submit されない。
**回避**: `tmux send-keys -t pane "text" Enter`（Enter を別引数）で
キーストロークとして届く。subscription quota を消費するインタラクティブモードを維持。

### AG クォータ共有プール

Antigravity デスクトップ・CLI・SDK でクォータを共有。
**回避**: CLI 専用に使う。watchdog で枯渇を即検知してDSにSTOP通知。
Proプランでの5並列は危険。3並列が安全圏。

## バージョン履歴

- v0.1（2026-06-22）: 初期設計・setup-doubleedge.sh・.clinerules 骨格
