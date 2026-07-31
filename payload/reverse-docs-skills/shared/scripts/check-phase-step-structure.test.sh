#!/usr/bin/env bash
# 改善課題 1-138 の横断検収条件の対象外: 本ファイル自体が check-phase-step-structure.mjs
# の自己テストであり、--self-test フラグを持つ本番経路スクリプトではないため、
# 追加の --self-test 実装は行わない（本ファイルの実行自体が回帰検証にあたる）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-phase-step-structure.mjs"

node "$CHECK" --strict-warnings

tmp="$(mktemp -d "${TMPDIR:-/tmp}/phase-step-structure-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cp -R "$REPO_ROOT/.claude" "$tmp/.claude"
mkdir -p "$tmp/shared/scripts" "$tmp/shared/references"
cp "$CHECK" "$tmp/shared/scripts/check-phase-step-structure.mjs"
cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"

assert_rejected() {
  local label="$1"
  local expected_code="$2"
  local output
  if output="$(node "$tmp/shared/scripts/check-phase-step-structure.mjs" 2>&1)"; then
    echo "FAIL: $label を拒否しなかった" >&2
    exit 1
  fi
  if ! grep -Fq "[$expected_code]" <<< "$output"; then
    echo "FAIL: $label の診断コードが $expected_code ではない" >&2
    echo "$output" >&2
    exit 1
  fi
  echo "PASS reject: $label [$expected_code]"
}

assert_warned() {
  local label="$1"
  local expected_code="$2"
  local output
  if output="$(node "$tmp/shared/scripts/check-phase-step-structure.mjs" --strict-warnings 2>&1)"; then
    echo "FAIL: $label をstrict警告として拒否しなかった" >&2
    exit 1
  fi
  if ! grep -Fq "[$expected_code]" <<< "$output"; then
    echo "FAIL: $label の警告コードが $expected_code ではない" >&2
    echo "$output" >&2
    exit 1
  fi
  if ! node "$tmp/shared/scripts/check-phase-step-structure.mjs" >/dev/null 2>&1; then
    echo "FAIL: $label を通常モードでも失敗にした" >&2
    exit 1
  fi
  echo "PASS warn: $label [$expected_code]"
}

target="$tmp/.claude/skills/counting-code-lines/SKILL.md"
cp "$target" "$tmp/original-skill.md"

perl -pi -e 's/^## Step 2-1:/### Step 2-1:/' "$target"
assert_rejected "h3 Step" "E_STRUCTURE"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^## Step 2-1:/## Step 1-1:/' "$target"
assert_rejected "親Phase不一致" "E_STRUCTURE"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^## Step 2-1:.*$/Step見出しを削除した負例/' "$target"
assert_rejected "StepなしPhase" "E_STRUCTURE"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^## Phase 3:/## Phase 2:/' "$target"
assert_rejected "Phase重複" "E_STRUCTURE"

cp "$tmp/original-skill.md" "$target"
orchestrator="$tmp/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md"
perl -pi -e 'if ($seen) { s/^- global_step: 2$/- global_step: 1/ } $seen = 1 if /^- global_step: 1$/' "$orchestrator"
assert_rejected "global Step重複" "E_STRUCTURE"
cp "$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md" "$orchestrator"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^## Phase ([1-9]\d*):/### P$1:/; s/^## Step [1-9]\d*-[1-9]\d*:.*$//' "$target"
assert_rejected "Phaseなし旧P記法" "E_STRUCTURE"

cp "$tmp/original-skill.md" "$target"
reference="$tmp/.claude/skills/rebuilding-screen-unit-from-docs/references/phase-details.md"
printf '\n## P3: 旧補足見出し\n' >> "$reference"
assert_rejected "references内の旧P見出し" "E_STRUCTURE"

perl -pi -e 's/^## P3: 旧補足見出し$/## 詳細: Phase 3 \/ Step 3-1 — 補足/' "$reference"
printf '\n### Step 1: 旧補足Step\n' >> "$reference"
assert_rejected "references内の親Phaseなし旧Step見出し" "E_STRUCTURE"
cp "$REPO_ROOT/.claude/skills/rebuilding-screen-unit-from-docs/references/phase-details.md" "$reference"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 'if (!$done && /^\*\*完了\*\*:/) { $_ = ""; $done = 1 }' "$target"
assert_rejected "Step完了判定欠落" "E_STEP_COMPLETION"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|)[^|]+(\| 3 \|)/$1 $2/' "$tmp/shared/references/リバース工程設計.md"
assert_rejected "Back-edge条件欠落" "E_BACK_EDGE"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|[^|]+\|) 3 (\\|)/$1 0 $2/' "$tmp/shared/references/リバース工程設計.md"
assert_rejected "Back-edge上限0" "E_BACK_EDGE"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
perl -pi -e 's/^\| facts-reextract \|/| architecture-revise |/' "$tmp/shared/references/リバース工程設計.md"
assert_rejected "Back-edge ID重複" "E_BACK_EDGE"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \|) 8 \| 5 \|/$1 5 | 8 |/' "$tmp/shared/references/リバース工程設計.md"
assert_rejected "Back-edgeが前方参照" "E_BACK_EDGE"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|[^|]+\| 3 \|)[^|]+\\|$/$1 |/' "$tmp/shared/references/リバース工程設計.md"
assert_rejected "Back-edge停止条件欠落" "E_BACK_EDGE"

cp "$REPO_ROOT/shared/references/リバース工程設計.md" "$tmp/shared/references/リバース工程設計.md"
cp "$tmp/original-skill.md" "$target"
cp "$REPO_ROOT/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md" "$orchestrator"
cp "$REPO_ROOT/.claude/skills/rebuilding-screen-unit-from-docs/references/phase-details.md" "$reference"
perl -pi -e 's/^\*\*使用ツール\*\*: Read \/ Bash$/**実行手段**: 判断のみ/' "$target"
assert_warned "Step使用ツール欠落" "W_STEP_TOOL"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^\*\*使用ツール\*\*: Read \/ Bash$/**使用ツール**: Read \/ Glob/' "$target"
assert_warned "allowed-tools外の使用ツール" "W_ALLOWED_TOOLS"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^allowed-tools: \[Bash, Read, Write\]$/allowed-tools: [Bash, Read, Write, Glob]/' "$target"
assert_warned "allowed-toolsの未使用ツール" "W_ALLOWED_TOOLS"

echo "PASS phase-step structure regression"
