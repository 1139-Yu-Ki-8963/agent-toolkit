---
name: setup-deriving-skills
日本語名: 機能の派生
description: "docs/skills の機能の定義を検査し、.claude/skills へ派生させる。"
invocation: setup-deriving-skills
type: transform
allowed-tools: [Bash, Read, Glob, Grep]
unit: setup
category: setup
kind: none
inputs: [docs/skills/*/SKILL.md]
outputs: [.claude/skills/*/SKILL.md]
requires: []
acceptance: tests/
---
<!-- 生成物: docs/skills/setup-deriving-skills/SKILL.md から自動生成。直接編集しないこと -->

## いつ使うか

機能の定義（`docs/skills`）を追加・変更した後、`.claude/skills` を作り直すとき。

## いつ使わないか

機能の本文を書くとき（定義を直接編集する）。派生物を直接直したいとき（禁止。定義を直して派生し直す）。

## 手順

1. `scripts/validate-skill-definitions.sh <docs/skills のルート>` で定義の形と欠落を検査する。不合格なら止まる
2. `scripts/build-derived-skills.sh <docs/skills のルート> <リポジトリのルート>` で生成予定を確かめる（書き込みなし）
3. `scripts/build-derived-skills.sh <docs/skills のルート> <リポジトリのルート> --apply` で派生物を書く
4. `scripts/check-skill-drift.sh <docs/skills のルート> <リポジトリのルート>` で定義と派生物のずれが無いことを確かめる

## 完了条件

- 手順 1 が終了コード 0
- 手順 4 が終了コード 0
- `tests/` の全件が通る
