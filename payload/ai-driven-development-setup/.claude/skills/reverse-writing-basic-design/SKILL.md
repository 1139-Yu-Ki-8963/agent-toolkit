---
name: reverse-writing-basic-design
日本語名: 基本設計書を書く
description: "読み取り結果を業務の言葉へ写し、種別ごとの様式で基本設計書と単体テスト設計書を書く。"
invocation: reverse-writing-basic-design
type: transform
allowed-tools: [Read, Glob, Grep, Bash, Write]
unit: reverse
category: setup
kind: [screen, api, table, batch, report, external, feature]
inputs: [ai-output/*/*/code-readings/*/*.json, docs/design/common/調査と検出条件の定義書.md, docs/design/common/業務仕様書.md, docs/design/common/方式設計書.md, docs/design/common/データ設計書.md, docs/design/common/エラー設計書.md, docs/design/common/共通外部仕様書.md, docs/design/common/基盤設計書.md, docs/design/requirements/要件定義書.md, docs/design/lists/機能と単位の対応表.md]
outputs: [docs/design/screens/*/画面/基本設計/画面基本設計書.md, docs/design/screens/*/画面/テスト設計/画面単体テスト設計書.md, docs/design/apis/*/API基本設計書.md, docs/design/apis/*/API単体テスト設計書.md, docs/design/tables/*/論理データモデル.md, docs/design/tables/*/テーブル単体テスト設計書.md, docs/design/batches/*/バッチ基本設計書.md, docs/design/batches/*/バッチ単体テスト設計書.md, docs/design/reports/*/帳票基本設計書.md, docs/design/reports/*/帳票単体テスト設計書.md, docs/design/externals/*/外部連携基本設計書.md, docs/design/externals/*/外部連携単体テスト設計書.md, docs/design/features/*/機能設計書.md, docs/design/features/*/機能単体テスト設計書.md, ai-work/records/basic-design-acceptance/*.json]
requires: [reverse-extracting-code-readings, reverse-listing-units]
acceptance: tests/
---
<!-- 生成物: 定義は支援ツールの正本リポジトリの docs/skills/reverse-writing-basic-design/ にある（この配布物には含まれない）。直接編集しないこと -->

## いつ使うか

読み取り結果の取り出しと要件定義書の裏付けが終わった後、種別ごとに使う。読み取り結果を業務の言葉に写し、基本設計書と単体テスト設計書を書く。

## いつ使わないか

読み取り結果がまだ無いとき（先に読み取り結果を取り出す機能を使う）。共通設計文書がまだ無いとき。

## 前提

- 実行フォルダを受け取る。対象リポジトリのルートと出力の置き場は `bash ../reverse-shared/scripts/read-run.sh <実行フォルダ> <キー>` で読む
- `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` の終了コードが 0 であること
- 種別ごとの単位一覧は `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で読む。単位のフォルダ名は `bash ../reverse-shared/scripts/unit-dir-name.sh <識別子>` で作る（唯一の定義）
- 単位の読み取り結果ファイルが `<実行フォルダ>/code-readings/<種別>/<単位のフォルダ名>.json` にあること
- 完了時の処理の前に `references/basic-phase-viewpoints.md` の6観点を読む
- 検査は共有部品の写しで行う。ファイルは `../reverse-shared/scripts/check-doc-heading-addendum.sh` にある。もう1つは `check-unit-test-design-doc-sections.sh` にある。対象に規約の配置は求めない

## 手順

1. `bash ../reverse-shared/scripts/check-entry.sh <実行フォルダ> <対象リポジトリのルート>` で範囲の承認を確かめる。終了コードが 0 でなければ止まり、調査と検出条件の定義書を描く機能の範囲の承認をやり直す
2. `bash ../reverse-shared/scripts/design-root.sh <実行フォルダ>` で設計書の置き場を読む
3. 種別ごとに `bash ../reverse-shared/scripts/list-units-of.sh <対象> <種別>` で単位を列挙する
4. 単位ごとに、読み取り結果ファイル・共通設計文書・要件定義書・機能と単位の対応表・調査と検出条件の定義書の節 8（用語の候補）を読む。種別に対応する `templates/<種別key>/` 配下の様式（後述「種別ごとの様式」表）を複製して埋める。読み取り結果の各項目を業務の言葉に写し、読み取り結果の項目名はそのまま `### <項目名>` の見出しにする。コードの名前が業務の言葉に写せないときは、用語の追加候補として要確認事項一覧に登録する。記述は後述「記述の3区分」に従い分ける
5. 同じ単位について、種別に対応する単体テスト設計書の様式を複製して埋める。テストの観点は読み取り結果と要件定義書の受入条件から起こす
6. 埋め終えたら後述「実装用語の混入検査」の種別ごとの検出パターンで grep する。検出0件になるまで該当箇所を業務語彙へ書き直す
7. `bash scripts/check-basic-design.sh <対象> --run <実行フォルダ> --kind <種別> --design-root <設計書の置き場>` を実行する
8. 終了コードを見る。0 なら次の種別へ進む。1 なら不合格の理由を読み、直してから 4 へ戻る。読み取り結果に無い項目が設計書に要るときは差し戻し先「読み取り結果-不足」として読み取り結果を取り出す機能の当該単位へ戻る。同じ不合格が 2 回続いたら書き方を変える
9. 単位が合格したら `bash ../reverse-shared/scripts/units-status.sh <実行フォルダ> set <種別> <識別子> 基本設計 済` を記録する
10. 完了時の処理として、単位ごとに文書のレビュー担当（AI）が `references/basic-phase-viewpoints.md` の6観点で基本設計書と単体テスト設計書を読む。合否を判定し、合格・不合格・保留のいずれかを次で記録する
    ```bash
    bash ../reverse-shared/scripts/record-acceptance.sh <対象> --run <実行フォルダ> --kind <種別> --unit <識別子> --verdict <合格|不合格|保留> --viewpoints "<観点=合|否;...>" [--reason "<理由>"] --design-root <設計書の置き場>
    ```
    不合格は 4 へ戻る。保留は既定を置けない不明点を持つ単位だけにし、理由を確認事項に登録する
11. 全種別が終わったら、単位数・合格数・保留数・要確認事項の件数を報告する


## 種別ごとの転記規則

### 種別ごとの様式

各様式は `templates/<種別key>/` 配下に置く。`<種別key>` は screen・api・table・batch・report・external・feature のいずれか。

| 種別 | 基本設計書の様式 | 単体テスト設計書の様式 |
|---|---|---|
| screen | `画面/基本設計/画面基本設計書.md` | `画面/テスト設計/画面単体テスト設計書.md` |
| api | `API基本設計書.md` | `API単体テスト設計書.md` |
| batch | `バッチ基本設計書.md` | `バッチ単体テスト設計書.md` |
| report | `帳票基本設計書.md` | `帳票単体テスト設計書.md` |
| external | `外部連携基本設計書.md` | `外部連携単体テスト設計書.md` |
| table | `論理データモデル.md` | `テーブル単体テスト設計書.md` |
| feature | `機能設計書.md` | `機能単体テスト設計書.md` |

### 読み取り結果の項目と転記先の節

節の番号は各様式の見出しに付く§番号を指す。読み取り結果の値は業務の言葉に翻訳してから書き、コードの名前をそのまま書かない。

| 種別 | 読み取り結果の項目 | 転記する節 |
|---|---|---|
| screen | 入力項目 | §5.1 入力 |
| screen | 表示項目 | §5.2 出力 |
| screen | 操作 | §3 機能仕様 |
| screen | 遷移 | §6 画面遷移の業務文脈 |
| screen | 呼ぶ接続窓口 | §3 機能仕様 |
| api | 経路 | §1.1 エンドポイントの業務的な位置づけ |
| api | 入力 | §1.3 入力仕様 |
| api | 出力 | §1.4 出力仕様 |
| api | 検証 | §2.3 業務ルール |
| api | 呼ぶ処理 | §2.1 業務フロー |
| api | 触る表 | §4.1 扱うデータの論理定義 |
| batch | 起動条件 | §1.1 起動の契機と実行の周期 |
| batch | 入力 | §1.2 入力と出力 |
| batch | 出力 | §1.2 入力と出力 |
| batch | 処理の流れ | §2.1 業務フロー |
| report | 出力条件 | §1.2 出力の条件と契機 |
| report | 項目 | §1.1 項目定義 |
| report | レイアウトの元 | §1.3 レイアウトの要件 |
| external | 相手先 | §1.1 連携先と方式 |
| external | 形式 | §1.1 連携先と方式 |
| external | 項目 | §1.2 項目とコード体系 |
| external | 応答 | §1.3 正常応答と異常応答 |
| external | 再試行 | §1.4 タイムアウトとリトライと冪等性 |
| table | 列 | §4.1 扱うデータの論理定義（列名は業務の言葉で書く） |
| table | 関係 | §4.1 扱うデータの論理定義（整合性の条件として書く） |
| table | 型・制約 | 論理データモデルには書かない。テーブル定義書（詳細設計）へ書く |
| feature | 含む単位 | §2.1 構成要素一覧 |

### 記述の3区分

| 区分 | 内容 | 扱い |
|---|---|---|
| 観測できる読み取り結果 | 読み取り結果ファイルの値・根拠に直接現れる名前・呼び出し先 | 本文へ書く。導出元の読み取り結果の項目を検証記録へ残す |
| 観測から一意に導ける存在理由 | 入出力・呼び出し関係から一意に定まる、その単位が担う処理 | 本文へ書く。導出元の読み取り結果の項目を検証記録へ残す |
| 判断基準と業務背景 | なぜその制約か・誰が使うか・業務上の位置づけ・例外の適用条件 | 本文へ書かず、要確認事項一覧へ移す |

3区分のどれか迷う記述は、3番目として扱う。断定せず、確定できなかった事項として分離する。

### 実装用語の混入検査

埋め終えた文書へ次の型で grep をかけ、検出0件を確認する。検出した箇所は業務語彙へ書き直す。

| 種別 | 検出パターンの例 |
|---|---|
| screen | `useState\|useEffect\|Props\b\|interface [A-Z]\|: *(string\|number\|boolean)\b\|\.(tsx\|ts\|jsx\|js\|css)\b` |
| api | `interface [A-Z]\|class [A-Z].*:\|def [a-z_]+\(\|: *(string\|number\|boolean)\b\|FastAPI\|Express\|@app\.(get\|post\|put\|delete)\|\.(py\|pl\|pm\|cgi\|rb\|go\|java)\b` |
| batch・report・external | `interface [A-Z]\|: *(string\|number\|boolean)\b\|styled-components\|FastAPI\|Express\|@app\.(get\|post\|put\|delete)\|\.(py\|pl\|pm\|cgi\|rb\|go\|java)\b` |
| table | `interface [A-Z]\|: *(string\|number\|boolean)\b\|CREATE TABLE\|PRIMARY KEY\|FOREIGN KEY\|\.(sql\|py\|ts\|js\|prisma)\b` |
| feature | 含む構成要素の種別の検出の型を併用する |

内部成果物の名前（読み取り結果ファイルのパス・`code-reading-items`・`取り出した実行`）も本文に書かない。

## 完了条件

- 全単位に基本設計書と単体テスト設計書がある（様式は種別ごとに定める）
- 必須節が順に埋まっている。実装位置（file:line）が無い。未記入のプレースホルダーが無い
- 要確認事項一覧の各キーが確認事項の記録に登録されている
- 読み取り結果の各項目が基本設計書に転記されている
- 保留を除く全単位に合格の記録がある
- 次が0を返す: `check-acceptance-record.sh <対象> --kind <種別> --unit <識別子> --design-root <置き場>`

## 設計判断

### check-basic-design.sh

**必要性**: 基本設計書は AI が読み取り結果を写して書くため文面は毎回変わる。完了条件（節の順序・位置づけの行・未記入の不在・読み取り結果の転記・確認事項の登録）は機械で確かめられる形を持つ。文面を問わず形と実在だけを検査することで、詳細設計へ進んでよいかを判定できる。

**代替案を採用しなかった理由**:
- 自己レビューだけにする: 節の欠落や転記漏れを毎回人手で数えることになる
- 対象の規約検査だけに任せる: 読み取り結果の転記や確認事項の登録までは規約検査が知らない

**保守責任者**: 人手（ユーザー）。読み取り結果の項目や様式を変えるときは、`docs/design/common/code-reading-items.json`・`templates/`・本スクリプトを同時に直す。

**廃棄条件**: 基本設計書の様式を構造化データから生成する仕組みに置き換えた時。

### record-acceptance.sh

**必要性**: 合格の記録は文書の同一性（sha256）とコミットを持たなければ、後から文書が変わったときに古い合格が生き残ってしまう。記録の形を1つに決め、詳細設計へ進む機能（check-acceptance-record.sh）がその形だけを読めば済むようにする。

完了の検査はこの機能自体の完了時の処理であり、独立した機能を別に持たない。本スクリプトと check-acceptance-record.sh は reverse-shared/scripts/ に置く共有部品である。共通処理の詳細設計・単位の詳細設計からも同じ場所を参照する。

**代替案を採用しなかった理由**:
- 合格をログにだけ書く: 文書の変更を検知できず、古い合格のまま詳細設計に進んでしまう
- 完了判定を別の機能として独立させる: 基本設計書を書く手順と完了判定が分離し、機能をまたいだ受け渡しが増える

**保守責任者**: 人手（ユーザー）。記録の形（キー）を変えるときは、本スクリプトと reverse-shared/scripts/check-acceptance-record.sh を同時に直す。

**廃棄条件**: 合格の記録を別の仕組みに置き換えた時。
