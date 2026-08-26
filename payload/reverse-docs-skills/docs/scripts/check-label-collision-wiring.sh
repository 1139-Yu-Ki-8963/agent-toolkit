#!/usr/bin/env bash
# check-label-collision-wiring.sh — 置き場の名前と表示見出しの衝突を検出する
# 指示書.md の判定表3行目を短くする
#
# 判定「第1層の集約の一覧に含まれる」を指示書の表へ直接パイプ付きコマンドで
# 書くと、片付けの判定器（docs/scripts/judge-task-done.sh）が縦棒を列の区切り
# と読み違え、判定行そのものを壊す。実測（2026-08-26）でこの事故が起き、
# 状態欄が「grep -q 'check-portal-label-collision'`」という定めていない値に
# なった。先例: docs/scripts/check-broken-verdict-rows.sh・
# docs/scripts/check-layer1-declarations.sh・docs/scripts/check-case49-orphan-html.sh。
# 式をこのファイルへ移す。表からは短いファイル名だけを呼ぶ形にする。
#
# 使い方:
#   bash docs/scripts/check-label-collision-wiring.sh
#     run-layer-machine-checks.sh --list の出力に
#     check-portal-label-collision が含まれるかどうかを判定する。
#   bash docs/scripts/check-label-collision-wiring.sh --self-test
#     上記判定が動くことを確認する自己テストを実行する。
#
# 終了コード: 満たせば0、満たさなければ1、判定不能なら2。

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
AGGREGATOR="$repo_root/generation-engine/scripts/verification/run-layer-machine-checks.sh"

check_wired() {
  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-label-collision-wiring.XXXXXX" \
      2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 一時領域を作成できません（mktempがサンドボックス制約等で失敗した可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  if ! bash "$AGGREGATOR" --list > "$work/list.log" 2>&1; then
    echo "[UNKNOWN] run-layer-machine-checks.sh --list の実行に失敗しました" >&2
    return 2
  fi

  if grep -q 'check-portal-label-collision' "$work/list.log"; then
    echo "[PASS] 第1層の集約の一覧に check-portal-label-collision が含まれる"
    return 0
  fi
  echo "[FAIL] 第1層の集約の一覧に check-portal-label-collision が含まれない" >&2
  return 1
}

run_self_test() {
  local rc=0 pass=0 fail=0

  if check_wired >/dev/null 2>&1; then
    echo "  [PASS] 一覧に含まれる判定が動く"; pass=$((pass + 1))
  else
    echo "  [FAIL] 一覧に含まれる判定が動く" >&2; fail=$((fail + 1)); rc=1
  fi

  # --list の出力を経由せずに、grep 判定そのものの正しさを確認する
  local work
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-label-collision-wiring-self.XXXXXX" \
      2>/dev/null)" || [ -z "$work" ]; then
    echo "  [UNKNOWN] 一時領域を作成できません" >&2
    fail=$((fail + 1)); rc=1
  else
    printf 'generation-engine/scripts/tests/check-portal-label-collision.sh\n' \
      > "$work/hit.log"
    if grep -q 'check-portal-label-collision' "$work/hit.log"; then
      echo "  [PASS] 一致する行があれば検出する"; pass=$((pass + 1))
    else
      echo "  [FAIL] 一致する行があれば検出する" >&2; fail=$((fail + 1)); rc=1
    fi

    printf 'generation-engine/scripts/tests/check-portal-dir-ascii.sh\n' \
      > "$work/miss.log"
    if ! grep -q 'check-portal-label-collision' "$work/miss.log"; then
      echo "  [PASS] 一致しなければ検出しない"; pass=$((pass + 1))
    else
      echo "  [FAIL] 一致しなければ検出しない" >&2; fail=$((fail + 1)); rc=1
    fi
    rm -rf "$work"
  fi

  printf '実行 %d 件 / 成功 %d 件 / 失敗 %d 件\n' "$((pass + fail))" "$pass" "$fail"
  return "$rc"
}

case "${1:-}" in
  --self-test) run_self_test ;;
  "") check_wired ;;
  *)
    echo "usage: check-label-collision-wiring.sh [--self-test]" >&2
    exit 2
    ;;
esac
