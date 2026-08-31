#!/usr/bin/env bash
# check-depends-on-kind.sh — 他の種別に依存する納品物が、依存の集合宣言
# （requiresAllOf / requiresAnyOf）を漏れなく・想定どおりに持っているかを見る
# （改善課題1-253。画面なし・API のみの対象向けの設計で集合宣言へ改めた）。
#
# 背景:
#   delivery-payload/references/deliverable-inventory.json の各項目は、
#   requiresAllOf（列挙した種別が1つでも対象外なら「対象なし」）または
#   requiresAnyOf（列挙した種別がすべて対象外のときだけ「対象なし」）で
#   依存先の種別を宣言する。宣言は generation-engine/scripts/
#   build-deliverable-inventory.sh の resolve_dependency_absence が解決する。
#   宣言が漏れると、画面が無いから作れない納品物が「未生成（作り忘れ）」の
#   まま永久に判定される。逆に画面以外の種別で成立する納品物へ画面だけの
#   依存を書くと、画面を持たず API だけを持つ対象でその納品物が欠ける。
#   旧い単一値の dependsOnKind はどちらの誤りも表せなかったため、本検査は
#   集合宣言の形と中身の両方を見る。
#
# 期待する宣言（導出方法）:
#   画面だけに依存する7件（screen-transition・permission-screen・
#   design-system・component-inventory・icon-catalog、および共通文書の
#   common-design・ui-common-design。後者2件は generating-reverse-common-docs の
#   common-document-definitions.json が dependsOnKinds=["screen"] と宣言する）は
#   requiresAllOf=["screen"]。
#   API があれば成立する3件（crud・traceability・permission-function）は
#   requiresAnyOf=["api"]。どの設計単位でも成立する3件（test-viewpoint-list・
#   test-case-list・confirmation-survey）は requiresAnyOf=7種別。
#   導出の根拠は docs/design/画面なしAPIのみ対象の設計.md の 5.1 節。
#
# 使い方:
#   check-depends-on-kind.sh                      既定の定義ファイルで宣言の網羅と中身を判定する
#   check-depends-on-kind.sh --inventory <file>    定義ファイルを差し替えて判定する（self-test用）
#   check-depends-on-kind.sh --check-resolution    画面だけが対象外（API のみ）・全種別が対象外・
#                                                   画面ありの3つの入力を実際に生成し、判定結果が
#                                                   想定どおりかを確かめる（重い処理）
#   check-depends-on-kind.sh --self-test           自己テスト
#
# 終了コード: 0=網羅している（または解決結果が想定どおり）。
#             1=不合格（宣言の欠落・誤り、または解決結果が想定と異なる）。
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

ALL_KINDS_JSON='["screen","api","table","batch","report","external","feature"]'

# 期待する宣言の一覧。1行 = "<kind>\t<鍵>\t<種別のカンマ区切り>"
expected_declarations() {
  cat <<'EOS'
screen-transition	requiresAllOf	screen
permission-screen	requiresAllOf	screen
common-design	requiresAllOf	screen
ui-common-design	requiresAllOf	screen
design-system	requiresAllOf	screen
component-inventory	requiresAllOf	screen
icon-catalog	requiresAllOf	screen
crud	requiresAnyOf	api
traceability	requiresAnyOf	api
permission-function	requiresAnyOf	api
test-viewpoint-list	requiresAnyOf	screen,api,table,batch,report,external,feature
test-case-list	requiresAnyOf	screen,api,table,batch,report,external,feature
confirmation-survey	requiresAnyOf	screen,api,table,batch,report,external,feature
EOS
}

SCREEN_ONLY_KINDS="screen-transition permission-screen design-system component-inventory icon-catalog common-design ui-common-design"
API_OK_KINDS="crud traceability permission-function test-viewpoint-list test-case-list confirmation-survey"

usage() {
  cat >&2 <<'USAGE'
Usage: check-depends-on-kind.sh [--inventory <file>]
       check-depends-on-kind.sh --check-resolution
       check-depends-on-kind.sh --self-test
USAGE
}

