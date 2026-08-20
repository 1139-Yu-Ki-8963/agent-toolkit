# reverse-docs-skills 作業案内

## 前半: リポジトリ索引

- 目的: 既存コードから設計書・一覧・検証記録をリバース生成し、設計書からの再生成と原本突合までを行うスキル群。
- 技術スタック: `.claude/skills/` のSKILL.md、`generation-engine/scripts/`、`delivery-payload/templates/`、`generation-engine/samples/` に実在する構成を参照する。
- 実行コマンド: README、各SKILL.md、各スクリプトに記載され、実行確認できたコマンドだけを記載する。
- ディレクトリ構造: `.claude/skills/`、`delivery-payload/references/`、`generation-engine/scripts/`、`delivery-payload/templates/`、`generation-engine/samples/`、`docs/`。
- リバース対象: 画面、API、テーブル、バッチ、帳票、外部連携、および各ポータル納品物カテゴリ。
- 成果物の正本: `delivery-payload/references/納品物フォルダ体系.md`、`delivery-payload/references/リバース工程設計.md`、`.claude/skills/*/SKILL.md`。
- 派生物: `README.md`、`docs/guides/reverse-docs-overview.html`、ガイドHTML、サンプルポータル。
- 調査入口: `README.md`、`docs/guides/reverse-docs-overview.html`、`.claude/skills/orchestrating-ai-development-setup/`。
- 検証出力先: 各スキルの指定する出力先と `verification/`。未確認の出力先は追加しない。

## 後半: 規約の読み込み

このリポジトリで明示された規約の実在パスと意図だけを記載する。規約本文は複製しない。対象リポジトリ固有の規約パスは、リバース時に実在確認できたものへ置換する。

### このリポジトリのAI設定資産管理

- 意図: スキル・ルール・フック等の変更経路とレビュー境界を確認する。
- 正確な参照パス: `.claude/rules/scoped/agent-config/`

### このリポジトリの公開完遂

- 意図: 正本commit、payload同期、agent-toolkitのorigin/main反映を確認する。
- 正確な参照パス: `.claude/rules/always/publish/complete/rule.md`

### 未確定事項

- 対象リポジトリへ生成する場合、上記パスは対象側の実在確認済みパスへ置換する。
