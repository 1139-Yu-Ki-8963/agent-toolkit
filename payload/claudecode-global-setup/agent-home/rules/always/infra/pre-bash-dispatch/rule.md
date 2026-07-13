# Bash 実行前マルチディスパッチ（PRE-BASH-DISPATCH）

PreToolUse(Bash) で git / gh / mkdir コマンドを検出し、命名規則・textlint・コンフリクト解消ガード・公開可否レビューの各種 context を additionalContext に注入する。複数の検査を 1 スクリプトに集約したディスパッチャ。

## 対象コマンドと検査内容

| コマンドパターン | 検査内容 | 注入タグ | block/advisory |
|---|---|---|---|
| `git commit *` | docs 追加行の textlint | `[TEXTLINT-BLOCK]` | exit 2 で block |
| `git commit *` | 英語 type（`feat:` 等）のコミットメッセージ命名 | `[NAMING-BLOCK]` | exit 2 で block |
| `git commit *` | 命名規則リマインド・公開可否・機密ファイル検出 | `[NAMING]` `[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY-FULL]` `[PUBLISH-SAFETY]` | advisory（exit 0） |
| `git commit *` | staged 追加行の API トークン/秘密鍵らしき文字列検出 | `[SECRET-BLOCK]` | exit 2 で block |
| `git push *` | 未 push コミットの追加行の API トークン/秘密鍵らしき文字列検出 | `[SECRET-BLOCK]` | exit 2 で block |
| `git checkout *` / `git branch *` / `git switch *` | ブランチ命名規則リマインド | `[NAMING]` | advisory（exit 0） |
| `mkdir *` | ディレクトリ命名規則リマインド | `[NAMING]` | advisory（exit 0） |
| `git rebase *` / `git merge --no-ff *` / `git merge --squash *` | コンフリクト解消プロトコルの確認促進 | `[CONFLICT-RESOLUTION-GUARD]` | advisory（exit 0） |
| `gh pr create *` / `gh issue create *` | PR・issue 本文の textlint | `[TEXTLINT-BLOCK]` | exit 2 で block |
| `gh pr comment *` / `gh issue comment *` | コメント本文の textlint（通知のみ） | `[TEXTLINT-ADVISORY]` | advisory（exit 0） |

## 再帰防止

`git commit` 検査時は `CLAUDE_HOOK_DICT_RUNNING` 環境変数が設定されている場合にスキップする。

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[TEXTLINT-BLOCK]` | docs 追加行または PR/issue 本文に textlint 違反があれば exit 2 で block |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[NAMING-BLOCK]` | 英語 type コミットメッセージを exit 2 で block |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[SECRET-BLOCK]` | commit の staged 追加行、または push 対象の未 push コミット追加行に API トークン/秘密鍵らしき文字列があれば exit 2 で block |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[NAMING]` | 命名規則リマインドを advisory 注入（block なし） |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[PUBLISH-AUTHOR]` `[PUBLISH-SAFETY-FULL]` `[PUBLISH-SAFETY]` | コミット時の公開可否レビュー促進（block なし） |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[CONFLICT-RESOLUTION-GUARD]` | rebase / merge 前にプロトコル確認を促す（block なし） |
| PreToolUse(Bash) | `dispatch-pre-bash-checks.sh` | `[TEXTLINT-ADVISORY]` | コメント本文の textlint 違反を通知のみ（block なし） |

## 違反検知時の手順

### `[TEXTLINT-BLOCK]` 受信（git commit）

1. additionalContext に列挙された違反行・ルール名を確認する
2. 対象ファイルの該当行を `~/agent-home/tools/linter/.textlintrc.json` のルールに沿って修正する
3. 既存行（diff に含まれない行）は対象外。追加・変更行のみ修正する
4. `git add` で修正をステージし直してから再度 `git commit` する

### `[TEXTLINT-BLOCK]` 受信（gh pr create / gh issue create）

1. additionalContext に列挙された違反箇所を確認する
2. `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` の違反時手順に従い PR/issue 本文を修正する（辞書に該当エントリがない新規語彙の場合のみ `adding-textlint-dictionary-terms` スキルを使う）
3. 修正後に改めて `gh pr create` / `gh issue create` を実行する

### `[NAMING-BLOCK]` 受信

1. コミットメッセージの英語 type（`feat:` / `fix:` / `docs:` 等）を日本語 prefix に変更する
2. 規約値の定義 `~/.claude/rules/always/naming/commit-branch/naming-values.txt` を Read し、prefix 対応表・subject ルールに従って修正する

### `[SECRET-BLOCK]` 受信（git commit / git push）

1. stderr に出力された検出件数・該当ファイル一覧を確認する（値そのものは出力されない）
2. 該当ファイルから API トークン・秘密鍵らしき文字列を除去する
3. commit 時: `git add` でステージし直してから再度 `git commit` する
4. push 時: `git log --branches --not --remotes --oneline` で対象コミットを特定し、`git rebase` 等で履歴から値を除去してから再度 `git push` する
5. 誤検知（テスト用ダミー値等）の場合も値は再出力せず、パターンに一致しない形に書き換える

### `[NAMING]` 受信（ブランチ）

- 形式: `<prefix>/<slug>`。prefix 一覧・slug ルールは `always/naming/commit-branch/naming-values.txt` を参照

### `[NAMING]` 受信（ディレクトリ）

- ケバブケース必須
- 予約名: `references/` / `scripts/` / `assets/` / `workflows/` / `shared_scripts/`

### `[CONFLICT-RESOLUTION-GUARD]` 受信

1. コンフリクト解消プロトコルの Step 1（事前影響分析）と Step 2（ユーザーへの報告・承認）が完了しているか確認する
2. 完了済みであればそのままコマンドを実行する
3. 未完了であれば Step 1 から着手する

### `[PUBLISH-AUTHOR]` / `[PUBLISH-SAFETY-FULL]` / `[PUBLISH-SAFETY]` 受信

1. `~/agent-home/skills/reviewing-public-readiness/SKILL.md` の手順に従い公開可否を確認する
2. `[PUBLISH-SAFETY]` が機密ファイル名を列挙している場合は CRITICAL 観点を優先して確認する

### `[TEXTLINT-ADVISORY]` 受信（gh pr comment / gh issue comment）

会話文のため block しない。気になる場合のみ prh 推奨語へ置換する。

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: ディスパッチャ本体は枠組みであり、値の委譲は個別規約（commit-branch / text-dictionary）側の受け口が担う

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## 関連

- `~/agent-home/tools/linter/.textlintrc.json` — docs textlint 設定
- `~/agent-home/tools/linter/.textlintrc.pr.json` — PR/issue/comment textlint 設定
- `~/agent-home/skills/reviewing-public-readiness/SKILL.md` — 公開可否レビュー手順
- `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` — 置き換え辞書の定義・違反時の自己完結修正手順
- `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` — 置き換え辞書（prh.yml）の定義とプロジェクト委譲受け口
