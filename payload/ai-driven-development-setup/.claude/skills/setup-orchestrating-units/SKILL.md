---
name: setup-orchestrating-units
日本語名: セットアップの統括
description: "機能の宣言を読んで実行順を組み立て、選んだ単位の機能を順に実行して対象リポジトリへ基盤一式を作る。"
invocation: setup-orchestrating-units
type: orchestration
allowed-tools: [Bash, Read, Glob, Grep, Skill, AskUserQuestion]
unit: setup
category: setup
kind: none
inputs: [docs/skills/*/SKILL.md]
outputs: [reports/setup-plan.md, ai-output/*/*/run.json]
requires: []
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/setup-orchestrating-units/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

対象リポジトリへ基盤一式を作るとき。単位（setup・reverse・verify・portal）を選んで一括で進めるとき。

## いつ使わないか

1 機能だけを実行するとき（その機能を直接使う）。納品先で日々の開発を回すとき（運用の単位の機能を使う）。

## 手順

0. `scripts/start-run.sh <対象リポジトリのルート> --project-name <先方の名前> --output-root <出力の置き場の親>` を実行し、実行フォルダを作る。標準出力に出た実行フォルダのパスを、以降の手順とSTEPで呼ぶ機能へ渡す
1. `scripts/plan-setup.sh <このリポジトリのルート> --units <単位をカンマ区切り> --target <対象リポジトリのルート>` を実行し、実行順の計画を得る。計画は `STEP <番号> <機能名>` の行と、根拠の表（入力と出力の対応・requires）からなる
2. 計画の各 `STEP` を上から順に、その機能名で Skill を呼んで実行する。名前は計画の出力から読む。この手順書に機能名を書かない
3. 各機能の完了条件（その SKILL.md の「完了条件」節）を確かめてから次へ進む。満たさなければ止まり、どの機能で止まったかを報告する
4. 全 STEP が終わったら、計画の表と各機能の結果を `reports/setup-plan.md` へ書く

## 完了条件

- `scripts/start-run.sh` が終了コード 0 で実行フォルダを作る
- `scripts/plan-setup.sh` が終了コード 0 で計画を返す（循環や未解決の入力があれば終了コード 1 で止まる）
- 全 STEP の機能がそれぞれの完了条件を満たす
- `tests/` の全件が通る
