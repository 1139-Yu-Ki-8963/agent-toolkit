#!/usr/bin/env bash
# rule.md の「機械強制」表が示すスクリプトの実在と hook 登録を照合する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

make_temp_dir() {
  local label="$1"
  local temp_dir
  if ! temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/${label}.XXXXXX" 2>/dev/null)" || [ -z "$temp_dir" ]; then
    unknown "一時ディレクトリを作成できないため判定できません"
  fi
  printf '%s\n' "$temp_dir"
}

extract_declarations() {
  local repo_root="$1"
  find "$repo_root/.claude/rules" -name rule.md -type f -print0 2>/dev/null |
    LC_ALL=C sort -z |
    xargs -0 awk '
      FNR == 1 { in_section = 0 }
      /^## 機械強制[[:space:]]*$/ { in_section = 1; next }
      in_section && /^## / { in_section = 0 }
      in_section && /^\|/ {
        count = split($0, col, "|")
        if (count < 4) next
        timing = col[2]
        script = col[3]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", timing)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", script)
        gsub(/`/, "", script)
        if (timing == "timing" || timing ~ /^-+$/ || script == "") next
        split(script, part, /[[:space:]]+/)
        print FILENAME "\t" timing "\t" part[1]
      }
    '
}

resolve_script() {
  local repo_root="$1"
  local rule_file="$2"
  local declared="$3"
  local candidate

  if [[ "$declared" == */* ]]; then
    candidate="$repo_root/$declared"
    [ -f "$candidate" ] && printf '%s\n' "$candidate"
    return
  fi

  candidate="$(dirname "$rule_file")/$declared"
  [ -f "$candidate" ] && printf '%s\n' "$candidate"
}

hook_registration_exists() {
  local settings="$1"
  local timing="$2"
  local script_name="$3"
  local event matcher
  local matcher_timing_pattern='^([A-Za-z]+)\(([^)]*)\)$'
  local event_timing_pattern='^(Stop|UserPromptSubmit|SessionStart|SessionEnd|Notification)$'

  if [[ "$timing" =~ $matcher_timing_pattern ]]; then
    event="${BASH_REMATCH[1]}"
    matcher="${BASH_REMATCH[2]}"
  elif [[ "$timing" =~ $event_timing_pattern ]]; then
    event="${BASH_REMATCH[1]}"
    matcher=""
  else
    return 2
  fi

  jq -e --arg event "$event" --arg matcher "$matcher" --arg script "$script_name" '
    (.hooks[$event] // [])
    | any(
        ((if $matcher == "" then true else (.matcher // "") == $matcher end))
        and any(.hooks[]?; ((.command // "") | split("/") | last) == $script)
      )
  ' "$settings" >/dev/null
}

run_check() {
  local repo_root="$1"
  local rules_dir="$repo_root/.claude/rules"
  local settings="$repo_root/.claude/settings.json"
  local temp_dir declarations unique_declarations
  local rule_file timing declared resolved rc
  local declared_count=0 exists_count=0 registered_count=0
  local hook_count=0 non_hook_count=0 missing_both_count=0
  local missing_script_count=0 missing_registration_count=0

  [ -d "$rules_dir" ] || unknown "$rules_dir が実在しません"
  [ -f "$settings" ] || unknown "$settings が実在しません"
  command -v jq >/dev/null 2>&1 || unknown "jq が無いため settings.json を判定できません"
  jq -e . "$settings" >/dev/null 2>&1 || unknown "settings.json を JSON として読めません"

  temp_dir="$(make_temp_dir check-rule-machine-enforcement-registration)" || return $?
  trap 'rm -rf "$temp_dir"' RETURN
  declarations="$temp_dir/declarations.tsv"
  unique_declarations="$temp_dir/unique.tsv"

  extract_declarations "$repo_root" >"$declarations"
  awk -F '\t' '!seen[$2 FS $3]++' "$declarations" >"$unique_declarations"

  while IFS=$'\t' read -r rule_file timing declared; do
    [ -n "$declared" ] || continue
    declared_count=$((declared_count + 1))
    resolved="$(resolve_script "$repo_root" "$rule_file" "$declared")"
    if [ -n "$resolved" ]; then
      exists_count=$((exists_count + 1))
    else
      missing_script_count=$((missing_script_count + 1))
      echo "[FAIL] スクリプト不在: ${declared} (${rule_file#$repo_root/})" >&2
    fi

    if hook_registration_exists "$settings" "$timing" "$(basename "$declared")"; then
      registered_count=$((registered_count + 1))
      hook_count=$((hook_count + 1))
    else
      rc=$?
      if [ "$rc" -eq 2 ]; then
        non_hook_count=$((non_hook_count + 1))
      else
        hook_count=$((hook_count + 1))
        missing_registration_count=$((missing_registration_count + 1))
        echo "[FAIL] hook未登録: ${timing} ${declared}" >&2
      fi
    fi

    if [ -z "$resolved" ]; then
      hook_registration_exists "$settings" "$timing" "$(basename "$declared")"
      rc=$?
      [ "$rc" -eq 2 ] || [ "$rc" -eq 0 ] || missing_both_count=$((missing_both_count + 1))
    fi
  done <"$unique_declarations"

  echo "機械強制表の固有スクリプト: ${declared_count}"
  echo "実在するスクリプト: ${exists_count}"
  echo "settings.json 登録対象の hook スクリプト: ${hook_count}"
  echo "settings.json に登録済み: ${registered_count}"
  echo "hook 登録対象外（手動・集約実行）: ${non_hook_count}"
  echo "スクリプト不在: ${missing_script_count}"
  echo "hook 登録漏れ: ${missing_registration_count}"
  echo "実在・登録の両方が欠ける hook: ${missing_both_count}"

  [ "$missing_script_count" -eq 0 ] && [ "$missing_registration_count" -eq 0 ]
}

write_fixture() {
  local root="$1"
  local with_script="$2"
  local with_registration="$3"
  mkdir -p "$root/.claude/rules/always/sample/check-sample"
  cat >"$root/.claude/rules/always/sample/check-sample/rule.md" <<'EOF'
## 機械強制

| timing | スクリプト | 注入タグ | 挙動 |
|---|---|---|---|
| PreToolUse(Bash) | `check-sample.sh` | `[SAMPLE-BLOCK]` | 不合格を止める |
EOF
  if [ "$with_script" = yes ]; then
    printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.claude/rules/always/sample/check-sample/check-sample.sh"
  fi
  if [ "$with_registration" = yes ]; then
    cat >"$root/.claude/settings.json" <<'EOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/rules/always/sample/check-sample/check-sample.sh"}]}]}}
EOF
  else
    printf '%s\n' '{"hooks":{}}' >"$root/.claude/settings.json"
  fi
}

run_self_test() {
  local temp_dir out rc pass=0 fail=0
  temp_dir="$(make_temp_dir check-rule-machine-enforcement-registration-self-test)" || return $?
  trap 'rm -rf "$temp_dir"' RETURN

  write_fixture "$temp_dir/valid" yes yes
  if out="$(run_check "$temp_dir/valid" 2>&1)" && grep -q 'settings.json に登録済み: 1' <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "[FAIL] 正常な宣言と登録: $out" >&2
  fi

  write_fixture "$temp_dir/missing-script" no yes
  if out="$(run_check "$temp_dir/missing-script" 2>&1)"; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && grep -q 'スクリプト不在: 1' <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "[FAIL] 不在スクリプトの検出: rc=$rc $out" >&2
  fi

  write_fixture "$temp_dir/missing-registration" yes no
  if out="$(run_check "$temp_dir/missing-registration" 2>&1)"; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && grep -q 'hook 登録漏れ: 1' <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "[FAIL] hook未登録の検出: rc=$rc $out" >&2
  fi

  write_fixture "$temp_dir/missing-both" no no
  if out="$(run_check "$temp_dir/missing-both" 2>&1)"; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && grep -q '実在・登録の両方が欠ける hook: 1' <<<"$out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "[FAIL] 両方が欠けるhookの検出: rc=$rc $out" >&2
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  "") run_check "$DEFAULT_REPO_ROOT" ;;
  --self-test) run_self_test ;;
  --repo-root)
    [ -n "${2:-}" ] || unknown "--repo-root の値がありません"
    run_check "$2"
    ;;
  *) echo "usage: $0 [--self-test | --repo-root <path>]" >&2; exit 2 ;;
esac
