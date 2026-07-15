# reviewing-pre-impl（orchestrating-dev-flow 内部モジュール）

## 実装前 統合レビューゲート

仕様コミット直前に、設計書・モック・テスト計画の品質を 1 agent に集約してレビューする。

プロジェクト固有コンテキストは次の 2 ファイルから注入する（どちらも存在しない場合は汎用モードで動作する）:

- `.claude/rules/always/project-context/flow-values.yml` — `pr.critical_globs`、`portal_dir`、`review_agents.pre_impl`
- `.claude/rules/always/project-context/layers.yml` — `layers[*].{name,src,e2e}`

---

## 前提: コンテキスト読み込み

着手前に以下を Read する（存在しない場合は当該設定をスキップ）。

1. `.claude/rules/always/project-context/flow-values.yml` を Read し `pr.critical_globs`・`portal_dir`・`review_agents.pre_impl` を取得する
2. `.claude/rules/always/project-context/layers.yml` を Read し `e2e: true` が設定されているレイヤーの `src` パターンを取得する

## Step 1: 対象を確認

```bash
git diff --name-only --cached
```

staged ファイル（仕様書 / HTML モック / テスト計画）から `<SPEC_PATH>` と `<TEST_PLAN>` を確定する。

## Step 1.5: E2E 強制の独立判定

設計書を信用せず、`git diff --name-only --cached` の出力から決定論的に E2E spec 要件の要否を判定する。

**判定ロジック（優先順）:**

1. `layers.yml` の各レイヤーのうち `e2e: true` が設定されているレイヤーを列挙する
2. staged ファイルがそのレイヤーの `src` パターン配下にマッチすれば `MANDATE_E2E=1`
3. いずれにも該当しない、または `layers.yml` が存在しない / `e2e` フィールドがない場合は `MANDATE_E2E=0`

| 判定 | 後続処理 |
|---|---|
| `MANDATE_E2E=1` | Step 3 で起動する agent の prompt 末尾の `<E2E_MANDATORY_BLOCK>` を下記の `[E2E-MANDATORY]` 文言で置換する |
| `MANDATE_E2E=0` | `<E2E_MANDATORY_BLOCK>` を空文字に置換する（既存 4 観点のみで判定する） |

`<E2E_MANDATORY_BLOCK>` に差し込む文言:

```
[E2E-MANDATORY] 本変更は layers.yml で e2e: true に指定されたレイヤー（<layer.src>/**）を含む。
設計書（<SPEC_PATH>）の記述内容に関わらず、E2E spec（playwright）の存在と PASS を
必須要件として判定せよ。E2E spec ファイル名（既存 or 新規）が <SPEC_PATH> および <TEST_PLAN>
に列挙されていない場合は無条件 FAIL とする。
```

## Step 2: 規模判定（並列数の決定）

`flow-values.yml` の `pr.critical_globs` パターンに staged ファイルが 1 つでも該当する場合は **3 並列**。それ以外は **単一 agent**。

`flow-values.yml` が存在しない場合、または `pr.critical_globs` が未設定の場合は **単一 agent** で動作する。

## Step 3-A: 単一 agent モード（非 critical）

`flow-values.yml` の `review_agents.pre_impl` にパスが設定されていればそのファイルを Read してチェックリストを取得する。未設定の場合は「仕様完全性・UX・技術整合・テスト網羅」の 4 観点を汎用基準として使う。

```
Agent(
  subagent_type: "worker-sonnet",
  model: "sonnet",
  description: "実装前統合レビュー（単一）",
  prompt: "
    リポジトリのルートで作業する。
    flow-values.yml の review_agents.pre_impl で指定されたレビュアー定義ファイルを Read し、
    そこに記載されたチェックリスト（仕様完全性 + UX + 技術整合 + テスト網羅）に従って
    <SPEC_PATH> と <TEST_PLAN> をレビューせよ。
    定義ファイルが未設定の場合は上記 4 観点を汎用基準として判定する。
    結果の冒頭に PASS または FAIL を明記する。
    FAIL の場合は指摘を番号付きリストで報告する。
    改善提案は SUGGESTION: <内容> 形式で追記する。
    コードは書かない。
    <E2E_MANDATORY_BLOCK>
  "
)
```

## Step 3-B: 3 並列モード（critical）

