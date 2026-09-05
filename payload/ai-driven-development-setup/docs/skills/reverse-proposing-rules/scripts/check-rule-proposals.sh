#!/usr/bin/env bash
set -uo pipefail
# 見出し・列名の完全一致比較は LC_ALL=C で行う。macOS 標準 awk は UTF-8 ロケールで
# 多バイト文字列の == を誤るため（check-unit-test-design-doc-sections.sh と同じ対処）。
export LC_ALL=C

# check-rule-proposals.sh — confirmations/規約提案.md の形を検査する
#   （reverse-proposing-rulesの実体）
#
# 定義: docs/design/skills/reverse-proposing-rules/基本設計書.md・詳細設計書.md
#
# 使い方:
#   check-rule-proposals.sh <実行フォルダ>
#   check-rule-proposals.sh --check-file <規約提案.md>
#   check-rule-proposals.sh --self-test
#
# 検査キー:
#   節-欠落        「## 観測」「## 判断」「## 観測なし」の見出しが1つでも
#                  無い（空ファイルを含む）
#   出典-不在      「## 判断」の行のキーに対応する「## 観測」の行が無い、
#                  または出典の文書が空
#   提案先-不在    「## 判断」の行の「提案先の規約」が空、または
#                  reverse-shared/references/rule-taxonomy.json の
#                  parent/key の組に無い
#   観測なし-理由欠落 「## 観測なし」の行の理由が空
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#   2 = 使い方の誤り・規約提案.md不在・rule-taxonomy.json不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。様式の節構成を変えるときは、本スクリプトと
#   templates/規約提案.mdと自己テストを同時に直す。
#
# 廃棄条件: 規約提案の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAXONOMY_FILE="${SCRIPT_DIR}/../../reverse-shared/references/rule-taxonomy.json"

usage_error() {
  echo "使い方: check-rule-proposals.sh <実行フォルダ>" >&2
  echo "        check-rule-proposals.sh --check-file <規約提案.md>" >&2
  echo "        check-rule-proposals.sh --self-test" >&2
  exit 2
}

# 「## 見出し」節の表データ行を \037 区切りで返す（見出し・区切り行を除く）
extract_section_rows() {
  local file="$1" heading="$2" ncols="$3"
  awk -v h="$heading" -v ncols="$ncols" '
    $0 == h { insec = 1; hdr = 0; next }
    insec == 1 && /^## / { insec = 0 }
    insec == 1 && /^\|/ {
      line = $0
      sub(/^\|/, "", line); sub(/\|$/, "", line)
      cnt = split(line, cols, "|")
      for (i = 1; i <= cnt; i++) { gsub(/^[ \t]+|[ \t]+$/, "", cols[i]) }
      if (hdr == 0) { hdr = 1; next }
      if (cols[1] ~ /^[-: ]+$/) next
      if (cols[1] ~ /^<.*>$/) next
      out = cols[1]
      for (i = 2; i <= ncols; i++) { out = out "\037" (i <= cnt ? cols[i] : "") }
      print out
    }
  ' "$file"
}

valid_targets() {
  [ -f "$TAXONOMY_FILE" ] || return 1
  command -v jq > /dev/null 2>&1 || return 1
  jq -r '.parents[] | .key as $p | .children[].key as $c | "\($p)/\($c)"' "$TAXONOMY_FILE" 2>/dev/null
}

check_required_sections() {
  local file="$1" h missing=""
  for h in "## 観測" "## 判断" "## 観測なし"; do
    grep -qxF "$h" "$file" 2>/dev/null || missing="${missing}${missing:+、}${h}"
  done
  [ -z "$missing" ] || { echo "$missing"; return 1; }
  return 0
}

