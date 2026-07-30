---
name: generating-test-case-list-for-reverse-docs
description: |
  画面ごとのテスト仕様書（単体・結合・操作シナリオ）を横断集約し、テストケース一覧HTMLを生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の派生一覧状態キーから起動された時、「テストケース一覧を生成」と言われた時。
  SKIP: per-screen テスト仕様書が output_dir に 1 件も存在しない時。
invocation: generating-test-case-list-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

# テストケース一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの派生一覧のうちテストケース一覧（`unit_kind=test_case`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<output_dir>` 配下の per-screen テスト仕様書を事実源とし、画面横断で集約したテストケース一覧HTMLを生成する。**本スキルは判定・評価を一切行わない**。各画面のテスト仕様書に記載された事実の転記のみに徹する。

## 使用タイミング

- 1 画面以上で単体/結合/操作シナリオのテスト仕様書.md が確定済みで、ポータルにテストケース一覧カードを追加したいとき
- 起動引数: `output_dir`（per-screen テスト仕様書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<output_dir>/一覧/テストケース一覧/テストケース一覧.html` に固定する。
`build-portal.sh` の派生一覧探索（`一覧/<種別名>/<種別名>.html` パターン）と照合して確定した定義である。

## 設計原則

- **転記のみ** — テストケースの妥当性・網羅性は判定しない。per-screen テスト仕様書.md に記載された事実（画面・テスト種別・キー・入力値・期待結果）のみを転記する
- **固定と可変の分離** — 抽出・整合検証・HTML 生成は、それぞれ決定的スクリプトに固定する。画面横断の走査とテスト種別判定も、抽出スクリプト側の機械的パターンマッチに閉じる
- **既存の派生一覧エンジンに乗る** — テスト観点表一覧（`generating-test-viewpoint-list-for-reverse-docs`）と同じ流儀を使う。汎用エンジン `build-unit-list.sh` の `--unit-kind test_case` 経路に乗せる。専用のタブ切り替え・複数manifest構成は持たない。単一テーブルでテスト種別（単体・結合・操作シナリオ）を列で区別する

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| manifest 横断集約 | `../../../shared/scripts/extract/aggregate-test-cases.sh` |
| 整合検証 | `../../../shared/scripts/unit-list/validate-test-case-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## 実行手順

## Phase 1: per-screen テスト仕様書の存在確認

## Step 1-1: per-screen テスト仕様書の存在確認

**使用ツール**: Read / Bash / Glob / Grep

- **Step 1** — `<output_dir>/画面/screen-*/テスト項目書/単体テスト仕様書.md`・`結合テスト仕様書.md`・`操作シナリオ仕様書.md` を `find`/`ls` で走査する。3 種とも 0 件ならハード停止し、テスト仕様書が未作成である旨を報告して終了する。完了条件: 1 件以上の実在確認済み、または不在を報告して停止している

**完了**: per-screen テスト仕様書の 1 件以上の実在確認済み、または不在を報告して停止している

## Phase 2: manifest JSON 横断集約（機械実行）

## Step 2-1: manifest JSON 横断集約（機械実行）

**使用ツール**: Read / Bash / Write

- **Step 1** — 集約スクリプトを実行する。完了条件: manifest JSON が生成済み

  ```
  ../../../shared/scripts/extract/aggregate-test-cases.sh <output_dir> <manifest.json>
  ```

- **Step 2** — `summary.totalCount`・`summary.byTestType`・`summary.byScreen` を確認する。0 件の場合もエラーにせず（本スクリプトは fail-safe 設計）、0 件である旨を Phase 4 完了報告の注記に残す。完了条件: 集約結果を確認済み

manifest.json の保存先は `$CLAUDE_JOB_DIR/tmp/test-case-manifest.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

**完了**: manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Read / Bash / Edit

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/unit-list/validate-test-case-manifest.sh <manifest.json>
  ```

- **Step 2** — FAIL 時は指摘に応じて manifest を修正し Step 1 を再実行する。3 回失敗したら Phase 2（集約スクリプトの入力＝per-screen テスト仕様書.md の記法）の見直しへ差し戻す。完了条件: exit 0

**完了**: `validate-test-case-manifest.sh` が全項目 PASS

## Phase 4: テストケース一覧.html 生成

