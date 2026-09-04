---
name: reverse-checking-requirements
日本語名: 要件定義書を裏付ける
description: "要件定義書の機能要件と一覧を突き合わせて機能と単位の対応表を書き、対応の漏れを機械検査する。工程2-2。"
invocation: reverse-checking-requirements
type: check
allowed-tools: [Read, Bash, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/requirements/要件定義書.md, docs/design/lists/*.json]
outputs: [docs/design/lists/機能と単位の対応表.md]
requires: [reverse-listing-units]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-checking-requirements/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

一覧化（`reverse-listing-units`）が完了した後、要件定義書の機能要件と実測した一覧の単位を突き合わせるときに使う。

## いつ使わないか

一覧が無い、または一覧化の完了条件を満たしていないとき。要件定義書そのものを書き直したいとき（道標を描く機能の手順 3 をやり直す）。

## 前提

- 対象リポジトリの `docs/design/requirements/要件定義書.md` と `docs/design/lists/*.json` があること
- 対象リポジトリの `ai-output` の `confirmations/` に承認の記録があること（無ければ止まる。確認は手順 1）
- 要件定義書は本工程では変更しない。変更が要る場合は差し戻し表の「要件-再承認」に従う

## 手順

1. `bash ../reverse-shared/scripts/check-entry.sh <出力の置き場> <対象リポジトリのルート>` を実行し、範囲の承認（可否・道標の同一性）を確かめる。終了コードが 0 でなければ止まり、道標を描く機能の範囲の承認をやり直す
2. 要件定義書の §3 機能要件（機能の一覧の表）・一覧（`docs/design/lists/*.json`）・道標の 4.8「機能のまとめ方」を読む。AI が `docs/design/lists/機能と単位の対応表.md` に対応表を書く
   - 表の列は「機能 | 種別 | 単位の識別子 | 根拠」の 4 列とする
   - 「種別」は一覧の json の「種別」フィールドと同じ表記（screen・api・table・batch・report・external・feature のいずれか）にする
   - 1 つの機能に複数の単位が対応する場合は行を分けて書く
3. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む。続けて `bash scripts/check-requirement-mapping.sh <対象リポジトリのルート> --design-root <設計書の置き場>` を実行する
4. 終了コードを見る。0 なら完了。1 なら不合格の内容（機能-単位なし・単位-機能なし）を読み、対応表を書き直す。対応が付けられない機能・単位は、出力の置き場の `confirmations/確認事項の記録.md` に「種類: 機能と単位の対応」で登録する。やり直しの回数に上限は設けない。同じ不合格が 2 回続いたら、対応表の書き方（機能のまとめ方の粒度など）を変える。要件定義書自体の変更が要ると判断した場合は差し戻し表の「要件-再承認」に従い、工程 1-3（1-5・1-6 を経て）へ差し戻す。要件定義書はこの工程では変更しない

## 完了条件

- 一覧の全単位がいずれかの機能に対応し、機能要件の全機能に 1 つ以上の単位が対応する（`scripts/check-requirement-mapping.sh` が終了コード 0）
- 対応しない項目は確認事項の記録に「種類: 機能と単位の対応」で登録済み
- `tests/` の全件が通る

## 設計判断

### check-requirement-mapping.sh

**必要性**: 機能と単位の対応の抜け漏れ（一覧にあるのに対応表に無い単位、機能要件にあるのに対応表に無い機能）は、目視の突合では見落としが起きやすい。要件定義書と一覧という 2 つの構造化データの集合演算であり、機械で確実に検出できる。対応そのものは業務判断のため AI が作り、本スクリプトは突合の確認だけを担う。

**代替案を採用しなかった理由**:
- AI の目視確認だけに任せる: 再現性が無く、件数が増えると見落としが起きる
- 対応が付かない機能・単位に合わせて要件定義書を書き換える: 本工程は要件定義書を変更しない制約に反する

**保守責任者**: 人手（ユーザー）。対応表・要件定義書の列構成を変えるときは、reverse-drawing-map の要件定義書の様式と本スクリプトと自己テストを同時に直す。

**廃棄条件**: 機能と単位の対応関係を別の構造化データ（データベース等）で機械的に維持する仕組みに変えた時。
