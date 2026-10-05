# 公開承認台帳

payload（public リポジトリ）への同期対象資産の承認状況を管理する台帳。
sync-manifest.json への mapping 追加は本台帳での承認を前提とする。

## 運用規則

1. sync-manifest.json に mirror / file mapping を追加する前に、当該資産に環境固有のパス・秘密情報・プロジェクト固有の名前が含まれないことを確かめ、本台帳に承認記録を追加する
2. 承認なしの mapping 追加を禁止する
3. 除外判定された資産は manifest から mapping を削除し、payload からも除去する

## 閉鎖した bundle: claudecode-global-setup（2026-09-29）

正本 `~/agent-home` の 2026-09-20 の全面解体で、スキル・規約・サブエージェント・hook の正本がなくなり、配布物だけが残っていたため、bundle 全体（payload、deploy-manifest.json、install.mjs、ポータル生成、公開安全テスト）を閉じた。ユーザーの決定。以下の「スキル（agent-home/skills/）」「ルール」「エージェント」「Codex ポータブル設定」の節は、閉鎖前の承認の履歴として残す。現在の同期対象は、「public-skills」の節だけである。reverse-docs-skills、claude-code-template、explanation-slides-kit、ai-consulting-toolkit は 2026-09-29 にユーザーの決定で公開をやめ、payload と manifest から除いた。

## スキル（agent-home/skills/）（閉鎖済み。履歴）

| スキル名 | 承認状況 | 承認根拠 | manifest 追加コミット | 備考 |
|---|---|---|---|---|
| managing-agent-configs | 承認済み | 初期同期対象 | beeebf1 以前 | |
| parallel-dev-worktree | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| grouping-commits | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| adding-textlint-dictionary-terms | 除外（未承認） | 正本 ~/agent-home の 2026-09-20 の全面解体で削除。payload と manifest から除去 | beeebf1 (2026-07-13) | 2026-09-29 に除外 |
| subagent-investigation-checklist | 除外（未承認） | 正本 ~/agent-home の 2026-09-20 の全面解体で削除。payload と manifest から除去 | beeebf1 (2026-07-13) | 2026-09-29 に除外 |
| eliciting-plan-tacit-knowledge | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| generating-explanation-html-slides | 承認済み | 815d818 で追加 | 815d818 (2026-07-14) | manifest に重複エントリあり（修正済み） |
| managing-session-workflow | 承認済み | セッション契約・ランタイム分岐・完了証拠を公開再レビュー | 本公開変更 | Codex/Claude 共通のルーティング責務。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| transcribing-images | 除外（未承認） | 正本 ~/agent-home の 2026-09-20 の全面解体で削除。payload と manifest から除去 | 本公開変更 | 2026-09-29 に除外。旧 source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| orchestrating-dev-flow | 承認済み | 指摘対応表・回帰・公開完了ゲートを公開再レビュー | 本公開変更 | 既存実装フローの補強。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| creating-new-project | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 未収載補完として無断追加。manifest・payload から除去済み |
| frontend-design | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 同上 |
| managing-github-issues | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 同上 |
| reviewing-against-rules | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 同上 |
| reviewing-public-readiness | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 同上 |
| reviewing-single-pr-with-inline-comments | 除外（未承認） | 公開可否レビュー未実施 | 3c44814 (2026-07-15) | 同上 |

## ルール（agent-home/rules/）

mirror モード（`~/agent-home/rules` → `payload/.../agent-home/rules`）で全量同期。beeebf1 (2026-07-13) で一括追加。`local-environment` は payload-artifacts.json で除外済み。

### always（常時注入・公開ミラー）

| ルールパス | 承認状況 | 備考 |
|---|---|---|
| always/agent-config/review | 承認済み（mirror 一括） | managing スキル実行ゲート |
| always/agent/coding-principles | 承認済み（mirror 一括） | コーディング原則 |
| always/agent/global-config-change | 承認済み（mirror 一括） | グローバル設定変更運用 |
| always/agent/subagent-selection | 承認済み（mirror 一括） | サブエージェント委任規約 |
| always/gate/phase-step-task | 承認済み（本公開変更で再レビュー） | phase 突入タスクゲート。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| always/infra/pre-bash-dispatch | 承認済み（mirror 一括） | Bash 実行前ディスパッチ |
| always/naming/commit-branch | 承認済み（mirror 一括） | コミット・ブランチ命名 |
| always/naming/common-principles | 承認済み（mirror 一括） | 共通命名原則 |
| always/placement/directory-structure | 承認済み（mirror 一括） | ディレクトリ構成ガード |
| always/placement/file-guard | 承認済み（mirror 一括） | ファイル配置ガード |
| always/placement/flow-context-guard | 承認済み（mirror 一括） | flow-values.yml 配置ガード |
| always/response/guard | 承認済み（mirror 一括） | 応答品質ガード |
| always/response/language | 承認済み（mirror 一括） | 応答言語・文体規約 |
| always/review-checklist/meaningful-key-naming | 承認済み（mirror 一括） | 意味キー規約 |
| always/review-checklist/term-explanation | 承認済み（mirror 一括） | 略称使用禁止 |
| always/review-checklist/text-dictionary | 承認済み（mirror 一括） | 文章置き換え辞書 |
| always/session/infra | 承認済み（mirror 一括） | セッション基盤 |
| always/session/workflow-gate | 承認済み（本公開変更で再レビュー） | 毎ターンの workflow コンテキスト供給・状態・完了ゲート。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |

