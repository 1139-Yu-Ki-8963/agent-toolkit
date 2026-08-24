#!/usr/bin/env bash
# check-confirmation-doc-handover.sh — 確定していない事項の台帳が納品物から
# 外れ、確定していない事項そのものを失わない経路が定義されているかを見る
# （改善課題1-256）。
#
# 背景:
#   delivery-payload/references/deliverable-inventory.json は、設計単位ごとの
#   確定していない事項の台帳（要確認事項台帳.json）を confirmation-item-ledger
#   という納品物として数えていた。この台帳が書き戻す先は設計書の確定していない
#   事項の節だが、その節は1-223で全テンプレートから外された。書き戻す先を失った
#   後も、台帳を指す portal-catalog.json の discovery.glob（docs/design/**/
#   要確認事項台帳.html）を生成する処理は1本も存在せず、納品物の一覧は永久に
#   「未生成」を報告し続けていた。
#
# 実測（1-256の起票時点）:
#   confirmation-survey（確認事項質問票）は、generation-engine/scripts/extract/
#   build-confirmation-survey-data.sh の --confirmation-ledger 引数を通じて、
#   設計単位ごとの要確認事項台帳.json を既に横断集約している
#   （generation-engine/scripts/verification/run-layer-full-pipeline.sh の
#   build_confirmation_ledger_args 経由）。confirmation-survey は
#   portal-catalog.json・deliverable-inventory.json の両方に既に存在し、
#   生成元（generating-cross-views-for-reverse-docs）も実在する。新規の
#   受け皿を作ると、confirmation-item-ledger と同じ「生成元を持たない
#   納品物」を複製しかねない。既存の confirmation-survey を正式な受け皿と
#   位置づけ、置き場を output-layout.json の matrixDir に紐づけて明記する
#   方針を採った。
#
# 検査内容（検収方法1〜4に対応。5・6は自己テストの専用ケースで扱う）:
#   1. confirmation-item-ledger が portal-catalog.json・deliverable-inventory.json
#      の両方から外れていること
#   2. confirmation-survey が両方に存在し、discovery.glob が
#      defaultRoots.matrixDir を起点として output-layout.json の
#      layout.matrixDir へ解決できること（置き場の定義）
#   3. output-layout.json に、確定していない事項が失われない経路（設計書は
#      確定事項のみ・confirmation-surveyが確定していない事項を集約）の
#      明記があること
#   4. output-layout.json に、台帳を作る側の作業記録として持つ旨の明記が
#      あること
#
# 使い方:
#   check-confirmation-doc-handover.sh
#   check-confirmation-doc-handover.sh --catalog <file> --inventory <file> --layout <file>
#   check-confirmation-doc-handover.sh --self-test
#
# 終了コード: 0=4検査すべて合格。1=いずれかの検査が不合格。
#             2=判定不能（対象ファイル不在・JSON不正・一時領域を作れない等）。
#
# 実装判断（一時ファイル・自己参照の除外）:
#   このリポジトリの check-depends-on-kind.sh・check-manifest-count-mismatch.sh
#   と同じ形で mktemp の置き場を明示し（.claude/rules/always/verification/
#   indeterminate-result/rule.md の判定不能規約に従う）、diff・comm は使わない
#   （jqの述語だけで判定する。プロセス置換を外部コマンドへ渡さない）。走査は
#   対象JSON3ファイルへのjq問い合わせに限定し、リポジトリ全体のgrepは行わない
#   （本スクリプト自身が"confirmation-item-ledger"という文字列を含むため、
#   ツリー全体を走査すると自己参照で誤検出する）。
#
# 設計判断: .claude/rules/always/tasks/instruction-format/rule.md の
#   「設計判断」節「check-confirmation-doc-handover.sh」を参照。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_CATALOG="$REPO_ROOT/delivery-payload/references/portal-catalog.json"
DEFAULT_INVENTORY="$REPO_ROOT/delivery-payload/references/deliverable-inventory.json"
DEFAULT_LAYOUT="$REPO_ROOT/delivery-payload/references/output-layout.json"
SURVEY_SCRIPT="$REPO_ROOT/generation-engine/scripts/extract/build-confirmation-survey-data.sh"

REMOVED_KIND="confirmation-item-ledger"
RECEPTACLE_KIND="confirmation-survey"

usage() {
  cat >&2 <<'USAGE'
Usage: check-confirmation-doc-handover.sh [--catalog <file>] [--inventory <file>] [--layout <file>]
       check-confirmation-doc-handover.sh --self-test
USAGE
}

