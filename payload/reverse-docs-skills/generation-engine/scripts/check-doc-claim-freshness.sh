#!/usr/bin/env bash
# 文書の未完了主張の鮮度検査
#
# 目的:
#   docs/ 配下の Markdown が「未実装である」等の未完了を現在形で断定するとき、
#   その主張がいつ時点のものかを読み手が判断できる状態かを検査する。
#   実装が進んで記述だけが取り残されると、読み手は古い記述を現状と誤認する。
#   文書の主張と実装の一致は機械では判定できないため、時点の明示を要求する。
#
# 使い方:
#   check-doc-claim-freshness.sh [<リポジトリルート>]
#   check-doc-claim-freshness.sh --self-test
#
# 判定:
#   未完了を現在形で断定する記述を含む段落に、時点の表明が無ければ不合格とする。
#   時点の表明は日付・「時点」・「着手前」・「当時」・「現在は」・「現在の」を認める。
#   過去形（「未実装であった」）は着手前の記録として通す。
set -uo pipefail

CLAIM_RE='(未実装|未着手|未対応|未整備|未完了)(である|です|だ)。'
DATED_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}|時点|着手前|当時|現在は|現在の'

check_para() {
  local f="$1" para="$2" start="$3"
  [ -z "$para" ] && return 0
  printf '%s' "$para" | grep -qE "$CLAIM_RE" || return 0
  printf '%s' "$para" | grep -qE "$DATED_RE" && return 0
  local snippet
  snippet="$(printf '%s' "$para" | grep -oE ".{0,40}${CLAIM_RE}" | head -1)"
  printf 'FAIL %s:%s 時点の表明がない未完了の断定: %s\n' "$f" "$start" "$snippet"
  return 1
}

scan_file() {
  local f="$1" para="" start=0 lineno=0 rc=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ -z "$line" ]; then
      check_para "$f" "$para" "$start" || rc=1
      para=""
      start=0
    else
      [ "$start" -eq 0 ] && start="$lineno"
      para="${para}
${line}"
    fi
  done < "$f"
  check_para "$f" "$para" "$start" || rc=1
  return "$rc"
}

run_check() {
  local root="$1" rc=0 files=0 f
  while IFS= read -r f; do
    files=$((files + 1))
    scan_file "$f" || rc=1
  done < <(find "$root/docs" -type f -name '*.md' 2>/dev/null | sort)
  if [ "$files" -eq 0 ]; then
    echo "SKIP: $root/docs に Markdown がない"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    echo "CLEAN: $files 件の文書に、時点の表明がない未完了の断定はない"
  fi
  return "$rc"
}

self_test() {
  local tmp pass=0 fail=0 got
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-doc-claim-freshness-self-test.XXXXXX")" || {
    echo "self-test: 一時ディレクトリを作成できない" >&2
    return 1
  }
  mkdir -p "$tmp/docs"

  assert() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  printf '2026-08-01 の調査では、値ずれ検知は未実装である。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "日付の時点表明あり" 0 "$got"

  printf '調査時点では、値ずれ検知は未実装である。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "「時点」の表明あり" 0 "$got"

  printf '目標の配置は文書化済みで未実装である。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "時点の表明なし" 1 "$got"

  printf '配置は宣言経由へ移行済みである。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "未完了の語なし" 0 "$got"

  printf '目標の配置は文書化済みで未実装であった。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "過去形は対象外" 0 "$got"

  printf '2026-08-01 に測定した。\n測定の結果、検知は未実装である。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "同一段落の別行に時点" 0 "$got"

  printf '2026-08-01 に測定した。\n\n検知は未実装である。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "別段落の時点は効かない" 1 "$got"

  printf '索引の作成は未着手です。\n' > "$tmp/docs/a.md"
  run_check "$tmp" >/dev/null 2>&1; got=$?
  assert "「未着手です」を検出" 1 "$got"

  rm -rf "$tmp"
  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  local root="${1:-}"
  if [ -z "$root" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  run_check "$root"
  exit $?
}

main "$@"
