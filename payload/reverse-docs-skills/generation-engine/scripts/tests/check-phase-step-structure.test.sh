#!/usr/bin/env bash
# 集約の対象外: 本ファイル自体が check-phase-step-structure.mjs
# の自己テストであり、--self-test フラグを持つ本番経路スクリプトではないため、
# 追加の --self-test 実装は行わない（本ファイルの実行自体が回帰検証にあたる）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECK="$SCRIPT_DIR/../check-phase-step-structure.mjs"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/phase-step-structure-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cp -R "$REPO_ROOT/.claude" "$tmp/.claude"
mkdir -p "$tmp/generation-engine/scripts" "$tmp/delivery-payload/references"
cp "$CHECK" "$tmp/generation-engine/scripts/check-phase-step-structure.mjs"
cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"

# ケースの実行件数・合格件数・不合格件数を数える。1件のケースが不合格でも
# その場で終了せず、残りのケースを最後まで実行して末尾で集計する
# （改善課題1-183: 1件の違反で早期中断すると他ケースへ到達できない）。
CASE_TOTAL=0
CASE_PASS=0
CASE_FAIL=0
FAILED_LABELS=""

record_pass() {
  CASE_PASS=$((CASE_PASS + 1))
  echo "PASS $1"
}

record_fail() {
  CASE_FAIL=$((CASE_FAIL + 1))
  FAILED_LABELS="${FAILED_LABELS}- $1
"
  echo "FAIL: $1" >&2
}

assert_rejected() {
  local label="$1"
  local expected_code="$2"
  local output
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if output="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" 2>&1)"; then
    record_fail "$label を拒否しなかった"
    return 0
  fi
  if ! grep -Fq "[$expected_code]" <<< "$output"; then
    record_fail "$label の診断コードが $expected_code ではない"
    printf '%s\n' "$output" >&2
    return 0
  fi
  record_pass "reject: $label [$expected_code]"
}

assert_warned() {
  local label="$1"
  local expected_code="$2"
  local output
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if output="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" --strict-warnings 2>&1)"; then
    record_fail "$label をstrict警告として拒否しなかった"
    return 0
  fi
  if ! grep -Fq "[$expected_code]" <<< "$output"; then
    record_fail "$label の警告コードが $expected_code ではない"
    printf '%s\n' "$output" >&2
    return 0
  fi
  if ! node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" >/dev/null 2>&1; then
    record_fail "$label を通常モードでも失敗にした"
    return 0
  fi
  record_pass "warn: $label [$expected_code]"
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
orchestrator="$tmp/.claude/skills/orchestrating-ai-development-setup/SKILL.md"
perl -pi -e 'if ($seen) { s/^- global_step: 2$/- global_step: 1/ } $seen = 1 if /^- global_step: 1$/' "$orchestrator"
assert_rejected "global Step重複" "E_STRUCTURE"
cp "$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/SKILL.md" "$orchestrator"

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

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|)[^|]+(\| 3 \|)/$1 $2/' "$tmp/delivery-payload/references/リバース工程設計.md"
assert_rejected "Back-edge条件欠落" "E_BACK_EDGE"

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|[^|]+\|) 3 (\|)/$1 0 $2/' "$tmp/delivery-payload/references/リバース工程設計.md"
assert_rejected "Back-edge上限0" "E_BACK_EDGE"

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
perl -pi -e 's/^\| facts-reextract \|/| architecture-revise |/' "$tmp/delivery-payload/references/リバース工程設計.md"
assert_rejected "Back-edge ID重複" "E_BACK_EDGE"

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \|) 8 \| 5 \|/$1 5 | 8 |/' "$tmp/delivery-payload/references/リバース工程設計.md"
assert_rejected "Back-edgeが前方参照" "E_BACK_EDGE"

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
perl -pi -e 's/^(\| architecture-revise \| 8 \| 5 \|[^|]+\| 3 \|)[^|]+\|$/$1 |/' "$tmp/delivery-payload/references/リバース工程設計.md"
assert_rejected "Back-edge停止条件欠落" "E_BACK_EDGE"

