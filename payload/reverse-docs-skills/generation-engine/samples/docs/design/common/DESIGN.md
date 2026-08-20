---
doc_id: design-common
type: design
status: traced
target_screen: _プロジェクト共通
updated: 2026-07-23
colors:
  primary: "#1a73e8"
  surface: "#ffffff"
  on-surface: "#1f1f1f"
  error: "#d93025"
typography:
  heading: "20px / line-height 28px / font-weight 600"
  body: "14px / line-height 20px / font-weight 400"
  label: "12px / line-height 16px / font-weight 500"
components:
  DataTable: "行ホバーで背景をsurface-hoverへ変更し、選択行は左端にprimaryの4pxアクセントバーを表示する"
  StatusBadge: "角丸4pxの塗りつぶしバッジ。状態値ごとに背景色を切り替える"
rounded: "4px（ボタン・カード・バッジ共通）"
spacing: "8pxグリッド（4/8/16/24/32pxの5段階）"
---

# 共通デザインシステム（リバース版・プロジェクト共通/DESIGN.md）

本書は複数のレガシー画面から共通して観測されたスタイル・数値の記録である。既存コードに実際に存在する共通のデザイントークン（テーマ変数・共通スタイルシート等）をそのまま転記する。個別画面の詳細設計書内DESIGN.mdはここからの **差分（画面固有の逸脱）のみ** を持ち、同じ値を重複して書いてはならない。

## Overview

CSSカスタムプロパティで定義した共通トークン（`--color-primary`等）と、ThemeContextが保持するライト/ダーク2テーマの値から採録した。

## Colors

複数画面で共通して観測された値のみを転記する。1画面にしか出てこない値は書かない。

| トークン名 | 用途 |
|---|---|
| primary | 主要ボタン・リンク・フォーカスリング |
| surface | 画面背景・カード背景 |
| on-surface | 本文テキスト |
| error | エラーメッセージ・バリデーション失敗 |

## Typography

| トークン名 | 用途 |
|---|---|
| heading | 画面タイトル・セクション見出し |
| body | 本文・データ表示 |
| label | 入力ラベル・テーブルヘッダ |

## Components

全画面共通のコンポーネント（ボタン・入力欄・カード等）の実装済み視覚原則を書く。

| 共通コンポーネント | 実装済みの視覚原則 |
|---|---|
| `DataTable` | 行ホバーで背景をsurface-hoverへ変更し、選択行は左端にprimaryの4pxアクセントバーを表示する |
| `StatusBadge` | 角丸4pxの塗りつぶしバッジ。状態値ごとに背景色を切り替える |
| `Toast` | 右下からスライドインし、4秒後に自動でフェードアウトする |

## レスポンシブ基準

| ブレークポイント名 | 実測した幅 | 実装済みレイアウト |
|---|---|---|
| tablet | 768px | サイドバーを折りたたみアイコンのみの表示へ切り替える |
| desktop | 1280px | サイドバーを常時展開表示に切り替える |

## アクセシビリティ基準

| 観点 | 実装済みの共通要件 |
|---|---|
| カラーコントラスト | primaryとsurfaceの組で4.5:1以上を確保 |
| フォーカス可視性 | フォーカスリングをprimaryの2px実線で表示 |
| スクリーンリーダー | モーダル・トーストに `aria-live` / `aria-modal` を付与 |
