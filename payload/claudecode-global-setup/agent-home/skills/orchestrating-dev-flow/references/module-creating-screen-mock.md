# creating-screen-mock（orchestrating-dev-flow 内部モジュール）

# creating-unified-layout-html-mock

flow-feature Phase 4-3 等で issue mock HTML を生成する時の **唯一の正規ルート**。bespoke レイアウトの乱立を防ぎ、portal click → 表示・portal 承認サイクル・mock-archive 整合を保証する。

## 設計思想

- **必須 section 7 種** を欠かさず描画する（layout-uniformity の正本）
- **skill marker** をファイル冒頭に必ず埋め込む（PostToolUse hook が検知する）
- **CSS トークン** は `:root` に集約し、bespoke style を `<style>` 末尾で override しない
- **mock-viewer (#1587)** と **portal 承認 (#1505 / #1577)** が読みやすい構造を保つ

## 配置先

| 用途 | 配置先 |
|---|---|
| 正規 mock（直接 archive） | `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html` |

`<sha8>` は `date +%s | sha256sum | cut -c1-8` で生成（macOS fallback: `date +%s | md5 | cut -c1-8`）。
git commit / push 不要。owner が mock-archive に直接 Write する。repo への書き込みは行わない。

## 必須 section（7 種）

| section | DOM | 役割 |
|---|---|---|
| header | `<h1 class="mock-title">` | issue 番号 + title |
| skill marker | `<!-- generated-by: creating-mock v1 -->` | 検証 hook 用 marker（**file 冒頭 1KB 以内**） |
| 背景 | `<section id="background"><h2>背景</h2>` | 解決する課題 |
| 提案 | `<section id="proposal"><h2>提案</h2>` | 設計の核 |
| 受け入れ条件 | `<section id="acceptance"><h2>受け入れ条件</h2><ul>` | チェックリスト |
| 配置 | `<section id="placement"><h2>配置</h2>` | ファイル配置先 |
| 関連 | `<section id="related"><h2>関連</h2>` | 関連 issue / PR |
| リスク | `<section id="risks"><h2>リスク</h2>` | 想定リスク + 緩和 |

`acceptance` の `<ul>` は必須。それ以外は `<ul>` / `<table>` / `<pre>` / `<p>` 自由。

## CSS トークン（5 種）

`<style>` 内 `:root` に必ず定義する。bespoke で override しない。

```css
:root {
  --mock-max-width: 1080px;
  --mock-accent: #2563eb;
  --mock-text: #1f2937;
  --mock-panel-bg: #f8fafc;
  --mock-font: -apple-system, "Hiragino Sans", sans-serif;
}
```

## 手順

### Step 1: UI 画面の有無を判定

issue の仕様を確認し、「ユーザーが操作する画面（ページ・ダイアログ・モーダル等）が存在するか」を判定する。

| 判定 | mock_type | 追加 section |
|---|---|---|
| 画面あり（新規ページ・ダイアログ等） | `screen` | `<section id="screen-mock"><h2>画面モック</h2>` を 7 section の後に追加 |
| 画面なし（API・スクリプト・設定変更等） | `spec` | 7 section 構成のまま |

- `mock_type` は `.flow-handoff.md` の `mock_type:` フィールドに記載する（例: `mock_type: screen`）
- 画面ありの場合は `screen-mock` section にワイヤーフレーム・コンポーネント配置・インタラクション説明を記述する
- `screen-mock` section は必須 7 section の **後** に配置し、7 section の `id` 属性を変更しない

### screen-mock section の構造

screen 型モックでは `<section id="screen-mock">` 内に以下の構造を生成する:

#### トークン注入

DESIGN.md（flow-values.yml の design_system で指定）を YAML parse し、`#screen-mock` スコープ内に `--app-*` prefix の CSS 変数として注入する。テンプレートの `--mock-*` は spec 部分（7 section）専用で据え置き、`#screen-mock` 配下だけが `--app-*` を参照する。

```css
#screen-mock {
  --app-primary: /* DESIGN.md colors.primary */;
  --app-surface: /* DESIGN.md colors.surface */;
  --app-ink: /* DESIGN.md colors.ink */;
  --app-font-display: /* DESIGN.md typography.display.fontFamily */;
  --app-font-body: /* DESIGN.md typography.body.fontFamily */;
  --app-rounded-md: /* DESIGN.md rounded.md */;
  --app-spacing-md: /* DESIGN.md spacing.md */;
  /* 以下、DESIGN.md の全トークンを --app-* として展開 */
}
```

#### phone-frame 構造

```html
<section id="screen-mock">
  <h2>画面モック</h2>
  <div class="phone-frame" style="max-width: 430px; background: var(--app-surface); color: var(--app-ink); border-radius: 20px; padding: 16px; margin: 0 auto;">
    <div class="app-header">
      <!-- 画面基本設計書のヘッダー行を再現 -->
    </div>
    <div class="app-content">
      <!-- 画面基本設計書のコンテンツ行を DESIGN.md の panel/banner-card 等で装飾 -->
    </div>
    <div class="app-footer">
      <!-- 画面基本設計書のフッター行を再現 -->
    </div>
  </div>
  <p class="mock-note">※ コンポーネント配置と配色の確認用です。実装の完全再現ではありません。</p>
</section>
```

#### 入力情報（screen-mock 生成に必須）

1. **既存画面コンポーネントのコード**
   - 変更対象の .tsx / .vue ファイルを Read する
   - 現在の DOM 構造・JSX 構成・コンポーネント階層を把握する
   - 条件分岐（loading / error / empty / data loaded）ごとの表示を確認する

2. **既存 CSS / スタイルファイル**
   - コンポーネントに適用されている CSS を Read する
   - Tailwind / CSS Modules / styled-components 等の方式を確認する
   - 現在の色・フォント・間隔・レイアウトを把握する

3. **DESIGN.md のデザイントークン**
   - flow-values.yml の design_system で指定されたファイルを Read する
   - colors / typography / spacing / rounded / components の全トークンを取得する
   - #screen-mock スコープに --app-* CSS 変数として注入する

4. **画面設計書（コーディングレベルの詳細）**
   - docs/ 配下の画面基本設計書を Read する
   - 以下の 7 項目が含まれていることを確認する:
     - 画面レイアウト（コンポーネント配置と階層構造）
     - コンポーネント一覧（名前・props・variant）
     - 状態定義（loading / error / empty 等）
     - データバインディング（API レスポンスフィールドとの紐付け）
     - ユーザー操作（ボタン・リンク・フォームの動作）
     - エラー表示（トースト / インライン / フルスクリーン）
     - アニメーション / トランジション
   - 不足項目がある場合はヒアリング結果から補完する

5. **変更内容（ヒアリング結果）**
   - Phase 3 で確定した変更仕様を参照する

#### Before HTML の生成手順

1. 既存コンポーネントの JSX / テンプレートを HTML に変換する
2. CSS クラスをインラインスタイルまたは <style> ブロックに展開する
3. DESIGN.md のトークンを --app-* CSS 変数として適用する
4. ダミーデータ（画面設計書のデータバインディング定義に基づく）を埋め込む
5. phone-frame 構造で囲む

#### After HTML の生成手順

1. Before HTML をベースにする
2. 変更仕様（ヒアリング結果）に従い DOM 構造を変更する
3. 新規コンポーネントを追加する場合は画面設計書のコンポーネント定義に従う
4. 状態定義に基づき、変更後の各状態（loading / data loaded 等）を表現する
5. phone-frame 構造で囲む

### 2. テンプレを Read

`creating-screen-mock-template.html` を Read する。これが正規テンプレ。

### 3. 必須 section に内容を埋める

7 section の DOM 構造は変更せず、`<p>` / `<ul>` / `<table>` で内容を埋める。

### 4. file 先頭に skill marker を確認

`<head>` 内または `<body>` 冒頭に `<!-- generated-by: creating-mock v1 -->` が含まれているか確認する。**file 先頭 1KB 以内**に必ず配置。

### 5. sha8 生成 → Write で出力

Bash で sha8 を生成し `~/.claude/mock-archive/issue-<N>/` を mkdir してから Write する。

```bash
sha8=$(date +%s | sha256sum | cut -c1-8 2>/dev/null || date +%s | md5 | cut -c1-8)
mkdir -p ~/.claude/mock-archive/issue-<N>
```

Write の `file_path` は **絶対パス** で `~/.claude/mock-archive/issue-<N>/${sha8}-mockup.html`（`<N>` と `${sha8}` を実際の値に置換）。
git commit / push は不要（mock-archive は git 管理外・直接書き出し）。

### 6. Artifact で公開

Write 完了後、Artifact ツールで公開する。

```
Artifact({
  file_path: "~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html",
  favicon: "🖼️",
  description: "issue #<N> <タイトル> の画面モック"
})
```

発行された URL を `phase-4-prd-creation.md` Step 4-5 の定型文でユーザーに提示する。

**なぜ mock-archive への直接書き出しと Artifact 公開を両方行うか**: mock-archive は既存 mock 一覧（mock-viewer, `~/.claude/mock-archive/index.html`）による永続的なローカル記録であり、issue 横断の履歴参照に使う。Artifact は都度の確認用に共有可能な URL を発行するためのものであり、役割が異なる。どちらか一方に一本化せず両方維持する。

## 予想を裏切る挙動

- skill marker を file 末尾に置くと PostToolUse hook が早期 read で見落とす可能性 → **必ず先頭 1KB 以内**
- section の `id` 属性を変えない（hook が `id="background"` 等を grep する）
- `<h1>` に `class="mock-title"` を付け忘れない
- 既存 mock の改修も本モジュール経由で行う（marker 不在の旧 mock は graceful に warning のみ）
- テンプレートに `<!DOCTYPE html>` / `<html>` / `<head>` / `<body>` タグを追加しない。Artifact ツールは公開時にファイル内容を独自の `<head>`/`<body>` 骨格で包むため、これらのタグを自前で含めると公開後に構造が壊れる（`<title>` / `<meta charset>` / `<style>` は骨格タグなしでそのまま書いてよい）

## 参照資料

- `creating-screen-mock-template.html` — 正規テンプレ
- `creating-screen-mock-conventions.md` — 命名規約 + CSS トークン定義
- `creating-screen-mock-examples-issue-1588-mockup.html` — 見本（本 issue 自身）
