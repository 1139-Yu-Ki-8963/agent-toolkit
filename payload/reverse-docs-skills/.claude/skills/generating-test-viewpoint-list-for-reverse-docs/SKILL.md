---
name: generating-test-viewpoint-list-for-reverse-docs
description: |
  per-screen テスト観点表を横断集約し、テスト観点表 HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の派生一覧状態キーから起動された時、「テスト観点表を生成」と言われた時。
  SKIP: per-screen 観点表が docs_root に 1 件も存在しない時。
invocation: generating-test-viewpoint-list-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# テスト観点表一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの派生一覧のうちテスト観点表一覧（`unit_kind=test_viewpoint`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<docs_root>` 配下の `画面/screen-*/詳細設計/単体テスト観点表.md` および `結合テスト観点表.md` を単一の事実源とし、画面横断で集約した manifest JSON を組み立ててテスト観点表.html を生成する。**本スキルは判定・評価を一切行わない**。各画面の観点表に記載された事実（章見出し・観点）の転記に徹する。

## 使用タイミング

- 1 画面以上で単体/結合テスト観点表.md が確定済みで、ポータルにテスト観点表カードを追加したいとき
- 起動引数: `docs_root`（per-screen 観点表の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<docs_root>/一覧/テスト観点表一覧/テスト観点表.html` に固定する。

## 設計原則

- **転記のみ** — 観点の妥当性・網羅性は判定しない。per-screen 観点表.md に記載された事実（画面・テスト種別・カテゴリ・観点文言）のみを転記する
- **固定と可変の分離** — 抽出（`aggregate-test-viewpoints.sh`）・整合検証（`validate-manifest.sh`）・HTML 生成（`build-unit-list.sh`）はすべて決定的スクリプトに固定する。画面横断の走査・種別判定（ファイル名に「単体」/「結合」を含むか）も抽出スクリプト側の機械的パターンマッチに閉じる

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| manifest 横断集約 | `../../../shared/scripts/extract/aggregate-test-viewpoints.sh` |
| 整合検証 | `../../../shared/scripts/unit-list/validate-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## Phase 手順

### Phase 1: per-screen 観点表の存在確認

- **Step 1** — `<docs_root>/画面/screen-*/詳細設計/単体テスト観点表.md` および `結合テスト観点表.md` を `find`/`ls` で走査する。1 件も存在しなければハード停止し、観点表が未作成である旨を報告して終了する。完了条件: 1 件以上の実在確認済み、または不在を報告して停止している

### Phase 2: manifest JSON 横断集約（機械実行）

- **Step 1** — 集約スクリプトを実行する。完了条件: manifest JSON が生成済み

  ```
  ../../../shared/scripts/extract/aggregate-test-viewpoints.sh <docs_root> <manifest.json>
  ```

- **Step 2** — `summary.totalCount`・`summary.byTestType`・`summary.byScreen` を確認する。0 件の場合もエラーにせず（本スクリプトは fail-safe 設計）、0 件である旨を Phase 4 完了報告の注記に残す。完了条件: 集約結果を確認済み

manifest.json の保存先は `$CLAUDE_JOB_DIR/tmp/test-viewpoint-manifest.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

### Phase 3: 整合検証（機械実行）

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/unit-list/validate-manifest.sh <manifest.json> --unit-kind test_viewpoint
  ```

- **Step 2** — FAIL 時は指摘に応じて manifest を修正し Step 1 を再実行する。3 回失敗したら Phase 2（集約スクリプトの入力＝per-screen 観点表.md の記法）の見直しへ差し戻す。完了条件: exit 0

### Phase 4: テスト観点表.html 生成

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<docs_root>/一覧/テスト観点表一覧/テスト観点表.html` が生成済み

  ```
  ../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <docs_root>/一覧/テスト観点表一覧/テスト観点表.html --unit-kind test_viewpoint
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-unit-list.sh` 経由の決定的処理で行う。

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | per-screen 観点表の 1 件以上の実在確認済み、または不在を報告して停止している |
| Phase 2 | manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み |
| Phase 3 | `validate-manifest.sh --unit-kind test_viewpoint` が全項目 PASS |
| Phase 4 | `<docs_root>/一覧/テスト観点表一覧/テスト観点表.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | per-screen 観点表.md の事実のみからテスト観点表.html が画面横断で生成され、0 件の場合もその旨が可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（観点表 1 件も不在）\| `ERROR` |
| artifacts | 生成したテスト観点表.html のパス（`STOPPED`/`ERROR` 時は空） |
| unit_kind | `test_viewpoint`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（観点表不在）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。観点の妥当性・網羅性には一切踏み込まず、per-screen 観点表.md の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `docs_root` 配下のテスト観点表.html のみ

## 予想を裏切る挙動

- `aggregate-test-viewpoints.sh` は観点表が 1 件も見つからない場合もエラーにせず `units:[]` で正常終了する（fail-safe）。0 件を異常とみなしてリトライしない
- `screenKey` はパス中の `screen-` で始まるディレクトリ名をそのまま使う。画面一覧の `screenKey` 命名と食い違う場合があっても本スキルは正規化しない（画面一覧側の命名を正とし、乖離は集約結果の `byScreen` から目視確認する）
- `build-unit-list.sh` の `--unit-kind` は `screen` の場合のみ `build-screen-list.sh` へ委譲される。`test_viewpoint` は汎用テンプレート経路で生成される

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-manifest.sh --unit-kind test_viewpoint` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/references/manifest-schema-extensions.md` — manifest JSON のスキーマ拡張定義（存在する場合）