check_file() {
  local file="$1"
  [ -f "$file" ] || { echo "[FAIL] 規約提案-不在: ${file}" >&2; return 2; }

  local missing_sections
  if ! missing_sections="$(check_required_sections "$file")"; then
    echo "[FAIL] 節-欠落: 観測・判断・観測なしの見出しが揃っていません（無い見出し: ${missing_sections}）" >&2
    return 1
  fi

  local targets
  targets="$(valid_targets)" || { echo "[FAIL] 規約定義-不在: ${TAXONOMY_FILE}" >&2; return 2; }

  local -a obs_keys=() obs_sources=()
  local line k src
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\037' read -r k src _ <<< "$line"
    obs_keys+=("$k")
    obs_sources+=("$src")
  done < <(extract_section_rows "$file" "## 観測" 4)

  local fail_count=0
  local dkey dtarget drule dcheck djudge found j n src_val
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\037' read -r dkey dtarget drule dcheck djudge <<< "$line"
    if [ -z "$dtarget" ]; then
      echo "[FAIL] 提案先-不在: ${dkey} の提案先の規約が空です" >&2
      fail_count=$((fail_count + 1))
    else
      case ",${targets//$'\n'/,}," in
        *",${dtarget},"*) : ;;
        *)
          echo "[FAIL] 提案先-不在: ${dkey} の提案先「${dtarget}」がrule-taxonomy.jsonにありません" >&2
          fail_count=$((fail_count + 1))
          ;;
      esac
    fi
    found=0
    n="${#obs_keys[@]}"
    for ((j = 0; j < n; j++)); do
      if [ "${obs_keys[$j]}" = "$dkey" ]; then
        found=1
        src_val="${obs_sources[$j]}"
        break
      fi
    done
    if [ "$found" -eq 0 ] || [ -z "${src_val:-}" ]; then
      echo "[FAIL] 出典-不在: ${dkey} に対応する観測行または出典の文書がありません" >&2
      fail_count=$((fail_count + 1))
    fi
    src_val=""
  done < <(extract_section_rows "$file" "## 判断" 5)

  local nkey nreason
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\037' read -r nkey nreason <<< "$line"
    if [ -z "$nreason" ]; then
      echo "[FAIL] 観測なし-理由欠落: ${nkey} の理由が空です" >&2
      fail_count=$((fail_count + 1))
    fi
  done < <(extract_section_rows "$file" "## 観測なし" 2)

  if [ "$fail_count" -gt 0 ]; then
    return 1
  fi
  echo "合格: 規約提案.mdは出典・提案先・観測なしの理由をすべて満たしています"
  return 0
}

# ------------------------------------------------------------------
# self-test
# ------------------------------------------------------------------

self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-proposals-self-test.XXXXXX" 2>/dev/null)" || {
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません" >&2
    exit 2
  }
  trap 'rm -rf "$tmp"' RETURN

  # ケース1: 出典が無い（判断行に対応する観測行が無い）→ 終了コード1
  local f1="${tmp}/1.md"
  cat > "$f1" << 'EOF'
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|

## 判断

| キー | 提案先の規約 | 提案する規則 | 検査の手段 | 判断 |
|---|---|---|---|---|
| 表の名前-接頭辞 | code-standards/naming | 表の名前は接頭辞で始める | 静的解析 | 提案する |

## 観測なし
EOF
  local out1 rc1=0
  out1="$(check_file "$f1" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 1 ] && printf '%s' "$out1" | grep -q '出典-不在'; then
    pass=$((pass + 1)); echo "  [PASS] ケース1: 出典が無ければ終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース1: 出典欠落の検知が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2: 提案先がrule-taxonomy.jsonに無い → 終了コード1
  local f2="${tmp}/2.md"
  cat > "$f2" << 'EOF'
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|
| 表の名前-接頭辞 | 表の名前は接頭辞で始める | 設計書29件 | 29件中29件 |

## 判断

| キー | 提案先の規約 | 提案する規則 | 検査の手段 | 判断 |
|---|---|---|---|---|
| 表の名前-接頭辞 | no-such-parent/no-such-key | 表の名前は接頭辞で始める | 静的解析 | 提案する |

## 観測なし
EOF
  local out2 rc2=0
  out2="$(check_file "$f2" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q '提案先-不在'; then
    pass=$((pass + 1)); echo "  [PASS] ケース2: 提案先がrule-taxonomy.jsonに無ければ終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース2: 提案先不在の検知が不正 (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi

  # ケース3: 観測なしの理由が現れる（正常系。出典・提案先ともに揃い、観測なし行にも理由がある）
  local real_target=""
  if command -v jq > /dev/null 2>&1 && [ -f "$TAXONOMY_FILE" ]; then
    real_target="$(valid_targets | head -n1)"
  fi
  if [ -n "$real_target" ]; then
    local f3="${tmp}/3.md"
    cat > "$f3" << EOF
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|
| 表の名前-接頭辞 | 表の名前は接頭辞で始める | 設計書29件 | 29件中29件 |

## 判断

| キー | 提案先の規約 | 提案する規則 | 検査の手段 | 判断 |
|---|---|---|---|---|
| 表の名前-接頭辞 | ${real_target} | 表の名前は接頭辞で始める | 静的解析 | 提案する |

## 観測なし

