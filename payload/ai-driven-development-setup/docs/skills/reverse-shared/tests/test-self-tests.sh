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
BASIC_DESIGN_TEMPLATES_DIR="${SHARED_DIR}/../reverse-writing-basic-design/templates"
if [ -d "$BASIC_DESIGN_TEMPLATES_DIR" ]; then
  BASIC_DESIGN_TEMPLATES_DIR="$(cd "$BASIC_DESIGN_TEMPLATES_DIR" && pwd)"
else
  BASIC_DESIGN_TEMPLATES_DIR=""
fi
SETUP_COPY_DIR=""
if [ -n "$SETUP_DIR" ] && [ -d "${SETUP_DIR}/documentation-standards/customer-facing-adequacy/リバース検証" ]; then
  SETUP_COPY_DIR="$(cd "${SETUP_DIR}/documentation-standards/customer-facing-adequacy/リバース検証" && pwd)"
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
    for elem in ${elems[@]+"${elems[@]}"}; do
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

# 出力配置-規約提案なし: 規約提案の廃止（工程2-10廃止）に伴い、references/の複製と
# docs/design/common/の原本のどちらもoutput-layout.jsonに規約提案の項を持たないことを見る。
output_layout_no_rule_proposal() {
  local ref_count design_count
  ref_count="$(grep -c "規約提案" "${SHARED_DIR}/references/output-layout.json" 2>/dev/null)"
  ref_count="${ref_count:-0}"
  [ "$ref_count" -eq 0 ] || return 1
  if [ -n "$DESIGN_DIR" ] && [ -f "${DESIGN_DIR}/output-layout.json" ]; then
    design_count="$(grep -c "規約提案" "${DESIGN_DIR}/output-layout.json" 2>/dev/null)"
    design_count="${design_count:-0}"
    [ "$design_count" -eq 0 ] || return 1
  fi
  return 0
}

# 様式-他種別名(全文走査)で使う定型文パターン。種別名（画面・機能・API・テーブル・
# バッチ・帳票・外部連携）を`・`・`と`・`/`で2つ以上並べた列挙を検出する
# （第1回改善指示書1-20・再検証。check-basic-design.shの同名パターンの写し。
# 走査対象のツリーが異なるため独立に持つ）。
CROSS_KIND_ENUM_PATTERN='(画面|機能|API|テーブル|バッチ|帳票|外部連携)[[:space:]]*(・|と|/)[[:space:]]*(画面|機能|API|テーブル|バッチ|帳票|外部連携)'

# 様式-他種別名(全文走査): 1行に列挙パターンが現れ、かつ自分の種別以外の名前を
# 含む場合に不合格とする。
# $1: 判定する1行  $2: 自分の種別の名前（1語）
# 戻り値: 0=違反なし 1=違反あり
assert_no_cross_kind_enumeration_line() {
  local line="$1" own="$2" matched m stripped name
  matched="$(printf '%s' "$line" | grep -oE "$CROSS_KIND_ENUM_PATTERN")" || return 0
  [ -n "$matched" ] || return 0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    stripped="${m//$own/}"
    for name in 画面 機能 API テーブル バッチ 帳票 外部連携; do
      [ "$name" = "$own" ] && continue
      case "$stripped" in
        *"$name"*) return 1 ;;
      esac
    done
  done <<CROSSMATCHED
$matched
CROSSMATCHED
  return 0
}

# 様式-他種別名(全文走査): ファイル全体を対象に上記の判定を行う。
# $1: 判定するファイル  $2: 自分の種別の名前（1語。空文字可）
# 標準エラー出力: 違反行を1行ずつ出す（再現・確認のため）
# 戻り値: 0=違反なし 1=違反あり
assert_no_cross_kind_enumeration_file() {
  local file="$1" own="$2" line ok=0
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if ! assert_no_cross_kind_enumeration_line "$line" "$own"; then
      echo "[FAIL] 様式-他種別名(全文): ${file}: ${line}" >&2
      ok=1
    fi
  done < "$file"
  return "$ok"
}

