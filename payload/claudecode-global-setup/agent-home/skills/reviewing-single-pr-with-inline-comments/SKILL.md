---
name: reviewing-single-pr-with-inline-comments
description: "PRレビュー・コメント・修正・マージ。 TRIGGER when: 差分確認、LGTM、まとめてレビュー、routine PR。 SKIP: PR無しローカル編集。"
invocation: reviewing-single-pr-with-inline-comments
type: orchestration
allowed-tools: Agent, Bash, Read, Grep, Write, Edit
---

# reviewing-single-pr-with-inline-comments

GitHub CLI (`gh`) を使ったPRレビュー操作。

## 前提条件

- `gh` インストール済み
- `gh auth login` で認証済み

## PR URLのパース

PR URL `https://github.com/OWNER/REPO/pull/NUMBER` から以下を抽出して使用：
- `OWNER`: リポジトリオーナー
- `REPO`: リポジトリ名
- `NUMBER`: PR番号

## 操作一覧

### 1. PR情報取得

```bash
gh pr view NUMBER --repo OWNER/REPO --json title,body,author,state,baseRefName,headRefName,url
```

### 2. 差分取得（行番号付き）

```bash
gh pr diff NUMBER --repo OWNER/REPO | awk '
/^@@/ {
  match($0, /-([0-9]+)/, old)
  match($0, /\+([0-9]+)/, new)
  old_line = old[1]
  new_line = new[1]
  print $0
  next
}
/^-/ { printf "L%-4d     | %s\n", old_line++, $0; next }
/^\+/ { printf "     R%-4d| %s\n", new_line++, $0; next }
/^ / { printf "L%-4d R%-4d| %s\n", old_line++, new_line++, $0; next }
{ print }
'
```

出力例：
```
@@ -163,17 +164,55 @@ func main() {
L163  R164 |            handler.SearchUsersByName,
L166      | -   if err := server.ServeStdio(...)
     R167 | +   transport := os.Getenv("TRANSPORT")
L168  R176 |
```

- `L数字`: LEFT(base)側の行番号 → インラインコメントで `side=LEFT` に使用
- `R数字`: RIGHT(head)側の行番号 → インラインコメントで `side=RIGHT` に使用

### 3. コメント取得

Issue Comments（PR全体へのコメント）:
```bash
gh api repos/OWNER/REPO/issues/NUMBER/comments --jq '.[] | {id, user: .user.login, created_at, body}'
```

Review Comments（コード行へのコメント）:
```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments --jq '.[] | {id, user: .user.login, path, line, created_at, body, in_reply_to_id}'
```

### 4. PRにコメント

```bash
gh pr comment NUMBER --repo OWNER/REPO --body "コメント内容"
```

### 5. インラインコメント（コード行指定）

まずhead commit SHAを取得：
```bash
gh api repos/OWNER/REPO/pulls/NUMBER --jq '.head.sha'
```

単一行コメント：
```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments \
  --method POST \
  -f body="コメント内容" \
  -f commit_id="COMMIT_SHA" \
  -f path="src/example.py" \
  -F line=15 \
  -f side=RIGHT
```

複数行コメント（10〜15行目）：
```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments \
  --method POST \
  -f body="コメント内容" \
  -f commit_id="COMMIT_SHA" \
  -f path="src/example.py" \
  -F line=15 \
  -f side=RIGHT \
  -F start_line=10 \
  -f start_side=RIGHT
```

### 6. コメントへ返信

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments/COMMENT_ID/replies \
  --method POST \
  -f body="返信内容"
```

`COMMENT_ID` はコメント取得で得た `id` を使用。

## 注意点

- `-F`（大文字）: 数値パラメータ（`line`、`start_line`）に使用。`-f` だと文字列になりAPIエラーになる
- `side`: `RIGHT`（追加行）または `LEFT`（削除行）
- インラインコメントの行番号は「2. 差分取得」の `L数字` / `R数字` プレフィックスから読み取る

---

## 自動フルレビューフロー

PR番号を渡すだけで worktree 作成→AIレビュー→テスト実行→LGTM投稿まで完結させるフロー。
PR番号が指定されていない場合は Phase 1 で一覧を出してユーザーに選ばせる。

**外部影響の注意**: 本フローは GitHub へコメント投稿・レビュー判定（approve / request-changes）を行う。これらは外部に公開される操作のため、Phase 8 の判定ロジックを満たした時のみ自動投稿する。判定を満たさない不確実なケースでは投稿せずユーザーに報告する。

**LGTM投稿条件**: AIレビューで Critical 指摘なし、かつ全テスト（lint・ユニット・E2E）通過。

### Phase 1: PR選択（番号未指定時のみ）

```bash
gh pr list \
  --state open \
  --limit 50 \
  --json number,title,author,createdAt,headRefName,reviewDecision
