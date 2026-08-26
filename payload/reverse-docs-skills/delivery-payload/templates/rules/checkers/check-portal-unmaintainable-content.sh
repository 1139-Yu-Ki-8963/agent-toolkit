#!/usr/bin/env bash
# ポータルと設計書へ根拠列または対象コードの写しを載せない。
set -uo pipefail

STRICT=0

judge_content() {
  local content="$1" source="$2" hits=0
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '\|[[:space:]]*(根拠|根拠パス)[[:space:]]*\|'; then
    printf '%s\n' "[FOUND] ${source}: 根拠列または根拠パス列"
    hits=$((hits + 1))
  fi
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '<pre[^>]*>[[:space:]]*<code|(^|[[:space:]])```[[:alnum:]_-]*[[:space:]]*$'; then
    printf '%s\n' "[FOUND] ${source}: コード柵または pre code"
    hits=$((hits + 1))
  fi
  if printf '%s\n' "$content" | LC_ALL=C grep -qE '`[^`]*(=>|==|!=|[[:space:]]=[[:space:]]|;|\{|\})[^`]*`'; then
    printf '%s\n' "[FOUND] ${source}: インラインまたは表セル内の実装断片"
    hits=$((hits + 1))
  fi
  return "$hits"
}

scan_path() {
  local target="$1" file found=0 code
  if [ -f "$target" ]; then
    if judge_content "$(cat "$target")" "$target"; then :; else found=1; fi
  elif [ -d "$target" ]; then
    while IFS= read -r file; do
      case "$file" in
        */rules/checkers/*|*/rules/tool-defined/*|*/docs/rules/*) continue ;;
      esac
      if judge_content "$(cat "$file")" "$file"; then code=0; else code=$?; fi
      [ "$code" -eq 0 ] || found=1
    done < <(find "$target" -type f \( -name '*.md' -o -name '*.html' \) -print)
  else
    printf '%s\n' "ERROR: 対象が見つからない: $target" >&2
    return 2
  fi
  return "$found"
}

self_test() {
  local failures=0 output code
  for value in "| 項目 | 根""拠 |" "| 項目 | 根""拠パス |" '```js
const copied = true;
```' '<pre><code>copied()</code></pre>' '| 算出 | `total = price * quantity` |'; do
    if output="$(judge_content "$value" fixture)"; then code=0; else code=$?; fi
    if [ "$code" -gt 0 ]; then printf '%s\n' '[PASS] 禁止対象を検出'; else printf '%s\n' "[FAIL] 未検出: $value"; failures=$((failures + 1)); fi
  done
  for value in '| 項目 | 参照先 |' '`src/service.ts` の processOrder 関数' '注文が有効なら処理を続ける'; do
    if output="$(judge_content "$value" fixture)"; then code=0; else code=$?; fi
    if [ "$code" -eq 0 ]; then printf '%s\n' '[PASS] 許可対象'; else printf '%s\n' "[FAIL] 誤検出: $value ($output)"; failures=$((failures + 1)); fi
  done
  printf '%s\n' "SELF-TEST: $((8 - failures)) PASS, ${failures} FAIL"
  [ "$failures" -eq 0 ]
}

run_hook() {
  local input content output code
  input="$(cat)"
  [ -z "$input" ] && return 0
  content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)"
  [ -z "$content" ] && return 0
  if output="$(judge_content "$content" '書き込み内容')"; then code=0; else code=$?; fi
  [ "$code" -eq 0 ] && return 0
  printf '%s\n' "[PORTAL-UNMAINTAINABLE-CONTENT-BLOCK] ${output}" >&2
  return 2
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "${1:-}" = "--hook" ]; then
  run_hook
  exit $?
fi

if [ "${1:-}" = "--strict" ]; then
  STRICT=1
  shift
fi

if [ "$#" -eq 0 ]; then
  run_hook
  exit $?
fi

found=0
for target in "$@"; do
  if scan_path "$target"; then :; else code=$?; [ "$code" -eq 2 ] && exit 2; found=1; fi
done

if [ "$found" -eq 0 ]; then
  printf '%s\n' '合格: 根拠列とコードの中身は無い'
  exit 0
fi
if [ "$STRICT" -eq 1 ]; then
  printf '%s\n' '不合格: ポータルで保守できない内容を検出した' >&2
  exit 2
fi
printf '%s\n' '報告: 既存違反を検出した。--strict では不合格になる'
exit 0
