#!/usr/bin/env bash
set -euo pipefail

# build-deliverable-inventory.sh — 「納品物一覧」をカタログと定義から生成する
#
# 目的:
#   納品先ポータル(HTML)とAI向け(Markdown)の両方へ、納品物ごとに「出力の有無と
#   理由」を持つ一覧を1つの定義から生成する。読み手は「画面一覧が無いのは、まだ
#   生成していないのか、対象が無いので出力されないのか」を1枚で判別できる。
#
#   定義は2つの既存正本を結合して作る。新規の重複データは持たない。
#     (1) delivery-payload/references/portal-catalog.json — 納品物・出力先(discovery.glob)・
#         生成元(generator)の正本。60件のblueprintをkindで引く。
#     (2) delivery-payload/references/deliverable-inventory.json — 本スクリプト専用の新規宣言。
#         カタログには無い「状態をどの証拠で判定するか」だけを持つ。60件全kindを
#         カバーし、7種別(screen/api/table/batch/report/external/feature)は
#         output-layout.jsonのマニフェストキー名とマニフェスト内の件数ポインタ(JSON
#         Pointer形式)を宣言する。screenに依存する8種別(screen-transition・
#         test-viewpoint-list・test-case-list・permission-screen・permission-function・
#         crud・traceability・confirmation-survey)は dependsOnKind で依存先kindを
#         宣言する。残りは証拠なし(none)を宣言する。
#   状態判定:
#     出力あり: discovery.glob の実ファイルが存在する
#     対象なし: (a) 実ファイルは無いが、自身のkindが対象外種別の記録
#               (output-layoutの excludedKinds キーが指す docs/scope-and-progress/
#               excluded-kinds.json 等)の excludedKinds(設計単位6種別専用)、または
#               同ファイルの excludedDeliverables(6種別に属さない納品物用。kind・
#               label・reason・categoryを持つ。形式は
#               .claude/skills/orchestrating-ai-development-setup/references/
#               contract.md の「excludedDeliverables」節を参照)に載っている。
#               (b) dependsOnKindの依存先kindが対象外種別の記録に載っている。
#               (c) 対応マニフェストが存在し件数0を示す
#     未生成:   実ファイルもマニフェストも無い、対象外の記録も無い、またはそもそも
#               証拠(マニフェスト概念)が無い kind。理由文は区別して書く
#   excludedKinds と excludedDeliverables の関係: 前者は
#   check-excluded-kinds-consistency.sh が設計単位6種別との完全一致を検査する
#   対象であり、本スクリプトはそれを変えない。後者は本スクリプトだけが読み、
#   6種別に属さない納品物(例: entity-state)を対象なしと判定するための鍵である。
#   件数の取得(countPointer)はJSON Pointer形式の値をgetpath用のパス配列へ変換して
#   jqへ渡す。形式不正・jq失敗はエラーとして報告し、既定値0へは倒さない。
#
# 使い方:
#   build-deliverable-inventory.sh <output_root> [<html_output_path> <md_output_path>]
#     [--project-name <name>] [--generated-at <ISO-8601>] [--catalog <file>]
#     [--deliverable-inventory <file>]
#   HTML・Markdownの出力先はoutput-layout.jsonから解決する。旧形式の出力先引数も
#   定義値と一致する場合だけ受け付け、定義外の置き場は異常終了する。
#   build-deliverable-inventory.sh --self-test
#
# 出力: HTML(project-portal共通シェルに乗せた単一テーブルページ)とMarkdown
#   (docs/配下、時点表明つき)の2形式。同じ導出結果(行データ)から両方を書く。
#
# 終了コード: 0 = 生成完了。1 = 引数不正・入力不正・カタログとの被覆不一致・self-test失敗。
#
# 保守責任者・廃棄条件:
#   .claude/rules/scoped/portal/page-conventions/rule.md の「## 設計判断」
#   「### build-deliverable-inventory.sh」を参照。
#
# macOS bash 3.2 互換(連想配列・mapfileは不使用)。

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../../delivery-payload/templates"
TOKENS_CSS_FILE="$TEMPLATES_DIR/tokens.css"
DEFAULT_CATALOG="$SCRIPT_DIR/../../delivery-payload/references/portal-catalog.json"
DEFAULT_INVENTORY_DEF="$SCRIPT_DIR/../../delivery-payload/references/deliverable-inventory.json"

# shellcheck source=./render-template.sh
. "$SCRIPT_DIR/render-template.sh"
# shellcheck source=./shell-injection.sh
. "$SCRIPT_DIR/shell-injection.sh"
# shellcheck source=./output-layout.sh
. "$SCRIPT_DIR/output-layout.sh"

