#!/usr/bin/env bash
# check-depends-on-kind.sh — 画面に依存する納品物が dependsOnKind=screen を
# 網羅して宣言しているかを見る（改善課題1-253）。
#
# 背景:
#   delivery-payload/references/deliverable-inventory.json の各項目は、
#   dependsOnKind へ依存先の種別を宣言すると、依存先が対象外（画面ゼロ件
#   など）と記録された対象で自動的に「対象なし」と判定される
#   （generation-engine/scripts/build-deliverable-inventory.sh の
#   resolve_state を参照）。この宣言が漏れると、画面が無いから作れない
#   納品物が「未生成（作り忘れ）」のまま永久に判定される。
#
# 洗い出しの方法（実測 2026-08-24）:
#   deliverable-inventory.json に既に dependsOnKind=screen を宣言する8件
#   （screen-transition・test-viewpoint-list・test-case-list・
#   permission-screen・permission-function・crud・traceability・
#   confirmation-survey。いずれも screen のマニフェスト以外の、画面固有の
#   成果物）に、design-system・component-inventory・icon-catalog の3件を
#   加えた11件を「画面に依存する納品物」とする。
#
#   後者3件は、生成元スキル（generating-design-system-for-reverse-docs /
#   generating-component-inventory-for-reverse-docs /
#   generating-icon-catalog-for-reverse-docs）の SKILL.md「いつ使わないか」
#   節を実測すると、screen のマニフェストや一覧そのものを直接には要求せず、
#   共通設計文書（DESIGN.md）・画面部品のファイル（.tsx/.jsx/.vue）・
#   アイコン参照という、UI が存在することを前提にした証拠に依存している。
#   dependsOnKind の語彙は6種別（screen/api/table/batch/report/external/
#   feature）のいずれかにしか依存を宣言できず、「UI が存在する」を表す
#   種別が無い。画面がゼロ件と記録された対象（excluded-kinds.json で
#   screen が対象外にされた対象）は、UI そのものを持たない可能性が高く、
#   この3件の証拠も存在しないと見込まれるため、現行の語彙のうち最も近い
#   代理として screen を採用する。
#
# 使い方:
#   check-depends-on-kind.sh                      既定の定義ファイルで網羅を判定する
#   check-depends-on-kind.sh --inventory <file>    定義ファイルを差し替えて判定する（self-test用）
#   check-depends-on-kind.sh --check-resolution    画面ゼロ件・画面ありの2つの入力を実際に生成し、
#                                                   判定結果が想定どおりかを確かめる（重い処理）
#   check-depends-on-kind.sh --self-test           自己テスト
#
# 終了コード: 0=網羅している（または解決結果が想定どおり）。
#             1=不合格（宣言の欠落、または解決結果が想定と異なる）。
#             2=判定不能（定義ファイル不在・JSON不正・一時領域を作れない等）。
#
# 設計判断: .claude/rules/always/tasks/instruction-format/rule.md の
#   「設計判断」節「check-depends-on-kind.sh」を参照。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_INVENTORY="$REPO_ROOT/delivery-payload/references/deliverable-inventory.json"
CATALOG="$REPO_ROOT/delivery-payload/references/portal-catalog.json"
BUILD_SCRIPT="$REPO_ROOT/generation-engine/scripts/build-deliverable-inventory.sh"
OUTPUT_LAYOUT_SCRIPT="$REPO_ROOT/generation-engine/scripts/output-layout.sh"
NO_SCREEN_EXCLUDED="$REPO_ROOT/generation-engine/samples-no-screen/一覧/excluded-kinds.json"

# 画面が無いと成り立たない納品物の一覧（導出方法は冒頭コメントを参照）。
SCREEN_DEPENDENT_KINDS=(
  screen-transition
  test-viewpoint-list
  test-case-list
  permission-screen
  permission-function
  crud
  traceability
  confirmation-survey
  design-system
  component-inventory
  icon-catalog
)