# run_coverage: 指定した定義ファイルで expected_declarations の全件が、
# 期待どおりの鍵と種別の集合を持つかを見る。旧 dependsOnKind が残っていれば不合格。
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

  local missing="" kind key kinds actual expected total=0
  while IFS=$'\t' read -r kind key kinds; do
    [ -n "$kind" ] || continue
    total=$((total + 1))
    expected="$(printf '%s' "$kinds" | tr ',' '\n' | LC_ALL=C sort | tr '\n' ',')"
    actual="$(jq -r --arg k "$kind" --arg key "$key" '
      [.items[] | select(.kind==$k)] as $hits
      | if ($hits | length) != 1 then "__count__"
        elif $hits[0].dependsOnKind then "__legacy__"
        elif ($hits[0][$key] | type) != "array" then "__missing__"
        else ($hits[0][$key] | sort | join(",")) + "," end
    ' "$inventory")"
    if [ "$actual" != "$expected" ]; then
      missing="${missing} ${kind}(${actual})"
    fi
  done <<EOS
$(expected_declarations)
EOS

  local legacy
  legacy="$(jq -r '[.items[] | select(.dependsOnKind)] | length' "$inventory")"
  if [ "$legacy" != "0" ]; then
    missing="${missing} 旧dependsOnKind残存${legacy}件"
  fi

  if [ -n "$missing" ]; then
    echo "[FAIL] 依存の集合宣言が期待と異なる、または欠けている納品物:${missing}" >&2
    return 1
  fi

  echo "[PASS] 他の種別に依存する納品物 ${total} 件すべてが期待どおりの集合宣言を持ち、旧 dependsOnKind は残っていない"
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

# _write_excluded_kinds: 対象外の記録を合成する。引数は対象外にする種別（空白区切り）。
_write_excluded_kinds() {
  local dest="$1" excluded="$2"
  local kinds_json
  kinds_json="$(printf '%s' "$excluded" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s .)"
  jq -n --argjson all "$ALL_KINDS_JSON" --argjson ex "$kinds_json" '
    {
      generatedAt: "2026-01-01T00:00:00+09:00",
      surveyDocPath: "プロジェクト共通/アーキテクチャ調査書.md",
      allKinds: ($all | map(select(. != "feature"))),
      presentKinds: ($all | map(select(. != "feature")) | map(select(. as $k | $ex | index($k) | not))),
      excludedKinds: ($ex | map({kind: ., label: ., reason: "検査用の合成入力で対象外にした"}))
    }' > "$dest"
}

# _mk_fixture: 一時領域を作り、対象外の記録を置く。標準出力へパスを返す。
_mk_fixture() {
  local excluded="$1" dir
  if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/check-depends-on-kind.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
    return 2
  fi
  mkdir -p "$dir/docs/scope-and-progress"
  _write_excluded_kinds "$dir/docs/scope-and-progress/excluded-kinds.json" "$excluded"
  printf '%s\n' "$dir"
}

# _expect_state: 納品物一覧(Markdown)で kind の行が state を含むかを見る。
_expect_state() {
  local md="$1" kind="$2" state="$3" label
  label="$(_label_for_kind "$kind")"
  grep -F "| ${label} |" "$md" | grep -q -- "$state"
}

