#!/usr/bin/env bash
set -euo pipefail
# 運転規約ファイル（RUNBOOK.md）の実在・構造・死に参照解消を機械検査する。
# 保守責任者: 人手（ユーザー）。RUNBOOK.mdの見出し構成を変更した場合は本スクリプトも同時に更新する。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNBOOK="$REPO_ROOT/RUNBOOK.md"

pass=0 fail=0

check() {
  local name="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    echo "PASS: $name"
    pass=$((pass+1))
  else
    echo "FAIL: $name"
    fail=$((fail+1))
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  if [ -f "$RUNBOOK" ]; then ok1=1; else ok1=0; fi
  check "RUNBOOK.mdが実在する" "$ok1"

  heading_count="$(grep -c '^## [1-5]\.' "$RUNBOOK" 2>/dev/null || echo 0)"
  if [ "$heading_count" = "5" ]; then ok2=1; else ok2=0; fi
  check "5見出しが揃っている" "$ok2"

  if [ -f "$RUNBOOK" ] && grep -q "RUNBOOK.md" "$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/references/contract.md"; then ok3=1; else ok3=0; fi
  check "契約文書の死に参照が解消済み" "$ok3"

  if [ -f "$RUNBOOK" ] && grep -q "RUNBOOK.md" "$REPO_ROOT/.claude/skills/syncing-reverse-env/SKILL.md"; then ok4=1; else ok4=0; fi
  check "環境同期スキル本文の死に参照が解消済み" "$ok4"

  if [ -f "$RUNBOOK" ] && grep -q "RUNBOOK.md" "$REPO_ROOT/shared/scripts/check-worktree-commit-guard.sh"; then ok5=1; else ok5=0; fi
  check "コミット保護ガードスクリプトの死に参照が解消済み" "$ok5"

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

echo "使い方: $0 --self-test"
exit 1
