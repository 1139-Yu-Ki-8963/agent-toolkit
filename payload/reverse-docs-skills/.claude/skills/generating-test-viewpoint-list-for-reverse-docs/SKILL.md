---
name: generating-test-viewpoint-list-for-reverse-docs
description: |
  per-screen テスト観点表を横断集約し、テスト観点表 HTML を生成する。
  TRIGGER when: orchestrating-reverse-docs-flow の派生一覧状態キーから起動された時、「テスト観点表を生成」と言われた時。
  SKIP: output_dir 自体が存在しない時。
invocation: generating-test-viewpoint-list-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

# テスト観点表一覧生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの派生一覧のうちテスト観点表一覧（`unit_kind=test_viewpoint`）のみを担い、単独起動できる（起動引数を渡せば動く）。

`<output_dir>` 配下の `<screenUnitRoot>/screen-*/詳細設計/単体テスト観点表.md` および `結合テスト観点表.md` を単一の事実源とし、画面横断で集約した manifest JSON を組み立ててテスト観点表.html を生成する。`screenUnitRoot` は output-layout の物理配置キーから解決し、表示用 `kindLabels.screen` はpathに使わない。**本スキルは判定・評価を一切行わない**。各画面の観点表に記載された事実（章見出し・観点）の転記に徹する。

## 使用タイミング

- ポータルにテスト観点表カードを追加したいとき（観点表が 0 件でも空状態のページを生成する）
- 起動引数: `output_dir`（per-screen 観点表の所在かつ出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

出力先は `<output_dir>/一覧/テスト観点表/テスト観点表.html` に固定する。
既存サンプルと `build-portal.sh` の派生一覧探索名を照合して確定した定義である。

## 設計原則

- **転記のみ** — 観点の妥当性・網羅性は判定しない。per-screen 観点表.md に記載された事実（画面・テスト種別・カテゴリ・観点文言）のみを転記する
- **固定と可変の分離** — 抽出・整合検証・HTML 生成は、それぞれ決定的スクリプトに固定する。画面横断の走査と種別判定も、抽出スクリプト側の機械的パターンマッチに閉じる

## エンジンスクリプトの所在

検証・生成スクリプトはスキルフォルダからの相対パスで参照する。