cp "$REPO_ROOT/delivery-payload/references/リバース工程設計.md" "$tmp/delivery-payload/references/リバース工程設計.md"
cp "$tmp/original-skill.md" "$target"
cp "$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/SKILL.md" "$orchestrator"
cp "$REPO_ROOT/.claude/skills/rebuilding-screen-unit-from-docs/references/phase-details.md" "$reference"
perl -pi -e 's/^\*\*使用ツール\*\*: Read \/ Bash$/**実行手段**: 判断のみ/' "$target"
assert_warned "Step使用ツール欠落" "W_STEP_TOOL"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^\*\*使用ツール\*\*: Read \/ Bash$/**使用ツール**: Read \/ Glob/' "$target"
assert_warned "allowed-tools外の使用ツール" "W_ALLOWED_TOOLS"

cp "$tmp/original-skill.md" "$target"
perl -pi -e 's/^allowed-tools: \[Bash, Read, Write\]$/allowed-tools: [Bash, Read, Write, Glob]/' "$target"
assert_warned "allowed-toolsの未使用ツール" "W_ALLOWED_TOOLS"

cp "$tmp/original-skill.md" "$target"

# 改善課題1-168: 位置引数で単一の定義文書を指定した場合、その対象のみの検査結果が返ること
# （リポジトリ全体を前提とする横断チェックの影響を受けないことも合わせて確認する）
CASE_TOTAL=$((CASE_TOTAL + 1))
if single_target_out="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" "$target" 2>&1)"; then
  if grep -q "single target" <<< "$single_target_out" && grep -q "counting-code-lines/SKILL.md" <<< "$single_target_out"; then
    record_pass "single-target: 単一の定義文書指定でその対象のみの結果が返る(exit 0)"
  else
    record_fail "単一対象指定(正常系)の出力形式が不正"
    printf '%s\n' "$single_target_out" >&2
  fi
else
  record_fail "単一対象指定(正常系)がexit 0にならない"
  printf '%s\n' "$single_target_out" >&2
fi

# 1-168: 単一対象指定時も、その対象自体の構造違反は実際に検出されること（フィルタが検査自体を素通りさせていないことの確認）
CASE_TOTAL=$((CASE_TOTAL + 1))
perl -pi -e 's/^## Step 2-1:/### Step 2-1:/' "$target"
if single_target_broken_out="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" "$target" 2>&1)"; then
  cp "$tmp/original-skill.md" "$target"
  record_fail "単一対象指定で対象自体の構造違反を拒否しなかった"
  printf '%s\n' "$single_target_broken_out" >&2
else
  cp "$tmp/original-skill.md" "$target"
  if grep -Fq "[E_STRUCTURE]" <<< "$single_target_broken_out"; then
    record_pass "single-target: 単一対象指定でもその対象の構造違反を検出する"
  else
    record_fail "単一対象指定で対象自体の違反コードがE_STRUCTUREではない"
    printf '%s\n' "$single_target_broken_out" >&2
  fi
fi

# 1-168: 認識しない引数を渡した場合は無視せず警告（エラー出力）して非0で終了すること
CASE_TOTAL=$((CASE_TOTAL + 1))
if unknown_out="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" --unknown-flag 2>&1)"; then
  record_fail "認識しない引数を無視して終了コード0を返した"
  printf '%s\n' "$unknown_out" >&2
else
  if grep -qi "ERROR unrecognized" <<< "$unknown_out"; then
    record_pass "unknown-arg: 認識しない引数を無視せず警告し非0終了"
  else
    record_fail "認識しない引数のエラーメッセージが出力されていない"
    printf '%s\n' "$unknown_out" >&2
  fi
fi

# 1-168: 実在しないパスを位置引数に渡した場合も無視せず警告して非0で終了すること
CASE_TOTAL=$((CASE_TOTAL + 1))
if missing_out="$(node "$tmp/generation-engine/scripts/check-phase-step-structure.mjs" "$tmp/no-such-file.md" 2>&1)"; then
  record_fail "実在しない位置引数を無視して終了コード0を返した"
  printf '%s\n' "$missing_out" >&2
else
  if grep -qi "ERROR unrecognized" <<< "$missing_out"; then
    record_pass "unknown-path: 実在しない位置引数を無視せず警告し非0終了"
  else
    record_fail "実在しない位置引数のエラーメッセージが出力されていない"
    printf '%s\n' "$missing_out" >&2
  fi
fi

echo "=== ケース結果 ==="
echo "実行件数: ${CASE_TOTAL} 件 / 合格: ${CASE_PASS} 件 / 不合格: ${CASE_FAIL} 件"
if [ "$CASE_FAIL" -eq 0 ]; then
  echo "PASS phase-step structure regression cases"
else
  echo "不合格のケース:" >&2
  printf '%s' "$FAILED_LABELS" >&2
fi

# ケースはすべて実行済み。ここから先はリポジトリ全体を対象にした
# --strict-warnings 検査であり、ケースの合否とは別に結果を報告する。
# set -e による即時終了を避けるため if で結果を受け取る。
echo "=== 全体の検査（--strict-warnings） ==="
overall_status=0
if strict_output="$(node "$CHECK" --strict-warnings 2>&1)"; then
  echo "全体の検査: 合格（警告0件）"
else
  overall_status=1
  echo "全体の検査: 不合格"
  echo "$strict_output"
fi

if [ "$CASE_FAIL" -ne 0 ] || [ "$overall_status" -ne 0 ]; then
  exit 1
fi
