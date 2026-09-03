# 公開承認台帳

payload（public リポジトリ）への同期対象資産の承認状況を管理する台帳。
sync-manifest.json への mapping 追加は本台帳での承認を前提とする。

## 運用規則

1. sync-manifest.json に mirror / file mapping を追加する前に、当該資産の公開可否レビュー（reviewing-public-readiness）を実施し、本台帳に承認記録を追加する
2. 承認なしの mapping 追加を禁止する
3. 除外判定された資産は manifest から mapping を削除し、payload からも除去する

## スキル（agent-home/skills/）

| スキル名 | 承認状況 | 承認根拠 | manifest 追加コミット | 備考 |
|---|---|---|---|---|
| managing-agent-configs | 承認済み | 初期同期対象 | beeebf1 以前 | |
| parallel-dev-worktree | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| grouping-commits | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| adding-textlint-dictionary-terms | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| subagent-investigation-checklist | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| eliciting-plan-tacit-knowledge | 承認済み | beeebf1 で追加 | beeebf1 (2026-07-13) | |
| generating-explanation-html-slides | 承認済み | 815d818 で追加 | 815d818 (2026-07-14) | manifest に重複エントリあり（修正済み） |
| managing-session-workflow | 承認済み | セッション契約・ランタイム分岐・完了証拠を公開再レビュー | 本公開変更 | Codex/Claude 共通のルーティング責務。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
| transcribing-images | 承認済み | 構造化 handoff と責務境界を公開再レビュー | 本公開変更 | 実装は行わずセッション管理へ返す。source: agent-home@532d7102520022ba81e04ee9e7f96eb9b1254fbe |
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

## 支援ツール（ai-driven-development-setup）

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
