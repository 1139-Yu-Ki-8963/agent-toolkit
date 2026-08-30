---
doc_id: design-common
type: design
status: draft
target_screen: _プロジェクト共通
updated: 2026-08-31
colors:
  bg-dark: "#0F1217"
  panel-dark: "#161C23"
  text-dark: "#E7ECF4"
  accent-dark: "#4CC2FE"
  stamp-dark: "#FF6E4F"
  bg-light: "#F1F4F8"
  panel-light: "#FFFFFF"
  text-light: "#1A222E"
  accent-light: "#0272AC"
typography:
  body: 'font-family: "Hiragino Kaku Gothic ProN","Hiragino Sans","Noto Sans JP","BIZ UDPGothic","Yu Gothic","Meiryo",system-ui,-apple-system,sans-serif'
  mono: 'font-family: "SFMono-Regular","Menlo","Cascadia Code","Consolas",monospace'
components: {}
rounded: "0（--radius・--radius-sm ともに0固定）"
spacing: "--page-gutter 40px / --grid-size 24px / --sidebar-w 248px"
---

# 共通デザインシステム（リバース版・プロジェクト共通/DESIGN.md）

本書は、対象リポジトリが生成するポータルHTML群に共通するデザイントークンの記録です。画面が対象外である判定の記録は docs/scope-and-progress/excluded-kinds.json を正とします。本書は、複数画面から観測された値ではなく、生成物であるポータルHTML群が共通で参照するデザイントークン定義から転記します。トークン定義の実体は delivery-payload/templates/tokens.css です。個別の生成物固有の逸脱は、本書が扱う共通の範囲には含めません。

## Overview

CSSカスタムプロパティで定義した26種の基本色トークンと、非色トークン（フォント・角丸・影・余白）から採録しました。既定はダークテーマであり、OSのライト設定または data-theme="light" 指定でライトテーマへ切り替わります。

## Colors

| トークン名 | ダーク値 | ライト値 | 用途 |
|---|---|---|---|
| bg | #0F1217 | #F1F4F8 | ページ全体の背景 |
| panel | #161C23 | #FFFFFF | パネル・カードの背景 |
| text | #E7ECF4 | #1A222E | 本文テキスト |
| accent | #4CC2FE | #0272AC | 主要リンク・アクセント |
| stamp | #FF6E4F | #FF6E4F | 差し色（強調・警告帯） |

## Typography

| トークン名 | 値 |
|---|---|
| font-body | Hiragino Kaku Gothic ProN, Hiragino Sans, Noto Sans JP, BIZ UDPGothic, Yu Gothic, Meiryo, system-ui, sans-serif |
| mono | SFMono-Regular, Menlo, Cascadia Code, Consolas, monospace |

## Components

対象リポジトリのポータルHTML群は、複数画面共通のUIコンポーネントではなく、共通シェル（partials）としてサイドバー・フッター・方眼紙背景を持ちます。共通シェルの実体は delivery-payload/templates/partials/ です。

## レスポンシブ基準

対象リポジトリのポータルHTML群は、共通シェルの全画面フィットレイアウトを採用しています。height:100vhとoverflow:hiddenの組で固定し、メインコンテンツ領域のみスクロールさせます。ブレークポイントによるレイアウト切替の実装は見つかりません。実在しない（理由: レスポンシブブレークポイントの定義がtokens.cssに存在しないため）。

## アクセシビリティ基準

| 観点 | 実装済みの共通要件 |
|---|---|
| 角丸 | 0固定（--radius・--radius-sm ともに0。角丸を使わない方針） |
| 影 | オフセットのみ（--shadow-smは3px 3px 0、--shadow-mdは4px 4px 0。ぼかし半径を持たない） |
| テーマ切替 | prefers-color-schemeメディアクエリとdata-theme属性の両方で明暗を切替可能 |