レビュアー定義ファイルの 4 観点を 3 エージェントに分割して同時起動する。定義ファイルが未設定の場合は汎用 4 観点を各エージェントのセクションに分配する。

```
Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "仕様完全性 + UX レビュー",
  prompt: "<review_agents.pre_impl の仕様完全性 + UX セクション（または汎用観点）> ... <E2E_MANDATORY_BLOCK>")

Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "技術整合性レビュー",
  prompt: "<review_agents.pre_impl の技術整合セクション（または汎用観点）> ... <E2E_MANDATORY_BLOCK>")

Agent(subagent_type: "worker-sonnet", model: "sonnet", description: "テスト網羅性レビュー",
  prompt: "<review_agents.pre_impl のテスト網羅セクション（または汎用観点）> ... <E2E_MANDATORY_BLOCK>")
```

Step 1.5 の判定結果に応じて `<E2E_MANDATORY_BLOCK>` を置換する。特に「テスト網羅性」担当 agent には必ず注入する。

## Step 4: 結果統合・判定

| 条件 | 判定 |
|---|---|
| agent 全 PASS | `✅ reviewing-pre-impl PASS` |
| 1 体以上 FAIL | `❌ reviewing-pre-impl FAIL` |

### 再レビューの差分化

FAIL 後の再呼び出しでは、前回 FAIL 項目に紐づくファイルだけを agent に渡す。
保存先: `$CLAUDE_JOB_DIR/tmp/reviewing-pre-impl-prev-failures.json`

```json
{ "failed_files": ["<path>"], "failed_items": ["<item-id>"] }
```

再呼び出し時は `prev-failures.json` を読み、`failed_files` のみを agent prompt に渡す。ファイルが存在しない初回は全ファイルを渡す通常モードで動く。

### PASS 時

SUGGESTION があれば改善提案リストを出力する（ブロッキングではない）。
呼び出し元（Phase 4）は改善提案を確認し Phase 5 へ進む。

### FAIL 時

全 agent の指摘を統合して番号付きリストで報告し、`❌ reviewing-pre-impl FAIL` を明示する。
Phase 4-2 に戻り指摘を修正して再呼び出しする（差分モード）。

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
  --arg agent "reviewing-pre-impl" \
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

---

## 除外観点（自動昇格済み・手動で消さない）

週次ルーティン `review-findings-promote-weekly` の Phase 6 が自動追記する。
ここに列挙された `finding_type` は機械検査側で検出済みのため、本モジュールのレビュー観点から除外する。

<!-- promoted-findings-start -->
<!-- promoted-findings-end -->

---

## PASS マーカー touch

本モジュールの審査が PASS と判定された最終 step で、必ず次の PASS マーカーを touch する。

```sh
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
_marker="$(marker_path "$(pwd)" "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}}" module-reviewing-pre-impl.pass)"
touch "$_marker"
```

このマーカーは `check-review-gate.sh`（本スキル同梱のグローバル hook。`git push` / `gh pr create` 時に発火）が存在確認するためのもの。24h より古いマーカーは無効になり、再 PASS が必要になる。マーカー配置先規約は `~/.claude/rules/always/placement/file-guard/rule.md` を参照。

---

## 予想を裏切る挙動

- `layers.yml` に `e2e: true` を設定したレイヤーの `src` パスを含む変更では、Step 1.5 が設計書の記述を無視して E2E spec を強制する。設計書に「E2E 不要」と書いても FAIL になる
- FAIL 後の差分再レビューは `$CLAUDE_JOB_DIR/tmp/reviewing-pre-impl-prev-failures.json` が存在しない別セッションでは全件再レビューになる
- `flow-values.yml` が存在しないプロジェクトでも動作する。critical_globs なし・portal_dir なし・agent 定義なしの汎用モードで実行する

## エージェント定義ファイルの配置（プロジェクト側の責務）

レビュアー定義ファイルはプロジェクト側に配置し、`flow-values.yml` でパスを指定する。

```yaml
# .claude/rules/always/project-context/flow-values.yml
review_agents:
  pre_impl: .claude/rules/always/project-context/agents/pre-impl-reviewer.md
```

定義ファイルには仕様完全性・UX・技術整合・テスト網羅の 4 観点のチェックリストを記載する。未設定の場合はこの汎用 4 観点が自動適用される。
