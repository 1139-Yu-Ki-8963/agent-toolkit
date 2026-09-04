# 旧 skill の対応表

旧リポジトリ（reverse-docs-skills）の skill を、新リポジトリの 5 単位（setup・reverse・verify・portal・operate）の機能へ対応させる表である。新の名前は skill の名前の決まり（`docs/rules/agent-operations/skill-naming/rule.md`）に従い `<単位>-<作業>-<対象>` の 3 語で組む。同じ作業を種別（画面・接続窓口・表・バッチ・帳票・外部連携・機能）ごとに分けず、種別は宣言の `kind` を引数にして 1 機能へ束ねる。旧 59 本（53 本と納品 6 本）は新 37 本になる。

扱いは束ねる（複数の旧を 1 つの新へ集める）・改名（1 対 1 で中身を持ち込む）・作り直し（役割は同じだが作り替える）・廃止（新へ持ち込まない）の 4 つである。持ち込みは単位ごとに進め、合格の集計（`setup-checking-acceptance`）を通ったものから旧の対応する skill を廃止する。

要件定義書は基盤一式に含める。順序は `docs/design/リバースの流れの設計.md` に従う（第一フェーズで道標・要件定義書・共通設計文書、第二フェーズで一覧化以降）。出力先は `docs/design/作業ディレクトリと出力の配置.md` に従う。