# 写しの全ファイル（$1 配下の全*.md）を対象に、トップレベルのフォルダ名から
# 自分の種別を決めて全文走査する（第1回改善指示書1-20・再検証。レビュー指摘に
# より、アンカー行突合だけでは「複数の機能・APIの連携」等の検出漏れがあった
# ため追加）。「プロジェクト共通」配下は複数の種別に触れる文書であり列挙が
# 正当なため、走査の対象から外す（第1回改善指示書1-20・再検証）。
setup_copy_enumeration_ok() {
  local copy_dir="$1" all_ok=1 top f own
  for top in 画面 API テーブル バッチ 帳票 外部連携 機能; do
    [ -d "${copy_dir}/${top}" ] || continue
    own="$top"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if ! assert_no_cross_kind_enumeration_file "$f" "$own"; then
        all_ok=0
      fi
    done <<FILELIST
$(find "${copy_dir}/${top}" -type f -name '*.md' 2>/dev/null)
FILELIST
  done
  [ "$all_ok" -eq 1 ]
}

cmp_anchor_line() {
  # 原本と写しの、指定パターンにマッチする最初の行が一致するかを見る
  local pattern="$1" file_a="$2" file_b="$3" line_a line_b
  line_a="$(grep -h -- "$pattern" "$file_a" 2>/dev/null | head -n1)"
  line_b="$(grep -h -- "$pattern" "$file_b" 2>/dev/null | head -n1)"
  [ -n "$line_a" ] && [ -n "$line_b" ] && [ "$line_a" = "$line_b" ]
}

