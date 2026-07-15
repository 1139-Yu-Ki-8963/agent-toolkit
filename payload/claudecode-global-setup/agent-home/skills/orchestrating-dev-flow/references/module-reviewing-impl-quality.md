# reviewing-impl-quality（orchestrating-dev-flow 内部モジュール）

## 実装品質レビュー（3 並列）

コミット前に実装コードとテストコードの品質を、コード品質・テスト品質・セキュリティ/パフォーマンスの 3 観点から並列審査する。

テストファイルを staged していない場合、テスト品質エージェントは「対象テストなし」として PASS を返す。コード品質・セキュリティ/パフォーマンスの 2 エージェントは常に実装ファイルを審査する。

プロジェクト固有コンテキストは次の 2 ファイルから注入する（どちらも存在しない場合は汎用モードで動作する）:

- `.claude/rules/always/project-context/flow-values.yml` — `review_agents.impl_quality.*`（3 観点のレビュアー定義パス）
- `.claude/rules/always/project-context/layers.yml` — `layers[*].{name,src}` で実装ファイルの帰属レイヤーを判定

---

## 前提: コンテキスト読み込み

着手前に以下を Read する（存在しない場合は当該設定をスキップ）。

1. `.claude/rules/always/project-context/flow-values.yml` を Read し `review_agents.impl_quality.{code,test,security}` の各パスを取得する
2. `.claude/rules/always/project-context/layers.yml` を Read し各レイヤーの `src` パターンを取得する

## Step 1: 対象ファイルを確認

```bash
git diff --name-only --cached
```

staged ファイルを実装ファイルとテストファイルに分類する。

**分類ロジック:**
- `layers.yml` の各レイヤーの `src` パターン配下に含まれるファイルを実装ファイルとして扱う
- テストファイルの判定はファイル名パターン（`*.test.*`・`*.spec.*`・`tests/` 配下等）で行う
- `layers.yml` が未設定の場合は staged 全ファイルを実装ファイルとして扱う

以降のエージェントに渡す `<STAGED_IMPL_FILES>` と `<STAGED_TEST_FILES>` のリストを確定する。

---

## Step 2: 3 並列レビュー実行

以下の 3 エージェントを **同時起動** する（model: sonnet）。

各エージェントは `flow-values.yml` の `review_agents.impl_quality.*` で指定されたレビュアー定義ファイルを Read してチェックリストを取得する。定義ファイルが未設定の場合は括弧内の汎用観点を適用する。

```
Agent(
  subagent_type: "worker-sonnet",
  model: "sonnet",
  description: "コード品質レビュー",
  prompt: "
    リポジトリのルートで作業する。
    flow-values.yml の review_agents.impl_quality.code で指定されたレビュアー定義ファイルを Read し、
    そこに記載されたチェックリストと評価基準に従って <STAGED_IMPL_FILES> をレビューせよ。
    定義ファイルが未設定の場合は（可読性・命名・単一責任・重複排除・複雑度）の 5 観点で判定する。
    結果の冒頭に PASS または FAIL を明記する。
    FAIL の場合は指摘を番号付きリストで報告する（ファイル名と行番号を含める）。
    改善提案がある場合は SUGGESTION: <内容> 形式で追記する。
    コードは書かない。
  "
)

Agent(
  subagent_type: "worker-sonnet",
  model: "sonnet",
  description: "テスト品質レビュー",
  prompt: "
    リポジトリのルートで作業する。
    <STAGED_TEST_FILES> が空の場合は「対象テストなし」として PASS を返し終了する。
    flow-values.yml の review_agents.impl_quality.test で指定されたレビュアー定義ファイルを Read し、
    そこに記載されたチェックリストと評価基準に従って <STAGED_TEST_FILES> をレビューせよ。
    定義ファイルが未設定の場合は（テスト網羅・アサーション強度・テスト独立性・命名）の 4 観点で判定する。
    結果の冒頭に PASS または FAIL を明記する。
    FAIL の場合は指摘を番号付きリストで報告する（テスト名と問題内容を含める）。
    改善提案がある場合は SUGGESTION: <内容> 形式で追記する。
    コードは書かない。
  "
)

Agent(
  subagent_type: "worker-sonnet",
  model: "sonnet",
  description: "セキュリティ・パフォーマンスレビュー",
  prompt: "
    リポジトリのルートで作業する。
    flow-values.yml の review_agents.impl_quality.security で指定されたレビュアー定義ファイルを Read し、
    そこに記載されたチェックリストと評価基準に従って <STAGED_IMPL_FILES> をレビューせよ。
    定義ファイルが未設定の場合は（入力バリデーション・認証/認可・機密情報漏洩・N+1 クエリ・不要な同期処理）の 5 観点で判定する。
    結果の冒頭に PASS または FAIL を明記する。
    FAIL の場合は指摘を番号付きリストで報告する。
    改善提案がある場合は SUGGESTION: <内容> 形式で追記する。
    コードは書かない。
  "
)
```

---

## Step 3: 結果統合・判定

3 エージェントの結果を収集して判定する。

| 条件 | 判定 |
|---|---|
| 全エージェント PASS | `✅ reviewing-impl-quality PASS` |
| 1 体以上 FAIL | `❌ reviewing-impl-quality FAIL` |

### PASS 時の処理

SUGGESTION が 1 件以上ある場合、改善提案リストを出力する（ブロッキングではない）:

```
改善提案（適用は任意）:
1. <提案内容>
2. ...
```

呼び出し元（Phase 5）は改善提案を確認し、適用可能なものを反映してからコミットへ進む。

### FAIL 時の処理

全エージェントの指摘を統合して番号付きリストで報告し、`❌ reviewing-impl-quality FAIL` を明示する。
Phase 5「リファクタリング」ステップに戻り指摘を修正して再呼び出しする。

---

## PASS マーカー touch

本モジュールの審査が PASS と判定された最終 step で、必ず次の PASS マーカーを touch する。

```sh
. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"
_marker="$(marker_path "$(pwd)" "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}}" module-reviewing-impl-quality.pass)"
touch "$_marker"
```

このマーカーは `check-review-gate.sh`（本スキル同梱のグローバル hook。`git push` / `gh pr create` 時に発火）が存在確認するためのもの。24h より古いマーカーは無効になり、再 PASS が必要になる。マーカー配置先規約は `~/.claude/rules/always/placement/file-guard/rule.md` を参照。

---

## 予想を裏切る挙動

- テストファイルが staged になければテスト品質エージェントは「対象テストなし」として自動 PASS を返すが、コード品質・セキュリティの 2 エージェントは常に実装ファイルを審査するため SKIP はできない
- `layers.yml` が未設定でも動作する。staged 全ファイルが実装ファイルとして扱われる
- PASS 判定後にマーカーを touch しないと、プロジェクト側の hook 設定によっては次の `git commit` が `[REVIEWING-GATE-BLOCK]` で block される

## エージェント定義ファイルの配置（プロジェクト側の責務）

レビュアー定義ファイルはプロジェクト側に配置し、`flow-values.yml` でパスを指定する。

```yaml
# .claude/rules/always/project-context/flow-values.yml
review_agents:
  impl_quality:
    code:     .claude/rules/always/project-context/agents/code-quality-reviewer.md
    test:     .claude/rules/always/project-context/agents/test-quality-reviewer.md
    security: .claude/rules/always/project-context/agents/security-performance-reviewer.md
```

各定義ファイルにはプロジェクト固有のチェックリスト・評価基準・重要度閾値を記載する。未設定の場合は括弧内の汎用観点が自動適用される。
