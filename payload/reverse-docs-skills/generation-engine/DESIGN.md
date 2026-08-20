# DESIGN.md — デザイントークン仕様

## 1. トークン一覧

基本トークンは26種のみで、ダーク・ライトの2テーマ分の値を持つ。既存の別名トークンはすべてvar()参照で基本トークンを指すため、テンプレート側のCSSを変更しなくても配色が自動で追従する。

### 1-1. 基本トークン（26種）

| 変数名 | ダーク | ライト | 用途 |
|---|---|---|---|
| `--bg` | #0F1217 | #F1F4F8 | ページ背景 |
| `--panel` | #161C23 | #FFFFFF | カード・パネル背景 |
| `--panel2` | #1C232E | #E9EEF4 | パネル内の副背景 |
| `--panel3` | #141A23 | #F7F9FC | サイドバー・フッターの背景 |
| `--line` | #2B3443 | #D8DFE8 | 標準境界線 |
| `--line2` | #3A4658 | #243040 | 強調境界線・シェル区切り線 |
| `--text` | #E7ECF4 | #1A222E | 本文文字 |
| `--sub` | #A8B3C3 | #4B5A70 | 補足文字 |
| `--muted` | #8A96A7 | #6C7A8E | 弱文字（キャプション等） |
| `--faint` | #5B6574 | #9AA7B6 | もっとも弱い文字（連番・区分ラベル） |
| `--accent` | #4CC2FE | #0284C7 | アクセント（唯一の主要色） |
| `--accent-hi` | #9ADCFF | #075985 | アクセントの強調値（リンクホバー等） |
| `--accent-soft` | rgba(76,194,255,0.17) | rgba(2,132,199,0.10) | アクセント背景 |
| `--stamp` | #FF6E4F | #D9482B | 差し色（警告・危険・陳腐化の表示専用） |
| `--stamp-soft` | rgba(255,110,78,0.16) | rgba(217,72,43,0.12) | `--stamp` の背景 |
| `--green` | #4ADE81 | #15803D | 完了・成功の表示専用色 |
| `--green-soft` | rgba(74,222,129,0.16) | rgba(21,128,61,0.16) | `--green` の背景 |
| `--grid` | rgba(255,255,255,0.036) | rgba(16,34,64,0.05) | 方眼紙背景の格子線 |
| `--head` | #202B3B | #243040 | テーブルヘッダの背景 |
| `--headtext` | #E7ECF4 | #F1F4F8 | テーブルヘッダの文字 |
| `--code` | #0B0E13 | #101722 | コードブロック背景 |
| `--codetext` | #C9E8FF | #C9E8FF | コードブロック文字（両テーマ共通値） |
| `--navon` | #EAF6FF | #102A43 | サイドバーの選択中ナビ文字 |
| `--chipontext` | #0F1217 | #FFFFFF | アクセント地の上に乗せる文字 |
| `--rowopen` | #1A212B | #F0F4F9 | 展開中テーブル行の背景 |
| `--neutral-soft` | rgba(255,255,255,0.06) | rgba(16,34,64,0.06) | 中立バッジの背景 |

### 1-2. 別名トークン

既存テンプレートの参照を壊さないために残した別名で、すべて上記いずれかの基本トークンをvar()で参照する。値そのものは持たない。

| 別名 | 参照先 | 別名 | 参照先 |
|---|---|---|---|
| `--panel-2` | `--panel2` | `--gold-border` | `--stamp` |
| `--border` | `--line` | `--warn` | `--stamp` |
| `--border-strong` | `--line2` | `--danger` | `--stamp` |
| `--text-sub` | `--sub` | `--danger-soft` | `--stamp-soft` |
| `--text-muted` | `--muted` | `--success` | `--green` |
| `--accent-2` | `--accent-hi` | `--success-soft` | `--green-soft` |
| `--accent-border` | `--accent` | `--highlight` | `--accent` |
| `--gold` | `--stamp` | `--highlight-soft` | `--accent-soft` |
| `--gold-soft` | `--stamp-soft` | `--highlight-border` | `--accent` |
| `--nav-tag` | `--faint` | `--self-tag-soft` | `--green-soft` |
| `--nav-tag-soft` | `--neutral-soft` | `--code-bg` | `--code` |
| `--self-tag` | `--green` | `--code-fg` | `--codetext` |
| `--cat-list` | `--accent` | `--cat-standards` | `--accent` |
| `--cat-design` | `--accent` | `--cat-project` | `--accent` |

