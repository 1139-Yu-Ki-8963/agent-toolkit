---
doc_id: design-common
type: design
status: draft   # draft | approved | implemented
target_screen: _共通
updated: <YYYY-MM-DD>
colors:
  primary: "<project-primary>"              # プロジェクトの主要アクションカラーに置き換える
  primary-variant: "<project-primary-var>"  # hover・focus 状態の変化色
  surface: "<project-surface>"              # 画面背景・カード背景
  on-surface: "<project-on-surface>"        # 本文テキスト色
  error: "<project-error>"                  # エラー・バリデーション失敗
typography:
  heading: "<project-heading>"   # 画面タイトル・セクション見出し
  body: "<project-body>"         # 本文・データ表示
  label: "<project-label>"       # 入力ラベル・テーブルヘッダ
  caption: "<project-caption>"   # 補足テキスト・タイムスタンプ
components:
  # 全画面共通コンポーネントの視覚原則。個別画面の DESIGN.md は差分のみを持つ
rounded: "<project-radius>"   # ボタン・カード・入力欄の角丸半径
spacing: "<project-spacing>"  # 基準グリッド（例: 4px または 8px ベース）
---

# プロジェクト共通デザインシステム（_共通/DESIGN.md）

本書はプロジェクト全画面のスタイル・数値の **上位の正（権威ある仕様源）** である。
個別画面の `DESIGN.md` はここからの **差分のみ** を持ち、同じ値を重複して書いてはならない。

## Overview

<!-- プロジェクト開始時に <山括弧> プレースホルダをすべて実値に置き換えてから使う -->

<プロジェクト名> の全画面に適用するデザインシステム。ブランドカラー・タイポグラフィ・
コンポーネント原則の正本として、個別画面の DESIGN.md から参照される。

## Colors

<!-- frontmatter の colors セクションの値をプロジェクトの実値に置き換えてから参照する -->

| トークン名 | 用途 | 設定先 |
|---|---|---|
| primary | 主要ボタン・リンク・フォーカスリング | frontmatter `colors.primary` |
| primary-variant | hover・active 状態の強調 | frontmatter `colors.primary-variant` |
| surface | 画面背景・カード背景 | frontmatter `colors.surface` |
| on-surface | 本文テキスト | frontmatter `colors.on-surface` |
| error | エラーメッセージ・バリデーション失敗 | frontmatter `colors.error` |

## Typography

<!-- フォントファミリはプロジェクト単位で 1 種に統一することを推奨する -->

| トークン名 | 用途 | 設定先 |
|---|---|---|
| heading | 画面タイトル・セクション見出し | frontmatter `typography.heading` |
| body | 本文・データ表示 | frontmatter `typography.body` |
| label | 入力ラベル・テーブルヘッダ | frontmatter `typography.label` |
| caption | 補足テキスト・タイムスタンプ | frontmatter `typography.caption` |

## Components

<!-- 全画面に共通するコンポーネントの視覚原則を書く -->
<!-- 数値は frontmatter の rounded / spacing トークンを参照する -->

| 共通コンポーネント | 視覚原則 |
|---|---|
| ボタン（プライマリ） | `primary` 色・`rounded` 角丸。ラベルは `label` フォント |
| 入力欄 | `on-surface` 色ボーダー。フォーカス時は `primary` 色リング |
| カード | `surface` 色背景・`rounded` 角丸・`spacing` ベース内余白 |
| エラーインライン | `error` 色・`caption` フォント・入力欄直下に配置 |

## レスポンシブ基準

<!-- プロジェクト共通のブレークポイントを定義する -->
<!-- 個別画面の DESIGN.md はここからの差分のみを持つ -->

| ブレークポイント名 | 幅の目安 | 適用レイアウト |
|---|---|---|
| <sm> | <〜767px> | <モバイル：1カラム縦積み> |
| <md> | <768px〜1023px> | <タブレット：2カラム> |
| <lg> | <1024px〜> | <デスクトップ：サイドバーあり> |

## アクセシビリティ基準

<!-- 全画面共通の最低要件。各画面 DESIGN.md はここからの逸脱のみを記録する -->

| 観点 | 共通要件 |
|---|---|
| カラーコントラスト | WCAG 2.1 AA 準拠（通常テキスト 4.5:1 以上・大テキスト 3:1 以上） |
| フォーカス可視性 | フォーカスリングは `primary` 色で常時表示（outline: none 禁止） |
| スクリーンリーダー | 意味のある画像に `alt` 必須。装飾画像は `alt=""` |
| キーボード操作 | Tab キーで全インタラクティブ要素にアクセスできること |
