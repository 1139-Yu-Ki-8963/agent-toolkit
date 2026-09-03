#!/usr/bin/env bash
set -u

# check-basic-phase.sh — 全種別の全単位と共通設計文書6つの機械検査を集約する
#
# 目的:
#   基本設計の完了判定は、まず機械で読める部分（単位ごとの様式・見出し・
#   事実の転記、共通設計文書の見出し構成）を集約して確かめる。文書の
#   レビュー担当（AI）はこの結果を通った単位・文書だけを完了状態の観点で
#   読めばよく、様式不備を毎回読む必要が無くなる。
#
# 使い方:
#   check-basic-phase.sh <対象リポジトリのルート> --run <実行フォルダ>
#   check-basic-phase.sh --self-test
#
# 種別ごとの単位検査は基本設計書を書く機能のcheck-basic-design.shを呼ぶ。
# 共通設計文書6つの検査は道標を描く機能のcheck-design-docs.shを呼ぶ。
# 一覧が無い種別（対象にその種別の単位が無い）は対象外として扱う。
#
# 出力:
#   <実行フォルダ>/logs/basic-phase-check.json に
#   {"種別":{"<種別>":{"対象":bool,"合格":bool}},
#    "共通設計文書":{"<文書名>":{"実在":bool,"合格":bool}},"判定":"合格"|"不合格"}
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   共有部品-不在   check-basic-design.sh・check-design-docs.sh・unit-kinds.jsonが無い
#   文書-不在       共通設計文書が実在しない
#
# 終了コード:
#   0 = 全種別・全共通設計文書が合格（対象外は数えない）
#   1 = 1件以上が不合格
#   2 = 使い方の誤り・共有部品が無い（判定不能）
#
# 保守責任者: 人手（ユーザー）。共通設計文書6つの一覧を変えるときは、
#   本スクリプトと道標を描く機能の様式を同時に直す。
#
# 廃棄条件: 完了判定の集約を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASIC_DESIGN_SH="${SCRIPT_DIR}/../../reverse-writing-basic-design/scripts/check-basic-design.sh"
DESIGN_DOCS_SH="${SCRIPT_DIR}/../../reverse-drawing-map/scripts/check-design-docs.sh"
UNIT_KINDS_JSON="${SCRIPT_DIR}/../../reverse-shared/references/unit-kinds.json"
COMMON_DOCS="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

usage_error() {
  echo "使い方: check-basic-phase.sh <対象リポジトリのルート> --run <実行フォルダ>" >&2
  echo "        check-basic-phase.sh --self-test" >&2
  exit 2
}