# 一時ファイルを作る。
#
# 実装判断: プロセス置換（<(...)）を diff・comm など外部コマンドの引数へ
# 渡すと /dev/fd/N が渡るが、実行環境によってはこれを開けない
# （実測 2026-08-24: diff: /dev/fd/11: Operation not permitted）。
# 比較そのものが失敗するため、失敗を「不合格」と読み違えると、中身に問題が
# 無いのに不合格を報告する。一時ファイルを経由してこの揺れを断つ。
#
# 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして
# 失敗するためである（実測 2026-08-24:
# mktemp: mkstemp failed on /var/folders/.../T/tmp.XXXX: Operation not
# permitted）。TMPDIR を明示すると成功する。
# この形を素直な mktemp へ戻してはならない。手元で動いても環境が変われば
# 再び壊れる。
_mk_tmp() {
  mktemp "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null
}

# --- カタログと定義の被覆検査(双方向)。1件でも欠けたらERRORで止める ---
validate_coverage() {
  local catalog="$1" inventory_def="$2"
  local catalog_kinds inventory_kinds missing_in_def missing_in_catalog _ta _tb

  catalog_kinds="$(jq -r '[.categories[].blueprints[].kind] | sort | .[]' "$catalog")"
  inventory_kinds="$(jq -r '[.items[].kind] | sort | .[]' "$inventory_def")"

  if ! _ta="$(_mk_tmp)" || [ -z "$_ta" ] || ! _tb="$(_mk_tmp)" || [ -z "$_tb" ]; then
    rm -f "${_ta:-}" "${_tb:-}"
    echo "[UNKNOWN] 一時ファイルを作れないためカタログと納品物一覧定義のkind被覆を判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  printf '%s\n' "$catalog_kinds" > "$_ta"
  printf '%s\n' "$inventory_kinds" > "$_tb"
  missing_in_def="$(comm -23 "$_ta" "$_tb")"
  missing_in_catalog="$(comm -13 "$_ta" "$_tb")"
  rm -f "$_ta" "$_tb"

  if [ -n "$missing_in_def" ] || [ -n "$missing_in_catalog" ]; then
    echo "ERROR: カタログと納品物一覧定義のkindが一致しない" >&2
    [ -n "$missing_in_def" ] && { echo "  定義に無い(カタログのみ):" >&2; printf '    %s\n' $missing_in_def >&2; }
    [ -n "$missing_in_catalog" ] && { echo "  カタログに無い(定義のみ):" >&2; printf '    %s\n' $missing_in_catalog >&2; }
    return 1
  fi
  return 0
}

# --- 本スクリプトが生成する2形式の置き場を宣言から検証する。
#     対象側の上書きでnull・絶対パス・上位脱出等へ変えられた場合も生成前に止める ---
validate_inventory_output_layout() {
  local layout_json="$1" key value
  for key in deliverableInventoryHtml deliverableInventoryMarkdown; do
    if ! printf '%s' "$layout_json" | jq -e --arg k "$key" '.layout[$k] | type == "string"' >/dev/null 2>&1; then
      echo "ERROR: output-layout の $key は文字列で必須です" >&2
      return 1
    fi
    value="$(output_layout_get "$layout_json" "$key")" || return 1
    _output_layout_check_relpath "$key" "$value" || return 1
  done
}

