#!/usr/bin/env bash
set -u

# test-self-tests.sh — reverse-shared の検収（acceptance）
#
# 目的:
#   reverse-shared は名前の決まり（skill-naming）によりSKILL.mdを持たない
#   共有部品であり、検収は本tests/が担う。read-run.sh・check-entry.sh・
#   unit-dir-name.sh・units-status.sh・list-units-of.sh・start-run.sh・
#   plan-units.sh・check-basic-phase.sh・record-acceptance.sh・
#   check-acceptance-record.shの--self-testを回すことに加え、references/の複製が
#   docs/design/common/の定義と一致していること（複製のずれ防止）を確かめる。
#   setupの原本（写しの元）が無い環境、およびdocs/design/common自体が無い環境では、
#   同一性の検査をSKIPにする。
#
# 使い方:
#   bash test-self-tests.sh
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#
# 保守責任者: 人手（ユーザー）。references/の複製元（docs/design/common/unit-kinds.json・
#   docs/design/common/output-layout.json・docs/design/common/code-reading-items.json）を変える
#   ときは、複製先とあわせて本テストも確かめる。
#
# 廃棄条件: reverse-shared自体を廃止した時。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESIGN_DIR="${SHARED_DIR}/../../design/common"
if [ -d "$DESIGN_DIR" ]; then
  DESIGN_DIR="$(cd "$DESIGN_DIR" && pwd)"
else
  DESIGN_DIR=""
fi
SETUP_DIR="${SHARED_DIR}/../setup-scaffolding-rules/templates/rules/tool-defined"
if [ -d "$SETUP_DIR" ]; then
  SETUP_DIR="$(cd "$SETUP_DIR" && pwd)"
else
  SETUP_DIR=""
fi
SETUP_REFERENCES_DIR="${SHARED_DIR}/../setup-scaffolding-rules/references"
if [ -d "$SETUP_REFERENCES_DIR" ]; then
  SETUP_REFERENCES_DIR="$(cd "$SETUP_REFERENCES_DIR" && pwd)"
else
  SETUP_REFERENCES_DIR=""
fi

total=0
fail=0

run_case() {
  local desc="$1"; shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS: ${desc}"
  else
    echo "FAIL: ${desc}"
    fail=$((fail + 1))
  fi
}

process_function_mapping_ok() {
  # 流れの設計の各工程の「担当」欄がバッククォートで名指しする機能名について、
  # docs/skills に実在し、そのSKILL.mdのoutputsが「出力」欄の語と対応することを見る。
  # バッククォートの名指しが無い工程（人が担当・機能名を書かない慣行の工程）は対象外。
  local doc="$1" skills_root="$2"
  local blocks
  blocks="$(awk '
    /^### 工程 / { if (started) print "===SECTION==="; started=1 }
    started { print }
    END { if (started) print "===SECTION===" }
  ' "$doc")"
  local block="" line all_ok=1
  while IFS= read -r line; do
    if [ "$line" = "===SECTION===" ]; then
      if [ -n "$block" ]; then
        process_one_section "$block" "$skills_root" || all_ok=0
      fi
      block=""
      continue
    fi
    block="${block}${line}"$'\n'
  done <<< "$blocks"
  [ "$all_ok" -eq 1 ]
}

process_one_section() {
  local block="$1" skills_root="$2"
  local tanto shukka
  tanto="$(printf '%s\n' "$block" | grep -m1 '^| 担当 ' || true)"
  shukka="$(printf '%s\n' "$block" | grep -m1 '^| 出力 ' || true)"
  [ -n "$tanto" ] || return 0
  local names
  names="$(printf '%s' "$tanto" | grep -o '`[a-zA-Z0-9-]\+`' | tr -d '`')"
  [ -n "$names" ] || return 0
  [ -n "$shukka" ] || return 0
  case "$shukka" in
    *'無し'*) return 0 ;;
  esac
  local name section_ok=1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    local skill_file="${skills_root}/${name}/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      echo "[FAIL] 工程-機能不在: ${name}" >&2
      section_ok=0
      continue
    fi
    local outputs_line
    outputs_line="$(grep -m1 '^outputs:' "$skill_file" | sed 's/^outputs: *//')"
    outputs_line="${outputs_line#\[}"
    outputs_line="${outputs_line%\]}"
    local elems=() elem base stem matched=0
    IFS=',' read -r -a elems <<< "$outputs_line"
    for elem in "${elems[@]}"; do
      elem="$(printf '%s' "$elem" | sed -e 's/^ *//' -e 's/ *$//')"
      base="${elem##*/}"
      stem="${base%.*}"
      [ -n "$stem" ] || continue
      case "$shukka" in
        *"$stem"*) matched=1; break ;;
      esac
    done
    if [ "$matched" -ne 1 ]; then
      echo "[FAIL] 工程-出力不一致: ${name} の outputs が出力欄と対応しない (${shukka})" >&2
      section_ok=0
    fi
  done <<< "$names"
  [ "$section_ok" -eq 1 ]
}

