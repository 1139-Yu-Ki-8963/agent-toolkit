#!/usr/bin/env bash
# check-coverage.sh — 網羅（第3層の判定基準の1つ）の判定
#
# 目的:
#   このリポジトリ自身の検証設計文書（配布対象外）「網羅の分母」節が定める成果物一式が、
#   生成物のディレクトリにすべて存在するかを突き合わせる。分母は次の3ファイルから
#   実行時に動的に読み取り、本スクリプトへ数値をハードコードしない。
#     - delivery-payload/references/portal-catalog.json   （一覧・マトリクス・デザインツールの glob）
#     - delivery-payload/references/output-layout.json     （画面マニフェスト2件・画面一覧htmlの配置）
#     - delivery-payload/references/rule-taxonomy.json      （規約の親7・子27の階層）
#
# 既知の乖離（未対応事項として報告する）:
#   verification-loop/設計.md の「網羅の分母」節は規約の階層を55件（親7+子27+子27=61の
#   誤算、または子24件だった当時の値の取り残し）、総分母を76件と記す。本スクリプトは
#   その場しのぎで55/76に合わせるのではなく、rule-taxonomy.json の実データ（本稿時点
#   で子27件）から動的に61件（現在は合計83件）を導出する。設計文書側の数値更新は本スクリプト
#   の担当外（Read専用ファイル）のため、乖離はそのまま報告する。
#
# Usage:
#   check-coverage.sh --output <生成物のディレクトリ> [--repo <リポジトリのパス>]
#   check-coverage.sh --self-test
#
# オプション:
#   --output <path>  検証対象の生成物ディレクトリ（<output_dir>/project-portal/index.html、
#                     <output_dir>/docs/...、<output_dir>/project-portal/... を持つ想定）
#   --repo <path>     分母の定義元（3ファイル）を読むリポジトリのパス。省略時は
#                      このスクリプトの位置から3階層上（generation-engine/scripts/verification
#                      → generation-engine/scripts → shared → リポジトリルート）
#   --self-test       本スクリプト自身の自己テストを実行する
#
# 出力（通常実行時）:
#   成果物ごとに1行: [OK|MISSING] <成果物の名前> — <期待するパス>
#   末尾に集計行: 分母 <T> 件 / 存在 <P> 件 / 欠落 <M> 件
#
# 終了コード: 欠落が1件でもあれば1。分母が0件、または引数不正・依存コマンド不在なら
#   エラーメッセージを stderr へ出し1で終える。すべて存在すれば0。
#
# 保守責任者: 人手（ユーザー）。分母の追加・除外を変える場合は
#   このリポジトリ自身の検証設計文書（配布対象外）の「網羅の分母」節と本ファイルと
#   self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 分母の組み立て
# ---------------------------------------------------------------------------

# list カテゴリのうち、画面本体・画面遷移図・用語辞書・ER図・状態遷移図は
# 「網羅の分母」節が別枠（画面一覧カテゴリ）または除外対象（分母に含めない成果物）
# として扱うため、本カテゴリの9件からは除く。
LIST_EXCLUDE_JSON='["screen","screen-transition","semantic-glossary","er-diagram","entity-state"]'