# --- JSON Pointer文字列(例: "/screens")をjqのgetpath用パス配列へ変換する。
#     形式が不正(先頭がスラッシュでない)なら失敗(戻り値1)を返す ---
json_pointer_to_jq_path() {
  local pointer="$1"
  case "$pointer" in
    '') printf '[]'; return 0 ;;
    /*) : ;;
    *) return 1 ;;
  esac
  jq -n --arg p "$pointer" '$p | ltrimstr("/") | split("/") | map(gsub("~1";"/") | gsub("~0";"~"))' 2>/dev/null
}

# カタログのdefaultRootsを対象側output-layoutで置換し、実効globを返す。
resolve_catalog_glob() {
  local catalog="$1" layout_json="$2" raw_glob="$3"
  jq -r --arg glob "$raw_glob" --argjson layout "$layout_json" '
    reduce ((.defaultRoots // {}) | to_entries[]) as $root ($glob;
      if . == $root.value then ($layout.layout[$root.key] // .)
      elif startswith($root.value + "/") then (($layout.layout[$root.key] // $root.value) + .[($root.value | length):])
      else . end
    )
  ' "$catalog"
}

# 安全な相対globに一致する実在HTMLを探す。bashの条件パターンは ** を含むglobも評価できる。
has_matching_html() {
  local output_root="$1" html_glob="$2" path relative
  case "$html_glob" in
    *\**|*\?*|*\[*) : ;;
    *) [ -f "$output_root/$html_glob" ]; return ;;
  esac
  while IFS= read -r path; do
    relative="${path#"$output_root"/}"
    if [[ "$relative" == $html_glob ]]; then
      return 0
    fi
  done < <(find "$output_root" -type f -name '*.html' -print)
  return 1
}

# --- 対象外種別の記録(excluded-kinds.json)を読み出す。存在しない・読めない場合は
#     空配列を返す(fail-open。除外の記録が無い場合は従来どおり未生成へ倒れる)。
#     excludedKinds(設計単位6種別専用。check-excluded-kinds-consistency.shが
#     完全一致を検査する対象)と excludedDeliverables(6種別に属さない納品物用。
#     本スクリプトだけが読む。形式は contract.md の「excludedDeliverables」節を
#     参照)を連結して返す。同じkindが両方に載っていても連結時に重複しうるが、
#     excluded_reason_for_kindは最初の一致だけを使うため判定結果には影響しない ---
load_excluded_kinds() {
  local output_root="$1" layout_json="$2"
  local rel path
  rel="$(output_layout_get "$layout_json" "excludedKinds" 2>/dev/null)" || { printf '[]'; return 0; }
  path="$output_root/$rel"
  [ -f "$path" ] || { printf '[]'; return 0; }
  jq -c '(.excludedKinds // []) + (.excludedDeliverables // [])' "$path" 2>/dev/null || printf '[]'
}

# --- 指定kindが対象外種別の記録に含まれるか判定する。含まれれば記録済みの理由を返す ---
excluded_reason_for_kind() {
  local excluded_json="${1:-}" kind="$2"
  [ -n "$excluded_json" ] || excluded_json='[]'
  printf '%s' "$excluded_json" | jq -r --arg k "$kind" '[.[] | select(.kind==$k)][0].reason // empty'
}

# --- 1件のkindの状態と理由を判定する。標準出力へ "状態<TAB>理由" を1行返す。
#     件数の取得に失敗した場合はエラーを標準エラーへ出し、戻り値1で返す
#     (既定値0へ倒さない。呼び出し元はset -eで停止する) ---
resolve_state() {
  local output_root="$1" html_glob="$2" kind="$3" inventory_def="$4" layout_json="$5" excluded_json="$6"
  local evidence_source manifest_key count_pointer manifest_rel manifest_path item_count
  local own_reason depends_on depends_reason jq_path_json item_count_output
  local absence_reason missing_without_declaration_state

  own_reason="$(excluded_reason_for_kind "$excluded_json" "$kind")"
  if [ -n "$own_reason" ]; then
    absence_reason="$(jq -r --arg k "$kind" '.absencePolicies[$k].reasonTemplate // empty' "$inventory_def")"
    [ -n "$absence_reason" ] || absence_reason="$own_reason"
    printf '対象なし\t%s\n' "$absence_reason"
    return 0
  fi

  depends_on="$(jq -r --arg k "$kind" '.items[] | select(.kind==$k) | .dependsOnKind // empty' "$inventory_def")"
  if [ -n "$depends_on" ]; then
    depends_reason="$(excluded_reason_for_kind "$excluded_json" "$depends_on")"
    if [ -n "$depends_reason" ]; then
      absence_reason="$(jq -r --arg k "$depends_on" '.absencePolicies[$k].reasonTemplate // empty' "$inventory_def")"
      [ -n "$absence_reason" ] || absence_reason="依存先「${depends_on}」が対象外のため生成されない(${depends_reason})"
      printf '対象なし\t%s\n' "$absence_reason"
      return 0
    fi
  fi

  if has_matching_html "$output_root" "$html_glob"; then
    printf '出力あり\t\n'
    return 0
  fi

  evidence_source="$(jq -r --arg k "$kind" '.items[] | select(.kind==$k) | .evidenceSource' "$inventory_def")"

  if [ "$evidence_source" != "manifest" ]; then
    printf '未生成\t判定の材料が無い\n'
    return 0
  fi

  manifest_key="$(jq -r --arg k "$kind" '.items[] | select(.kind==$k) | .manifestKey' "$inventory_def")"
  count_pointer="$(jq -r --arg k "$kind" '.items[] | select(.kind==$k) | .countPointer' "$inventory_def")"
  manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || { printf '未生成\t判定の材料が無い\n'; return 0; }
  manifest_path="$output_root/$manifest_rel"

  if [ ! -f "$manifest_path" ]; then
    printf '未生成\tマニフェスト未生成のため生成スキル未実行と判定\n'
    return 0
  fi

  jq_path_json="$(json_pointer_to_jq_path "$count_pointer")" || {
    echo "ERROR: countPointerがJSON Pointer形式ではありません(kind=$kind, countPointer=$count_pointer)" >&2
    return 1
  }
  if ! item_count_output="$(jq --argjson p "$jq_path_json" '(getpath($p) // []) | length' "$manifest_path" 2>&1)"; then
    echo "ERROR: 件数の取得に失敗しました(kind=$kind, manifest=$manifest_path): $item_count_output" >&2
    return 1
  fi
  item_count="$item_count_output"

  if [ "$item_count" = "0" ]; then
    missing_without_declaration_state="$(jq -r --arg k "$kind" '.absencePolicies[$k].missingWithoutDeclarationState // empty' "$inventory_def")"
    if [ -n "$missing_without_declaration_state" ]; then
      printf '%s\t対象外宣言がないため対象なしと判定できない\n' "$missing_without_declaration_state"
    else
      printf '対象なし\t対象0件のため生成されない\n'
    fi
  else
    printf '未生成\tマニフェストは存在するがHTML未生成(不整合)\n'
  fi
}

# --- 全kind分の行データを組み立てる。TSV(納品物<TAB>出力先<TAB>生成元<TAB>状態<TAB>理由)を返す ---
build_rows() {
  local output_root="$1" catalog="$2" inventory_def="$3"
  local layout_json excluded_json
  layout_json="$(resolve_output_layout "$output_root")" || return 1
  excluded_json="$(load_excluded_kinds "$output_root" "$layout_json")"

  local kind label glob generator state_reason state reason effective_glob
  while IFS=$'\t' read -r kind label glob generator; do
    [ -n "$kind" ] || continue
    effective_glob="$(resolve_catalog_glob "$catalog" "$layout_json" "$glob")" || return 1
    state_reason="$(resolve_state "$output_root" "$effective_glob" "$kind" "$inventory_def" "$layout_json" "$excluded_json")"
    state="$(printf '%s' "$state_reason" | cut -f1)"
    reason="$(printf '%s' "$state_reason" | cut -f2)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$effective_glob" "$generator" "$state" "$reason"
  done < <(jq -r '.categories[].blueprints[] | [.kind, .label, .discovery.glob, .generator] | @tsv' "$catalog")
}

PAGE_TEMPLATE='<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>本資料一覧</title>
<style>
/* TOKENS_CSS */
/* SHELL_CSS */

* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }

.di-lead { flex: none; margin: 16px 0 20px; font-size: 0.85rem; color: var(--sub); max-width: 72ch; }

.table-area { flex: 1; min-height: 0; overflow-y: auto; }

table.di { width: 100%; table-layout: fixed; border-collapse: separate; border-spacing: 0; font-size: 0.85rem; }
table.di th, table.di td { border-top: 1px solid var(--line); padding: 7px 10px; text-align: left; vertical-align: top; word-break: break-word; }
table.di thead th { position: sticky; top: 0; background: var(--bg); font-size: 11px; font-weight: 600; color: var(--muted); }
table.di td.di-state-出力あり { color: var(--ok, inherit); }
</style>
</head>
<body>
<div class="pt">
  <div class="pt-grid"></div>
  <div class="pt-row">
    <!--SHELL_SIDEBAR-->
    <main class="pt-main is-fixed">
      <div class="pt-head">
        <div class="pt-crumb"><a href="{{BACK_LINK}}">TOP</a> ／ {{ACTIVE_CATEGORY_LABEL}} ／ <span class="pt-crumb-current">本資料一覧</span></div>
        <div class="pt-title-row">
          <h1 class="pt-title">本資料一覧</h1>
          <span class="pt-title-sub">更新 {{GENERATED_AT}} ／ 本資料 {{ITEM_COUNT}} 件</span>
        </div>
      </div>

      <p class="di-lead">本資料ごとに、出力先・生成元・状態(出力あり／対象なし／未生成)・理由を示す。「対象なし」は生成対象が0件と確認できた場合、「未生成」はまだ判定できないか未実行の場合。</p>

      <div class="table-area">
        <div class="pt-tablewrap">
        <table class="di">
        <thead><tr><th>本資料</th><th>出力先</th><th>生成元</th><th>状態</th><th>理由</th></tr></thead>
        <tbody>
        {{ROWS_HTML}}
        </tbody>
        </table>
        </div>
      </div>
    </main>
  </div>
  <!--SHELL_FOOTER-->
</div>
</body>
</html>
'

USAGE="Usage: build-deliverable-inventory.sh <output_root> [<html_output_path> <md_output_path>] [--project-name <name>] [--generated-at <iso8601>] [--catalog <file>] [--deliverable-inventory <file>]
       build-deliverable-inventory.sh --self-test"

