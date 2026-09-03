---
name: reverse-writing-basic-design
日本語名: 基本設計書を書く
description: "事実を業務の言葉へ写し、単位ごとの基本設計書と単体テスト設計書を書く。機能は集約設計書だけを書く。"
invocation: reverse-writing-basic-design
type: transform
allowed-tools: [Read, Glob, Grep, Bash, Write]
unit: reverse
category: setup
kind: [screen, api, table, batch, report, external, feature]
inputs: [ai-output/*/*/facts/*/*.json, docs/design/common/業務仕様書.md, docs/design/common/方式設計書.md, docs/design/common/データ設計書.md, docs/design/common/エラー設計書.md, docs/design/common/共通外部仕様書.md, docs/design/common/基盤設計書.md, docs/design/requirements/要件定義書.md, docs/design/lists/機能と単位の対応表.md]
outputs: [docs/design/screens/*/基本設計書.md, docs/design/apis/*/基本設計書.md, docs/design/tables/*/基本設計書.md, docs/design/batches/*/基本設計書.md, docs/design/reports/*/基本設計書.md, docs/design/externals/*/基本設計書.md, docs/design/screens/*/単体テスト設計書.md, docs/design/apis/*/単体テスト設計書.md, docs/design/tables/*/単体テスト設計書.md, docs/design/batches/*/単体テスト設計書.md, docs/design/reports/*/単体テスト設計書.md, docs/design/externals/*/単体テスト設計書.md, docs/design/features/*/集約設計書.md]
requires: [reverse-extracting-facts, reverse-checking-requirements]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-writing-basic-design/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

事実の取り出しと要件定義書の裏付けが終わった後、種別ごとに使う。事実を業務の言葉に写し、基本設計書と単体テスト設計書を書く。

## いつ使わないか

事実がまだ無いとき（先に事実を取り出す機能を使う）。共通設計文書がまだ無いとき。

## 前提

- 実行フォルダを受け取る。対象リポジトリのルートと出力の置き場は `bash ../reverse-shared/scripts/read-run.sh <実行フォルダ> <キー>` で読む
- `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` の終了コードが 0 であること
- 種別ごとの単位一覧は `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で読む。単位のフォルダ名は `bash ../reverse-shared/scripts/unit-dir-name.sh <識別子>` で作る（唯一の定義）
- 単位の事実ファイルが `<実行フォルダ>/facts/<種別>/<単位のフォルダ名>.json` にあること
- 対象に `docs/rules/documentation-standards/document-writing/check-doc-heading-addendum.sh` が配置済みであること
- 対象に `docs/rules/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh` が配置済みであること

## 手順

1. `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` で範囲の承認を確かめる。終了コードが 0 でなければ止まり、道標を描く機能の範囲の承認をやり直す
2. 種別ごとに `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で単位を列挙する
3. 単位ごとに、事実ファイル・共通設計文書・要件定義書・機能と単位の対応表・規約「業務の言葉の決まり」を読む。事実の各項目を業務の言葉に写し、`templates/基本設計書.md` を複製して埋める。事実の項目名はそのまま `### <項目名>` の見出しにする。コードの名前が業務の言葉に写せないときは、用語の追加候補として要確認事項一覧に登録する
4. 同じ単位について `templates/単体テスト設計書.md` を複製して埋める。テストの観点は事実と要件定義書の受入条件から起こす
5. 機能の単位は `templates/集約設計書.md` だけを複製して埋める。基本設計書と単体テスト設計書は書かない
6. `bash scripts/check-basic-design.sh <対象> --run <実行フォルダ> --kind <種別>` を実行する
7. 終了コードを見る。0 なら次の種別へ進む。1 なら不合格の理由を読み、直してから 3 へ戻る。事実に無い項目が設計書に要るときは差し戻し先「事実-不足」として事実を取り出す機能の当該単位へ戻る。同じ不合格が 2 回続いたら書き方を変える
8. 単位が合格したら `bash ../reverse-shared/scripts/units-status.sh <実行フォルダ> set <種別> <識別子> 基本設計 済` を記録する
9. 全種別が終わったら、単位数・合格数・要確認事項の件数を報告する

## 完了条件

- 全単位（機能は集約設計書だけ）に文書がある
- 必須節が順に埋まっている。実装位置（file:line）が無い。未記入のプレースホルダーが無い
- 要確認事項一覧の各キーが確認事項の記録に登録されている
- 事実の各項目が基本設計書に転記されている
- `tests/` の全件が通る

## 設計判断

### check-basic-design.sh

**必要性**: 基本設計書は AI が事実を写して書くため文面は毎回変わる。完了条件（節の順序・位置づけの行・未記入の不在・事実の転記・確認事項の登録）は機械で確かめられる形を持つ。文面を問わず形と実在だけを検査することで、詳細設計へ進んでよいかを判定できる。

**代替案を採用しなかった理由**:
- 自己レビューだけにする: 節の欠落や転記漏れを毎回人手で数えることになる
- 対象の規約検査だけに任せる: 事実の転記や確認事項の登録までは規約検査が知らない

**保守責任者**: 人手（ユーザー）。事実の項目や様式を変えるときは、`docs/design/fact-shapes.json`・`templates/`・本スクリプトを同時に直す。

**廃棄条件**: 基本設計書の様式を構造化データから生成する仕組みに置き換えた時。