## Step 4-1: テストケース一覧.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/一覧/テストケース一覧/テストケース一覧.html` が生成済み

  ```
  ../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <output_dir>/一覧/テストケース一覧/テストケース一覧.html --unit-kind test_case
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-unit-list.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/一覧/テストケース一覧/テストケース一覧.html` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | per-screen テスト仕様書の 1 件以上の実在確認済み、または不在を報告して停止している |
| Phase 2 | manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み |
| Phase 3 | `validate-test-case-manifest.sh` が全項目 PASS |
| Phase 4 | `<output_dir>/一覧/テストケース一覧/テストケース一覧.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | per-screen テスト仕様書.md の事実のみからテストケース一覧.html が画面横断で生成され、0 件の場合もその旨が可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（テスト仕様書 1 件も不在）\| `ERROR` |
| artifacts | 生成したテストケース一覧.html のパス（`STOPPED`/`ERROR` 時は空） |
| unit_kind | `test_case`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（テスト仕様書不在）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。テストケースの妥当性・網羅性には一切踏み込まず、per-screen テスト仕様書.md の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のテストケース一覧.html のみ

## 予想を裏切る挙動

- 出力は単一テーブルであり、単体・結合・操作シナリオを切り替えるタブは持たない。テスト種別は列（テスト種別列・区分バッジ）で区別する
- 単体テスト仕様書.md・結合テスト仕様書.md は「キー」列を先頭に持つ表を集約元とする。結合は追加で「操作手順」列を `steps` として転記するが、単体は `steps` を空文字列にする
- 操作シナリオ仕様書.md は「シナリオ一覧表」（シナリオ名・対応往復検証観点キー・前提条件）と、`### <シナリオ名>` 節の「**期待結果**」直後の段落を、シナリオ名で突合して1件のケースに合成する。操作手順のサブテーブル（順序・アクション・対象セレクタ・入力値）は転記対象に含めない（`steps` は空文字列になる）
- `aggregate-test-cases.sh` は `aggregate-test-viewpoints.sh` と同じ fail-safe 方針とする。テスト仕様書が 0 件でもエラーにせず空集合で正常終了させる
- 観点表側の観点網羅（カバー率）は本スキルの出力に含まない。観点の網羅状況を確認したい場合は `generating-test-viewpoint-list-for-reverse-docs` が生成するテスト観点表一覧を別途参照する

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-test-case-manifest.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/references/manifest-schema-extensions.md` — manifest JSON のスキーマ拡張定義（存在する場合）

## 設計判断

### aggregate-test-cases.sh

**必要性**: テストケース一覧の集約元は per-screen の単体・結合・操作シナリオ仕様書.md である。表の列構成はそれぞれ異なる（単体は5列、結合は6列）。操作シナリオは上位のシナリオ一覧表と `###` 節ごとの期待結果段落を合成する。`aggregate-test-viewpoints.sh` の列パース仕様（観点表.md 専用）とは事実源の文書種別が異なるため、専用スクリプトとして分離する。画面横断の走査・ヘッダ名によるテスト種別ごとの列マッピング・操作シナリオの表とセクションの突合は、繰り返し実行される決定的処理である。手作業のプレースホルダ置換では再現性を保てない。

**代替案を採用しなかった理由**:
- `aggregate-test-viewpoints.sh` に列判定の分岐を追加: 観点表・テスト仕様書という異なる文書種別の抽出仕様が1スクリプトへ混在し保守性が下がる
- 専用のタブ構成HTML生成スクリプトを別途新設（当初案）: `build-unit-list.sh` の `--unit-kind test_viewpoint` と同じ経路に乗せれば単一テーブルで足りる。専用スクリプト3本のうちHTML生成は既存の汎用エンジンで代替できるため新設しない
- Bash ツール直叩き: 画面横断の走査・ヘッダ名の解決・シナリオ名による表とセクションの突合を都度手作業で行うと再現性がない。`Phase 2` を実行するたびに結果が変わりうる

**保守責任者**: 人手（ユーザー）。per-screen テスト仕様書.md のテーブル列構成を変更する場合は、本スクリプトの `want_names` 定義を同時に更新する

**廃棄条件**: テストケース仕様書のフォーマット自体を廃止した時、または汎用エンジンが複数文書源の合成抽出を標準機能として提供するようになった時

### validate-test-case-manifest.sh

**必要性**: テストケース一覧の manifest は「転記のみ」設計である。検出系スキルの `validate-manifest.sh` が要求する sourceFile 実在チェック・strategy 承認・内容要約キー品質検査・参照整合を満たさない構造を持つ。`validate-test-viewpoint-manifest.sh` と同様の考え方を使う。専用スキーマ（`unitKey`・`screenKey`・`testType`・`caseKey`・`viewpointKey` 等）を検証する。

**代替案を採用しなかった理由**:
- `validate-manifest.sh` に test_case 分岐を追加: 複数種別が依存する共有スクリプトへの guard 散在で影響範囲が大きく、必須キー集合を変えない方針を維持する
- `validate-test-viewpoint-manifest.sh` を流用: 必須キー集合が異なる（`category`/`viewpoint` 対 `testType`/`caseKey`/`steps` 等）。流用すると欠落検知ができない

**保守責任者**: 人手（ユーザー）。`aggregate-test-cases.sh` の出力契約を変更する場合は本スクリプトの必須フィールドリスト（`REQUIRED_UNIT_KEYS`）を同時に更新する

**廃棄条件**: `validate-manifest.sh` が種別ごとの検証プロファイルを内蔵し、test_case 種別の転記契約に対応した時
