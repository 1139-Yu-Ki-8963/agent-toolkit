#!/usr/bin/env bash
# SKILL.md本文で実際に使うツールがallowed-toolsに宣言されているか検査する。
# 宣言に無い使用だけを不合格とする。宣言済みだが本文で使わないツールは報告のみで、終了コードへ影響させない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${SKILL_ALLOWED_TOOLS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

scan() {
  node - "${SKILL_ALLOWED_TOOLS_ROOT:-$REPO_ROOT}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = process.argv[2];
const skillsRoot = path.join(repoRoot, ".claude", "skills");
const toolNames = [
  "Agent", "AskUserQuestion", "Bash", "Edit", "Glob", "Grep", "Read",
  "SendUserFile", "Skill", "TaskCreate", "TaskUpdate", "Write",
];
const negative = /(?:不使用|使わない|使用してはならない|発行しない|聞き出さない|書かない|禁止|撤廃|再openしない|渡さない|させない|ではなく)/;

function unknown(message) {
  console.error(`[UNKNOWN] ${message}`);
  process.exit(2);
}

if (!fs.existsSync(skillsRoot) || !fs.statSync(skillsRoot).isDirectory()) {
  console.log("[PASS] 対象なし: .claude/skills がありません");
  process.exit(0);
}

const skillFiles = fs.readdirSync(skillsRoot)
  .map((name) => path.join(skillsRoot, name, "SKILL.md"))
  .filter((file) => fs.existsSync(file))
  .sort();
if (skillFiles.length === 0) unknown("SKILL.md が0件のため判定できません");

let missingCount = 0;
let unusedCount = 0;
let matchCount = 0;
const missingDetails = [];
const unusedDetails = [];

for (const file of skillFiles) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    unknown(`${path.relative(repoRoot, file)} を読めないため判定できません: ${error.code ?? error.message}`);
  }
  const frontmatter = text.match(/^---\n([\s\S]*?)\n---(?:\n|$)/);
  if (!frontmatter) unknown(`${path.relative(repoRoot, file)} のfrontmatterを読めません`);
  const allowedMatch = frontmatter[1].match(/^allowed-tools:\s*\[([^\]]*)\]\s*$/m);
  if (!allowedMatch) unknown(`${path.relative(repoRoot, file)} のallowed-toolsを読めません`);

  const allowed = new Set(allowedMatch[1].split(",").map((item) => item.trim()).filter(Boolean));
  const body = text.slice(frontmatter[0].length);
  const segments = body.split(/[。\n]|(?:が|けれども|ただし)[、,]/).map((item) => item.trim()).filter(Boolean);
  const used = new Set();

  for (const segment of segments) {
    const declaration = /^(?:\*\*使用ツール\*\*:|- tool:)/.test(segment);
    for (const tool of toolNames) {
      if (!new RegExp(`\\b${tool}\\b`).test(segment)) continue;
      if (!declaration && negative.test(segment)) continue;
      if (tool === "Skill" && /が Skill\s*ツールで呼び出/.test(segment)) continue;
      if (tool === "Skill" && !declaration && !/(?:Skill\s*\(|Skill\s*ツール.{0,30}(?:起動|呼び出)|Skill.{0,15}(?:を|で)(?:順次)?起動)/.test(segment)) continue;
      used.add(tool);
    }
  }

  const missing = [...used].filter((tool) => !allowed.has(tool)).sort();
  const unused = [...allowed].filter((tool) => !used.has(tool)).sort();
  const relative = path.relative(repoRoot, file);
  if (missing.length > 0) {
    missingCount += 1;
    missingDetails.push(`${relative}: ${missing.join(", ")}`);
  } else if (unused.length > 0) {
    unusedCount += 1;
    unusedDetails.push(`${relative}: ${unused.join(", ")}`);
  } else {
    matchCount += 1;
  }
}

console.log(`検査対象: ${skillFiles.length}件`);
console.log(`宣言に無いツールを使う: ${missingCount}件`);
console.log(`宣言にあるが使わない: ${unusedCount}件`);
console.log(`一致: ${matchCount}件`);
for (const detail of missingDetails) console.error(`[FAIL] ${detail}`);
for (const detail of unusedDetails) console.log(`[REPORT] ${detail}`);
process.exit(missingCount > 0 ? 1 : 0);
NODE
}

self_test() {
  local work output rc
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-allowed-tools.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため判定できません" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN
  mkdir -p "$work/.claude/skills/missing" "$work/.claude/skills/unused" "$work/.claude/skills/match"
  printf '%s\n' '---' 'allowed-tools: [Read]' '---' 'Bash で検査する。' > "$work/.claude/skills/missing/SKILL.md"
  printf '%s\n' '---' 'allowed-tools: [Read, Write]' '---' 'Read で読む。Write は使わない。' > "$work/.claude/skills/unused/SKILL.md"
  printf '%s\n' '---' 'allowed-tools: [Read]' '---' 'Read で読む。' > "$work/.claude/skills/match/SKILL.md"

  output="$(SKILL_ALLOWED_TOOLS_ROOT="$work" scan 2>&1)"
  rc=$?
  if [ "$rc" -ne 1 ] || ! grep -Fq '宣言に無いツールを使う: 1件' <<< "$output" \
    || ! grep -Fq '宣言にあるが使わない: 1件' <<< "$output" \
    || ! grep -Fq '一致: 1件' <<< "$output"; then
    echo "[FAIL] 不一致3分類の自己テストに失敗しました" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf '%s\n' '---' 'allowed-tools: [Bash, Read]' '---' 'Bash で検査する。Read は使わない。' > "$work/.claude/skills/missing/SKILL.md"
  output="$(SKILL_ALLOWED_TOOLS_ROOT="$work" scan 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -Fq '宣言に無いツールを使う: 0件' <<< "$output"; then
    echo "[FAIL] 未使用宣言が終了コードへ影響しない自己テストに失敗しました" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf '%s\n' '---' 'allowed-tools: [Write]' '---' 'Write は使わないが、Read で入力を読む。' > "$work/.claude/skills/missing/SKILL.md"
  output="$(SKILL_ALLOWED_TOOLS_ROOT="$work" scan 2>&1)"
  rc=$?
  if [ "$rc" -ne 1 ] || ! grep -Fq '.claude/skills/missing/SKILL.md: Read' <<< "$output"; then
    echo "[FAIL] 否定節の後にある肯定的な使用を検出する自己テストに失敗しました" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  mkdir -p "$work/.claude/skills/unreadable/SKILL.md"
  output="$(SKILL_ALLOWED_TOOLS_ROOT="$work" scan 2>&1)"
  rc=$?
  if [ "$rc" -ne 2 ] || ! grep -Fq '[UNKNOWN]' <<< "$output"; then
    echo "[FAIL] 読取不能を判定不能にする自己テストに失敗しました" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  echo "PASS check-skill-allowed-tools self-test"
}

case "${1:-}" in
  "") scan ;;
  --self-test) self_test ;;
  *) echo "[UNKNOWN] 未対応の引数です: $1" >&2; exit 2 ;;
esac