```

取得結果を以下の形式でユーザーに提示する（`No.` は 1 始まりの連番）:

```
| No. | PR #  | タイトル                    | 作成者  | ブランチ         | レビュー状態      | 作成日     |
|-----|-------|-----------------------------|---------|-----------------|-------------------|------------|
| 1   | #12   | ログイン画面を修正          | alice   | fix/login-form  | レビュー待ち | 2026-05-05 |
| 2   | #10   | ダッシュボード実装          | bob     | feat/dashboard  | 修正依頼     | 2026-05-03 |
```

- `reviewDecision` の表示: `APPROVED` → `承認済み` / `CHANGES_REQUESTED` → `修正依頼` / `REVIEW_REQUIRED` → `レビュー待ち` / null → `-`
- PRが0件の場合は「オープンなPRはありません」と伝えて終了

AskUserQuestion で選択を問いかける:
- **question**: 「レビューする PR の No. を選んでください」
- **options**: 一覧の各PRをオプションとして提示（ラベル: `No.1 — #12 ログイン画面を修正`）

選択された No. から GitHub PR番号（`number`）を取り出し、Phase 2 に進む。

### Phase 2: PR情報取得

```bash
gh pr view NUMBER --repo OWNER/REPO \
  --json title,body,headRefName,headRefOid,baseRefName,author,files

gh pr diff NUMBER --repo OWNER/REPO   # AIレビュー用差分テキスト
```

取得する情報:
- `headRefName` — worktree に checkout するブランチ名
- `headRefOid` — インラインコメント投稿に必要な commit SHA
- `files` — 変更ファイル一覧（レビュー優先度判定に使用）

### Phase 3: git worktree セットアップ

```bash
WORKTREE="$HOME/Projects/oradora-battle-base-pr-NUMBER"
PROJECT="$HOME/Projects/oradora-battle-base"

# 既存 worktree があれば削除してから再作成
git -C "$PROJECT" worktree remove "$WORKTREE" --force 2>/dev/null || true

git -C "$PROJECT" fetch origin HEADBRANCH
git -C "$PROJECT" worktree add "$WORKTREE" --checkout "origin/HEADBRANCH"
```

### Phase 4: 環境準備

```bash
# 環境変数ファイル（gitignore済みのため worktree に含まれない）
cp "$PROJECT/backend/.env"         "$WORKTREE/backend/.env"
cp "$PROJECT/frontend/.env.local"  "$WORKTREE/frontend/.env.local"

# フロントエンド依存関係
cd "$WORKTREE/frontend" && npm ci --silent

# バックエンド仮想環境
cd "$WORKTREE/backend"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt -q
```

### Phase 5: AIコードレビュー

レビュー判定は `reviewing-against-rules` スキルの手順に従い code-reviewer サブエージェントに委任する（観点の正本は `~/.claude/rules/scoped/review-checklist/code/common/rule.md`。メインが観点を書き写して自己レビューすることを禁止する）。判定結果の重要度定義・記録フォーマット・投稿処理の詳細は references/review-checklist.md を参照。

### Phase 6: テスト実行

```bash
cd "$WORKTREE"

# lint
frontend/node_modules/@biomejs/biome/bin/biome check frontend/src
backend/.venv/bin/ruff check backend/
backend/.venv/bin/mypy backend/app

# ユニットテスト
cd frontend && npx vitest run 2>&1 | tail -30
cd ../backend && .venv/bin/pytest tests/ -q --tb=short 2>&1 | tail -20
```

失敗した場合: エラー内容をキャプチャして Phase 8 のコメント本文に含める。

### Phase 7: E2Eテスト

スタック起動状態を確認して分岐する:

```bash
curl -s http://localhost:8000/api/health | grep -q '"status":"ok"'
BACKEND_OK=$?
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173 | grep -q "200"
FRONTEND_OK=$?
```

| バックエンド | フロントエンド | 対応 |
|-------------|---------------|------|
| 稼働中 | 稼働中 | そのまま E2E 実行 |
| 両方停止 | 両方停止 | `launching-battle-base-dev-servers` スキルでフルスタック起動後に E2E 実行 |
| 片方のみ | — | ユーザーに状況を報告して確認 |

```bash
# E2E 実行
cd "$WORKTREE/frontend"
npx playwright test 2>&1 | tail -40
```

