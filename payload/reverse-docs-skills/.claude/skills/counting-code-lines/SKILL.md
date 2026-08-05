---
name: counting-code-lines
description: |
  コード行数・ファイル数を FE/BE 別に計測してJSON出力する。
  TRIGGER when: 「コード行数」「LOC計測」「コード計測」「code-metrics」と言われた時、リバース設計ポータル生成で計測結果が必要な時。
  SKIP: code-metrics.json が既に存在し再計測が不要な時。
invocation: counting-code-lines
type: transform
allowed-tools: [Bash, Read, Write]
---

# コード行数計測スキル

対象ディレクトリのコード行数とファイル数を計測し、FE/BE 別の内訳つきで `code-metrics.json` に出力する。env-config.json を参照して cloc（正確）と find + wc -l（フォールバック）を使い分ける。

## 起動引数

| 引数 | 必須 | 内容 | 既定値 |
|---|---|---|---|
| target_dir | 必須 | 計測対象のディレクトリパス | なし |
| output_dir | 任意 | code-metrics.json の出力先 | カレントディレクトリ |
| env_config | 任意 | env-config.json のパス | `$output_dir/env-config.json` |
| survey_doc_path | 任意 | アーキテクチャ調査書のパス。指定時は技術スタック節・ディレクトリ責務マップから対象拡張子・FE/BE 判定パス・テスト規約を決定する | なし（既定パターンを使用） |

## 実行手順

## Phase 1: 前提確認

## Step 1-1: 前提確認

**使用ツール**: Read / Bash / Write

1. `target_dir` が存在するか確認する。存在しなければエラー終了
2. `env_config` が存在するか確認する。存在しなければ `tools.cloc = false` として扱う（surveying-local-environment の未実行を許容し、フォールバック計測で進める）
3. `mkdir -p "$output_dir"` で出力先を作成する

**完了**: `target_dir` の実在、`env_config` の有無、書き込み可能な `output_dir` が確認済み

## Phase 2: 計測方式の決定

## Step 2-1: 計測方式の決定

**使用ツール**: Read / Bash

`env_config` が存在する場合、`jq -r '.tools.cloc' "$env_config"` で cloc の有無を確認する。

- `true` → cloc 方式
- `false` または env_config 不在 → wc -l 方式

**完了**: cloc方式またはwc -l方式のいずれか一方が確定している

## Phase 3: コード行数の計測

## Step 3-1: コード行数の計測

**使用ツール**: Read / Bash / Write

#### 対象拡張子の決定

- `survey_doc_path` が指定されている場合、当該アーキテクチャ調査書の技術スタック節を読み、実際に使われている言語から対象拡張子を決定する。決定した拡張子一覧を `scanScope.extensions` に、`scanScope.extensionSource` を `"survey"` として記録する
- `survey_doc_path` が指定されていない場合は下記の既定 8 種（`.ts` `.tsx` `.js` `.jsx` `.py` `.sql` `.vue` `.svelte`）を使う。`scanScope.extensionSource` は `"default"` とする
- 既定 8 種のみで走査した場合（survey 方式で決定した拡張子が既定 8 種と一致する場合も含む）、`target_dir` 配下の総ファイル数（`find "$target_dir" -type f | wc -l` 等）と列挙件数の差分を `scanScope.excludedFileCount` として記録する

#### cloc 方式（既定パターン。survey 方式では `--include-lang` を決定済み言語に差し替える）

```bash
cloc "$target_dir" --json \
  --exclude-dir=node_modules,.git,dist,build,__pycache__,.next,coverage \
  --include-lang=TypeScript,JavaScript,Python,SQL,Vue,Svelte \
  2>/dev/null
```

cloc の JSON 出力から `SUM.code`（コード行）を total とする。言語別の内訳は出力に含まれるが、FE/BE 分離は cloc 単体ではできないため、ファイルリスト方式で補完する。

#### wc -l 方式（既定パターン。survey 方式では `-name` の拡張子指定を決定済み拡張子に差し替える）

```bash
find "$target_dir" \
  -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
            -o -name '*.py' -o -name '*.sql' -o -name '*.vue' -o -name '*.svelte' \) \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/.next/*' \
  -not -path '*/coverage/*' \
  2>/dev/null
```

列挙されたファイルに対して `xargs wc -l` で行数を合計する。

#### 除外ディレクトリ（隠しディレクトリの一括除外）

既存 7 種（`node_modules` `.git` `dist` `build` `__pycache__` `.next` `coverage`）に加え、`target_dir` 直下の隠しディレクトリ（`.` で始まるディレクトリ）をすべて除外する。

> リポジトリ直下の隠しディレクトリ（`.` で始まるディレクトリ）は、エディタ拡張の設定・配布物や各種ツールの作業領域であり、対象コードではない。除外すべきディレクトリ名を網羅的に列挙するのではなく、この 1 つの規則で扱う。

除外した隠しディレクトリの名前一覧を `scanScope.excludedDirs` に、それらの配下で対象拡張子に一致していたファイル数を `scanScope.excludedDirFileCount` に記録する。