# run_check_resolution: 3つの入力で実際に build-deliverable-inventory.sh を走らせる。
#   1. 画面だけが対象外（API のみの対象）: 画面だけに依存する5件が対象なし、
#      API で成立する6件は対象なしにならない
#   2. 6種別すべてが対象外: 13件すべてが対象なし
#   3. 画面あり（回帰）: HTMLが実在すれば従来どおり出力あり
run_check_resolution() {
  if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "[UNKNOWN] 生成スクリプトが見つからないため判定できません: ${BUILD_SCRIPT}" >&2
    return 2
  fi
  if [ ! -f "$OUTPUT_LAYOUT_SCRIPT" ]; then
    echo "[UNKNOWN] 出力配置の解決スクリプトが見つからないため判定できません: ${OUTPUT_LAYOUT_SCRIPT}" >&2
    return 2
  fi
  # shellcheck source=../../generation-engine/scripts/output-layout.sh
  . "$OUTPUT_LAYOUT_SCRIPT"

  local fail=0 dir md kind

  # --- 1. 画面だけが対象外（API のみ） ---
  if ! dir="$(_mk_fixture "screen")"; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  if ! bash "$BUILD_SCRIPT" "$dir" >"$dir/build.log" 2>&1; then
    echo "[FAIL] 画面だけが対象外の入力で納品物一覧の生成が失敗した" >&2
    cat "$dir/build.log" >&2
    fail=1
  else
    md="$dir/docs/納品物一覧.md"
    for kind in $SCREEN_ONLY_KINDS; do
      _expect_state "$md" "$kind" '対象なし' || { echo "[FAIL] 画面だけが対象外の入力で $(_label_for_kind "$kind")（${kind}）が「対象なし」にならない" >&2; fail=1; }
    done
    for kind in $API_OK_KINDS; do
      if _expect_state "$md" "$kind" '対象なし'; then
        echo "[FAIL] 画面だけが対象外の入力で $(_label_for_kind "$kind")（${kind}）が「対象なし」へ倒れた（API があれば成立する納品物）" >&2
        fail=1
      fi
    done
  fi
  rm -rf "$dir"

  # --- 2. 6種別すべてが対象外 ---
  if ! dir="$(_mk_fixture "screen api table batch report external")"; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  if ! bash "$BUILD_SCRIPT" "$dir" >"$dir/build.log" 2>&1; then
    echo "[FAIL] 全種別が対象外の入力で納品物一覧の生成が失敗した" >&2
    cat "$dir/build.log" >&2
    fail=1
  else
    md="$dir/docs/納品物一覧.md"
    for kind in $SCREEN_ONLY_KINDS crud traceability permission-function; do
      _expect_state "$md" "$kind" '対象なし' || { echo "[FAIL] 全種別が対象外の入力で $(_label_for_kind "$kind")（${kind}）が「対象なし」にならない" >&2; fail=1; }
    done
  fi
  rm -rf "$dir"

  # --- 3. 画面あり（回帰）: HTMLが実在すれば従来どおり「出力あり」になること ---
  if ! dir="$(_mk_fixture "")"; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  rm -f "$dir/docs/scope-and-progress/excluded-kinds.json"
  local layout_json glob effective_glob
  if ! layout_json="$(resolve_output_layout "$dir" 2>/dev/null)"; then
    echo "[UNKNOWN] 出力配置の定義を解決できないため判定できません" >&2
    rm -rf "$dir"
    return 2
  fi
  for kind in design-system component-inventory icon-catalog; do
    glob="$(jq -r --arg k "$kind" '.categories[].blueprints[] | select(.kind==$k) | .discovery.glob' "$CATALOG")"
    effective_glob="$(_resolve_catalog_glob "$layout_json" "$glob")"
    mkdir -p "$dir/$(dirname "$effective_glob")"
    : > "$dir/$effective_glob"
  done
  if ! bash "$BUILD_SCRIPT" "$dir" >"$dir/build.log" 2>&1; then
    echo "[FAIL] 画面ありの回帰用入力で納品物一覧の生成が失敗した" >&2
    cat "$dir/build.log" >&2
    fail=1
  else
    md="$dir/docs/納品物一覧.md"
    for kind in design-system component-inventory icon-catalog; do
      _expect_state "$md" "$kind" '出力あり' || { echo "[FAIL] 画面ありの入力で $(_label_for_kind "$kind")（${kind}）が従来どおり判定されなかった" >&2; fail=1; }
    done
  fi
  rm -rf "$dir"

  if [ "$fail" -ne 0 ]; then
    return 1
  fi
  echo "[PASS] 画面だけが対象外なら画面依存7件だけが対象なし、全種別が対象外なら依存する納品物すべてが対象なし、画面ありでは従来どおりの判定を確認した"
  return 0
}

