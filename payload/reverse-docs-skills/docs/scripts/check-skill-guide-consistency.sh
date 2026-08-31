#!/usr/bin/env bash
# SKILL.md と guide.html の名前・日本語名・Phase 数を機械的に照合する。
# 依存と説明の言い換えは文脈判断が必要なため、この検査の対象外とする。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

guide_heading() {
  local file="$1"
  sed -n 's/^[[:space:]]*<h1[^>]*>\([^<]*\)<br>.*/\1/p' "$file" | head -n 1
}

guide_phase_count() {
  local file="$1"
  sed -n 's/^[[:space:]]*<h1[^>]*data-phase-count="\([0-9][0-9]*\)"[^>]*>.*/\1/p' "$file" | head -n 1
}

scan() {
  local repo_root="$1" skills="$1/.claude/skills"
  local work list skill_file guide_file directory_name skill_name japanese_name heading
  local skill_phases guide_phases total=0 matched=0 mismatched=0

  if [ ! -d "$skills" ]; then
    echo "[PASS] 対象なし: .claude/skills がありません"
    return 0
  fi
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-guide-consistency.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため判定できません" >&2
    return 2
  fi
  list="$work/skill-files.txt"
  if ! find "$skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | LC_ALL=C sort > "$list"; then
    rm -rf "$work"
    echo "[UNKNOWN] SKILL.md の一覧を取得できないため判定できません" >&2
    return 2
  fi
  if [ ! -s "$list" ]; then
    rm -rf "$work"
    echo "[UNKNOWN] SKILL.md が0件のため判定できません" >&2
    return 2
  fi

  while IFS= read -r skill_file; do
    total=$((total + 1))
    directory_name="$(basename "$(dirname "$skill_file")")"
    guide_file="$(dirname "$skill_file")/references/guide.html"
    if [ ! -f "$guide_file" ]; then
      echo "[FAIL] guide.html がありません: $directory_name" >&2
      mismatched=$((mismatched + 1))
      continue
    fi
    skill_name="$(frontmatter_value "$skill_file" name)"
    japanese_name="$(frontmatter_value "$skill_file" 日本語名)"
    heading="$(guide_heading "$guide_file")"
    skill_phases="$(grep -c '^## Phase[[:space:]]' "$skill_file" || true)"
    guide_phases="$(guide_phase_count "$guide_file")"

    local failed=0
    if [ -z "$skill_name" ] || [ -z "$japanese_name" ] || [ -z "$heading" ] || [ -z "$guide_phases" ]; then
      echo "[FAIL] 比較に必要な値がありません: $directory_name" >&2
      failed=1
    fi
    if [ "$skill_name" != "$directory_name" ]; then
      echo "[FAIL] name: $directory_name / SKILL.md=$skill_name" >&2
      failed=1
    fi
    if [ "$japanese_name" != "$heading" ]; then
      echo "[FAIL] 日本語名: $directory_name / SKILL.md=$japanese_name / guide.html=$heading" >&2
      failed=1
    fi
    if [ "$skill_phases" != "$guide_phases" ]; then
      echo "[FAIL] Phase数: $directory_name / SKILL.md=$skill_phases / guide.html=$guide_phases" >&2
      failed=1
    fi
    if [ "$failed" -eq 0 ]; then
      matched=$((matched + 1))
    else
      mismatched=$((mismatched + 1))
    fi
  done < "$list"

  rm -rf "$work"
  echo "対象 $total 件 / 一致 $matched 件 / 食い違い $mismatched 件"
  [ "$mismatched" -eq 0 ]
}

self_test() {
  local work base rc pass=0 fail=0
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-guide-consistency-selftest.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため自己テストを判定できません" >&2
    return 2
  fi
  base="$work/repo"
  mkdir -p "$base/.claude/skills/example-skill/references"
  printf '%s\n' '---' 'name: example-skill' '日本語名: 例を実行する' '---' '' '## Phase 1: 確認' '## Phase 2: 実行' > "$base/.claude/skills/example-skill/SKILL.md"
  printf '%s\n' '<h1 data-phase-count="2">例を実行する<br><span class="skill-name">example-skill</span></h1>' > "$base/.claude/skills/example-skill/references/guide.html"

  if _cap="$(scan "$base" 2>&1)"; then
    echo "[PASS] 3項目が一致する組を合格にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 3項目が一致する組を合格にできない" >&2; fail=$((fail + 1))
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
  fi

  sed -i.bak 's/name: example-skill/name: another-skill/' "$base/.claude/skills/example-skill/SKILL.md"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] name の食い違いを終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] name の食い違いを検出できない: $rc" >&2; fail=$((fail + 1))
  fi
  mv "$base/.claude/skills/example-skill/SKILL.md.bak" "$base/.claude/skills/example-skill/SKILL.md"

  sed -i.bak 's/例を実行する<br>/別の見出し<br>/' "$base/.claude/skills/example-skill/references/guide.html"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 日本語名の食い違いを終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 日本語名の食い違いを検出できない: $rc" >&2; fail=$((fail + 1))
  fi
  mv "$base/.claude/skills/example-skill/references/guide.html.bak" "$base/.claude/skills/example-skill/references/guide.html"

  sed -i.bak 's/data-phase-count="2"/data-phase-count="1"/' "$base/.claude/skills/example-skill/references/guide.html"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] Phase数の食い違いを終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] Phase数の食い違いを検出できない: $rc" >&2; fail=$((fail + 1))
  fi
  mv "$base/.claude/skills/example-skill/references/guide.html.bak" "$base/.claude/skills/example-skill/references/guide.html"

  rm -f "$base/.claude/skills/example-skill/references/guide.html"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] guide.html の欠落を終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] guide.html の欠落を検出できない: $rc" >&2; fail=$((fail + 1))
  fi

  TMPDIR="$work/no-such-directory" scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[PASS] mktemp失敗を終了コード2にする"; pass=$((pass + 1))
  else
    echo "[FAIL] mktemp失敗を終了コード2にできない: $rc" >&2; fail=$((fail + 1))
  fi

  rm -rf "$work"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  "") scan "$REPO_ROOT" ;;
  *) echo "使い方: $0 [--self-test]" >&2; exit 2 ;;
esac
