---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.html"
  - "**/*.css"
  - "**/*.scss"
---

# UI実装基準（CODE-UI-STANDARDS）

Web アプリの UI 実装（コンポーネント・スタイル・テンプレート）に適用する合格基準。作成時に守るべき規約であると同時に、レビュー時の照合観点表そのものである。レビューでは code-reviewer が本ファイルを Read して照合する（フォルダ `review-checklist/code/` 配下 = code-reviewer 担当）。

現時点の基準はアイコンの 1 領域。UI 実装の観点（不要な再レンダリングの詳細基準・アクセシビリティ等）を増やす場合は、新しい `## 見出し` として本ファイルに追記する。

## アイコン

Web アプリの UI にアイコンを使用する場合、Google Material Symbols Outlined を必須とする。

### 必須事項

1. **アイコンソース**: https://fonts.google.com/icons から選択する
2. **フォントファミリ**: `Material Symbols Outlined` を使用する
3. **読み込み方法**: `<link>` タグで Google Fonts CDN から読み込む

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" />
```

4. **使用方法**: `<span>` タグに `material-symbols-outlined` クラスを付与する

```html
<span className="material-symbols-outlined">expand_more</span>
```

### 禁止事項

1. **Unicode 記号をアイコン代わりに使うこと** — `▲` `▼` `◀` `▶` `✕` 等の記号文字をアイコンとして使用しない
2. **絵文字をアイコン代わりに使うこと** — `🏠` `📊` `⚙️` 等の絵文字を UI アイコンとして使用しない
3. **他のアイコンライブラリを混在させること** — Lucide、Heroicons、Font Awesome 等を併用しない

## プロジェクト上書き

- 上書き可否: 一律適用
- 理由: 全プロジェクトの UI 統一が目的の規約であり、プロジェクト別アイコンシステムを許すと目的が崩れるため受け口を設けない

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。