# repo: リポジトリのパス
# 1行1件、"<成果物の名前>\t<output_dirからの相対パス>" 形式で標準出力へ返す。
build_denominator() {
  local repo="$1" output_dir="$2"
  local catalog_json taxonomy_json layout_sh layout_json

  catalog_json="${repo}/delivery-payload/references/portal-catalog.json"
  taxonomy_json="${repo}/delivery-payload/references/rule-taxonomy.json"
  layout_sh="${repo}/generation-engine/scripts/output-layout.sh"

  if [ ! -f "$catalog_json" ]; then
    echo "ERROR: portal-catalog.json が見つかりません: ${catalog_json}" >&2
    return 1
  fi
  if [ ! -f "$taxonomy_json" ]; then
    echo "ERROR: rule-taxonomy.json が見つかりません: ${taxonomy_json}" >&2
    return 1
  fi
  if [ ! -f "$layout_sh" ]; then
    echo "ERROR: output-layout.sh が見つかりません: ${layout_sh}" >&2
    return 1
  fi

  # shellcheck source=/dev/null
  . "$layout_sh"
  layout_json="$(resolve_output_layout "$output_dir")" || return 1

  local screen_manifest screen_manifest_ext screen_list_html rules_root
  screen_manifest="$(output_layout_get "$layout_json" screenManifest)" || return 1
  screen_manifest_ext="$(output_layout_get "$layout_json" screenManifestExt)" || return 1
  screen_list_html="$(output_layout_get "$layout_json" screenListHtml)" || return 1
  rules_root="$(output_layout_get "$layout_json" rulesRoot)" || return 1

  # --- 1) 画面一覧のマニフェストと一覧（3） ---
  printf '画面マニフェストraw正本\t%s\n' "$screen_manifest"
  printf '画面拡張マニフェスト\t%s\n' "$screen_manifest_ext"
  printf '画面一覧\t%s\n' "$screen_list_html"

  # --- 2) 種別別の一覧（カタログから動的に導出） ---
  jq -r --argjson exclude "$LIST_EXCLUDE_JSON" '
    .categories[] | select(.key=="list") | .blueprints[]
    | select(.kind as $k | ($exclude | index($k) | not))
    | .label + "\t" + .discovery.glob
  ' "$catalog_json"

  # --- 3) マトリクスと対応表（5） ---
  jq -r '
    .categories[] | select(.key=="cross") | .blueprints[]
    | .label + "\t" + .discovery.glob
  ' "$catalog_json"

  # --- 4) 規約の階層（親7×parent.yml + 子27×rule.md + 子27×design-notes.md） ---
  local parent_lines pline
  parent_lines="$(jq -c '.parents[]' "$taxonomy_json")"
  while IFS= read -r pline; do
    [ -n "$pline" ] || continue
    local pkey ptitle
    pkey="$(printf '%s' "$pline" | jq -r '.key')"
    ptitle="$(printf '%s' "$pline" | jq -r '.title')"
    printf '規約-%s（親定義）\t%s/%s/parent.yml\n' "$ptitle" "$rules_root" "$pkey"

    local child_lines cline
    child_lines="$(printf '%s' "$pline" | jq -c '.children[]')"
    while IFS= read -r cline; do
      [ -n "$cline" ] || continue
      local ckey ctitle
      ckey="$(printf '%s' "$cline" | jq -r '.key')"
      ctitle="$(printf '%s' "$cline" | jq -r '.title')"
      printf '規約-%s（本文）\t%s/%s/%s/rule.md\n' "$ctitle" "$rules_root" "$pkey" "$ckey"
      printf '規約-%s（設計判断）\t%s/%s/%s/design-notes.md\n' "$ctitle" "$rules_root" "$pkey" "$ckey"
    done <<EOF
$child_lines
EOF
  done <<EOF
$parent_lines
EOF

  # --- 5) デザインシステムと棚卸しとアイコン（3） ---
  jq -r '
    .categories[] | select(.key=="design-tools") | .blueprints[]
    | .label + "\t" + .discovery.glob
  ' "$catalog_json"

  # --- 6) ポータルのトップページ（1） ---
  printf 'ポータルのトップページ\tproject-portal/index.html\n'

  return 0
}

# ---------------------------------------------------------------------------
# 判定本体
# ---------------------------------------------------------------------------

