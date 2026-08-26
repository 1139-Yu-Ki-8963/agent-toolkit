#!/usr/bin/env bash
# 完了した指摘ごとに、検収方法の全項目が状態行で判定されているかを検査する。
# 数え方: 検収方法は「N.」または「N．」で始まる列挙を数え、列挙がなければ1項目とする。
# 状態行は「検収N」「項目N」「判定N」から次の「:」「：」「=」までを判定ラベルとして数える。
# 同じ番号の重複は1判定とし、判定数の超過は詳しい判定として許容する。不足だけを不合格とする。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_LEDGER="$REPO_ROOT/docs/tasks/指摘改善一覧.md"
SELF_TEST_TMPDIR=""

cleanup_self_test() {
  if [ -n "$SELF_TEST_TMPDIR" ] && [ -d "$SELF_TEST_TMPDIR" ]; then
    rm -rf -- "$SELF_TEST_TMPDIR"
  fi
}

unknown() {
  echo "[UNKNOWN] $1" >&2
  return 2
}

analyze_ledger() {
  local ledger="$1"

  if [ ! -f "$ledger" ]; then
    unknown "台帳が見つかりません: $ledger"
    return $?
  fi

  awk '
    function clear_labels( key) {
      for (key in labels) delete labels[key]
    }
    function count_acceptance(text, count, rest) {
      count = 0
      rest = text
      while (match(rest, /(^|[[:space:]])[0-9]+[.．][[:space:]]/)) {
        count++
        rest = substr(rest, RSTART + RLENGTH)
      }
      return count > 0 ? count : 1
    }
    function count_verdicts(text, token, number, rest, count) {
      clear_labels()
      rest = text
      while (match(rest, /(検収|項目|判定)[[:space:]]*[0-9]+[^:：=。]*[:：=]/)) {
        token = substr(rest, RSTART, RLENGTH)
        number = token
        sub(/^(検収|項目|判定)[[:space:]]*/, "", number)
        sub(/[^0-9].*$/, "", number)
        labels[number] = 1
        rest = substr(rest, RSTART + RLENGTH)
      }
      count = 0
      for (number in labels) count++
      return count
    }
    function flush_issue( verdict_count) {
      if (issue == "" || state !~ /^\*\*状態\*\*:[[:space:]]*完了/) return
      completed++
      verdict_count = count_verdicts(state)
      if (acceptance_count > verdict_count) {
        invalid++
        printf "[FAIL] %s 検収%d項目 / 状態%d判定\n", issue, acceptance_count, verdict_count
      }
    }
    /^### / {
      flush_issue()
      issue = ""
      acceptance_count = 0
      state = ""
      if ($0 !~ /^### 1-[0-9]+\./) next
      issue = $2
      sub(/\.$/, "", issue)
      next
    }
    /^\*\*検収方法\*\*:/ {
      acceptance_count = count_acceptance(substr($0, index($0, ":") + 1))
      next
    }
    /^\*\*状態\*\*:/ { state = $0 }
    END {
      flush_issue()
      printf "完了%d件 / 判定不足%d件\n", completed, invalid
      exit invalid > 0 ? 1 : 0
    }
  ' "$ledger"
}

run_self_test() {
  SELF_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/ledger-acceptance-coverage.XXXXXX")" || {
    unknown "自己テスト用の一時ディレクトリを作成できません"
    return $?
  }
  trap cleanup_self_test EXIT HUP INT TERM

  local fixture="$SELF_TEST_TMPDIR/ledger.md"
  local output
  local code

  printf '%s\n' \
    '### 1-1. 単一項目' \
    '**検収方法**: 自己テストを実行する' \
    '**状態**: 完了（検収1: 満たす）' \
    '### 1-2. 揺れと超過' \
    '**検収方法**: 1. 一つ目 2. 二つ目' \
    '**状態**: 完了（項目1「一つ目」=満たす: 詳細。判定2：満たす。検収3: 追加確認）' \
    '### 1-3. 完了以外' \
    '**検収方法**: 1. 一つ目 2. 二つ目' \
    '**状態**: 対応中' \
    '### 1-5. 無番号見出しの直前' \
    '**検収方法**: 1. 一つ目 2. 二つ目 3. 三つ目 4. 四つ目' \
    '**状態**: 完了。検収1: 満たす。検収2: 満たす。検収3: 満たす。検収4: 満たす。' \
    '### 台帳の構造を説明する見出し' \
    '**検収方法**: 1. 一つ目 2. 二つ目 3. 三つ目 4. 四つ目 5. 五つ目 6. 六つ目' \
    '**状態**: 完了。これは指摘の状態行ではない。' > "$fixture"
  output="$(analyze_ledger "$fixture")"
  code=$?
  if [ "$code" -ne 0 ] || ! printf '%s\n' "$output" | grep -q '完了3件 / 判定不足0件'; then
    echo "[FAIL] 正常系、表記揺れ、無番号見出しの自己テスト"
    printf '%s\n' "$output"
    return 1
  fi

  printf '%s\n' \
    '### 1-4. 判定不足' \
    '**検収方法**: 1. 一つ目 2. 二つ目 3. 三つ目' \
    '**状態**: 完了（検収1: 満たす。項目2=満たす: 詳細）' > "$fixture"
  set +e
  output="$(analyze_ledger "$fixture")"
  code=$?
  set -e
  if [ "$code" -ne 1 ] || ! printf '%s\n' "$output" | grep -q '\[FAIL\] 1-4 検収3項目 / 状態2判定'; then
    echo "[FAIL] 判定不足の自己テスト"
    printf '%s\n' "$output"
    return 1
  fi

  echo "[PASS] 自己テスト2件"
}

case "${1:-}" in
  --self-test)
    run_self_test
    ;;
  "")
    analyze_ledger "$DEFAULT_LEDGER"
    ;;
  *)
    analyze_ledger "$1"
    ;;
esac
