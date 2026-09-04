#!/usr/bin/env bash
# ポータル・設計文書・規約定義へ保守不能な対象コード行番号を書かせない。
#
# 判定メッセージに付けた規則名ラベルについて:
#   規約「生成した文書を直接編集しない決まり」（portal-maintenance）は
#   「対象コードの行番号を書かない」という規則を持ち、その検査列は本検査を
#   名指しする。規則と検査の対応を測る検査（validate-rule-judgment-coverage.sh）
#   は、検査スクリプトの中で「拒否」「通知」「許可」「対象外」のいずれかの
#   語に続けて規則名を大括弧で囲んだ形（下記 judge 関数の出力を参照）が
#   出ている箇所を静的に数えるため、ラベルが無いと判定が0件と数えられる。
#   2026-08-28の実測で、本検査はこの形の出力を1件も持たず「不足」（規則4件/
#   判定1件）に数えられていた。規則名は規約の「## 規則」表の値と一字一句
#   同じにする必要がある。
set -uo pipefail

LINE_REF_RE='[A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]*:[0-9]+'

judge() {
  local content="$1" normalized hit
  normalized="$(printf '%s\n' "$content" | LC_ALL=C perl -pe 's{https?://[^[:space:]"<>]+}{}g')"
  hit="$(printf '%s\n' "$normalized" | LC_ALL=C grep -oE "$LINE_REF_RE" | head -1)"
  if [ -n "$hit" ]; then
    printf '%s\n' "拒否[対象コードの行番号を書かない]: 対象コードの行番号を検出した（${hit}）。参照はファイルパスと関数名までにする"
    return 2
  fi
  printf '%s\n' "許可[対象コードの行番号を書かない]: 対象コードの行番号は無い"
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