# coverage_check <repo> <output_dir>
# 標準出力へ判定結果を書き、欠落が1件でもあれば1を返す。
coverage_check() {
  local repo="$1" output_dir="$2"
  local denom
  denom="$(build_denominator "$repo" "$output_dir")" || return 1

  if [ -z "$denom" ]; then
    echo "ERROR: 分母が0件です" >&2
    return 1
  fi

  local total=0 present=0 missing=0
  local line label relpath
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    label="${line%%$'\t'*}"
    relpath="${line#*$'\t'}"
    total=$((total + 1))
    if [ -e "${output_dir}/${relpath}" ]; then
      present=$((present + 1))
      printf '[OK] %s — %s\n' "$label" "${output_dir}/${relpath}"
    else
      missing=$((missing + 1))
      printf '[MISSING] %s — %s\n' "$label" "${output_dir}/${relpath}"
    fi
  done <<EOF
$denom
EOF

  printf '分母 %s 件 / 存在 %s 件 / 欠落 %s 件\n' "$total" "$present" "$missing"

  [ "$missing" -eq 0 ]
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

_self_test() {
  local repo run=0 ok=0 ng=0
  repo="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

  _case_pass() { run=$((run + 1)); ok=$((ok + 1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run + 1)); ng=$((ng + 1)); echo "[FAIL] $1 — $2" >&2; }

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-coverage-self-test.XXXXXX")" || {
    echo "ERROR: 一時ディレクトリを作成できません" >&2
    exit 1
  }
  trap 'rm -rf "$tmp"' EXIT

  # 規約-親子読取
  local parent_count child_count
  parent_count="$(jq '.parents | length' "${repo}/delivery-payload/references/rule-taxonomy.json")"
  child_count="$(jq '[.parents[].children[]] | length' "${repo}/delivery-payload/references/rule-taxonomy.json")"
  if [ "$parent_count" -eq 7 ] && [ "$child_count" -eq 27 ]; then
    _case_pass "規約-親子読取" "rule-taxonomy.json から親7・子27を読み取った"
  else
    _case_fail "規約-親子読取" "親${parent_count}件・子${child_count}件（期待: 親7・子27）"
  fi

  # 分母-件数（動的導出との内部整合性を検査する。verification-loop/設計.md記載の
  # 55/76は現行のrule-taxonomy.json（子27件）とは整合しない既知の乖離であり、
  # 本テストは「今のrule-taxonomy.jsonから導いた総数」と「build_denominatorの
  # 出力件数」が一致することを検査する）
  local dummy_out="${tmp}/dummy-output"
  local denom_all total_actual rules_total expected_total
  denom_all="$(build_denominator "$repo" "$dummy_out")"
  total_actual="$(printf '%s\n' "$denom_all" | grep -c .)"
  rules_total=$((parent_count + child_count * 2))
  local list_total
  list_total="$(jq --argjson exclude "$LIST_EXCLUDE_JSON" '[.categories[] | select(.key=="list") | .blueprints[] | select(.kind as $k | ($exclude | index($k) | not))] | length' "${repo}/delivery-payload/references/portal-catalog.json")"
  expected_total=$((3 + list_total + 5 + rules_total + 3 + 1))
  if [ "$total_actual" -eq "$expected_total" ]; then
    _case_pass "分母-件数" "分母の総件数が ${expected_total} 件（3+${list_total}+5+${rules_total}+3+1。設計文書記載の76とは既知の乖離があり本ケースは動的導出の内部整合性を検査する）"
  else
    _case_fail "分母-件数" "分母の総件数が ${total_actual} 件（期待 ${expected_total} 件）"
  fi

  # 検出-存在 / 検出-欠落 / 終了コード-欠落時
  local out_partial="${tmp}/out-partial"
  mkdir -p "$out_partial"
  local half create_n=0 i=0
  half=$((total_actual / 2))
  local pline plabel prel
  while IFS= read -r pline; do
    [ -n "$pline" ] || continue
    i=$((i + 1))
    [ "$i" -gt "$half" ] && continue
    prel="${pline#*$'\t'}"
    mkdir -p "$(dirname "${out_partial}/${prel}")"
    : > "${out_partial}/${prel}"
    create_n=$((create_n + 1))
  done <<EOF
$denom_all
EOF

  local partial_out partial_rc
  partial_out="$(coverage_check "$repo" "$out_partial")"
  partial_rc=$?

  local ok_lines missing_lines
  ok_lines="$(printf '%s\n' "$partial_out" | grep -cE '^\[OK\]')"
  missing_lines="$(printf '%s\n' "$partial_out" | grep -cE '^\[MISSING\]')"

  if [ "$ok_lines" -eq "$create_n" ]; then
    _case_pass "検出-存在" "作成した ${create_n} 件が [OK] として数えられた"
  else
    _case_fail "検出-存在" "[OK] ${ok_lines} 件（期待 ${create_n} 件）"
  fi

  if [ "$missing_lines" -eq $((total_actual - create_n)) ]; then
    _case_pass "検出-欠落" "未作成の $((total_actual - create_n)) 件が [MISSING] として数えられた"
  else
    _case_fail "検出-欠落" "[MISSING] ${missing_lines} 件（期待 $((total_actual - create_n)) 件）"
  fi

  if [ "$partial_rc" -eq 1 ]; then
    _case_pass "終了コード-欠落時" "欠落がある場合に終了コード1を返した"
  else
    _case_fail "終了コード-欠落時" "終了コードが${partial_rc}（期待1）"
  fi

  # 終了コード-完全時
  local out_full="${tmp}/out-full"
  mkdir -p "$out_full"
  while IFS= read -r pline; do
    [ -n "$pline" ] || continue
    prel="${pline#*$'\t'}"
    mkdir -p "$(dirname "${out_full}/${prel}")"
    : > "${out_full}/${prel}"
  done <<EOF
$denom_all
EOF
  local full_out full_rc
  full_out="$(coverage_check "$repo" "$out_full")"
  full_rc=$?
  if [ "$full_rc" -eq 0 ] && printf '%s\n' "$full_out" | grep -qE '欠落 0 件$'; then
    _case_pass "終了コード-完全時" "欠落0件で終了コード0を返した"
  else
    _case_fail "終了コード-完全時" "rc=${full_rc}（期待0）、または欠落0件の集計行が無い"
  fi

  # 期待-トップページ配置
  if printf '%s\n' "$denom_all" | grep -Fq "$(printf 'ポータルのトップページ\tproject-portal/index.html')"; then
    _case_pass "期待-トップページ配置" "ポータルのトップページの期待パスが project-portal/index.html である"
  else
    _case_fail "期待-トップページ配置" "ポータルのトップページの期待パスが project-portal/index.html になっていない"
  fi

  rm -rf "$tmp"
  trap - EXIT

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOS'
使い方: check-coverage.sh --output <生成物のディレクトリ> [--repo <リポジトリのパス>]
        check-coverage.sh --self-test
EOS
}

main() {
  local output_dir="" repo="" self_test_mode=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        output_dir="${2:-}"
        shift 2
        ;;
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      --self-test)
        self_test_mode=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "不明な引数: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ "$self_test_mode" -eq 1 ]; then
    _self_test
    exit $?
  fi

  if [ -z "$output_dir" ]; then
    echo "ERROR: --output は必須です" >&2
    usage >&2
    exit 1
  fi

  if [ -z "$repo" ]; then
    repo="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  fi

  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq が必要です" >&2; exit 1; }

  coverage_check "$repo" "$output_dir"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
