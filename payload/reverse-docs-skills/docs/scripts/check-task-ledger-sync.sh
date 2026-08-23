#!/usr/bin/env bash
# 作業課題一覧の状態と、対応する指示書の実際の置き場を照合する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER="$REPO_ROOT/docs/tasks/作業課題一覧.md"
TASKS_DIR="$REPO_ROOT/docs/tasks"

check_ledger() {
  local ledger="$1"
  local tasks_dir="$2"

  if [ ! -f "$ledger" ] || [ ! -d "$tasks_dir" ] || [ ! -d "$tasks_dir/done" ]; then
    echo "[UNKNOWN] 台帳または指示書の置き場を読み取れないため判定できません: $ledger / $tasks_dir" >&2
    return 2
  fi

  local checked=0
  local mismatches=0
  local name state direct_exists done_exists expected

  while IFS=$'\t' read -r name state; do
    [ -n "$name" ] || continue
    checked=$((checked + 1))
    direct_exists=0
    done_exists=0
    if [ -f "$tasks_dir/$name" ]; then
      direct_exists=1
    fi
    if [ -f "$tasks_dir/done/$name" ]; then
      done_exists=1
    fi

    if [ "$direct_exists" -eq 1 ] && [ "$done_exists" -eq 0 ]; then
      expected="not-complete"
      if [ "$state" = "完了" ]; then
        echo "[FAIL] 直下にあるのに状態が完了です: $name"
        mismatches=$((mismatches + 1))
      fi
    elif [ "$direct_exists" -eq 0 ] && [ "$done_exists" -eq 1 ]; then
      expected="完了"
      if [ "$state" != "$expected" ]; then
        echo "[FAIL] done/ にあるのに状態が完了ではありません: ${name}（状態=${state:-なし}）"
        mismatches=$((mismatches + 1))
      fi
    elif [ "$direct_exists" -eq 1 ] && [ "$done_exists" -eq 1 ]; then
      echo "[FAIL] 直下と done/ の両方にあります: $name"
      mismatches=$((mismatches + 1))
    else
      echo "[FAIL] 直下にも done/ にもありません: $name"
      mismatches=$((mismatches + 1))
    fi
  done < <(awk '
    /^### / {
      if (name != "") print name "\t" state
      name = substr($0, 5)
      state = ""
      next
    }
    name != "" && state == "" && /^\*\*状態\*\*: / {
      state = $0
      sub(/^\*\*状態\*\*: /, "", state)
    }
    END { if (name != "") print name "\t" state }
  ' "$ledger")

  if [ "$checked" -eq 0 ]; then
    echo "[FAIL] 台帳の見出しが0件です"
    return 1
  fi
  if [ "$mismatches" -ne 0 ]; then
    echo "[FAIL] 台帳と置き場の食い違い=${mismatches}件（確認=${checked}件）"
    return 1
  fi

  echo "[PASS] 台帳と置き場の食い違い=0件（確認=${checked}件）"
}

record_self_test() {
  local name="$1"
  local expected="$2"
  local ledger="$3"
  local tasks_dir="$4"
  local actual
  if (check_ledger "$ledger" "$tasks_dir") >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" -eq "$expected" ]; then
    echo "  [PASS] $name"
    SELF_TEST_PASS=$((SELF_TEST_PASS + 1))
  else
    echo "  [FAIL] ${name}（終了コード=${actual}、期待=${expected}）"
    SELF_TEST_FAIL=$((SELF_TEST_FAIL + 1))
  fi
}

run_self_test() {
  local tmpdir=""
  if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  trap 'if [ -n "${tmpdir:-}" ]; then rm -rf "$tmpdir"; fi' EXIT

  mkdir -p "$tmpdir/tasks/done"
  touch "$tmpdir/tasks/進行中指示書.md"
  touch "$tmpdir/tasks/done/完了済み指示書.md"

  local valid="$tmpdir/valid.md"
  local direct_mismatched="$tmpdir/direct-mismatched.md"
  local done_mismatched="$tmpdir/done-mismatched.md"
  printf '%s\n' \
    '### 進行中指示書.md' \
    '**状態**: 着手できる' \
    '' \
    '### 完了済み指示書.md' \
    '**状態**: 完了' > "$valid"
  printf '%s\n' \
    '### 進行中指示書.md' \
    '**状態**: 完了' \
    > "$direct_mismatched"
  printf '%s\n' \
    '### 完了済み指示書.md' \
    '**状態**: 着手できる' > "$done_mismatched"

  SELF_TEST_PASS=0
  SELF_TEST_FAIL=0
  record_self_test "正常な台帳" 0 "$valid" "$tmpdir/tasks"
  record_self_test "直下なのに完了の台帳" 1 "$direct_mismatched" "$tmpdir/tasks"
  record_self_test "done/ なのに未完了の台帳" 1 "$done_mismatched" "$tmpdir/tasks"

  echo "実行 3 件 / 成功 ${SELF_TEST_PASS} 件 / 失敗 ${SELF_TEST_FAIL} 件"
  local result=0
  [ "$SELF_TEST_FAIL" -eq 0 ] || result=1
  rm -rf "$tmpdir"
  tmpdir=""
  trap - EXIT
  return "$result"
}

case "${1:-}" in
  "") check_ledger "$LEDGER" "$TASKS_DIR" ;;
  --self-test) run_self_test ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
