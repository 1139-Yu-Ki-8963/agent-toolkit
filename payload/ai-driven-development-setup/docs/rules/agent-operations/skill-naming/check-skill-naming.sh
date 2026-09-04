#!/usr/bin/env bash
# timing: PreToolUse(Write|Edit|MultiEdit)
set -euo pipefail

# check-skill-naming.sh — docs/skills/ 配下の機能の名前を検査する
#
# 規約の定義: docs/rules/agent-operations/skill-naming/rule.md
#
# 目的:
#   docs/skills/<名前>/ の名前とSKILL.mdの front matter を読み、規約の
#   「## 規則」表が定める7規則（単位・作業・対象の3語／動詞の一覧／種別の不在／
#   文脈語の不在／共有部品の形／3か所一致と日本語名）を検査する。
#
# 使い方:
#   check-skill-naming.sh <docs/skills のルート>   （CLI。動作確認・CI用）
#   check-skill-naming.sh                          （hook呼び出し。引数無し。
#                                                    標準入力へフックのJSONが渡る）
#   check-skill-naming.sh --self-test
#
# hook呼び出し（PreToolUse(Write|Edit|MultiEdit)として登録される）:
#   派生（build-derived-rules.sh）は checkable:true の規約を settings.json 等へ
#   PreToolUse hook として登録する。この経路では引数は渡らず、標準入力へ
#   フックのJSON（tool_input.file_path を含む。file_path は絶対パス）が渡る。
#   file_path から docs/skills を含む祖先パスを求めて検査する。file_path が
#   docs/skills 配下を指していない場合は対象外として何もしない（無関係な
#   書き込みを誤って止めないため）。
#
# 終了コードの意味（2種類の呼び出し経路で意味が異なる。
#   .claude/rules/always/tasks/commit-issue-trace/rule.md「終了コードの意味衝突」の
#   節が記す先例と同じ注意が要る）:
#
#   CLI（引数でルートを渡した場合）:
#     0 = 走査対象の全フォルダが7規則を満たす
#     1 = 1件以上の不合格（標準エラーへ [FAIL] 行を列挙）
#     2 = ルートが存在しない、または走査対象が0件（判定不能。
#         .claude/rules/always/verification/indeterminate-result/rule.md に従う）
#
#   hook（引数無しで呼んだ場合。この経路の終了コード2は
#   「ツール呼び出しを止める」ことを意味するため、上記の「判定不能」と衝突する）:
#     0 = 対象外（docs/skills 配下への書き込みでない、標準入力が空、
#         jqが無い、file_pathが取れない）、または合格
#     2 = 不合格（[HOOK-BLOCK] を stderr へ出し、ツール呼び出しを止める）
#     判定不能（動詞一覧が読めない等）はhookとしては止めず終了コード0で通す
#
# 動詞の一覧は本ファイルと同じフォルダの rule.md の「## 動詞の一覧」節から読む
# （スクリプトへ複製しない）。読めない場合はCLIでは [UNKNOWN] を出し終了コード2、
# hookでは判定不能として終了コード0（止めない）。
#
# 保守責任者: 人手（ユーザー）。規則を増減する場合は rule.md と本スクリプトを
#   同時に更新する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE_FILE="${SCRIPT_DIR}/rule.md"

KIND_WORDS="screen api table batch report external feature message"
CONTEXT_WORDS="claude cursor codex docs"
UNIT_WORDS="setup reverse verify portal operate"

# --- front matter の最小読み取り（validate-rule-definitions.sh の
#     fm_extract/fm_get_scalar と同じ発想の簡約版。他機能のスクリプトを
#     source せず本ファイル単体で完結させる） ---
fm_extract() {
  local file="$1"
  local first_line
  first_line="$(head -n1 "$file" 2>/dev/null || true)"
  [ "$first_line" = "---" ] || return 1
  awk 'NR==1{next} /^---$/{exit} {print}' "$file"
}

fm_scalar() {
  local body="$1" key="$2"
  printf '%s\n' "$body" | awk -v k="$key" '
    index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }
  '
}

# rule.md の「## 動詞の一覧」節から動詞を読む。標準出力へ
# "・deriving・scaffolding・...・handling・" の形（前後に区切り文字）で返す。
load_verbs() {
  local rule_file="$1"
  [ -f "$rule_file" ] || return 1
  # 「## 動詞の一覧」の直後にある "- <動詞>" 形式の箇条書きを読む
  # （1文が長くなりすぎるため、動詞の並びを「・」区切りの1行ではなく
  # 箇条書きで書いている。this規約 rule.md の「## 動詞の一覧」節を参照）。
  local block
  block="$(awk '
    /^## 動詞の一覧$/ { f = 1; next }
    f && /^## / { exit }
    f && /^- / { print }
  ' "$rule_file")"
  [ -n "$block" ] || return 1
  local verbs
  verbs="$(printf '%s\n' "$block" | sed -E 's/^- +//' | tr -d '`' | tr '\n' '・')"
  [ -n "$verbs" ] || return 1
  printf '・%s' "$verbs"
}

