---
name: reviewing-against-rules
description: |
  レビューの単一入口。適用 rule を解決し、専門家に照合を委任する。
  TRIGGER when: 「レビューして」と成果物・差分を指定された時、他スキルのレビュー工程（PR レビュー Phase 5・開発フローのレビューゲート）から呼ばれた時、HTML・コードの完成判定時。
  SKIP: 設定資産（skills/rules/hooks/routines/subagents）のレビューは managing-agent-configs。調査報告の事実性検証は report-reviewer 直接委任。公開可否は reviewing-public-readiness。
invocation: reviewing-against-rules
type: orchestration
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# rules 照合レビューの単一入口

レビュー観点の正本は rules（`~/.claude/rules/scoped/` 配下の各 rule.md）にある。本スキルは「対象ファイル → 適用 rule の解決 → ドメイン別専門家への委任 → 判定回収」を定型化し、スキル・セッションごとに観点参照がばらける事故（参照切れ・観点省略・メイン自己レビュー）を防ぐ。

## 原則

1. **観点表を直接読まない**: レビュー観点は専門家サブエージェントが rule.md から読む。呼び出し側（メインセッション・他スキル）が観点を要約してプロンプトに書き写すことを禁止する（乖離の温床）
2. **メインの自己レビュー禁止**: 判定は必ず専門家サブエージェントが行う。生成役と検証役を分離する
3. **適用 rule は機械的に解決する**: scoped rule の `paths:` frontmatter が適用対象の宣言。手動でルールを選ばない

## 手順

1. **対象の確定**: レビュー対象ファイル一覧を確定する。PR・ブランチ差分なら `git diff --name-only` で取得する
2. **適用 rule と担当専門家の解決**: `scripts/resolve-applicable-rules.sh <file...>` を実行する。グローバル scoped rules とカレントリポジトリの受け口（`<repo>/.claude/rules/scoped/`）の両方から、paths にマッチする `<file, rule.md実パス, 専門家>` の組を全件得る（3列TSV）。**専門家の選択はファイル拡張子から推測しない**。担当は rule の配置フォルダから機械導出される: `review-checklist/<domain>/` 配下の rule は `<domain>-reviewer` の担当（統治規約: `~/.claude/rules/scoped/agent-config/review-checklist/rule.md`）。1 ファイルに複数 rule・複数専門家が該当する場合がある（例: `.tsx` は `code/common` と `code/ui` の両方、`.html` は `code/ui` と `document/html-output` の両方が該当しうる）
3. **専門家ごとにグルーピング**:
   - 3 列目（専門家）の値ごとに `<file, rule>` の組をグルーピングする
   - `(non-review)` の rule（review-checklist 外の scoped rule。dev-flow ゲート等）はレビュー照合の対象外。無視してよい
   - `rule` が `(none)` のファイルは、対象外と報告して終了（観点なしの LLM 裁量レビューをしない）
   - 設定資産（SKILL.md・rule.md・hook `.sh` 等）は本スキル対象外。`managing-agent-configs` に委譲
   - 複数専門家が必要な場合は並列起動する（1 メッセージで複数 Agent 呼び出し）
4. **構成の照合**: 対象ファイル一覧に「新規ディレクトリ内のファイル」または「リポジトリルート直下の新規ファイル」が含まれる場合、当該リポジトリの許可リスト（`<repo>/.claude/rules/always/placement/directory-structure/rule.md`。無ければグローバル `~/.claude/rules/always/placement/directory-structure/rule.md` の枠組み）と照合し、結果を「構成: 配置」行としてレビュー結果に必ず含める（mkdir 時の hook は advisory で block しないため、出来上がった構成の適合はレビューが最後の防衛線となる）
5. **委任**: 各専門家に、そのグループに属する `<file, rule>` の組を次の形で埋め込んで委任する。文脈依存語（「直前の」「例の」）は禁止
   - 対象ファイルの実パス一覧
   - 手順 2 で解決した rule.md の実パス一覧（そのファイルに適用される、当該専門家の担当分のみ。専門家がこれを Read する）
   - `## 調査チェックリスト` 見出し配下に「rule の全基準を確認し、基準ごとに PASS / FAIL / 対象外 + 証拠を返す」旨
   - 出力形式（専門家定義の出力形式に従う）と行数上限
6. **判定回収と後続**:
   - 同一ファイルに複数専門家の判定がある場合、手順 4 の構成照合も含めて全ての判定を統合してから合否を決める（1 つでも不合格なら全体を不合格として扱う）
   - 総合判定が「マージ不可 / 不合格」の場合: 修正を worker-sonnet に委任し（専門家は修正しない）、修正後に手順 5 を再実行する。最大 5 回、同一指摘の 2 回連続再発でユーザーへ差し戻す
   - 合格の場合: 判定・照合 rule 一覧・指摘の要約をユーザー（または呼び出し元スキル）へ返す

