# creating-mock conventions

`creating-mock`（本 references の `module-creating-screen-mock.md`）が出力する HTML mock の **命名 / 構造 / CSS トークン** の正本。

## 命名規約

| 項目 | 値 |
|---|---|
| ファイル名 | `<sha8>-mockup.html` |
| `<N>` | GitHub issue 番号（数字のみ） |
| `<sha8>` | `date +%s \| sha256sum \| cut -c1-8`（macOS fallback: `date +%s \| md5 \| cut -c1-8`）で生成 |
| suffix | `-mockup.html` 固定 |
| 配置先 | `~/.claude/mock-archive/issue-<N>/<sha8>-mockup.html` |

配置先・ファイル名の正本は `module-creating-screen-mock.md` であり、本ファイルはそれに追従する。

## skill marker（最重要）

`<head>` 内または `<body>` 冒頭の **先頭 1KB 以内** に必ず含める。

```html
<!-- generated-by: creating-mock v1 -->
```

PostToolUse(Write) hook の `check-mock-html.sh` がこの marker を検知して mock 品質検証を発火する。
marker 不在の Write は warning（既存 60+ mock との後方互換）。

## 必須 section（7 種・layout-uniformity の正本）

| section id | h2 タグの想定タイトル | 必須子要素 |
|---|---|---|
| `background` | 背景 | — |
| `proposal` | 提案 | — |
| `acceptance` | 受け入れ条件 | `<ul>` 必須 |
| `placement` | 配置 | — |
| `related` | 関連 | — |
| `risks` | リスク | — |
| header（section ではない） | issue 番号 + タイトル | `<h1 class="mock-title">` |

各 section の `id` 属性は **完全一致** で書く（hook が grep する）。`h2` の中身（タイトル文言）は自由。

## CSS トークン（5 種）

`<style>` 内 `:root` に集約する。

```css
:root {
  --mock-max-width: 1080px;
  --mock-accent: #2563eb;
  --mock-text: #1f2937;
  --mock-panel-bg: #f8fafc;
  --mock-font: -apple-system, "Hiragino Sans", sans-serif;
}
```

トークンを上書きしたい場合は別 CSS class を作る。`:root` の値は変えない。

## 検証 hook の発火フロー

```
Write(*-mockup.html)
  ↓
PostToolUse → check-mock-html.sh
  ↓
1) skill marker check
2) 必須 7 section check
3) <h1 class="mock-title"> check
  ↓
全 pass → exit 0
1 つでも fail → exit 0 + [MOCK-QUALITY-BLOCK] を additionalContext に注入
                ※ PostToolUse は exit 2 を持たないため warning として扱う
3 連発火 → auto-release（緊急バイパス）
```

## 承認前 hook の発火フロー

```
serve.py が /api/approve POST を受信
  ↓
check-mock-approval-ready.sh を exec
  ↓
state.json 全 mock_awaiting task について:
  1) archive_history 末尾 URL の HTTP 200
  2) 必須 7 section の DOM 一致
  3) skill marker 存在
  4) mock-archive directory 整合（#1587 連携）
  ↓
全 pass → 承認成立
1 件でも fail → 承認 block + reason 表示
3 連発火 → auto-release
```

## 予想を裏切る挙動

- `id="background"` を `id="bg"` 等に短縮しない（hook と一致しなくなる）
- `<h1 class="mock-title">` を `<h1>` だけにしない
- skill marker を `<!-- generated-by creating-mock -->`（コロン抜き）にしない
- bespoke style を増やしたい場合は section の中の class を新設する。`:root` のトークンは触らない
