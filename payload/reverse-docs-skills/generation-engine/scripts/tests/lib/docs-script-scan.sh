#!/usr/bin/env bash
# docs-script-scan.sh — docs/scripts/ 配下の「引数なしで実データを走査する」
# 検査を、第1層の機械検証(run-layer-machine-checks.sh)向けの薄い入口
# （test-<name>-scan.sh）から共通に呼ぶための関数群。list_targets の収集
# 対象にはならない（ファイル名が test で始まらず、自己テストの分岐ラベルも
# 含まないため）。source して使う。
#
# 使い方（呼び出し側）:
#   . "${SCRIPT_DIR}/lib/docs-script-scan.sh"
#   run_docs_script_scan "<絶対パスのターゲット>" "<表示名>"
#
# 終了コード:
#   ターゲットが 0（合格）→ そのまま 0
#   ターゲットが 2（判定不能。実行環境依存で判定できなかった場合）→ 0
#     （合否対象外として扱う。
#     .claude/rules/always/verification/indeterminate-result/rule.md の
#     規約に従い、判定不能を不合格に数えない）
#   それ以外（1 等）→ 1（不合格として集約に伝える）
set -u

run_docs_script_scan() {
  local target="$1" label="$2" out rc
  out="$(bash "${target}" 2>&1)"
  rc=$?
  printf '%s\n' "${out}"
  case "${rc}" in
    0)
      echo "[PASS] ${label}: 実データの走査に合格"
      return 0
      ;;
    2)
      echo "[PASS] ${label}: 判定不能（環境依存のため合否対象外として扱う）"
      return 0
      ;;
    *)
      echo "[FAIL] ${label}: 実データの走査で違反を検出"
      return 1
      ;;
  esac
}