_mk_tmp() {
  mktemp "${TMPDIR:-/tmp}/check-confirmation-doc-handover.XXXXXX" 2>/dev/null
}

_mk_tmp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/check-confirmation-doc-handover.XXXXXX" 2>/dev/null
}

# _json_ok: 指定ファイルが実在しjqでパースできるかを見る。判定不能ならUNKNOWNを出して2を返す
_json_ok() {
  local file="$1" label="$2"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] ${label}が見つからないため判定できません: ${file}" >&2
    return 2
  fi
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    echo "[UNKNOWN] ${label}をJSONとして読めないため判定できません: ${file}" >&2
    return 2
  fi
  return 0
}

# check_removed: 台帳(confirmation-item-ledger)がcatalog・inventoryの両方から
# 外れているかを見る（検収方法1）
check_removed() {
  local catalog="$1" inventory="$2"
  local in_catalog in_inventory fail=0

  in_catalog="$(jq -r --arg k "$REMOVED_KIND" '[.categories[].blueprints[] | select(.kind==$k)] | length' "$catalog")"
  in_inventory="$(jq -r --arg k "$REMOVED_KIND" '[.items[] | select(.kind==$k)] | length' "$inventory")"

  if [ "$in_catalog" != "0" ]; then
    echo "[FAIL] 検査1: ${REMOVED_KIND} が portal-catalog.json に残っている" >&2
    fail=1
  fi
  if [ "$in_inventory" != "0" ]; then
    echo "[FAIL] 検査1: ${REMOVED_KIND} が deliverable-inventory.json に残っている" >&2
    fail=1
  fi
  if [ "$fail" -eq 0 ]; then
    echo "[PASS] 検査1: ${REMOVED_KIND} が納品物の一覧から外れている"
    return 0
  fi
  return 1
}

