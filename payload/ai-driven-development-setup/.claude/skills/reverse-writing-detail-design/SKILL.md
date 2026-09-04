---
name: reverse-writing-detail-design
日本語名: 詳細設計書を書く
description: "事実・基本設計書・共通処理の詳細設計書を読み、コードと1対1の詳細設計書（表はテーブル定義書）を単位ごとに書き、事実の網羅と基本設計書との整合を機械検査する。工程2-8。"
invocation: reverse-writing-detail-design
type: transform
allowed-tools: [Bash, Read, Glob, Grep, Write]
unit: reverse
category: setup
kind: [screen, api, table, batch, report, external]
inputs: [ai-output/*/*/facts/*/*.json, docs/design/screens/*/基本設計書.md, docs/design/apis/*/基本設計書.md, docs/design/tables/*/基本設計書.md, docs/design/batches/*/基本設計書.md, docs/design/reports/*/基本設計書.md, docs/design/externals/*/基本設計書.md, docs/design/common/共通処理の詳細設計書.md]
outputs: [docs/design/screens/*/詳細設計書.md, docs/design/apis/*/詳細設計書.md, docs/design/batches/*/詳細設計書.md, docs/design/reports/*/詳細設計書.md, docs/design/externals/*/詳細設計書.md, docs/design/tables/*/テーブル定義書.md]
requires: [reverse-writing-common-detail-design]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-writing-detail-design/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

工程2-7（共通処理の詳細設計）が完了条件を満たし、当該単位の基本設計に合格の記録が付いた後、種別ごとに単位ごとへ回して使う。コードと1対1の詳細設計書を書く。

## いつ使わないか

共通処理の詳細設計書がまだ検査を通っていないとき（工程2-7をやり直す）。当該単位に合格の記録が無い、または保留のとき（保留の単位は飛ばす）。機能（種別 feature）の詳細設計を書くとき（機能は詳細設計を持たない）。

## 前提

- 対象リポジトリの `docs/design/common/共通処理の詳細設計書.md` が検査を通っていること
- 対象リポジトリの `ai-work/records/basic-design-acceptance/<種別>-<単位のフォルダ名>.json` に、当該単位の合格の記録があること
- 合格の記録の確認は次のコマンドで行う
  ```bash
  bash ../reverse-shared/scripts/check-acceptance-record.sh <対象リポジトリのルート> --kind <種別> --unit <識別子>
  ```
- 実行フォルダの `facts/<種別>/<単位のフォルダ名>.json` に、当該単位の事実があること（工程2-4の出力）
- 単位の一覧は `../reverse-shared/scripts/list-units-of.sh <対象リポジトリのルート> <種別>` で読む
- 単位のフォルダ名は `../reverse-shared/scripts/unit-dir-name.sh <識別子>` で求める

## 手順

1. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む
2. 次を実行し、終了コードが0であることを確かめる。0でなければ止まり、工程2-7へ差し戻す
   ```bash
   bash ../reverse-writing-common-detail-design/scripts/check-common-detail-design.sh <対象リポジトリのルート> --design-root <設計書の置き場>
   ```
3. 種別ごとに、`bash ../reverse-shared/scripts/list-units-of.sh <対象リポジトリのルート> <種別>` で一覧を得る
4. 単位ごとに次を実行する。終了コードが0でなく、合格の記録の判定が「保留」であればこの単位を飛ばす。保留でなければ止まり、工程2-5・2-6（事実の不足なら工程2-4も）へ差し戻す
   ```bash
   bash ../reverse-shared/scripts/check-acceptance-record.sh <対象リポジトリのルート> --kind <種別> --unit <識別子> --design-root <設計書の置き場>
   ```
5. 種別に対応する `templates/<種別key>/` 配下の様式（後述「種別ごとの様式」表）を、`docs/design/<フォルダ>/<単位のフォルダ名>/` へ複製する
6. 事実（`facts/<種別>/<単位のフォルダ名>.json`）・基本設計書・共通処理の詳細設計書・一覧の属するファイルを読み、様式を埋める。事実の値をそのまま本文に転記し、コードの名前だけの記述にしない。設計の理由は `理由（観測）:`（実測に基づく）／`理由（推定）:`（実測から読み取れない）の形で書く
7. 本文に実装の位置（file:line）を書かない。事実に無い項目が要る場合は「事実-不足」として工程2-4の当該単位へ差し戻す
8. 検査する
   ```bash
   bash scripts/check-detail-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> --design-root <設計書の置き場>
   ```
9. 不合格の項目を手順6からやり直す（工程内-やり直し）。やり直しの回数に上限は設けない。同じ不合格が2回続いたら、同じ方法を繰り返さずに方法を変える
10. 合格した単位ごとに `../reverse-shared/scripts/units-status.sh <実行フォルダ> set <種別> <識別子> 詳細設計 済` を実行する

## 種別ごとの様式

各様式は `templates/<種別key>/` 配下に置く。`<種別key>` は screen・api・table・batch・report・external のいずれか。feature は詳細設計書を持たない。

| 種別 | 様式 |
|---|---|
| screen | `画面/詳細設計/画面詳細設計書.md` |
| api | `API詳細設計書.md` |
| batch | `バッチ詳細設計書.md` |
| report | `帳票詳細設計書.md` |
| external | `外部連携詳細設計書.md` |
| table | `テーブル定義書.md` |

### 事実の項目と転記先の節の目安

節の番号は各様式の見出しに付く§番号を指す。値は事実の値をそのまま転記し、コードの名前だけの記述にしない。

| 種別 | 事実の項目 | 転記先の目安 |
|---|---|---|
| screen | 入力項目 | §10 データ定義・§11 イベント処理 |
| screen | 表示項目 | §3 画面構造・§12 領域別仕様 |
| screen | 操作 | §11 イベント処理 |
| screen | 遷移 | §15 画面遷移仕様 |
| screen | 呼ぶ接続窓口 | §9 API通信仕様 |
| api | 経路 | §1.1 基本情報 |
| api | 入力 | §2 リクエスト |
| api | 出力 | §3 レスポンス |
| api | 検証 | §6 業務ルールとバリデーション |
| api | 呼ぶ処理 | §4 処理フロー |
| api | 触る表 | §4.2 内部呼び出し・§4.3 外部呼び出し |
| batch | 起動条件 | §1 構成要素 |
| batch | 入力 | §4 入出力の値 |
| batch | 出力 | §4 入出力の値 |
| batch | 処理の流れ | §2 処理の定義 |
| report | 出力条件 | §1 構成要素 |
| report | 項目 | §4 入出力の値 |
| report | レイアウトの元 | §2 処理の定義 |
| external | 相手先 | §1 構成要素 |
| external | 形式 | §1 構成要素 |
| external | 項目 | §4 入出力の値 |
| external | 応答 | §4 入出力の値 |
| external | 再試行 | §5 エラー処理 |
| table | 列 | §1 構成要素（カラム定義） |
| table | 関係 | §1 構成要素（外部キー） |
| table | 型・制約 | §1 構成要素 |

## 完了条件

- 保留を除く全単位に詳細設計書（表はテーブル定義書）がある
- 事実ファイルの値が空でない各項目の値が文書本文に現れる（事実の網羅）
- 基本設計書の`### <項目名>`見出しの各項目名が詳細設計書に現れる（基本設計書との整合）
- file:lineが無く、対応するファイルの表が一覧の場所と属するファイルの集合に一致する
- `scripts/check-detail-design.sh` が種別ごとに終了コード0
- `tests/` の全件が通る

## 設計判断

### check-detail-design.sh

**必要性**: 詳細設計書はコードと1対1でなければならず、事実の網羅・対応するファイルの一致・基本設計書との整合という3つの照合は、単位数が対象ごとに違う中で人手で数えると見落とす。

合格の記録の確認（入口）は自前で再実装しない。`reverse-shared` の `check-acceptance-record.sh` に委ねる。単位の一覧と識別子からフォルダ名を得る処理も `reverse-shared` の共有部品に委ねる。こうすることで、判定方法の変更が本スクリプト以外にも及ばないようにする。

**代替案を採用しなかった理由**:
- 事実の網羅を自己レビューだけで確かめる: 単位数・項目数が対象ごとに違うため、見落としが工程2-9（テスト設計）以降まで気付かれない
- 単位のフォルダ名の変換規則を本スクリプトが独自に持つと、`reverse-shared` の `unit-dir-name.sh` と定義が食い違う恐れがある
- 定義が食い違うと、他の機能（`reverse-listing-units` 等）が作るフォルダと一致しなくなる

**保守責任者**: 人手（ユーザー）。様式の見出し構成を変えるときは、`templates/<種別key>/` 配下の様式と本スクリプトと自己テストを同時に直す。

**廃棄条件**: 詳細設計書の様式を構造化データに変えた時。
