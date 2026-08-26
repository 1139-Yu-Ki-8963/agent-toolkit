#!/usr/bin/env bash
# .claude/skills 配下の Markdown からスキル名候補を抽出し、定義の実在を検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXCLUSIONS_REL="docs/references/skill-cross-reference-exclusions.tsv"
NAME_RE='[a-z][a-z0-9-]{6,}-for-reverse-docs|orchestrating-[a-z-]+|generating-[a-z-]+|rebuilding-[a-z-]+|surveying-[a-z-]+|extracting-[a-z-]+|maintaining-[a-z-]+|syncing-[a-z-]+|counting-[a-z-]+|running-[a-z-]+|managing-[a-z-]+|prioritizing-[a-z-]+|unlocking-[a-z-]+'

is_excluded() {
  local name="$1" repo_root="$2" exclusions="$3"
  local declared=0 reference source reason file relative

  while IFS=$'\t' read -r reference source reason; do
    [ "$reference" = "$name" ] || continue
    declared=$((declared + 1))
    case "$source" in
      .claude/skills/*.md) ;;
      *) return 1 ;;
    esac
    [ -f "$repo_root/$source" ] || return 1
    grep -hoE "$NAME_RE" "$repo_root/$source" | grep -Fxq -- "$name" || return 1
    if grep -Fq -- "Skill(\"$name\")" "$repo_root/$source" \
      || grep -Fq -- ".claude/skills/$name/SKILL.md" "$repo_root/$source" \
      || grep -Eq -- "[$(printf '\140')]${name}[$(printf '\140')].{0,20}(を)?起動する" "$repo_root/$source"; then
      return 1
    fi
  done < <(tail -n +2 "$exclusions")
  [ "$declared" -gt 0 ] || return 1

  while IFS= read -r file; do
    relative="${file#"$repo_root/"}"
    awk -F '\t' -v target="$name" -v target_source="$relative" '
      NR > 1 && $1 == target && $2 == target_source { found=1 }
      END { exit !found }
    ' "$exclusions" || return 1
  done < <(
    while IFS= read -r file; do
      grep -hoE "$NAME_RE" "$file" | grep -Fxq -- "$name" && printf '%s\n' "$file"
    done < <(grep -rlF --include='*.md' -- "$name" "$repo_root/.claude/skills")
  )
}

validate_exclusions() {
  local exclusions="$1"
  awk -F '\t' '
    NR == 1 { if ($1 != "reference" || $2 != "source" || $3 != "reason") bad=1; next }
    NF < 3 || $1 == "" || $2 == "" || $3 == "" { bad=1 }
    END { exit bad ? 1 : 0 }
  ' "$exclusions"
}

scan() {
  local repo_root="$1"
  local skills="$repo_root/.claude/skills"
  local exclusions="$repo_root/$EXCLUSIONS_REL"
  local work raw_candidates candidates rc

  if [ ! -d "$skills" ]; then
    echo "[PASS] 対象なし: .claude/skills がありません"
    return 0
  fi
  if [ ! -f "$exclusions" ]; then
    echo "[UNKNOWN] 除外一覧が見つからないため判定できません: $exclusions" >&2
    return 2
  fi
  if ! validate_exclusions "$exclusions"; then
    echo "[UNKNOWN] 除外一覧に参照名または理由が無い行があるため判定できません: $exclusions" >&2
    return 2
  fi
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-cross-references.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため判定できません" >&2
    return 2
  fi
  raw_candidates="$work/raw-candidates.txt"
  candidates="$work/candidates.txt"
  grep -rhoE "$NAME_RE" "$skills" --include='*.md' > "$raw_candidates" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    rm -rf "$work"
    echo "[UNKNOWN] スキル名候補の抽出に失敗したため判定できません" >&2
    return 2
  fi
  if ! LC_ALL=C sort -u "$raw_candidates" > "$candidates"; then
    rm -rf "$work"
    echo "[UNKNOWN] スキル名候補の整列に失敗したため判定できません" >&2
    return 2
  fi

  local total=0 present=0 excluded=0 missing=0 name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    total=$((total + 1))
    if [ -f "$skills/$name/SKILL.md" ]; then
      present=$((present + 1))
    elif is_excluded "$name" "$repo_root" "$exclusions"; then
      excluded=$((excluded + 1))
    else
      echo "[FAIL] 実在しないスキル参照: $name" >&2
      missing=$((missing + 1))
    fi
  done < "$candidates"

  rm -rf "$work"
  echo "候補 $total 件 / 実在 $present 件 / 除外 $excluded 件 / 不在 $missing 件"
  [ "$missing" -eq 0 ]
}

self_test() {
  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-cross-references-selftest.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため自己テストを判定できません" >&2
    return 2
  fi

  local base="$work/repo" pass=0 fail=0 rc=0
  mkdir -p \
    "$base/.claude/skills/generating-present-for-reverse-docs" \
    "$base/.claude/skills/managing-present-references" \
    "$base/.claude/skills/prioritizing-present-references" \
    "$base/.claude/skills/unlocking-present-references" \
    "$base/docs/references"
  : > "$base/.claude/skills/generating-present-for-reverse-docs/SKILL.md"
  : > "$base/.claude/skills/managing-present-references/SKILL.md"
  : > "$base/.claude/skills/prioritizing-present-references/SKILL.md"
  : > "$base/.claude/skills/unlocking-present-references/SKILL.md"
  printf 'reference\tsource\treason\n' > "$base/$EXCLUSIONS_REL"

  printf '%s\n' \
    'Skill("generating-present-for-reverse-docs")' \
    'Skill("managing-present-references")' \
    'Skill("prioritizing-present-references")' \
    'Skill("unlocking-present-references")' \
    > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 実在するスキル参照を合格にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在するスキル参照を合格にできない" >&2; fail=$((fail + 1))
  fi

  local prefix prefix_failure=0
  for prefix in managing prioritizing unlocking; do
    printf 'Skill("%s-absent-reference")\n' "$prefix" > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
    scan "$base" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 1 ] || prefix_failure=1
  done
  if [ "$prefix_failure" -eq 0 ]; then
    echo "[PASS] 追加した3接頭辞の不在参照を終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 追加した3接頭辞のいずれかを抽出できない" >&2; fail=$((fail + 1))
  fi

  printf '%s\n' 'Skill("generating-absent-for-reverse-docs")' > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
  scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 実在しないスキル参照を終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在しないスキル参照の終了コードが1ではない: $rc" >&2; fail=$((fail + 1))
  fi

  printf '%s\n' 'Skill("generating-absent-for-reverse-docs")' '旧 generating-excluded-for-reverse-docs の記録' > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
  printf 'generating-excluded-for-reverse-docs\t.claude/skills/generating-present-for-reverse-docs/reference.md\t歴史的記述\n' >> "$base/$EXCLUSIONS_REL"
  scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 理由付き除外だけを判定対象から外す"; pass=$((pass + 1))
  else
    echo "[FAIL] 除外が未登録の不在参照まで隠した: $rc" >&2; fail=$((fail + 1))
  fi

  printf '%s\n' '旧 generating-excluded-for-reverse-docs の記録' > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 理由付き除外を合格にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 理由付き除外を合格にできない" >&2; fail=$((fail + 1))
  fi

  printf '%s\n' 'Skill("generating-excluded-for-reverse-docs")' > "$base/.claude/skills/managing-present-references/reference.md"
  scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 除外元と異なる実呼び出しを終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 除外元と異なる実呼び出しを隠した: $rc" >&2; fail=$((fail + 1))
  fi
  rm -f "$base/.claude/skills/managing-present-references/reference.md"

  printf '%s\n' \
    '旧 generating-excluded-for-reverse-docs の記録' \
    'Skill("generating-excluded-for-reverse-docs")' \
    > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"
  scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 除外元に加わった実呼び出しを終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 除外元に加わった実呼び出しを隠した: $rc" >&2; fail=$((fail + 1))
  fi
  printf '%s\n' '旧 generating-excluded-for-reverse-docs の記録' > "$base/.claude/skills/generating-present-for-reverse-docs/reference.md"

  printf 'generating-empty-reason-for-reverse-docs\t.claude/skills/generating-present-for-reverse-docs/reference.md\t\n' >> "$base/$EXCLUSIONS_REL"
  scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[PASS] 理由が空の除外一覧を終了コード2にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 理由が空の除外一覧の終了コードが2ではない: $rc" >&2; fail=$((fail + 1))
  fi
  sed -i.bak '/generating-empty-reason-for-reverse-docs/d' "$base/$EXCLUSIONS_REL"
  rm -f "$base/$EXCLUSIONS_REL.bak"

  local fake_bin="$work/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 2' > "$fake_bin/grep"
  chmod +x "$fake_bin/grep"
  PATH="$fake_bin:$PATH" scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[PASS] 候補抽出の失敗を終了コード2にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 候補抽出失敗の終了コードが2ではない: $rc" >&2; fail=$((fail + 1))
  fi

  TMPDIR="$work/no-such-directory" scan "$base" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[PASS] mktemp 失敗を終了コード2にする"; pass=$((pass + 1))
  else
    echo "[FAIL] mktemp 失敗の終了コードが2ではない: $rc" >&2; fail=$((fail + 1))
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