スクリーンショット保存先: `~/agent-home/tools/MCP/playwright/pr-NUMBER-*.png`（cwd 不問、SessionEnd hook が 2 日経過で自動清掃）

### Phase 8: LGTM判定・コメント投稿

投稿前に ExitPlanMode でレビュー内容をユーザーに提示し、承認を取る。

#### 判定ロジック

```
LGTM = 重大な問題指摘数 == 0
     AND lint エラーなし
     AND FE ユニットテスト 全通過
     AND BE ユニットテスト 全通過
     AND E2E テスト 全通過
```

#### 投稿の 2 ステップ（重大な問題 / 警告がある場合）

Phase 5 で記録した内部記録形式の指摘リストを次の順で投稿する。**インラインを先に投稿してその HTML URL を取得し、総括コメント本文へ埋め込む** のが要点。

##### ステップ 1: インラインコメント投稿

`severity: critical` と `severity: warning` の各指摘について、`file` と `line` が特定できているものを 1 件ずつインライン投稿する。`file:line` が特定できない指摘はスキップ（総括のみで扱う）。

head commit SHA の取得は Phase 2 の `headRefOid` を流用する。

```bash
HEAD_SHA=$(jq -r '.headRefOid' <<< "$PR_INFO")

# 単一行のインライン投稿（重大な問題・警告 共通）
gh api repos/OWNER/REPO/pulls/NUMBER/comments \
  --method POST \
  -f body="$(cat path/to/inline-body.md)" \
  -f commit_id="$HEAD_SHA" \
  -f path="<相対パス>" \
  -F line=<行番号> \
  -f side=RIGHT \
  --jq '.html_url'
```

`--jq '.html_url'` で返るインラインコメントの URL を、各指摘の `inline_url` として保持する。総括コメントの本文組み立てで「該当行: [インラインコメント](<inline_url>)」リンクに埋める。

複数行に跨る指摘（`related_locations` がある場合）は代表 1 行のみインライン投稿し、総括コメント本文の表に他箇所を列挙する。

##### ステップ 2: 総括コメント投稿

全インライン投稿後、総括コメントを `--body-file` で投稿する。HEREDOC はメモリ `feedback-gh-body-textlint.md` の理由で避ける。本文は次の構造で組み立てる。

```bash
gh pr comment NUMBER --repo OWNER/REPO --body-file path/to/summary-body.md
```

総括コメント本文の構造:

```markdown
## レビュー結果: 修正依頼

### 重大な問題

<severity: critical 各 1 件を Phase 5 セクション B のテンプレで展開。
 末尾に該当行のインライン URL を貼る>

### 警告

<severity: warning 各 1 件を Phase 5 セクション C の 1 行要約で列挙。
 インライン URL を末尾に貼る>

### 提案

<severity: suggestion の指摘を 1 件 1 行で列挙（インラインなし）>

### テスト結果

- [OK/FAIL] FE lint (biome)
- [OK/FAIL] BE lint (ruff) + 型チェック (mypy)
- [OK/FAIL] FE ユニットテスト (vitest)
- [OK/FAIL] BE ユニットテスト (pytest)
- [OK/FAIL] E2E テスト (playwright)

### 補足

<docs カバレッジ未更新等の追加指摘>
```

##### ステップ 3: GitHub の Review API による request-changes

重大な問題がある場合のみ実行する。総括コメントの URL を本文に貼る形式とし、レビュー本体は短くする。

```bash
gh pr review NUMBER --repo OWNER/REPO --request-changes --body "詳細は総括コメントを参照: <総括コメントの URL>"
```

#### LGTM（approve）の場合

重大な問題と警告がともに 0 件のときは、インライン投稿はスキップして次を実行する。

```bash
gh pr review NUMBER --repo OWNER/REPO --approve --body-file path/to/lgtm-body.md
```

LGTM 本文:

```markdown
## LGTM

コードレビューおよびテストが全て通過しました。

### テスト結果
- [OK] FE lint (biome)
- [OK] BE lint (ruff) + 型チェック (mypy)
- [OK] FE ユニットテスト (vitest)
- [OK] BE ユニットテスト (pytest)
- [OK] E2E テスト (playwright)

### AI レビュー所見
<提案 指摘一覧、または「指摘なし」>
```

### Phase 9: クリーンアップ

**警告指摘がある場合**: worktree 削除は `fixing-review-findings` スキルが担う。この段階はスキップする。

**警告指摘がない場合**:

