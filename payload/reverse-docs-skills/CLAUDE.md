# reverse-docs-skills AI作業案内

このリポジトリは、対象プロジェクトへ「AI駆動開発の基盤一式」を納品するツール群の定義です。区分はセットアップ・リバース・保守（納品物の維持）・現場運用（納品先の開発サイクル）の4つです。リバースでは既存コードから設計書を書き起こし、設計書だけからの再生成と原本突合で品質を確かめます。スキルの実体は `.claude/skills/`、納品先へ配るテンプレート・参照文書は `delivery-payload/`、納品物を作る生成器・見本は `generation-engine/`、全体ガイドは `docs/guides/reverse-docs-overview.html`、納品物ガイドは `docs/guides/納品物ガイド.html` にあります。

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
- 作業の記録: `docs/tasks/work-records/`（配布対象外のため配布先には無い）

成果物の対象リポジトリへの配置は、対象リポジトリを分析して生成する `AGENTS.md` と `CLAUDE.md` の前半索引に記録します。このリポジトリ自身の公開手順は、次節と公開完遂規約を参照します。公開完遂規約はこのリポジトリ自身の規約であり、配布対象外のため配布先には無い。

## 公開完遂フロー

このリポジトリの変更は、定義の commit、配布先への同期、`origin/main` への push までを完了条件とする。配布先は `~/github-public/agent-toolkit/payload/reverse-docs-skills/` である。同期対象と手順の詳細は公開完遂規約と [RUNBOOK.md](RUNBOOK.md) を定義として参照する。公開完遂規約はこのリポジトリ自身の規約であり、配布対象外のため配布先には無い。