run_self_test() {
  local total=0 fail=0

  # ケース1: 実物の定義ファイルで13件すべてに期待どおりの宣言がある
  total=$((total + 1))
  if _cap="$(run_coverage "$DEFAULT_INVENTORY" 2>&1)"; then
    echo "  [PASS] ケース1: 実物の定義ファイルで13件すべてに期待どおりの宣言がある"
  else
    echo "  [FAIL] ケース1: 実物の定義ファイルで宣言が欠けている、または期待と異なる" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    fail=$((fail + 1))
  fi

  local tmp
  if ! tmp="$(mktemp "${TMPDIR:-/tmp}/check-depends-on-kind.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ファイルを作れないため自己テストの一部を判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -f "$tmp"' RETURN

  # ケース2: 宣言を1件意図的に外すと不合格になる（検収方法4）。
  # 「不合格」の判定はrc==1に限定する。rc==2を合格扱いにすると、jqの変換自体が
  # 失敗した場合もPASSしてしまい、宣言の欠落を検出する経路を確かめないまま通る
  total=$((total + 1))
  local rc2=0
  if ! jq '(.items[] | select(.kind=="design-system")) |= del(.requiresAllOf)' "$DEFAULT_INVENTORY" > "$tmp" 2>/dev/null; then
    echo "  [FAIL] ケース2: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  else
    run_coverage "$tmp" >/dev/null 2>&1
    rc2=$?
    if [ "$rc2" -eq 1 ]; then
      echo "  [PASS] ケース2: 宣言を意図的に外すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース2: 宣言を外したときの終了コードが1でない(rc=${rc2})" >&2
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

  # ケース5: 全13件が揃った正常な入力では合格する（重複や誤字での過検出が無いことの確認）
  total=$((total + 1))
  cp "$DEFAULT_INVENTORY" "$tmp"
  if _cap="$(run_coverage "$tmp" 2>&1)"; then
    echo "  [PASS] ケース5: 全13件が揃った入力を複製しても合格する"
  else
    echo "  [FAIL] ケース5: 複製した正常な入力で不合格になった" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    fail=$((fail + 1))
  fi

  # ケース6: API で成立する納品物へ画面だけの依存(requiresAllOf=["screen"])を書くと不合格になる。
  # 画面を持たず API だけを持つ対象でその納品物が欠ける誤りを検出する
  total=$((total + 1))
  local rc6=0
  if ! jq '(.items[] | select(.kind=="crud")) |= (del(.requiresAnyOf) | .requiresAllOf=["screen"])' "$DEFAULT_INVENTORY" > "$tmp" 2>/dev/null; then
    echo "  [FAIL] ケース6: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  else
    run_coverage "$tmp" >/dev/null 2>&1
    rc6=$?
    if [ "$rc6" -eq 1 ]; then
      echo "  [PASS] ケース6: API で成立する納品物へ画面だけの依存を書くと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース6: 画面だけの依存を書いたときの終了コードが1でない(rc=${rc6})" >&2
      fail=$((fail + 1))
    fi
  fi

  # ケース7: 旧い単一値の dependsOnKind が残っていると不合格になる
  total=$((total + 1))
  local rc7=0
  if ! jq '(.items[] | select(.kind=="icon-catalog")) |= (del(.requiresAllOf) | .dependsOnKind="screen")' "$DEFAULT_INVENTORY" > "$tmp" 2>/dev/null; then
    echo "  [FAIL] ケース7: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  else
    run_coverage "$tmp" >/dev/null 2>&1
    rc7=$?
    if [ "$rc7" -eq 1 ]; then
      echo "  [PASS] ケース7: 旧 dependsOnKind が残っていると不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース7: 旧 dependsOnKind が残っているときの終了コードが1でない(rc=${rc7})" >&2
      fail=$((fail + 1))
    fi
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
}

main "$@"