| 旧の名前 | 日本語名 | 新の名前 | 単位 | category | 扱い | 備考 |
|---|---|---|---|---|---|---|
| counting-code-lines | コードの行数を数える | reverse-counting-code-lines | reverse | survey | 改名 | — |
| extracting-unit-facts-from-code | 元のコードから事実を取り出す | reverse-extracting-facts | reverse | setup | 改名 | 種別は kind で受ける |
| generating-agent-config-index-from-repo | エージェント向け案内の索引を作る | setup-generating-agent-index | setup | setup | 束ねる | 旧 cross-views のエージェント設定の一覧を含む |
| generating-api-basic-design-for-reverse-docs | 接続窓口の基本設計書を作る | reverse-writing-basic-design | reverse | setup | 束ねる | kind=api。単体テスト設計書も基本設計で作る |
| generating-api-detail-design-for-reverse-docs | 接続窓口の詳細設計書を作る | reverse-writing-detail-design | reverse | setup | 束ねる | kind=api |
| generating-api-list-for-reverse-docs | 接続窓口の一覧を作る | reverse-listing-units | reverse | setup | 束ねる | kind=api。出力は JSON と Markdown。HTML は portal 単位 |
| generating-batch-basic-design-for-reverse-docs | バッチの基本設計書を作る | reverse-writing-basic-design | reverse | setup | 束ねる | kind=batch |
| generating-batch-detail-design-for-reverse-docs | バッチの詳細設計書を作る | reverse-writing-detail-design | reverse | setup | 束ねる | kind=batch |
| generating-batch-list-for-reverse-docs | バッチの一覧を作る | reverse-listing-units | reverse | setup | 束ねる | kind=batch |
| generating-component-inventory-for-reverse-docs | 部品の棚卸し表を作る | portal-building-design-tools | portal | setup | 束ねる | 部品の棚卸し表 |
| generating-cross-views-for-reverse-docs | 対応表とエージェント設定の一覧を作る | portal-building-matrices | portal | setup | 束ねる | 対応表（CRUD・権限・画面と接続窓口と表の対応）。エージェント設定の一覧は setup-generating-agent-index へ |
| generating-design-system-for-reverse-docs | デザインの決まりのページを作る | portal-building-design-tools | portal | setup | 束ねる | デザインの決まりのページ |
| generating-entity-state-for-reverse-docs | 状態の移り変わりの図を作る | portal-drawing-diagrams | portal | setup | 束ねる | 状態の移り変わりの図 |
| generating-env-guide-for-reverse-docs | 環境構築の手順書を作る | reverse-writing-foundation-guides | reverse | setup | 束ねる | 環境構築の手順書 |
| generating-er-diagram-for-reverse-docs | 表同士のつながりを図にする | portal-drawing-diagrams | portal | setup | 束ねる | 表同士のつながりの図 |
| generating-external-basic-design-for-reverse-docs | 外部連携の基本設計書を書く | reverse-writing-basic-design | reverse | setup | 束ねる | kind=external |
| generating-external-detail-design-for-reverse-docs | 外部連携の詳細設計書を書く | reverse-writing-detail-design | reverse | setup | 束ねる | kind=external |
| generating-external-list-for-reverse-docs | 外部連携の一覧を作る | reverse-listing-units | reverse | setup | 束ねる | kind=external |
| generating-feature-design-for-reverse-docs | 機能の集約設計書を書く | reverse-writing-basic-design | reverse | setup | 束ねる | kind=feature。機能は集約設計書のみで詳細設計を持たない |
| generating-feature-list-for-reverse-docs | 機能の一覧を作る | reverse-listing-units | reverse | setup | 束ねる | kind=feature |
| generating-glossary-for-reverse-docs | 用語の候補を挙げる | reverse-proposing-rules | reverse | setup | 束ねる | 用語の候補。用語は規約（業務の言葉の決まり）に含める |
| generating-icon-catalog-for-reverse-docs | アイコン一覧を作る | portal-building-design-tools | portal | setup | 束ねる | アイコン一覧 |
| generating-integration-test-spec-for-reverse-docs | 結合テスト仕様書の生成 | reverse-writing-test-designs | reverse | setup | 束ねる | 結合テスト仕様書 |
| generating-message-list-for-reverse-docs | メッセージの一覧を作る | — | reverse | setup | 廃止 | メッセージは単位にせず、共通外部仕様書の節にする |
| generating-release-notes-for-reverse-docs | 更新履歴のページを作る | portal-building-top | portal | setup | 束ねる | 更新履歴のページ |
| generating-report-basic-design-for-reverse-docs | 帳票の基本設計書を書く | reverse-writing-basic-design | reverse | setup | 束ねる | kind=report |
| generating-report-detail-design-for-reverse-docs | 帳票の詳細設計書を書く | reverse-writing-detail-design | reverse | setup | 束ねる | kind=report |
| generating-report-list-for-reverse-docs | 帳票一覧のとりまとめ | reverse-listing-units | reverse | setup | 束ねる | kind=report |
| generating-requirement-definitions-for-reverse-docs | 要件定義文書のとりまとめ | reverse-drawing-map | reverse | setup | 束ねる | 要件定義書は第一フェーズの手順 3 |
| generating-reverse-basic-design | 基本設計書の書き起こし | reverse-writing-basic-design | reverse | setup | 束ねる | kind=screen |
| generating-reverse-common-docs | 共通文書の書き起こし | reverse-drawing-map | reverse | setup | 束ねる | 共通設計文書 6 つは第一フェーズの手順 4 |
| generating-reverse-detailed-design | 詳細設計書の書き起こし | reverse-writing-detail-design | reverse | setup | 束ねる | kind=screen。単体テスト設計書の生成は基本設計へ移す |
| generating-rule-proposals-for-reverse-docs | 規約提案の書き出し | reverse-proposing-rules | reverse | setup | 束ねる | 規約提案。納品先で回す同名の納品 skill は operate-handling-rule-proposals へ |
| generating-screen-list-for-reverse-docs | 画面一覧のとりまとめ | reverse-listing-units | reverse | setup | 束ねる | kind=screen。reverse 単位の持ち込みはここから始める |
| generating-screen-transition-for-reverse-docs | 画面遷移図の書き出し | portal-drawing-diagrams | portal | setup | 束ねる | 画面遷移図 |
| generating-sequence-diagram-for-reverse-docs | シーケンス図の書き出し | portal-drawing-diagrams | portal | setup | 束ねる | シーケンス図 |
| generating-table-definition-for-reverse-docs | テーブル定義書の書き起こし | reverse-writing-detail-design | reverse | setup | 束ねる | kind=table。テーブル定義書 |
| generating-table-list-for-reverse-docs | テーブル一覧のとりまとめ | reverse-listing-units | reverse | setup | 束ねる | kind=table |
| generating-table-logical-model-for-reverse-docs | 論理データモデルの書き起こし | reverse-writing-basic-design | reverse | setup | 束ねる | kind=table。論理データモデル |
| generating-tech-stack-for-reverse-docs | 技術スタックの書き出し | reverse-writing-foundation-guides | reverse | setup | 束ねる | 技術スタック |
| generating-test-case-list-for-reverse-docs | テストケース一覧の生成 | reverse-writing-test-designs | reverse | setup | 束ねる | テストケース一覧 |
| generating-test-viewpoint-list-for-reverse-docs | テスト観点表の生成 | reverse-writing-test-designs | reverse | setup | 束ねる | テスト観点表 |
| maintaining-semantic-glossary | 用語変更の検査と影響分析 | operate-managing-glossary | operate | operate | 束ねる | 用語変更の検査と影響分析 |
| managing-semantic-glossary | 用語の変更と公開の管理 | operate-managing-glossary | operate | operate | 束ねる | 用語の変更と公開。ポータルへの投影の段は portal 単位へ移す |
| orchestrating-ai-development-setup | 検証工程全体の統括 | setup-orchestrating-units | setup | setup | 作り直し | 宣言を読んで実行順を導く。名前の直書きを持たない |
| prioritizing-improvement-tasks-from-images | 改善課題の登録と優先順位付け | — | — | — | 廃止 | 旧リポジトリ自身の運用として旧に残す |
| rebuilding-code-from-docs | 設計書からのコード再構築 | verify-rebuilding-code | verify | setup | 束ねる | 設計書からの再構築 |
| rebuilding-screen-unit-from-docs | 単一ファイルの再構築検証 | verify-rebuilding-code | verify | setup | 束ねる | 単一ファイルの再構築は kind=screen の 1 件実行 |
| running-reverse-screen-batch | 画面単位の無人一括検証 | verify-running-screen-batch | verify | setup | 改名 | 全画面の基本設計と単体テスト設計を終えてから詳細設計へ進む二周の形にする |
| surveying-architecture-for-reverse-docs | アーキテクチャ調査書の確定 | reverse-drawing-map | reverse | survey | 作り直し | 第一フェーズ全体（調査・要件定義書・共通設計文書・承認）を 1 機能にした |
| surveying-local-environment | 実行環境の調査 | verify-syncing-environment | verify | setup | 束ねる | 実行環境の調査 |
| syncing-reverse-env | 元コードと設計書の環境をそろえる | verify-syncing-environment | verify | setup | 束ねる | 環境をそろえる |
| unlocking-reverse-target-screens | 対象画面の疑似接続 | verify-unlocking-target-screens | verify | setup | 改名 | — |