`--highlight`・`--nav-tag`・`--self-tag`は`detail-t4-diagram.html`（画面遷移図）専用の3層配色として残る。値はすべてアクセント・弱文字・成功色の参照であり、独自の色は持たない。`--cat-list`・`--cat-standards`・`--cat-design`・`--cat-project`はカテゴリごとの色分け廃止により、4つとも`--accent`を指す別名になった。

### 1-3. 非色トークン（9種、テーマで値を変えない）

| 変数名 | 値 | 用途 |
|---|---|---|
| `--font-body` | Hiragino Kaku Gothic ProN 他のフォントスタック | 本文フォント |
| `--mono` | SFMono-Regular 他の等幅フォントスタック | コード・数値表示 |
| `--radius` | 0 | 標準の角丸（角丸を使わない方針のため常に0） |
| `--radius-sm` | 0 | 小さい角丸（同上） |
| `--shadow-sm` | `3px 3px 0 var(--accent-soft)` | 小さい影（オフセットのみ・ぼかし半径なし） |
| `--shadow-md` | `4px 4px 0 var(--accent-soft)` | 大きい影（同上） |
| `--sidebar-w` | 248px | 共通シェルのサイドバー幅 |
| `--page-gutter` | 40px | メインペインの左右余白 |
| `--grid-size` | 24px | 方眼紙背景の格子間隔 |

## 2. 色の使い分け指針

アクセントは`--accent`1色に統一し、カテゴリごとの色分けは廃止した。旧トークンの`--cat-list`・`--cat-standards`・`--cat-design`・`--cat-project`は、現在は4つとも`--accent`を指す別名として残るのみである。

- `--accent`: 主要な操作要素・強調リンク・選択状態・ナビゲーションの選択中表示
- `--stamp`（`--gold`・`--warn`・`--danger`を含む）: 警告・危険・陳腐化の表示にのみ使う差し色。ブランドスタンプ表記など、ごく一部の装飾的強調にも限定的に使う
- `--green`（`--success`を含む）: 完了・成功状態の表示にのみ使う
- `--highlight`・`--nav-tag`・`--self-tag`: `detail-t4-diagram.html`（画面遷移図）専用の3層配色。遷移先を画面固有／共通ナビ／自己ループの3種に分類する着色にのみ使用する

数値の閾値によって色を切り替える判定ロジックは持たない。色は固定的な役割割り当てであり、状態評価の結果ではない。

## 3. レイアウト原則

- カードは固定枠で組む。件数が増減してもグリッド構造やカードサイズは変化させない
- 判定・閾値・評価色（合格/不合格・良好/警告等の意味づけ）は導入しない。表示するのは事実の数値と計算式、その出所のみ
- レスポンシブはブレークポイントでカラム数を減らす方式とし、固定枠の原則は維持する
- 角丸は使わない。`--radius`・`--radius-sm`は常に0で固定する
- 影はオフセットのみで表現し、ぼかし半径を持たない。`--shadow-sm`・`--shadow-md`はいずれも`<x> <y> 0 <color>`の形で定義する
- ページ全体に方眼紙状の背景（`--grid`の格子線を`--grid-size`間隔で敷く`.pt-grid`）を敷く

## 4. テーマ切替の仕組み

- 既定はダークテーマ。OSの設定がライトで、かつユーザーがテーマを明示指定していない場合に限りライトへ切り替わる
- `localStorage`のキー`rd-portal-theme`にユーザーの選択（`light`/`dark`）を保存する。保存キーは刷新前から変わっていない
- `<html>`の`data-theme`属性を切替キーとし、`tokens.css`の`[data-theme="light"]`/`[data-theme="dark"]`セレクタで変数値を上書きする
- 初回アクセス時は`localStorage`の保存値を優先する。未保存の場合は`prefers-color-scheme: light`に一致すればライト、それ以外はダークを既定にする

## 5. アイコン仕様

