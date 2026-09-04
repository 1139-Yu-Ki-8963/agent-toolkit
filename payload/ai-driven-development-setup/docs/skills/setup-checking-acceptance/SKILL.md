---
name: setup-checking-acceptance
日本語名: 合格の集計
description: "機能の tests を実行し、機能・単位・要件の 3 階層で合格を集計し、欠落 6 つを 0 件で要求する。"
invocation: setup-checking-acceptance
type: transform
allowed-tools: [Bash, Read, Glob, Grep]
unit: setup
category: setup
kind: none
inputs: [docs/skills/*/SKILL.md, docs/skills/*/tests/*.sh, docs/design/requirement-pillars.json]
outputs: [reports/acceptance.md]
requires: [setup-deriving-skills]
acceptance: tests/
---

## いつ使うか

機能を足した・変えた後、体系全体が合格しているかを確かめるとき。単位を納品先へ配る前。

## いつ使わないか

1 機能の tests だけを回すとき（その機能の `tests/` を直接実行する）。

## 手順

1. `scripts/check-acceptance.sh <リポジトリのルート>` を実行する。`--unit <単位>` で単位を絞れる
2. 出力の表（機能・単位・要件の 3 段）と欠落の一覧を読む。終了コード 0 だけを合格とする。欠落は 6 種類（tests無し機能・孤立tests・2単位に属する機能・統括直書きの機能名・他単位の名前を持つ機能・portal以外のhtml出力）。共有部品（名前が `-shared` で終わるフォルダ）の tests は機能に属さないが孤立にはせず、その単位の合格条件に含める
3. 終了コード 1 は不合格または欠落ありを表し、終了コード 2 は tests1 本あたりの上限超過（未確認）が 1 件以上ある、または判定材料が揃わないことを表す。合格でない終了コードはすべて未合格として扱う

## 完了条件

- `scripts/check-acceptance.sh <リポジトリのルート>` が終了コード 0
- `tests/` の全件が通る