```bash
# Phase 7 で launching-battle-base-dev-servers を起動した場合のみ停止（既存の起動プロセスは残す）

git -C "$PROJECT" worktree remove "$WORKTREE" --force
```

worktree 削除が拒否された場合は `git worktree prune` でメタデータも整理する。

---

---

## 複数 PR モード

「PR を全部レビュー」「まとめてレビュー」「routine PR を処理」などの指示では、以下の複数 PR モードで動く。

### Step 1: PR 一覧取得・選択

```bash
gh pr list \
  --state open \
  --limit 50 \
  --json number,title,author,createdAt,headRefName,reviewDecision
```

`routine` ラベル付き PR を対象にする場合は `--label "routine"` を追加する。

LGTM 済み PR を判定して視覚的に区別し、対象 PR をユーザーに選択させる（「LGTM 済みも含めてすべてレビューする」の選択肢を含める）。選択結果を確認してから Step 2 に進む。

### Step 2: Reviewer サブエージェントを並列起動

選択した各 PR に対して **同時に** サブエージェントを起動する。

```
Task(general-purpose, "reviewing-single-pr-with-inline-comments スキルを使って PR #N をレビューせよ。
  Phase 1（PR選択）はスキップし、PR番号 N を直接使うこと。
  Phase 9（worktree削除）は実行しないこと——Fixer が引き継ぐ。
  最終的に以下の JSON 形式で結果を返せ:
  {pr_number, head_sha, worktree_path, p0_list, p1_list, p2_list, tests_passed}")
```

### Step 3: 結果集約・Fixer 起動判定

| 条件 | 処理 |
|---|---|
| `p0_list` に1件以上 | Fixer を起動しない。request-changes を投稿してスキップ |
| `p0_list` が空・`p1_list` に1件以上 | `fixing-review-findings` スキルを使う Fixer サブエージェントを並列起動 |
| `p0_list` も `p1_list` も空 | approve / LGTM コメントを即時投稿 |

### Step 4: routine PR の追加処理

`routine` ラベル付き PR を対象にしている場合は以下を追加で実施する。

- **古い PR の判定**: 同じルーティンの後続 PR が存在する場合は、古い PR をクローズ候補として `gh pr close <number> --comment "後続 PR で上書き済み"` を実行する
- **マージ**: レビュー安全 + テスト PASS の場合、AskUserQuestion でユーザーに「PR をマージしますか？」の確認を取ってからマージを実行する。`gh pr merge <number> --merge --delete-branch` を実行する

### Step 5: 完了報告

本ファイルの「完了報告」セクション（後述）の形式で報告する。

---

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | PR 番号が確定している |
| Phase 2 | PR の差分ファイル一覧と変更内容を取得済み |
| Phase 3 | 対象ファイルの全変更を読了している |
| Phase 4 | 関連ドキュメント・テストを確認済み |
| Phase 5 | 全チェックカテゴリの検査結果が記録されている |
| Phase 6 | レビュー結果が集計されている |
| Phase 7 | レビューコメントが下書きされている |
| Phase 8 | レビューが GitHub に投稿済み |
| Phase 9 | 結果サマリがユーザーに報告済み |
| **Goal** | 全 Phase 完了・重大な問題 0 件で approve 投稿済み、または修正依頼投稿済み |

## サブエージェント委任仕様

| 呼び出し箇所 | subagent_type | prompt 骨格 | 期待返却値 |
|---|---|---|---|
| Phase 5 コード検証 | code-reviewer | 対象ファイル実パス + 適用 rule 実パス（reviewing-against-rules で解決） | 基準別判定表 + 総合判定 + 指摘一覧 |
| routine PR Fixer | worker-sonnet | 指摘に基づく自動修正 | 修正ファイル一覧 |

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。
固有の検証行: 全 PR の処理結果（承認 / 修正依頼 / マージ件数）

---

## 予想を裏切る挙動

- 複数 PR を並列起動する際、独立した PR は必ず並列起動する（直列禁止）
- `routine` ラベルがない PR は routine モードの対象外
- E2E テストはローカルでのみ実行可能

---

### フロー全体の判定ツリー

```
Phase 5 (AIレビュー)
    │
    ├─ 重大な問題あり → インラインコメント投稿
    │                   ↓ Phase 6・7 も続けて実行（全体報告のため）
    │                   ↓ Phase 8: request-changes
    │
    └─ 重大な問題なし
            ↓
        Phase 6・7 テスト実行
            │
            ├─ 失敗あり → Phase 8: request-changes
            │
            └─ 全通過  → Phase 8: approve (LGTM ✅)
```
