# page-data.json スキーマ定義

detail-pages 系（用語辞書 / 技術スタック / 画面遷移図 / ER図 / 環境構築手順）が共有する入力 JSON `page-data.json` の完全スキーマ。`build-detail-page.sh` / `validate-page-data.sh` / 5 生成スキルはすべて本ファイルを定義とする。

## トップレベル

| キー | 型 | 必須 | 内容 |
|---|---|---|---|
| pageKind | string | 必須 | `glossary` \| `techstack` \| `transition` \| `er` \| `env` \| `entity-state` \| `release-notes` \| `design-system` \| `component-inventory` \| `icon-catalog` のいずれか |
| generatedAt | string | 必須 | ISO8601 形式の生成日時（例: `2026-01-01T00:00:00Z`） |
| manifestContentHash | string | transitionのみ必須 | raw `screen-manifest.json`を`jq -cjS`した改行なしbytesのSHA-256（64桁lowercase hex） |
| manifestScreenCount | number | transitionのみ必須 | raw `screen-manifest.json`の`screens[]`件数（全件。1-144）。`validate-page-data.sh`が`nodes[]`件数+`unresolved[]`のうち`reason`が`"routeが空文字列のため遷移解決不能"`の件数の合計と一致することを検証し、ノード欠落を機械検知する |
| edgesStatus | string | transitionのみ・任意 | `未抽出` \| `抽出済み` のいずれか。「未抽出」は遷移抽出未実施（bridgeが `edges:[]` を出力した状態）、「抽出済み」は遷移抽出スキルが `edges` を構築した状態（0件の抽出結果を含む）を示す。省略時は後方互換のため検査対象外（validate-page-data.shが値域検査） |
| title | string | 必須 | ページ見出し |
| description | string | 必須 | ページ概要（1〜2 文） |
| unresolved | array | 任意 | 未解決項目の配列。要素は `{ "label": string, "reason": string, "sourceRef"?: string }`。省略時は空扱い |
| diagnostics | object | 任意 | 検出できなかった事実の集計。キーは指標名、値は `{ "count": number, "total": number, "ratio": number, "threshold": number, "warning": boolean }`。省略時は空扱い（1-145: transitionの`unscannedSource`、1-148: glossaryの`missingSource`/`unimplementedLayer`） |
| flowCategories | array（transition のみ・任意） | 任意 | 動線カテゴリの要約。要素は `{ "name": string, "source": string, "screenCount": number }`。`categories[]`（glossary の分類軸）とは別物のため `flowCategories` と命名する |
| （型別スロット） | object | 必須 | pageKind に応じたキーをトップレベルへ直接持つ（下記「型別スロット」参照） |

## sourceRef の形式

対象リポジトリからの相対パスに、任意で `:<行番号>` を付す（例: `src/router.tsx:42`）。コード以外の根拠は文書参照形式 `<文書名>.md#<見出し>`（例: `アーキテクチャ調査書.md#§2`）を許可する。

### 検証規則（validate-page-data.sh --target-repo 指定時）

1. パス部分（`:` より前。文書参照形式は対象外）は `--target-repo` を基点に `test -f` で実在確認する（必須）
2. 行番号が付与されている場合、そのファイルの総行数（`wc -l`）以内であることを確認する（行番号が存在するときのみ）
3. 文書参照形式（`.md#` を含む値）はパス実在チェックの対象外とする（対象リポジトリ外の生成物文書のため）

## 型別スロット

### T3: techstack（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| tiles | array | `{ "label": string, "value": string, "note"?: string }` の配列。要約タイル列 |
| columns | object | 明細表の列ラベル。`{ "item": "項目", "value": "値", "sourceRef": "出所" }`（値はページ側で上書き可） |
| rows | array | `{ "item": string, "value": string, "sourceRef": string }` の配列。明細表 1 行 = 1 要素。sourceRef は必須（出所の検証可能性を担保するため） |
| absentRows | array（任意） | `{ "item": string, "value": string, "sourceRef": string }` の配列。調査書が「実在しない（理由: …）」と判定した項目を、根拠パスを保持したまま記録する別表（1-132）。`value` には理由文をそのまま入れる。省略時は空扱い。`rows[]` とは別の表としてテンプレート側が描画するため、`rows[]` へ混在させない |