### scoped（パス条件付き・公開ミラー）

| ルールパス | 承認状況 | 備考 |
|---|---|---|
| scoped/agent-config/claude-md | 承認済み（mirror 一括） | CLAUDE.md 保護 |
| scoped/agent-config/hooks | 承認済み（mirror 一括） | hook 配置アーキ規約 |
| scoped/agent-config/placement | 承認済み（mirror 一括） | 設定層配置判定 |
| scoped/agent-config/project-structure | 承認済み（mirror 一括） | プロジェクト構造 |
| scoped/agent-config/review-checklist | 承認済み（mirror 一括） | レビュー観点統治 |
| scoped/dev-flow/gate | 承認済み（本公開変更で再レビュー） | 実装フローゲート。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| scoped/dev-flow/worktree | 承認済み（mirror 一括） | worktree 運用 |
| scoped/portal/page-conventions | 承認済み（mirror 一括） | ポータルページ規約 |
| scoped/review-checklist/business-content/common | 承認済み（mirror 一括） | ビジネス資料品質基準 |
| scoped/review-checklist/code/common | 承認済み（mirror 一括） | コード共通観点 |
| scoped/review-checklist/code/test | 承認済み（mirror 一括） | テスト観点 |
| scoped/review-checklist/code/ui | 承認済み（mirror 一括） | UI 観点 |
| scoped/review-checklist/document/common | 承認済み（mirror 一括） | 文書共通観点 |
| scoped/review-checklist/document/html-output | 承認済み（mirror 一括） | HTML 出力規約 |
| scoped/review-checklist/report/common | 承認済み（mirror 一括） | 報告書観点 |
| scoped/routines/test-completion | 承認済み（mirror 一括） | テスト完了ルーティン |
| scoped/tooling/shell | 承認済み（mirror 一括） | シェルスクリプト規約 |
| scoped/review-checklist/code/catalog-site/design-notes.txt | 承認済み（公開安全 cleanup） | origin/main に残存した内部プロジェクト固有名のみ汎用化。規約内容・判断根拠は不変 |

## エージェント（agent-home/agents/）

mirror モード（`~/agent-home/agents` → `payload/.../agent-home/agents`）で全量同期。beeebf1 (2026-07-13) で一括追加。

| エージェント名 | 承認状況 | 分類 | 備考 |
|---|---|---|---|
| brain | 承認済み（mirror 一括） | 計画系 | 計画立案・タスク分解 |
| worker-sonnet | 承認済み（mirror 一括） | 実行系 | ファイル作成・修正 |
| worker-haiku | 承認済み（mirror 一括） | 実行系 | コマンド実行・結果報告 |
| investigator | 承認済み（mirror 一括） | 調査系 | 読み取り専用調査 |
| researcher | 承認済み（mirror 一括） | 調査系 | 外部情報収集 |
| plan-comprehension-prober | 承認済み（mirror 一括） | 調査系 | 計画初見読解 |
| code-reviewer | 承認済み（mirror 一括） | 判定系 | コード照合 |
| document-reviewer | 承認済み（mirror 一括） | 判定系 | 文書照合 |
| business-content-reviewer | 承認済み（mirror 一括） | 判定系 | 顧客資料照合 |
| report-reviewer | 承認済み（mirror 一括） | 判定系 | 調査報告検証 |

## 支援ツール（ai-driven-development-setup）（閉鎖済み 2026-09-29。履歴。正本 ~/Projects/ai-driven-development-setup が存在しないため、ユーザーの決定で payload と manifest から除いた）