verb_allowed() {
  local tok="$1" verbs_padded="$2"
  case "$verbs_padded" in
    *"・${tok}・"*) return 0 ;;
    *) return 1 ;;
  esac
}

word_in_list() {
  local tok="$1" list="$2"
  local w
  for w in $list; do
    [ "$tok" = "$w" ] && return 0
  done
  return 1
}

# $1: 対象フォルダの絶対（または相対）パス  $2: 動詞一覧（load_verbsの戻り値）
# 標準出力へ [FAIL] 行を列挙する。戻り値: 0=全規則合格 1=1件以上不合格
judge_one() {
  local dir="$1" verbs_padded="$2"
  local name
  name="$(basename "$dir")"
  local fail=0

  case "$name" in
    *-shared)
      if [ -f "${dir}/SKILL.md" ]; then
        echo "[FAIL] ${name}: 共有部品は<単位>-shared: -shared で終わるが SKILL.md が実在する"
        fail=1
      fi
      if [ ! -d "${dir}/tests" ]; then
        echo "[FAIL] ${name}: 共有部品は<単位>-shared: -shared で終わるが tests/ が実在しない"
        fail=1
      fi
      return "$fail"
      ;;
  esac

  local tokens tok_count first_tok second_tok
  tokens="$(printf '%s' "$name" | tr '-' ' ')"
  tok_count="$(printf '%s' "$tokens" | awk '{print NF}')"
  first_tok="$(printf '%s' "$tokens" | awk '{print $1}')"
  second_tok="$(printf '%s' "$tokens" | awk '{print $2}')"

  if ! word_in_list "$first_tok" "$UNIT_WORDS"; then
    echo "[FAIL] ${name}: 単位・作業・対象の3語で組む: 先頭の語 '${first_tok}' が5単位のいずれでもない"
    fail=1
  fi
  if [ "$tok_count" -lt 3 ]; then
    echo "[FAIL] ${name}: 単位・作業・対象の3語で組む: 語が${tok_count}個しかない（3つ以上必要）"
    fail=1
  fi

  if [ -n "$second_tok" ]; then
    if ! verb_allowed "$second_tok" "$verbs_padded"; then
      echo "[FAIL] ${name}: 作業は動詞のing形で表す: 2語目 '${second_tok}' が動詞の一覧に無い"
      fail=1
    fi
  fi

  local tok
  for tok in $tokens; do
    if word_in_list "$tok" "$KIND_WORDS"; then
      echo "[FAIL] ${name}: 種別は名前に入れない: '${tok}' は種別を表す語である"
      fail=1
    fi
  done

  case "$name" in
    *for-*)
      echo "[FAIL] ${name}: 文脈や置き場を表す語を入れない: 'for-' を含む"
      fail=1
      ;;
  esac
  for tok in $tokens; do
    if word_in_list "$tok" "$CONTEXT_WORDS"; then
      echo "[FAIL] ${name}: 文脈や置き場を表す語を入れない: '${tok}' は文脈・置き場を表す語である"
      fail=1
    fi
  done

  if [ ! -f "${dir}/SKILL.md" ]; then
    echo "[FAIL] ${name}: 名前は3か所で一致し日本語名を持つ: SKILL.md が実在しない（-shared でもない）"
    return 1
  fi

  local body v_name v_invocation v_ja v_unit
  body="$(fm_extract "${dir}/SKILL.md")" || body=""
  v_name="$(fm_scalar "$body" name)"
  v_invocation="$(fm_scalar "$body" invocation)"
  v_ja="$(fm_scalar "$body" 日本語名)"
  v_unit="$(fm_scalar "$body" unit)"

  if [ "$v_name" != "$name" ] || [ "$v_invocation" != "$name" ]; then
    echo "[FAIL] ${name}: 名前は3か所で一致し日本語名を持つ: name='${v_name}' invocation='${v_invocation}' がフォルダ名と不一致"
    fail=1
  fi
  if [ -z "$v_ja" ]; then
    echo "[FAIL] ${name}: 名前は3か所で一致し日本語名を持つ: 日本語名が空または未設定"
    fail=1
  fi
  if [ -n "$v_unit" ] && [ "$v_unit" != "$first_tok" ]; then
    echo "[FAIL] ${name}: 単位・作業・対象の3語で組む: 宣言のunit '${v_unit}' が先頭の語 '${first_tok}' と不一致"
    fail=1
  fi

  return "$fail"
}