`absentRows[].sourceRef`はsourceRef実在検査の対象外とする。
「実在しない」という根拠は、調査書や対象リポジトリに存在しないファイルを指す場合があるためである。
実在確認を要求すると正当なデータが誤ってFAILする。`rows[].sourceRef`は実在必須のままとする。

### T2: glossary（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| categories | array | 分類軸。`{ "key": string, "label": string }` の配列。テンプレート側は先頭に「すべて」チップを自動付加する |
| projectionVersion | string（semanticのみ） | portal投影形式。現行は`0.2` |
| glossarySchemaVersion | string（semanticのみ） | 投影元glossary schemaのversion |
| glossaryContentVersion | string（semanticのみ） | 投影元glossary contentのversion |
| terms | array | 下記legacy形式、semantic v0.1互換形式、semantic v0.2形式のいずれか。同じ配列への新旧混在は禁止 |

#### legacy形式

旧形式は`term`、`definition`、`codeRefs`、`category`、`sourceRef`を持つ。
表示時だけ各値を用語、コード表現、根拠へ写像する。
意味keyと状態は`未移行`とする。入力JSONは変更しない。

legacy page-data rootは既定の表示項目、`categories`、`terms`、診断項目だけを許可する。
semantic用version項目、候補・監査項目、その他の未知keyは拒否する。

#### semantic v0.2形式

semantic page-data rootは既定の表示項目、3つのversion、分類、用語、診断項目だけを許可する。
`proposalAudit`、`reviewers`、`approval`、`confidence`などの候補・監査keyは拒否する。
その他の未知keyも拒否する。

必須項目は次のとおり。

| キー | 型 | 内容 |
|---|---|---|
| key | string | meaningful snake_caseの一意key |
| term_ja | string | 日本語の代表用語 |
| term_en | string | 英語の代表用語 |
| definition | string | 概念の定義 |
| scope | string | 適用範囲 |
| category | string | `entity` \| `attribute` \| `value` \| `process` \| `event` \| `role` \| `rule` \| `metric` |
| code_name | string | 代表コード名 |
| type_name | string/null | クラス・型・enum等の型名 |
| db_name | string | テーブル・列等のDB名 |
| api_name | string | APIのfield・parameter名 |
| ui_label | string/null | 画面表示名 |
| allowed_values | string[] | 許容値 |
| status | string | `active` \| `deprecated` \| `retired` |
| notes | string | 補足 |
| representations | array | `{ "channel": string, "value": string, "location": string }`。一覧は先頭2件、drawerは全件を表示 |
| sourceRefs | string[] | 根拠参照。全件をdrawerへ表示 |

semantic v0.1のterm rootは、次の明示allowlist以外を拒否する。

- 基本情報は標準14項目と`representations`。
- 補足情報は`aliases`、`forbiddenTerms`、`relations`、`examples`、`counterExamples`、`constraints`、`tags`。
- 状態情報は`status`、`introducedIn`、`deprecatedIn`、`retiredIn`、`migrationDeadline`、`replacementKey`、`lifecycleReason`。
- 管理情報は`securityClassification`、`notes`、`approvers`、`sourceRefs`、`decisionRef`、`changeRef`。

正式な後継用語fieldは`replacementKey`だけとする。`replacedBy`は予約fieldではなく禁止する。
旧page-dataに`replacedBy`がある場合はsemantic v0.1として受理しない。
`replacementKey`へ移行してから再検証する。

nested objectも明示allowlistとする。
`categories[]`、`scope`、`representations[]`、`forbiddenTerms[]`、`relations[]`、`unresolved[]`ごとに許可keyを固定する。
glossaryの`diagnostics`は`missingSource,unimplementedLayer`だけを指標名に使う。
各指標は`count,total,ratio,threshold,warning`だけを持つ。候補専用keyと未知keyは位置にかかわらず拒否する。

#### 表示・安全性

- 一覧の14列は次のとおり。
  - `key`、`term_ja`、`term_en`、`definition`、`scope`、`category`、`code_name`
  - `type_name`、`db_name`、`api_name`、`ui_label`、`allowed_values`、`status`、`notes`
