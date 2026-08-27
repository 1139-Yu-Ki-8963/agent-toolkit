---
doc_id: design-screen-home
type: design
status: traced   # draft | traced（値が全て既存コードからの抽出値に置き換わった状態）
target_screen: screen-home   # ./画面詳細設計書.md の target_screen と常に同値にする
source_design: ./画面詳細設計書.md
updated: 2026-07-24
colors:
  primary: "#1a73e8"
  surface: "#ffffff"
  on-surface: "#1f1f1f"
  error: "#d93025"
  badgeCount: "#d93025"
typography:
  heading: "20px / line-height 28px / font-weight 600"
  body: "14px / line-height 20px / font-weight 400"
  label: "12px / line-height 16px / font-weight 500"
components:
  SideNav: "幅240px固定。項目間の余白は8pxグリッドの16px単位"
  NotificationBell: "アイコン右上にbadgeCountの円形バッジ（直径16px）を重ねて表示"
rounded: "4px（バッジ・カード共通。プロジェクト共通/DESIGN.mdと同値）"
spacing: "8pxグリッド（プロジェクト共通/DESIGN.mdと同値）"
---

# ホーム画面 デザイン仕様（DESIGN.md・リバース版）

本書が指す節番号は `画面詳細設計書.md` のものです。この参照を（詳細: 節番号）と表記します。


本書はレガシー画面の実装から抽出したスタイル・数値の記録です。ただし複数画面共通のデザイン値は `../../プロジェクト共通/DESIGN.md` が上位の正であり、本書は「画面固有の差分の実測記録」のみを持つ（`プロジェクト共通/DESIGN.md` と同じ値を重複して書かない）。往復検証の「正は既存挙動の忠実再現であり、あるべき仕様ではない」という原則に従い、デザイン改善案ではなく **既存コードの実測値** のみを扱います。画面状態の一覧の定義権は `./画面詳細設計書.md （詳細: §5）` にある。

## Overview

> `target_screen` は `./画面詳細設計書.md` の同フィールドと常に同値にすること。一方を変更したら他方も変更する。

サイドナビと通知ベルの2領域だけがプロジェクト共通のトークンから逸脱する画面固有スタイルを持ち、それ以外はプロジェクト共通のコンポーネント（DataTable・StatusBadge・Toast）をそのまま利用する実装です。

## Colors

<!-- 既存コードの CSS・スタイルファイル・computed style から実測した値をそのまま転記する -->
<!-- frontmatter の colors セクションも実測値に置き換える -->

| トークン名 | 用途 | 実測値の抽出元 |
|---|---|---|
| primary | 主要アクション・フォーカス表示 | `components/SideNav.module.css`（プロジェクト共通と同値のため差分なし） |
| surface | 画面背景・カード背景 | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |
| on-surface | 本文テキスト | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |
| error | エラーメッセージ・バリデーション失敗 | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |
| badgeCount | 未読通知バッジの背景色 | `components/NotificationBell.module.css` の `.badge { background: #d93025 }` |

## Typography

<!-- 既存コードのフォント指定を実測して転記する -->

| トークン名 | 用途 | 実測値の抽出元 |
|---|---|---|
| heading | 画面タイトル・セクション見出し | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |
| body | 本文・データ表示 | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |
| label | 入力ラベル・テーブルヘッダ | `pages/HomePage.module.css`（プロジェクト共通と同値のため差分なし） |

## Components

<!-- （詳細: §3）（./画面詳細設計書.md （詳細: §3） 画面構造）で定義した領域名と同名の項目で記述する -->

### SideNav

幅240px固定のサイドナビゲーション。メニュー項目の高さは40px、項目間の余白は16px（8pxグリッドの2単位）。選択中の項目は左端にprimaryの4pxアクセントバーを表示する（プロジェクト共通のDataTable選択行と同じ視覚パターン）。

### NotificationBell

通知ベルアイコン（24px×24px）の右上に、直径16pxの円形バッジをbadgeCountの背景色で重ねて表示する。バッジ内の数値フォントはlabelトークンを流用する。

## 画面状態の視覚仕様

<!-- 状態一覧の定義権は ./画面詳細設計書.md （詳細: §5） にある。本節はその各状態の「実装済みの見え方」のみを担う -->

| 状態 | 実装済みの見せ方 | アニメーション・トランジション |
|---|---|---|
| loading | ダッシュボード集計カード3枚分をスケルトン表示（プロジェクト共通のスケルトン行と同じ視覚パターン） | フェードイン200ms |
| empty | 該当なし（本画面は集計値0件でも「0件」として通常表示する） | — |
| error | 画面上部にエラーバナーを表示し、リトライボタンのみ操作可能にする | フェードイン150ms |
| ready | 通常表示 | — |

## レスポンシブ仕様

<!-- 既存コードのブレークポイント定義を実測して転記する -->

| ブレークポイント | 実装済みのレイアウト変更点 |
|---|---|
| tablet（768px） | SideNavをアイコンのみの折りたたみ表示へ切り替える（プロジェクト共通と同値） |
| desktop（1280px） | SideNavを常時展開表示に切り替える（プロジェクト共通と同値） |

## アクセシビリティ

<!-- （詳細: §11）（./画面詳細設計書.md （詳細: §11） エラーハンドリング）等との整合を実測ベースで確認する -->

| 観点 | 実装済みの状態 |
|---|---|
| フォーカス管理 | Tabキーでヘッダー→SideNav→通知ベル→メインコンテンツの順に移動する（プロジェクト共通の `共通設計書.md` §2 と同じ順序） |
| スクリーンリーダー対応 | NotificationBellのバッジに `aria-label="未読通知{件数}件"` を付与する |
| カラーコントラスト | primaryとsurfaceの組で4.5:1（プロジェクト共通と同値のため差分なし） |
