# authoring-screen-docs-from-code 工程詳細

SKILL.md の Phase 2（原本読解）〜Phase 5（完全性ゲート）の詳細手順。9 分類の抽出粒度・Phase 4 転記マップの判定条件・字面転記禁止の境界例・fact-table.md の節構成テンプレートを集約する。

## Phase 2 詳細: 宣言的契約事実表（fact-table.md）の 9 分類

原本を読解し、以下 9 分類を `<screen_dir>/検証記録/著述-<対象>/<timestamp>/fact-table.md` に作成する。各分類は「## <番号><分類名>」見出し + Markdown 表で書く。表の 1 列目は**意味キー**（連番禁止・内容要約キー）、2 列目は事実。キーは Phase 5 の `check-fact-coverage.sh` が抽出して設計書への転記を突合する識別子であり、設計書本文にもそのキー文字列が出現するように転記する。

| 分類 | 抽出粒度（原本から拾う事実） | キーの付け方の例 |
|---|---|---|
| ①import | モジュール名 + import 名（named/default/type）。副作用 import も含む | `import-react-useState`・`import-styled-components` |
| ②export・型 | export 名、interface/type の**全フィールド**（フィールド名・型・省略可否）。型宣言を伴わない export（リテラル推論型）は事実欄に「型定義なし・リテラル推論型」と明記する | `export-ReportTable`・`type-ReportRow-id`・`type-ReportRow-amount` |
| ③定数 | 定数名と値（リテラル・enum・as const）。オブジェクト/enum 型の定数は**フィールドごとにキーを分解**し、各フィールドの値を事実欄に記載する | `const-MAX_ROWS-100`・`const-STATUS_LABELS-active`・`const-STATUS_LABELS-inactive` |
| ④状態変数 | useState/useRef/store 参照の変数名・型・初期値リテラル | `state-rows-empty`・`ref-scrollTop-0` |
| ⑤イベントハンドラ | ハンドラ名・発火要素・処理 1 行要約 | `handler-onRowClick-遷移`・`handler-onSort-並替` |
| ⑥JSX 構造 | コンポーネントのネスト**のみ**（属性値・実測レイアウトは書かない） | `jsx-Table-Row-Cell`・`jsx-Header-Title` |
| ⑦スタイル実測値 | styled 定数名と数値・色（実測値。DESIGN.md が正） | `style-Wrapper-padding-16`・`style-Title-color-333` |
| ⑧API 呼出 | BL 名・契機・リクエスト/レスポンス形 | `api-fetchReport-req`・`api-fetchReport-res` |
| ⑨実測系 | 初期表示値・DOM 配置順・要素位置・レイアウト。**断定せず一覧化のみ** | `初期表示-件数`・`DOM順-ヘッダ先頭` |

各分類は「該当なし」でも節を残す。その場合は表の代わりに根拠を書く（例:「該当なし（原本に useState/useRef/store 参照が存在しない）」）。根拠なしの空節・裸の「未確認」は完了条件違反。

### fact-table.md の節構成テンプレート

```markdown
# 宣言的契約事実表: <対象ファイル>

## ①import
| キー | 事実 |
|---|---|
| import-react-useState | react から useState |

## ②export・型
| キー | 事実 |
|---|---|
| export-ReportTable | ReportTable コンポーネントを default export |

## ③定数
該当なし（原本にトップレベル定数が存在しない）

## ④状態変数
| キー | 事実 |
|---|---|
| state-rows-empty | rows: ReportRow[]、初期値 [] |

## ⑤イベントハンドラ
| キー | 事実 |
|---|---|
| handler-onRowClick-遷移 | onRowClick、行要素クリック、詳細画面へ遷移 |

## ⑥JSX構造
| キー | 事実 |
|---|---|
| jsx-Table-Row-Cell | Table > Row > Cell のネスト |

## ⑦スタイル実測値
| キー | 事実 |
|---|---|
| style-Wrapper-padding-16 | Wrapper の padding: 16px |

## ⑧API呼出
| キー | 事実 |
|---|---|
| api-fetchReport-res | fetchReport のレスポンス形 { rows: ReportRow[] } |

## ⑨実測系（measurement_pending・転記対象外）
| キー | 事実 |
|---|---|
| 初期表示-件数 | 初期表示件数は実測で確定（[画面単位検証で実測]） |
```

