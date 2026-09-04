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
inputs: [docs/skills/*/SKILL.md, docs/skills/*/tests/*.sh, docs/design/requirements/requirement-pillars.json]
outputs: [reports/setup-plan.md, ai-output/*/*/run.json, reports/acceptance.md]
requires: []
acceptance: tests/
---

## いつ使うか

対象リポジトリへ基盤一式を作るとき。単位（setup・reverse・verify・portal）を選んで一括で進めるとき。

## いつ使わないか

1 機能だけを実行するとき（その機能を直接使う）。納品先で日々の開発を回すとき（運用の単位の機能を使う）。

## 手順

0. 前提の確認。AskUserQuestionで次の5項目を確かめる。
   - 作業場所（必須。対象コードの場所と出力の置き場の親を兼ねる1つのフォルダ）
   - 先方の名前
   - 設計書の展開先（先方リポジトリへ展開する／作業場所だけに置く。展開するときだけ先方リポジトリのルートを併せて聞く）
   - 実行する単位（setup・reverse・verify から複数選べる）
   - 出力の範囲（全部・基本設計・一覧 のいずれかまで）

   答えを`scripts/start-run.sh`へ渡し、実行フォルダを作る。渡す引数は`<作業場所> --project-name <先方の名前> --output-root <作業場所> --units <単位のカンマ区切り> --scope <出力の範囲>`である。設計書の展開先が「先方リポジトリへ展開する」なら`--deploy-to <先方リポジトリのルート>`を足す。標準出力に出た実行フォルダのパスを渡す。渡す先は、以降の手順とSTEPで呼ぶ機能である。

   実行する単位に reverse が含まれるときは、以降の手順をこの統括では行わず「リバースの統括」（reverse単位の機能）へ委譲する。実行フォルダのパスを渡して呼ぶ。setupの統括はsetup単位の機能だけを自分で回す。
1. `scripts/plan-setup.sh <このリポジトリのルート> --units <単位をカンマ区切り> --target <対象リポジトリのルート>`を実行し、実行順の計画を得る。出力の範囲に応じて`--until`を足す。この手順書に機能名を書かず、対応は日本語名で示す。

   | 出力の範囲 | `--until`に渡す機能の日本語名 |
   |---|---|
   | 一覧まで | 一覧を作る |
   | 基本設計まで | 基本設計書を書く |
   | 全部 | 指定しない |

   `--until`には機能名（フォルダ名）を渡す必要があるため、計画の出力（STEPの一覧）と各機能のSKILL.mdのfront matterの日本語名を照合し、対応する機能名を求めてから渡す。

   計画は`STEP <番号> <機能名>`の行と、根拠の表（入力と出力の対応・requires）からなる
2. 計画の各`STEP`を上から順に、その機能名でSkillを呼んで実行する。名前は計画の出力から読む。この手順書に機能名を書かない
3. 各機能の完了条件（そのSKILL.mdの「完了条件」節）を確かめてから次へ進む。満たさなければ止まり、どの機能で止まったかを報告する
4. 全STEPが終わったら、計画の表と各機能の結果を`reports/setup-plan.md`へ書く

## 完了時の処理

全STEPが終わったら、`scripts/check-acceptance.sh <このリポジトリのルート> [--unit <単位>]`を実行する。
docs/skills配下の全機能のtestsを回し、機能・単位・要件（柱）の3段で合格を集計する。
欠落は6種類（tests無し機能・孤立tests・2単位に属する機能・統括直書きの機能名・他単位の名前を持つ機能・portal以外のhtml出力）で、いずれも0件を求める。
共有部品（名前が`-shared`で終わるフォルダ）のtestsは機能に属さないが孤立にはせず、その単位の合格条件に含める。
結果を`reports/acceptance.md`へ書く。
終了コード0だけを合格とする（1は不合格または欠落あり、2は未確認1件以上または判定材料不足）。

詳細設計へ進む前の門（合格の記録が揃っているかの確認）は、reverse単位の機能へ委譲した時点で「リバースの統括」の手順が担う。本機能はこの門を持たない。

## 完了条件

- `scripts/start-run.sh` が終了コード 0 で実行フォルダを作る
- `scripts/plan-setup.sh` が終了コード 0 で計画を返す（循環や未解決の入力があれば終了コード 1 で止まる。`--until`の対象不在は終了コード2）
- 全 STEP の機能がそれぞれの完了条件を満たす
- `scripts/check-acceptance.sh` が終了コード 0 で機能・単位・要件の合格を返す
- `tests/` の全件が通る

## 設計判断

`scripts/check-acceptance.sh`は元は検査だけの独立した機能だった。
完了の検査は独立した機能ではなく統括の完了時の処理であるという方針により、本機能へ`git mv`で移した。
判定の中身（front matter読み取り・6つの欠落検査・柱の集計）は変えていない。
