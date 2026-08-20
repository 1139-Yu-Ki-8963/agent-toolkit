#!/usr/bin/env bash
# スキルガイドが書くリポジトリ内のパスの実在を検査する。
#
# 何を見るか:
#   .claude/skills/*/references/guide.html の本文に現れる
#   generation-engine/ と delivery-payload/ で始まるパスが実在するかを見る。
#
# なぜ要るか:
#   ガイドの「依存」欄が置き場所の階層を落として書かれ、
#   読み手がそのパスを辿ると見つからない状態が実際に起きた。
#   設計判断は .claude/rules/always/skill-guide/html/rule.md の「設計判断」節に置く。
#
# 使い方:
#   check-guide-script-paths.sh             全ガイドを走査する
#   check-guide-script-paths.sh --self-test 判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PATH_RE='(generation-engine|delivery-payload)/[A-Za-z0-9_./-]+\.(sh|mjs|cjs|py|json|css|md|html)'

scan_dir() {
  local root="$1" base="$2"
  local missing=0 total=0
  local guide p
  [ -d "$root" ] || { echo "走査 0 件 / 不在 0 件"; return 0; }
  # LC_ALL=C sort: 実行環境のロケール（照合順序）に依存しないバイト単位の
  # 決定的な順序で列挙する。素直な形（ロケール指定なしのsort）は環境によって
  # 走査順・報告順が変わりうるため、self-testの出力比較や再現性を損なう。
  while IFS= read -r guide; do
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      total=$((total + 1))
      if [ ! -e "$base/$p" ]; then
        echo "[FAIL] $guide -> $p"
        missing=$((missing + 1))
      fi
    done < <(grep -hoE "$PATH_RE" "$guide" | LC_ALL=C sort -u)
  done < <(find "$root" -name guide.html -type f | LC_ALL=C sort)
  echo "走査 $total 件 / 不在 $missing 件"
  [ "$missing" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  # 明示テンプレート付きmktemp -d（"${TMPDIR:-/tmp}/<name>.XXXXXX"）を使う。裸のmktemp -dは
  # $TMPDIRを無視し書き込み許可の外にある既定領域を使うため、サンドボックス実行環境では
  # 失敗する（改善課題「一時ディレクトリ-作成先」。手元の環境で動いても裸の形へ戻すな）。
  # それでも失敗しうる（書き込み自体を拒む環境）ため、素直な形（失敗時に即座に
  # コマンド全体を止める）を避け、明示的に検知して不合格1件として報告してから抜ける。
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/guide-script-paths.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi
  mkdir -p "$tmp/base/generation-engine/scripts"
  : > "$tmp/base/generation-engine/scripts/present.sh"

  mkdir -p "$tmp/base/.claude/skills/a/references"
  printf '%s\n' '<code>generation-engine/scripts/present.sh</code>' > "$tmp/base/.claude/skills/a/references/guide.html"
  if scan_dir "$tmp/base/.claude/skills" "$tmp/base" >/dev/null 2>&1; then
    echo "[PASS] 実在するパスだけのガイドを合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] 実在するパスだけのガイドを合格と判定する"; fail=$((fail + 1))
  fi

  mkdir -p "$tmp/base/.claude/skills/b/references"
  printf '%s\n' '<code>generation-engine/scripts/absent.sh</code>' > "$tmp/base/.claude/skills/b/references/guide.html"
  if scan_dir "$tmp/base/.claude/skills" "$tmp/base" >/dev/null 2>&1; then
    echo "[FAIL] 不在のパスを持つガイドを不合格と判定する"; fail=$((fail + 1))
  else
    echo "[PASS] 不在のパスを持つガイドを不合格と判定する"; pass=$((pass + 1))
  fi

  if scan_dir "$tmp/base/.claude/skills/none" "$tmp/base" >/dev/null 2>&1; then
    echo "[PASS] ガイドが1件も無い場合は合格と判定する"; pass=$((pass + 1))
  else
    echo "[FAIL] ガイドが1件も無い場合は合格と判定する"; fail=$((fail + 1))
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
    scan_dir "$REPO_ROOT/.claude/skills" "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