## 納品 skill（旧 delivery-payload/templates/delivered-skills）

| 旧の名前 | 日本語名 | 新の名前 | 単位 | category | 扱い | 備考 |
|---|---|---|---|---|---|---|
| dev-flow | 開発フロー | operate-running-dev-flow | operate | operate | 改名 | ポータル再生成の段は portal 単位へ移し、ポータルが無い場合も回る |
| generating-rule-proposals | 規約提案の書き出し（納品先） | operate-handling-rule-proposals | operate | operate | 束ねる | 提案の書き出し |
| importing-rule-proposals | 規約提案の取り込み | operate-handling-rule-proposals | operate | operate | 束ねる | 提案の取り込み |
| maintaining-portal | ポータルの保守 | portal-maintaining-pages | portal | operate | 改名 | 納品先で回すが単位は portal |
| resolving-confirmation-items | 確認事項の反映 | operate-resolving-confirmation-items | operate | operate | 改名 | 確認事項一覧（1 行 1 事項）の回答を先方リポジトリの設計書へ書き戻す |
| syncing-derived-artifacts | 派生物の同期 | operate-syncing-derived-artifacts | operate | operate | 作り直し | 配置された派生のスクリプトを納品先で呼ぶ薄い手順 |

## 新設

| 新の名前 | 単位 | category | 役割 |
|---|---|---|---|
| setup-deriving-rules | setup | setup | docs/rules の定義から .claude/rules 等を派生する（作成済み） |
| setup-deriving-skills | setup | setup | docs/skills の定義を検査し .claude/skills へ派生する（作成済み） |
| setup-scaffolding-rules | setup | setup | 対象へ規約の定義一式を配置する（作成済み） |
| setup-checking-acceptance | setup | setup | 機能・単位・要件の合格を集計し欠落を検査する（作成済み） |
| setup-orchestrating-units | setup | setup | 宣言を読んで実行順を導く統括（作成済み） |
| setup-building-delivery | setup | setup | 定義から配布物 `delivery-payload/<単位>/` を作る |
| reverse-checking-basic-phase | reverse | setup | 基本設計の完了状態を 6 観点で確かめ、合格記録を書く。不合格は基本設計へ差し戻して繰り返す |
| reverse-writing-common-detail-design | reverse | setup | 共通処理の詳細設計書。共通の基本設計の後、単位ごとの詳細設計の前に書く |
| reverse-listing-confirmation-items | reverse | setup | 確認事項一覧（1 行 1 事項・Markdown）を `ai-output/` の confirmations へ出す。用語候補と規約提案の採否も行として含む |
| portal-building-lists | portal | setup | 一覧の HTML（旧の一覧 skill から HTML の描画を分けたもの） |
| portal-building-design-docs | portal | setup | 設計書の HTML 表示 |
| operate-installing-skills | operate | setup | 納品先へ運用の単位の skill と agent（規約レビュー担当）を配置する |
| reverse-drawing-map | reverse | survey | 第一フェーズ全体（領域の切り出し・領域ごとの調査・要件定義書・共通設計文書・検査と出し直し・範囲の承認）を担う機能 |
| reverse-listing-units | reverse | setup | 検出条件を実行する共通の走査（実行器）を持つ。機械の種別はスクリプトで実測し、AI の読み取りの種別は AI が読んで一覧にする |
| reverse-checking-requirements | reverse | setup | 要件定義書の機能要件と一覧を突き合わせ、機能と単位の対応表を書く。要件定義書は変更しない |

