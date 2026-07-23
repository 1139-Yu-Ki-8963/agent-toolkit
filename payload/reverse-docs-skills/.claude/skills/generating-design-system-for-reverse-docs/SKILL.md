---
name: generating-design-system-for-reverse-docs
description: |
  共通 DESIGN.md の CSS トークンを抽出し、デザインシステム HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の「基盤ページ未生成（任意）」状態キーから起動された時、「デザインシステムを生成」と言われた時。
  SKIP: 共通 DESIGN.md が docs_root に存在しない時。
invocation: generating-design-system-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# デザインシステムページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの基盤ページ受け口のうちデザインシステム（`pageKind: design-system`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<docs_root>/プロジェクト共通/DESIGN.md` を単一の事実源とし、frontmatter の colors/typography/spacing/rounded/components を抽出してデザインシステム.html を組み立てる。**本スキルは判定・評価を一切行わない**。DESIGN.md に記載されたトークン値の転記に徹し、frontmatter 未検出時のみ CSS 変数への正規表現フォールバックを行う。

## 使用タイミング

- `<docs_root>/プロジェクト共通/DESIGN.md` が確定済みで、ポータルにデザインシステムカードを追加したいとき
- 起動引数: `docs_root`（DESIGN.md の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/デザインシステム.html` に固定する。

## 設計原則

- **転記のみ** — トークン値の妥当性（配色の良否・命名の是非）は判定しない。DESIGN.md の frontmatter・本文表に記載された事実（トークン名・値・用途）のみを転記する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（frontmatter パース・本文表との突合・CSS 変数フォールバック）は `extract-design-tokens-from-designmd.sh` が機械的に行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| トークン抽出 | `../../../shared/scripts/extract/extract-design-tokens-from-designmd.sh` |
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: DESIGN.md の存在確認

- **Step 1** — `<docs_root>/プロジェクト共通/DESIGN.md` の実在を `test -f` で確認する。存在しなければハード停止し、DESIGN.md が未作成である旨を報告して終了する。完了条件: 実在確認済み、または不在を報告して停止している

### Phase 2: トークン抽出（機械実行）

- **Step 1** — 抽出スクリプトを実行する。完了条件: page-data.json が生成済み

  ```
  ../../../shared/scripts/extract/extract-design-tokens-from-designmd.sh <DESIGN.md> <page-data.json>
  ```

- **Step 2** — `summary.totalTokens`・`summary.byCategory` を確認する。frontmatter 不在で CSS 変数フォールバックに落ちた場合（`components: []` 固定）はその旨を Phase 4 完了報告の注記に残す。完了条件: 抽出経路（frontmatter/フォールバック）を確認済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/design-system-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json>
  ```

- **Step 2** — FAIL 時は指摘に応じて修正し Step 1 を再実行する。3 回失敗したら Phase 2（DESIGN.md の記法との突合）へ差し戻す。完了条件: exit 0

### Phase 4: デザインシステム.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/デザインシステム.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page design-system
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | DESIGN.md の実在確認済み、または不在を報告して停止している |
| Phase 2 | トークンが抽出済み、抽出経路（frontmatter/フォールバック）を確認済み |
| Phase 3 | `validate-page-data.sh` が全項目 PASS |
| Phase 4 | `<docs_root>/デザインシステム.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | DESIGN.md の事実のみからデザインシステム.html が生成され、フォールバック抽出時はその旨が可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（DESIGN.md 不在）\| `ERROR` |
| artifacts | 生成したデザインシステム.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `design-system`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（DESIGN.md 不在）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。トークン値の妥当性には一切踏み込まず、DESIGN.md の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のデザインシステム.html のみ

## 予想を裏切る挙動

- `role`（用途）は frontmatter に存在しないため本文 Markdown 表（`## Colors` / `## Typography`）からトークン名で突合して補う。該当行が無ければ `role` は空文字となり、これは fail ではない
- `rounded:` は独立フィールドだが `spacing` 配列へ合流する。出力 JSON にトークン名 `rounded` として現れても spacing カテゴリの一員として扱う
- frontmatter が存在しない場合、`components` は常に `[]`（フォールバック対象外）。CSS 変数フォールバックはコンポーネント一覧を復元できない

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
