# DESIGN.md — デザイントークン仕様

## 1. トークン一覧

| 変数名 | ライト | ダーク | 用途 |
|---|---|---|---|
| `--bg` | #F7F5EE | #15171C | ページ背景 |
| `--panel` | #FFFFFF | #1C1F26 | カード・パネル背景 |
| `--panel-2` | #F0EDE3 | #232730 | パネル内の副背景 |
| `--border` | #DAD5C5 | #353944 | 標準境界線 |
| `--border-strong` | #BFB9A6 | #4A4F5C | 強調境界線 |
| `--text` | #1B1F26 | #E8E5DC | 本文文字 |
| `--text-sub` | #4A4F58 | #B6B3AB | 補足文字 |
| `--text-muted` | #767B85 | #888784 | 弱文字（キャプション等） |
| `--accent` | #3F4F8E | #8FA3DB | アクセント（主） |
| `--accent-2` | #5A6BAE | #A8B8E5 | アクセント（副） |
| `--accent-soft` | #E6E9F3 | #2A2E47 | アクセント背景 |
| `--accent-border` | #BAC2DC | #4C5680 | アクセント境界線 |
| `--gold` | #9B7A1F | #D4B45D | ゴールド（主） |
| `--gold-soft` | #F5EFD9 | #3D3520 | ゴールド背景 |
| `--gold-border` | #DDC68A | #7A6633 | ゴールド境界線 |
| `--success` | #3F4F8E | #8FA3DB | `--accent` の別名 |
| `--success-soft` | #E6E9F3 | #2A2E47 | `--accent-soft` の別名 |
| `--warn` | #9B7A1F | #D4B45D | `--gold` の別名 |
| `--danger` | #9B3F2D | #D4836E | 危険色（主） |
| `--danger-soft` | #F5E2DC | #3F2620 | 危険色の背景 |
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

- Material Symbols Outlined を CDN 経由で読み込む
- CDN 到達不可時のオフラインフォールバックを用意し、アイコン欠落時もレイアウトが崩れないようにする

## 6. テンプレート構成と対応するページ型

| ファイル | ページ型 |
|---|---|
| `portal-template.html` | TOP ページ（ダイジェストカード 2 枚 + カテゴリカード） |
| `detail-t2-dictionary.html` | 対訳辞書型（用語辞書） |
| `detail-t3-attributes.html` | 属性表型（技術スタック） |
| `detail-t4-diagram.html` | 図解型（画面遷移図・ER 図、client-side SVG） |
| `detail-t5-procedure.html` | 手順型（環境実行手順） |
| `unit-list-template.html` | 一覧型（単位一覧、検索・ソート付き） |
| `screen-list-template.html` | 一覧型（画面一覧、検索・ソート付き） |
| `feature-list-template.html` | 一覧型（機能一覧、検索・ソート付き） |

本文フォントは `"Hiragino Kaku Gothic ProN","Hiragino Sans","Yu Gothic","Meiryo",system-ui,-apple-system,sans-serif`、一覧系テンプレートのみ `system-ui,-apple-system,"Hiragino Sans","Noto Sans JP",sans-serif` を使う。コード表示は `--mono`（`SFMono-Regular,Menlo,Consolas,monospace`）で統一する。
