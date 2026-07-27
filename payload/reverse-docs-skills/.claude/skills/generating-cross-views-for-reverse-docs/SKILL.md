---
name: generating-cross-views-for-reverse-docs
description: "権限×画面・権限×機能・CRUD図・追跡可能性のマトリクス・対応表4ページとAI設定資産ページをmanifest群から機械生成する。 TRIGGER when: マトリクス・対応表生成、権限マトリクス作成、CRUD図作成、追跡可能性ページ作成、AI設定資産ページ作成。 SKIP: 画面/API/テーブル/機能一覧自体の作成（→各対応する一覧生成スキル）、往復検証/同期/実装。"
invocation: generating-cross-views-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion, TaskCreate, TaskUpdate]
---

# マトリクス・対応表生成スキル

工程全体は orchestrating-reverse-docs-flow が案内する。本スキルはポータルの「マトリクス・対応表」カテゴリ4ページ（権限画面マトリクス・権限機能マトリクス・CRUD図・追跡可能性）と「AI設定資産」カテゴリ1ページの、あわせて5ページを担い、単独起動できる（起動引数を渡せば動く）。

既に確立済みの種別別一覧（画面一覧・API一覧・テーブル一覧・機能一覧）の manifest を突き合わせ、権限・CRUD・画面-API-テーブルの連鎖関係を導出する。**本スキルはソースコードを新規に読み解いて画面・API・テーブルを検出する一覧生成の役割は持たない**。既存 manifest の再構成と、対象リポジトリの `.claude/` 配下（AI設定資産のみ）の走査に限定する。

## 使用タイミング

- 画面一覧.html・API一覧.html が確定済みで、ポータルにマトリクス・対応表・AI設定資産のカードを追加したいとき
- 起動引数: `target_repo_path`（対象リポジトリの絶対パス）・`output_dir`（一覧HTML所在 / マトリクス・対応表・AI設定資産の出力先）・`portal_output_dir`（任意）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

## 出力先（固定・`build-portal.sh` の `get_cross_label`/`CROSS_ORDER` と同値）

| page-type | 出力パス |
|---|---|
| permission-screen | `<output_dir>/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html` |
| permission-function | `<output_dir>/マトリクス・対応表/権限機能マトリクス/権限機能マトリクス.html` |
| crud | `<output_dir>/マトリクス・対応表/CRUD図/CRUD図.html` |
| traceability | `<output_dir>/マトリクス・対応表/追跡可能性/追跡可能性.html` |
| ai-assets | `<output_dir>/AI設定資産/AI設定資産.html` |

`build-portal.sh` はこの5パスの実在有無だけでカードを出す（不在時はセクション自体が非表示になる fail-safe）。パスをこの表からずらすとカードが無言で出ない事故になるため厳守する。

## エンジンスクリプトの所在

抽出・導出・生成はいずれも決定的スクリプトに固定する。Claude 自身が手作業でHTML・JSONを組み立てることはしない。

| スクリプト | パス（スキルフォルダ基点） | 役割 |
|---|---|---|
| 画面メタ拡張抽出 | `../../../shared/scripts/extract/extract-screen-metadata.sh` | permissions・relatedApis 等を screen-manifest に追加 |
| APIメタ拡張抽出 | `../../../shared/scripts/extract/extract-api-metadata.sh` | method・targetTables 等を api-manifest に追加 |
| 交差データ導出 | `../../../shared/scripts/extract/build-matrix-data.sh` | 拡張済みmanifest群から permission-matrix.json・crud-matrix.json・traceability.json を導出 |
| AI設定資産抽出 | `../../../shared/scripts/extract/extract-ai-assets.sh` | `.claude/` 配下から rules/skills/subagents/hooks を抽出 |
| ページHTML生成 | `../../../shared/scripts/matrix/build-matrix-pages.sh` | page-type ごとにテンプレートへ data.json を埋め込み、整合検証（必須トップレベルキー）も兼ねる |
| ポータル再生成（任意） | `../../../shared/scripts/build-portal.sh` | 生成済みページをカードへ反映 |