- drawerは「別名、禁止語、全representations、relations、例/反例、constraints、security、全根拠」の8群とする。
- 通常filterはactive、deprecated、legacyの未移行を表示する。retiredは履歴filterだけに表示する。
- proposal、candidate、changeに相当するトップレベルslotは拒否する。
- semantic `terms[]`配下は全ネストobjectを走査し、候補・監査用keyを拒否する。
- snake_caseとcamelCaseの両表記を検査し、allowlist内のnested objectへ混入した場合も拒否する。
- 検索は標準14項目とコード表現の部分一致（大小文字無視）とする。分類・状態filterとはAND条件にする。
- 行はclick、Enter、Spaceでdrawerを開き、Escapeで閉じる。modal中は背景をinertにし、focusをdrawer内へ閉じ込め、閉じたら起点行へ戻す。
- 狭幅では14列を省略せず横scrollとし、drawerは画面幅全体を使う。
- `terms`が空配列、またはfilter結果が0件の場合は表本体に「なし」を1行表示する。
- HTMLの`application/json`へ埋め込む際は`<`、literal U+2028、literal U+2029をUnicode escapeする。入力JSONと埋込JSONをparseし、key順に依存しない意味一致で検証する。

#### 正式glossaryからの投影

`project-semantic-glossary.py`をinput、registry、outputの各引数付きで実行する。
投影前に正式validatorを実行する。解決不能ref、exit 1/2、error、review_requiredでは出力を作らない。
warningだけなら生成できる。一時fileからatomic replaceし、入力YAMLは変更しない。

主な写像はsourceを`sourceRefs`、stewardshipのapproversを`approvers`、lifecycle statusを`status`とする。
snake_caseの各値はcamelCaseへ決定変換する。aliasの`value`は文字列配列へ投影する。
retiredもpage-dataへ含め、履歴filterで表示する。

実サンプルの基準fixtureは`semantic-glossary-sample-page-data.json`である。
次のbuilder wrapperで再生成する。現行fixtureはactiveを2件含み、deprecatedとretiredは含まない。

```bash
bash generation-engine/scripts/detail-pages/regenerate-semantic-glossary-sample.sh
```

wrapperは`build-detail-page.sh --page glossary`を呼ぶ。
`generation-engine/samples/project-portal/lists/semantic-glossary/用語辞書.html`は現行T2 templateから再生成する。
HTMLの手修正は禁止する。画面の列見出しは日本語14列とする。埋め込みpage-dataのキーは英語14キーを維持する。

### T4: transition / er（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| legend | array | 凡例。`{ "symbol": string, "meaning": string }` の配列。空配列可（「凡例なし」を表示） |
| nodes | array（transition のみ） | `{ "unitKey": string, "label": string, "route"?: string, "category"?: string, "categorySrc"?: string }` の配列。SVG 描画時のノードキーは `unitKey` |
| edges | array（transition のみ） | `{ "from": string, "to": string, "trigger": string, "sourceRef": string, "confidence": string }` の配列。`from`/`to` は `nodes[].unitKey` を参照する。bridge（`build-detail-pages-from-screen-manifest.sh`）は既存 page-data の `manifestContentHash` が今回生成分と一致する場合に限り、既存の `edges`（と `edgesStatus`）をそのまま引き継ぐ。manifest が変化した場合は空配列で再出力する（トップレベルの `edgesStatus` 参照） |
| entities | array（er のみ） | `{ "key": string, "label": string }` の配列。SVG 描画時のノードキーは `key` |
| relations | array（er のみ） | `{ "from": string, "to": string, "cardinality": string, "sourceRef": string }` の配列。`from`/`to` は `entities[].key` を参照する |

`entities[]` は上記に加え、次の任意フィールドを持つ（ER図専用）。

| キー | 型 | 内容 |
|---|---|---|
| columns | array（任意） | `{ "name": string, "type": string, "pk"?: boolean, "fk"?: boolean, "unique"?: boolean, "nullable"?: boolean }` の配列。テーブルのカラム定義。省略時はテンプレート側でカラム明細を表示しない |

`nodes[]` は上記に加え、次の任意フィールドを持つ。

| キー | 型 | 内容 |
|---|---|---|
| category | string（任意） | 動線カテゴリ名。未設定の場合はテンプレート側で「その他」に集約 |
| categorySrc | string（任意） | カテゴリの導出元。`routing-group` \| `url-segment` \| `account-group` \| `fallback` のいずれか |
| sourceScanned | boolean（任意） | 遷移元としてこの画面のファイルを実際に走査できたか（1-145）。省略時はテンプレート側で `true` 扱い（後方互換）。`false` は「走査した結果0件」ではなく「そもそも走査できなかった」ことを示す |

