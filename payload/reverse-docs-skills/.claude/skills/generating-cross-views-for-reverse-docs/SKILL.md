---
name: generating-cross-views-for-reverse-docs
日本語名: 対応表とエージェント設定の一覧を作る
description: "画面・接続窓口・データの一覧をもとに、権限や関係を示す対応表と、エージェント設定のページをまとめて作る。"
invocation: generating-cross-views-for-reverse-docs
type: transform
allowed-tools: [Bash, Read, Write]
---

## いつ使うか

権限の対応表や更新の対応図、画面と接続窓口とデータの対応表、エージェント設定のページなど、対応表・まとめのページを追加したいとき。

## いつ使わないか

画面・接続窓口・データ・機能そのものの一覧を新しく作るとき（それぞれ対応する一覧作成のスキルが担当）、コードと設計書を比べる検証や、環境の同期、実装作業を行うとき。

# 正本: reverse-docs-skills

本スキルが生成する納品物は顧客提示の文書である。自由記述の本文（要約・説明文）は敬体（です・ます）で書く。記入規則・検証記録・作業記録は常体でもよい（`delivery-payload/references/設計書様式.md` §8）。

# マトリクス・対応表生成スキル

工程全体は orchestrating-ai-development-setup が案内する。本スキルはポータルの「マトリクス・対応表」カテゴリ4ページ（権限画面マトリクス・権限機能マトリクス・CRUD図・画面-API-テーブル対応表）と「AI設定資産」カテゴリ1ページの、あわせて5ページを担い、単独起動できる（起動引数を渡せば動く）。

既に確立済みの種別別一覧（画面一覧・API一覧・テーブル一覧・機能一覧）の manifest を突き合わせ、権限・CRUD・画面-API-テーブルの連鎖関係を導出する。**本スキルはソースコードを新規に読み解いて画面・API・テーブルを検出する一覧生成の役割は持たない**。既存 manifest の再構成と、対象リポジトリの `.claude/` 配下（AI設定資産のみ）の走査に限定する。

## 使用タイミング

- raw画面正本・raw由来の拡張画面manifest・API一覧.htmlが確定済みで、ポータルにマトリクス・対応表・AI設定資産のカードを追加したいとき
- 起動引数: `target_repo_path`（対象リポジトリの絶対パス）・`output_dir`（一覧HTML所在 / マトリクス・対応表・AI設定資産の出力先）・`portal_output_dir`（任意）・`sites_path`（任意。複数サイト時の`sites.json`）・`site_key`（任意。対象サイトキー）
- `portal_output_dir` を指定した場合、生成後に `build-portal.sh` を再実行してカードへ反映する

## 出力先（固定・`build-portal.sh` の `get_cross_label`/`CROSS_ORDER` と同値）

| page-type | 出力パス |
|---|---|
| permission-screen | `<output_dir>/project-portal/matrices/permission-screen/権限画面マトリクス.html` |
| permission-function | `<output_dir>/project-portal/matrices/permission-function/権限機能マトリクス.html` |
| crud | `<output_dir>/project-portal/matrices/crud/CRUD図.html` |
| traceability | `<output_dir>/project-portal/matrices/traceability/画面-API-テーブル対応表.html` |
| ai-assets | `<output_dir>/project-portal/foundation/AI設定資産.html` |

`build-portal.sh` はこの5パスの実在有無だけでカードを出す（不在時はセクション自体が非表示になる fail-safe）。パスをこの表からずらすとカードが無言で出ない事故になるため厳守する。

## エンジンスクリプトの所在

抽出・導出・生成はいずれも決定的スクリプトに固定する。Claude 自身が手作業でHTML・JSONを組み立てることはしない。

| スクリプト | パス（スキルフォルダ基点） | 役割 |
|---|---|---|
| 画面メタ拡張抽出 | `../../../generation-engine/scripts/extract/extract-screen-metadata.sh` | permissions・relatedApis 等を screen-manifest に追加 |
| APIメタ拡張抽出 | `../../../generation-engine/scripts/extract/extract-api-metadata.sh` | method・targetTables 等を api-manifest に追加 |
| 交差データ導出 | `../../../generation-engine/scripts/extract/build-matrix-data.sh` | 拡張済みmanifest群から permission-matrix.json・crud-matrix.json・traceability.json を導出 |
| AI設定資産抽出 | `../../../generation-engine/scripts/extract/extract-ai-assets.sh` | `.claude/` 配下から rules/skills/subagents/hooks を抽出 |
| ページHTML生成 | `../../../generation-engine/scripts/matrix/build-matrix-pages.sh` | page-type ごとにテンプレートへ data.json を埋め込み、整合検証（必須トップレベルキー）も兼ねる |
| ポータル再生成（任意） | `../../../generation-engine/scripts/build-portal.sh` | 生成済みページをカードへ反映 |

