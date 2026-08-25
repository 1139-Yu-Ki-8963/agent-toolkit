#!/usr/bin/env bash
# check-case49-orphan-html.sh — 1-205の判定表の「確かめる手段」欄を短くする
#
# 判定「全ケースPASS」「旧ディレクトリ名の直書きが無い」を
# 指示書の表へ直接パイプ付きコマンドで書くと、片付けの判定器が
# 縦棒を列の区切りと読み違え、判定行そのものを壊す。先例:
# docs/scripts/check-broken-verdict-rows.sh・
# docs/scripts/check-layer1-declarations.sh。
# 式をこのファイルへ移す。
# 表からは短いファイル名だけを呼ぶ形にする。
#
# 使い方:
#   bash docs/scripts/check-case49-orphan-html.sh --count-pass
#     build-portal.sh --self-test --case 49 を実行し、
#     「PASS: --self-test ケース49」で始まる行が9件かどうかを判定する。
#   bash docs/scripts/check-case49-orphan-html.sh --stale-paths
#     run_orphaned_html_self_test 関数の行範囲を切り出し、project-portal配下
#     の旧ディレクトリ名（test_portal/基盤・test_portal/画面）の直書きが
#     0件かどうかを判定する。
#
# 終了コード: 満たせば0、満たさなければ1。

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
build_portal="$repo_root/generation-engine/scripts/build-portal.sh"

if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-case49-orphan-html.XXXXXX" \
    2>/dev/null)" || [ -z "$work" ]; then
  msg="[UNKNOWN] 一時領域を作成できません"
  msg+="（mktempがサンドボックス制約等で失敗した可能性があります）"
  echo "$msg" >&2
  exit 2
fi
trap 'rm -rf "$work"' EXIT

case "${1:-}" in
  --count-pass)
    bash "$build_portal" --self-test --case 49 > "$work/case49.log" 2>&1
    count="$(grep -c '^PASS: --self-test ケース49' "$work/case49.log")"
    echo "PASS件数: $count / 9"
    test "$count" -eq 9
    ;;
  --stale-paths)
    sed -n '/^run_orphaned_html_self_test/,/^}/p' "$build_portal" > "$work/fn.txt"
    count="$(grep -c 'test_portal/基盤' "$work/fn.txt")"
    count2="$(grep -c 'test_portal/画面' "$work/fn.txt")"
    total=$((count + count2))
    echo "旧ディレクトリ名の直書き: $total 件"
    test "$total" -eq 0
    ;;
  *)
    echo "usage: check-case49-orphan-html.sh --count-pass|--stale-paths" >&2
    exit 2
    ;;
esac
