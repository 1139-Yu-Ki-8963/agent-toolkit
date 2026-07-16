# page-data.json スキーマ正本

detail-pages 系（用語辞書 / 技術スタック / 画面遷移図 / ER図 / 環境実行手順）が共有する入力 JSON `page-data.json` の完全スキーマ。`build-detail-page.sh` / `validate-page-data.sh` / 5 生成スキルはすべて本ファイルを正本とする。

## トップレベル

| キー | 型 | 必須 | 内容 |
|---|---|---|---|
| pageKind | string | 必須 | `glossary` \| `techstack` \| `transition` \| `er` \| `env` のいずれか |
| generatedAt | string | 必須 | ISO8601 形式の生成日時（例: `2026-01-01T00:00:00Z`） |
| title | string | 必須 | ページ見出し |
| description | string | 必須 | ページ概要（1〜2 文） |
| unresolved | array | 任意 | 未解決項目の配列。要素は `{ "label": string, "reason": string, "sourceRef"?: string }`。省略時は空扱い |
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

### T2: glossary（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| categories | array | 分類軸。`{ "key": string, "label": string }` の配列。テンプレート側は先頭に「すべて」チップを自動付加する |
| terms | array | `{ "term": string, "definition": string, "codeRefs": string[], "category": string, "sourceRef": string }` の配列。`category` は `categories[].key` のいずれかと一致させる（チップ絞り込みの対象キー） |

テンプレート挙動: 検索ボックスは行の `textContent` 部分一致（大小文字無視）、分類チップは `category` の完全一致で絞り込む（AND 条件）。`terms` が空配列の場合は表本体に「なし」を 1 行表示する。

### T4: transition / er（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| legend | array | 凡例。`{ "symbol": string, "meaning": string }` の配列。空配列可（「凡例なし」を表示） |
| nodes | array（transition のみ） | `{ "unitKey": string, "label": string }` の配列。SVG 描画時のノードキーは `unitKey` |
| edges | array（transition のみ） | `{ "from": string, "to": string, "trigger": string, "sourceRef": string, "confidence": string }` の配列。`from`/`to` は `nodes[].unitKey` を参照する |
| entities | array（er のみ） | `{ "key": string, "label": string }` の配列。SVG 描画時のノードキーは `key` |
| relations | array（er のみ） | `{ "from": string, "to": string, "cardinality": string, "sourceRef": string }` の配列。`from`/`to` は `entities[].key` を参照する |

テンプレート挙動: SVG は埋め込み JSON から client-side で構築する（サーバー側ではノード・エッジ要素を生成しない。静的 HTML の `<svg>` は空要素）。レイアウトは pageKind で分岐する。

- `transition`: `edges[]` から入次数を計算し、入次数 0 のノードを起点とした層状配置（左→右。1 レイヤ = 1 列）。孤立サイクル等で入次数 0 ノードから到達できないノードは層 0 に配置する
- `er`: `entities[]` の出現順にグリッド配置（列数 = `ceil(sqrt(件数))`）

矢印（`marker-end`）は `transition` のみに付与する。エッジ/リレーションのラベルは `transition` が `trigger`、`er` が `cardinality`。`from`/`to` が `nodes`/`entities` に存在しないエッジは描画をスキップする（データ不整合時のフェイルセーフ。`unresolved[]` での明示が本来の解決手段）。図の下には `edges[]`/`relations[]` の詳細（`from`/`to`/ラベル/`sourceRef`/`confidence`〈transition のみ〉）を補足表として一覧表示する。大規模時は `.diagram-wrap` 内で横スクロールし、ページ本体は横スクロールしない。

### T5: env（確定仕様）

| キー | 型 | 内容 |
|---|---|---|
| prerequisites | array | `{ "name": string, "note": string }` の配列 |
| steps | array | `{ "order": number, "command": string, "note": string }` の配列。`order` は表示前にテンプレート側で昇順ソートする（順序 = 実行順） |
| allocations | array | `{ "target": string, "value": string, "sourceRef": string }` の配列。ポート割当等 |

テンプレート挙動: 前提ツール表 → 手順表 → 割当表の順に固定表示する。各配列が空の場合は該当表に「なし」を 1 行表示する。

## 出力ファイル名との対応

pageKind と固定出力ファイル名の対応は `build-detail-page.sh` 側で保持する（正は `build-portal.sh` の `FUTURE_FILES`）。

| pageKind | 出力ファイル名 |
|---|---|
| glossary | 用語辞書.html |
| techstack | 技術スタック.html |
| transition | 画面遷移図.html |
| er | ER図.html |
| env | 環境実行手順.html |
