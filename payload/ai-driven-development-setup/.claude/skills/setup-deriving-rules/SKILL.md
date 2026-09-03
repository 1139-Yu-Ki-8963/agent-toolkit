---
name: setup-deriving-rules
日本語名: 規約の派生
description: "docs/rules の規約の定義から .claude/rules・.cursor/rules・AGENTS.md の索引・hooks の登録を生成する。"
invocation: setup-deriving-rules
type: transform
allowed-tools: [Bash, Read, Glob, Grep]
unit: setup
category: setup
kind: none
inputs: [docs/rules/*/parent.yml, docs/rules/*/*/rule.md]
outputs: [.claude/rules/**/rule.md, .cursor/rules/*.mdc, AGENTS.md, .claude/settings.json, .cursor/hooks.json, .codex/config.toml]
requires: []
acceptance: tests/
---
<!-- 生成物: docs/skills/setup-deriving-rules/SKILL.md から自動生成。直接編集しないこと -->

## いつ使うか

規約の定義（`docs/rules`）を追加・変更した後、派生物を作り直すとき。納品先へ規約を配置した後、納品先で派生物を作るとき。

## いつ使わないか

規約の本文を書くとき（定義を直接編集する）。派生物を直接直したいとき（禁止。定義を直して派生し直す）。

## 手順

1. `scripts/validate-rule-definitions.sh <docs/rules のルート> [--taxonomy <分類定義のパス>]` で定義の形を検査する。不合格なら止まる。`--taxonomy` は任意で、指定した場合だけ checker 宣言の網羅を検査する
2. `scripts/build-derived-rules.sh <docs/rules のルート> <リポジトリのルート>` で生成予定を確かめる（書き込みなし）
3. `scripts/build-derived-rules.sh <docs/rules のルート> <リポジトリのルート> --apply` で派生物を書く
4. `scripts/check-rule-drift.sh <docs/rules のルート> <リポジトリのルート>` で定義と派生物のずれが無いことを確かめる

## 完了条件

- 手順 1 が終了コード 0
- 手順 4 が終了コード 0
- `tests/` の全件が通る
