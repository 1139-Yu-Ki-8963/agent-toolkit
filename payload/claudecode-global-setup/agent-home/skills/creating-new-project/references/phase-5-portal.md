# Phase 5: プロジェクトポータル（詳細手順）

> `creating-new-project/SKILL.md` の Phase 5 詳細。

vanilla JS SPA のプロジェクト管理ポータルを構築する。ビルドツール不要、ES modules + hash routing。

## 5-1. ディレクトリ作成

```
project-portal/
├── index.html
├── style.css
├── src/
│   ├── main.js
│   ├── top.js
│   ├── category-view.js
│   ├── master-table-detail.js
│   ├── master-util.js
│   ├── dom.js
│   └── common/
│       ├── header.js
│       ├── theme.js
│       ├── search-ui.js
│       ├── search-index.js
│       ├── toc.js
│       └── shortcuts.js
├── data/
│   ├── manifest.js
│   ├── design-docs.js
│   ├── search-index.js
│   ├── page-graph.js
│   ├── release-notes.js
│   ├── mocks.js
│   └── master-tables/
│       ├── index.js
│       ├── features.js
│       ├── screens.js
│       ├── techstack.js
│       └── project-index.js
├── sites/
│   └── rules/
│       └── index.html
├── mocks-archive/
│   └── .gitkeep
└── tools/
    └── serve.py
```

## 5-2. index.html

ポータルのエントリポイント。構成要素:
- ヘッダー（プロジェクト名 + ナビゲーション）
- 品質サマリ（metrics-mount）
- テストカバレッジ（coverage-mount）
- ドキュメント入口（docs-entry-mount）

`<project>` の `project-portal/index.html` をリファレンスとし、プロジェクト名・タイトルを置換して生成する。

## 5-3. data/ ファイル群

Phase 1 の機能・画面・スタック情報から初期データを生成する。

- `manifest.js` — カテゴリ・ツール定義（ルール一覧・マスタ一覧・フロー一覧・デザイン・設計書）
- `master-tables/features.js` — 機能マスタ（Phase 1 の機能リストから生成）
- `master-tables/screens.js` — 画面マスタ（Phase 1 の画面リストから生成）
- `master-tables/techstack.js` — 技術スタック（Phase 1 のスタック選択から生成）
- `master-tables/project-index.js` — プロジェクト索引（ディレクトリ構造・設計ドキュメント体系）
- `design-docs.js` — docs/ → カテゴリ対応表（Phase 4 で生成した設計書の一覧）
- `release-notes.js` — 空のリリースノート配列
- `mocks.js` — 空の mock 一覧
- `search-index.js` — 空の検索インデックス
- `page-graph.js` — 空のページ間リンク

## 5-4. src/ SPA ロジック

ハッシュルーター + カードグリッド + テーブル詳細表示の SPA を生成する。

- `main.js` — ハッシュルーター（`#/`, `#/category/<id>`, `#/table/<id>`）
- `top.js` — TOPページ（manifest.js からカードグリッドを描画）
- `category-view.js` — カテゴリ詳細（sections と tools を描画）
- `master-table-detail.js` — マスタテーブル表示
- `dom.js` — DOM ヘルパー
- `master-util.js` — テーブル描画ユーティリティ
- `common/` — 共有モジュール（ヘッダー・テーマ切替・検索 UI・目次・ショートカット）

`<project>` の `project-portal/src/` をリファレンスとし、プロジェクト固有の参照を汎化して生成する。

## 5-5. style.css

ポータルの共通スタイル。ダーク/ライトテーマ対応。カード・テーブル・ナビのスタイル定義。

## 5-6. tools/serve.py

ポータル開発サーバー。ポート管理規約に基づくポート（`<base_port+2>`）を使用する。
