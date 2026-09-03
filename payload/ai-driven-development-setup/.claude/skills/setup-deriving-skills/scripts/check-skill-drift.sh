#!/usr/bin/env bash
set -euo pipefail

# check-skill-drift.sh — 機能派生物（.claude/skills/*/SKILL.md 等）の手作業編集検知
#
# 目的:
#   docs/skills/ の定義から一時ディレクトリへ生成し直し、実際の派生物
#   （<出力先リポジトリルート>/.claude/skills/**）と内容を突き合わせる。
#   ハッシュを記録した台帳は持たない。毎回その場で定義から生成して比べれば、
#   docs/skills/ が唯一の正になる（setup-deriving-rules の check-rule-drift.sh と
#   同じ考え方）。
#
# 使い方:
#   check-skill-drift.sh <docs/skills のルート> <出力先リポジトリルート>
#   check-skill-drift.sh --self-test
#
# 判定方法:
#   1. mktemp -d で一時ディレクトリを作る
#   2. build-derived-skills.sh <docs/skills のルート> <一時ディレクトリ> --apply を実行する
#   3. 一時ディレクトリの生成物と、出力先リポジトリの現物を突き合わせる
#   4. 内容が違う・現物にしかない・一時ディレクトリにしかない、をそれぞれ報告する
#   5. 一時ディレクトリを削除する
#
# 終了コード: ずれなし0 / ずれあり1 / 前提不足（root不在・生成失敗等）2
#
# 保守責任者: 人手（ユーザー）。走査対象（.claude/skills/**）を変える場合は
#   本スクリプトの list_targets と
#   docs/skills/setup-deriving-skills/SKILL.md を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build-derived-skills.sh"

usage() {
  echo "usage: $0 <docs/skills のルート> <出力先リポジトリルート> | --self-test" >&2
  exit 2
}

# root配下の .claude/skills/** の全ファイルを、rootからの相対パスで
# 決定的な順序（path昇順）で列挙する。
list_targets() {
  local root="$1"
  (
    cd "$root" 2>/dev/null || exit 0
    if [ -d ".claude/skills" ]; then
      find ".claude/skills" -type f 2>/dev/null
    fi
  ) | LC_ALL=C sort || true
}

