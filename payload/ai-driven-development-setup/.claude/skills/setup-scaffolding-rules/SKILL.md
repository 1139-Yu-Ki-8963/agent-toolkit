---
name: setup-scaffolding-rules
日本語名: 規約の配置
description: "対象リポジトリの docs/rules へ、親7件・子32件の規約の定義と検査スクリプトを配置する。"
invocation: setup-scaffolding-rules
type: transform
allowed-tools: [Bash, Read, Glob, Grep]
unit: setup
category: setup
kind: none
inputs: [references/rule-taxonomy.json, templates/rules/**]
outputs: [docs/rules/*/parent.yml, docs/rules/*/*/rule.md, docs/rules/*/*/*.sh]
requires: []
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/setup-scaffolding-rules/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

対象リポジトリに規約の定義（`docs/rules`）が無い、または未整備のとき。配置の後に規約の派生（`setup-deriving-rules`）を実行する。

## いつ使わないか

規約の本文を対象リポジトリの実装から起こすとき（リバースの機能が担う）。派生物を作るとき（規約の派生が担う）。

## 手順

1. `scripts/scaffold-rule-definitions.sh <対象リポジトリのルート>` で配置予定を確かめる（書き込みなし）
2. `scripts/scaffold-rule-definitions.sh <対象リポジトリのルート> --apply` で配置する。既存の `parent.yml`・`design-notes.md` と、現場が書き足した「このプロジェクトの規則」節は上書きしない
3. 配置後は規約の派生の手順に従い、`--taxonomy references/rule-taxonomy.json` を渡して検査し派生する

## 完了条件

- 手順 2 の後、対象の `docs/rules` に親 7 件の `parent.yml` と子 32 件の `rule.md` がある
- 対象で規約の派生の検査（validate-rule-definitions.sh）が終了コード 0
- `tests/` の全件が通る