run_build() {
  local output_root="$1"
  shift

  local supplied_html_output="" supplied_md_output=""
  if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
    if [ $# -lt 2 ] || [ "${2#--}" != "$2" ]; then
      echo "ERROR: 旧形式の出力先引数はHTMLとMarkdownの2つを指定してください" >&2
      echo "$USAGE" >&2
      return 1
    fi
    supplied_html_output="$1"
    supplied_md_output="$2"
    shift 2
  fi

  local project_name="" generated_at="" catalog="" inventory_def=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-name) project_name="${2:-}"; shift 2 ;;
      --generated-at) generated_at="${2:-}"; shift 2 ;;
      --catalog) catalog="${2:-}"; shift 2 ;;
      --deliverable-inventory) inventory_def="${2:-}"; shift 2 ;;
      *) echo "ERROR: unknown argument: $1" >&2; echo "$USAGE" >&2; return 1 ;;
    esac
  done

  catalog="${catalog:-$DEFAULT_CATALOG}"
  inventory_def="${inventory_def:-$DEFAULT_INVENTORY_DEF}"

  if [ ! -d "$output_root" ]; then
    echo "ERROR: output_root not found: $output_root" >&2
    return 1
  fi

  local layout_json html_output md_output html_rel md_rel
  layout_json="$(resolve_output_layout "$output_root")" || return 1
  validate_inventory_output_layout "$layout_json" || return 1
  html_rel="$(output_layout_get "$layout_json" "deliverableInventoryHtml")" || return 1
  md_rel="$(output_layout_get "$layout_json" "deliverableInventoryMarkdown")" || return 1
  html_output="$output_root/$html_rel"
  md_output="$output_root/$md_rel"

  if [ -n "$supplied_html_output" ] && { [ "$supplied_html_output" != "$html_output" ] || [ "$supplied_md_output" != "$md_output" ]; }; then
    echo "ERROR: 納品物一覧の出力先はoutput-layout.jsonの定義と一致しません" >&2
    echo "  HTML: $html_output" >&2
    echo "  Markdown: $md_output" >&2
    return 1
  fi
  if [ ! -f "$catalog" ]; then
    echo "ERROR: catalog not found: $catalog" >&2
    return 1
  fi
  if [ ! -f "$inventory_def" ]; then
    echo "ERROR: deliverable-inventory not found: $inventory_def" >&2
    return 1
  fi
  if [ ! -f "$TOKENS_CSS_FILE" ]; then
    echo "ERROR: tokens.css not found: $TOKENS_CSS_FILE" >&2
    return 1
  fi

  validate_coverage "$catalog" "$inventory_def" || return 1

  [ -z "$generated_at" ] && generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local rows_tsv item_count
  rows_tsv="$(build_rows "$output_root" "$catalog" "$inventory_def")" || return 1
  item_count="$(printf '%s\n' "$rows_tsv" | grep -c . || true)"

  # --- HTML行の組み立て ---
  local rows_html
  rows_html="$(printf '%s\n' "$rows_tsv" | jq -Rr '
    split("\t") | select(length==5) |
    "<tr><td>\(.[0])</td><td><code>\(.[1])</code></td><td>\(.[2])</td><td class=\"di-state-\(.[3])\">\(.[3])</td><td>\(.[4])</td></tr>"
  ' | sed 's/&/\&amp;/g' 2>/dev/null || true)"
  # jqの-Rr行入力はエスケープを行わないため、HTML特殊文字はここでは値が既にプレーンテキストの
  # 日本語ラベル・パス・固定文言のみであることを前提にする(カタログ・定義とも制御文字を含まない)。

  mkdir -p "$(dirname "$html_output")"
  mkdir -p "$(dirname "$md_output")"

  local render_args=(
    "{{GENERATED_AT}}" "$generated_at"
    "{{ITEM_COUNT}}" "$item_count"
  )
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")

  if type shell_injection_args >/dev/null 2>&1; then
    shell_injection_args "$TEMPLATES_DIR" "$catalog" "../index.html" "$project_name" "$generated_at" "" \
      "build-deliverable-inventory" "project"
    if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
      render_args+=("${SHELL_RENDER_ARGS[@]}")
    fi
  fi

  render_args+=("{{BACK_LINK}}" "../index.html")
  render_args+=("{{ROWS_HTML}}" "$rows_html")

  local out
  out="$(render_template "$PAGE_TEMPLATE" "${render_args[@]}")"
  printf '%s\n' "$out" > "$html_output"

  # --- Markdownの組み立て(時点表明つき。check-doc-claim-freshness.sh 準拠) ---
  local md_rows
  md_rows="$(printf '%s\n' "$rows_tsv" | awk -F'\t' '{printf "| %s | `%s` | %s | %s | %s |\n", $1, $2, $3, $4, $5}')"
  {
    printf '# 本資料一覧\n\n'
    printf '本書は %s 時点の状態を示す。生成元は delivery-payload/references/portal-catalog.json と delivery-payload/references/deliverable-inventory.json。\n\n' "$generated_at"
    printf '| 本資料 | 出力先 | 生成元 | 状態 | 理由 |\n'
    printf '|---|---|---|---|---|\n'
    printf '%s\n' "$md_rows"
  } > "$md_output"

  echo "OK: wrote $html_output" >&2
  echo "OK: wrote $md_output" >&2
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local script_path="$0"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-deliverable-inventory-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local catalog="$SCRIPT_DIR/../../delivery-payload/references/portal-catalog.json"
  local inventory_def="$SCRIPT_DIR/../../delivery-payload/references/deliverable-inventory.json"

  # ケース1: カタログと定義のkind被覆が一致する(双方向)
  if validate_coverage "$catalog" "$inventory_def" >"$tmp/coverage.log" 2>&1; then
    echo "  [PASS] ケース1: カタログと定義のkindが1:1で一致する"
  else
    echo "  [FAIL] ケース1: カタログと定義のkindが一致しない" >&2
    sed 's/^/    /' "$tmp/coverage.log" >&2
    rc=1
  fi

  # ケース2: 生成コマンド自体が成功し、HTML/Markdown双方が実在する
  local out_root="$tmp/output-root"
  mkdir -p "$out_root"
  local layout_json html_rel md_rel html_out md_out
  layout_json="$(resolve_output_layout "$out_root")"
  html_rel="$(output_layout_get "$layout_json" "deliverableInventoryHtml")"
  md_rel="$(output_layout_get "$layout_json" "deliverableInventoryMarkdown")"
  html_out="$out_root/$html_rel"
  md_out="$out_root/$md_rel"
  local build_log="$tmp/build.log"
  if bash "$script_path" "$out_root" --project-name "テストプロジェクト" --generated-at "2026-01-01T00:00:00Z" >"$build_log" 2>&1; then
    echo "  [PASS] ケース2: 生成コマンドが成功する"
  else
    echo "  [FAIL] ケース2: 生成コマンドが失敗した" >&2
    sed 's/^/    /' "$build_log" >&2
    rc=1
  fi
  if [ -f "$html_out" ] && [ -f "$md_out" ]; then
    echo "  [PASS] ケース3: HTMLとMarkdownの両方が実在する"
  else
    echo "  [FAIL] ケース3: 出力が欠落している(html=$([ -f "$html_out" ] && echo 有 || echo 無) md=$([ -f "$md_out" ] && echo 有 || echo 無))" >&2
    rc=1
    echo "self-test FAIL(ケース3で打ち切り)" >&2
    return 1
  fi

  # ケース4: 60件全kindの納品物名がHTMLとMarkdownの両方に現れる
  local expected_count missing_html=0 missing_md=0 label
  expected_count="$(jq '[.categories[].blueprints[]] | length' "$catalog")"
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    grep -qF "$label" "$html_out" || { missing_html=$((missing_html + 1)); }
    grep -qF "$label" "$md_out" || { missing_md=$((missing_md + 1)); }
  done < <(jq -r '.categories[].blueprints[].label' "$catalog")
  if [ "$missing_html" -eq 0 ] && [ "$missing_md" -eq 0 ]; then
    echo "  [PASS] ケース4: カタログ全${expected_count}件の納品物名がHTML・Markdown双方に現れる"
  else
    echo "  [FAIL] ケース4: HTML欠落${missing_html}件・Markdown欠落${missing_md}件" >&2
    rc=1
  fi

  # ケース5: 宣言なしの0件は未生成のまま、HTML実在時だけ出力ありになる
  #   合成 output_root を3通り用意する: (a) マニフェスト無し (b) マニフェスト0件 (c) HTML実在
  #   screenブループリントのdiscovery.globとoutput-layoutのscreenManifestを使う。
  local screen_glob screen_manifest_rel
  screen_glob="$(jq -r '.categories[].blueprints[] | select(.kind=="screen") | .discovery.glob' "$catalog")"
  screen_manifest_rel="$(jq -r '.layout.screenManifest' "$SCRIPT_DIR/../../delivery-payload/references/output-layout.json")"

  local root_a root_b root_c
  root_a="$tmp/case5-a-no-manifest"; mkdir -p "$root_a"
  root_b="$tmp/case5-b-zero-manifest"; mkdir -p "$root_b/$(dirname "$screen_manifest_rel")"
  echo '{"screens":[]}' > "$root_b/$screen_manifest_rel"
  root_c="$tmp/case5-c-html-exists"; mkdir -p "$root_c/$(dirname "$screen_glob")"
  echo '<html></html>' > "$root_c/$screen_glob"

  # resolve_state()を直接呼ぶ(kindはASCIIのため、この環境のawk/grepが多バイト文字列の
  # 完全一致で誤マッチする問題を回避できる。build_rows()+awk文字列比較は使わない)。
  local layout_json_a layout_json_b layout_json_c
  layout_json_a="$(resolve_output_layout "$root_a")"
  layout_json_b="$(resolve_output_layout "$root_b")"
  layout_json_c="$(resolve_output_layout "$root_c")"
  local out_a out_b out_c
  out_a="$(resolve_state "$root_a" "$screen_glob" "screen" "$inventory_def" "$layout_json_a" '[]' | cut -f1)"
  out_b="$(resolve_state "$root_b" "$screen_glob" "screen" "$inventory_def" "$layout_json_b" '[]' | cut -f1)"
  out_c="$(resolve_state "$root_c" "$screen_glob" "screen" "$inventory_def" "$layout_json_c" '[]' | cut -f1)"

  if [ "$out_a" = "未生成" ] && [ "$out_b" = "未生成" ] && [ "$out_c" = "出力あり" ]; then
    echo "  [PASS] ケース5: 宣言なし0件を対象なしへ倒さず、HTML実在を出力ありと判定する"
  else
    echo "  [FAIL] ケース5: 状態が入力に追従しない(a=${out_a:-なし} b=${out_b:-なし} c=${out_c:-なし}、期待=未生成/対象なし/出力あり)" >&2
    rc=1
  fi

  # ケース6: test-portal-conventions.sh が不合格0件で通る(HTML側のみ)
  local conv_script conv_log conv_fail
  conv_script="$SCRIPT_DIR/tests/test-portal-conventions.sh"
  conv_log="$tmp/conventions.log"
  bash "$conv_script" "$html_out" >"$conv_log" 2>&1 || true
  conv_fail="$(grep -c '^  FAIL:' "$conv_log" || true)"
  if [ "$conv_fail" -eq 0 ]; then
    echo "  [PASS] ケース6: test-portal-conventions.sh が不合格0件で通る"
  else
    echo "  [FAIL] ケース6: test-portal-conventions.sh が${conv_fail}件不合格" >&2
    grep '^  FAIL:' "$conv_log" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース7: 定義からkindを1件削除するとカタログとの被覆不一致でERROR終了する
  local inventory_missing bad_rc
  inventory_missing="$tmp/inventory-missing-kind.json"
  jq '.items |= (.[1:])' "$inventory_def" > "$inventory_missing"
  bad_rc=0
  bash "$script_path" "$out_root" --deliverable-inventory "$inventory_missing" >/dev/null 2>&1 || bad_rc=$?
  if [ "$bad_rc" -ne 0 ]; then
    echo "  [PASS] ケース7: 定義のkind欠落をカタログとの被覆検査で検出しエラー終了する"
  else
    echo "  [FAIL] ケース7: kind欠落を検出できない(rc=${bad_rc})" >&2
    rc=1
  fi

  # ケース13: 旧形式で定義に無い出力先を渡すと、ファイルを作らず異常終了する
  local undefined_html undefined_md case13_rc
  undefined_html="$tmp/undefined/納品物一覧.html"
  undefined_md="$tmp/undefined/納品物一覧.md"
  case13_rc=0
  bash "$script_path" "$out_root" "$undefined_html" "$undefined_md" >/dev/null 2>&1 || case13_rc=$?
  if [ "$case13_rc" -ne 0 ] && [ ! -e "$undefined_html" ] && [ ! -e "$undefined_md" ]; then
    echo "  [PASS] ケース13: 定義に無い出力先引数を拒否し、生成物を作らない"
  else
    echo "  [FAIL] ケース13: 定義に無い出力先引数を拒否できない(rc=${case13_rc})" >&2
    rc=1
  fi

  # ケース14: 本項目で対象とした全生成物の置き場が定義されている
  local required_layout_keys missing_layout_keys
  required_layout_keys='["deliverableInventoryHtml","deliverableInventoryMarkdown","permissionFunctionMatrixHtml","platformDesignHtml","commonDesignHtml","dataDesignHtml","messageDesignHtml","uiCommonDesignHtml"]'
  missing_layout_keys="$(printf '%s' "$layout_json" | jq -r --argjson keys "$required_layout_keys" '$keys[] as $key | select((.layout[$key] | type) != "string") | $key')"
  if [ -z "$missing_layout_keys" ]; then
    echo "  [PASS] ケース14: 納品物一覧2形式・機能別対応表・共通設計文書5形式の出力先が定義されている"
  else
    echo "  [FAIL] ケース14: 出力先の定義が不足している($missing_layout_keys)" >&2
    rc=1
  fi

  # ケース15: 旧3引数形式でも、定義どおりの2出力先なら受け付ける
  local legacy_root legacy_layout legacy_html legacy_md case15_rc
  legacy_root="$tmp/legacy-defined-output"; mkdir -p "$legacy_root"
  legacy_layout="$(resolve_output_layout "$legacy_root")"
  legacy_html="$legacy_root/$(output_layout_get "$legacy_layout" "deliverableInventoryHtml")"
  legacy_md="$legacy_root/$(output_layout_get "$legacy_layout" "deliverableInventoryMarkdown")"
  case15_rc=0
  bash "$script_path" "$legacy_root" "$legacy_html" "$legacy_md" --generated-at "2026-01-01T00:00:00Z" >/dev/null 2>&1 || case15_rc=$?
  if [ "$case15_rc" -eq 0 ] && [ -f "$legacy_html" ] && [ -f "$legacy_md" ]; then
    echo "  [PASS] ケース15: 定義どおりの旧3引数形式は互換経路で生成できる"
  else
    echo "  [FAIL] ケース15: 定義どおりの旧3引数形式を受け付けられない(rc=${case15_rc})" >&2
    rc=1
  fi

  # ケース8: 0件でないマニフェストを実ファイル無しで判定すると、対象なしではなく
  #   不整合(未生成+理由に「不整合」)として報告される
  local root_d layout_json_d out_d_sr out_d reason_d
  root_d="$tmp/case8-nonzero-manifest"; mkdir -p "$root_d/$(dirname "$screen_manifest_rel")"
  echo '{"screens":[{"id":"s1"},{"id":"s2"}]}' > "$root_d/$screen_manifest_rel"
  layout_json_d="$(resolve_output_layout "$root_d")"
  out_d_sr="$(resolve_state "$root_d" "$screen_glob" "screen" "$inventory_def" "$layout_json_d" '[]')"
  out_d="$(printf '%s' "$out_d_sr" | cut -f1)"
  reason_d="$(printf '%s' "$out_d_sr" | cut -f2)"
  if [ "$out_d" = "未生成" ] && printf '%s' "$reason_d" | grep -q '不整合'; then
    echo "  [PASS] ケース8: 0件でないマニフェスト+実ファイル無しは不整合として報告される(状態=${out_d})"
  else
    echo "  [FAIL] ケース8: 不整合として報告されない(状態=${out_d:-なし}, 理由=${reason_d:-なし})" >&2
    rc=1
  fi

  # ケース9: 0件でも対象外宣言がなければ未生成と判定される
  local out_e_sr out_e reason_e
  out_e_sr="$(resolve_state "$root_b" "$screen_glob" "screen" "$inventory_def" "$layout_json_b" '[]')"
  out_e="$(printf '%s' "$out_e_sr" | cut -f1)"
  reason_e="$(printf '%s' "$out_e_sr" | cut -f2)"
  if [ "$out_e" = "未生成" ] && printf '%s' "$reason_e" | grep -q '対象外宣言がない'; then
    echo "  [PASS] ケース9: 宣言なしの0件画面マニフェストは未生成と判定される"
  else
    echo "  [FAIL] ケース9: 0件のマニフェストの判定が変わった(状態=${out_e:-なし}, 理由=${reason_e:-なし})" >&2
    rc=1
  fi

  # ケース10: 件数の取得に失敗した場合、既定値0へ倒さずエラーとして報告される
  local root_f layout_json_f case10_out case10_err case10_rc
  root_f="$tmp/case10-bad-manifest"; mkdir -p "$root_f/$(dirname "$screen_manifest_rel")"
  echo 'THIS IS NOT JSON' > "$root_f/$screen_manifest_rel"
  layout_json_f="$(resolve_output_layout "$root_f")"
  case10_err="$tmp/case10.err"
  case10_rc=0
  if case10_out="$(resolve_state "$root_f" "$screen_glob" "screen" "$inventory_def" "$layout_json_f" '[]' 2>"$case10_err")"; then
    case10_rc=0
  else
    case10_rc=1
  fi
  if [ "$case10_rc" -ne 0 ] && [ -s "$case10_err" ] && grep -q 'ERROR' "$case10_err" && [ "$(printf '%s' "$case10_out" | cut -f1)" != "対象なし" ]; then
    echo "  [PASS] ケース10: 件数取得の失敗が既定値0へ倒れず、ERRORとして報告される"
  else
    echo "  [FAIL] ケース10: 件数取得の失敗がエラー報告されない(rc=${case10_rc}, err=$(cat "$case10_err" 2>/dev/null))" >&2
    rc=1
  fi

  # ケース11・12: ある種別(screen)を対象外として記録すると、依存する成果物
  #   (confirmation-survey)が対象なしと判定される。除外の記録が無ければ従来どおり未生成
  local confirmation_glob root_g layout_json_g excluded_json_g
  local out_h_sr out_h out_i_sr out_i
  confirmation_glob="$(jq -r '.categories[].blueprints[] | select(.kind=="confirmation-survey") | .discovery.glob' "$catalog")"
  root_g="$tmp/case11-dependent-kind"; mkdir -p "$root_g"
  layout_json_g="$(resolve_output_layout "$root_g")"
  excluded_json_g='[{"kind":"screen","label":"画面","reason":"画面を持たないバックエンドのみのプロジェクトのため画面が存在しない"}]'

  out_h_sr="$(resolve_state "$root_g" "$confirmation_glob" "confirmation-survey" "$inventory_def" "$layout_json_g" "$excluded_json_g")"
  out_h="$(printf '%s' "$out_h_sr" | cut -f1)"
  if [ "$out_h" = "対象なし" ]; then
    echo "  [PASS] ケース11: 対象外種別(screen)に依存するconfirmation-surveyが対象なしと判定される"
  else
    echo "  [FAIL] ケース11: 依存先が対象外でも対象なしにならない(状態=${out_h:-なし})" >&2
    rc=1
  fi

  out_i_sr="$(resolve_state "$root_g" "$confirmation_glob" "confirmation-survey" "$inventory_def" "$layout_json_g" '[]')"
  out_i="$(printf '%s' "$out_i_sr" | cut -f1)"
  if [ "$out_i" = "未生成" ]; then
    echo "  [PASS] ケース12: 除外の記録が無ければconfirmation-surveyは従来どおり未生成と判定される"
  else
    echo "  [FAIL] ケース12: 除外の記録が無いのに判定が変わった(状態=${out_i:-なし})" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ $# -lt 1 ]; then
    echo "$USAGE" >&2
    exit 1
  fi

  local output_root="$1"
  shift
  run_build "$output_root" "$@"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
