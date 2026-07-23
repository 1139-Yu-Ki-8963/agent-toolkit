---
name: generating-message-list-for-reverse-docs
description: |
  メッセージ定義書.md を manifest JSON に変換し、メッセージ一覧 HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の派生一覧状態キーから起動された時、「メッセージ一覧を生成」と言われた時。
  SKIP: メッセージ定義書.md が docs_root に存在しない時。
invocation: generating-message-list-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# メッセージ一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの派生一覧のうちメッセージ一覧（`unit_kind=message`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<docs_root>/プロジェクト共通/メッセージ定義書.md` の「キー | 文言(実測) | 種別 | 抽出元 | 使用画面」5列パイプテーブルを単一の事実源とし、manifest JSON へ変換してメッセージ一覧.html を組み立てる。**本スキルは判定・評価を一切行わない**。メッセージ定義書.md に記載された事実の転記に徹し、テーブル解析は決定的パターンマッチのみで行う。

## 使用タイミング

- `<docs_root>/プロジェクト共通/メッセージ定義書.md` が確定済みで、ポータルにメッセージ一覧カードを追加したいとき
- 起動引数: `docs_root`（メッセージ定義書.md の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/一覧/メッセージ一覧/メッセージ一覧.html` に固定する。

## 設計原則

- **転記のみ** — メッセージ文言の妥当性・粒度は判定しない。メッセージ定義書.md に記載された事実（キー・文言・種別・抽出元・使用画面）のみを転記する
- **固定と可変の分離** — 抽出（`convert-message-doc-to-manifest.sh`）・整合検証（`validate-manifest.sh`）・HTML 生成（`build-unit-list.sh`）はすべて決定的スクリプトに固定する。他種別一覧のようなカスタム抽出判断は不要（メッセージ定義書.md の形式が既に固定契約のため）

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| manifest 変換 | `../../../shared/scripts/extract/convert-message-doc-to-manifest.sh` |
| 整合検証 | `../../../shared/scripts/unit-list/validate-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: メッセージ定義書.md の存在確認

- **Step 1** — `<docs_root>/プロジェクト共通/メッセージ定義書.md` の実在を `test -f` で確認する。存在しなければハード停止し、メッセージ定義書.md が未作成である旨を報告して終了する。完了条件: 実在確認済み、または不在を報告して停止している

### Phase 2: manifest JSON 生成（機械実行）

- **Step 1** — 変換スクリプトを実行する。完了条件: manifest JSON が生成済み

  ```
  ../../../shared/scripts/extract/convert-message-doc-to-manifest.sh <メッセージ定義書.md> <manifest.json>
  ```

- **Step 2** — `summary.totalCount` を確認する。0 件の場合もエラーにせず（本スクリプトは fail-safe 設計）、0 件である旨を Phase 4 完了報告の注記に残す。完了条件: totalCount を確認済み

manifest.json の保存先は `$CLAUDE_JOB_DIR/tmp/message-manifest.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/unit-list/validate-manifest.sh <manifest.json> --unit-kind message
  ```

- **Step 2** — FAIL 時は指摘に応じて manifest を修正し Step 1 を再実行する。3 回失敗したら Phase 2（変換スクリプトの入力＝メッセージ定義書.md の記法）の見直しへ差し戻す。完了条件: exit 0

### Phase 4: メッセージ一覧.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/一覧/メッセージ一覧/メッセージ一覧.html` が生成済み

  ```
  ../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <docs_root>/一覧/メッセージ一覧/メッセージ一覧.html --unit-kind message
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-unit-list.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | メッセージ定義書.md の実在確認済み、または不在を報告して停止している |
| Phase 2 | manifest JSON が生成済み、totalCount を確認済み |
| Phase 3 | `validate-manifest.sh --unit-kind message` が全項目 PASS |
| Phase 4 | `<docs_root>/一覧/メッセージ一覧/メッセージ一覧.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | メッセージ定義書.md の事実のみからメッセージ一覧.html が生成され、0 件の場合もその旨が可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（メッセージ定義書.md 不在）\| `ERROR` |
| artifacts | 生成したメッセージ一覧.html のパス（`STOPPED`/`ERROR` 時は空） |
| unit_kind | `message`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（メッセージ定義書.md 不在）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。メッセージ文言の妥当性・粒度には一切踏み込まず、メッセージ定義書.md の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のメッセージ一覧.html のみ

## 予想を裏切る挙動

- `convert-message-doc-to-manifest.sh` はテーブルが 1 件も見つからない場合もエラーにせず `units:[]` で正常終了する（fail-safe）。0 件を異常とみなしてリトライしない
- `build-unit-list.sh` の `--unit-kind` は `screen` の場合のみ `build-screen-list.sh` へ委譲される。`message` は汎用テンプレート経路で生成される

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-manifest.sh --unit-kind message` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/references/manifest-schema-extensions.md` — manifest JSON のスキーマ拡張定義（存在する場合）