**完了**: 対象拡張子・除外規則を適用したコード行数のtotalが数値で取得済み

## Phase 4: FE/BE 分離

## Step 4-1: FE/BE 分離

**使用ツール**: Bash / Write

計測対象ファイルのパスに以下のパターンが含まれるかで判定する。BE を先に判定し、一致しなければ FE を判定する。どちらにも一致しないファイルは未分類（total にのみ計上）。

| 判定 | パスに含まれる文字列 |
|---|---|
| BE | `backend/` `api/` `server/` |
| FE | `frontend/` `src/pages/` `src/components/` `src/app/` |
| 未分類 | 上記いずれにも該当しない |

ファイル数も同じパターンで分類する。

判定パターンは、`survey_doc_path` が指定されている場合、アーキテクチャ調査書の技術スタック節とディレクトリ責務マップの記載から補う（例: 調査書が特定のディレクトリを FE・BE いずれかの領域と記載していれば、そのパスを判定パターンに追加する）。`survey_doc_path` が指定されていない場合のみ上表の既定パターンを使う。

未分類のファイル数・行数を集計し `unclassified.files` / `unclassified.lines` に記録する。未分類率（未分類ファイル数 ÷ 列挙ファイル数）を `unclassified.ratio` に記録する。未分類率が 0.5 を超えた場合は `unclassified.warning` を `true` とし、計測結果を報告する際に警告として明示する。全件未分類が無警告で通る状態を許さない。

**完了**: 計測対象の行数とファイル数がFE・BE・未分類へ重複なく分類済み

## Phase 5: テスト計測

## Step 5-1: テスト計測

**使用ツール**: Read / Bash / Write

テストファイルを以下のパターンで列挙する。除外規則は Phase 3 の wc -l 方式と同じである。除外対象は `node_modules` / `.git` / `dist` / `build` / `__pycache__` / `.next` / `coverage`、および `target_dir` 直下の隠しディレクトリ（`.` で始まるディレクトリ）である。

- `*.test.ts` / `*.test.tsx` / `*.spec.ts` / `*.spec.tsx`
- `test_*.py` / `*_test.py`

列挙したテストファイルに対して、ファイル内容からアサーション出現数を grep で計数する。計数パターンは、`survey_doc_path` が指定されている場合はアーキテクチャ調査書のテスト規約（フレームワーク）から決定する。

指定されていない場合は既定パターン（`it(` / `test(` / `def test_` / Perl Test::More形式の `ok(` / `is(` / `like(`）を全て試す。テストファイルを先に列挙してから計数することで、テスト以外のファイル内の偶発的な文字列一致を防ぐ。テストファイルが1件以上検出されているにもかかわらず既定パターンに一致しない場合は `tests.assertionPatternUnsupported` を `true` として記録する。`tests.count` は 0 のままにして、「アサーションが存在しない」場合と区別する。

FE/BE の内訳は Phase 4 と同じ判定パスをそのまま適用する。判定パスは、パスに `backend/` `api/` `server/` を含めば BE とする。パスに `frontend/` `src/pages/` `src/components/` `src/app/` を含めば FE とする。テストファイル数も同じ判定パスで分類する。

テストファイルの列挙パターンは、`survey_doc_path` が指定されている場合、アーキテクチャ調査書の技術スタック節に記載されたテスト規約（フレームワーク・命名規則）から決定する。`survey_doc_path` が指定されていない場合のみ既定 6 種（`*.test.ts` `*.test.tsx` `*.spec.ts` `*.spec.tsx` `test_*.py` `*_test.py`）を使う。

既定パターンで列挙が 0 件になった場合は `testDetectionFailed` を `true` として記録し、「テストが存在しない」場合と区別する。`target_dir` 内にテストランナーの設定（`jest.config.*` `pytest.ini` `vitest.config.*` 等）やテスト用ディレクトリ（`tests/` `__tests__/` `test/`）が実在せず、かつ列挙が 0 件であることを確認できた場合に限り、テストが実在しないと判断して `testDetectionFailed` を `false` のままとする。

**完了**: テスト件数・テストファイル数とFE/BE内訳が数値で取得済み

## Phase 6: code-metrics.json の出力

## Step 6-1: code-metrics.json の出力

**使用ツール**: Read / Bash / Write

Write 前に `$output_dir/code-metrics.json` が既存であれば読み込む。`total` の値を `previous.total` として、`tests.count` の値を `previous.tests_count` として、`measured_at` の値を `previous.measured_at` として転記する。ファイル不在時、すなわち初回計測時は `previous` を `null` にする。デフォルト値は作らない。

`git -C "$target_dir" rev-parse HEAD` で計測時のコミットハッシュを取得し `commit` に記録する（`target_dir` が git 管理外の場合は `null`）。

計測結果を JSON 形式で `$output_dir/code-metrics.json` に Write する。

**完了**: `code-metrics.json` が正しいJSONとして存在し、commit・total・tests・previousが記録済み

