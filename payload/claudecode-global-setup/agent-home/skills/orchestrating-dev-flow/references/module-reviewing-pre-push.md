# reviewing-pre-push（orchestrating-dev-flow 内部モジュール）

## push 前 統合レビューゲート

`git push` 直前に、ブランチ全体の品質を 1 agent に集約してレビューする。

プロジェクト固有コンテキストは次の 2 ファイルから注入する（どちらも存在しない場合は汎用モードで動作する）:

- `.claude/rules/always/project-context/flow-values.yml` — `pr.critical_globs`、`portal_dir`、`review_agents.pre_push`
- `.claude/rules/always/project-context/layers.yml` — `layers[*].{name,src}` で規模判定に使用

---

## 前提: コンテキスト読み込み

着手前に以下を Read する（存在しない場合は当該設定をスキップ）。

1. `.claude/rules/always/project-context/flow-values.yml` を Read し `pr.critical_globs`・`portal_dir`・`review_agents.pre_push` を取得する
2. `.claude/rules/always/project-context/layers.yml` を Read しレイヤー一覧と各 `src` パターンを取得する

## Step 1: ブランチ全体差分を確認

```bash
git diff origin/main...HEAD --name-only
git log origin/main..HEAD --oneline
```

`<BRANCH_DIFF>`（変更ファイル一覧）と `<COMMIT_LOG>`（コミット履歴）を確定する。
仕様書パスも `<SPEC_PATH>` として特定する。

## Step 2: 規模判定（並列数の決定）

`flow-values.yml` の `pr.critical_globs` パターンに `<BRANCH_DIFF>` のファイルが 1 つでも該当する場合は **3 並列**。それ以外は **単一 agent**。

**代替判定（`flow-values.yml` が未設定の場合）:**
`layers.yml` のレイヤー数が 2 以上かつ変更ファイルが複数レイヤーをまたがる場合は 3 並列。1 レイヤー内のみの変更は単一 agent。`layers.yml` も未設定の場合は単一 agent。

## Step 3-A: 単一 agent モード（非 critical）

`flow-values.yml` の `review_agents.pre_push` にパスが設定されていればそのファイルを Read してチェックリストを取得する。未設定の場合は「コード品質・テスト品質・セキュリティ・デザイン規約・仕様達成・CI・PR 品質」の 7 観点を汎用基準として使う。

```
Agent(
  subagent_type: "worker-sonnet",
  model: "sonnet",
  description: "push 前統合レビュー（単一）",
  prompt: "
    リポジトリのルートで作業する。
    flow-values.yml の review_agents.pre_push で指定されたレビュアー定義ファイルを Read し、
    そこに記載されたチェックリスト（コード品質 + テスト品質 + セキュリティ + デザイン規約
    + 仕様達成 + CI + PR 品質）に従って <BRANCH_DIFF> <COMMIT_LOG> <SPEC_PATH> を
    レビューせよ。
    定義ファイルが未設定の場合は上記 7 観点を汎用基準として判定する。
    結果の冒頭に PASS または FAIL を明記する。
    FAIL の場合は指摘を番号付きリストで報告する。
    改善提案は SUGGESTION: <内容> 形式で追記する。
    コードは書かない。
  "
)
```

## Step 3-B: 3 並列モード（critical）

レビュアー定義ファイルの 7 観点を 3 エージェントに分割して同時起動する。定義ファイルが未設定の場合は汎用 7 観点を分配する。

```
Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "コード品質 + セキュリティ レビュー",
  prompt: "<review_agents.pre_push のコード品質 + セキュリティセクション（または汎用観点）>
           対象: <BRANCH_DIFF> <COMMIT_LOG>
           結果の冒頭に PASS または FAIL を明記。FAIL は番号付きリストで報告。コードは書かない。")

Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "テスト品質 + CI 品質 レビュー",
  prompt: "<review_agents.pre_push のテスト品質 + CI セクション（または汎用観点）>
           対象: <BRANCH_DIFF> <COMMIT_LOG>
           結果の冒頭に PASS または FAIL を明記。FAIL は番号付きリストで報告。コードは書かない。")

Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "仕様達成 + デザイン規約 + PR 品質 レビュー",
  prompt: "<review_agents.pre_push の仕様達成 + デザイン規約 + PR 品質セクション（または汎用観点）>
           対象: <BRANCH_DIFF> <COMMIT_LOG> <SPEC_PATH>
           結果の冒頭に PASS または FAIL を明記。FAIL は番号付きリストで報告。コードは書かない。")
```

## Step 4: 結果統合・判定

| 条件 | 判定 |
|---|---|
| agent 全 PASS | `✅ reviewing-pre-push PASS` |
| 1 体以上 FAIL | `❌ reviewing-pre-push FAIL` |

