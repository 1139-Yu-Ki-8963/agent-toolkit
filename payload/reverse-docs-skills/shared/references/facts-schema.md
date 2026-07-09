# facts.yml スキーマ正本

`extracting-unit-facts-from-code` が出力する `facts.yml` の構造・必須フィールド・正規化規則を定める正本。9 分類の定義は `authoring-screen-docs-from-code` の `references/phase-details.md`（宣言的契約事実表 `fact-table.md` の9分類定義）から移設したものであり、authoring 側の `fact-table.md`（Markdown 2列表）とは別形式（YAML・evidence列付き）の独立した成果物である。

## 全体構造

```yaml
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/target-repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
  - src/screens/Foo/FooRow.tsx
meta:
  source_repo: /abs/path/to/target-repo
  source_ref: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
  route:
    value: "/foo/:id"
    evidence: "src/router/routes.tsx:42"
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  export_type:
    reason: ""
    items: []
  const:
    reason: "該当なし（原本にトップレベル定数が存在しない）"
    items: []
  state:
    reason: ""
    items: []
  handler:
    reason: ""
    items: []
  jsx:
    reason: ""
    items: []
  style:
    reason: ""
    items: []
  api:
    reason: ""
    items: []
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:12"
```

インデントは2スペース刻み固定とする（`sections` 配下のキー = 2段目、`reason`/`items` = 3段目、`- key:` = 4段目、`value:`/`evidence:` = 5段目）。この固定インデントは `scripts/recount-facts.sh` が awk で行位置ベースに解析するための契約であり、崩すと再計数ゲートが正しく集計できない。

`meta` は `sections` と並ぶトップレベル必須節であり、以下の3フィールドを持つ。

| フィールド | 内容 |
|---|---|
| source_repo | 対象リポジトリの絶対パス（`target_repo_path` と同値） |
| source_ref | 抽出時点のコミットSHA（`git -C <target_repo_path> rev-parse HEAD` で実測） |
| route | 画面のルートパス。`value`（実測したパス文字列）と `evidence`（ルーター定義ファイルの `file:line`）を持つ |

## 9分類とキーの付け方

`①`〜`⑨` の丸数字は分類記号であり連番 ID ではない（`always/naming/semantic-key` 規約の対象外。既存契約の分類記号として踏襲する）。各分類のセクションキー（YAML上の識別子）・ラベル・抽出粒度・キーの付け方は次の通り。

| 分類記号 | セクションキー | ラベル | 抽出粒度（原本から拾う事実） | キーの付け方の例 |
|---|---|---|---|---|
| ① | import | import | モジュール名 + import 名（named/default/type/namespace）。副作用 import も含む | `import-react-useState`・`import-styled-components` |
| ② | export_type | export・型 | export 名、interface/type の全フィールド（フィールド名・型・省略可否）。型宣言を伴わない export は事実欄に「型定義なし・リテラル推論型」と明記する | `export-ReportTable`・`type-ReportRow-id` |
| ③ | const | 定数 | 定数名と値（リテラル・enum・as const）。オブジェクト/enum 型はフィールドごとにキーを分解する（最上位1階層のみ。フィールド値自体がオブジェクト/配列でも内部までは再帰的に分解しない）。フィールドのevidenceは当該フィールド行のfile:line | `const-MAX_ROWS-100`（スカラー）・`const-cardStyle-height`（オブジェクトのフィールド分解） |
| ④ | state | 状態変数 | useState/useReducer/useRef/store 参照の変数名・型・初期値リテラル | `state-rows-empty` |
| ⑤ | handler | イベントハンドラ | ハンドラ名・発火要素・処理1行要約 | `handler-onRowClick-遷移` |
| ⑥ | jsx | JSX構造 | コンポーネントのネスト構造。全文字列リテラル・全propsの具体値・className・見出しレベル等の具体粒度は references/profile-screen.md の「⑥JSX構造の採録規律」を正本とする。条件分岐（早期return・三項演算子・&&）で複数パスが生成される場合、パスごとのルート要素を独立キーで採録する（jsx-path-<パス識別子>-<ルート要素名>） | `jsx-Table-Row-Cell`（ネスト）・`jsx-path-loading-div`（パス別ルート） |
| ⑦ | style | スタイル実測値 | styled 定数名と数値・色（実測値。DESIGN.md が正） | `style-Wrapper-padding-16` |
| ⑧ | api | API呼出 | BL 名・契機・リクエスト/レスポンス形 | `api-fetchReport-req` |
| ⑨ | measurement_pending | 実測系（実測委譲・転記対象外） | 初期表示値・DOM配置順・要素位置・レイアウト。断定せず一覧化のみ | `初期表示-件数` |