- アイコンは全てインライン SVG で実装する（CDN 不使用・自己完結）
- `portal-template.html` の `matIcon()` 関数が約30種の SVG path データを保持し、アイコン名から SVG 要素を生成する
- 戻る導線は各テンプレートが個別に持たず、共通シェルのサイドバーナビゲーションに一本化されている
- 外部フォントやCDNに一切依存しないため、オフライン環境でも全アイコンが表示される

## 6. テンプレート構成と対応するページ型

| ファイル | ページ型 |
|---|---|
| `portal-template.html` | TOPページ（ダッシュボード。ダイジェストカード＋カテゴリカード） |
| `common-doc-template.html` | 汎用文書型（プロジェクト共通の規約・設計書等の長文表示） |
| `screen-doc-template.html` | 画面別文書型（画面基本設計・詳細設計等の個別画面文書） |
| `screen-sequence-template.html` | シーケンス図型（画面の操作単位のシーケンス図） |
| `ai-assets/ai-assets-template.html` | AI設定資産型（rules・skills・サブエージェント・hooksの俯瞰） |
| `detail-pages/detail-t2-dictionary.html` | 対訳辞書型（用語辞書） |
| `detail-pages/detail-t3-attributes.html` | 属性表型（技術スタック） |
| `detail-pages/detail-t4-diagram.html` | 図解型（画面遷移図、client-side SVG） |
| `detail-pages/detail-t5-procedure.html` | 手順型（環境構築手順） |
| `detail-pages/detail-t6-er.html` | ER図型 |
| `detail-pages/detail-t7-entity-state.html` | 状態遷移図型 |
| `detail-pages/detail-t7-release-notes.html` | リリースノート型 |
| `detail-pages/detail-t8-design-system.html` | デザインシステム型（対象プロジェクトのCSSトークン可視化） |
| `detail-pages/detail-t9-component-inventory.html` | コンポーネント棚卸し型 |
| `detail-pages/detail-t10-icon-catalog.html` | アイコンカタログ型 |
| `matrix/crud-matrix-template.html` | CRUD図型 |
| `matrix/permission-function-matrix-template.html` | 権限機能マトリクス型 |
| `matrix/permission-screen-matrix-template.html` | 権限画面マトリクス型 |
| `matrix/traceability-template.html` | 画面-API-テーブル対応表型 |
| `unit-list/feature-list-template.html` | 一覧型（機能一覧、検索・ソート付き） |
| `unit-list/screen-list-template.html` | 一覧型（画面一覧、検索・ソート付き） |
| `unit-list/unit-list-template.html` | 一覧型（API・テーブル・バッチ・帳票・外部連携一覧、検索・ソート付き） |

本文フォントは全テンプレート共通で`var(--font-body)`を使用する。コード表示は`var(--mono)`で統一する。両者の実値は§1-3の非色トークン一覧を参照する。

## 7. 共通シェル

サイドバー・フッター・方眼紙背景は`delivery-payload/templates/partials/`配下の3ファイルに切り出されている。ファイル構成は`shell.css`・`shell-sidebar.html`・`shell-footer.html`であり、22本のテンプレートすべてがこれを差し込んで使う。

- `generation-engine/scripts/shell-injection.sh`が`shell_injection_args`関数を提供し、既存のトークン注入と同じマーカー置換の仕組みで各テンプレートへ差し込む。差し込み先のマーカーは`/* SHELL_CSS */`（`shell.css`の全文）・`<!--SHELL_SIDEBAR-->`（サイドバー）・`<!--SHELL_FOOTER-->`（フッター）の3種
- サイドバーのナビ項目はカタログ（`delivery-payload/references/portal-catalog.json`）のカテゴリ一覧から組み立てる。各項目はカテゴリキー・01始まりの通し番号・表示名・資料数を持ち、資料数はカタログの定義から数えるため生成済みページの有無に依存しない
- partialsが1つでも欠けている場合、`shell_injection_args`は差し込み引数を空にして戻る。呼び出し側のテンプレートにマーカーがない場合も差し込み処理は素通りするため、移行途中のテンプレートが混在していても壊れない
- 方眼紙背景（`.pt-grid`）・角丸なし・オフセットのみの影といったレイアウト原則（§3）は、テンプレート個別のCSSではなく`shell.css`側で一括定義する