データスキーマの正本は `delivery-payload/references/manifest-schema-extensions.md`（種別ごとの追加フィールド定義・マトリクス・対応表用新規データファイル定義・AI設定資産ページのデータ源）。`build-matrix-pages.sh` の必須トップレベルキー検査もこの定義と一致させてある（二重管理・ドリフト禁止）。

## 進捗管理（必須手順）

スキル開始時に `TaskCreate` で Phase 1〜4 のタスクを登録する。各 Phase 開始時に該当タスクを `in_progress` に、完了時に `completed` へ `TaskUpdate` で更新する。実行環境に TaskCreate/TaskUpdate が存在しない場合は、`output_dir` 内のタスク台帳ファイル（`task-ledger.md`）で同等の Phase 遷移記録を代替する。

## 実行手順

## Phase 1: 前提確認

## Step 1-1: 前提確認

**使用ツール**: Read / Bash / Write

- **Step 1** — `<output_dir>/<manifestsRoot>/screen-manifest.json`、同`screen-manifest.ext.json`、`<output_dir>/<unitListHtml>`（{label}=「API」）の実在を確認する。いずれか不在ならハード停止する。この場合`generating-screen-list-for-reverse-docs` / `generating-api-list-for-reverse-docs`の先行実行を案内して終了する。通常生成では画面一覧HTMLの埋め込みJSONを逆抽出しない。旧成果物からの移行・復元時だけ`restore-screen-manifest.sh`でrawを正規配置へ復元・検証し、メタデータ抽出でextを再生成してから本スキルを再開する。完了条件: raw・raw由来ext・API一覧HTMLの実在確認済み、または不在を報告して停止している
- **Step 2** — テーブル一覧`<output_dir>/<unitListHtml>`と機能一覧`<output_dir>/<unitListHtml>`の実在を確認する。いずれも任意データ源であり、不在でも Phase 2 以降を続行する（`build-matrix-data.sh` は table-manifest・feature-manifest を省略しても動作する fail-safe 設計）。完了条件: 両ファイルの実在有無が確定済み

**完了**: 画面一覧.html・API一覧.html の実在確認済み（不在時は停止）。テーブル一覧.html・機能一覧.html の実在有無が確定済み

## Phase 2: 拡張マニフェスト抽出 + 交差データ導出

## Step 2-1: 拡張マニフェスト抽出 + 交差データ導出

**使用ツール**: Read / Bash / Write

- **Step 1** — 画面は正規配置のrawとraw由来extを直接入力にする。API・テーブル・機能は各一覧HTMLから埋め込みmanifestを抽出する。抽出先は一時ディレクトリ（`$CLAUDE_JOB_DIR/tmp/`、未設定時は `${TMPDIR:-/tmp}/claude-job-${session}/tmp/` 配下）。

  ```bash
  screen_manifest=<output_dir>/<manifestsRoot>/screen-manifest.json
  screen_manifest_ext=<output_dir>/<manifestsRoot>/screen-manifest.ext.json
  ../../../generation-engine/scripts/unit-list/validate-manifest.sh "$screen_manifest" --unit-kind screen
  ../../../generation-engine/scripts/unit-list/validate-manifest.sh "$screen_manifest_ext" --unit-kind screen
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <API一覧.html> | sed '1d;$d' > api-manifest.json
  # テーブル一覧・機能一覧が実在する場合のみ
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <テーブル一覧.html> | sed '1d;$d' > table-manifest.json
  sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' <機能一覧.html> | sed '1d;$d' > feature-manifest.json
  ```

  画面manifestは正規配置から直接読み、rawの正規化SHA-256とextの`manifestContentHash`が一致することも検査する。それ以外（API・テーブル・機能）は共通の`unit-manifest`を抽出する。完了条件: raw・raw由来extのschemaとhashが検証済みで、他の実在するHTMLすべてからmanifest JSONを抽出済み

