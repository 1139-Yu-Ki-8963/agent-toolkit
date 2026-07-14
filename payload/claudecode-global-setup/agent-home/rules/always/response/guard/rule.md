# 応答品質ガード（RESPONSE-GUARD）

Claude の応答品質を機械強制する 2 軸の規約。ユーザー操作依頼の禁止と先送り表現の禁止。

## 1. ユーザー操作依頼禁止（NO-DELEGATION）

Claude がユーザーに CLI コマンド実行・画面操作・Web 認証を依頼することを禁止する。Claude 自身のツールで完遂する。

### 禁止対象

- コマンド実行依頼（「実行してください」「打ってください」「コピペ」「`! <cmd>`」）
- 画面操作依頼（「Dashboard で設定してください」「管理画面で有効化してください」）
- 認証依頼（「ログインしてください」「OAuth 認証してください」）
- 対話必須コマンドの発行（`gh auth login` / `npm login` / `docker login` 等）

## 2. 先送り禁止（NO-DEFERRAL）

「別 PR で対応」「残課題」「次回対応」等の先送り表現を禁止する。当該作業を本 PR 内で完遂する。

### 禁止対象

- 「別 PR / 別 issue で対応・起票・分割・切り出し」
- 「別途 PR / issue」「次の PR」「新規 issue を起票」
- 「残課題」「残作業」「残タスク」
- 「将来課題」「今後の課題・対応」「後日対応」
- 「Phase 2 以降」「次回対応・実装・セッション」

### 例外

PR body テンプレートの `### 未実施・残課題` 見出しと、その直下のバレット値が「なし」「特になし」「<!-- ... -->」の場合は検出対象外。

## 3. セッション内の作業先送り禁止（NO-PREMATURE-DEFERRAL）

Claude が残作業を「別セッションで対応」「次回で対応」と先送りすることを禁止する。

### 禁止対象

1. ユーザーが明示的に「終わり」「ここまで」「また今度」と言っていないのに、作業を別セッションに先送りすること
2. Stop hook のブロックを「セッション終了」と解釈すること — ブロックは「まだ作業が残っている」の意味であり作業を継続する
3. 「まとめ」を出して終了ムードを作ること — 残作業がある状態での成果まとめ出力は先送りの前兆であり、残作業を実行する

### 判定基準（先送りしてよい条件）

ユーザーが「ここまで」「また今度」「別セッションで」と明示指示した場合、技術的に現セッションで実行不可能な場合、またはユーザーが離席を明示した場合のいずれかに限る。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-no-delegation-pre-bash.sh`（rules-bash-runner 経由） | `[NO-DELEGATION-BLOCK]` | 対話必須コマンドを exit 2 で block |
| PostToolUse(Write\|Edit\|MultiEdit) | `check-no-delegation-post-write.sh` | `[NO-DELEGATION]` | PR/issue body 内の依頼文を検出し warning 注入 |
| Stop | `check-no-delegation-stop.sh` | `[NO-DELEGATION]` | 最終応答に依頼文を検出したら decision:block で書き直し強制。同一セッション 3 回連続で自動解除 |
| PreToolUse(Bash) | `check-no-deferral-pre-bash.sh`（rules-bash-runner 経由） | `[NO-DEFERRAL-BLOCK]` | `gh pr/issue create/comment` の body に先送り表現を検出したら exit 2 で block |
| PostToolUse(Write\|Edit\|MultiEdit) | `check-no-deferral-post-write.sh` | `[NO-DEFERRAL]` | PR/issue body 風の md に先送り表現を検出し warning 注入 |
| Stop | `check-no-deferral-stop.sh` | `[NO-DEFERRAL-RESPONSE]` | 最終応答に先送り表現を検出したら decision:block。同一セッション 3 回連続で自動解除 |

## 違反検知時の手順

### `[NO-DELEGATION-BLOCK]` 受信

1. 対話必須コマンドの発行を中止する
2. token ベースの代替手段を使う（`RENDER_API_KEY` / `VERCEL_TOKEN` / `SUPABASE_ACCESS_TOKEN` / `gh` の token 認証等）
3. 代行不可（MFA / SSO / 物理デバイス必須）なら `[NO-DELEGATION-ABORT]` 形式で中止報告する

### `[NO-DELEGATION]` 受信（PostToolUse / Stop）

1. 依頼文を特定する
2. Claude 自身のツールで完遂する記述に書き換える
3. 代行不可なら `[NO-DELEGATION-ABORT]` 形式で中止報告する

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 応答品質はプロジェクトに依存しない普遍的な作業姿勢であり、受け口を設けない

### `[NO-DELEGATION-ABORT]` 形式

代行不可能な操作を検出した場合の中止報告テンプレート:

```
[NO-DELEGATION-ABORT]
操作: <何が必要か>
理由: <なぜ Claude では代行不可か（MFA / SSO / 物理デバイス等）>
代替案: <あれば記載>
```

### `[NO-DEFERRAL-BLOCK]` 受信

1. block された `gh` コマンドの body から先送り表現を特定する
2. 当該作業を本 PR 内で完遂する記述に書き換える
3. 物理的に不可能な場合のみ AskUserQuestion で (A) 代替案 / (B) タスク全体中止 の 2 択を提示する

### `[NO-DEFERRAL]` 受信（PostToolUse）

1. 検出されたファイルと行を確認する
2. 先送り表現を削除し、本 PR 内で完遂する記述に書き換える

### `[NO-DEFERRAL-RESPONSE]` 受信（Stop）

1. 最終応答内の先送り表現を特定する
2. 当該作業を本ターン内で完遂する応答に書き換える
3. 物理的に不可能な場合のみ AskUserQuestion で (A) 代替案 / (B) タスク全体中止 の 2 択を提示する

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。