データスキーマの正本は `shared/references/manifest-schema-extensions.md`（種別ごとの追加フィールド定義・マトリクス・対応表用新規データファイル定義・AI設定資産ページのデータ源）。`build-matrix-pages.sh` の必須トップレベルキー検査もこの定義と一致させてある（二重管理・ドリフト禁止）。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。実行環境に TaskCreate/TaskUpdate が存在しない場合は、`output_dir` 内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## Phase 手順

### Phase 1: 前提確認

- **Step 1** — `<output_dir>/一覧/画面一覧/画面一覧.html` と `<output_dir>/一覧/API一覧/API一覧.html` の実在を確認する。いずれか不在ならハード停止する。この場合 `generating-screen-list-for-reverse-docs` / `generating-api-list-for-reverse-docs` の先行実行を案内して終了する。完了条件: 両ファイルの実在確認済み、または不在を報告して停止している
- **Step 2** — `<output_dir>/一覧/テーブル一覧/テーブル一覧.html` と `<output_dir>/一覧/機能一覧/機能一覧.html` の実在を確認する。いずれも任意データ源であり、不在でも Phase 2 以降を続行する（`build-matrix-data.sh` は table-manifest・feature-manifest を省略しても動作する fail-safe 設計）。完了条件: 両ファイルの実在有無が確定済み

### Phase 2: 拡張マニフェスト抽出 + 交差データ導出

- **Step 1** — 各一覧HTMLから埋め込み manifest を抽出する。抽出先は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下）。

  ```bash
  sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' <画面一覧.html> | sed '1d;$d' > screen-manifest.json
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <API一覧.html> | sed '1d;$d' > api-manifest.json
  # テーブル一覧・機能一覧が実在する場合のみ
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <テーブル一覧.html> | sed '1d;$d' > table-manifest.json
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <機能一覧.html> | sed '1d;$d' > feature-manifest.json
  ```

  画面一覧のみ埋め込みID が `screen-manifest`（`build-screen-list.sh` 固有仕様）。それ以外（API・テーブル・機能）は共通の `unit-manifest`。完了条件: 実在するHTMLすべてから manifest JSON を抽出済み

- **Step 2** — 画面メタ拡張抽出を実行する。完了条件: 拡張画面マニフェストが生成済み

  ```bash
  ../../../shared/scripts/extract/extract-screen-metadata.sh screen-manifest.json <target_repo_path> screen-manifest.ext.json --api-manifest api-manifest.json
  ```

- **Step 3** — APIメタ拡張抽出を実行する。完了条件: 拡張APIマニフェストが生成済み

  ```bash
  ../../../shared/scripts/extract/extract-api-metadata.sh api-manifest.json <target_repo_path> api-manifest.ext.json --screen-manifest screen-manifest.ext.json --table-manifest table-manifest.json
  ```

  `--table-manifest` はテーブル一覧が実在する場合のみ付与する。

- **Step 4** — 交差データ導出を実行する。完了条件: `permission-matrix.json`・`crud-matrix.json`・`traceability.json` の3ファイルが生成済み

  ```bash
  ../../../shared/scripts/extract/build-matrix-data.sh <output-dir> \
    --screen-manifest screen-manifest.ext.json \
    --api-manifest api-manifest.ext.json \
    [--table-manifest table-manifest.json] \
    [--feature-manifest feature-manifest.json]
  ```

  table-manifest・feature-manifest はPhase 1 Step 2 で不在確認したものは省略する（省略時の fail-safe 挙動は `build-matrix-data.sh` ヘッダコメント参照）。

### Phase 3: AI設定資産データ抽出

