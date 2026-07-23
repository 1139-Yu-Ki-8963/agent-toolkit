---
name: generating-icon-catalog-for-reverse-docs
description: |
  対象リポジトリの JSX/HTML からアイコン参照を抽出し、カタログ HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の「基盤ページ未生成（任意）」状態キーから起動された時、「アイコンカタログを生成」と言われた時。
  SKIP: 対象リポジトリにアイコン参照が 0 件の時。
invocation: generating-icon-catalog-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# アイコンカタログページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの基盤ページ受け口のうちアイコンカタログ（`pageKind: icon-catalog`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`target_repo_path` 配下の JSX/HTML を単一の事実源とし、Material Icons・SVG import・React icons コンポーネントの 3 パターンを機械的に抽出してアイコンカタログ.html を組み立てる。**本スキルは判定・評価を一切行わない**。実コードに現れたアイコン参照（アイコン名・参照元ファイル・行番号・件数）の転記に徹する。

## 使用タイミング

- 対象リポジトリにアイコン参照（Material Icons/SVG import/React icons コンポーネント）が存在し、ポータルにアイコンカタログカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/アイコンカタログ.html` に固定する。

## 設計原則

- **転記のみ** — アイコン使用の妥当性・重複の是非は判定しない。実コードに現れた参照パターン（3 種類固定）に一致した事実のみを転記する
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（3 パターンの grep 走査・出現箇所集計）は `extract-icon-usage.sh` が固定ルールで機械的に行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| アイコン抽出 | `../../../shared/scripts/extract/extract-icon-usage.sh` |
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: アイコン参照の存在確認

- **Step 1** — `target_repo_path` 配下に Material Icons／SVG import／React icons コンポーネントのいずれかの参照が存在するか `grep` で確認する。1 件も無ければハード停止し、アイコン参照が 0 件である旨を報告して終了する。完了条件: 1 件以上の実在確認済み、または 0 件を報告して停止している

### Phase 2: アイコン参照抽出（機械実行）

- **Step 1** — 抽出スクリプトを実行する。完了条件: page-data.json が生成済み

  ```
  ../../../shared/scripts/extract/extract-icon-usage.sh <target_repo_path> <page-data.json>
  ```

- **Step 2** — `summary.totalIcons`・`summary.totalUsages`・`summary.bySource` を確認する。完了条件: 抽出結果を確認済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/icon-catalog-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は指摘に応じて修正し Step 1 を再実行する。3 回失敗したら Phase 2（抽出手順）へ差し戻す。完了条件: exit 0

### Phase 4: アイコンカタログ.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/アイコンカタログ.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page icon-catalog
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | アイコン参照の 1 件以上の実在確認済み、または 0 件を報告して停止している |
| Phase 2 | アイコン参照が抽出済み、抽出結果（総数・使用回数・参照元内訳）を確認済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/アイコンカタログ.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 対象リポジトリの実コードのみからアイコンカタログ.html が生成され、3 パターン以外の参照方式は捏造なく対象外として扱われている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（アイコン参照 0 件）\| `ERROR` |
| artifacts | 生成したアイコンカタログ.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `icon-catalog`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（アイコン参照 0 件）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。アイコン使用の妥当性・重複には一切踏み込まず、実コードの参照事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のアイコンカタログ.html のみ

## 予想を裏切る挙動

- 抽出対象は Material Icons（`material-symbols-outlined`/`material-icons` タグ内）・SVG import（`.svg` ファイル名込み）・React icons コンポーネント（`<Lucide*`/`<Hero*`/`<FontAwesome*`）の 3 パターンに固定される。これ以外の独自アイコン参照方式（CSS `background-image` 等）は抽出対象外であり、0 件でも異常ではない
- grep 該当が 0 件の場合もエラーにせず `icons:[]` で正常終了する（fail-safe）。ただし本スキルの Phase 1 は事前に存在確認を行うため、Phase 2 到達後の 0 件は想定外の乖離として扱い、Phase 1 の判定条件を見直す

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
