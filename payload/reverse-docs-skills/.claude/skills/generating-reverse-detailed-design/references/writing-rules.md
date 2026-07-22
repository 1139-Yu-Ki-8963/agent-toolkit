# generating-reverse-detailed-design 執筆規律

facts.yml から設計書への転記を担当する際の執筆規律の正本。転記先の判定条件・字面転記と要約の境界・実測委譲の書式・禁止事項を定める。9 分類のキー付け規則自体は `shared/references/facts-schema.md` が正本であり、本ファイルでは重複定義しない。

## 章マップ（章役割キー）準拠の転記先決定

転記先の章は「章の役割キー → §番号」の対応表である起動引数 chapter_map_path（実体: `shared/references/chapter-map.md`）で解決する。SKILL.md・本ファイルに書く §番号はすべて既定値であり、実際の設計書の章マップ表（テンプレート冒頭に埋め込まれた表）が優先する。§番号が食い違う場合は設計書側の章マップ表を正とする。

## facts のキー→設計書章の対応規律（判定条件付き）

| facts.yml セクション | 転記先（章の役割キー / §） | 判定・書き方 |
|---|---|---|
| import | 実装契約 §15.3（依存） | key を依存一覧へ。副作用 import も残す |
| export_type | 実装契約 §15.1（ファイル分割）/ §15.2（型定義） | export をファイル分割表へ、型の全フィールドを §15.2 へ。型定義はテンプレート様式の§15.2テーブル（型名/フィールド名/型/必須任意の4列）のみで表現する。facts.yml の export_type が「型定義なし・リテラル推論型」（facts-schema.md 準拠）の場合はテーブル行を置かず、§15.2 に「型定義なし（facts.yml の export_type に型宣言なし）」という根拠付き該当なし文を書く（設計原則2）。型を捏造してテーブルを埋めることは禁止事項1違反であり、audit_script_path 側の既知の非致命的挙動（`references/phase-details.md` Phase 5 詳細を参照）を避ける目的でも許されない |
| const | §10（定数・設定値） | 定数名と値を定数表へ。オブジェクトリテラル定数がフィールド分解されている場合（const-<定数名>-<フィールド名>キー）も、フィールドごとに1行として定数表へ転記する |
| state | §5（状態管理。メイン §5.3 / サブ §5.4） | 変数名・型・初期値を状態変数表へ |
| handler | §8（イベント処理） | ハンドラ名・発火要素・挙動を挙動表へ |
| jsx | §3（画面構造）/ §9（領域別仕様） | ネスト構造・全文字列リテラル・props具体値・className等を構造記述へ字面転記する。jsx-path-* キー（条件分岐パス別ルート要素）は、各パスに対応する記述（表示制御方式の分岐として §3.1/§9 へ）として個別に転記する |
| style | DESIGN.md 本体 + §3.6/§15.6 のキー参照 | 数値・色は DESIGN.md が正。設計書はスタイル定数キーを参照 |
| api | §7（API 通信仕様。§7.2 リクエスト・レスポンス型） | BL 名・契機・req/res 形を API 表へ |
| measurement_pending | 転記しない | 該当章に `実測委譲（画面単位検証で確定）` を残し measurement_pending へ |

### §15.1 ファイル分割表の記入規律

画面固有でないファイル（ルーター定義ファイル・共有部品など、facts.yml の target_file_paths に含まれるが本画面のコンポーネントではないファイル）を §15.1（ファイル分割）表に記載する場合は、配置ディレクトリ列または備考に「参考情報」と必ず明記する。`audit-consistency.sh --list-contract-files` はこの表の1列目を rebuilding Phase 3 の白紙化（git rm）対象として機械抽出するため、「参考情報」の明記がない行は画面固有ファイルとして誤って白紙化対象に混入する。

## 字面転記と要約の境界

facts.yml の `value` 列は既に原本から正規化された宣言的契約であり、原本コードそのものではない。しかし `value` を機械的にコピー＆ペーストするだけでは章の文脈（表の列構成・文体）に合わず、また facts.yml の内部表現（YAML の記法・引用符）がそのまま設計書に漏れ出す。転記は「value の意味を保ったまま章のテンプレート様式で書き直す」ことであり、以下の境界に従う。

| 対象 | 許可（正規化） | 禁止（字面転記・創作） |
|---|---|---|
| 型定義 | facts.yml の `export_type` セクションの全フィールドを §15.2 のテンプレート様式テーブル（1フィールド=1行）で表現する | facts.yml の `value` 文字列をそのまま YAML の引用符付きでコピーする |
| ロジック | facts.yml の `handler` セクションの `value`（処理1行要約）を挙動表の文へ整形する | facts.yml に無い条件分岐・処理詳細を推測で補う |
| JSX | facts.yml の `jsx` セクションの `value`（ネスト記述）をそのまま構造記述として使う | facts.yml に無い属性値・実測レイアウトを創作する |
| スタイル | facts.yml の `style` セクションの `value` を DESIGN.md 側の記載として転記し、設計書側はキー参照に留める | facts.yml に無い数値・色を推測で埋める |
| API | facts.yml の `api` セクションの `value`（req/res 形）を §7.2 の表形式へ整形する | facts.yml に無いエンドポイント・パラメータを創作する |

