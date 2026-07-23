---
doc_id: ui-common-design
type: ui-common-design
status: traced   # draft | traced（全節が実測値で埋まった状態）
updated: 2026-07-23
---

# UI共通設計書

本書は複数のレガシー画面から抽出した、UI の設計方針を上位から俯瞰する記録である。あるべき UI 設計を新たに構想するのではなく、既存コードに実際に存在する共通方針のみを記載する。個々の状態・操作規則の詳細は `./共通設計書.md`、数値・色・フォントは `./DESIGN.md` を正とし、本書はそれらの要約・俯瞰に徹する。

## 本書に書かないもの

| 書かない内容 | 正の置き場 |
|---|---|
| 共通状態・操作規則の詳細（loading/empty/error 等） | `./共通設計書.md`（§1〜§3） |
| 数値・色・フォント（共通） | `./DESIGN.md` |
| 数値・色・フォント（画面固有差分） | 各画面の `../画面/詳細設計/DESIGN.md` |
| UI 文言 | `./メッセージ定義書.md` |
| コンポーネント実装規則（props 命名・分割方針等） | `./規約/コンポーネント設計規約.md` |
| 画面固有のレイアウト | 各画面詳細設計書 |

---

## §1 デザインシステム（実測）

| 項目 | 内容 | 根拠パス |
|---|---|---|
| 使用ライブラリ・デザインシステム | 独自実装のコンポーネントライブラリ（社内製 `@ec-admin/ui`） | `package.json` |
| バージョン | 2.4.0 | `package.json` |

---

## §2 共通コンポーネント一覧（実測）

| コンポーネント | 用途 | 使用画面数（頻度） | 根拠パス |
|---|---|---|---|
| DataTable | 一覧画面の表形式表示（ソート・ページング内蔵） | 22/44 | `src/components/common/DataTable.tsx` |
| ConfirmDialog | 確定・削除等の破壊的操作前の確認ダイアログ | 18/44 | `src/components/common/ConfirmDialog.tsx` |
| StatusBadge | 注文・請求・会員等の状態値をバッジ表示 | 30/44 | `src/components/common/StatusBadge.tsx` |
| Toast | 操作結果の通知トースト表示 | 44/44 | `src/components/common/Toast.tsx` |

---

## §3 レイアウト方針（実測）

| 要素 | 実装済みの原則 | 根拠パス |
|---|---|---|
| グリッドシステム | CSS Grid による 12 カラム構成 | `src/styles/grid.css` |
| ブレークポイント | 768px（タブレット）/ 1280px（デスクトップ）の 2 段階 | `src/styles/breakpoints.ts` |

---

## §4 テーマ・スタイル管理（実測）

| 項目 | 内容 | 根拠パス |
|---|---|---|
| CSS 設計方針 | CSS Modules（コンポーネント単位で `*.module.css` を併置） | `src/components/common/DataTable.module.css` |
| テーマ切替の有無 | ライト/ダークの 2 テーマ切替あり | `src/contexts/ThemeContext.tsx` |
| レスポンシブ対応方針 | 管理画面のためデスクトップファースト（モバイル最適化は対象外） | `src/styles/breakpoints.ts` |

---

## §5 アクセシビリティ方針（実測）

| 項目 | 内容 | 根拠パス |
|---|---|---|
| WAI-ARIA 対応 | モーダル・トーストに `aria-live` / `aria-modal` 属性を付与 | `src/components/common/Modal.tsx` |
| キーボード操作対応 | Tab キーによるフォーカス移動、Esc キーでモーダルを閉じる（詳細は `./共通設計書.md` §2 参照） | `src/components/common/Modal.tsx` |

---

## §6 画面横断 UI 状態（実測）

| 状態名 | 保持場所（store/context等） | 影響範囲（画面・コンポーネント） | 初期値 | 根拠パス |
|---|---|---|---|---|
| テーマ設定 | localStorage（キー: `theme-preference`） | 全 44 画面の共通レイアウト | light | `src/contexts/ThemeContext.tsx` |
| 通知トースト | Zustand ストア（`toastStore`） | 全画面共通ヘッダー配下の Toast コンポーネント | 空配列 | `src/stores/toastStore.ts` |
| モーダル開閉状態 | `ModalContext`（React Context） | 一覧・編集系の約 20 画面 | closed | `src/contexts/ModalContext.tsx` |
| サイドバー開閉 | localStorage（キー: `sidebar-collapsed`） | 全 44 画面の共通レイアウト | false（展開） | `src/components/layout/SidebarNav.tsx` |

---

## traced の条件

- 全節の実測値が既存コードまたは `./共通設計書.md`・`./DESIGN.md` からの要約で埋まっていること
- コード内に実在しない項目は「実在しない（理由: …）」で埋めること（空欄・省略は禁止）
