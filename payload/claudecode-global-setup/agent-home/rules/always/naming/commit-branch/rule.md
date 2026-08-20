# コミット・ブランチ命名規約（COMMIT-BRANCH-NAMING）

コミットメッセージとブランチ名の命名規約。規約値の定義は同ディレクトリの `naming-values.txt`（非注入サイドカー）に置き、本ファイルは索引のみを持つ。

## 規約の要点

- コミット: `【<type>】<subject>`。日本語 prefix 必須・英語 type（`feat:` 等）禁止
- ブランチ: `<prefix>/<slug>`。prefix は feature/fix/docs/chore/refactor/release/hotfix、slug はケバブケース
- 規約値の全表（prefix 対応表・subject ルール・slug ルール）: `~/.claude/rules/always/naming/commit-branch/naming-values.txt`
- 作業手順の詳細（prefix 選択マトリクス・ファイル名・ディレクトリ名・git author 固定値）も naming-values.txt に含まれる

## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `always/infra/pre-bash-dispatch/dispatch-pre-bash-checks.sh` | `[NAMING-BLOCK]` | 英語 type コミットを exit 2 で block |
| PreToolUse(Bash) | 同上 | `[NAMING]` | commit / branch / mkdir 時に命名リマインドを advisory 注入 |
| PreToolUse(Bash) | `check-git-author-allowlist.sh` | `[GIT-AUTHOR-BLOCK]` | git commit の author name/email（明示指定・実効値いずれか）が白リストに不一致、または email が空の場合に exit 2 で block |
| PreToolUse(Bash) | `check-git-author-allowlist.sh` | `[GIT-AUTHOR-PUSH-BLOCK]` | git push で統合先とのマージベース以降の push 対象範囲に白リスト外 author のコミットが含まれる場合に exit 2 で block |

## 違反検知時の手順

`[NAMING-BLOCK]` / `[NAMING]` を受信したら `naming-values.txt` を Read し、対応表に従って命名を修正してから再実行する。

### `[GIT-AUTHOR-BLOCK]` 受信

明示指定（`-c user.name`/`-c user.email`）または実効 author（`~/.gitconfig` 等）が白リスト（name: `1139-Yu-Ki-8963` / email: `63326271+1139-Yu-Ki-8963@users.noreply.github.com`）と不一致。該当設定を白リストの値に修正してから再度 commit する。

### `[GIT-AUTHOR-PUSH-BLOCK]` 受信

push 対象範囲に白リスト外 author のコミットが含まれる。additionalContext に列挙されたコミットを `git rebase <親> --exec "git commit --amend --reset-author --no-edit"` で書き換えてから再度 push する。

## プロジェクト上書き

- 上書き可否: 委譲可（値のみ）
- 受け口: `<repo>/.claude/rules/always/naming/commit-branch/naming-values.txt`
- 優先順位: 受け口が存在すれば規約値はプロジェクト側を優先する。枠組み（英語 type 禁止・hook による強制・違反時手順）はグローバルが常に正

## 設計判断

設計判断の全文は同ディレクトリの `design-notes.txt` を参照（check-git-author-allowlist.sh・check-git-author-allowlist.test.sh の必要性・代替案・保守責任者・廃棄条件を含む。非注入サイドカー）。

## 関連

- `always/review-checklist/meaningful-key-naming/rule.md` — ドキュメント内の行識別子（ID 命名）。対象が異なる
- 同ディレクトリ check-git-author-allowlist.sh — git author 白リスト検査 hook（PreToolUse）
- `always/naming/common-principles/rule.md` — 全サーフェス共通の命名意味論原則（本規約の上位規約）
