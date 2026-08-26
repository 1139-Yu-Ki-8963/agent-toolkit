---
name: generating-test-case-list-for-reverse-docs
日本語名: テストケース一覧の生成
description: "各設計単位のテスト設計書を横断して集め、テストケース一覧を作る。"
invocation: generating-test-case-list-for-reverse-docs
type: transform
allowed-tools: [Read, Bash, Write, Edit, Grep, Glob]
---

## いつ使うか

orchestrating-ai-development-setup の派生一覧状態キーから起動された時、「テストケース一覧を生成」と言われた時に使う。

## いつ使わないか

設計単位ごとのテスト設計書が output_dir に 1 件も存在しない時は使わない。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# テストケース一覧生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはポータルの派生一覧のうちテストケース一覧（`unit_kind=test_case`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<output_dir>` 配下の各設計単位の2テスト設計書と、画面固有の操作シナリオ仕様書を事実源とし、横断集約したテストケース一覧HTMLを生成する。新配置がない既存画面に限り、旧テスト仕様書を後方互換として読む。**本スキルは判定・評価を一切行わない**。各文書に記載された事実の転記のみに徹する。

## 使用タイミング

- 1単位以上で2種類のテスト設計書の一方が確定済みで、ポータルにテストケース一覧カードを追加したいとき。画面固有の操作シナリオ仕様書は前提条件に数えず、画面が存在する場合だけ追加入力にする
- 起動引数: `output_dir`（設計単位ごとのテスト設計書の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<output_dir>/<unitListHtml>` に固定する。`unitListHtml` は output-layout の物理配置キーで、{label} は「テストケース」である。
`build-portal.sh` の派生一覧探索（`<unitsRoot>/<種別名>/<種別名>.html` パターン）と照合して確定した定義である。

## 設計原則

- **転記のみ** — テストケースの妥当性・網羅性は判定しない。設計単位ごとのテスト設計書と画面固有シナリオに記載された事実のみを転記する
- **固定と可変の分離** — 抽出・整合検証・HTML 生成は、それぞれ決定的スクリプトに固定する。画面横断の走査とテスト種別判定も、抽出スクリプト側の機械的パターンマッチに閉じる
- **既存の派生一覧エンジンに乗る** — テスト観点表一覧（`generating-test-viewpoint-list-for-reverse-docs`）と同じ流儀を使う。汎用エンジン `build-unit-list.sh` の `--unit-kind test_case` 経路に乗せる。専用のタブ切り替え・複数manifest構成は持たない。単一テーブルで集約元の種別（画面・API・テーブル・バッチ・帳票・外部連携・機能）とテスト種別（単体・結合・操作シナリオ）を列で区別する

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| manifest 横断集約 | `../../../generation-engine/scripts/extract/aggregate-test-cases.sh` |
| 整合検証 | `../../../generation-engine/scripts/unit-list/validate-test-case-manifest.sh` |
| HTML生成 | `../../../generation-engine/scripts/unit-list/build-unit-list.sh` |
| ポータル再生成（任意） | `../../../generation-engine/scripts/build-portal.sh` |

## 実行手順

## Phase 1: テスト設計書の存在確認

## Step 1-1: テスト設計書の存在確認

**使用ツール**: Read / Bash / Glob / Grep

- **Step 1** — output-layout の各 `*UnitRoot` を解決し、設計単位直下の `テスト設計/` にある2設計書を走査する。画面は新配置を優先し、役割ごとに新文書がない場合だけ旧 `テスト項目書/` の対応文書をfallbackとして数える。2設計書のいずれかが1件以上存在するときだけ前提成立とし、その後、画面が存在する場合だけ操作シナリオ仕様書を追加入力として走査する。全種別で2設計書が0件ならハード停止する。完了条件: 2設計書の1件以上の実在確認済み、または不在を報告して停止している

**完了**: 新配置優先・旧配置fallbackで有効なテスト設計書の1件以上の実在確認済み、または不在を報告して停止している

## Phase 2: manifest JSON 横断集約（機械実行）

## Step 2-1: manifest JSON 横断集約（機械実行）

**使用ツール**: Read / Bash / Write

- **Step 1** — 集約スクリプトを実行する。完了条件: manifest JSON が生成済み

  ```
  ../../../generation-engine/scripts/extract/aggregate-test-cases.sh <output_dir> <manifest.json>
  ```

- **Step 2** — `summary.totalCount`・`summary.byTestType`・`summary.byScreen` と各行の `sourceKind` を確認する。0 件の場合もエラーにせず（本スクリプトは fail-safe 設計）、0 件である旨を Phase 4 完了報告の注記に残す。完了条件: 集約結果を確認済み

manifest.json の保存先は `$CLAUDE_JOB_DIR/tmp/test-case-manifest.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

