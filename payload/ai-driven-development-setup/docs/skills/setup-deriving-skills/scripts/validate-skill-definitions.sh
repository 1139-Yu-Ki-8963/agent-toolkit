#!/usr/bin/env bash
set -euo pipefail

# validate-skill-definitions.sh — docs/skills/ 配下の機能定義の整合性検査
#
# 目的:
#   docs/skills/<機能名>/SKILL.md の front matter と本体を読み、機能の定義が
#   満たすべき形と欠落を検査する。1件でも不合格なら終了コード1で不合格内容を
#   標準エラーへ列挙する。
#
# 使い方:
#   validate-skill-definitions.sh <docs/skills のルート>
#   validate-skill-definitions.sh --self-test
#
# 検査キー:
#   宣言-鍵欠落      front matter に name・日本語名・description・invocation・type・
#                    allowed-tools・unit・category・kind・inputs・outputs・requires・
#                    acceptance の13鍵すべてがある
#   名前-一致        name とフォルダ名と invocation が同じ
#   接頭辞-不一致    name が setup-/reverse-/verify-/portal-/operate- のいずれかで
#                    始まり、その接頭辞が unit と一致する
#   区分-不正        category が survey・setup・operate のいずれか（支援ツールの3本柱:
#                    調査を支える・基盤一式の作成を支える・現場運用を支える に対応）。
#                    unit が operate なら category は operate。それ以外の unit は
#                    3値のどれでもよい
#   requires-単位不一致  requires の各要素が同じルートに実在し、かつ同じ unit の機能である
#   検収-未整備      acceptance が "tests/" であり、<機能>/tests/ に実行権限を持つ *.sh が
#                    1本以上ある
#   他単位-名前混入  SKILL.md 本体（front matter を除く）と scripts/ 配下の全ファイルに、
#                    自分と異なる単位の接頭辞を持つ機能名らしき文字列が現れない
#   入出力-空        inputs・outputs が空でない配列である（requires は空を許す）
#
# 名前の決まり（agent-operations/skill-naming）との連結:
#   同じルートの兄弟に docs/rules/agent-operations/skill-naming/check-skill-naming.sh
#   が実在する場合だけ、そのファイルへ <docs/skills のルート> を渡して呼ぶ。
#   終了コード1（不合格）なら本検査全体も不合格に数える。実在しない場合は
#   何もしない（本ファイルへ規約の名前や規則の中身は書かず、実在確認だけで
#   結合する）。
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格
#   2 = 走査対象（docs/skills/*/SKILL.md）が1件も無い、またはルート不在、または
#       一時領域の作成に失敗（--self-test のみ）
#
# 保守責任者: 人手（ユーザー）。必須鍵・単位の接頭辞一覧を増減する場合は
#   本スクリプトと docs/skills/setup-deriving-skills/SKILL.md を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXPECTED_KEYS="name 日本語名 description invocation type allowed-tools unit category kind inputs outputs requires acceptance"
UNIT_PREFIXES="setup reverse verify portal operate"

FAILURES=""
FAIL_COUNT=0

add_failure() {
  # $1: 機能名  $2: 検査キー  $3: 詳細
  FAILURES="${FAILURES}[FAIL] ${1}: ${2}: ${3}
"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# front matter本体（1行目と2行目以降の最初の "---" に挟まれた範囲）を取り出す。
fm_extract() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  if [ "$first_line" != "---" ]; then
    return 1
  fi
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
  return 0
}

# front matter本体からファイル末尾（本文）を取り出す。
body_extract() {
  local file="$1"
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$file"
}

fm_get_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
    $0 == k ":" { print ""; exit }
  '
}

fm_has_key() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | grep -qE "^${key}:( |\$)"
}

# 配列値（"key: [...]" の1行表記のみ対応）を取り出す。中身（角括弧を含む）を返す。
fm_get_array_raw() {
  local body="$1" key="$2"
  local line
  line="$(printf '%s\n' "$body" | grep -E "^${key}:" | head -n1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  printf '%s\n' "${line#"${key}: "}"
  return 0
}

is_empty_array() {
  case "$1" in
    "[]") return 0 ;;
    *) return 1 ;;
  esac
}