deps_available() {
  [ -f "$BASIC_DESIGN_SH" ] && [ -f "$DESIGN_DOCS_SH" ] && [ -f "$UNIT_KINDS_JSON" ]
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done
  [ -n "$run_dir" ] || usage_error

  if ! deps_available; then
    echo "[FAIL] 共有部品-不在: check-basic-design.sh・check-design-docs.sh・unit-kinds.jsonのいずれかがありません" >&2
    exit 2
  fi

  mkdir -p "${run_dir%/}/logs" 2>/dev/null
  local out_json="${run_dir%/}/logs/basic-phase-check.json"

  local kinds kind overall_fail=0 kind_entries="" list_file rc entry

  kinds="$(jq -r '.[].key' "$UNIT_KINDS_JSON")"
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    list_file="${target}/docs/design/lists/${kind}.json"
    if [ ! -f "$list_file" ]; then
      entry="$(jq -n --arg k "$kind" '{($k): {"対象": false}}')"
    else
      bash "$BASIC_DESIGN_SH" "$target" --run "$run_dir" --kind "$kind" > /dev/null 2>>"${run_dir%/}/logs/basic-phase-check-${kind}.log"
      rc=$?
      if [ "$rc" -eq 0 ]; then
        entry="$(jq -n --arg k "$kind" '{($k): {"対象": true, "合格": true}}')"
      else
        overall_fail=1
        entry="$(jq -n --arg k "$kind" '{($k): {"対象": true, "合格": false}}')"
      fi
    fi
    kind_entries="${kind_entries}${entry}
"
  done <<KINDS
$kinds
KINDS

  local doc doc_path common_entries=""
  for doc in $COMMON_DOCS; do
    doc_path="${target}/docs/design/common/${doc}.md"
    if [ ! -f "$doc_path" ]; then
      echo "[FAIL] 文書-不在: ${doc_path} が実在しません" >&2
      overall_fail=1
      entry="$(jq -n --arg d "$doc" '{($d): {"実在": false, "合格": false}}')"
    else
      if bash "$DESIGN_DOCS_SH" "$doc_path" > /dev/null 2>>"${run_dir%/}/logs/basic-phase-check-common.log"; then
        entry="$(jq -n --arg d "$doc" '{($d): {"実在": true, "合格": true}}')"
      else
        overall_fail=1
        entry="$(jq -n --arg d "$doc" '{($d): {"実在": true, "合格": false}}')"
      fi
    fi
    common_entries="${common_entries}${entry}
"
  done

  local kinds_json common_json verdict
  kinds_json="$(printf '%s' "$kind_entries" | jq -s 'add // {}')"
  common_json="$(printf '%s' "$common_entries" | jq -s 'add // {}')"
  if [ "$overall_fail" -eq 0 ]; then verdict="合格"; else verdict="不合格"; fi

  jq -n --argjson kinds "$kinds_json" --argjson common "$common_json" --arg v "$verdict" \
    '{"種別": $kinds, "共通設計文書": $common, "判定": $v}' > "$out_json"

  echo "判定: ${verdict}"
  if [ "$overall_fail" -eq 1 ]; then
    exit 1
  fi
  exit 0
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/check-basic-phase-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

  check() {
    local name="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${name}"
    else
      echo "FAIL: ${name}"
      fail=$((fail + 1))
    fi
  }

  # --- 使い方エラー系 ---
  bash "$SCRIPT_DIR/check-basic-phase.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/check-basic-phase.sh" "$base" > "$base/u2.out" 2>"$base/u2.err"
  check "使い方-run未指定は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local tmpl_dir="${SCRIPT_DIR}/../../reverse-drawing-map/templates/common"
  local docs="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

  write_common_docs() {
    local d="$1" name
    mkdir -p "$d/docs/design/common"
    for name in $docs; do
      sed -E 's/<[^<>]+>/記入済み/g' "${tmpl_dir}/${name}.md" > "$d/docs/design/common/${name}.md"
    done
  }

  # --- 合格-共通設計文書のみ（単位の種別は0件） ---
  local d1="$base/target1" run1="$base/run1"
  mkdir -p "$d1/docs/design/lists" "$run1"
  write_common_docs "$d1"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d1" --run "$run1" > "$base/c1.out" 2>"$base/c1.err"
  local rc1=$?
  check "合格-共通設計文書のみ: 終了コード0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
  local verdict1
  verdict1="$(jq -r '.["判定"]' "$run1/logs/basic-phase-check.json" 2>/dev/null)"
  check "合格-共通設計文書のみ: 判定が合格" "$([ "$verdict1" = "合格" ] && echo 0 || echo 1)"

  # --- 不合格-共通設計文書が1つ不在 ---
  local d2="$base/target2" run2="$base/run2"
  mkdir -p "$d2/docs/design/lists" "$run2"
  write_common_docs "$d2"
  rm -f "$d2/docs/design/common/基盤設計書.md"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d2" --run "$run2" > "$base/c2.out" 2>"$base/c2.err"
  local rc2=$?
  check "不合格-共通設計文書不在: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"
  local base_ok2
  base_ok2="$(jq -r '.["共通設計文書"]["基盤設計書"]["実在"]' "$run2/logs/basic-phase-check.json" 2>/dev/null)"
  check "不合格-共通設計文書不在: 実在がfalse" "$([ "$base_ok2" = "false" ] && echo 0 || echo 1)"

  # --- 不合格-種別に単位はあるが文書が無い ---
  local d3="$base/target3" run3="$base/run3"
  mkdir -p "$d3/docs/design/lists" "$run3" \
           "$d3/docs/rules/documentation-standards/document-writing" \
           "$d3/docs/rules/quality-assurance/test-policy"
  write_common_docs "$d3"
  cat > "$d3/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  cat > "$d3/docs/rules/documentation-standards/document-writing/check-doc-heading-addendum.sh" <<'HOOKEOF'
#!/usr/bin/env bash
exit 0
HOOKEOF
  chmod +x "$d3/docs/rules/documentation-standards/document-writing/check-doc-heading-addendum.sh"
  cat > "$d3/docs/rules/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh" <<'HOOKEOF2'
#!/usr/bin/env bash
exit 0
HOOKEOF2
  chmod +x "$d3/docs/rules/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d3" --run "$run3" > "$base/c3.out" 2>"$base/c3.err"
  local rc3=$?
  check "不合格-種別に文書無し: 終了コード1" "$([ "$rc3" -eq 1 ] && echo 0 || echo 1)"
  local screen_ok3
  screen_ok3="$(jq -r '.["種別"]["screen"]["合格"]' "$run3/logs/basic-phase-check.json" 2>/dev/null)"
  check "不合格-種別に文書無し: screenの合格がfalse" "$([ "$screen_ok3" = "false" ] && echo 0 || echo 1)"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================
# エントリポイント
# ============================================================

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

run_main "$@"