unit_test_design_anchor_lines_match() {
  # 7種別の単体テスト設計書について、「外部結合」の行（全種別が持つ）と
  # 「本書が扱わない範囲」の文（接続窓口=API以外の6種別が持つ。APIは表形式で
  # 別途あるため対象外）が、原本(reverse-writing-basic-design)と
  # setup-scaffolding-rulesが配る写しとで行単位で一致することを見る。写しは
  # 文体（である調／です・ます調）が原本と異なるため、本文全体ではなく
  # この2つのアンカー行だけをフレーズが揃っているか確かめる
  # （第1回改善指示書1-20・再検証）。
  local basic_dir="$1" setup_dir="$2" all_ok=1
  local pairs="
画面|screen/画面/テスト設計/画面単体テスト設計書.md|画面/テスト設計/画面単体テスト設計書.md
API|api/API単体テスト設計書.md|API/API単体テスト設計書.md
テーブル|table/テーブル単体テスト設計書.md|テーブル/テーブル単体テスト設計書.md
バッチ|batch/バッチ単体テスト設計書.md|バッチ/バッチ単体テスト設計書.md
帳票|report/帳票単体テスト設計書.md|帳票/帳票単体テスト設計書.md
外部連携|external/外部連携単体テスト設計書.md|外部連携/外部連携単体テスト設計書.md
機能|feature/機能単体テスト設計書.md|機能/機能単体テスト設計書.md
"
  local kind orig_rel copy_rel orig_file copy_file
  while IFS='|' read -r kind orig_rel copy_rel; do
    [ -n "$kind" ] || continue
    orig_file="${basic_dir}/${orig_rel}"
    copy_file="${setup_dir}/${copy_rel}"
    if [ ! -f "$orig_file" ] || [ ! -f "$copy_file" ]; then
      echo "[FAIL] 様式-写し不在: ${kind}" >&2
      all_ok=0
      continue
    fi
    if ! cmp_anchor_line '外部結合 |' "$orig_file" "$copy_file"; then
      echo "[FAIL] 様式-外部結合行不一致: ${kind}" >&2
      all_ok=0
    fi
    if [ "$kind" != "API" ]; then
      if ! cmp_anchor_line 'にまたがる結合テスト' "$orig_file" "$copy_file"; then
        echo "[FAIL] 様式-本書が扱わない範囲文不一致: ${kind}" >&2
        all_ok=0
      fi
    fi
  done <<< "$pairs"
  # 旧定型文「複数の画面・機能・API」の複製が写しの置き場にも残っていないことを見る
  # （check-basic-design.shの同名検査は原本の置き場だけを見るため、写しの置き場は
  # ここで見る。第1回改善指示書1-20・再検証）。「プロジェクト共通」配下は複数の
  # 種別に触れる文書であり列挙が正当なため対象から外す（第1回改善指示書1-20・
  # 再検証）。
  local setup_phrase_hits
  setup_phrase_hits="$(grep -rn '複数の画面・機能・API' "$setup_dir" 2>/dev/null | grep -v '/プロジェクト共通/' | wc -l | tr -d ' ')"
  if [ "${setup_phrase_hits:-0}" -ne 0 ]; then
    echo "[FAIL] 様式-他種別名: 旧定型文「複数の画面・機能・API」の複製が写しに残っている（${setup_phrase_hits}件）" >&2
    all_ok=0
  fi
  [ "$all_ok" -eq 1 ]
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
# 第1回改善指示書1-35追記: 全機能のSKILL.mdが書くコマンドを実際に走らせ、
# 使い方の誤り・要確認-判定不能・異常終了のいずれにも該当しないことを確かめる。
run_case "全機能の手順書のコマンドに引数不足が無い" bash "${SCRIPT_DIR}/test-skill-commands.sh" "${SHARED_DIR}/.."
if [ -n "$DESIGN_DIR" ]; then
  run_case "定義と複製が一致する: unit-kinds.json" cmp -s "${DESIGN_DIR}/unit-kinds.json" "${SHARED_DIR}/references/unit-kinds.json"
  run_case "定義と複製が一致する: output-layout.json" cmp -s "${DESIGN_DIR}/output-layout.json" "${SHARED_DIR}/references/output-layout.json"
  run_case "定義と複製が一致する: code-reading-items.json" cmp -s "${DESIGN_DIR}/code-reading-items.json" "${SHARED_DIR}/references/code-reading-items.json"
else
  echo "SKIP: 定義と複製が一致する: unit-kinds.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: output-layout.json（原本のdocs/design/commonが無い）"
  echo "SKIP: 定義と複製が一致する: code-reading-items.json（原本のdocs/design/commonが無い）"
fi
run_case "出力配置-規約提案なし: output-layout.jsonに規約提案の項が無い" output_layout_no_rule_proposal
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
if [ -n "$BASIC_DESIGN_TEMPLATES_DIR" ] && [ -n "$SETUP_COPY_DIR" ]; then
  run_case "写しが原本と一致する: 単体テスト設計書のアンカー行（7種別）" unit_test_design_anchor_lines_match "$BASIC_DESIGN_TEMPLATES_DIR" "$SETUP_COPY_DIR"
else
  echo "SKIP: 写しが原本と一致する: 単体テスト設計書のアンカー行（7種別）（原本または写しが無い）"
fi
if [ -n "$DESIGN_DIR" ] && [ -f "${DESIGN_DIR}/リバースの流れの設計.md" ]; then
  run_case "工程の担当欄の機能が実在しoutputsが出力欄と対応する" process_function_mapping_ok "${DESIGN_DIR}/リバースの流れの設計.md" "${SHARED_DIR}/.."
else
  echo "SKIP: 工程の担当欄の機能が実在しoutputsが出力欄と対応する（原本のdocs/design/commonが無い）"
fi
if [ -n "$SETUP_COPY_DIR" ]; then
  run_case "写しの全ファイルに自分の種別以外の名前を含む列挙が無い" setup_copy_enumeration_ok "$SETUP_COPY_DIR"
else
  echo "SKIP: 写しの全ファイルに自分の種別以外の名前を含む列挙が無い（写しが無い）"
fi

# 再発防止: 全文走査が実際に列挙を検出できること（検出漏れの退行を防ぐ）
enum_negative_detected() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/reverse-shared-enum-negative.XXXXXX")"
  printf '## 見出し\n複数の機能・APIの連携はここに書かない。\n' > "${dir}/negative.md"
  assert_no_cross_kind_enumeration_file "${dir}/negative.md" "画面" 2>/dev/null
  local rc=$?
  rm -rf "$dir"
  [ "$rc" -eq 1 ]
}
run_case "様式-他種別名(全文走査): 列挙を含む行は不合格になる（再発防止）" enum_negative_detected

echo "実行 ${total} 件 / 失敗 ${fail} 件"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
