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

## 適用範囲

- 説明用 HTML は縮退モード（1〜2 ファイルの軽微修正）以外の全タスクで必須
- 画面変更を伴うタスクでは、説明 HTML 内の画面モックを実装同等の忠実度（実デザイントークン・実 CSS）で作成する。承認後にマークアップを実装へ流用できる水準を正とする
- 画面のない変更（DB・ロジックのみ）では proposal の画面部分を「対象外」とし、db-schema / domain-logic / api-contract が本体となる
- 承認済みモックと実装が乖離する場合はモックを更新して再承認を得る（mock-archive は内容ハッシュ別に版が残るため旧版は自動保存される）

## skill marker（最重要）

`<head>` 内または `<body>` 冒頭の **先頭 1KB 以内** に必ず含める。

```html
<!-- generated-by: creating-mock v1 -->
```

PostToolUse(Write|Edit|MultiEdit) hook の `scripts/check-mock-html.sh` がこの marker を検知して mock 品質検証を発火する。
marker 不在の Write/Edit は検査対象外（exit 0・既存 60+ mock との後方互換）。

## 必須 section（13 種・layout-uniformity の正本）

| section id | h2 タグの想定タイトル | 必須子要素 |
|---|---|---|
| `background` | 背景 | — |
| `proposal` | 提案 | — |
| `acceptance` | 受け入れ条件 | `<ul>` 必須 |
| `placement` | 配置 | — |
| `related` | 関連 | — |
| `risks` | リスク | — |
| `db-schema` | DB設計 | 読み書きするテーブルの表形式定義。データ永続化を伴わない画面は「対象外」+ 判断理由 1 行 |
| `domain-logic` | ドメインロジック | 業務ルール・状態遷移・バリデーション一覧。データ永続化を伴わない画面は「対象外」+ 判断理由 1 行 |
| `api-contract` | API契約 | この画面が呼ぶエンドポイント一覧（メソッド・パス・リクエスト型・レスポンス型・エラー形式）の表形式定義。バックエンド変更を伴わない場合は既存 API の参照一覧。API を伴わない画面は「対象外」+ 判断理由 1 行 |
| `role-visibility` | 権限・ロール別表示 | ロールごとに見える/操作できる項目の差分表。ロール概念のないアプリは「対象外」+ 判断理由 1 行 |
| `screen-flow` | 画面遷移マップ | 前後の画面と遷移条件のテキストベースの遷移図または表。`placement` が「位置」を、本 section が「遷移」を担当する |
| `acceptance-tests` | 受け入れテスト観点 | `acceptance` を条件・操作・期待結果のテストケース形式に構造化した表 |
| header（section ではない） | issue 番号 + タイトル | `<h1 class="mock-title">` |

各 section の `id` 属性は **完全一致** で書く（hook が grep する）。`h2` の中身（タイトル文言）は自由。

例外規定の統一: `db-schema` / `domain-logic` / `api-contract` / `role-visibility` は該当概念がない画面では「対象外」+ 判断理由 1 行で充足する（セクション省略は不可）。

検査 hook の実装: PostToolUse(Write|Edit|MultiEdit) の `scripts/check-mock-html.sh` が id 完全一致で検査し、欠落時は `[MOCK-HTML-BLOCK]` で差し戻す（2026-07-23 実装。それ以前の記述は実体のない参照だった）。

## 表現規約（認知設計）

13 セクションは「何を書くか」を定める。本節は「どう見せるか」を定める。以下 6 項目は必須。出典: generating-explainer 系の認知設計カタログ（段階的開示・バッジ・読む順序・ビュー切替）+ html-output 規約の図解義務。

### 1. 読み順ナビ（冒頭必須）

h1 直後に「このモックの読み方」を置き、読み手別の読む順序を提示する。最低 2 経路: 承認判断者向け（`proposal` → `acceptance-tests` → `risks` の 3 セクションで判断が完結する導線）と実装者向け（`placement` → `db-schema` → `domain-logic` → `api-contract`）。

### 2. proposal のビフォー/アフタータブ（必須）

`proposal` 内の画面モックは「現状」「変更後」の 2 タブ切替とする（自己完結 JS・タブに `aria-selected`、パネルに `role="tabpanel"`）。新規画面の場合は「現状」タブに「画面なし（新規）」と遷移元画面を表示する。変更後タブでは差分点に「変更」「新規」バッジまたはハイライトを付け、どこが変わるかが一目で分かる状態を正とする。

### 3. 全体図 ⇄ 詳細の対提示（2 ペイン原則）

構造を持つセクション（`domain-logic` の状態遷移・`screen-flow` の遷移・`db-schema` のテーブル関連）は、まず全体図（SVG または罫線図）を示し、詳細表をその直下に対で置く。図だけで概要が、表だけで正確な定義が把握できる状態を正とする。

### 4. 重要度バッジ

`risks` は重大度（高/中/低）、`acceptance-tests` は優先度（必須/推奨）、状態遷移・スキーマ・API の新規追加分は「新規」バッジを付す。色はデザイントークンの success / gold / danger 系を使い、色だけに依存せずテキストでも判別可能にする。

### 5. 段階的開示

8 行を超える表は、サマリー（件数 + 要点 1 行）を常時表示し、全行は `details`/`summary` の折りたたみで提供する。折りたたみ時にも何がいくつあるかが分かること。

### 6. 図解義務（html-output 規約の適用）

`~/.claude/rules/scoped/review-checklist/document/html-output/rule.md` の「図解候補の全件調査」と「構造・図解の採用評価 5 項目」をモックにも適用する。意味関係（遷移・依存・比較・因果・包含）を文章・表だけで提示し、図解可能性を未検討のまま残すことを禁止する。図解を不採用にした候補は理由を 1 行記録する（HTML コメントで可）。

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

画面部分は実装同等（実デザイントークン・実 CSS 使用。`flow-values.yml` の `design_system` 参照）の忠実度で作成する（「適用範囲」節参照）。

## 検証 hook の発火フロー

```
Write|Edit|MultiEdit(*.html)
  ↓
PostToolUse → scripts/check-mock-html.sh
  ↓
1) 対象が .html か（非 .html は exit 0）
2) skill marker（先頭 1KB 以内の generated-by: creating-mock）を持つか（無ければ exit 0）
3) 必須 13 section の id 完全一致 check（background / proposal / acceptance / placement /
   related / risks / db-schema / domain-logic / api-contract / role-visibility /
   screen-flow / acceptance-tests + header の <h1 class="mock-title">）
  ↓
全 pass → exit 0
1 つでも fail → stderr に [MOCK-HTML-BLOCK] + 欠落 id 一覧を出力して exit 2
```

## 承認前 hook の発火フロー

```
serve.py が /api/approve POST を受信
  ↓
check-mock-approval-ready.sh を exec
  ↓
state.json 全 mock_awaiting task について:
  1) archive_history 末尾 URL の HTTP 200
  2) 必須 13 section の DOM 一致
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