# "[a, b, c]" 形式から要素を1行1件で取り出す（前後の空白を落とす）
array_elements() {
  local raw="$1"
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -e 's/^ *//' -e 's/ *$//'
}

# name の接頭辞（setup/reverse/verify/portal/operateのいずれか）を返す。無ければ非0で返る。
prefix_of() {
  local name="$1" p
  for p in $UNIT_PREFIXES; do
    case "$name" in
      "${p}-"*) printf '%s' "$p"; return 0 ;;
    esac
  done
  return 1
}

# root配下の指定した機能名のunit値を返す。定義が無ければ非0で返る。
get_unit_of() {
  local root="$1" name="$2" f body
  f="${root}/${name}/SKILL.md"
  [ -f "$f" ] || return 1
  body="$(fm_extract "$f")" || return 1
  fm_get_scalar "$body" unit
}

# 文字列中の他単位接頭辞の混入行を "<label>:<行番号>: <一致文字列>" で列挙する
scan_leaks_in_content() {
  # $1: 内容  $2: 自身のunit  $3: 表示用ラベル
  local content="$1" own_unit="$2" label="$3"
  printf '%s\n' "$content" | grep -noE '\b(setup|reverse|verify|portal|operate)-[a-z0-9-]+' 2>/dev/null | while IFS=: read -r lineno match; do
    local u="${match%%-*}"
    if [ "$u" != "$own_unit" ]; then
      printf '%s:%s: %s\n' "$label" "$lineno" "$match"
    fi
  done
}

validate_one_skill() {
  local dir="$1" root="$2"
  local skill_file="${dir}/SKILL.md"
  local name
  name="$(basename "$dir")"

  if [ ! -f "$skill_file" ]; then
    add_failure "$name" "定義-不在" "SKILL.md が存在しない"
    return
  fi

  local body
  if ! body="$(fm_extract "$skill_file")"; then
    add_failure "$name" "front-matter形式" "1行目が '---' ではないため front matter を認識できない"
    return
  fi

  # 宣言-鍵欠落
  local key missing=""
  for key in $EXPECTED_KEYS; do
    if ! fm_has_key "$body" "$key"; then
      missing="${missing}${key} "
    fi
  done
  if [ -n "$missing" ]; then
    add_failure "$name" "宣言-鍵欠落" "必須13鍵のうち欠落: ${missing}"
  fi

  local v_name v_invocation v_unit v_category v_acceptance
  v_name="$(fm_get_scalar "$body" name)"
  v_invocation="$(fm_get_scalar "$body" invocation)"
  v_unit="$(fm_get_scalar "$body" unit)"
  v_category="$(fm_get_scalar "$body" category)"
  v_acceptance="$(fm_get_scalar "$body" acceptance)"

  # 名前-一致
  if [ "$v_name" != "$name" ] || [ "$v_invocation" != "$name" ]; then
    add_failure "$name" "名前-一致" "name(${v_name:-（空）})・フォルダ名(${name})・invocation(${v_invocation:-（空）})が一致しない"
  fi

  # 接頭辞-不一致
  local prefix
  if prefix="$(prefix_of "$v_name")"; then
    if [ "$prefix" != "$v_unit" ]; then
      add_failure "$name" "接頭辞-不一致" "name の接頭辞(${prefix})と unit(${v_unit:-（空）})が一致しない"
    fi
  else
    add_failure "$name" "接頭辞-不一致" "name(${v_name:-（空）})が setup-/reverse-/verify-/portal-/operate- のいずれでも始まらない"
  fi

  # 区分-不正（値域と unit との整合を1つの検査キーで扱う）
  # category は survey・setup・operate の3値。unit が operate の機能だけ
  # category を operate に固定し、それ以外の unit は3値のどれでもよい。
  case "$v_category" in
    survey|setup|operate)
      if [ "$v_unit" = "operate" ] && [ "$v_category" != "operate" ]; then
        add_failure "$name" "区分-不正" "unit(operate)に対し category は operate であるべきだが実際は ${v_category}"
      fi
      ;;
    *)
      add_failure "$name" "区分-不正" "category(${v_category:-（空）})が survey/setup/operate のいずれでもない"
      ;;
  esac

  # 入出力-空
  local v_inputs_raw v_outputs_raw
  if v_inputs_raw="$(fm_get_array_raw "$body" inputs)"; then
    if is_empty_array "$v_inputs_raw"; then
      add_failure "$name" "入出力-空" "inputs が空配列"
    fi
  fi
  if v_outputs_raw="$(fm_get_array_raw "$body" outputs)"; then
    if is_empty_array "$v_outputs_raw"; then
      add_failure "$name" "入出力-空" "outputs が空配列"
    fi
  fi

  # requires-単位不一致
  local v_requires_raw
  if v_requires_raw="$(fm_get_array_raw "$body" requires)"; then
    if ! is_empty_array "$v_requires_raw"; then
      local elem req_unit
      while IFS= read -r elem; do
        [ -n "$elem" ] || continue
        if [ ! -f "${root}/${elem}/SKILL.md" ]; then
          add_failure "$name" "requires-単位不一致" "requires に挙げた ${elem} の定義が存在しない"
          continue
        fi
        req_unit="$(get_unit_of "$root" "$elem" || true)"
        if [ "$req_unit" != "$v_unit" ]; then
          add_failure "$name" "requires-単位不一致" "requires に挙げた ${elem} は unit(${req_unit:-（空）})で、自身のunit(${v_unit:-（空）})と異なる"
        fi
      done <<REQLIST