## 新の機能の一覧

| 単位 | 新の名前 | 束ねた旧の数 |
|---|---|---|
| setup | setup-deriving-rules | 0 |
| setup | setup-deriving-skills | 0 |
| setup | setup-scaffolding-rules | 0 |
| setup | setup-checking-acceptance | 0 |
| setup | setup-orchestrating-units | 1 |
| setup | setup-building-delivery | 0 |
| setup | setup-generating-agent-index | 1 |
| reverse | reverse-counting-code-lines | 1 |
| reverse | reverse-extracting-facts | 1 |
| reverse | reverse-writing-basic-design | 7 |
| reverse | reverse-writing-detail-design | 6 |
| reverse | reverse-listing-units | 7 |
| reverse | reverse-writing-foundation-guides | 2 |
| reverse | reverse-proposing-rules | 2 |
| reverse | reverse-writing-test-designs | 3 |
| reverse | reverse-drawing-map | 3 |
| reverse | reverse-checking-basic-phase | 0 |
| reverse | reverse-writing-common-detail-design | 0 |
| reverse | reverse-listing-confirmation-items | 0 |
| verify | verify-rebuilding-code | 2 |
| verify | verify-running-screen-batch | 1 |
| verify | verify-syncing-environment | 2 |
| verify | verify-unlocking-target-screens | 1 |
| portal | portal-building-design-tools | 3 |
| portal | portal-building-matrices | 1 |
| portal | portal-drawing-diagrams | 4 |
| portal | portal-building-top | 1 |
| portal | portal-maintaining-pages | 1 |
| portal | portal-building-lists | 0 |
| portal | portal-building-design-docs | 0 |
| operate | operate-managing-glossary | 2 |
| operate | operate-running-dev-flow | 1 |
| operate | operate-handling-rule-proposals | 2 |
| operate | operate-resolving-confirmation-items | 1 |
| operate | operate-syncing-derived-artifacts | 1 |
| operate | operate-installing-skills | 0 |

## 単位ごとの件数

| 単位 | 件数 |
|---|---|
| setup | 7 |
| reverse | 13 |
| verify | 4 |
| portal | 7 |
| operate | 6 |

## 出力形式の振り分け

portal 以外の 4 単位は宣言の `outputs` を `.md` と `.json` に限り、HTML は portal 単位だけが出す（2026-09-03 決定。検査は合格の集計の欠落 6 つ目）。旧がポータルの HTML として出していた物の振り分けは次のとおり。詳しい表は `ai-work/records/` の記録「出力形式を Markdown と JSON に限る」にある。

| 振り分け | 成果物 | 新の出し方 |
|---|---|---|
| md/json を定義として出し、HTML は portal が別に作る | 一覧 8 種・テスト観点表・テストケース一覧・結合テスト仕様書・共通設計 5 文書・アーキテクチャ調査書・技術スタック・環境構築手順・単位の設計書・規約 32 件・用語・AI 設定資産・納品物一覧・デザインシステム・マトリクス 4 種 | reverse／setup の機能が `docs/design/` と `docs/rules/` へ md（一覧は json も）。portal-building-* が HTML |
| md だけ出し、HTML は作らない | 確認事項一覧 | reverse-listing-confirmation-items が先方リポジトリに含めない出力の置き場へ md。単位ごとの台帳は廃止 |
| portal だけが出す | 図 4 種・コンポーネント棚卸し・アイコンカタログ・リリースノート | portal-drawing-diagrams・portal-building-design-tools・portal-building-top |
| 廃止 | 規約とフローの対応（旧の生成器 build-rule-flow-map） | 作らない。規約の索引は派生の AGENTS.md が担う |
