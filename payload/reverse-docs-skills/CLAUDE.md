# reverse-docs-skills AI作業案内

このリポジトリは、既存コードから設計書・一覧・検証記録をリバース生成し、設計書からの再生成と原本突合までを行うスキル群の定義です。スキルの実体は `.claude/skills/`、納品先へ配るテンプレート・参照文書は `delivery-payload/`、納品物を作る生成器・見本は `generation-engine/`、全体ガイドは `docs/guides/reverse-docs-overview.html`、納品物ガイドは `docs/guides/納品物ガイド.html` にあります。

## 索引

- スキル: `.claude/skills/`
- 納品先へ配るテンプレート: `delivery-payload/templates/`
- 納品先へ配る参照文書: `delivery-payload/references/`
- 生成エンジンのスクリプト: `generation-engine/scripts/`
- 生成エンジンの見本（サンプル）: `generation-engine/samples/`・`generation-engine/samples-no-screen/`
- 生成エンジンのスキーマ: `generation-engine/schemas/`
- 生成エンジンの設計文書: `generation-engine/DESIGN.md`
- このリポジトリ自身の設計文書: `docs/`
- ポータル設計: `docs/design/portal/`
- 用語管理関連文書: `docs/design/glossary/`
- 検証loop設計: `docs/design/reverse-verification/`
- 計画文書: `docs/tasks/`
- 納品物ガイド関連文書: `docs/`
- 人間向け全体ガイド: `docs/guides/reverse-docs-overview.html`
- 納品物ガイド: `docs/guides/納品物ガイド.html`
- 作業の記録: `docs/tasks/work-records/`

成果物の対象リポジトリへの配置は、対象リポジトリを分析して生成する `AGENTS.md` と `CLAUDE.md` の前半索引に記録します。このリポジトリ自身の公開手順は、次節と [公開完遂規約](.claude/rules/always/publish/complete/rule.md) を参照します。

## 公開完遂フロー

このリポジトリの変更は、定義の commit、`~/github-public/agent-toolkit/payload/reverse-docs-skills/` への同期、`origin/main` への push までを完了条件とする。同期対象と手順の詳細は [公開完遂規約](.claude/rules/always/publish/complete/rule.md) と [RUNBOOK.md](RUNBOOK.md) を定義として参照する。