```json
{
  "total": 67738,
  "fe": 52230,
  "be": 15508,
  "file_count": 512,
  "fe_files": 371,
  "be_files": 141,
  "method": "cloc",
  "measured_at": "<ISO8601 タイムスタンプ>",
  "commit": "<git rev-parse HEAD の値 | null>",
  "tests": { "count": 128, "fe": 84, "be": 44, "files": 37, "assertionPatternUnsupported": false },
  "previous": { "total": 66210, "tests_count": 120, "measured_at": "<前回計測時の ISO8601 タイムスタンプ>" },
  "scanScope": {
    "extensions": ["<採用した対象拡張子>"],
    "extensionSource": "survey | default",
    "excludedFileCount": 0,
    "excludedDirs": ["<除外したディレクトリ名>"],
    "excludedDirFileCount": 0
  },
  "unclassified": {
    "files": 0,
    "lines": 0,
    "ratio": 0.0,
    "warning": false
  },
  "testDetectionFailed": false
}
```

`method` は `"cloc"` または `"wc"` を記録する。`previous` はファイル不在（初回計測）時のみ `null` を記録する。`scanScope`・`unclassified`・`testDetectionFailed` は既存キーに追加する新規キーであり、既存キーの値・意味は変更しない。`unclassified.warning` は `unclassified.ratio` が 0.5 を超えたときに `true` とする。`tests.assertionPatternUnsupported` は、既定パターンが対応しない言語のテストファイルが検出された場合に `true` とする。

## 完了条件

| Phase | 条件 |
|---|---|
| Phase 1 | target_dir の存在確認済み、出力先が準備済み |
| Phase 2 | 計測方式（cloc/wc）が決定済み |
| Phase 3 | コード行数の計測が完了。scanScope（対象拡張子・除外ディレクトリ）が記録済み |
| Phase 4 | FE/BE の分離が完了。unclassified（件数・行数・率・警告）が記録済み |
| Phase 5 | テスト計測（件数・FE/BE 内訳・ファイル数）が完了。testDetectionFailed・tests.assertionPatternUnsupported が記録済み |
| Phase 6 | code-metrics.json が出力先に存在する |
| **Goal** | `shared/scripts/validate-code-metrics.sh "$output_dir/code-metrics.json"` の終了コードが 0 であること。終了コード 0 は total/fe/be/file_count/tests/commit/previous/scanScope/unclassified/testDetectionFailed の値が妥当であることの機械的な合格判定であり、自然文の自己申告に代える |

## 使用タイミング

- リバース設計フローのglobal Step 16（ポータル生成）でポータルの解析サマリに表示するコード行数を計測する時
- 任意のプロジェクトのコード規模を概算したい時

## 予想を裏切る挙動

- cloc と wc -l で同じコードベースを計測すると 20〜40% の差が出る。cloc はコメント行・空行を除外するため小さい値になる。`method` フィールドで計測方式を記録しているので、消費側は方式を考慮して表示できる
- FE/BE のパターンに一致しないファイル（設定ファイル・テストファイル等）は total にのみ計上される。そのため `total ≠ fe + be` になりうる
- 未分類率は `unclassified.ratio` として計測結果に記録され、0.5 を超えると `unclassified.warning` が真になる
- 大規模リポジトリ（10万行超）では cloc の実行に数十秒かかる場合がある
- `it.each` / パラメタライズドテスト / `describe.each` は展開後の実行時ケース数ではなく 1 件として計数される。グロブ・grep ベースの静的計数のため、実行時に動的展開されるケース数までは追跡しない
- テスト以外の種類のファイル（ドキュメント・スクリプト等）に書かれた `it(` / `test(` / `def test_` / `ok(` / `is(` / `like(` 相当の文字列は計数されない。テストファイル名パターンに一致するファイルのみが計数対象

## 完了報告

`managing-agent-configs/references/skills/completion-report-format.md` の共通骨格（作業報告型）に従う。

固有の検証行:
- code-metrics.json の生成成功・JSON valid・total/fe/be/file_count の値が存在
- `shared/scripts/validate-code-metrics.sh "$output_dir/code-metrics.json"` の終了コードが 0

## 設計判断

### shared/scripts/validate-code-metrics.sh

- **必要性**: 改善課題 1-109 が指摘するとおり、本スキルは出力 JSON の構文検証・キー充足検証の手順を持たず完了判定が自己申告になっている。決定的な検査の exit code を完了判定に使うため、`validate-code-metrics.sh` を新設した
- **代替案を採用しなかった理由**: SKILL.md 本文への検査手順の直書きは、検査ロジックが自然文に埋もれて機械実行できない。他スキルの `validate-*.sh` と同様に独立スクリプト化し、終了コードで合否を判定できる形にした
- **保守責任者**: 人手（ユーザー）。code-metrics.json のスキーマ（必須キー）を変更した場合は `validate-code-metrics.sh` の必須キー対応表を同時に更新する
- **廃棄条件**: counting-code-lines スキル自体が廃止された時、またはスキーマ検証をビルド基盤が標準で提供するようになった時

詳細は `shared/scripts/validate-code-metrics.sh` 本体のヘッダコメントを参照する。