## 完了条件

- 対象ファイル全件について、適用 rule の解決結果（該当 rule またはレビュー対象外）が示されている
- 適用 rule があるファイルは専門家の総合判定（証拠付き）が回収されている
- 不合格→修正→再判定のループが収束（合格）またはユーザー差し戻しで終端している

## サブエージェント委任仕様

| 呼び出し箇所 | subagent_type | 期待返却値 |
|---|---|---|
| 手順 5（HTML・文書照合） | document-reviewer | 基準別判定表 + 総合判定（合格/不合格） |
| 手順 5（コード照合） | code-reviewer | 基準別判定表 + 総合判定（承認可/修正必須/マージ不可） |
| 調査報告の照合（直接委任経路。本スキルの手順 1〜4 は経由しない） | report-reviewer | 観点別判定 + 総合判定（PASS/FAIL） |
| 手順 6（不合格時の修正） | worker-sonnet | 修正ファイル一覧と修正内容の要約 |

## ループ設計

| 要素 | 内容 |
|---|---|
| 反復条件 | 専門家の総合判定が「不合格 / マージ不可 / 修正必須」なら worker-sonnet で修正し、手順 5 の照合を再実行する |
| 上限回数 | 最大 5 回 |
| 停止条件 | 収束（総合判定が合格）/ リソース上限（5 回到達）/ 発散検知（同一指摘が 2 回連続で再発）のいずれか。発散・上限時はユーザーへ差し戻す |

検証役（専門家）と修正役（worker-sonnet）を分離し、同一エージェントに判定と修正を兼務させない。

## 予想を裏切る挙動

- 専門家の定義には観点が書かれていない。rule.md のパスを渡し忘れると「照合 rule なし」で判定不能になる（これは仕様。観点なしレビューを許さないための設計）
- `resolve-applicable-rules.sh` は scoped rule のみ解決する。always rule（常時注入）は全作業で既に効いているため、レビュー委任時に改めて渡す必要はない。ただし用語辞書・意味キー等の横断規約は専門家自身が機械照合する（各専門家定義の該当箇所を参照）
- 担当専門家はフォルダ名から導出される（`review-checklist/<domain>/` → `<domain>-reviewer`）。ファイル拡張子から推測してはならない。新しい観点は既存ドメイン（code / document / report）配下に置けば追加作業なしでレビュー経路に乗る
- report ドメインだけは主経路が異なる: 照合対象（調査報告文）がファイルでないため、resolve スクリプトを経由せず report-reviewer へ直接委任する（調査チェックリストパイプライン Step 3）。report-reviewer は担当フォルダの rule（`report/common/rule.md`）を自ら Read する
- 新しいドメインを作る場合（例: shell）、対応する `<domain>-reviewer` を managing-agent-configs（種別 subagents）で**先に**新設する。専門家不在のドメインは監査が FAIL する
- `scripts/audit-review-coverage.sh` を定期的に実行し、ドメイン⇄専門家の 1 対 1・always 横断規約の参照・全 rule 分類を確認する（rules のレビュー時にも実行する）

## 関連

- `~/.claude/rules/scoped/agent-config/review-checklist/rule.md` — レビュー観点フォルダの統治規約（構造の正本）
- `~/.claude/rules/scoped/review-checklist/code/common/rule.md` — コードレビュー共通基準（観点正本）
- `~/.claude/rules/scoped/review-checklist/code/ui/rule.md` — UI実装基準（アイコン等。tsx/jsx/vue/css/scss/html に適用）
- `~/.claude/rules/scoped/review-checklist/document/html-output/rule.md` — 単一HTML成果物規約（観点正本）
- `~/.claude/rules/scoped/review-checklist/document/common/rule.md` — ドキュメント共通観点（観点正本）
- `~/.claude/rules/scoped/review-checklist/report/common/rule.md` — 調査報告共通観点（観点正本。report-reviewer が直接委任時に自ら Read する）
- `~/.claude/agents/code-reviewer/code-reviewer.md` / `~/.claude/agents/document-reviewer/document-reviewer.md` / `~/.claude/agents/report-reviewer/report-reviewer.md` — ドメイン別専門家
- `scripts/audit-review-coverage.sh` — ドメイン⇄専門家・観点・分類の網羅性監査
- `~/agent-home/skills/managing-agent-configs/SKILL.md` — 設定資産レビュー（本スキルの対象外領域）
