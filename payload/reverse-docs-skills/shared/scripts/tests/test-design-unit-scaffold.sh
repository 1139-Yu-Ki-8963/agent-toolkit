#!/usr/bin/env bash
# scaffold-design-unit.sh の黒箱テスト。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCAFFOLD="$REPO_ROOT/shared/scripts/scaffold-design-unit.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-scaffold-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# 1. 5種別×2phaseの展開が成功する
docs1="$tmp/docs1"
mkdir -p "$docs1"
for kind in api table batch report external; do
  for phase in basic detail; do
    bash "$SCAFFOLD" "$kind" "$phase" "$docs1" "case-${kind}" "ケース${kind}" >/dev/null \
      || { echo "FAIL: 展開に失敗しました: $kind $phase" >&2; exit 1; }
  done
done
echo "PASS: 5種別×2phaseの展開が成功"

# 2. --verify が成功する
for kind in api table batch report external; do
  for phase in basic detail; do
    bash "$SCAFFOLD" --verify "$kind" "$phase" "$docs1" "case-${kind}" >/dev/null \
      || { echo "FAIL: verifyに失敗しました: $kind $phase" >&2; exit 1; }
  done
done
echo "PASS: --verify が全件成功"

# 3. --dry-run が何も書かない
docs3="$tmp/docs3"
mkdir -p "$docs3"
before="$(find "$docs3" | sort)"
bash "$SCAFFOLD" --dry-run api basic "$docs3" dryrun-case "ドライラン" >/dev/null \
  || { echo "FAIL: --dry-run 自体が異常終了しました" >&2; exit 1; }
after="$(find "$docs3" | sort)"
if [ "$before" != "$after" ]; then
  echo "FAIL: --dry-run がファイルを書き込みました" >&2
  exit 1
fi
if [ -d "$docs3/API" ]; then
  echo "FAIL: --dry-run が出力ディレクトリを作成しました" >&2
  exit 1
fi
echo "PASS: --dry-run は何も書かない"

# 4. symlink を含む出力先が拒否される
docs4="$tmp/docs4"
external4="$tmp/external4-target"
mkdir -p "$docs4" "$external4"
ln -s "$external4" "$docs4/API"
if bash "$SCAFFOLD" api basic "$docs4" symlink-case "シムリンク" >/dev/null 2>&1; then
  echo "FAIL: symlinkを含む出力先を受理しました" >&2
  exit 1
fi
if [ -e "$external4/api-symlink-case" ]; then
  echo "FAIL: symlink経由で外部treeへ書き込みました" >&2
  exit 1
fi
echo "PASS: symlinkを含む出力先を拒否"

# 5. 同じ phase の再実行が拒否される
docs5="$tmp/docs5"
mkdir -p "$docs5"
bash "$SCAFFOLD" api basic "$docs5" repeat-case "リピート" >/dev/null
if bash "$SCAFFOLD" api basic "$docs5" repeat-case "リピート再実行" >/dev/null 2>&1; then
  echo "FAIL: 同じphaseの再実行を受理しました" >&2
  exit 1
fi
echo "PASS: 同じphaseの再実行を拒否"

# 6. basic の実行後に detail を実行しても basic が上書きされない
docs6="$tmp/docs6"
mkdir -p "$docs6"
bash "$SCAFFOLD" api basic "$docs6" order-case "オーダー基本" >/dev/null
basic_before="$(cat "$docs6/API/api-order-case/基本設計/API基本設計書.md")"
bash "$SCAFFOLD" api detail "$docs6" order-case "オーダー詳細" >/dev/null
basic_after="$(cat "$docs6/API/api-order-case/基本設計/API基本設計書.md")"
if [ "$basic_before" != "$basic_after" ]; then
  echo "FAIL: detail展開でbasicが上書きされました" >&2
  exit 1
fi
if [ ! -f "$docs6/API/api-order-case/詳細設計/API詳細設計書.md" ]; then
  echo "FAIL: detail展開が行われませんでした" >&2
  exit 1
fi
echo "PASS: basic実行後のdetail実行でbasicが保持される"

# 7. 未置換のトークンが検出される
docs7="$tmp/docs7"
mkdir -p "$docs7"
bash "$SCAFFOLD" api basic "$docs7" token-case "トークン確認" >/dev/null
printf '<API名>\n' >> "$docs7/API/api-token-case/基本設計/API基本設計書.md"
if bash "$SCAFFOLD" --verify api basic "$docs7" token-case >/dev/null 2>&1; then
  echo "FAIL: 未置換トークンが残っているのにverifyが成功しました" >&2
  exit 1
fi
echo "PASS: 未置換トークンをverifyが検出"

# 8. 章の欠落が検出される
docs8="$tmp/docs8"
mkdir -p "$docs8"
bash "$SCAFFOLD" api basic "$docs8" heading-case "見出し確認" >/dev/null
target8="$docs8/API/api-heading-case/基本設計/API基本設計書.md"
grep -v '^## §1 外部仕様$' "$target8" > "$target8.tmp"
mv "$target8.tmp" "$target8"
if bash "$SCAFFOLD" --verify api basic "$docs8" heading-case >/dev/null 2>&1; then
  echo "FAIL: 見出し欠落があるのにverifyが成功しました" >&2
  exit 1
fi
echo "PASS: 見出しの欠落をverifyが検出"

echo "PASS: test-design-unit-scaffold.sh 全8項目"