$(array_elements "$v_requires_raw")
REQLIST
    fi
  fi

  # 検収-未整備
  if [ "$v_acceptance" != "tests/" ]; then
    add_failure "$name" "検収-未整備" "acceptance(${v_acceptance:-（空）})が 'tests/' ではない"
  else
    if [ ! -d "${dir}/tests" ]; then
      add_failure "$name" "検収-未整備" "tests/ ディレクトリが存在しない"
    else
      local exec_count
      exec_count="$(find "${dir}/tests" -maxdepth 1 -type f -name '*.sh' -perm -u+x 2>/dev/null | grep -c . || true)"
      if [ "${exec_count:-0}" -eq 0 ]; then
        add_failure "$name" "検収-未整備" "tests/ に実行権限を持つ *.sh が1本も無い"
      fi
    fi
  fi

  # 他単位-名前混入（SKILL.md本体 + scripts/配下全ファイル）
  local own_unit="$v_unit" body_only leaks
  body_only="$(body_extract "$skill_file")"
  leaks="$(scan_leaks_in_content "$body_only" "$own_unit" "SKILL.md")" || true
  if [ -d "${dir}/scripts" ]; then
    local f rel content found
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="scripts/${f#"${dir}/scripts/"}"
      content="$(cat "$f" 2>/dev/null || true)"
      found="$(scan_leaks_in_content "$content" "$own_unit" "$rel")" || true
      if [ -n "$found" ]; then
        if [ -n "$leaks" ]; then
          leaks="${leaks}
${found}"
        else
          leaks="$found"
        fi
      fi
    done <<SCRIPTLIST
$(find "${dir}/scripts" -type f | sort)
SCRIPTLIST
  fi
  if [ -n "$leaks" ]; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      add_failure "$name" "他単位-名前混入" "$line"
    done <<LEAKLIST
$leaks
LEAKLIST
  fi
}