# check_receptacle: 確定していない事項の受け皿(confirmation-survey)が両方に
# 存在し、置き場がoutput-layout.jsonのmatrixDirへ解決できるかを見る（検収方法2）
check_receptacle() {
  local catalog="$1" inventory="$2" layout="$3"
  local in_catalog in_inventory glob matrix_default matrix_layout fail=0

  in_catalog="$(jq -r --arg k "$RECEPTACLE_KIND" '[.categories[].blueprints[] | select(.kind==$k)] | length' "$catalog")"
  in_inventory="$(jq -r --arg k "$RECEPTACLE_KIND" '[.items[] | select(.kind==$k)] | length' "$inventory")"

  if [ "$in_catalog" != "1" ]; then
    echo "[FAIL] 検査2: ${RECEPTACLE_KIND} が portal-catalog.json に存在しない" >&2
    fail=1
  fi
  if [ "$in_inventory" != "1" ]; then
    echo "[FAIL] 検査2: ${RECEPTACLE_KIND} が deliverable-inventory.json に存在しない" >&2
    fail=1
  fi
  if [ "$fail" -ne 0 ]; then
    return 1
  fi

  glob="$(jq -r --arg k "$RECEPTACLE_KIND" '.categories[].blueprints[] | select(.kind==$k) | .discovery.glob' "$catalog")"
  matrix_default="$(jq -r '.defaultRoots.matrixDir // empty' "$catalog")"
  matrix_layout="$(jq -r '.layout.matrixDir // empty' "$layout")"

  if [ -z "$matrix_default" ] || [ -z "$matrix_layout" ]; then
    echo "[FAIL] 検査2: matrixDir が catalog の defaultRoots または output-layout.json の layout に定義されていない" >&2
    return 1
  fi
  case "$glob" in
    "$matrix_default"/*) : ;;
    *)
      echo "[FAIL] 検査2: ${RECEPTACLE_KIND} の discovery.glob（${glob}）が defaultRoots.matrixDir（${matrix_default}）を起点としていない" >&2
      return 1
      ;;
  esac

  echo "[PASS] 検査2: ${RECEPTACLE_KIND} が納品物の一覧に含まれ、置き場が output-layout.json の matrixDir（${matrix_layout}）に紐づいている"
  return 0
}

# check_note: output-layout.jsonに経路の明記(検収方法3)と作業記録の明記
# (検収方法4)があるかを見る
check_note() {
  local layout="$1"
  local note fail=0

  note="$(jq -r '.directoryNamePolicy.confirmationItemHandover // empty' "$layout")"
  if [ -z "$note" ]; then
    echo "[FAIL] 検査3/4: output-layout.json に confirmationItemHandover の明記が無い" >&2
    return 1
  fi

  if ! printf '%s' "$note" | grep -q '作業記録' || ! printf '%s' "$note" | grep -q '納品物の一覧'; then
    echo "[FAIL] 検査4: 台帳を作業記録として持つ旨の明記が無い" >&2
    fail=1
  fi
  if ! printf '%s' "$note" | grep -q "$RECEPTACLE_KIND" || ! printf '%s' "$note" | grep -q '失われない'; then
    echo "[FAIL] 検査3: 確定していない事項が失われない経路の明記が無い" >&2
    fail=1
  fi

  if [ "$fail" -eq 0 ]; then
    echo "[PASS] 検査3: 確定していない事項が失われない経路が明記されている"
    echo "[PASS] 検査4: 台帳を作業記録として持つ旨が明記されている"
    return 0
  fi
  return 1
}

run_check() {
  local catalog="$1" inventory="$2" layout="$3"
  local rc

  _json_ok "$catalog" "portal-catalog.json"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  _json_ok "$inventory" "deliverable-inventory.json"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  _json_ok "$layout" "output-layout.json"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

  local fail=0
  check_removed "$catalog" "$inventory" || fail=1
  check_receptacle "$catalog" "$inventory" "$layout" || fail=1
  check_note "$layout" || fail=1

  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

run_self_test() {
  local total=0 fail=0 tmp

  if ! tmp="$(_mk_tmp_dir)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 実物の3ファイルで4検査すべて合格する
  total=$((total + 1))
  if run_check "$DEFAULT_CATALOG" "$DEFAULT_INVENTORY" "$DEFAULT_LAYOUT" >/dev/null 2>&1; then
    echo "  [PASS] ケース1: 実物の定義3ファイルで4検査すべて合格する"
  else
    echo "  [FAIL] ケース1: 実物の定義3ファイルで不合格の検査がある" >&2
    fail=$((fail + 1))
  fi

  # ケース2: 台帳をcatalogへ戻すと検査1が不合格になる
  total=$((total + 1))
  local c2="$tmp/catalog-restored-ledger.json"
  if jq '.categories |= map(if .key == "design" then .blueprints += [{"kind":"confirmation-item-ledger","label":"要確認事項台帳","discovery":{"glob":"docs/design/**/要確認事項台帳.html"}}] else . end)' \
    "$DEFAULT_CATALOG" > "$c2" 2>/dev/null; then
    local rc2=0
    run_check "$c2" "$DEFAULT_INVENTORY" "$DEFAULT_LAYOUT" >/dev/null 2>&1 || rc2=$?
    if [ "$rc2" -eq 1 ]; then
      echo "  [PASS] ケース2: 台帳をportal-catalog.jsonへ戻すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース2: 台帳を戻したときの終了コードが1でない(rc=${rc2})" >&2
      fail=$((fail + 1))
    fi
  else
    echo "  [FAIL] ケース2: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  fi

  # ケース3: 台帳をinventoryへ戻すと検査1が不合格になる(catalog側は正常のまま)
  total=$((total + 1))
  local i3="$tmp/inventory-restored-ledger.json"
  if jq '.items += [{"kind":"confirmation-item-ledger","evidenceSource":"none"}]' \
    "$DEFAULT_INVENTORY" > "$i3" 2>/dev/null; then
    local rc3=0
    run_check "$DEFAULT_CATALOG" "$i3" "$DEFAULT_LAYOUT" >/dev/null 2>&1 || rc3=$?
    if [ "$rc3" -eq 1 ]; then
      echo "  [PASS] ケース3: 台帳をdeliverable-inventory.jsonへ戻すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース3: 台帳を戻したときの終了コードが1でない(rc=${rc3})" >&2
      fail=$((fail + 1))
    fi
  else
    echo "  [FAIL] ケース3: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  fi

  # ケース4: confirmation-surveyをcatalogから消すと検査2が不合格になる
  total=$((total + 1))
  local c4="$tmp/catalog-no-survey.json"
  if jq '.categories |= map(.blueprints |= map(select(.kind != "confirmation-survey")))' \
    "$DEFAULT_CATALOG" > "$c4" 2>/dev/null; then
    local rc4=0
    run_check "$c4" "$DEFAULT_INVENTORY" "$DEFAULT_LAYOUT" >/dev/null 2>&1 || rc4=$?
    if [ "$rc4" -eq 1 ]; then
      echo "  [PASS] ケース4: confirmation-surveyをportal-catalog.jsonから消すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース4: 消したときの終了コードが1でない(rc=${rc4})" >&2
      fail=$((fail + 1))
    fi
  else
    echo "  [FAIL] ケース4: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  fi

  # ケース5: output-layout.jsonのconfirmationItemHandoverノートを消すと検査3/4が不合格になる
  total=$((total + 1))
  local l5="$tmp/layout-no-note.json"
  if jq 'del(.directoryNamePolicy.confirmationItemHandover)' \
    "$DEFAULT_LAYOUT" > "$l5" 2>/dev/null; then
    local rc5=0
    run_check "$DEFAULT_CATALOG" "$DEFAULT_INVENTORY" "$l5" >/dev/null 2>&1 || rc5=$?
    if [ "$rc5" -eq 1 ]; then
      echo "  [PASS] ケース5: 経路・作業記録の明記を消すと不合格になる(rc=1)"
    else
      echo "  [FAIL] ケース5: 消したときの終了コードが1でない(rc=${rc5})" >&2
      fail=$((fail + 1))
    fi
  else
    echo "  [FAIL] ケース5: フィクスチャの作成(jq)自体が失敗した" >&2
    fail=$((fail + 1))
  fi

  # ケース6: 定義ファイルが存在しない場合は判定不能(UNKNOWN・終了コード2)
  total=$((total + 1))
  local rc6=0
  run_check "$tmp/does-not-exist.json" "$DEFAULT_INVENTORY" "$DEFAULT_LAYOUT" >/dev/null 2>&1 || rc6=$?
  if [ "$rc6" -eq 2 ]; then
    echo "  [PASS] ケース6: 対象ファイルが無いと判定不能(終了コード2)になる"
  else
    echo "  [FAIL] ケース6: ファイル不在のときの終了コードが2でない(rc=${rc6})" >&2
    fail=$((fail + 1))
  fi

  # ケース7（検収方法5）: 確定していない事項が1件以上ある台帳から、
  # confirmation-surveyの元データへ質問行が生成されること
  total=$((total + 1))
  if [ -f "$SURVEY_SCRIPT" ]; then
    local ledger7="$tmp/要確認事項台帳-1件.json"
    jq -n '{
      unitKey: "screen-order-list",
      designDocument: "画面詳細設計書.md",
      items: [{"key":"表示件数の既定値","question":"一覧の既定の表示件数を確認してください","status":"未確認","answer":""}]
    }' > "$ledger7"
    local out7="$tmp/confirmation-survey-1件.json"
    if bash "$SURVEY_SCRIPT" "$out7" --confirmation-ledger "$ledger7" >"$tmp/survey7.log" 2>&1 \
      && [ "$(jq '.questions | length' "$out7" 2>/dev/null)" -ge 1 ]; then
      echo "  [PASS] ケース7: 確定していない事項1件の台帳からconfirmation-surveyの質問行が生成される"
    else
      echo "  [FAIL] ケース7: 確定していない事項1件の台帳から質問行が生成されない" >&2
      cat "$tmp/survey7.log" >&2 2>/dev/null || true
      fail=$((fail + 1))
    fi
  else
    echo "  [UNKNOWN] ケース7: ${SURVEY_SCRIPT} が見つからないため判定できません" >&2
  fi

  # ケース8（検収方法6）: 確定していない事項が0件の台帳では質問行が生成されないこと
  total=$((total + 1))
  if [ -f "$SURVEY_SCRIPT" ]; then
    local ledger8="$tmp/要確認事項台帳-0件.json"
    jq -n '{unitKey: "screen-order-list", designDocument: "画面詳細設計書.md", items: []}' > "$ledger8"
    local out8="$tmp/confirmation-survey-0件.json"
    if bash "$SURVEY_SCRIPT" "$out8" --confirmation-ledger "$ledger8" >"$tmp/survey8.log" 2>&1 \
      && [ "$(jq '.questions | length' "$out8" 2>/dev/null)" = "0" ]; then
      echo "  [PASS] ケース8: 確定していない事項0件の台帳では質問行が生成されない"
    else
      echo "  [FAIL] ケース8: 0件の台帳で質問行が生成された、または実行が失敗した" >&2
      cat "$tmp/survey8.log" >&2 2>/dev/null || true
      fail=$((fail + 1))
    fi
  else
    echo "  [UNKNOWN] ケース8: ${SURVEY_SCRIPT} が見つからないため判定できません" >&2
  fi

  echo "実行 ${total} 件 / 成功 $((total - fail)) 件 / 失敗 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main() {
  local catalog="$DEFAULT_CATALOG" inventory="$DEFAULT_INVENTORY" layout="$DEFAULT_LAYOUT"

  if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    exit $?
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --catalog) catalog="${2:-}"; shift 2 ;;
      --inventory) inventory="${2:-}"; shift 2 ;;
      --layout) layout="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done

  run_check "$catalog" "$inventory" "$layout"
  exit $?
}

main "$@"