usage() {
  cat >&2 <<'USAGE'
Usage: check-depends-on-kind.sh [--inventory <file>]
       check-depends-on-kind.sh --check-resolution
       check-depends-on-kind.sh --self-test
USAGE
}

# run_coverage: 指定した定義ファイルで SCREEN_DEPENDENT_KINDS が全件
# dependsOnKind=="screen" を持つかを見る。
run_coverage() {
  local inventory="$1"
  if [ ! -f "$inventory" ]; then
    echo "[UNKNOWN] 納品物の定義ファイルが見つからないため判定できません: ${inventory}（操作: run_coverage / 想定原因: パス指定の誤り、またはファイルの未配置）" >&2
    return 2
  fi
  if ! jq -e '.items | type == "array"' "$inventory" >/dev/null 2>&1; then
    echo "[UNKNOWN] 納品物の定義ファイルをJSONとして読めないため判定できません: ${inventory}（操作: run_coverage / 想定原因: JSON構文の破損）" >&2
    return 2
  fi

  local missing="" kind has
  for kind in "${SCREEN_DEPENDENT_KINDS[@]}"; do
    has="$(jq -r --arg k "$kind" '[.items[] | select(.kind==$k) | select(.dependsOnKind=="screen")] | length' "$inventory")"
    if [ "$has" != "1" ]; then
      missing="${missing} ${kind}"
    fi
  done

  if [ -n "$missing" ]; then
    echo "[FAIL] dependsOnKind=screen が無い、または重複している納品物:${missing}" >&2
    return 1
  fi

  echo "[PASS] 画面に依存する納品物 ${#SCREEN_DEPENDENT_KINDS[@]} 件すべてが dependsOnKind=screen を宣言している"
  return 0
}

# _label_for_kind: portal-catalog.json から表示名（一覧の行を特定するのに使う）を引く。
_label_for_kind() {
  jq -r --arg k "$1" '.categories[].blueprints[] | select(.kind==$k) | .label' "$CATALOG"
}

