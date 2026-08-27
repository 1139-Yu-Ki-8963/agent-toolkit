#!/usr/bin/env bash
# check-browser-test-unknown.sh — ブラウザを使う検査が、ブラウザを起動できない
# ときに不合格(終了コード1)ではなく判定不能(終了コード2・[UNKNOWN])を返す形に
# なっているかを見る。
#
# docs/tasks/ブラウザを使う検査が実行できないのに不合格を返す問題を直す指示書.md
# が要求する検査。判定の式に縦棒(|)が入るため指示書の表へ直接書けず、
# スクリプトへ切り出した（.claude/rules/always/tasks/instruction-format/rule.md
# の設計判断を参照）。
#
# 使い方:
#   check-browser-test-unknown.sh                 対象15本が判定不能へ対応
#                                                   している形になっているかを
#                                                   静的に見る
#   check-browser-test-unknown.sh --count-failures 制限再現用の保存済み第1層
#                                                   集約ログを読み、失敗本数が
#                                                   3本以下かを見る
#   check-browser-test-unknown.sh --count-unknowns 制限再現用の保存済み第1層
#                                                   集約ログを読み、判定不能本数が
#                                                   16本以上かを見る
#   check-browser-test-unknown.sh --count-successes 制限なし専用の保存済み第1層
#                                                   集約ログを読み、成功本数が
#                                                   182本以上かを見る
#   check-browser-test-unknown.sh --input <path>   --count-failures /
#                                                   --count-unknowns /
#                                                   --count-successes が読む
#                                                   ログの場所を変える
#   check-browser-test-unknown.sh --self-test      このスクリプト自身の判定を
#                                                   確かめる
#
# --count-failures / --count-unknowns は制限再現ログ、--count-successes は
# 制限なし専用ログを読む。いずれも --input でログの場所を上書きできる。
# 第1層の集約(generation-engine/scripts/verification/run-layer-machine-checks.sh)
# は自分では実行しない。集約は所要時間が約16分あり、片付けの判定器
# (docs/scripts/judge-task-done.sh)の時間の上限(既定120秒)を超えるため、
# この場で実行すると必ず未確認になる。呼び出す側が事前に集約を実行し、
# 出力を本スクリプトの既定の置き場(または --input で指定した場所)へ保存して
# から呼ぶ。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$REPO_ROOT/generation-engine/scripts/tests"
# 保存先はリポジトリルートからの固定パスにする（${TMPDIRを使わない}）。
# ${TMPDIRは実行するシェルごとに値が変わるため}、保存したシェルと読むシェルが
# 別だと場所が一致せず、判定不能(見つからない)が恒常的に発生していた。
DEFAULT_LOG="$REPO_ROOT/.cache/check-browser-test-unknown/layer1-aggregate.log"
DEFAULT_UNRESTRICTED_LOG="$REPO_ROOT/.cache/check-browser-test-unknown/layer1-unrestricted.log"

# ブラウザを使う対象15本(このリポジトリのgeneration-engine/scripts/tests/配下)。
TARGETS=(
  "test-badge-nav-contrast.cjs"
  "test-er-diagram-hub-card-font-size.cjs"
  "test-er-diagram-table-detail-tab.cjs"
  "test-matrix-header-compact-layout.cjs"
  "test-portal-disabled-card-interaction.cjs"
  "test-screen-doc-appendix-collapse.cjs"
  "test-screen-doc-column-width.cjs"
  "test-screen-doc-markdown-renderer.cjs"
  "test-screen-doc-section-order.cjs"
  "test-screen-doc-unresolved-callout.cjs"
  "test-scroll-cue-visibility.cjs"
  "test-semantic-glossary-page.cjs"
  "test-transition-diagram-initial-summary.cjs"
  "test-unit-list-format.cjs"
  "assert-generated-detail-pages-runtime.cjs"
)

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

