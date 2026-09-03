---
name: reverse-checking-basic-phase
日本語名: 基本設計の完了を判定する
description: "全単位の基本設計書と共通設計文書が完了状態の観点を満たすことを確かめ、合格の記録を書く。"
invocation: reverse-checking-basic-phase
type: check
allowed-tools: [Read, Glob, Grep, Bash, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/features/*/集約設計書.md, docs/design/common/業務仕様書.md, docs/design/common/方式設計書.md, docs/design/common/データ設計書.md, docs/design/common/エラー設計書.md, docs/design/common/共通外部仕様書.md, docs/design/common/基盤設計書.md]
outputs: [ai-work/records/basic-design-acceptance/*.json]
requires: [reverse-writing-basic-design, reverse-writing-foundation-guides]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-checking-basic-phase/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

全種別の基本設計書と単体テスト設計書、共通設計文書6つが書き終わった後に使う。共通処理の詳細設計へ進んでよいかを判定する。

## いつ使わないか

基本設計書や共通設計文書がまだ書き終わっていないとき。

## 前提

- 実行フォルダを受け取る。対象リポジトリのルートは `bash ../reverse-shared/scripts/read-run.sh <実行フォルダ> 対象リポジトリ` で読む
- `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` の終了コードが 0 であること
- `references/basic-phase-viewpoints.md` の6観点を先に読む

## 手順

1. `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` で範囲の承認を確かめる
2. 全種別の全単位と共通設計文書6つを機械検査し、`<実行フォルダ>/logs/basic-phase-check.json` に結果を書く
   ```bash
   bash scripts/check-basic-phase.sh <対象> --run <実行フォルダ>
   ```
3. 機械検査を通った単位・文書ごとに、文書のレビュー担当（AI）が `references/basic-phase-viewpoints.md` の6観点で読む
4. 単位ごとに次を実行して記録する
   ```bash
   bash scripts/record-acceptance.sh <対象> --run <実行フォルダ> --kind <種別> --unit <識別子> --verdict <合格|不合格|保留> --viewpoints "<観点=合|否;...>" [--reason "<理由>"]
   ```
5. 共通設計文書ごとに次を実行して記録する
   ```bash
   bash scripts/record-acceptance.sh <対象> --run <実行フォルダ> --common <文書名> --verdict <合格|不合格|保留> --viewpoints "<観点=合|否;...>" [--reason "<理由>"]
   ```
6. 不合格は差し戻し表のとおり戻す。単位の不合格は基本設計を書く機能の当該単位へ、共通設計文書に起因する不合格は道標を描く機能の手順4へ戻り、以後の検査と承認を経る
7. 保留は既定を置けない不明点を持つ単位・文書だけにする。理由を確認事項に登録する
8. 保留を除く全単位と共通設計文書6つに合格の記録があることを確かめて終える

## 完了条件

- 保留を除く全単位と共通設計文書6つに合格の記録がある
- 既定を置けない不明点を持つ単位が保留として記録されている
- `bash scripts/check-acceptance-record.sh <対象> --kind <種別> --unit <識別子>` および `--common` が対象の記録に対して 0 を返す
- `tests/` の全件が通る

## 設計判断

### check-basic-phase.sh

**必要性**: 基本設計の完了判定は単位数が多く、機械で読める部分（文書の様式・見出し・事実の転記）を先に検査してからでないと、文書のレビュー担当が毎回同じ形式不備を読むことになる。機械検査を先に集約することで、レビュー担当は内容の判断だけに集中できる。

**代替案を採用しなかった理由**:
- レビュー担当が毎回様式も読む: 同じ様式不備を繰り返し見つけることになる
- 単位ごとに個別のスクリプトを持つ: 基本設計書を書く機能の検査（check-basic-design.sh）と重複する

**保守責任者**: 人手（ユーザー）。共通設計文書の一覧を変えるときは、本スクリプトと道標を描く機能の様式を同時に直す。

**廃棄条件**: 完了判定を別の仕組みに置き換えた時。

### record-acceptance.sh

**必要性**: 合格の記録は文書の同一性（sha256）とコミットを持たなければ、後から文書が変わったときに古い合格が生き残ってしまう。記録の形を1つに決め、詳細設計へ進む機能（check-acceptance-record.sh）がその形だけを読めば済むようにする。

**代替案を採用しなかった理由**:
- 合格をログにだけ書く: 文書の変更を検知できず、古い合格のまま詳細設計に進んでしまう
- 単位ごとに別々の形で記録する: 詳細設計を書く機能が形ごとに読み方を変える必要が出る

**保守責任者**: 人手（ユーザー）。記録の形（キー）を変えるときは、本スクリプトと check-acceptance-record.sh を同時に直す。

**廃棄条件**: 合格の記録を別の仕組みに置き換えた時。

### check-acceptance-record.sh

**必要性**: 共通処理の詳細設計と単位の詳細設計は、合格の記録が現在の文書と一致することを入口で確かめないと、書き直された基本設計書に古い合格のまま詳細設計を進めてしまう。

**代替案を採用しなかった理由**:
- 詳細設計を書く機能が記録を直接読む: 合格記録の形の変更のたびに複数の機能を直す必要が出る

**保守責任者**: 人手（ユーザー）。共通設計文書6つの名前を変えるときは、本スクリプトを同時に直す。

**廃棄条件**: 合格の記録を別の仕組みに置き換えた時。