各分類は「該当なし」を許容する。その場合 `items: []` とし `reason` に根拠を記す（例: `"該当なし（原本にトップレベル定数が存在しない）"`）。`items` が空で `reason` も空のセクションは不正（Phase 2 の完了条件違反）。

**「該当なし」は原本に当該分類の事実が実在しない場合専用**である。原本に事実が実在するが `scripts/recount-facts.sh` の再計数パターンがそれを構造的に検知できない（Promiseチェーン形式のAPI呼出し・複数行JSX開始タグ・カスタムフック分割代入・オブジェクトリテラル定数のフィールド値・条件分岐JSXパスの外殻ラッパー等）場合は「該当なし」に該当しない。この場合に items を省略・reason へ逃がして Phase 3 を通すことは禁止する。`extracting-unit-facts-from-code` の `references/profile-screen.md`・`scripts/recount-facts.sh` 側のパターンを実在の構文に合わせて修正する（詳細は同スキルの SKILL.md Gotchas を参照）。

## 必須フィールド

| セクション | 必須フィールド | 備考 |
|---|---|---|
| import 〜 api（①〜⑧） | key・value・evidence | `evidence` は `<target_file_paths内の相対パス>:<行番号>` 形式（例: `src/screens/Foo.tsx:12`） |
| measurement_pending（⑨） | key・evidence | `value` を持たない（実測委譲のため値を記録しない） |

`scripts/recount-facts.sh` の空欄率検査は **key・evidence の2フィールドのみ** を機械検査の対象にする（`value` の欠落は本メトリクスに現れない。Phase 2 実行者は分類ごとの抽出粒度表に従い value を必ず埋める。value 欠落は完了条件違反だが、独立の自動検査は持たない）。

## 孤児参照の定義

`evidence` の相対パス部分（`:<行番号>` を除いた部分）が `target_file_paths` に列挙された相対パスの集合に含まれない場合を「孤児参照」とみなす。対象ユニットの宣言対象外ファイルを根拠に事実を書いてはならないという原則を機械検査する。

## normalize 規則（`shared/scripts/seal-facts.sh normalize`）

再現性検証（Phase 5）は同一 args での2回の独立抽出結果を比較するため、`run_id` の差異・空行・行末空白の揺れを正規化で除去してから比較する。

1. `^run_id:` で始まる行を削除する（`run_id` は起動ごとに変わりうる値であり、内容の同一性判定には含めない）
2. 各行の行末空白を除去する
3. 空行を削除する

`target_repo_path`・`target_file_paths`・`meta`・`sections` 配下の内容（key・value・evidence）はそのまま比較対象に残る（`meta` は正規化対象に含め除去しない。`source_ref` も値そのものを比較対象とする）。normalize は封印（sha256計算）にも同じ関数を使う（`seal`/`verify` は normalize 後のハッシュを比較する）。

## 拡張予約（screen 以外のプロファイル追加余地）

本スキー本体は Stage 3 の範囲で `profile: screen` のみを実装する。他プロファイル（API・テーブル・バッチ・帳票・外部連携）を追加する場合は、`sections` の9分類キー構成をプロファイルごとに拡張・差し替えできるよう、`profile` フィールド値ごとに `references/profile-<profile名>.md`（例: `references/profile-api.md`）を追加し、`recount-facts.sh` の分類別パターンを `profile` 値で切り替える設計とする。9分類の枠組み自体（意味キー・key/value/evidence の3フィールド契約・孤児参照定義・normalize規則）はプロファイル非依存で共通利用する。

## 関連

- `.claude/skills/extracting-unit-facts-from-code/SKILL.md` — 本スキーマを使う抽出スキル本体
- `.claude/skills/extracting-unit-facts-from-code/references/profile-screen.md` — screen プロファイルの分類別抽出手順・再計数用決定的パターン
- `.claude/skills/extracting-unit-facts-from-code/scripts/recount-facts.sh` — 本スキーマに基づく独立再計数ゲート
- `shared/scripts/seal-facts.sh` — 本スキーマの normalize・封印・検証を担う共有スクリプト
- `.claude/skills/authoring-screen-docs-from-code/references/phase-details.md` — 9分類定義の移設元（fact-table.md 側は本スキーマの対象外。authoring 側の改修は別工程）