# --- 静的検査: 対象15本が判定不能への対応を持つ形になっているか ---
# [UNKNOWN]ラベルの出力は、対象ファイル自身が直接持つ場合と、共通ヘルパー
# (lib/browser-unavailable.cjs)へ委譲して間接的に持つ場合の両方を許す。
# 対象15本のうち大半は reportIfUnavailable() 経由でヘルパー側が出力するため、
# ファイル自身の文字列一致だけでは正しく検出できない。
run_static_check() {
  local tests_dir="${1:-$TESTS_DIR}" name file n_fail=0 n_total=0 helper

  [ -d "$tests_dir" ] || unknown "対象ディレクトリが見つからないため判定できません 参照したパス: ${tests_dir}"

  helper="$tests_dir/lib/browser-unavailable.cjs"
  if [ -f "$helper" ] && ! LC_ALL=C grep -q '\[UNKNOWN\]' "$helper"; then
    echo "[FAIL] 共通ヘルパーが[UNKNOWN]ラベルを出力しない: lib/browser-unavailable.cjs"
    n_fail=$((n_fail + 1))
  fi

  for name in "${TARGETS[@]}"; do
    n_total=$((n_total + 1))
    file="$tests_dir/$name"
    if [ ! -f "$file" ]; then
      echo "[FAIL] 対象ファイルが実在しない: ${name}"
      n_fail=$((n_fail + 1))
      continue
    fi
    if ! LC_ALL=C grep -q 'BrowserUnavailableError\|markUnavailable' "$file"; then
      echo "[FAIL] 判定不能への対応(BrowserUnavailableError/markUnavailable)が見つからない: ${name}"
      n_fail=$((n_fail + 1))
      continue
    fi
    if ! LC_ALL=C grep -q '\[UNKNOWN\]' "$file" \
      && ! LC_ALL=C grep -q "require('./lib/browser-unavailable.cjs')" "$file"; then
      echo "[FAIL] [UNKNOWN]ラベルの出力(直接またはヘルパー経由)が見つからない: ${name}"
      n_fail=$((n_fail + 1))
      continue
    fi
  done

  if [ "$n_fail" -eq 0 ]; then
    echo "[PASS] 対象${n_total}本すべてが判定不能(BrowserUnavailableError・[UNKNOWN])へ対応している"
    return 0
  fi
  echo "[FAIL] 対象${n_total}本中${n_fail}本が判定不能へ未対応"
  return 1
}

