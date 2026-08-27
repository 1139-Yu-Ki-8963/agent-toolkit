#!/usr/bin/env bash
# 「記録」は課題を管理する語ではなく、過去にわかったことを残す語である。
# 日付付きの作業記録・試行の記録は残してよい。対象から外す理由はこれである。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

find_unexpected() {
  local docs_root="$1" output_file="$2"
  if ! find "$docs_root" -type f -name '*.md' \( -name '*台帳*' -o -name '*一覧*' -o -name '*進捗*' -o -name '*タスク*' \) -print 2>/dev/null |
    awk -v root="$docs_root/" '
      index($0, root) == 1 {
        rel = substr($0, length(root) + 1)
        if (rel == "tasks/作業課題一覧.md" || rel == "tasks/指摘改善一覧.md") next
        if (index(rel, "tasks/done/") == 1 || index(rel, "guides/") == 1) next
        print rel
      }
    ' > "$output_file"; then
    return 2
  fi
}

check_tree() {
  local docs_root="$1" tmp_file
  if ! tmp_file="$(mktemp "${TMPDIR:-/tmp}/check-ledger-file-count.XXXXXX" 2>/dev/null)" || [ -z "$tmp_file" ]; then
    echo "[UNKNOWN] 一時ファイルを作成できません" >&2
    return 2
  fi
  if ! find_unexpected "$docs_root" "$tmp_file"; then
    echo "[UNKNOWN] docs 配下を走査できません" >&2
    rm -f "$tmp_file"
    return 2
  fi
  if [ -s "$tmp_file" ]; then
    echo "[FAIL] 許可されていない台帳・一覧・進捗・タスク名の Markdown を検出しました" >&2
    cat "$tmp_file" >&2
    rm -f "$tmp_file"
    return 1
  fi
  rm -f "$tmp_file"
  echo "[PASS] 課題を管理する Markdown は許可された置き場だけです"
}

run_self_test() {
  local test_root blocked_tmp code
  if ! test_root="$(mktemp -d "${TMPDIR:-/tmp}/check-ledger-file-count-selftest.XXXXXX" 2>/dev/null)" || [ -z "$test_root" ]; then
    echo "[UNKNOWN] 自己テスト用ディレクトリを作成できません" >&2
    return 2
  fi
  trap "rm -rf '$test_root'" EXIT
  mkdir -p "$test_root/docs/tasks/done" "$test_root/docs/guides" "$test_root/docs/design"
  touch "$test_root/docs/tasks/作業課題一覧.md" "$test_root/docs/tasks/指摘改善一覧.md"
  touch "$test_root/docs/tasks/done/完了記録.md" "$test_root/docs/guides/進捗一覧.md"
  touch "$test_root/docs/design/ポータル試行の記録.md"
  check_tree "$test_root/docs" >/dev/null || return 1
  echo "[PASS] 許可された4経路と試行の記録を除外する"

  touch "$test_root/docs/design/新規台帳.md"
  code=0
  check_tree "$test_root/docs" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 1 ] || return 1
  echo "[PASS] 許可外の台帳名を検出する"

  blocked_tmp="$test_root/missing/tmp"
  code=0
  TMPDIR="$blocked_tmp" check_tree "$test_root/docs" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || return 1
  echo "[PASS] 一時ファイル作成失敗を UNKNOWN にする"
}

case "${1:-}" in
  --self-test) run_self_test ;;
  "") check_tree "$REPO_ROOT/docs" ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