| キー | 理由 |
|---|---|
| ${real_target} | 対象コードに該当する慣行が見当たらない |
EOF
    local out3 rc3=0
    out3="$(check_file "$f3" 2>&1)" || rc3=$?
    if [ "$rc3" -eq 0 ]; then
      pass=$((pass + 1)); echo "  [PASS] ケース3: 出典・提案先が揃い観測なしにも理由があれば合格"
    else
      fail=$((fail + 1)); echo "  [FAIL] ケース3: 正常系が不合格 (exit ${rc3})" >&2
      printf '%s\n' "$out3" | sed 's/^/    /' >&2
    fi
  else
    echo "  [SKIP] ケース3: jqまたはrule-taxonomy.jsonが無いため実在する提案先を使う検証を省略"
    pass=$((pass + 1))
  fi

  # ケース4: 観測なしの理由が空 → 終了コード1
  local f4="${tmp}/4.md"
  cat > "$f4" << 'EOF'
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|

## 判断

| キー | 提案先の規約 | 提案する規則 | 検査の手段 | 判断 |
|---|---|---|---|---|

## 観測なし

| キー | 理由 |
|---|---|
| code-standards/naming |  |
EOF
  local out4 rc4=0
  out4="$(check_file "$f4" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 1 ] && printf '%s' "$out4" | grep -q '観測なし-理由欠落'; then
    pass=$((pass + 1)); echo "  [PASS] ケース4: 観測なしの理由が空なら終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース4: 観測なしの理由欠落の検知が不正 (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi

  # ケース5: 規約提案.md自体が無ければ判定不能（終了コード2）
  local out5 rc5=0
  out5="$(check_file "${tmp}/no-such-file.md" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 2 ] && printf '%s' "$out5" | grep -q '規約提案-不在'; then
    pass=$((pass + 1)); echo "  [PASS] ケース5: 規約提案.mdが無ければ判定不能(2)"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース5: 不在検知が不正 (exit ${rc5})" >&2
  fi

  # ケース6: 「## 判断」の見出しが無い（節-欠落）→ 終了コード1
  local f6="${tmp}/6.md"
  cat > "$f6" << 'EOF'
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|

## 観測なし
EOF
  local out6 rc6=0
  out6="$(check_file "$f6" 2>&1)" || rc6=$?
  if [ "$rc6" -eq 1 ] && printf '%s' "$out6" | grep -q '節-欠落'; then
    pass=$((pass + 1)); echo "  [PASS] ケース6: 「## 判断」の見出しが無ければ節-欠落で終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース6: 節欠落の検知が不正 (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi

  # ケース7: 空ファイル → 節-欠落で終了コード1（不在の2とは区別する）
  local f7="${tmp}/7.md"
  : > "$f7"
  local out7 rc7=0
  out7="$(check_file "$f7" 2>&1)" || rc7=$?
  if [ "$rc7" -eq 1 ] && printf '%s' "$out7" | grep -q '節-欠落'; then
    pass=$((pass + 1)); echo "  [PASS] ケース7: 空ファイルは節-欠落で終了コード1"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース7: 空ファイルの検知が不正 (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi

  # ケース8: rule-taxonomy.jsonが無い環境を模す（規約定義-不在で終了コード2）
  local f8="${tmp}/8.md"
  cat > "$f8" << 'EOF'
## 観測

| キー | 観測した慣行 | 出典の文書 | 数え方の条件 |
|---|---|---|---|

## 判断

| キー | 提案先の規約 | 提案する規則 | 検査の手段 | 判断 |
|---|---|---|---|---|

## 観測なし
EOF
  local saved_taxonomy="$TAXONOMY_FILE"
  TAXONOMY_FILE="${tmp}/no-such-taxonomy.json"
  local out8 rc8=0
  out8="$(check_file "$f8" 2>&1)" || rc8=$?
  TAXONOMY_FILE="$saved_taxonomy"
  if [ "$rc8" -eq 2 ] && printf '%s' "$out8" | grep -q '規約定義-不在'; then
    pass=$((pass + 1)); echo "  [PASS] ケース8: rule-taxonomy.json不在は規約定義-不在で終了コード2"
  else
    fail=$((fail + 1)); echo "  [FAIL] ケース8: 規約定義不在の検知が不正 (exit ${rc8})" >&2
    printf '%s\n' "$out8" | sed 's/^/    /' >&2
  fi

  echo "実行 $((pass + fail)) 件 / 合格 ${pass} 件（失敗 ${fail} 件）"
  if [ "$fail" -eq 0 ]; then
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------
# エントリポイント
# ------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "${1:-}" = "--check-file" ]; then
  [ -n "${2:-}" ] || usage_error
  check_file "$2"
  exit $?
fi

[ $# -ge 1 ] || usage_error
RUN_DIR="$1"
[ -d "$RUN_DIR" ] || { echo "[FAIL] 実行フォルダ-不在: ${RUN_DIR}" >&2; exit 2; }
check_file "${RUN_DIR%/}/confirmations/規約提案.md"
exit $?