run_validate() {
  local root="$1"
  FAILURES=""
  FAIL_COUNT=0

  if [ ! -d "$root" ]; then
    echo "ERROR: ルートディレクトリが存在しません: $root" >&2
    return 2
  fi

  local skill_files
  skill_files="$(find "$root" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | sort)"
  if [ -z "$skill_files" ]; then
    echo "[UNKNOWN] 機能の定義が1件も無い" >&2
    return 2
  fi

  local f dir
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dir="$(dirname "$f")"
    validate_one_skill "$dir" "$root"
  done <<SKILLLIST
$skill_files
SKILLLIST

  # 名前の決まり（agent-operations/skill-naming）の検査。同じルートの兄弟に
  # docs/rules が実在し、その checker が実在する場合だけ呼ぶ。実在しなければ
  # 何もしない（このスクリプトから規約の名前を直書きしない。実在確認だけで
  # 結合する）。
  local naming_checker="${root}/../rules/agent-operations/skill-naming/check-skill-naming.sh"
  if [ -f "$naming_checker" ]; then
    local naming_out naming_rc
    naming_rc=0
    naming_out="$(bash "$naming_checker" "$root" 2>&1)" || naming_rc=$?
    if [ "$naming_rc" -eq 1 ]; then
      local naming_fail_count
      naming_fail_count="$(printf '%s\n' "$naming_out" | grep -c '^\[FAIL\]' || true)"
      FAILURES="${FAILURES}${naming_out}
"
      FAIL_COUNT=$((FAIL_COUNT + naming_fail_count))
    fi
  fi

  local total
  total="$(printf '%s\n' "$skill_files" | grep -c . || true)"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '%s' "$FAILURES" >&2
    echo "[FAIL] 検査不合格: ${FAIL_COUNT} 件" >&2
    return 1
  fi

  echo "[OK] ${total} 件"
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_valid_skill() {
  # $1: root  $2: name  $3: unit  $4: category（省略時はunitから機械的に決める）
  local root="$1" name="$2" unit="$3" category="${4:-}"
  if [ -z "$category" ]; then
    if [ "$unit" = "operate" ]; then category="operate"; else category="setup"; fi
  fi
  local dir="${root}/${name}"
  mkdir -p "${dir}/tests" "${dir}/scripts"
  cat > "${dir}/SKILL.md" <<SKILLEOF
---
name: ${name}
日本語名: テスト用機能
description: "self-test用の機能定義。"
invocation: ${name}
type: transform
allowed-tools: [Bash]
unit: ${unit}
category: ${category}
kind: none
inputs: [docs/skills/${name}/dummy-input]
outputs: [docs/skills/${name}/dummy-output]
requires: []
acceptance: tests/
---

## いつ使うか

self-test用。
SKILLEOF
  cat > "${dir}/tests/test-dummy.sh" <<'TESTEOF'
#!/usr/bin/env bash
exit 0
TESTEOF
  chmod +x "${dir}/tests/test-dummy.sh"
  cat > "${dir}/scripts/dummy.sh" <<SCRIPTEOF2
#!/usr/bin/env bash
# ${name} 用のダミースクリプト
SCRIPTEOF2
}

self_test() {
  local pass=0 fail=0

  local root
  if ! root="$(mktemp -d "${TMPDIR:-/tmp}/validate-skill-definitions-self-test.XXXXXX" 2>/dev/null)" || [ -z "$root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  # ケース1（合格）: 適正な機能定義1件
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  local out1 rc1=0
  out1="$("$0" "$root" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '^\[OK\]'; then
    pass=$((pass+1)); echo "  [PASS] ケース1: 適正な定義は合格（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース1: 適正な定義が合格しない (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース2（宣言-鍵欠落）
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  sed -i.bak '/^kind: /d' "${root}/setup-alpha/SKILL.md" && rm -f "${root}/setup-alpha/SKILL.md.bak"
  local out2 rc2=0
  out2="$("$0" "$root" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q '宣言-鍵欠落'; then
    pass=$((pass+1)); echo "  [PASS] ケース2: 鍵の欠落を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース2: 鍵の欠落を検知しない (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース3（名前-一致）: フォルダ名とinvocationを不一致にする
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  sed -i.bak 's/^invocation: setup-alpha$/invocation: setup-beta/' "${root}/setup-alpha/SKILL.md" && rm -f "${root}/setup-alpha/SKILL.md.bak"
  local out3 rc3=0
  out3="$("$0" "$root" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q '名前-一致'; then
    pass=$((pass+1)); echo "  [PASS] ケース3: 名前の不一致を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース3: 名前の不一致を検知しない (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース4（接頭辞-不一致）: unitとnameの接頭辞をずらす
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  sed -i.bak 's/^unit: setup$/unit: reverse/' "${root}/setup-alpha/SKILL.md" && rm -f "${root}/setup-alpha/SKILL.md.bak"
  local out4 rc4=0
  out4="$("$0" "$root" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 1 ] && printf '%s' "$out4" | grep -q '接頭辞-不一致'; then
    pass=$((pass+1)); echo "  [PASS] ケース4: 接頭辞の不一致を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース4: 接頭辞の不一致を検知しない (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース5（区分-不正）: category が3値（survey/setup/operate）のいずれでもない
  bst_write_valid_skill "$root" "setup-alpha" "setup" "custom"
  local out5 rc5=0
  out5="$("$0" "$root" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 1 ] && printf '%s' "$out5" | grep -q '区分-不正'; then
    pass=$((pass+1)); echo "  [PASS] ケース5: 区分の値域違反を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース5: 区分の値域違反を検知しない (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース6（requires-単位不一致）: setup機能が他単位の機能をrequiresする
  # 注記: 他単位の名前を本ファイルへ直接literalで書くと、本検査自身の
  # 「他単位-名前混入」検査が自分自身のscripts/を走査した際に誤検知するため、
  # ハイフンを変数経由で組み立てて文字列の連続一致を避ける。
  local h6='-'
  local other_unit_name="reverse${h6}beta"
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  bst_write_valid_skill "$root" "$other_unit_name" "reverse"
  sed -i.bak "s/^requires: \\[\\]\$/requires: [${other_unit_name}]/" "${root}/setup-alpha/SKILL.md" && rm -f "${root}/setup-alpha/SKILL.md.bak"
  local out6 rc6=0
  out6="$("$0" "$root" 2>&1)" || rc6=$?
  if [ "$rc6" -eq 1 ] && printf '%s' "$out6" | grep -q 'requires-単位不一致'; then
    pass=$((pass+1)); echo "  [PASS] ケース6: requiresの単位不一致を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース6: requiresの単位不一致を検知しない (exit ${rc6})" >&2
    printf '%s\n' "$out6" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース7（検収-未整備）: tests/を空にする
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  rm -f "${root}/setup-alpha/tests/test-dummy.sh"
  local out7 rc7=0
  out7="$("$0" "$root" 2>&1)" || rc7=$?
  if [ "$rc7" -eq 1 ] && printf '%s' "$out7" | grep -q '検収-未整備'; then
    pass=$((pass+1)); echo "  [PASS] ケース7: テスト不在を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース7: テスト不在を検知しない (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース8（他単位-名前混入）: scripts/配下に他単位の機能名を書く
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  # 注記: 他単位の名前を本ファイルへ直接literalで書くと自己検知するため
  # ハイフンを変数経由で組み立てて文字列の連続一致を避ける。
  local h8='-'
  local other_ref="reverse${h8}extract${h8}screens"
  printf '# %s を呼び出す想定\n' "$other_ref" >> "${root}/setup-alpha/scripts/dummy.sh"
  local out8 rc8=0
  out8="$("$0" "$root" 2>&1)" || rc8=$?
  if [ "$rc8" -eq 1 ] && printf '%s' "$out8" | grep -q '他単位-名前混入'; then
    pass=$((pass+1)); echo "  [PASS] ケース8: 他単位の名前の混入を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース8: 他単位の名前の混入を検知しない (exit ${rc8})" >&2
    printf '%s\n' "$out8" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース9（入出力-空）: inputsを空配列にする
  bst_write_valid_skill "$root" "setup-alpha" "setup"
  sed -i.bak 's/^inputs: \[docs\/skills\/setup-alpha\/dummy-input\]$/inputs: []/' "${root}/setup-alpha/SKILL.md" && rm -f "${root}/setup-alpha/SKILL.md.bak"
  local out9 rc9=0
  out9="$("$0" "$root" 2>&1)" || rc9=$?
  if [ "$rc9" -eq 1 ] && printf '%s' "$out9" | grep -q '入出力-空'; then
    pass=$((pass+1)); echo "  [PASS] ケース9: inputsの空配列を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース9: inputsの空配列を検知しない (exit ${rc9})" >&2
    printf '%s\n' "$out9" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース11（区分-不正・unit=operate強制）: unit=operateなのにcategory=setup
  # 注記: 他単位の名前を本ファイルへ直接literalで書くと、本検査自身の
  # 「他単位-名前混入」検査が自分自身のscripts/を走査した際に誤検知するため、
  # ハイフンを変数経由で組み立てて文字列の連続一致を避ける。
  local h11='-'
  local operate_name="operate${h11}alpha"
  bst_write_valid_skill "$root" "$operate_name" "operate" "setup"
  local out11 rc11=0
  out11="$("$0" "$root" 2>&1)" || rc11=$?
  if [ "$rc11" -eq 1 ] && printf '%s' "$out11" | grep -q '区分-不正'; then
    pass=$((pass+1)); echo "  [PASS] ケース11: unit=operate強制の不整合を検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース11: unit=operate強制の不整合を検知しない (exit ${rc11})" >&2
    printf '%s\n' "$out11" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース12（区分-合格・survey）: unit=reverseでcategory=surveyは合格する
  local h12='-'
  local reverse_name="reverse${h12}alpha"
  bst_write_valid_skill "$root" "$reverse_name" "reverse" "survey"
  local out12 rc12=0
  out12="$("$0" "$root" 2>&1)" || rc12=$?
  if [ "$rc12" -eq 0 ] && printf '%s' "$out12" | grep -q '^\[OK\]'; then
    pass=$((pass+1)); echo "  [PASS] ケース12: unit=reverse・category=surveyは合格（exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース12: unit=reverse・category=surveyが合格しない (exit ${rc12})" >&2
    printf '%s\n' "$out12" | sed 's/^/    /' >&2
  fi
  rm -rf "${root:?}"/*

  # ケース10（走査対象なし）: 定義が1件も無い
  local out10 rc10=0
  out10="$("$0" "$root" 2>&1)" || rc10=$?
  if [ "$rc10" -eq 2 ] && printf '%s' "$out10" | grep -q '\[UNKNOWN\]'; then
    pass=$((pass+1)); echo "  [PASS] ケース10: 定義0件を判定不能として報告（exit 2）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース10: 定義0件の扱いが不正 (exit ${rc10})" >&2
    printf '%s\n' "$out10" | sed 's/^/    /' >&2
  fi

  rm -rf "$root"

  # ケース13（名前の決まりの検査を呼ぶ）: 兄弟に
  # docs/rules/agent-operations/skill-naming/check-skill-naming.sh が実在し、
  # それが不合格（終了コード1）を返すなら validate 自体も不合格にする。
  # checker本体（check-skill-naming.sh）の判定の中身は問わず、呼び出しの
  # 配線だけをスタブで確かめる（本体の正しさは同checkerのself-testが担う）。
  local scratch
  if ! scratch="$(mktemp -d "${TMPDIR:-/tmp}/validate-skill-definitions-naming-hook.XXXXXX" 2>/dev/null)" || [ -z "$scratch" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  mkdir -p "${scratch}/docs/skills" "${scratch}/docs/rules/agent-operations/skill-naming"
  bst_write_valid_skill "${scratch}/docs/skills" "setup-alpha" "setup"
  cat > "${scratch}/docs/rules/agent-operations/skill-naming/check-skill-naming.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "[FAIL] stub-naming: 単位・作業・対象の3語で組む: テスト用の常時不合格"
exit 1
STUBEOF
  chmod +x "${scratch}/docs/rules/agent-operations/skill-naming/check-skill-naming.sh"
  local out13 rc13=0
  out13="$("$0" "${scratch}/docs/skills" 2>&1)" || rc13=$?
  if [ "$rc13" -eq 1 ] && printf '%s' "$out13" | grep -q 'stub-naming'; then
    pass=$((pass+1)); echo "  [PASS] ケース13: 名前の決まりの検査が不合格なら validate も不合格（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース13: 名前の決まりの検査の不合格を反映しない (exit ${rc13})" >&2
    printf '%s\n' "$out13" | sed 's/^/    /' >&2
  fi
  rm -rf "$scratch"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
  return 1
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ $# -ne 1 ]; then
    echo "usage: $(basename "$0") <docs/skills のルート> | --self-test" >&2
    exit 2
  fi

  run_validate "$1"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