# docs/skills のルートを実際に走査し、判定不能規約に沿った意味の終了コードを
# 「返す」（exit しない。呼び出し側が CLI と hook のどちらの作法で終了するかを
# 決めるため）。
# $1: docs/skills のルート  $2: explicit(1)/hook(0)
# 戻り値: 0=全件合格  1=1件以上不合格  2=判定不能（動詞一覧が読めない、
#         または explicit時にルート不在か走査対象0件）
do_scan() {
  local root="$1" explicit="$2"
  local verbs_padded
  if ! verbs_padded="$(load_verbs "$RULE_FILE")"; then
    echo "[UNKNOWN] 動詞の一覧を読めません（rule.md: ${RULE_FILE}）" >&2
    return 2
  fi

  local dirs count
  dirs="$(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort || true)"
  count="$(printf '%s\n' "$dirs" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    if [ "$explicit" -eq 1 ]; then
      echo "[UNKNOWN] 走査対象が0件です: ${root}" >&2
      return 2
    fi
    return 0
  fi

  local fail_all=0 d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if ! judge_one "$d" "$verbs_padded"; then
      fail_all=1
    fi
  done <<EOF
$dirs
EOF

  if [ "$fail_all" -ne 0 ]; then
    return 1
  fi
  echo "[OK] ${count} 件のskillが名前の決まりに合格"
  return 0
}

# CLI の明示呼び出し（動作確認・CI 用のバッチ実行）。do_scan の戻り値を
# そのまま終了コードとして使う（0/1/2の意味は判定不能規約のとおり）。
# $1: docs/skills のルート
run_cli_mode() {
  local root="$1"
  if [ ! -d "$root" ]; then
    echo "[UNKNOWN] 対象ディレクトリが存在しません: ${root}" >&2
    exit 2
  fi
  local rc=0
  do_scan "$root" 1 || rc=$?
  exit "$rc"
}

