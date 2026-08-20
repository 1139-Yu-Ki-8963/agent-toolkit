#!/usr/bin/env bash
# test-livelock-release.sh — should_auto_release の回帰テスト
# worker-haiku に「このスクリプトを実行して結果を報告しろ」と渡すだけで
# 14本の livelock hook の自動解除判定が正しく動くかを検証する。
# 規約: ~/.claude/rules/scoped/agent-config/hooks/rule.md「マーカーファイル禁止」節

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/transcript-query.sh"

TMPDIR="${TMPDIR:-/tmp}"
PASS=0
FAIL=0

# 定義テーブル: hook名 タグ 閾値
ENTRIES=(
  "no-delegation-stop NO-DELEGATION 3"
  "no-deferral-stop NO-DEFERRAL-RESPONSE 3"
  "port-allocation-block PORT-ALLOCATION-BLOCK 3"
  "investigation-checklist CHECKLIST-MISSING 4"
  "main-agent-direct-work MAIN-AGENT-DIRECT-WORK-BLOCK 4"
  "subagent-choice-category SUBAGENT-CHOICE-BLOCK 4"
  "subagent-choice-model SUBAGENT-CHOICE-BLOCK 4"
  "claude-md-ref-block CLAUDE-MD-REF-BLOCK 3"
  "term-explanation TERM-EXPLANATION-BLOCK 3"
  "dev-flow-agent-gate DEV-FLOW-AGENT-GATE-BLOCK 3"
  "claude-home-root-marker CLAUDE-HOME-ROOT-MARKER-BLOCK 3"
  "remind-worktree-cleanup REMIND-WORKTREE-CLEANUP 2"
  "plan-draft-write-gate PLAN-DRAFT-WRITE-GATE-BLOCK 3"
  "plan-tacit-knowledge-gate PLAN-TACIT-KNOWLEDGE-GATE-BLOCK 3"
)

for entry in "${ENTRIES[@]}"; do
  read -r hook tag threshold <<< "$entry"
  tp_below="$TMPDIR/test-livelock-below-$$"
  tp_above="$TMPDIR/test-livelock-above-$$"

  # 閾値未満（0回）: should_auto_release は false（return 1）を期待
  : > "$tp_below"
  should_auto_release "$tp_below" "$tag" "$threshold" && below=0 || below=$?

  # 閾値以上（閾値回）: should_auto_release は true（return 0）を期待
  : > "$tp_above"
  for ((i = 0; i < threshold; i++)); do
    echo "[$tag]" >> "$tp_above"
  done
  should_auto_release "$tp_above" "$tag" "$threshold" && above=0 || above=$?

  rm -f "$tp_below" "$tp_above"

  if [ "$below" -eq 1 ] && [ "$above" -eq 0 ]; then
    echo "PASS $hook: below=$below(expect1) above=$above(expect0)"
    PASS=$((PASS + 1))
  else
    echo "FAIL $hook: below=$below(expect1) above=$above(expect0)"
    FAIL=$((FAIL + 1))
  fi
done

TOTAL=${#ENTRIES[@]}
echo "---"
echo "$TOTAL tests, $PASS PASS, $FAIL FAIL"

[ "$FAIL" -eq 0 ]