`edges[]` は上記に加え、次の任意フィールドを持つ。

| キー | 型 | 内容 |
|---|---|---|
| section | string（任意） | UI要素が所属するセクション名。スキルがコード走査時に親要素構造から推定。未設定の場合はテンプレート側で「その他」に集約 |
| triggerType | string（任意） | 遷移の種別。「リンク遷移」「フォーム送信」「リダイレクト」「ブラウザバック」の4値。未設定の場合はテンプレート側で「リンク遷移」にフォールバック。triggerType が「ブラウザバック」の場合、`to` は空文字列とする（遷移先がランタイム依存で静的に確定しないため）。テンプレート側で「(前画面)」と表示し、孤児参照検査は `to` のみスキップする（`from` は通常通り検査する） |
| condition | string（任意） | 遷移が発火する条件の自由記述（例: "未認証の場合"、"管理者権限ありの場合"）。認証ガード・ルートガード・条件分岐内の遷移に該当する場合に記録する。未設定の場合はテンプレート側で非表示 |

`transition`は埋込JSONからワイヤーフレームと遷移先表をclient-sideで構築する。
画面選択と前後ボタンで表示を切り替える。`er`はCanvas 2Dをclient-sideで構築する。
サーバー側ではノードとエッジを生成しない。レイアウトはpageKindで分岐する。

- `transition`: 画面ごとの split-view 表示。エッジを出現率 30% 以上で「共通ナビゲーション」と判定し、画面固有（橙）/ 共通ナビ（青）/ 自己ループ（緑）の 3 層に分類する。出次数がしきい値（`MAX_EDGES_PER_VIEW`）超のノードは中央ナビゲーション画面として折りたたみ表示、入出次数 0 のノードは未接続画面一覧として分離表示する
- `er`: FK接続グラフの連結成分を決定的にクラスタ化する。
  クラスタ俯瞰、ドメイン拡大、テーブル選択の3段階探索を提供する。
  ドメインの色はクラスタのインデックスから導出する。

矢印は`transition`だけに付与する。transitionは`trigger`、erは`cardinality`を表示する。
参照先が存在しないエッジは描画をスキップし、`unresolved[]`で明示する。
transitionは図の下に`edges[]`の詳細を補足表として表示する。
大規模時はdiagram内だけを横スクロールする。erは詳細パネルにカラム定義とrelationを表示する。

`relations[]`が空の場合はクラスタ探索Canvasを表示しない。
代わりに`entities[]`全件の静的なエンティティ一覧と、外部キー0件の警告を表示する。
`relations[]`が1件以上の場合は一覧を空文字に置換し、クラスタ探索Canvasだけを表示する。

### T7: entity-state（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| legend | array | 凡例。`{ "symbol": string, "meaning": string }` の配列。空配列可（「凡例なし」を表示） |
| nodes | array | `{ "key": string, "label": string, "entity": string }` の配列。`key` は「`<エンティティ>.<状態>`」形式を推奨（例: `注文.下書き`）。`entity` はエンティティ絞り込みセレクタのグルーピングキー |
| edges | array | `{ "from": string, "to": string, "trigger": string, "sourceRef": string, "entity": string }` の配列。`from`/`to` は `nodes[].key` を参照する。`trigger` は遷移契機（画面操作・API・バッチ等の業務語彙） |

### T5: env（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| prerequisites | array | `{ "name": string, "note": string }` の配列 |
| environment | array（任意） | `{ "name": string, "value": string }` の配列。実行環境の実測値（OS・アーキテクチャ・Linux 互換環境フラグ等）。省略時は空配列として扱う |
| steps | array | `{ "order": number, "command": string, "note": string }` の配列。`order` は表示前にテンプレート側で昇順ソートする（順序 = 実行順） |
| allocations | array | `{ "target": string, "value": string, "sourceRef": string }` の配列。ポート割当等 |

テンプレート挙動: 前提ツール表 → 実行環境表 → 手順表 → 割当表の順に固定表示する。各配列が空の場合は該当表に「なし」を 1 行表示する。

`validate-page-data.sh` は `steps[]` に対し次の 2 点を検証する（1-133）。

1. 順序番号は、`order`の値集合を重複・欠番のない`1..N`とする。空配列はPASSとする。
2. command欄に句点を含めない。実行可能なコマンドがない行は`該当なし`とし、説明はnoteへ入れる。