| 資産 | 承認状況 | 承認根拠 | manifest 追加コミット | 備考 |
|---|---|---|---|---|
| .claude/skills（派生した機能 7 つ） | 承認済み | 公開可否レビュー（12 カテゴリの機密検査）を 2026-09-03 に実施し INFO。禁止語・固有パス・author を確認 | 本公開変更 | 定義（docs/）は配らない。delivery-payload は未作成のため対象外 |
| README.md | 承認済み | 公開可否レビュー（12 カテゴリの機密検査）を 2026-09-03 に実施し INFO。禁止語・固有パス・author を確認 | 本公開変更 | 定義（docs/）は配らない。delivery-payload は未作成のため対象外 |

## Codex ポータブル設定

| 資産 | 承認状況 | 承認根拠 | 備考 |
|---|---|---|---|
| agent-home/config/codex/hook-command-adapter.sh | 承認済み | 偽 bootstrap 廃止とイベント検証を再レビュー | `--runtime codex\|all` で配布。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| agent-home/config/codex/hook-command-adapter.test.sh | 承認済み | adapter 回帰テストとして再レビュー | 配布後の自己診断に利用可能。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| agent-home/config/codex/hooks-registry.json | 承認済み | 公開対象 hook の最小集合として再レビュー | `$HOME` 基準のポータブル registry。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| codex-config/hooks.json | 承認済み | Codex hook 形状・既存設定 merge をレビュー | opt-in、既存設定を backup して merge。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |

## public-skills（~/Projects/public-skills/.claude/ を mirror）

| スキル名 | 承認状況 | 承認根拠 | 備考 |
|---|---|---|---|
| reporting-textlint-findings | 承認済み | 初期同期対象（2026-09-15） | |
| drafting-skill-with-template（旧 creating-agent-skills） | 承認済み | ユーザーの公開指示（2026-09-29）。環境固有のパスなし。実行者の検証 8 回で必須要件すべて ○。2026-09-30 に新規作成だけへ縮小し、drafting-skill-with-template に改名 | source: agent-home@09baffc、public-skills@bee2543 |
| testing-agent-skills | 承認済み | ユーザーの公開指示（2026-09-29）。成果物は一時フォルダに書き終了時に消す。環境固有のパスなし | source: agent-home@8a3313c、public-skills@68984d1 |

| reviewing-agent-skills | 承認済み | 3 分割で新設（2026-09-30）。環境固有のパスなし。実行者の検証 2 シナリオで必須要件すべて ○、結果を変える点 0 件 | source: agent-home@09baffc、public-skills@bee2543 |
| agent-skill-templates | 除外（廃止） | 2026-10-01 に rules/agent-skill へ移して廃止。payload と manifest から除去 | |
| rules/skill-writing（規約 9 本、雛形 2 本、記入例 1 本。スキルではない） | 承認済み | 2026-10-01。旧 agent-skill を改名し、構成（structure）・書き方（writing）・雛形（templates）で分ける。環境固有のパスなし | mirror ~/Projects/public-skills/rules。source: agent-home@e45a7b7 |

### 2026-10-05 の構成変更

| 対象 | 承認状況 | 承認根拠 | 備考 |
|---|---|---|---|
| .claude/ 配下の構成 | 承認済み | ユーザーの指示（2026-10-05）。規約の paths はプロジェクト内のファイルにしか効かないため、~/.claude/ への複製をやめ、プロジェクトの .claude/ に置く形に改めた | 旧 rules/ と skills/ は削除 |
| rules/skill-writing-compact（規約 1 ファイル版 42 規則、雛形、完成例） | 承認済み | zip 版を正とし、paths を .claude/skills/**/* と .claude/rules/skill-writing-compact/**/* に書き換え。環境固有のパスなし | source: agent-home、public-skills@33dfb31 |
| drafting-skill-with-template（zip 版 + step 1-1 の realpath） | 承認済み | 検証者で規約と照合し違反 0 件。環境固有のパスなし | 同上 |
| checking-skill-against-rules（旧 reviewing-agent-skills の置き換え） | 承認済み | 検証者で規約と照合し違反 0 件。環境固有のパスなし | 同上 |
| designing-skill-tests | 承認済み | 検証者で規約と照合し違反 0 件。環境固有のパスなし（作業フォルダ基準） | 同上 |
| testing-agent-skills（作り直し） | 承認済み | 検証者で規約と照合し違反 0 件。環境固有のパスなし | 同上 |
| reviewing-agent-skills、reporting-textlint-findings、converting-mermaid-md-to-html、rules/skill-writing（12 本版） | 除外 | 2026-10-05 にユーザーの指示で公開をやめた | payload と manifest から除去 |
