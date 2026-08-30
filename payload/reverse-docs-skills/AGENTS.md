# reverse-docs-skills 作業案内

## 前半: リポジトリ索引

- 目的: 既存コードから設計書・一覧・検証記録をリバース生成し、設計書からの再生成と原本突合までを行うスキル群。
- 技術スタック: `.claude/skills/` のSKILL.md、`generation-engine/scripts/`、`delivery-payload/templates/`、`generation-engine/samples/` に実在する構成を参照する。
- 実行コマンド: README、各SKILL.md、各スクリプトに記載され、実行確認できたコマンドだけを記載する。
- リバース対象: 画面、API、テーブル、バッチ、帳票、外部連携、および各ポータル納品物カテゴリ。
- 成果物の正本: `delivery-payload/references/納品物フォルダ体系.md`、`delivery-payload/references/リバース工程設計.md`、`.claude/skills/*/SKILL.md`。
- 調査入口: `README.md`、`docs/guides/reverse-docs-overview.html`、`.claude/skills/orchestrating-ai-development-setup/`。
- 検証出力先: 各スキルの指定する出力先と `verification/`。未確認の出力先は追加しない。

## 後半: 規約の読み込み

このリポジトリで明示された規約の実在パスと意図だけを記載する。規約本文は複製しない。対象リポジトリ固有の規約パスは、リバース時に実在確認できたものへ置換する。

### このリポジトリのAI設定資産管理

- 意図: スキル・ルール・フック等の変更経路とレビュー境界を確認する。
- 正確な参照パス: `.claude/rules/scoped/agent-config/`

### このリポジトリの公開完遂

- 意図: 正本commit、payload同期、agent-toolkitのorigin/main反映を確認する。
- 参照先: このリポジトリ自身の公開完遂規約。配布対象外のため配布先には存在しない

### 未確定事項

- 対象リポジトリへ生成する場合、上記パスは対象側の実在確認済みパスへ置換する。

<!-- RULES-INDEX:START -->
<!-- 生成物: build-derived-rules.sh により docs/rules/ から自動生成。直接編集しないこと -->

## AIエージェント運用
- **人とAIの分担の決まり**: AIエージェントへの作業委任・役割分担・実行方式の取り決め。（参照: docs/rules/agent-operations/ai-behavior/rule.md）
- **定義と生成物の分け方の決まり**: スキル・規約・フックなどAI設定資産の作成・変更・配置・レビューの手順。（参照: docs/rules/agent-operations/ai-config-asset-management/rule.md）
- **上書きの前に読む決まり**: rm -rf・force push・reset --hard 等の破壊的操作を実行する前の確認と検査の取り決め。（参照: docs/rules/agent-operations/destructive-operation-safety/rule.md）
- **繰り返す作業の手順書の決まり**: 定期的に繰り返す定型作業の手順と実行タイミングの取り決め。（参照: docs/rules/agent-operations/routine-operations/rule.md）
- **完了報告に実行結果を添える決まり**: 作業セッションの開始・終了・記録・引き継ぎに関する取り決め。（参照: docs/rules/agent-operations/session-management/rule.md）

## 業務ドメイン規約
- **業務の判定の書き方の決まり**: 業務上守るべき判定ロジックと制約の取り決め。（参照: docs/rules/business-domain/business-rules/rule.md）
- **金額と数量の計算の決まり**: 金額・数量などの計算ロジックとその根拠の取り決め。（参照: docs/rules/business-domain/calculation-rules/rule.md）
- **業務の言葉の決まり**: 業務用語とコード上の識別子の対応関係の定義。（参照: docs/rules/business-domain/glossary/rule.md）
- **状態の移り変わりの決まり**: 業務エンティティが取りうる状態と許可される遷移の取り決め。（参照: docs/rules/business-domain/state-transitions/rule.md）

## コード規約
- **コードの書き方と分割の決まり**: コードの書き方・関数分割・ファイル行数など実装スタイルの取り決め。（参照: docs/rules/code-standards/coding-style/rule.md）
- **部品の分け方と依存の決まり**: コンポーネントの分割方針・責務分担・依存関係の設計指針。（参照: docs/rules/code-standards/component-architecture/rule.md）
- **どこに何を置くかの決まり**: リポジトリのディレクトリ配置とレイヤー構成の取り決め。（参照: docs/rules/code-standards/directory-structure/rule.md）
- **名前の付け方の決まり**: 変数・関数・ファイル・ディレクトリなど識別子の命名パターン。（参照: docs/rules/code-standards/naming/rule.md）

## 開発プロセス
- **開発環境の組み立て方の決まり**: ローカル開発環境の構築手順・依存関係・環境変数の管理方法。（参照: docs/rules/development-process/development-environment/rule.md）
- **実装から統合までの順序の決まり**: 設計から実装・レビュー・統合までの開発工程の順序と各段階の完了条件。（参照: docs/rules/development-process/development-flow/rule.md）
- **コミットと枝の決まり**: コミット・ブランチ・マージ・プルリクエストの運用ルール。（参照: docs/rules/development-process/git-operations/rule.md）
- **版付けと公開の決まり**: リリース手順・デプロイ方法・バージョン管理の取り決め。（参照: docs/rules/development-process/release-and-delivery/rule.md）
- **使うツールとコマンドの決まり**: 開発で使うツールとコマンドの実行方法・権限・実行前確認の取り決め。（参照: docs/rules/development-process/tools-and-commands/rule.md）

## 文書化規約
- **設計書の書き方の決まり**: 設計書・手順書などドキュメントの記述形式と更新手順の取り決め。（参照: docs/rules/documentation-standards/document-writing/rule.md）
- **生成した文書を直接編集しない決まり**: ポータルと一覧のHTMLを保守するときの取り決め。（参照: docs/rules/documentation-standards/portal-maintenance/rule.md）

## 非機能要件
- **稼働を続けることと復旧の決まり**: システムの稼働継続性と障害時の復旧に関する要件。（参照: docs/rules/non-functional-requirements/availability/rule.md）
- **記録と監視の決まり**: ログ出力・監視・アラートに関する要件。（参照: docs/rules/non-functional-requirements/observability/rule.md）
- **応答の速さと処理の量の決まり**: 応答時間・処理件数などパフォーマンスに関する要件。（参照: docs/rules/non-functional-requirements/performance/rule.md）
- **利用が増えたときの決まり**: 利用量の増加に対応するための拡張方針に関する要件。（参照: docs/rules/non-functional-requirements/scalability/rule.md）
- **認証と入力と秘密の値の決まり**: 認証・認可・入力検証など安全性に関する要件。（参照: docs/rules/non-functional-requirements/security/rule.md）

## ポータル
- **ポータル HTML 規約**: リバース設計ポータルの生成 HTML に適用する合格基準。テンプレートから生成された全ページが統一されたデザインシステムと構造規約に準拠していることを検証する。（参照: docs/rules/portal/page-conventions/rule.md）

## 品質保証
- **レビューの観点の決まり**: レビューをいつ・誰が・何を基準に行い、どの条件で通すかの取り決め。（参照: docs/rules/quality-assurance/review-checklist/rule.md）
- **単体テスト設計書の決まり**: テストの種類・カバレッジ目標・実行タイミングの取り決め。（参照: docs/rules/quality-assurance/test-policy/rule.md）

## 検証
- **リバース検証運用規約**: リバース設計スキル群の検証手順を実行側リポジトリの散文から本規約へ移し、判定の基準を機械が読める形で定義する。（参照: docs/rules/verification/reverse-verification/rule.md）
<!-- RULES-INDEX:END -->
