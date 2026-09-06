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
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/setup-deriving-skills/ にある（この配布物には含まれない）。直接編集しないこと -->

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

## 設計判断

`tests/test-self-tests.sh` は、本機能自身のスクリプトに加え、`docs/rules/*/*/check-*.sh`（規約の置き場にある検査）の `--self-test` も走らせる。`*.test.sh` は checker へ `--self-test` を渡すだけの薄い入口であり、二重実行を避けるため対象から外す。名前の決まり（`check-skill-naming.sh`）のように規約の置き場に自己テストを持つ検査は、docs/skills 配下の機能の tests として登録されない。ここから呼ばない限り機能の自己テストの走行に含まれない（第1回改善指示書 1-26）。
