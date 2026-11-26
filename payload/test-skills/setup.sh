#!/usr/bin/env bash
# test-skills の準備のスクリプト。
# このフォルダの直下で走らせる。
#
#   ./setup.sh   designing-test-cases が使う Python のパッケージを確かめる

set -euo pipefail

cd "$(dirname "$0")"

for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "知らない引数です: $arg" >&2; exit 2 ;;
  esac
done

# designing-test-cases のペアワイズの表に要る Python のパッケージ
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import allpairspy' 2>/dev/null; then
    echo "python3 と allpairspy があります。"
  else
    echo "注意: allpairspy がありません。designing-test-cases でペアワイズの表を作るときは、次を走らせてください。"
    echo "  python3 -m pip install allpairspy"
    echo "  (システムの Python に入れられないときの例: python3 -m venv .venv && source .venv/bin/activate && python3 -m pip install allpairspy)"
  fi
else
  echo "注意: python3 がありません。designing-test-cases のペアワイズの表は作れません。"
fi

echo
echo "準備が終わりました。このフォルダで Claude Code を開くと、.claude/skills/ の skill が読み込まれます。"
