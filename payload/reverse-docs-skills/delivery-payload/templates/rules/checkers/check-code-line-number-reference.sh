#!/usr/bin/env bash
# ポータル・設計文書・規約定義へ保守不能な対象コード行番号を書かせない。
set -uo pipefail

LINE_REF_RE='[A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]*:[0-9]+'

judge() {
  local content="$1" normalized hit
  normalized="$(printf '%s\n' "$content" | LC_ALL=C perl -pe 's{https?://[^[:space:]"<>]+}{}g')"
  hit="$(printf '%s\n' "$normalized" | LC_ALL=C grep -oE "$LINE_REF_RE" | head -1)"
  if [ -n "$hit" ]; then
    printf '%s\n' "不合格: 対象コードの行番号を検出した（${hit}）。参照はファイルパスと関数名までにする"
    return 2
  fi
  printf '%s\n' "合格: 対象コードの行番号は無い"
  return 0
}

self_test() {
  local test_dir rc=0 msg code
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/check-code-line-number-reference.XXXXXX")" || return 1
  trap "rm -rf '$test_dir'" EXIT

  for value in 'src/api/client.ts:42' 'lib/task.py:7' 'scripts/build.sh:120'; do
    if msg="$(judge "$value")"; then code=0; else code=$?; fi
    if [ "$code" -eq 2 ]; then
      printf '%s\n' "[PASS] 検出: ${value}"
    else
      printf '%s\n' "[FAIL] 未検出: ${value} (${msg})" >&2
      rc=1
    fi
  done

  for value in '12:30' 'https://example.com:8080/path' 'key: value' 'src/api/client.ts' 'client関数'; do
    if msg="$(judge "$value")"; then code=0; else code=$?; fi
    if [ "$code" -eq 0 ]; then
      printf '%s\n' "[PASS] 非対象: ${value}"
    else
      printf '%s\n' "[FAIL] 誤検出: ${value} (${msg})" >&2
      rc=1
    fi
  done

  printf '%s\n' "self-test: PASS=$((8 - rc)) FAIL=${rc}"
  return "$rc"
}

run_hook() {
  local input content msg code
  input="$(cat)"
  [ -z "$input" ] && return 0
  content="$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)"
  [ -z "$content" ] && return 0
  if msg="$(judge "$content")"; then code=0; else code=$?; fi
  [ "$code" -eq 0 ] && return 0
  printf '%s\n' "[CODE-LINE-NUMBER-REFERENCE-BLOCK] ${msg}" >&2
  return 2
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  run_hook
fi