cmd_check() {
  local skills_root="$1" out_root="$2"
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-drift.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  local build_rc=0
  "$BUILD_SCRIPT" "$skills_root" "$tmp" --apply >/dev/null 2>&1 || build_rc=$?
  if [ "$build_rc" -ne 0 ]; then
    echo "ERROR: build-derived-skills.sh --apply が失敗した（skills_root=${skills_root}）" >&2
    rm -rf "$tmp"
    return 2
  fi

  local drift=0 rel

  # 定義から生成されるはずのものを基準に、現物との一致（MODIFIED）・不在（DELETED）を検知する
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${out_root}/${rel}" ]; then
      echo "DELETED: ${rel}"
      drift=1
      continue
    fi
    if ! diff -q "${tmp}/${rel}" "${out_root}/${rel}" >/dev/null 2>&1; then
      echo "MODIFIED: ${rel}"
      drift=1
    fi
  done <<LIST
$(list_targets "$tmp")
LIST

  # 現物にはあるが、定義からの生成物には無いもの（ADDED）を検知する
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${tmp}/${rel}" ]; then
      echo "ADDED: ${rel}"
      drift=1
    fi
  done <<LIST
$(list_targets "$out_root")
LIST

  rm -rf "$tmp"

  if [ "$drift" -eq 0 ]; then
    echo "CLEAN: 定義からの再生成と一致（ずれなし）"
    return 0
  fi
  echo "DRIFT: 生成物に定義との不一致がある。手作業編集の可能性がある。定義（docs/skills/）を直して再生成するか、意図した変更なら定義側を直す" >&2
  return 1
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_skill() {
  local root="$1" name="$2"
  local dir="${root}/${name}"
  mkdir -p "${dir}/tests"
  cat > "${dir}/SKILL.md" <<SKILLEOF
---
name: ${name}
日本語名: テスト用機能
description: "self-test用の機能定義。"
invocation: ${name}
type: transform
allowed-tools: [Bash]
unit: setup
category: setup
kind: none
inputs: [docs/skills/${name}/dummy-input]
outputs: [docs/skills/${name}/dummy-output]
requires: []
acceptance: tests/
---

## いつ使うか

self-test用。
SKILLEOF
  cat > "${dir}/tests/test-dummy.sh" <<'TESTEOF'
#!/usr/bin/env bash
exit 0
TESTEOF
  chmod +x "${dir}/tests/test-dummy.sh"
}

self_test() {
  local pass=0 fail=0
  local skills_root out rel_skill

  if ! skills_root="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-drift-self-test-skills.XXXXXX" 2>/dev/null)" || [ -z "$skills_root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  if ! out="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-drift-self-test-out.XXXXXX" 2>/dev/null)" || [ -z "$out" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  bst_write_skill "$skills_root" "setup-alpha"

  "$BUILD_SCRIPT" "$skills_root" "$out" --apply >/dev/null 2>&1

  rel_skill=".claude/skills/setup-alpha/SKILL.md"

  if [ ! -f "${out}/${rel_skill}" ]; then
    echo "  [FAIL] 前提: フィクスチャの生成に失敗した" >&2
    rm -rf "$skills_root" "$out"
    return 1
  fi

  # ケース1（ずれなし・検知しない）
  local out1 rc1=0
  out1="$("$0" "$skills_root" "$out" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  [PASS] ケース1: 生成直後はずれなし（CLEAN・exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース1: 生成直後の判定が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2（ずれあり・検知する）: 現物のSKILL.mdを書き換えるとMODIFIEDを検知する
  local original out2 rc2=0
  original="$(cat "${out}/${rel_skill}")"
  printf '%s\n手で書き換えた行\n' "$original" > "${out}/${rel_skill}"
  out2="$("$0" "$skills_root" "$out" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q "^MODIFIED: ${rel_skill}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース2: SKILL.mdの手作業編集をMODIFIEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース2: MODIFIED検知が不正 (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi
  printf '%s' "$original" > "${out}/${rel_skill}"

  # ケース3（ずれあり・検知する）: 現物を削除するとDELETEDを検知する
  local out3 rc3=0
  rm -f "${out}/${rel_skill}"
  out3="$("$0" "$skills_root" "$out" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q "^DELETED: ${rel_skill}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース3: 削除をDELETEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース3: DELETED検知が不正 (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi
  "$BUILD_SCRIPT" "$skills_root" "$out" --apply >/dev/null 2>&1

  # ケース4（ずれあり・検知する）: 定義に無いファイルを現物へ追加するとADDEDを検知する
  local rel_extra=".claude/skills/setup-alpha/extra-not-in-definition.md"
  local out4 rc4=0
  printf 'extra' > "${out}/${rel_extra}"
  out4="$("$0" "$skills_root" "$out" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 1 ] && printf '%s' "$out4" | grep -q "^ADDED: ${rel_extra}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース4: 定義に無いファイルの追加をADDEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース4: ADDED検知が不正 (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi
  rm -f "${out}/${rel_extra}"

  # ケース5（ずれなし・検知しない）: 現物を戻すと再びCLEANに戻る
  local out5 rc5=0
  out5="$("$0" "$skills_root" "$out" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 0 ] && printf '%s' "$out5" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  [PASS] ケース5: 現物を戻すと再びずれなしに戻る（CLEAN・exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース5: 復元後の判定が不正 (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi

  rm -rf "$skills_root" "$out"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
  return 1
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

[ $# -eq 2 ] || usage

SKILLS_ROOT="$1"
OUT_ROOT="$2"

[ -n "$SKILLS_ROOT" ] && [ -d "$SKILLS_ROOT" ] || { echo "ERROR: docs/skills のルートが存在しない: ${SKILLS_ROOT:-（未指定）}" >&2; exit 2; }
[ -n "$OUT_ROOT" ] && [ -d "$OUT_ROOT" ] || { echo "ERROR: 出力先リポジトリルートが存在しない: ${OUT_ROOT:-（未指定）}" >&2; exit 2; }

cmd_check "$SKILLS_ROOT" "$OUT_ROOT"
