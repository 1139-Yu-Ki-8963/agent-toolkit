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

## いつ使うか

対象リポジトリへ基盤一式を作るとき。単位（setup・reverse・verify・portal）を選んで一括で進めるとき。

## いつ使わないか

1 機能だけを実行するとき（その機能を直接使う）。納品先で日々の開発を回すとき（運用の単位の機能を使う）。

## 手順

0. 前提の確認。AskUserQuestionで次の5項目を確かめる。
   - 対象リポジトリのルート
   - 先方の名前
   - 出力の置き場の親
   - 実行する単位（setup・reverse・verify から複数選べる）
   - 出力の範囲（全部・基本設計まで・一覧まで）

   答えを`scripts/start-run.sh <対象リポジトリのルート> --project-name <先方の名前> --output-root <出力の置き場の親> --units <実行する単位をカンマ区切り> --scope <出力の範囲>`へ渡し、実行フォルダを作る。標準出力に出た実行フォルダのパスを、以降の手順とSTEPで呼ぶ機能へ渡す
1. `scripts/plan-setup.sh <このリポジトリのルート> --units <単位をカンマ区切り> --target <対象リポジトリのルート>`を実行し、実行順の計画を得る。出力の範囲に応じて`--until`を足す。この手順書に機能名を書かず、対応は日本語名で示す。

   | 出力の範囲 | `--until`に渡す機能の日本語名 |
   |---|---|
   | 一覧まで | 一覧を作る |
   | 基本設計まで | 基本設計の完了を判定する |
   | 全部 | 指定しない |

   `--until`には機能名（フォルダ名）を渡す必要があるため、計画の出力（STEPの一覧）と各機能のSKILL.mdのfront matterの日本語名を照合し、対応する機能名を求めてから渡す。

   計画は`STEP <番号> <機能名>`の行と、根拠の表（入力と出力の対応・requires）からなる
2. 計画の各`STEP`を上から順に、その機能名でSkillを呼んで実行する。名前は計画の出力から読む。この手順書に機能名を書かない
3. 各機能の完了条件（そのSKILL.mdの「完了条件」節）を確かめてから次へ進む。満たさなければ止まり、どの機能で止まったかを報告する
4. 全STEPが終わったら、計画の表と各機能の結果を`reports/setup-plan.md`へ書く

## 完了条件

- `scripts/start-run.sh` が終了コード 0 で実行フォルダを作る
- `scripts/plan-setup.sh` が終了コード 0 で計画を返す（循環や未解決の入力があれば終了コード 1 で止まる。`--until`の対象不在は終了コード2）
- 全 STEP の機能がそれぞれの完了条件を満たす
- `tests/` の全件が通る