# --- ログの要約行から値を読む ---
# 対応する要約行の形式:
#   対象 <T> 本 / 成功 <P> 本 / 失敗 <F> 本 / 判定不能 <U> 本 / ...
read_summary_field() {
  local log="$1" label="$2" line value
  line="$(LC_ALL=C grep -E '^対象 [0-9]+ 本 / 成功 [0-9]+ 本 / 失敗 [0-9]+ 本 / 判定不能 [0-9]+ 本' "$log" 2>/dev/null | tail -1)" || :
  [ -n "$line" ] || return 1
  value="$(printf '%s\n' "$line" | LC_ALL=C sed -n "s/.*${label} \([0-9][0-9]*\) 本.*/\1/p")"
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

run_count_failures() {
  local log="${1:-$DEFAULT_LOG}" max="${2:-3}" value

  [ -f "$log" ] || unknown "保存済みの第1層集約ログが見つからないため判定できません 参照したパス: ${log}（先に generation-engine/scripts/verification/run-layer-machine-checks.sh --timeout 200 を実行し、出力を ${log} へ保存すること）"

  if ! value="$(read_summary_field "$log" '失敗')" || [ -z "$value" ]; then
    unknown "ログから失敗本数を読み取れないため判定できません 参照したパス: ${log}"
  fi

  if [ "$value" -le "$max" ]; then
    echo "[PASS] 失敗本数は${value}本（${max}本以下）"
    return 0
  fi
  echo "[FAIL] 失敗本数は${value}本（${max}本を超える）"
  return 1
}

run_count_unknowns() {
  local log="${1:-$DEFAULT_LOG}" min="${2:-16}" value

  [ -f "$log" ] || unknown "保存済みの第1層集約ログが見つからないため判定できません 参照したパス: ${log}（先に generation-engine/scripts/verification/run-layer-machine-checks.sh --timeout 200 を実行し、出力を ${log} へ保存すること）"

  if ! value="$(read_summary_field "$log" '判定不能')" || [ -z "$value" ]; then
    unknown "ログから判定不能本数を読み取れないため判定できません 参照したパス: ${log}"
  fi

  if [ "$value" -ge "$min" ]; then
    echo "[PASS] 判定不能本数は${value}本（${min}本以上）"
    return 0
  fi
  echo "[FAIL] 判定不能本数は${value}本（${min}本に届かない）"
  return 1
}

run_count_successes() {
  local log="${1:-$DEFAULT_UNRESTRICTED_LOG}" min="${2:-182}" value

  [ -f "$log" ] || unknown "保存済みの第1層集約ログが見つからないため判定できません 参照したパス: ${log}（先に generation-engine/scripts/verification/run-layer-machine-checks.sh を実行し、出力を ${log} へ保存すること）"

  if ! value="$(read_summary_field "$log" '成功')" || [ -z "$value" ]; then
    unknown "ログから成功本数を読み取れないため判定できません 参照したパス: ${log}"
  fi

  if [ "$value" -ge "$min" ]; then
    echo "[PASS] 成功本数は${value}本（${min}本以上）"
    return 0
  fi
  echo "[FAIL] 成功本数は${value}本（${min}本に届かない）"
  return 1
}

run_self_test() {
  local tmp n_pass=0 n_fail=0 tests_dir

  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  assert() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
      echo "[PASS] ${name}"
      n_pass=$((n_pass + 1))
    else
      echo "[FAIL] ${name}（期待 ${want} / 実際 ${got}）"
      n_fail=$((n_fail + 1))
    fi
  }

  # --- run_static_check の自己テスト ---
  tests_dir="$tmp/tests-ok"
  mkdir -p "$tests_dir"
  for name in "${TARGETS[@]}"; do
    printf '%s\n' "const { markUnavailable } = require('./lib/browser-unavailable.cjs');" \
      "console.error('[UNKNOWN] dummy');" > "$tests_dir/$name"
  done
  ( run_static_check "$tests_dir" >/dev/null 2>&1 )
  assert "対象15本すべて対応済みなら合格" 0 $?

  tests_dir="$tmp/tests-missing-one"
  mkdir -p "$tests_dir"
  for name in "${TARGETS[@]}"; do
    printf '%s\n' "const { markUnavailable } = require('./lib/browser-unavailable.cjs');" \
      "console.error('[UNKNOWN] dummy');" > "$tests_dir/$name"
  done
  printf '%s\n' "// 対応なし" > "$tests_dir/${TARGETS[0]}"
  ( run_static_check "$tests_dir" >/dev/null 2>&1 )
  assert "1本でも未対応なら不合格" 1 $?

  ( run_static_check "$tmp/no-such-dir" >/dev/null 2>&1 )
  assert "対象ディレクトリが無ければ判定不能" 2 $?

  # --- run_count_failures / run_count_unknowns / run_count_successes の自己テスト ---
  printf '%s\n' "対象 202 本 / 成功 182 本 / 失敗 3 本 / 判定不能 16 本 / 途中停止の疑い 1 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 4463 件" > "$tmp/ok.log"
  ( run_count_failures "$tmp/ok.log" 3 >/dev/null 2>&1 )
  assert "失敗が上限ちょうどなら合格" 0 $?
  ( run_count_unknowns "$tmp/ok.log" 16 >/dev/null 2>&1 )
  assert "判定不能が下限ちょうどなら合格" 0 $?
  ( run_count_successes "$tmp/ok.log" 182 >/dev/null 2>&1 )
  assert "成功が下限ちょうどなら合格" 0 $?

  printf '%s\n' "対象 201 本 / 成功 181 本 / 失敗 4 本 / 判定不能 15 本 / 途中停止の疑い 1 本 / 打ち切り 0 本 / 宣言済み長時間 0 本 / 総ケース数 4463 件" > "$tmp/bad.log"
  ( run_count_failures "$tmp/bad.log" 3 >/dev/null 2>&1 )
  assert "失敗が上限を超えれば不合格" 1 $?
  ( run_count_unknowns "$tmp/bad.log" 16 >/dev/null 2>&1 )
  assert "判定不能が下限に届かなければ不合格" 1 $?
  ( run_count_successes "$tmp/bad.log" 182 >/dev/null 2>&1 )
  assert "成功が下限に届かなければ不合格" 1 $?

  ( run_count_failures "$tmp/no-such-file.log" 3 >/dev/null 2>&1 )
  assert "ログが無ければ判定不能(失敗本数)" 2 $?
  ( run_count_unknowns "$tmp/no-such-file.log" 16 >/dev/null 2>&1 )
  assert "ログが無ければ判定不能(判定不能本数)" 2 $?
  ( run_count_successes "$tmp/no-such-file.log" 182 >/dev/null 2>&1 )
  assert "ログが無ければ判定不能(成功本数)" 2 $?

  printf '%s\n' "要約行を持たないログ" > "$tmp/nosummary.log"
  ( run_count_failures "$tmp/nosummary.log" 3 >/dev/null 2>&1 )
  assert "要約行が無ければ判定不能" 2 $?

  ( bash "${BASH_SOURCE[0]}" --input >/dev/null 2>&1 )
  assert "--inputの値が無ければ判定不能" 2 $?
  ( bash "${BASH_SOURCE[0]}" --input --count-successes >/dev/null 2>&1 )
  assert "--inputの次がオプションなら判定不能" 2 $?

  echo "---"
  echo "SELF-TEST SUMMARY: 実行 $((n_pass + n_fail)) 件 合格 ${n_pass} 件 不合格 ${n_fail} 件"
  [ "$n_fail" -eq 0 ] || exit 1
  exit 0
}

MODE="static"
INPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) run_self_test ;;
    --count-failures) MODE="failures"; shift ;;
    --count-unknowns) MODE="unknowns"; shift ;;
    --count-successes) MODE="successes"; shift ;;
    --input)
      case "${2:-}" in
        ""|--*) unknown "--input の値が指定されていないため判定できません（使い方: --input <path>）" ;;
      esac
      INPUT="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done

case "$MODE" in
  static) run_static_check ;;
  failures) run_count_failures "$INPUT" ;;
  unknowns) run_count_unknowns "$INPUT" ;;
  successes) run_count_successes "$INPUT" ;;
esac