**完了**: manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み。種別内訳（`summary.byTestType`）は単体/結合/操作シナリオの3種を検出0件も含めて記録する

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Read / Bash / Edit

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../generation-engine/scripts/unit-list/validate-test-case-manifest.sh <manifest.json>
  ```

- **Step 2** — FAIL 時は指摘に応じて manifest を修正し Step 1 を再実行する。3 回失敗したら Phase 2（集約スクリプトの入力＝各設計単位のテスト設計書、または画面の旧仕様書の記法）の見直しへ差し戻す。完了条件: exit 0

**完了**: `validate-test-case-manifest.sh` が全項目 PASS

## Phase 4: テストケース一覧.html 生成

## Step 4-1: テストケース一覧.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。完了条件: `<output_dir>/<unitListHtml>` が生成済み

  ```
  ../../../generation-engine/scripts/unit-list/build-unit-list.sh <manifest.json> <output_dir>/<unitListHtml> --unit-kind test_case --portal-dir <output_dir>
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-unit-list.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/<unitListHtml>` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 新配置優先・旧配置fallbackで有効なテスト設計書の1件以上の実在確認済み、または不在を報告して停止している |
| Phase 2 | manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み。種別内訳は検出0件も含めて記録済み |
| Phase 3 | `validate-test-case-manifest.sh` が全項目 PASS |
| Phase 4 | `<output_dir>/<unitListHtml>` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | 設計単位ごとの2テスト設計書と画面固有シナリオ（既存生成物は旧仕様書fallback）の事実からテストケース一覧.html が横断生成されている |

## 返却ブロック

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了）\| `STOPPED`（テスト仕様書 1 件も不在）\| `ERROR` |
| artifacts | 生成したテストケース一覧.html のパス（`STOPPED`/`ERROR` 時は空） |
| unit_kind | `test_case`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由（テスト仕様書不在）、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。テストケースの妥当性・網羅性には一切踏み込まず、テスト設計書（または旧配置fallback）の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のテストケース一覧.html のみ

## 予想を裏切る挙動

- 出力は単一テーブルであり、単体・結合・操作シナリオを切り替えるタブは持たない。集約元は「種別」列、テスト種別は「テスト種別」列と区分バッジで区別する
- 各種別の単体テスト設計書・テスト設計書は「キー」列を先頭に持つケース表を集約元とする。画面の操作シナリオ仕様書は別契約で集約し、複数単位をまたぐプロジェクト全体の結合テスト仕様書は単位別一覧の集約元に含めない
- 操作シナリオ仕様書.md は「シナリオ一覧表」（シナリオ名・対応往復検証観点キー・前提条件）と、`### <シナリオ名>` 節の「**期待結果**」直後の段落を、シナリオ名で突合して1件のケースに合成する。操作手順のサブテーブル（順序・アクション・対象セレクタ・入力値）は転記対象に含めない（`steps` は空文字列になる）
- `aggregate-test-cases.sh` は `aggregate-test-viewpoints.sh` と同じ fail-safe 方針とする。テスト仕様書が 0 件でもエラーにせず空集合で正常終了させる
- 観点表側の観点網羅（カバー率）は本スキルの出力に含まない。観点の網羅状況を確認したい場合は `generating-test-viewpoint-list-for-reverse-docs` が生成するテスト観点表一覧を別途参照する
- 種別内訳は検出0件の種別もキーを残して0で出力する。仕様書が不在で走査対象にならなかった場合と、仕様書は実在するが確定行が0件だった場合は `scannedByTestType` で区別する

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-test-case-manifest.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../delivery-payload/references/manifest-schema-extensions.md` — manifest JSON のスキーマ拡張定義（存在する場合）

## 設計判断

### aggregate-test-cases.sh

**必要性**: テストケース一覧の集約元は、全設計種別の各単位にある2テスト設計書と、画面が存在する場合の操作シナリオ仕様書である。画面の旧配置では単体・結合の列構成が異なり、操作シナリオは上位のシナリオ一覧表と `###` 節ごとの期待結果段落を合成する。`aggregate-test-viewpoints.sh` の列パース仕様（観点抽出専用）とは事実源の節が異なるため、専用スクリプトとして分離する。全種別の走査・ヘッダ名による列マッピング・画面固有シナリオの表とセクションの突合は、繰り返し実行される決定的処理である。手作業のプレースホルダ置換では再現性を保てない。

**代替案を採用しなかった理由**:
- `aggregate-test-viewpoints.sh` に列判定の分岐を追加: 観点表・テスト仕様書という異なる文書種別の抽出仕様が1スクリプトへ混在し保守性が下がる
- 専用のタブ構成HTML生成スクリプトを別途新設（当初案）: `build-unit-list.sh` の `--unit-kind test_viewpoint` と同じ経路に乗せれば単一テーブルで足りる。専用スクリプト3本のうちHTML生成は既存の汎用エンジンで代替できるため新設しない
- Bash ツール直叩き: 画面横断の走査・ヘッダ名の解決・シナリオ名による表とセクションの突合を都度手作業で行うと再現性がない。`Phase 2` を実行するたびに結果が変わりうる

**保守責任者**: 人手（ユーザー）。各種別のテスト設計書、または画面の旧テスト仕様書のテーブル列構成を変更する場合は、本スクリプトの `want_names` 定義を同時に更新する

**廃棄条件**: テストケース仕様書のフォーマット自体を廃止した時、または汎用エンジンが複数文書源の合成抽出を標準機能として提供するようになった時

### validate-test-case-manifest.sh

**必要性**: テストケース一覧の manifest は「転記のみ」設計である。検出系スキルの `validate-manifest.sh` が要求する sourceFile 実在チェック・strategy 承認・内容要約キー品質検査・参照整合を満たさない構造を持つ。`validate-test-viewpoint-manifest.sh` と同様の考え方を使う。専用スキーマ（`unitKey`・`screenKey`・`testType`・`caseKey`・`viewpointKey` 等）を検証する。

**代替案を採用しなかった理由**:
- `validate-manifest.sh` に test_case 分岐を追加: 複数種別が依存する共有スクリプトへの guard 散在で影響範囲が大きく、必須キー集合を変えない方針を維持する
- `validate-test-viewpoint-manifest.sh` を流用: 必須キー集合が異なる（`category`/`viewpoint` 対 `testType`/`caseKey`/`steps` 等）。流用すると欠落検知ができない

**保守責任者**: 人手（ユーザー）。`aggregate-test-cases.sh` の出力契約を変更する場合は本スクリプトの必須フィールドリスト（`REQUIRED_UNIT_KEYS`）を同時に更新する

**廃棄条件**: `validate-manifest.sh` が種別ごとの検証プロファイルを内蔵し、test_case 種別の転記契約に対応した時
