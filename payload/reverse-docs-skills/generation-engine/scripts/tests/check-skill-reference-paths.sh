#!/usr/bin/env bash
# check-skill-reference-paths.sh — スキル定義が参照するファイルの実在を検査する
#
# 何を見るか:
#   .claude/skills/*/SKILL.md の本文に現れる次の 2 種を見る。
#     1. スキルの置き場からの相対参照（../../../ で始まるもの）
#     2. リポジトリルートからの参照（generation-engine/ と delivery-payload/ で始まるもの）
#
# 何を見ないか:
#   ~/ で始まる参照は、このリポジトリの外を指すため対象にしない。
#   外部への依存は RUNBOOK.md の依存表が扱う。
#
# なぜ要るか:
#   スキルの参照資料が、存在しない見本を指したまま配られた実例がある。
#   読み手は完成形を確かめられず、参照が古いのか未作成なのかも判別できない。
#   設計判断は .claude/rules/scoped/portal/page-conventions/rule.md の
#   「## 設計判断」内「### check-skill-reference-paths.sh」に置く。
#
# 使い方:
#   check-skill-reference-paths.sh             全スキルを走査する
#   check-skill-reference-paths.sh --self-test 判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

REL_RE='\.\./\.\./\.\./[^[:space:]`"()]+\.[A-Za-z0-9]+'
ABS_RE='(^|[^./~A-Za-z0-9_-])(generation-engine|delivery-payload)/[A-Za-z0-9_./-]+\.(sh|mjs|cjs|py|json|css|md|html)'

scan() {
  local base="$1"
  local skills="$base/.claude/skills"
  local total=0 missing=0 f d p
  if [ ! -d "$skills" ]; then
    echo "走査 0 件 / 不在 0 件"
    return 0
  fi
  while IFS= read -r f; do
    d="$(dirname "$f")"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      total=$((total + 1))
      if [ ! -e "$d/$p" ]; then
        echo "[FAIL] $f -> $p"
        missing=$((missing + 1))
      fi
    done < <(grep -oE "$REL_RE" "$f" 2>/dev/null | LC_ALL=C sort -u)
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      total=$((total + 1))
      if [ ! -e "$base/$p" ]; then
        echo "[FAIL] $f -> $p"
        missing=$((missing + 1))
      fi
    done < <(grep -oE "$ABS_RE" "$f" 2>/dev/null | sed -E 's#^[^gd]*##' | LC_ALL=C sort -u)
  done < <(find "$skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f 2>/dev/null | LC_ALL=C sort)
  echo "走査 $total 件 / 不在 $missing 件"
  [ "$missing" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-reference-paths.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local base="$tmp/base"
  mkdir -p "$base/generation-engine/scripts" "$base/docs"
  : > "$base/generation-engine/scripts/present.sh"
  : > "$base/docs/present.md"

  mkdir -p "$base/.claude/skills/ok/references"
  printf '%s\n' '../../../docs/present.md を参照する' 'generation-engine/scripts/present.sh を使う' > "$base/.claude/skills/ok/SKILL.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] 実在する参照だけのスキルを合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在する参照だけのスキルを合格と判定する"; fail=$((fail + 1))
  fi

  mkdir -p "$base/.claude/skills/home/references"
  printf '%s\n' '~/.claude/skills/other/references/foo.md を参照する' > "$base/.claude/skills/home/SKILL.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[PASS] ホーム配下の参照は対象にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] ホーム配下の参照は対象にしない"; fail=$((fail + 1))
  fi

  mkdir -p "$base/.claude/skills/relmiss/references"
  printf '%s\n' '../../../docs/absent.md を参照する' > "$base/.claude/skills/relmiss/SKILL.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[FAIL] 不在の相対参照を不合格と判定する"; fail=$((fail + 1))
  else
    echo "[PASS] 不在の相対参照を不合格と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base/.claude/skills/relmiss"

  mkdir -p "$base/.claude/skills/absmiss/references"
  printf '%s\n' 'generation-engine/scripts/absent.sh を使う' > "$base/.claude/skills/absmiss/SKILL.md"
  if scan "$base" >/dev/null 2>&1; then
    echo "[FAIL] 不在のリポジトリ相対の参照を不合格と判定する"; fail=$((fail + 1))
  else
    echo "[PASS] 不在のリポジトリ相対の参照を不合格と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base/.claude/skills/absmiss"

  if scan "$tmp/empty" >/dev/null 2>&1; then
    echo "[PASS] スキルが1件も無い場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] スキルが1件も無い場合は合格と判定する"; fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  "")
    scan "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