# file_path（絶対パス想定）から docs/skills のルートを取り出す。
# docs/skills を含む祖先パスまでを返す。docs/skills 配下を指していなければ
# 空文字を返し戻り値1。
skills_root_from_path() {
  local path="$1"
  case "$path" in
    */docs/skills/*)
      printf '%s' "${path%%/docs/skills/*}/docs/skills"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# PreToolUse(Write|Edit|MultiEdit) フックとしての起動。引数は無く、標準入力へ
# フックのJSON（tool_input.file_path を含む）が渡る。
#
# 対象外（何もせず終了コード0で通す）:
#   標準入力が空、jqが無い（fail-open）、file_path が取れない、
#   file_path が docs/skills 配下を指していない
#
# 対象内での判定:
#   do_scan の戻り値が 0 のとき終了コード0
#   do_scan の戻り値が 1 のとき hook の作法（終了コード2・stderrへメッセージ）で止める
#   do_scan の戻り値が 2 のとき判定不能。hookとしては止めない（終了コード0）
run_hook_mode() {
  local input
  input="$(cat 2>/dev/null || true)"
  if [ -z "$input" ]; then
    exit 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi
  local file_path
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  if [ -z "$file_path" ]; then
    exit 0
  fi
  local skills_root
  if ! skills_root="$(skills_root_from_path "$file_path")" || [ -z "$skills_root" ]; then
    exit 0
  fi
  local rc=0
  do_scan "$skills_root" 0 || rc=$?
  case "$rc" in
    0) exit 0 ;;
    1)
      echo "[HOOK-BLOCK] skill の名前の決まり（docs/rules/agent-operations/skill-naming/rule.md）に違反しています。上のFAIL行を直してから再実行してください。" >&2
      exit 2
      ;;
    *) exit 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------
_mk_tmp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/check-skill-naming.XXXXXX" 2>/dev/null
}

_write_skill() {
  # $1: dir  $2: name  $3: 日本語名  $4: invocation(空なら$2)  $5: unit(空なら省略)
  local dir="$1" name="$2" ja="$3" invocation="${4:-$2}" unit="${5:-}"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: ${name}"
    echo "日本語名: ${ja}"
    echo "description: \"テスト用。\""
    echo "invocation: ${invocation}"
    echo "type: transform"
    if [ -n "$unit" ]; then
      echo "unit: ${unit}"
    fi
    echo "---"
    echo ""
    echo "## いつ使うか"
  } > "${dir}/SKILL.md"
}

run_self_test() {
  local tmp
  if ! tmp="$(_mk_tmp_dir)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを実行できません（mktempが失敗しました）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  local pass=0 fail=0 _out

  # ケース1: 3語・動詞あり・SKILL.md一致 → 合格
  _write_skill "${tmp}/skills-ok/setup-deriving-rules" "setup-deriving-rules" "規約の派生" "" "setup"
  if bash "${BASH_SOURCE[0]}" "${tmp}/skills-ok" >/dev/null 2>&1; then
    echo "  [PASS] ケース1: 3語・動詞あり・SKILL.md一致で合格"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース1: 合格するはずが不合格になった" >&2
    fail=$((fail + 1))
  fi

  # ケース2: 先頭の語が5単位に無い
  mkdir -p "${tmp}/skills-bad-unit"
  _write_skill "${tmp}/skills-bad-unit/foo-deriving-rules" "foo-deriving-rules" "テスト" "" "foo"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-bad-unit" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '単位・作業・対象の3語で組む'; then
    echo "  [PASS] ケース2: 単位が5つに無いことを検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース2: 単位違反を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース3: 語が2つしかない（対象が無い）
  mkdir -p "${tmp}/skills-2tok"
  _write_skill "${tmp}/skills-2tok/setup-deriving" "setup-deriving" "テスト" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-2tok" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '語が2個しかない'; then
    echo "  [PASS] ケース3: 語が2つしかないことを検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース3: 語数不足を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース4: 2語目が動詞の一覧に無い
  mkdir -p "${tmp}/skills-bad-verb"
  _write_skill "${tmp}/skills-bad-verb/setup-fooing-rules" "setup-fooing-rules" "テスト" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-bad-verb" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '作業は動詞のing形で表す'; then
    echo "  [PASS] ケース4: 動詞一覧に無い語を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース4: 動詞違反を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース5: 種別の語が入っている
  mkdir -p "${tmp}/skills-kind"
  _write_skill "${tmp}/skills-kind/setup-listing-screen-items" "setup-listing-screen-items" "テスト" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-kind" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '種別は名前に入れない'; then
    echo "  [PASS] ケース5: 種別の語を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース5: 種別の混入を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース6: for- を含む
  mkdir -p "${tmp}/skills-for"
  _write_skill "${tmp}/skills-for/setup-deriving-rules-for-x" "setup-deriving-rules-for-x" "テスト" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-for" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q "'for-' を含む"; then
    echo "  [PASS] ケース6: for- の混入を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース6: for- の混入を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース7: 文脈語（docs）が対象語に混入
  mkdir -p "${tmp}/skills-ctx"
  _write_skill "${tmp}/skills-ctx/setup-syncing-docs" "setup-syncing-docs" "テスト" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-ctx" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '文脈や置き場を表す語を入れない'; then
    echo "  [PASS] ケース7: 文脈語の混入を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース7: 文脈語の混入を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース8: 共有部品（正しい形） → 合格
  mkdir -p "${tmp}/skills-shared-ok/setup-shared/tests"
  touch "${tmp}/skills-shared-ok/setup-shared/tests/.gitkeep"
  if bash "${BASH_SOURCE[0]}" "${tmp}/skills-shared-ok" >/dev/null 2>&1; then
    echo "  [PASS] ケース8: 共有部品（SKILL.mdなし・tests あり）で合格"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース8: 正しい共有部品が不合格になった" >&2
    fail=$((fail + 1))
  fi

  # ケース9: 共有部品なのにSKILL.mdを持つ
  mkdir -p "${tmp}/skills-shared-bad1/setup-shared/tests"
  touch "${tmp}/skills-shared-bad1/setup-shared/tests/.gitkeep"
  _write_skill "${tmp}/skills-shared-bad1/setup-shared" "setup-shared" "テスト"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-shared-bad1" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '共有部品は<単位>-shared'; then
    echo "  [PASS] ケース9: 共有部品がSKILL.mdを持つ違反を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース9: SKILL.md混入の共有部品を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース10: 共有部品なのにtestsが無い
  mkdir -p "${tmp}/skills-shared-bad2/setup-shared"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-shared-bad2" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q 'tests/ が実在しない'; then
    echo "  [PASS] ケース10: testsが無い共有部品の違反を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース10: tests不在の共有部品を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース11: フォルダ名とSKILL.mdのname/invocationが不一致
  mkdir -p "${tmp}/skills-mismatch"
  _write_skill "${tmp}/skills-mismatch/setup-deriving-rules" "setup-deriving-other" "テスト" "setup-deriving-other" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-mismatch" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q 'フォルダ名と不一致'; then
    echo "  [PASS] ケース11: name/invocationの不一致を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース11: name/invocationの不一致を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース12: 日本語名が空
  mkdir -p "${tmp}/skills-noja"
  _write_skill "${tmp}/skills-noja/setup-deriving-rules" "setup-deriving-rules" "" "" "setup"
  _out="$(bash "${BASH_SOURCE[0]}" "${tmp}/skills-noja" 2>&1 || true)"
  if printf '%s' "$_out" | grep -q '日本語名が空または未設定'; then
    echo "  [PASS] ケース12: 日本語名の欠落を検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース12: 日本語名欠落を検出できなかった" >&2
    fail=$((fail + 1))
  fi

  # ケース13: 明示ルートで走査対象0件 → [UNKNOWN]・終了コード2
  mkdir -p "${tmp}/skills-empty"
  local rc13=0
  bash "${BASH_SOURCE[0]}" "${tmp}/skills-empty" >/dev/null 2>"${tmp}/case13.err" || rc13=$?
  if [ "$rc13" -eq 2 ] && grep -q '^\[UNKNOWN\]' "${tmp}/case13.err"; then
    echo "  [PASS] ケース13: 明示ルートの0件は[UNKNOWN]・終了コード2"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース13: 明示ルート0件の判定不能扱いにならなかった（rc=${rc13}）" >&2
    fail=$((fail + 1))
  fi

  # hook経路（標準入力にフックのJSONを渡す）のテスト用ヘルパー。
  # $1: file_path の値
  _hook_input_json() {
    local fp="$1"
    printf '{"tool_input":{"file_path":"%s"}}' "$fp"
  }

  # ケース14（hook・合格）: file_pathがdocs/skills配下の適正な機能を指す → 終了コード0
  mkdir -p "${tmp}/hook-ok/docs/skills"
  _write_skill "${tmp}/hook-ok/docs/skills/setup-deriving-rules" "setup-deriving-rules" "規約の派生" "" "setup"
  local rc14=0
  _hook_input_json "${tmp}/hook-ok/docs/skills/setup-deriving-rules/SKILL.md" \
    | bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || rc14=$?
  if [ "$rc14" -eq 0 ]; then
    echo "  [PASS] ケース14: hook経路（JSON入力）で適正な機能は終了コード0"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース14: hook経路で適正な機能を止めた（rc=${rc14}）" >&2
    fail=$((fail + 1))
  fi

  # ケース15（hook・不合格）: file_pathがdocs/skills配下の違反機能を指す
  # → hookの作法で終了コード2・[HOOK-BLOCK]をstderrへ
  mkdir -p "${tmp}/hook-bad/docs/skills"
  _write_skill "${tmp}/hook-bad/docs/skills/foo-deriving-rules" "foo-deriving-rules" "テスト" "" "foo"
  local rc15=0 out15
  set +e
  out15="$(_hook_input_json "${tmp}/hook-bad/docs/skills/foo-deriving-rules/SKILL.md" \
    | bash "${BASH_SOURCE[0]}" 2>&1)"
  rc15=$?
  set -e
  if [ "$rc15" -eq 2 ] && printf '%s' "$out15" | grep -q '^\[HOOK-BLOCK\]'; then
    echo "  [PASS] ケース15: hook経路（JSON入力）で違反はhookの作法（終了コード2）で止める"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース15: hook経路で違反を見逃した（rc=${rc15}）" >&2
    fail=$((fail + 1))
  fi

  # ケース16（hook・対象外）: file_pathがdocs/skills配下を指していない → 終了コード0
  local rc16=0
  _hook_input_json "${tmp}/README.md" | bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || rc16=$?
  if [ "$rc16" -eq 0 ]; then
    echo "  [PASS] ケース16: hook経路でdocs/skills対象外のfile_pathは終了コード0"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース16: hook経路で対象外のfile_pathなのに止めた（rc=${rc16}）" >&2
    fail=$((fail + 1))
  fi

  # ケース17（hook・標準入力なし）: 引数無し・標準入力も空 → 終了コード0
  local rc17=0
  bash "${BASH_SOURCE[0]}" < /dev/null >/dev/null 2>&1 || rc17=$?
  if [ "$rc17" -eq 0 ]; then
    echo "  [PASS] ケース17: hook経路で標準入力が空なら終了コード0"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ケース17: 標準入力が空なのに止めた（rc=${rc17}）" >&2
    fail=$((fail + 1))
  fi

  echo "自己テスト結果: 合格 ${pass} 件 / 不合格 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    exit $?
  fi

  if [ $# -ge 1 ]; then
    run_cli_mode "$1"
  fi

  run_hook_mode
}

main "$@"