- **Step 2** — 検証済みのraw由来拡張画面manifestをそのまま使用する。通常生成では画面一覧HTMLからrawを復元せず、拡張画面manifestも再抽出しない。完了条件: `screen_manifest_ext`が後続入力として確定済み

  ```bash
  test -f "$screen_manifest_ext"
  ```

- **Step 3** — APIメタ拡張抽出を実行する。完了条件: 拡張APIマニフェストが生成済み

  ```bash
  ../../../generation-engine/scripts/extract/extract-api-metadata.sh api-manifest.json <target_repo_path> api-manifest.ext.json --screen-manifest "$screen_manifest_ext" --table-manifest table-manifest.json
  ```

  `--table-manifest` はテーブル一覧が実在する場合のみ付与する。

- **Step 4** — 交差データ導出を実行する。完了条件: `permission-matrix.json`・`crud-matrix.json`・`traceability.json` の3ファイルが生成済み

  ```bash
  ../../../generation-engine/scripts/extract/build-matrix-data.sh <output-dir> \
    --screen-manifest "$screen_manifest_ext" \
    --api-manifest api-manifest.ext.json \
    [--table-manifest table-manifest.json] \
    [--feature-manifest feature-manifest.json]
  ```

  table-manifest・feature-manifest はPhase 1 Step 2 で不在確認したものは省略する（省略時の fail-safe 挙動は `build-matrix-data.sh` ヘッダコメント参照）。

**完了**: 拡張画面/APIマニフェストが生成され、`permission-matrix.json`・`crud-matrix.json`・`traceability.json` が生成済み

## Phase 3: AI設定資産データ抽出

## Step 3-1: AI設定資産データ抽出

**使用ツール**: Bash / Write

- **Step 1** — 対象リポジトリの `.claude/` 配下を走査する。完了条件: `ai-assets-data.json` が生成済み

  ```bash
  ../../../generation-engine/scripts/extract/extract-ai-assets.sh <target_repo_path> ai-assets-data.json
  ```

**非UTF-8原本への対応**: 原本が UTF-8 以外のエンコーディングで書かれている場合、通常の文字列検索はバイナリ扱いとなりマッチ 0 件を返す。走査の前に `generation-engine/scripts/detect-encoding.sh encoding <file>` でエンコーディングを確定し、UTF-8 以外なら `detect-encoding.sh to-utf8` で変換した一時コピーに対して走査する。変換結果は永続化せず一時コピーで足りる。マッチ 0 件を「該当なし」と結論する前に、エンコーディングが原因でないことを確認する。

**完了**: `ai-assets-data.json` が生成済み

## Phase 4: ページHTML生成

## Step 4-1: ページHTML生成

**使用ツール**: Read / Bash / Write

- **Step 1** — 4種のデータ（Phase 2 の3ファイル + Phase 3 の1ファイル）を、`build-matrix-pages.sh` で対応するテンプレートへ埋め込む。**手作業でのプレースホルダ置換は禁止する**（HTML生成は必ずスクリプト経由の決定的処理で行う）。完了条件: 生成可能な全ページがそれぞれの固定パス（本SKILL冒頭の出力先表）に出力済み

  ```bash
  ../../../generation-engine/scripts/matrix/build-matrix-pages.sh permission-screen permission-matrix.json "<output_dir>/<matrixDir>/権限画面マトリクス/権限画面マトリクス.html"
  ../../../generation-engine/scripts/matrix/build-matrix-pages.sh crud crud-matrix.json "<output_dir>/<matrixDir>/CRUD図/CRUD図.html"
  ../../../generation-engine/scripts/matrix/build-matrix-pages.sh traceability traceability.json "<output_dir>/<matrixDir>/画面-API-テーブル対応表/画面-API-テーブル対応表.html"
  ../../../generation-engine/scripts/matrix/build-matrix-pages.sh ai-assets ai-assets-data.json "<output_dir>/AI設定資産/AI設定資産.html"
  ```

  `permission-function`は`build-permission-function-data.sh`で`permission-matrix.json`から決定的に変換してから生成する。

  ```bash
  ../../../generation-engine/scripts/extract/build-permission-function-data.sh \
    permission-matrix.json permission-function-matrix.json \
    --generated-at "<ISO8601 UTC>" --manifest-content-hash "<sha256>"
  ../../../generation-engine/scripts/matrix/build-matrix-pages.sh permission-function \
    permission-function-matrix.json \
    "<output_dir>/<matrixDir>/権限機能マトリクス/権限機能マトリクス.html"
  ```