cmp_ignoring_notice() {
  local expected="$1" actual="$2"
  local tmp_expected tmp_actual
  tmp_expected="$(mktemp "${TMPDIR:-/tmp}/reverse-shared-cmp.XXXXXX")"
  tmp_actual="$(mktemp "${TMPDIR:-/tmp}/reverse-shared-cmp.XXXXXX")"
  tail -n +2 "$expected" > "$tmp_expected"
  tail -n +3 "$actual" > "$tmp_actual"
  cmp -s "$tmp_expected" "$tmp_actual"
  local result=$?
  rm -f "$tmp_expected" "$tmp_actual"
  return $result
}

run_case "read-run.sh --self-test" bash "${SHARED_DIR}/scripts/read-run.sh" --self-test
run_case "design-root.sh --self-test" bash "${SHARED_DIR}/scripts/design-root.sh" --self-test
run_case "check-entry.sh --self-test" bash "${SHARED_DIR}/scripts/check-entry.sh" --self-test
run_case "unit-dir-name.sh --self-test" bash "${SHARED_DIR}/scripts/unit-dir-name.sh" --self-test
run_case "units-status.sh --self-test" bash "${SHARED_DIR}/scripts/units-status.sh" --self-test
run_case "list-units-of.sh --self-test" bash "${SHARED_DIR}/scripts/list-units-of.sh" --self-test
run_case "check-doc-heading-addendum.sh --self-test" bash "${SHARED_DIR}/scripts/check-doc-heading-addendum.sh" --self-test
run_case "check-unit-test-design-doc-sections.sh --self-test" bash "${SHARED_DIR}/scripts/check-unit-test-design-doc-sections.sh" --self-test
run_case "start-run.sh --self-test" bash "${SHARED_DIR}/scripts/start-run.sh" --self-test
run_case "plan-units.sh --self-test" bash "${SHARED_DIR}/scripts/plan-units.sh" --self-test
run_case "check-basic-phase.sh --self-test" bash "${SHARED_DIR}/scripts/check-basic-phase.sh" --self-test
run_case "record-acceptance.sh --self-test" bash "${SHARED_DIR}/scripts/record-acceptance.sh" --self-test
run_case "check-acceptance-record.sh --self-test" bash "${SHARED_DIR}/scripts/check-acceptance-record.sh" --self-test
if [ -n "$DESIGN_DIR" ]; then
  run_case "定義と複製が一致する: unit-kinds.json" cmp -s "${DESIGN_DIR}/unit-kinds.json" "${SHARED_DIR}/references/unit-kinds.json"
  run_case "定義と複製が一致する: output-layout.json" cmp -s "${DESIGN_DIR}/output-layout.json" "${SHARED_DIR}/references/output-layout.json"
  run_case "定義と複製が一致する: code-reading-items.json" cmp -s "${DESIGN_DIR}/code-reading-items.json" "${SHARED_DIR}/references/code-reading-items.json"
else
  echo "SKIP: 定義と複製が一致する: unit-kinds.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: output-layout.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: code-reading-items.json（原本のdocs/design/commonが無い）"
fi
if [ -n "$SETUP_REFERENCES_DIR" ] && [ -f "${SETUP_REFERENCES_DIR}/rule-taxonomy.json" ]; then
  run_case "定義と複製が一致する: rule-taxonomy.json" cmp -s "${SETUP_REFERENCES_DIR}/rule-taxonomy.json" "${SHARED_DIR}/references/rule-taxonomy.json"
else
  echo "SKIP: 定義と複製が一致する: rule-taxonomy.json（原本が無い）"
fi
if [ -n "$SETUP_DIR" ] && [ -f "${SETUP_DIR}/documentation-standards/document-writing/check-doc-heading-addendum.sh" ]; then
  run_case "写しが原本と一致する: check-doc-heading-addendum.sh" cmp_ignoring_notice "${SETUP_DIR}/documentation-standards/document-writing/check-doc-heading-addendum.sh" "${SHARED_DIR}/scripts/check-doc-heading-addendum.sh"
else
  echo "SKIP: 写しが原本と一致する: check-doc-heading-addendum.sh（原本が無い）"
fi
if [ -n "$SETUP_DIR" ] && [ -f "${SETUP_DIR}/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh" ]; then
  run_case "写しが原本と一致する: check-unit-test-design-doc-sections.sh" cmp_ignoring_notice "${SETUP_DIR}/quality-assurance/test-policy/check-unit-test-design-doc-sections.sh" "${SHARED_DIR}/scripts/check-unit-test-design-doc-sections.sh"
else
  echo "SKIP: 写しが原本と一致する: check-unit-test-design-doc-sections.sh（原本が無い）"
fi
if [ -n "$DESIGN_DIR" ] && [ -f "${DESIGN_DIR}/リバースの流れの設計.md" ]; then
  run_case "工程の担当欄の機能が実在しoutputsが出力欄と対応する" process_function_mapping_ok "${DESIGN_DIR}/リバースの流れの設計.md" "${SHARED_DIR}/.."
else
  echo "SKIP: 工程の担当欄の機能が実在しoutputsが出力欄と対応する（原本のdocs/design/commonが無い）"
fi

echo "実行 ${total} 件 / 失敗 ${fail} 件"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