| スクリプト | パス（スキルフォルダ基点） |
|---|---|
| manifest 横断集約 | `../../../shared/scripts/extract/aggregate-test-viewpoints.sh` |
| 整合検証 | `../../../shared/scripts/unit-list/validate-test-viewpoint-manifest.sh` |
| HTML生成 | `../../../shared/scripts/unit-list/build-unit-list.sh` |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` |

## 実行手順

## Phase 1: per-screen 観点表の存在確認

## Step 1-1: per-screen 観点表の存在確認

**使用ツール**: Read / Bash / Write

- **Step 1** — `<output_dir>` を起点とした再帰探索でファイル名を絞り込み、per-screen 観点表を走査する。中間ディレクトリが存在しなくてもエラーにならない形にする。完了条件: 走査が終了コード 0 で終わり、件数が確定している

  ```
  find <output_dir> -type f \( -name '単体テスト観点表.md' -o -name '結合テスト観点表.md' \) | wc -l
  ```

- **Step 2** — 件数が 0 でも停止しない。0 件は「観点表が 1 件も無い」という事実として後続へ引き渡し、Phase 4 で空状態のページを生成する。完了条件: 件数（0 を含む）が確定している

**完了**: per-screen 観点表の件数（0 件を含む）が確定している

## Phase 2: manifest JSON 横断集約（機械実行）

## Step 2-1: manifest JSON 横断集約（機械実行）

**使用ツール**: Read / Bash / Write

- **Step 1** — 集約スクリプトを実行する。完了条件: manifest JSON が生成済み

  ```
  ../../../shared/scripts/extract/aggregate-test-viewpoints.sh <output_dir> <manifest.json>
  ```

- **Step 2** — `summary.totalCount`・`summary.byTestType`・`summary.byScreen` を確認する。0 件の場合もエラーにせず（本スクリプトは fail-safe 設計）、0 件である旨を Phase 4 完了報告の注記に残す。完了条件: 集約結果を確認済み

manifest.json の保存先は `$CLAUDE_JOB_DIR/tmp/test-viewpoint-manifest.json` とする。未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下に置く。

**完了**: manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み

## Phase 3: 整合検証（機械実行）

## Step 3-1: 整合検証（機械実行）

**使用ツール**: Read / Bash

- **Step 1** — 整合検証スクリプトを実行する。完了条件: 全項目 PASS

  ```
  ../../../shared/scripts/unit-list/validate-test-viewpoint-manifest.sh <manifest.json>
  ```

- **Step 2** — FAIL 時は指摘に応じて manifest を修正し Step 1 を再実行する。3 回失敗したら Phase 2（集約スクリプトの入力＝per-screen 観点表.md の記法）の見直しへ差し戻す。完了条件: exit 0

**完了**: `validate-test-viewpoint-manifest.sh` が全項目 PASS

## Phase 4: テスト観点表.html 生成

## Step 4-1: テスト観点表.html 生成

**使用ツール**: Bash / Write

- **Step 1** — HTML 生成スクリプトを実行する。集約結果が 0 件でも実行し、0 件である旨が読み手に伝わる空状態のページを生成する。完了条件: `<output_dir>/一覧/テスト観点表/テスト観点表.html` が生成済み

  ```
  ../../../shared/scripts/unit-list/build-unit-list.sh <manifest.json> <output_dir>/一覧/テスト観点表/テスト観点表.html --unit-kind test_viewpoint
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```
  ../../../shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

**手作業でのプレースホルダ置換は禁止する**。HTML 生成は必ず `build-unit-list.sh` 経由の決定的処理で行う。

**完了**: `<output_dir>/一覧/テスト観点表/テスト観点表.html` が生成され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | per-screen 観点表の件数（0 件を含む）が確定している |
| Phase 2 | manifest JSON が横断集約済み、集約結果（件数・種別内訳・画面内訳）を確認済み |
| Phase 3 | `validate-test-viewpoint-manifest.sh` が全項目 PASS |
| Phase 4 | `<output_dir>/一覧/テスト観点表/テスト観点表.html` が生成され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | per-screen 観点表.md の事実のみからテスト観点表.html が画面横断で生成され、0 件の場合もその旨が可視化されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（生成完了。観点表 0 件でも空状態ページを生成して `DONE`）\| `ERROR` |
| artifacts | 生成したテスト観点表.html のパス（`ERROR` 時は空） |
| unit_kind | `test_viewpoint`（固定値） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 観点表が 0 件だった場合はその旨、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。観点の妥当性・網羅性には一切踏み込まず、per-screen 観点表.md の事実の転記のみを行う
- Phase 4 の HTML 手作業組み立てを禁止する。`build-unit-list.sh` を必ず経由する
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のテスト観点表.html のみ

## 予想を裏切る挙動

- `aggregate-test-viewpoints.sh` は観点表が 1 件も見つからない場合もエラーにせず `units:[]` で正常終了する（fail-safe）。0 件を異常とみなしてリトライしない
- 観点表が 0 件でも本スキルは停止せず、空状態のページを生成して `DONE` を返す。0 件は異常ではなく「まだ観点表が無い」という事実として成果物に残す
- `screenKey` はパス中の `screen-` で始まるディレクトリ名をそのまま使う。画面一覧の `screenKey` 命名と食い違う場合があっても本スキルは正規化しない（画面一覧側の命名を正とし、乖離は集約結果の `byScreen` から目視確認する）
- `build-unit-list.sh` の `--unit-kind` は `screen` の場合のみ `build-screen-list.sh` へ委譲される。`test_viewpoint` は汎用テンプレート経路で生成される

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `validate-test-viewpoint-manifest.sh` の PASS/FAIL 行を追加する。

## 参照資料

- `../../../shared/references/manifest-schema-extensions.md` — manifest JSON のスキーマ拡張定義（存在する場合）

## 設計判断

### validate-test-viewpoint-manifest.sh

**必要性**: テスト観点表一覧の manifest は「転記のみ」設計であり、検出系スキルの validate-manifest.sh が要求する sourceFile 実在チェック・strategy 承認・意味キー品質（screenKey-testType-N 形式の連番検査）・参照整合を満たさない構造を持つ。これらの検査を通そうとすると manifest の意味を歪める値を追加することになり、事実の転記に徹する本スキルの設計原則と矛盾する。

**代替案を採用しなかった理由**:
- validate-manifest.sh に test_viewpoint 分岐を追加: 複数種別が依存する共有スクリプトへの guard 散在で影響範囲が大きく、必須キー集合を変えない方針を維持する
- 検証をスキップ: unitKey 一意性・summary 一致の保証が失われる

**保守責任者**: 人手（ユーザー）。aggregate-test-viewpoints.sh の出力契約を変更する場合は本スクリプトの必須フィールドリストを同時に更新する

**廃棄条件**: validate-manifest.sh が種別ごとの検証プロファイルを内蔵し、test_viewpoint 種別の転記契約に対応した時
