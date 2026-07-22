---
version: alpha
name: AI Management Portal
description: Internal dashboard design system for agent-home operations (skills, hooks, rules, routines) with a zinc neutral base and a GitHub-style blue accent (#0969DA).
colors:
  primary: "#18181b"
  secondary: "#3f3f46"
  muted: "#71717a"
  tertiary: "#0969DA"
  accent-soft: "#DDF4FF"
  neutral: "#fafafa"
  surface: "#ffffff"
  surface-variant: "#F6F8FA"
  border: "#D1D9E0"
  success: "#1A7F37"
  gold: "#BC4C00"
  danger: "#CF222E"
  code-bg: "#0f172a"
  code-fg: "#e2e8f0"
typography:
  body:
    fontFamily: "Hiragino Kaku Gothic ProN"
    fontSize: 15px
    lineHeight: 1.7
  h1:
    fontSize: 24px
    fontWeight: 700
    lineHeight: 1.4
  h2:
    fontSize: 19px
    fontWeight: 700
    lineHeight: 1.4
  h3:
    fontSize: 16px
    fontWeight: 700
    lineHeight: 1.4
  nav:
    fontSize: 13px
    fontWeight: 500
  caption:
    fontSize: 11px
  code:
    fontFamily: "SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: 12.5px
    lineHeight: 1.55
rounded:
  sm: 6px
  md: 10px
spacing:
  sm: 8px
  md: 16px
  lg: 24px
components:
  page:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    typography: "{typography.body}"
  topbar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.secondary}"
    padding: "12px 20px"
  page-hero:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.neutral}"
    rounded: "{rounded.md}"
    padding: "{spacing.lg}"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  chip:
    backgroundColor: "{colors.surface-variant}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.sm}"
  tag-accent:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.tertiary}"
    rounded: "{rounded.sm}"
  button-ghost:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.sm}"
  button-ghost-hover:
    textColor: "{colors.tertiary}"
  caption:
    textColor: "{colors.muted}"
    typography: "{typography.caption}"
  divider:
    backgroundColor: "{colors.border}"
    height: 1px
  badge-success:
    textColor: "{colors.success}"
  badge-warn:
    textColor: "{colors.gold}"
  badge-danger:
    textColor: "{colors.danger}"
  code-block:
    backgroundColor: "{colors.code-bg}"
    textColor: "{colors.code-fg}"
    rounded: "{rounded.sm}"
    typography: "{typography.code}"
---

## Overview

AI Management Portal は、agent-home 配下のスキル・hook・ルール・ルーティンを横断表示する内部ダッシュボードである。無彩色の zinc 系パレットに teal（`tertiary`）単一のアクセント色を組み合わせ、操作可能要素だけがアクセントで浮き上がる抑制的な配色を採る。UI はすべて日本語で、本文フォントは Hiragino Kaku Gothic ProN を基調とする。本 DESIGN.md はライトテーマの値を正本とし、ダークテーマは `style.css` の `:root[data-theme="dark"]` を正とする（本ファイルには含めない）。

## Colors

`primary`（#18181b）は見出し・本文インクの基調色で、反転帯（`page-hero`）では背景としても使う。`secondary`（#3f3f46）と `muted`（#71717a）は本文の階調違いで、`secondary` はナビゲーションやカード内の準本文、`muted` はキャプション・補足など最も弱い情報に使う。

`tertiary`（#0f766e、teal）は唯一の操作アクセントであり、リンク・アクティブ状態・アクセントタグ・ホバー時の強調に限定して使う。`accent-soft`（#f0fdfa）は `tertiary` の淡色版で、タグやアクセント帯の背景に使い、テキストは常に `tertiary` と対にする。

`neutral`（#fafafa）はページ地の背景、`surface`（#ffffff）と `surface-variant`（#f4f4f5）はカード・パネルとその内部の階調違いの背景に使う。`border`（#e4e4e7）は罫線・区切り専用で、`divider` コンポーネントを通してのみ塗る。

状態色は `success`（緑）・`gold`（黄褐色、warning 相当）・`danger`（赤）の 3 種で、バッジのテキスト色としてのみ使い背景には使わない（背景に使う場合は各色の soft 版を `style.css` 側で別途定義する）。`code-bg` / `code-fg` はコードブロック専用の暗色ペアで、本文の配色とは独立させる。