# _resolve_catalog_glob: カタログの生globを、出力配置の定義(layout_json)に
# 従って実際の出力先へ変換する。build-deliverable-inventory.sh の
# resolve_catalog_glob と同じ変換式を使う（重複だが、対象スクリプトを
# 安全に source する手段が無いための実装判断。理由は
# .claude/rules/always/design-record/implementation-decision/rule.md の
# 対象。build-deliverable-inventory.sh の SCRIPT_DIR は $0 を使っており、
# source した場合に呼び出し元のパスを見てしまい壊れる）。
_resolve_catalog_glob() {
  local layout_json="$1" raw_glob="$2"
  jq -r --arg glob "$raw_glob" --argjson layout "$layout_json" '
    reduce ((.defaultRoots // {}) | to_entries[]) as $root ($glob;
      if . == $root.value then ($layout.layout[$root.key] // .)
      elif startswith($root.value + "/") then (($layout.layout[$root.key] // $root.value) + .[($root.value | length):])
      else . end
    )
  ' "$CATALOG"
}

# run_check_resolution: 画面ゼロ件の入力・画面ありの入力それぞれで、実際に
# build-deliverable-inventory.sh を走らせ、design-system・component-inventory・
# icon-catalog の3件が想定どおりの状態（対象なし／出力あり）になるかを見る。
#
# 画面ありの回帰確認は generation-engine/samples/ を複製せず、実効globの
# 位置へ空のHTMLを置いた最小のフィクスチャで行う。samples/ 配下の該当3件は
# 出力先が英字ディレクトリ(project-portal/foundation)へ統一される前の構成
# (project-portal/基盤)のまま残っており、そのまま使うと本項目と無関係な
# 理由（配置の食い違い）で「未生成」になり、判定の意味が変わってしまう
# ため使わない。
run_check_resolution() {
  if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "[UNKNOWN] 生成スクリプトが見つからないため判定できません: ${BUILD_SCRIPT}" >&2
    return 2
  fi
  if [ ! -f "$NO_SCREEN_EXCLUDED" ]; then
    echo "[UNKNOWN] 画面ゼロ件の試験用入力が見つからないため判定できません: ${NO_SCREEN_EXCLUDED}" >&2
    return 2
  fi
  if [ ! -f "$OUTPUT_LAYOUT_SCRIPT" ]; then
    echo "[UNKNOWN] 出力配置の解決スクリプトが見つからないため判定できません: ${OUTPUT_LAYOUT_SCRIPT}" >&2
    return 2
  fi
  # shellcheck source=../../generation-engine/scripts/output-layout.sh
  . "$OUTPUT_LAYOUT_SCRIPT"

  local fail=0

  # --- 画面ゼロ件: 3件が「対象なし」になること ---
  local tmp_noscreen
  if ! tmp_noscreen="$(mktemp -d "${TMPDIR:-/tmp}/check-depends-on-kind.XXXXXX" 2>/dev/null)" || [ -z "$tmp_noscreen" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  mkdir -p "$tmp_noscreen/docs/scope-and-progress"
  cp "$NO_SCREEN_EXCLUDED" "$tmp_noscreen/docs/scope-and-progress/excluded-kinds.json"

  if ! bash "$BUILD_SCRIPT" "$tmp_noscreen" >"$tmp_noscreen/build.log" 2>&1; then
    echo "[FAIL] 画面ゼロ件の試験用入力で納品物一覧の生成が失敗した" >&2
    cat "$tmp_noscreen/build.log" >&2
    fail=1
  else
    local md_noscreen="$tmp_noscreen/docs/納品物一覧.md"
    local kind label
    for kind in design-system component-inventory icon-catalog; do
      label="$(_label_for_kind "$kind")"
      if ! grep -F "| ${label} |" "$md_noscreen" | grep -q '対象なし'; then
        echo "[FAIL] 画面ゼロ件の入力で ${label}（${kind}）が「対象なし」と判定されなかった" >&2
        fail=1
      fi
    done
  fi
  rm -rf "$tmp_noscreen"

  # --- 画面あり（回帰）: HTMLが実在すれば従来どおり「出力あり」になること ---
  local tmp_present
  if ! tmp_present="$(mktemp -d "${TMPDIR:-/tmp}/check-depends-on-kind.XXXXXX" 2>/dev/null)" || [ -z "$tmp_present" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi

  local layout_json
  if ! layout_json="$(resolve_output_layout "$tmp_present" 2>/dev/null)"; then
    echo "[UNKNOWN] 出力配置の定義を解決できないため判定できません" >&2
    rm -rf "$tmp_present"
    return 2
  fi

  local kind glob effective_glob label
  for kind in design-system component-inventory icon-catalog; do
    glob="$(jq -r --arg k "$kind" '.categories[].blueprints[] | select(.kind==$k) | .discovery.glob' "$CATALOG")"
    effective_glob="$(_resolve_catalog_glob "$layout_json" "$glob")"
    mkdir -p "$tmp_present/$(dirname "$effective_glob")"
    : > "$tmp_present/$effective_glob"
  done

  if ! bash "$BUILD_SCRIPT" "$tmp_present" >"$tmp_present/build.log" 2>&1; then
    echo "[FAIL] 画面ありの回帰用入力で納品物一覧の生成が失敗した" >&2
    cat "$tmp_present/build.log" >&2
    fail=1
  else
    local md_present="$tmp_present/docs/納品物一覧.md"
    for kind in design-system component-inventory icon-catalog; do
      label="$(_label_for_kind "$kind")"
      if ! grep -F "| ${label} |" "$md_present" | grep -q '出力あり'; then
        echo "[FAIL] 画面ありの入力で ${label}（${kind}）が従来どおり判定されなかった" >&2
        fail=1
      fi
    done
  fi
  rm -rf "$tmp_present"

  if [ "$fail" -ne 0 ]; then
    return 1
  fi
  echo "[PASS] 画面ゼロ件では対象なし、画面ありでは従来どおりの判定を確認した"
  return 0
}

run_self_test() {
  local total=0 fail=0

  # ケース1: 実物の定義ファイルで11件すべてに宣言がある
  total=$((total + 1))
  if run_coverage "$DEFAULT_INVENTORY" >/dev/null 2>&1; then
    echo "  [PASS] ケース1: 実物の定義ファイルで11件すべてに宣言がある"
  else
    echo "  [FAIL] ケース1: 実物の定義ファイルで宣言が欠けている" >&2
    fail=$((fail + 1))
  fi

  local tmp
  if ! tmp="$(mktemp "${TMPDIR:-/tmp}/check-depends-on-kind.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ファイルを作れないため自己テストの一部を判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -f "$tmp"' RETURN

  # ケース2: dependsOnKindを1件意図的に外すと不合格になる（検収方法4）。
  # 「不合格」の判定はrc==1（宣言の欠落）に限定する。rc==2（判定不能）を
  # 合格扱いにすると、jqの変換そのものが失敗して$tmpが空になった場合にも
  # ケース2がPASSしてしまい、本来テストしたい経路（宣言の欠落を検出する）
  # を確かめないまま通ってしまう
  total=$((total + 1))
  local rc2=0
  if ! jq '(.items[] | select(.kind=="design-system")) |= del(.dependsOnKind)' "$DEFAULT_INVENTORY" > "$tmp" 2>/dev/null; then
    echo "  [FAIL] ケース2: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  else
    run_coverage "$tmp" >/dev/null 2>&1
    rc2=$?
    if [ "$rc2" -eq 1 ]; then
      echo "  [PASS] ケース2: dependsOnKindを意図的に外すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース2: dependsOnKindを外したときの終了コードが1でない(rc=${rc2})" >&2
      fail=$((fail + 1))
    fi
  fi

  # ケース3: 定義ファイルが存在しない場合は判定不能(UNKNOWN・終了コード2)
  total=$((total + 1))
  local rc3=0
  run_coverage "${tmp}.does-not-exist" >/dev/null 2>&1
  rc3=$?
  if [ "$rc3" -eq 2 ]; then
    echo "  [PASS] ケース3: 定義ファイルが無いと判定不能(終了コード2)になる"
  else
    echo "  [FAIL] ケース3: 定義ファイルが無いときの終了コードが2でない(rc=${rc3})" >&2
    fail=$((fail + 1))
  fi

  # ケース4: JSONとして壊れている場合も判定不能になる
  total=$((total + 1))
  printf 'THIS IS NOT JSON' > "$tmp"
  local rc4=0
  run_coverage "$tmp" >/dev/null 2>&1
  rc4=$?
  if [ "$rc4" -eq 2 ]; then
    echo "  [PASS] ケース4: 壊れたJSONでは判定不能(終了コード2)になる"
  else
    echo "  [FAIL] ケース4: 壊れたJSONのときの終了コードが2でない(rc=${rc4})" >&2
    fail=$((fail + 1))
  fi

  # ケース5: 全11件が揃った正常な入力では合格する（重複や誤字での過検出が無いことの確認）
  total=$((total + 1))
  cp "$DEFAULT_INVENTORY" "$tmp"
  if run_coverage "$tmp" >/dev/null 2>&1; then
    echo "  [PASS] ケース5: 全11件が揃った入力を複製しても合格する"
  else
    echo "  [FAIL] ケース5: 複製した正常な入力で不合格になった" >&2
    fail=$((fail + 1))
  fi

  echo "実行 ${total} 件 / 成功 $((total - fail)) 件 / 失敗 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main() {
  local inventory="$DEFAULT_INVENTORY"
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    --check-resolution)
      run_check_resolution
      exit $?
      ;;
    --inventory)
      inventory="${2:-}"
      if [ -z "$inventory" ]; then
        usage
        exit 2
      fi
      ;;
    "")
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  run_coverage "$inventory"
  exit $?
}

main "$@"