- **Step 1** — 対象リポジトリの `.claude/` 配下を走査する。完了条件: `ai-assets-data.json` が生成済み

  ```bash
  ../../../shared/scripts/extract/extract-ai-assets.sh <target_repo_path> ai-assets-data.json
  ```

### Phase 4: ページHTML生成

- **Step 1** — 4種のデータ（Phase 2 の3ファイル + Phase 3 の1ファイル）を、`build-matrix-pages.sh` で対応するテンプレートへ埋め込む。**手作業でのプレースホルダ置換は禁止する**（HTML生成は必ずスクリプト経由の決定的処理で行う）。完了条件: 生成可能な全ページがそれぞれの固定パス（本SKILL冒頭の出力先表）に出力済み

  ```bash
  ../../../shared/scripts/matrix/build-matrix-pages.sh permission-screen permission-matrix.json "<output_dir>/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
  ../../../shared/scripts/matrix/build-matrix-pages.sh crud crud-matrix.json "<output_dir>/マトリクス・対応表/CRUD図/CRUD図.html"
  ../../../shared/scripts/matrix/build-matrix-pages.sh traceability traceability.json "<output_dir>/マトリクス・対応表/追跡可能性/追跡可能性.html"
  ../../../shared/scripts/matrix/build-matrix-pages.sh ai-assets ai-assets-data.json "<output_dir>/AI設定資産/AI設定資産.html"
  ```

  `permission-function`（権限機能マトリクス）は「予想を裏切る挙動」節に記載する既知の制約により、Phase 2 の `permission-matrix.json` をそのまま入力に使えない。生成できる場合のみ実行し、できない場合はスキップして完了報告に明記する（下記参照）。

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```bash
  ../../../shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
  ```

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | 画面一覧.html・API一覧.html の実在確認済み（不在時は停止）。テーブル一覧.html・機能一覧.html の実在有無が確定済み |
| Phase 2 | 拡張画面/APIマニフェストが生成され、`permission-matrix.json`・`crud-matrix.json`・`traceability.json` が生成済み |
| Phase 3 | `ai-assets-data.json` が生成済み |
| Phase 4 | 生成可能な全ページ（permission-screen / crud / traceability / ai-assets は必ず、permission-function はデータ形状が揃った場合のみ）が固定パスに出力され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | マトリクス・対応表・AI設定資産のうち生成可能なページがすべて生成され、ポータルのカードへ反映されている。permission-function を未生成のまま終える場合はその理由が完了報告に明記されている |

## 返却ブロック

本スキルは orchestrating-reverse-docs-flow の契約に準拠する。完了時に以下を返す。

| キー | 値 |
|---|---|
| status | `DONE`（1ページ以上生成完了）\| `STOPPED`（画面一覧/API一覧不在）\| `ERROR` |
| artifacts | 生成した各ページのパス（`STOPPED`/`ERROR` 時は空） |
| generated_pages | 生成した page-type の配列（例: `["permission-screen","crud","traceability","ai-assets"]`） |
| skipped_pages | 未生成の page-type とその理由（例: `[{"page":"permission-function","reason":"..."}]`） |
| portal_rebuilt | `true`（build-portal.sh 再実行済み）\| `false`（`portal_output_dir` 未指定のため省略） |
| hint | 停止理由、または次工程への申し送り |

## 重要な注意事項

- 判定・評価はしない。権限設計・CRUD設計の良否には踏み込まず、manifest から機械導出できた関係のみを転記する
- 検出できない関係を AskUserQuestion で聞き出さない。データが揃わないページは生成せず理由を報告する（捏造しない）
- 対象リポジトリへの書き込み・変更は一切行わない。出力は `output_dir` 配下のページのみ

## 予想を裏切る挙動