## Typography

本文は Hiragino Kaku Gothic ProN・15px・行間 1.7 を基準とし、日本語の可読性を優先して行間を広めに取る。見出しは `h1`（24px）→ `h2`（19px）→ `h3`（16px）の 3 段階のみとし、いずれも太字（700）で階層を明確にする。ナビゲーション文字は 13px・500 ウェイトで本文より小さく抑え、キャプションは 11px でさらに弱める。コードは等幅（SFMono-Regular / Menlo 系）12.5px・行間 1.55 とし、本文よりわずかに詰めて表示密度を上げる。

## Layout

余白は `sm`（8px）・`md`（16px）・`lg`（24px）の 3 段階のみを使う。カード内部の余白には `md`、ヒーロー帯や大きなセクション間隔には `lg`、チップやバッジ内側の詰めた余白には `sm` を当てる。topbar のような密度の高い水平バーは `12px 20px` のように 2 値指定で個別調整してよいが、新規に中間値を増やさずこの 3 段階に収める。

## Shapes

角丸は `sm`（6px）と `md`（10px）の 2 段階のみを使う。カード・パネル・ヒーロー帯などまとまった面には `md`、チップ・タグ・ボタン・コードブロックなど小さな要素には `sm` を当てる。

## Components

`page` はページ全体の地で、`neutral` 背景に `primary` の本文色を乗せる。`topbar` は `surface` 背景に `secondary` の文字色で、ページ内で最も明るい水平バーとして機能する。`page-hero` は `primary` を背景・`neutral` を文字色にした反転帯で、カテゴリページの導入部など強調したいセクション冒頭に使う。表示ルートは TOP（`#/`）とカテゴリ詳細（`#/category/<id>`）に限り、フロー詳細（`#/flow/<id>`）では非表示にする。この表示制御は `src/main.js` の `setTopElementsVisible` 関数が担う。

規模サマリ（`.metric-grid` とその見出しラベル）は TOP ページでのみ表示するコンポーネントで、カテゴリ詳細・フロー詳細では非表示にする。表示制御は `page-hero` と同じく `src/main.js` の `setTopElementsVisible` 関数が担う。

`card` は `surface` 背景・`rounded.md` の汎用コンテナで、一覧のグリッド表示に使う。`chip` は `surface-variant` 背景・`secondary` 文字・`rounded.sm` の中立的な小要素で、状態を持たないラベルに使う。`tag-accent` は `accent-soft` 背景・`tertiary` 文字・`rounded.sm` で、操作可能・注目してほしい情報にのみ使う。

`button-ghost` は `surface` 背景・`secondary` 文字のボーダーレス風ボタンで、ホバー時は `button-ghost-hover` の文字色（`tertiary`）に切り替わる。`caption` は `muted` 文字色の補助テキストで、カード下部の件数表示などに使う。`divider` は `border` 色・高さ 1px の水平線で、罫線が必要な箇所は必ずこのコンポーネント経由で塗る。

`badge-success` / `badge-warn` / `badge-danger` は状態バッジの文字色をそれぞれ `success` / `gold` / `danger` に固定し、意味を色で即座に伝える。`code-block` は `code-bg` 背景・`code-fg` 文字・`rounded.sm` で、コマンド例や JSON 出力の表示に使う。

## Do's and Don'ts

- teal（`tertiary`）はアクセントとして 1 画面に対して抑制的に使う。本文色として多用しない
- 状態色（`success` / `gold` / `danger`）はバッジ・警告文脈以外で装飾目的に使わない
- 罫線色（`border`）は必ず `divider` コンポーネント経由で塗り、他コンポーネントの背景として転用しない
- 角丸・余白は定義済みの 2〜3 段階以外の中間値を新規に増やさない
- ダークテーマの値は `style.css` の `:root[data-theme="dark"]` が正本。本ファイルの値をダーク兼用として流用しない
- `page-hero` と規模サマリの表示・非表示は `src/main.js` の `setTopElementsVisible` が正本。ルート追加時はこの関数のロジックも同時に更新する