- **Step 2** — `portal_output_dir` が指定されていればポータル再生成スクリプトを実行しカードへ反映する。未指定なら省略し完了報告に注記する。完了条件: 再実行済み、または省略を注記済み

  ```bash
  ../../../generation-engine/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir> \
    --screen-manifest "$screen_manifest_ext" \
    [--sites <sites_path> --site-key <site_key>]
  ```

**完了**: 生成可能な全ページ（permission-screen / crud / traceability / ai-assets は必ず、permission-function はデータ形状が揃った場合のみ）が固定パスに出力され、指定時は `build-portal.sh` の再実行が完了している

## 完了条件

| Phase | 完了条件 |
|---|---|
| Phase 1 | raw画面正本・raw由来ext・API一覧.htmlの実在確認済み（不在時は停止）。テーブル一覧.html・機能一覧.htmlの実在有無が確定済み |
| Phase 2 | 拡張画面/APIマニフェストが生成され、`permission-matrix.json`・`crud-matrix.json`・`traceability.json` が生成済み |
| Phase 3 | `ai-assets-data.json` が生成済み |
| Phase 4 | 全5ページ（permission-screen / permission-function / crud / traceability / ai-assets）が固定パスに出力され、指定時は `build-portal.sh` の再実行が完了している |
| **Goal** | マトリクス・対応表・AI設定資産のうち生成可能なページがすべて生成され、ポータルのカードへ反映されている。permission-function を未生成のまま終える場合はその理由が完了報告に明記されている |

## 返却ブロック

本スキルは orchestrating-ai-development-setup の契約に準拠する。完了時に以下を返す。

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
- **permission-functionのデータ形状ギャップは変換器で閉じる**。roles文字列は`{key,name}`へ、features[].unitKeyはfunctionKey/functionNameへ写像し、categoryは空文字列、CRUDは`CRU-`形式へ正規化する。推測値を追加せず、重複・型不正・CRUD外文字を拒否する
- feature-manifest（機能一覧）は任意入力であり、不在でも他の交差データは生成できる（`build-matrix-data.sh` の fail-safe。feature 関連フィールドのみ空扱いになる）
- `portal_output_dir` 未指定時は `build-portal.sh` を実行しない。生成済みページはそのまま残り、次回ポータル生成時に自動でカード化される
- `ai-assets-data.json` の rules/skills/subagents/hooks いずれかが 0 件の場合、対象が存在しないのか走査できていないのかを区別して確認する（上記「非UTF-8原本への対応」）

## 設計判断

### エンジンスクリプトの共用（extract/・matrix/ 配下）

**必要性**: 抽出・導出・HTML生成はいずれも page-type 非依存の決定的処理であり、`generation-engine/scripts/extract/`・`generation-engine/scripts/matrix/` の単一実装を本スキルが相対パスで参照する。テンプレート側が手作業置換を明示的に禁止する契約（`build-matrix-pages.sh` ヘッダコメント）に従う。

**代替案を採用しなかった理由**:
- Bash ツール直叩きでのプレースホルダ置換: テンプレート側の禁止契約に反し、データ混入・エスケープ漏れを根絶する目的を損なう
- スキル内への複製: 修正のたびに同期漏れが発生する

**保守責任者**: 人手（ユーザー）

**廃棄条件**: マトリクス・対応表・AI設定資産ページの生成が別基盤へ移行した時、または対応テンプレート群が廃止された時

### permission-function変換器

**必要性**: `permission-matrix.json`と描画テンプレートの形状差を、単一の決定的変換器で閉じる。`functionName=unitKey`、`category=""`は明示契約であり、自由記述の推測はしない。

**保守責任者**: 人手（ユーザー）

**廃棄条件**: `build-matrix-data.sh`がテンプレート要求形状を直接出力するようになった時

## 完了報告

`../../../delivery-payload/references/完了報告の書き方.md` の作業報告型に従う。固有差分として「検証」テーブルに `build-matrix-pages.sh` の各page-type実行結果（生成/スキップ）を追加する。

## 参照資料

- `../../../delivery-payload/references/manifest-schema-extensions.md` — 種別ごとの追加フィールド定義・マトリクス・対応表用新規データファイル定義・AI設定資産ページのデータ源
- `../../../generation-engine/scripts/matrix/build-matrix-pages.sh` — page-type→テンプレート・必須キーの対応表（正本コメント）