### 再レビューの差分化

FAIL 後の再呼び出しでは、前回 FAIL 項目に紐づくファイルだけを agent に渡す。
保存先: `$CLAUDE_JOB_DIR/tmp/reviewing-pre-push-prev-failures.json`

```json
{ "failed_files": ["<path>"], "failed_items": ["<item-id>"] }
```

再呼び出し時は `prev-failures.json` を読み `failed_files` のみを agent prompt に渡す。ファイルが存在しない初回は全ファイルを渡す通常モードで動く。

### PASS 時

SUGGESTION があれば改善提案リストを出力する（ブロッキングではない）。
呼び出し元（Phase 8）は改善提案を確認し `git push` へ進む。

### FAIL 時

全 agent の指摘を統合して番号付きリストで報告し、`❌ reviewing-pre-push FAIL` を明示する。
Phase 8 の該当ステップに戻り指摘を修正して再呼び出しする（差分モード）。

---

## PASS マーカー touch

本モジュールの審査が PASS と判定された最終 step で、必ず次の PASS マーカーを touch する。

```sh
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
_marker="$(marker_path "$(pwd)" "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}}" module-reviewing-pre-push.pass)"
touch "$_marker"
```

このマーカーはプロジェクト側の `check-review-gate.sh` が `git push` 直前に存在確認するためのもの。マーカー配置先規約は `~/.claude/rules/always/placement/file-guard/rule.md` を参照。

---

## Step 5: finding JSONL 記録

Step 4 で FAIL（または warning 以上の指摘あり）と判定された場合に限り、各指摘 1 件ごとに記録する。PASS の自動承認指摘は記録しない（ノイズ削減）。

**出力先:** `flow-values.yml` の `portal_dir` + `/data/review-findings/<YYYY-MM-DD>.jsonl`（追記モード・1 行 1 finding）。`portal_dir` が未設定の場合は `project-portal/data/review-findings/` にフォールバックする。

```bash
# flow-values.yml から portal_dir を取得（Agent 内で Read して変数に展開する）
PORTAL_DIR="<flow-values.yml の portal_dir>"
FINDING_DIR="${PORTAL_DIR}/data/review-findings"
mkdir -p "$FINDING_DIR"

jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg agent "reviewing-pre-push" \
  --arg pr_or_branch "<pr_or_branch>" \
  --arg finding_type "<finding_type>" \
  --arg severity "<severity>" \
  --arg target_path "<target_path>" \
  --arg observation "<observation>" \
  --arg fix_proposal "<fix_proposal>" \
  '{ts:$ts,agent:$agent,pr_or_branch:$pr_or_branch,observation:$observation,
    target_path:$target_path,finding_type:$finding_type,fix_proposal:$fix_proposal,
    severity:$severity,promoted_to:null}' \
  >> "${FINDING_DIR}/$(date +%Y-%m-%d).jsonl"
```

- スキーマ: `{ts, agent, pr_or_branch, observation, target_path, finding_type, fix_proposal, severity, promoted_to:null}`
- `finding_type` はプロジェクトの正規化語彙から 1 つ選択する（新規は `other:<slug>`）
- `severity` が `suggestion` のみの指摘は記録されないため「指摘はあったが JSONL が空」は正常ケースとして発生する

---

## 除外観点（自動昇格済み・手動で消さない）

週次ルーティン `review-findings-promote-weekly` の Phase 6 が自動追記する。
ここに列挙された `finding_type` は機械検査側で検出済みのため、本モジュールのレビュー観点から除外する。

<!-- promoted-findings-start -->
<!-- promoted-findings-end -->

---

## 予想を裏切る挙動

- `pr.critical_globs` に 1 ファイルでも該当すれば 3 並列モードになり、単一ファイル修正でも並列コストが発生する
- FAIL 後の差分再レビューは `$CLAUDE_JOB_DIR/tmp/reviewing-pre-push-prev-failures.json` が別セッション起動時に存在しないと全件再レビューになる
- `flow-values.yml` が存在しないプロジェクトでも動作する。critical_globs なし・portal_dir なし・agent 定義なしの汎用モードで実行する

## エージェント定義ファイルの配置（プロジェクト側の責務）

レビュアー定義ファイルはプロジェクト側に配置し、`flow-values.yml` でパスを指定する。

```yaml
# .claude/rules/always/project-context/flow-values.yml
review_agents:
  pre_push: .claude/rules/always/project-context/agents/pre-push-reviewer.md
```

定義ファイルにはコード品質・テスト品質・セキュリティ・デザイン規約・仕様達成・CI・PR 品質の 7 観点のチェックリストを記載する。未設定の場合はこの汎用 7 観点が自動適用される。