### T7: release-notes（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| releases | array | `{ id: string, date: string, title: string, pr: number \| null, prUrl: string \| null, flow: string, summary: array, changes: array, verifySteps: array }` の配列。1 要素 = 1 リリース（PR 単位） |

- `releases[].id` は一意キー。`YYYY-MM-DD-<kebab>` 形式を推奨
- `releases[].date` はコミット日（`YYYY-MM-DD`）
- `releases[].pr` / `releases[].prUrl` は PR 番号・URL。存在しない場合は null
- `releases[].flow` は `feature` \| `maintenance` \| `docs` のいずれか
- `releases[].summary` は `{ label: string, text: string }` の配列。変更概要のラベル付き箇条書き
- `releases[].changes` は `{ type: string, text: string }` の配列。`type` は `feat` \| `fix` \| `docs` \| `test` \| `refactor` \| `chore` のいずれか
- `releases[].verifySteps` は `{ title: string, env?: string, checks: string[] }` の配列。`env` は `staging` \| `production` \| `local` のいずれか（省略可）

テンプレート挙動: `releases[]` を PR 単位のアコーディオンカードとして一覧表示する。各カードの中身は「変更概要」「変更内容」「確認手順」の 3 つの折りたたみで構成し、確認手順のチェック状態は `localStorage` に永続化する。全チェック完了のカードは完了表示に切り替わる。

### T8: design-system（確定仕様）

トークンはカテゴリごとの配列を持つオブジェクトとする（平坦な単一配列ではない）。抽出（`extract-design-tokens-from-designmd.sh`）とテンプレート（`detail-t8-design-system.html`）の実装がこの形を前提に作られており、既存の生成済みサンプル（`generation-engine/samples/project-portal/foundation/デザインシステム.html`）もこの形で埋め込まれている。定義側をこの実装へ合わせる（2026-08-11、証跡パス台帳「デザインシステム-データ形式の不一致」）。

| キー | 型 | 内容 |
|---|---|---|
| tokens | object | `{ colors: array, typography: array, spacing: array, components: array }`。カテゴリごとの配列を持つオブジェクト |
| tokens.colors | array | `{ name: string, hex: string, usage: string }` の配列 |
| tokens.typography | array | `{ name: string, fontFamily: string, size?: string, weight?: string, description: string }` の配列。`size`/`weight` は任意（省略時はテンプレート側で無視） |
| tokens.spacing | array | `{ name: string, value: string }` の配列 |
| tokens.components | array | `{ name: string, description: string }` の配列 |
| summary | array | `{ label: string, value: string, note?: string }` の配列。要約タイル（任意） |

### T9: component-inventory（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| components | array | `{ name: string, path: string, props: number, usageCount: number, files: string[] }` の配列。コンポーネント 1 件 = 1 要素 |
| summary | array | `{ label: string, value: string, note?: string }` の配列。要約タイル（任意） |

### T10: icon-catalog（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| icons | array | `{ name: string, sourceType: string, usageCount: number, files: string[] }` の配列。アイコン 1 個 = 1 要素 |
| summary | array | `{ label: string, value: string, note?: string }` の配列。要約タイル（任意） |

`icons[]`をカードグリッドで表示する。`sourceType`に応じたグリフをカード上部へ描画する。
ソース種別、名前検索、`usageCount`降順で絞り込む。使用ファイル一覧は`details`で展開する。

## 出力ファイル名との対応

pageKind と固定出力ファイル名の対応は `build-detail-page.sh` 側で保持する（正は `build-portal.sh` の `FUTURE_FILES`）。

| pageKind | 出力ファイル名 |
|---|---|
| glossary | 用語辞書.html |
| techstack | 技術スタック.html |
| transition | 画面遷移図.html |
| er | ER図.html |
| env | 環境構築手順.html |
| entity-state | 状態遷移図.html |

## C統合テストの実行

意味基盤用語辞書の統合テストは、Node.js 20以上、`playwright`パッケージ、Chromiumを実行依存とする。依存versionはリポジトリルートの`package.json`と`package-lock.json`で固定する。

```bash
npm ci
npx playwright install chromium
npm run test:semantic-glossary-page
```

通常の依存導入後は`NODE_PATH`を指定しない。`playwright`を読み込めない場合はテスト失敗とし、静的検査だけの成功やSKIPにはしない。
