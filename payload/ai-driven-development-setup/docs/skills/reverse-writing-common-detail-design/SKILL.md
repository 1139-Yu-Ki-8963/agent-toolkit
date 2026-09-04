---
name: reverse-writing-common-detail-design
日本語名: 共通処理の詳細設計書を書く
description: "道標の共通方式の場所とその実装を読み、共通処理の詳細設計書を方式ごとに書き、位置づけ・未記入・file:lineを機械検査する。工程2-7。"
invocation: reverse-writing-common-detail-design
type: transform
allowed-tools: [Bash, Read, Glob, Grep, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/common/道標.md, ai-work/records/basic-design-acceptance/common-*.json]
outputs: [docs/design/common/共通処理の詳細設計書.md]
requires: [reverse-writing-basic-design]
acceptance: tests/
---

## いつ使うか

工程2-6（基本設計の完了判定）で保留を除く全単位と共通設計文書に合格の記録が付いた後、単位ごとの詳細設計より先に使う。基盤層と共通部品の詳細設計書を書く。

## いつ使わないか

共通設計文書の合格の記録が無いとき（工程2-6をやり直す）。単位ごとの詳細設計を書くとき（`reverse-writing-detail-design` を使う）。

## 前提

- 対象リポジトリの `docs/design/common/道標.md` の節7「共通方式の場所」に、方式ごとの実装の場所（複数のパスは `;` 区切り）があること
- 対象リポジトリの `ai-work/records/basic-design-acceptance/common-*.json` に、共通設計文書の合格の記録があること。確認は `../reverse-shared/scripts/check-acceptance-record.sh <対象リポジトリのルート> --common` で行う
- 実行フォルダ（統括の実行の開始スクリプトが作る）は使わない。共通処理の詳細設計書は対象リポジトリの `docs/design/common/` に直接書く

## 手順

1. 次を実行し、終了コードが0であることを確かめる。0でなければ止まり、工程2-6（基本設計の完了判定）へ差し戻す
   ```bash
   bash ../reverse-shared/scripts/check-acceptance-record.sh <対象リポジトリのルート> --common
   ```
2. `templates/共通処理の詳細設計書.md` を `docs/design/common/共通処理の詳細設計書.md` へ複製する
3. 道標の節7の方式のうち、実装の場所が「なし」でないものだけを残す（「なし」の方式の節は削除する）
4. 各節について、道標の節7が指す実装（共通方式の実装）を読み、6つの小節（クラス設計・メソッド設計・ロジック設計・戻り値と引数・エラー処理・データ定義）を埋める。各節の位置づけ（仕様・現行実装・仕様／現行実装）の行を実測に応じて改める
5. 本文に実装の位置（file:line）を書かない。仕様か現行実装かを決められない節は、既定を付けて要確認事項一覧に書き、確認事項に登録する
6. 検査する
   ```bash
   bash scripts/check-common-detail-design.sh <対象リポジトリのルート>
   ```
7. 不合格の項目を手順4からやり直す（工程内-やり直し）。やり直しの回数に上限は設けない。同じ不合格が2回続いたら、同じ方法を繰り返さずに方法を変える

## 完了条件

- 実装の場所が「なし」でない方式に対応する節がすべてある
- 各節に位置づけの行と6つの小節がある
- file:lineが無く、未記入のプレースホルダーが無く、追記の見出しが無い
- `scripts/check-common-detail-design.sh` が終了コード0
- `tests/` の全件が通る

## 設計判断

### check-common-detail-design.sh

**必要性**: 共通処理の詳細設計書は道標の節7に対応する節をすべて持たなければならない。方式の数と場所は対象ごとに違うため、機械で道標を読み、節の欠落・位置づけの欠落・小節の欠落・未記入・file:lineを一括で確かめる必要がある。

判定方法の入口（合格の記録の有無）は自前で再実装しない。`reverse-shared` の `check-acceptance-record.sh` に委ねることで、合格の記録の形が変わっても本スクリプトを直さずに済む。

**代替案を採用しなかった理由**:
- 手順書の注意書きだけにする: 方式の数が対象ごとに違うため、節の書き漏れが後工程（単位の詳細設計）で初めて見つかる
- 合格の記録の判定を本スクリプトが再実装する: 判定方法が2箇所に分散し、記録の形を変えるたびに2箇所を直すことになる

**保守責任者**: 人手（ユーザー）。10方式の一覧・6小節の名前を変えるときは、`templates/共通処理の詳細設計書.md` と本スクリプトと自己テストを同時に直す。

**廃棄条件**: 共通処理の詳細設計書の様式を構造化データに変えた時。