- 出力先は種別ごとに `マトリクス・対応表/<ラベル>/<ラベル>.html`（AI設定資産のみ `AI設定資産/AI設定資産.html` で専用フォルダ名がラベルと一致しない）。`build-portal.sh` の `get_cross_label`/`CROSS_ORDER` 固定出力名仕様に従う
- **permission-function（権限機能マトリクス）は既知のデータ形状ギャップを持つ**。`build-matrix-data.sh` が導出する `permission-matrix.json` は `roles`（文字列配列）と `features[]`（`unitKey`/`crud` の2フィールドのみ）を持つが、`permission-function-matrix-template.html` が要求する data.json は `roles: [{key,name}...]` と `functions: [{functionKey,functionName,category,permissions}...]` の形状であり、両者は互換しない（`functionName`・`category` に対応する抽出元がスキーマ定義上どこにも存在しない）。`build-matrix-pages.sh --self-test` の連結ケースが permission-screen/crud/traceability の3種のみを対象とし permission-function を意図的に除外しているのも同じ理由による。本スキールはこのギャップを推測で埋めた変換を行わない。生成できる4ページ（permission-screen/crud/traceability/ai-assets）のみ確実に生成し、permission-function は `skipped_pages` に理由を添えて報告する
- feature-manifest（機能一覧）は任意入力であり、不在でも他の交差データは生成できる（`build-matrix-data.sh` の fail-safe。feature 関連フィールドのみ空扱いになる）
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済みページはそのまま残り、次回ポータル生成時に自動でカード化される

## 設計判断

### エンジンスクリプトの共用（extract/・matrix/ 配下）

**必要性**: 抽出・導出・HTML生成はいずれも page-type 非依存の決定的処理であり、`shared/scripts/extract/`・`shared/scripts/matrix/` の単一実装を本スキルが相対パスで参照する。テンプレート側が手作業置換を明示的に禁止する契約（`build-matrix-pages.sh` ヘッダコメント）に従う。

**代替案を採用しなかった理由**:
- Bash ツール直叩きでのプレースホルダ置換: テンプレート側の禁止契約に反し、データ混入・エスケープ漏れを根絶する目的を損なう
- スキル内への複製: 修正のたびに同期漏れが発生する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マトリクス・対応表・AI設定資産ページの生成が別基盤へ移行した時、または対応テンプレート群が廃止された時

### permission-function を推測変換しない判断

**必要性**: `build-matrix-data.sh` の出力とテンプレートの要求形状が一致しないことを自己テスト（連結ケースの意図的除外）から確認済みである。ここで unitKey→functionKey・category の穴埋め等の変換をClaude自身が推測で行うと、根拠のないfunctionName/categoryがマトリクス・対応表に混入し、往復検証の対象外である本スキルが誤情報を生成する側になる。

**代替案を採用しなかった理由**:
- 推測での変換実装: 抽出元が定義されていない値（category等）を捏造することになり、「manifest外参照は捏造しない」という他の生成スキル群の設計原則に反する
- permission-function自体を5ページから削除: `build-matrix-pages.sh`・テンプレートは既に page-type として実装済みであり、本スキルの都合で対応表から消すのは正本の記述と食い違う

**保守責任者**: 人手（ユーザー）。`build-matrix-data.sh` が `functions[]` 形状の出力に対応した時点で本節を撤回し、Phase 4 の permission-function 生成を他4ページと同列に扱う

**廃棄条件**: `build-matrix-data.sh` の出力スキーマが `permission-function-matrix-template.html` の要求形状と一致した時

## 完了報告

`~/.claude/skills/managing-agent-configs/references/skills/completion-report-format.md` の作業報告型に従う。固有差分として「検証」テーブルに `build-matrix-pages.sh` の各page-type実行結果（生成/スキップ）を追加する。

## 参照資料

- `../../../shared/references/manifest-schema-extensions.md` — 種別ごとの追加フィールド定義・マトリクス・対応表用新規データファイル定義・AI設定資産ページのデータ源
- `../../../shared/scripts/matrix/build-matrix-pages.sh` — page-type→テンプレート・必須キーの対応表（正本コメント）
