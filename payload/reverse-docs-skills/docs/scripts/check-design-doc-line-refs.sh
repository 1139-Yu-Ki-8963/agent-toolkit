#!/usr/bin/env bash
# 設計文書から、編集でずれる行番号参照を検出する。
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
DESIGN_ROOT="${REPO_ROOT}/docs/design"
LINE_REF_PATTERN='[0-9]+([〜~-][0-9]+)?(・[0-9]+([〜~-][0-9]+)?)*[[:space:]]*行目|:[0-9]+[[:space:]]*行目|行目は'

scan_design_docs() {
  local root="$1"
  local matches

  if [ ! -d "$root" ]; then
    echo "[UNKNOWN] 設計文書の置き場が見つかりません: $root" >&2
    return 2
  fi

  matches="$(find "$root" -type f -name '*.md' -exec grep -nHE "$LINE_REF_PATTERN" {} + 2>/dev/null)"
  if [ -n "$matches" ]; then
    echo "$matches"
    echo "[FAIL] 行番号参照を検出しました" >&2
    return 1
  fi

  echo "[PASS] docs/design の行番号参照は0件です"
  return 0
}

make_self_test_dir() {
  local base="${TMPDIR:-/tmp}"
  local made

  made="$(mktemp -d "${base%/}/check-design-doc-line-refs.XXXXXX")" || {
    echo "[UNKNOWN] 自己テスト用一時ディレクトリを作成できません" >&2
    return 2
  }
  printf '%s\n' "$made"
}

self_test() {
  local tmp
  local failures=0

  tmp="$(make_self_test_dir)" || return 2
  trap "rm -rf '$tmp'" EXIT
  mkdir -p "$tmp/bad" "$tmp/good"

  printf '%s\n' '本体コメント728〜731行目を参照する。' > "$tmp/bad/range.md"
  printf '%s\n' 'ヘッダコメント37〜42 行目を参照する。' > "$tmp/bad/spaced-range.md"
  printf '%s\n' 'コメント1〜21・727〜729・795〜798行目を参照する。' > "$tmp/bad/compound.md"
  printf '%s\n' '実測150〜260秒、対象72件、版2.1を記録する。' > "$tmp/good/metrics.md"

  scan_design_docs "$tmp/bad" >/dev/null 2>&1
  [ "$?" -eq 1 ] || failures=$((failures + 1))
  scan_design_docs "$tmp/good" >/dev/null 2>&1
  [ "$?" -eq 0 ] || failures=$((failures + 1))

  if [ "$failures" -ne 0 ]; then
    echo "[FAIL] 自己テスト: ${failures}件失敗" >&2
    return 1
  fi
  echo "[PASS] 自己テスト: 行番号参照を検出し、秒数・件数・版番号を除外しました"
  return 0
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  "")
    scan_design_docs "$DESIGN_ROOT"
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