⑨の見出しには必ず「⑨」または「measurement_pending」を含める。`check-fact-coverage.sh` はこの見出しを検出して⑨セクションを転記突合の対象外にする。⑨を最終分類として配置する（以降に転記対象の分類を置かない）。

## Phase 4 詳細: 事実表 → 章の転記マップ（判定条件付き）

事実表の各分類を、対応する章へ転記する。⑦はスタイル数値を DESIGN.md に置き、設計書側はキー参照に留める。⑨は転記せず `[画面単位検証で実測]` プレースホルダを該当章に残し、返却ブロックの `measurement_pending[]` に一覧化する。

| 分類 | 転記先（章の役割キー / §） | 判定・書き方 |
|---|---|---|
| ①import | 実装契約 §15.3（依存） | import キーを依存一覧へ。副作用 import も残す |
| ②export・型 | 実装契約 §15.1（ファイル分割）/ §15.2（型定義） | export をファイル分割表へ、型の全フィールドを §15.2 へ。型ブロックはテンプレート様式の typescript ブロックのみ許可 |
| ③定数 | §10（定数・設定値） | 定数名と値を定数表へ |
| ④状態変数 | §5（状態管理。メイン §5.3 / サブ §5.4） | 変数名・型・初期値を状態変数表へ |
| ⑤イベントハンドラ | §8（イベント処理） | ハンドラ名・発火要素・挙動を挙動表へ |
| ⑥JSX 構造 | §3（画面構造）/ §9（領域別仕様） | ネスト構造を構造記述へ。属性値・レイアウトは書かない |
| ⑦スタイル実測値 | DESIGN.md 本体 + §3.6/§15.6 のキー参照 | 数値・色は DESIGN.md が正。設計書はスタイル定数キーを参照 |
| ⑧API 呼出 | §7（API 通信仕様。§7.2 リクエスト・レスポンス型） | BL 名・契機・req/res 形を API 表へ |
| ⑨実測系 | 転記しない | 該当章に `[画面単位検証で実測]` を残し measurement_pending へ |

章の役割キー → §番号の解決は起動引数 chapter_map_path（`shared/references/chapter-map.md`）を正本とする。§番号は既定値であり、設計書の章マップ表で解決する。

## 宣言的契約への正規化 —「字面転記禁止」の境界例

著述は「宣言的契約への正規化」であり、コード行の丸写しは禁止する。境界は次の通り。

| 対象 | 許可（正規化） | 禁止（字面転記） |
|---|---|---|
| 型定義 | interface の全フィールドを §15.2 のテンプレート様式 typescript ブロックで表現 | 実装ファイルの型宣言をコメントごとコピー |
| ロジック | 「金額が 0 未満なら error 表示」という契約文 | if 文・三項演算子のコードブロック丸写し |
| JSX | 「Table > Row > Cell のネスト」という構造記述 | JSX の属性・className を含む行のコピー |
| スタイル | 「padding は DESIGN.md の spacing キー参照」 | styled-components のテンプレートリテラル全文コピー |

例外: テンプレート §15.2 の typescript 型ブロックはテンプレートが定める様式であり、型を表現する手段として許可する。

## Phase 5 詳細: 完全性ゲート

1. `scripts/check-fact-coverage.sh <fact-table.md> <画面詳細設計書.md> [<DESIGN.md>]` を実行し exit 0 を確認する。未転記が 1 行でもあれば exit 1（fail-closed）で、未転記キーが stderr に列挙される。該当キーを Phase 4 のマップに従って転記してから再実行する。
2. 起動引数 audit_script_path（`shared/scripts/audit-consistency.sh`）を通常モードで実行し、章の内部整合性の違反が 0 件であることを確認する。

⑨実測系のキーは `check-fact-coverage.sh` が除外するため、設計書に確定値を転記しなくてもゲートは通過する。⑨は measurement_pending として返却ブロックに残す。
