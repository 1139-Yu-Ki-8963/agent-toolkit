#!/usr/bin/env bash
# 設計文書の行番号非記録と、生成する3スキルの回帰をまとめて確認する入口。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

check_api_basic_design_contract() {
  local skill_dir="$REPO_ROOT/.claude/skills/generating-api-basic-design-for-reverse-docs"

  grep -qF '**検査5 実装位置の非記録検査**' "$skill_dir/SKILL.md"
  grep -qF '対象コードのファイルパス・行番号・`file:line` が無く' "$skill_dir/SKILL.md"
  grep -qF '| 実装位置-非記録 |' "$skill_dir/references/test-cases.md"
  echo '[PASS] 接続窓口の基本設計は実装位置を記録しない契約を持つ'
}

run_self_tests() {
  bash "$REPO_ROOT/docs/scripts/check-design-doc-line-refs.sh" --self-test
  check_api_basic_design_contract
  bash "$SCRIPT_DIR/check-detailed-design-conventions.test.sh" --self-test
  bash "$REPO_ROOT/.claude/skills/generating-reverse-common-docs/scripts/check-common-docs.sh" --self-test
}

case "${1:-}" in
  ""|--self-test)
    run_self_tests
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