§15.2のテーブルはコードではなく構造化データとして型を記録する。コードブロック（fenced code block）での型定義記載は本テンプレートでは一律禁止する。

## JSX 転記の値そのまま転記（往復検証FAIL対策）

facts の jsx 項目にある文言リテラル・props 値・className・アイコン名/size は、§3/§9 と DESIGN.md へ**値そのまま**転記する。要約・代表例への丸め込みは禁止する（転記漏れは往復検証 FAIL の主因）。

実測確定済みの frontmatter `scenarios`（`ready.selector`・`operations` 等）は再執筆時にも維持し、「実測委譲（画面単位検証で確定）」へ巻き戻さない。

## 実測委譲の書式

`measurement_pending`（⑨）に由来する事実は転記しない。該当章には固定書式 `実測委譲（画面単位検証で確定）` をプレースホルダとして残す。この文字列は `scripts/check-fact-coverage.sh` が「実測委譲の表記あり」として個別キー一致を免除する判定に使う識別子であるため、表記を変更しない。返却ブロックの `measurement_pending[]` には facts.yml の `measurement_pending.items[].key` をそのまま一覧化する。

## frontmatter 転記規律

facts.yml の `meta` 節は以下の通り frontmatter へ転記する（`shared/references/facts-schema.md` の `meta` 定義に対応）。

- `meta.source_repo` → frontmatter の `source_repo` へそのまま転記する（必須）
- `meta.source_ref` → frontmatter の `source_ref` へそのまま転記する（必須）
- `meta.route`（`value`）→ frontmatter の `scenarios[].path` を構成する。`query` / `path_params` は起動引数 `verification_url`（画面レジストリに記帳された、開通時に実レンダリング確認済みのURL。管理者が解決して渡す）から確定転記する。`ready`（描画到達判定に使う要素）は facts.yml の `jsx` セクションの分岐別ルート要素（`jsx-path-*`）から確定する。**`scenarios` 内に実測委譲プレースホルダを残すことを禁止する**（残すと基準確立・往復検証の動的比較（render-ready 判定）が実行不能になる）。確定できない場合は `AUTHORED` を返さず、hint に「開通不完全（scenarios 確定不能）」を記して管理者へ差し戻す（開通の完了が先）。`scenarios: []` のまま `AUTHORED` を返すことも禁止する

## 禁止事項

1. **facts に無い事実の創作**: facts.yml の `sections` 配下に存在しない項目を推測・慣習・一般論で補って書かない。「該当なし」は facts.yml 側が「該当なし」（`items: []` + `reason`）を示している場合にのみ書ける
2. **原本参照**: 本スキル実行中に対象リポジトリの原本コードを Read しない（SKILL.md 設計原則4）。facts.yml の欠落・矛盾に気づいても自ら原本で確認せず、extracting-unit-facts-from-code への差し戻し事由として hint に記録する
3. **facts.yml の改変**: facts.yml は封印済みの確定情報であり、本スキルは読むだけで書き換えない。誤りに気づいた場合も差し戻し対象とする
4. **意味キーの変更**: facts.yml の `key` をそのまま設計書内の言及に使う（`check-fact-coverage.sh` の転記突合はこのキー文字列の一致で判定するため、言い換えて別の語にすると未転記判定されて完全性ゲートを通過できない）

## fenced code block への転記規律

facts の value 内の `\n` エスケープを fenced code block（` ``` ` で囲まれたコードブロック）へ転記する際は、`\n` を実改行へ展開して複数行として記載する。1行のまま転記すると、盲検再構築者が行構造を推測で再構成することになり、再現精度が低下する。転記後の fenced block の行数が、facts.yml の evidence から特定できる原本コードの行数と著しく乖離する場合は、value の `\n` 展開漏れまたは省略がないか確認する。

## gold標準の見本参照規律

`shared/references/gold-standard/docs/` 配下の正解設計書が存在する場合、各章の執筆直前に同章の gold 版を見本として参照してよい。ただし以下の制約を守る:

- **参照してよいもの**: 書式（章の粒度・表のカラム構成・値の記述スタイル・記載の深さ）
- **参照禁止**: 値・識別子・画面固有の事実。対象画面の事実の唯一の出典は facts.yml であり、gold 見本の値を書き写すと別画面の事実を混入させる事故になる
