# DESIGN.md — デザイントークン仕様

## 1. トークン一覧

| 変数名 | ライト | ダーク | 用途 |
|---|---|---|---|
| `--bg` | #FFFFFF | #15171C | ページ背景 |
| `--panel` | #FFFFFF | #1C1F26 | カード・パネル背景 |
| `--panel-2` | #F6F8FA | #21262D | パネル内の副背景 |
| `--border` | #D1D9E0 | #30363D | 標準境界線 |
| `--border-strong` | #AFB8C1 | #484F58 | 強調境界線 |
| `--text` | #1B1F26 | #E8E5DC | 本文文字 |
| `--text-sub` | #4A4F58 | #B6B3AB | 補足文字 |
| `--text-muted` | #767B85 | #888784 | 弱文字（キャプション等） |
| `--accent` | #0969DA | #58A6FF | アクセント（主） |
| `--accent-2` | #218BFF | #79C0FF | アクセント（副） |
| `--accent-soft` | #DDF4FF | #132D4B | アクセント背景 |
| `--accent-border` | #54AEFF | #1F6FEB | アクセント境界線 |
| `--gold` | #BC4C00 | #DB6D28 | ゴールド（主） |
| `--gold-soft` | #FFF1E5 | #311D08 | ゴールド背景 |
| `--gold-border` | #D18A5A | #7A3E0D | ゴールド境界線 |
| `--success` | #1A7F37 | #3FB950 | `--accent` の別名 |
| `--success-soft` | #DAFBE1 | #0D2818 | `--accent-soft` の別名 |
| `--warn` | #BC4C00 | #DB6D28 | `--gold` の別名 |
| `--danger` | #CF222E | #F85149 | 危険色（主） |
| `--danger-soft` | #FFEBE9 | #3D1214 | 危険色の背景 |
| `--highlight` | #D97B1A | #E8943A | 画面遷移図の「画面固有」色 |
| `--highlight-soft` | rgba(217,123,26,0.12) | rgba(232,148,58,0.15) | `--highlight` の背景 |
| `--highlight-border` | rgba(217,123,26,0.5) | rgba(232,148,58,0.5) | `--highlight` の境界線 |
| `--nav-tag` | #7B8BBF | #8E9ED0 | 画面遷移図の「共通ナビ」色 |
| `--nav-tag-soft` | #ECEEF6 | rgba(142,158,208,0.15) | `--nav-tag` の背景 |
| `--self-tag` | #6B9B6B | #7DB87D | 画面遷移図の「自己ループ」色 |
| `--self-tag-soft` | #E8F0E8 | rgba(125,184,125,0.15) | `--self-tag` の背景 |
| `--code-bg` | #1B1F26 | #0E1116 | コードブロック背景 |
| `--code-fg` | #E8E5DC | #E8E5DC | コードブロック文字 |
| `--mono` | （共通） | （共通） | 等幅フォント指定 |
| `--shadow-sm` | （共通） | （共通） | 小さい影 |
| `--shadow-md` | （共通） | （共通） | 大きい影 |
| `--radius` | （共通） | （共通） | 標準の角丸 |
| `--radius-sm` | （共通） | （共通） | 小さい角丸 |

`--mono`・`--shadow-sm`・`--shadow-md`・`--radius`・`--radius-sm` の 5 つはダークテーマでも値を変えない共通トークンである。

## 2. 色の使い分けガイドライン

`--success`・`--success-soft` は `--accent`・`--accent-soft` の別名であり、`--warn` は `--gold` の別名である。値の善し悪しを表す評価色ではなく、特定 UI 面で意味付けするための命名にすぎない。

- `--accent`（`--success` を含む）: 主要な操作要素・強調リンク・選択状態
- `--gold`（`--warn` を含む）: 副次的な強調・注意喚起の見出し帯
- `--danger`: 破壊的操作（削除等）のボタン・警告テキスト
- `--highlight`・`--nav-tag`・`--self-tag`: `detail-t4-diagram.html`（画面遷移図）専用の3層配色。遷移先を画面固有／共通ナビ／自己ループの3種に分類する着色にのみ使用する

数値の閾値によって色を切り替える判定ロジックは持たない。色は固定的な役割割り当てであり、状態評価の結果ではない。

## 3. レイアウト原則

- カードは固定枠で組む。件数が増減してもグリッド構造やカードサイズは変化させない
- 判定・閾値・評価色（合格/不合格・良好/警告等の意味づけ）は導入しない。表示するのは事実の数値と計算式、その出所のみ
- レスポンシブはブレークポイントでカラム数を減らす方式とし、固定枠の原則は維持する

## 4. テーマ切替の仕組み

- `localStorage` のキー `rd-portal-theme` にユーザーの選択（`light` / `dark`）を保存する
- `<html>` または `<body>` の `data-theme` 属性を切替キーとし、`tokens.css` の `[data-theme="light"]` / `[data-theme="dark"]` セレクタで変数値を上書きする
- 初回アクセス時は `localStorage` の保存値を優先し、未保存ならライトテーマを既定とする

## 5. アイコン仕様

- アイコンは全てインライン SVG で実装する（CDN 不使用・自己完結）
- `portal-template.html` の `matIcon()` 関数が約30種の SVG path データを保持し、アイコン名から SVG 要素を生成する
- 詳細ページテンプレートは戻る矢印（arrow_back）のみをインライン SVG で直接埋め込む
- 外部フォントやCDNに一切依存しないため、オフライン環境でも全アイコンが表示される

## 6. テンプレート構成と対応するページ型

| ファイル | ページ型 |
|---|---|
| `portal-template.html` | TOP ページ（ダイジェストカード 2 枚 + カテゴリカード） |
| `detail-t2-dictionary.html` | 対訳辞書型（用語辞書） |
| `detail-t3-attributes.html` | 属性表型（技術スタック） |
| `detail-t4-diagram.html` | 図解型（画面遷移図・ER 図、client-side SVG） |
| `detail-t5-procedure.html` | 手順型（環境構築手順） |
| `unit-list-template.html` | 一覧型（単位一覧、検索・ソート付き） |
| `screen-list-template.html` | 一覧型（画面一覧、検索・ソート付き） |
| `feature-list-template.html` | 一覧型（機能一覧、検索・ソート付き） |

本文フォントは全テンプレート共通で `var(--font-body)` を使用する（実値は `tokens.css` の `--font-body` で定義: `"Hiragino Kaku Gothic ProN","Hiragino Sans","Noto Sans JP","BIZ UDPGothic","Yu Gothic","Meiryo",system-ui,-apple-system,sans-serif`）。コード表示は `var(--mono)`（`"SFMono-Regular","Menlo","Cascadia Code","Consolas",monospace`）で統一する。
