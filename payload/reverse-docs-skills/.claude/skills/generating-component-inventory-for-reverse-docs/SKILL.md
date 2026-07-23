---
name: generating-component-inventory-for-reverse-docs
description: |
  対象リポジトリのコンポーネントファイルを走査し、棚卸し HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の「基盤ページ未生成（任意）」状態キーから起動された時、「コンポーネント棚卸しを生成」と言われた時。
  SKIP: 対象リポジトリに .tsx/.jsx/.vue ファイルが存在しない時。
invocation: generating-component-inventory-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# コンポーネント棚卸しページ生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの基盤ページ受け口のうちコンポーネント棚卸し（`pageKind: component-inventory`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`target_repo_path` 配下の `.tsx`/`.jsx`/`.vue` ファイルを単一の事実源とし、export 名・props 有無・ディレクトリ由来の分類・被参照件数を決定的に抽出してコンポーネント棚卸し.html を組み立てる。**本スキルは自動分類（taxonomy inference）を一切行わない**。分類はディレクトリパスから機械的に導出するのみで、責務推定・意味的グルーピングの判断は行わない。

## 使用タイミング

- 対象リポジトリに `.tsx`/`.jsx`/`.vue` ファイルが存在し、ポータルにコンポーネント棚卸しカードを追加したいとき
- 起動引数: `target_repo_path`（調査対象リポジトリの絶対パス）・`docs_root`（出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/コンポーネント棚卸し.html` に固定する。

## 設計原則

- **自動分類なし** — 分類（`category`）はディレクトリパスから導出する（`components/`・`pages/`・`layouts/` 配下ならそれぞれの分類、それ以外は `other`）のみを行い、コンポーネントの責務・用途を推定した独自分類は行わない
- **固定と可変の分離** — 整合検証（`validate-page-data.sh`）と HTML 生成（`build-detail-page.sh`）は決定的スクリプトに固定する。抽出（export 名判定・props 判定・被参照カウント）は `extract-component-inventory.sh` が固定ルールで機械的に行う

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| 棚卸し抽出 | `../../../shared/scripts/extract/extract-component-inventory.sh` |
| 整合検証 | `../../../shared/scripts/detail-pages/validate-page-data.sh` |
| HTML生成 | `../../../shared/scripts/detail-pages/build-detail-page.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: コンポーネントファイルの存在確認

- **Step 1** — `target_repo_path` 配下に `.tsx`/`.jsx`/`.vue` ファイルが 1 件以上存在するか `find` で確認する（`node_modules`/`.next`/`dist`/`build` は除外）。存在しなければハード停止し、コンポーネントファイルが無い旨を報告して終了する。完了条件: 1 件以上の実在確認済み、または不在を報告して停止している

### Phase 2: 棚卸し抽出（機械実行）

- **Step 1** — 抽出スクリプトを実行する。完了条件: page-data.json が生成済み

  ```
  ../../../shared/scripts/extract/extract-component-inventory.sh <target_repo_path> <page-data.json>
  ```

- **Step 2** — `summary.totalComponents`・`summary.byCategory`・`summary.topImported` を確認する。完了条件: 抽出結果を確認済み

page-data.json の保存先は `$CLAUDE_JOB_DIR/tmp/component-inventory-page-data.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/detail-pages/validate-page-data.sh <page-data.json> --target-repo <target_repo_path>
  ```

- **Step 2** — FAIL 時は指摘に応じて修正し Step 1 を再実行する。3 回失敗したら Phase 2（抽出手順）へ差し戻す。完了条件: exit 0

### Phase 4: コンポーネント棚卸し.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/コンポーネント棚卸し.html` が生成済み

  ```
  ../../../shared/scripts/detail-pages/build-detail-page.sh <page-data.json> <docs_root> --page component-inventory
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-detail-page.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | コンポーネントファイルの 1 件以上の実在確認済み、または不在を報告して停止している |
| Phase 2 | 棚卸しが抽出済み、抽出結果（総数・分類内訳・被参照上位）を確認済み |
| Phase 3 | `validate-page-data.sh --target-repo` が全項目 PASS |
| Phase 4 | `<docs_root>/コンポーネント棚卸し.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 対象リポジトリの実ファイルのみからコンポーネント棚卸し.html が生成され、分類は自動推定なくディレクトリパス由来の機械的な値のみである |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（コンポーネントファイル不在）\| `ERROR` |
| artifacts | 生成したコンポーネント棚卸し.html のパス（`STOPPED`/`ERROR` 時は空） |
| page_kind | `component-inventory`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（コンポーネントファイル不在）、または次工程への申し送り |

## 重要な注意事項

- 自動分類（taxonomy inference）は行わない。分類はディレクトリパス（`components/`・`pages/`・`layouts/`・`other`）からのみ導出する
- Phase 4 の HTML 手作業組み立てを禁止する。`build-detail-page.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のコンポーネント棚卸し.html のみ

## 予想を裏切る挙動

- export 名の判定順序は `export default function/class` → `export function/const` → `export default <bare識別子>;` の順で最初の一致を採用する。いずれも一致しなければファイル名（拡張子抜き）を使う
- props 型の有無（`hasProps`）はファイル内に文字列 `Props` を含む行があるかのみで判定する。実際に型定義として使われているかは検証しない
- 被参照カウント（`importCount`）は export 名ごとに `import.*<name>` を含むファイル数の単純カウントであり、実際に使用（呼び出し）されているかは検証しない

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-page-data.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/scripts/detail-pages/page-data-schema.md` — page-data.json のスキーマ定義
