#!/usr/bin/env bash
# リバース検証テンプレートの記入規則と生成Skillの実行手順を照合する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAPPING_REL="docs/references/template-guidance-skill-mapping.tsv"
GUIDANCE_MARKER='<!-- TEMPLATE_GUIDANCE_EXECUTION -->'

scan() {
  local repo_root="$1"
  local templates="$repo_root/delivery-payload/templates/リバース検証"
  local mapping="$repo_root/$MAPPING_REL"
  local work discovered declared rc

  if [ ! -d "$templates" ] || [ ! -f "$mapping" ]; then
    echo "[UNKNOWN] テンプレートまたは対応定義が見つからないため判定できません" >&2
    return 2
  fi
  if ! awk -F '\t' '
    NR == 1 { ok=($1=="template" && $2=="skill" && $3=="status" && $4=="reason"); next }
    NF != 4 || $1=="" || $2=="" || ($3!="mapped" && $3!="unknown") || $4=="" { ok=0 }
    $3=="mapped" && $2=="-" { ok=0 }
    $3=="unknown" && $2!="-" { ok=0 }
    seen[$1]++ { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "$mapping"; then
    echo "[UNKNOWN] 対応定義の形式が不正なため判定できません: $MAPPING_REL" >&2
    return 2
  fi
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-template-guidance-skill-steps.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため判定できません" >&2
    return 2
  fi
  discovered="$work/discovered.txt"
  declared="$work/declared.txt"
  grep -rlE --include='*.md' '<!-- (記入規則:|INTRODUCTION_GUIDANCE)' "$templates" > "$discovered"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    rm -rf "$work"
    echo "[UNKNOWN] 記入規則の抽出に失敗したため判定できません" >&2
    return 2
  fi
  sed "s#^$repo_root/##" "$discovered" | LC_ALL=C sort -u > "$work/discovered.sorted"
  awk -F '\t' 'NR>1 {print $1}' "$mapping" | LC_ALL=C sort -u > "$declared"

  local mismatch=0
  if ! diff -u "$work/discovered.sorted" "$declared" >/dev/null; then
    echo "[FAIL] 記入規則を持つテンプレートと対応定義が一致しません" >&2
    diff -u "$work/discovered.sorted" "$declared" >&2 || true
    mismatch=1
  fi

  local total=0 present=0 absent=0 unknown=0 template skill status reason skill_file
  while IFS=$'\t' read -r template skill status reason; do
    [ "$template" = "template" ] && continue
    total=$((total + 1))
    if [ "$status" = "unknown" ]; then
      unknown=$((unknown + 1))
      continue
    fi
    skill_file="$repo_root/.claude/skills/$skill/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      echo "[FAIL] 対応するSkillが存在しません: $skill" >&2
      absent=$((absent + 1))
    elif grep -Fq "$GUIDANCE_MARKER" "$skill_file" \
      && grep -Fq '<!-- INTRODUCTION_GUIDANCE ... -->' "$skill_file" \
      && grep -Fq '設計書様式.md` の §9' "$skill_file"; then
      present=$((present + 1))
    else
      echo "[FAIL] 記入規則を実行する手順がありません: $template -> $skill" >&2
      absent=$((absent + 1))
    fi
  done < "$mapping"

  rm -rf "$work"
  echo "記入規則 $total 件 / 手順あり $present 件 / 手順なし $absent 件 / 判定不能 $unknown 件"
  [ "$mismatch" -eq 0 ] && [ "$absent" -eq 0 ]
}

self_test() {
  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-template-guidance-skill-steps-selftest.XXXXXX" 2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] mktemp が失敗し、一時ディレクトリを作れないため自己テストを判定できません" >&2
    return 2
  fi
  local base="$work/repo" pass=0 fail=0 rc=0
  mkdir -p "$base/delivery-payload/templates/リバース検証/画面" \
    "$base/.claude/skills/generating-example-for-reverse-docs" "$base/docs/references"
  printf '<!-- INTRODUCTION_GUIDANCE: 案内 -->\n' > "$base/delivery-payload/templates/リバース検証/画面/例.md"
  printf '%s\n' "$GUIDANCE_MARKER" '<!-- INTRODUCTION_GUIDANCE ... -->' '設計書様式.md` の §9' \
    > "$base/.claude/skills/generating-example-for-reverse-docs/SKILL.md"
  printf 'template\tskill\tstatus\treason\n%s\t%s\tmapped\t%s\n' \
    'delivery-payload/templates/リバース検証/画面/例.md' 'generating-example-for-reverse-docs' '生成担当' \
    > "$base/$MAPPING_REL"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 対応手順がある記入規則を合格にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 対応手順がある記入規則を合格にできない" >&2; fail=$((fail + 1))
  fi

  : > "$base/.claude/skills/generating-example-for-reverse-docs/SKILL.md"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 対応手順の欠落を終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 対応手順の欠落を終了コード1にできない: $rc" >&2; fail=$((fail + 1))
  fi

  printf '%s\n' "$GUIDANCE_MARKER" '<!-- INTRODUCTION_GUIDANCE ... -->' '設計書様式.md` の §9' \
    > "$base/.claude/skills/generating-example-for-reverse-docs/SKILL.md"
  printf 'template\tskill\tstatus\treason\n' > "$base/$MAPPING_REL"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "[PASS] 対応定義にない記入規則を終了コード1にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 対応定義の不足を終了コード1にできない: $rc" >&2; fail=$((fail + 1))
  fi

  printf 'template\tskill\tstatus\treason\n%s\t-\tunknown\t%s\n' \
    'delivery-payload/templates/リバース検証/画面/例.md' '生成担当を確定できない' > "$base/$MAPPING_REL"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 理由付きの判定不能を明示状態として扱う"; pass=$((pass + 1))
  else
    echo "[FAIL] 理由付きの判定不能を扱えない" >&2; fail=$((fail + 1))
  fi

  printf 'template\tskill\tstatus\treason\n%s\t-\tunknown\t\n' \
    'delivery-payload/templates/リバース検証/画面/例.md' > "$base/$MAPPING_REL"
  scan "$base" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[PASS] 理由のない判定不能を終了コード2にする"; pass=$((pass + 1))
  else
    echo "[FAIL] 不正な対応定義を終了コード2にできない: $rc" >&2; fail=$((fail + 1))
  fi

  printf 'template\tskill\tstatus\treason\n%s\t-\tunknown\t%s\n' \
    'delivery-payload/templates/リバース検証/画面/例.md' '生成担当を確定できない' > "$base/$MAPPING_REL"
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
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
