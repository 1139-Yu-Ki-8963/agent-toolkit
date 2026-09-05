---
name: reverse-writing-test-designs
日本語名: テスト設計書を書く
description: "テスト設計書の出力が「出力する」のとき、基本設計書・詳細設計書・単体テスト設計書・要件定義書の受入条件を読み、種別内結合テスト設計書と種別横断結合テスト設計書を書き、節の順序・未記入・観点キーの整合を機械検査する。工程2-9。"
invocation: reverse-writing-test-designs
type: transform
allowed-tools: [Bash, Read, Glob, Grep, Write]
unit: reverse
category: setup
kind: none
inputs: [docs/design/requirements/要件定義書.md, docs/design/screens/*/画面/基本設計/画面基本設計書.md, docs/design/apis/*/API基本設計書.md, docs/design/tables/*/論理データモデル.md, docs/design/batches/*/バッチ基本設計書.md, docs/design/reports/*/帳票基本設計書.md, docs/design/externals/*/外部連携基本設計書.md, docs/design/features/*/機能設計書.md, docs/design/lists/*.json]
outputs: [docs/design/screens/画面結合テスト設計書.md, docs/design/apis/API結合テスト設計書.md, docs/design/tables/テーブル結合テスト設計書.md, docs/design/batches/バッチ結合テスト設計書.md, docs/design/reports/帳票結合テスト設計書.md, docs/design/externals/外部連携結合テスト設計書.md, docs/design/features/機能結合テスト設計書.md, docs/design/common/種別横断結合テスト設計書.md]
requires: [reverse-writing-detail-design]
---

## いつ使うか

工程2-8（単位の詳細設計）が完了条件を満たした後、テスト設計書の出力が「出力する」のときだけ使う。種別ごとの単位どうしのつながりと、種別をまたぐ流れを検証するテスト設計書を書く。

## いつ使わないか

テスト設計書の出力が「出力しない」のとき（何もせず終える）。単位ごとの入出力・エラー処理を検証するとき（単体テスト設計書は基本設計書を書く機能が対で書く）。

## 前提

- 実行フォルダを受け取る。テスト設計書の出力は `bash ../reverse-shared/scripts/read-run.sh <実行フォルダ> テスト設計書の出力` で読む
- 設計書の置き場は `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で読む
- 種別ごとの単位一覧は `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で読む

## 手順

1. `bash ../reverse-shared/scripts/read-run.sh <実行フォルダ> テスト設計書の出力` を読む。「出力しない」なら「テスト設計書の出力が出力しないのため何も作らない」と標準出力に書き、終了コード0で終える
2. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む
3. 種別ごとに `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で単位を列挙する。単位が1つ以上ある種別について `templates/種別内結合テスト設計書.md` を `docs/design/<種別フォルダ>/<種別名>結合テスト設計書.md` へ複製して埋める。単位間のつながりは詳細設計書と読み取り結果から起こす。単位が無い種別は作らない
4. `templates/種別横断結合テスト設計書.md` を `docs/design/common/種別横断結合テスト設計書.md` へ複製して埋める。§1テスト観点表は要件定義書の受入条件の各項を1行以上持ち、§2テストケース一覧は§1の全観点に1件以上対応させる
5. `bash scripts/check-test-designs.sh <対象> --run <実行フォルダ> --design-root <設計書の置き場>` を実行する
6. 不合格の理由が名指しする項目を、基本設計書・詳細設計書・要件定義書の受入条件を再度読んで書き出し、手順3または4へ戻る。理由に無い箇所は変えない。欠けが無くなるまで回数の上限なく戻る
7. 単位の状態は `units-status.sh` で種別ごとに記録する。工程一覧（読み取り結果・基本設計・完了判定・詳細設計）に「テスト設計」のキーが無いため、記録は省き、完了時の報告に含める

## 種別と置き場の対応

| 種別 | 種別フォルダ | 種別名 | 種別内結合テスト設計書の置き場 |
|---|---|---|---|
| screen | screens | 画面 | `docs/design/screens/画面結合テスト設計書.md` |
| api | apis | API | `docs/design/apis/API結合テスト設計書.md` |
| table | tables | テーブル | `docs/design/tables/テーブル結合テスト設計書.md` |
| batch | batches | バッチ | `docs/design/batches/バッチ結合テスト設計書.md` |
| report | reports | 帳票 | `docs/design/reports/帳票結合テスト設計書.md` |
| external | externals | 外部連携 | `docs/design/externals/外部連携結合テスト設計書.md` |
| feature | features | 機能 | `docs/design/features/機能結合テスト設計書.md` |

種別横断結合テスト設計書は種別によらず1冊、`docs/design/common/種別横断結合テスト設計書.md` に置く。

## 完了条件

- テスト設計書の出力が「出力しない」なら何も作らずに終える
- 単位が1つ以上ある種別すべてに種別内結合テスト設計書がある
- 種別横断結合テスト設計書があり、§1の全観点に§2のケースが対応し、§4が受入条件を1行以上持つ
- 節の順序・件数が様式と一致し、位置づけの行があり、未記入のプレースホルダーとfile:lineが無い
- `scripts/check-test-designs.sh` が終了コード0

## 設計判断

### check-test-designs.sh

**必要性**: 種別内結合テスト設計書は単位が1つ以上ある種別すべてに要り、種別横断結合テスト設計書は観点とケースと受入条件の対応が要る。対象ごとに単位の有無・種別の数・受入条件の件数が違うため、機械で節の欠落・観点キーの不整合・未記入・file:lineを一括で確かめる必要がある。

**代替案を採用しなかった理由**:
- 手順書の注意書きだけにする: 種別の数が対象ごとに違うため、種別内結合テスト設計書の作り忘れが後工程まで見つからない
- 単体テスト設計書の検査（check-unit-test-design-doc-sections.sh）を流用する: あちらは単位ごとの単体テスト設計書の様式（12節または13節）を検査する専用であり、種別内結合・種別横断結合という別の様式（単位間のつながり・種別をまたぐ流れ・受入条件との対応を持つ）を検査する責務を持たない

**保守責任者**: 人手（ユーザー）。7種別の一覧・節の名前を変えるときは、`templates/種別内結合テスト設計書.md`・`templates/種別横断結合テスト設計書.md`と本スクリプトと自己テストを同時に直す。

**廃棄条件**: テスト設計書の様式を構造化データに変えた時。
