#!/usr/bin/env bash
# 系に依存する書き方が入っていないことを確かめる（第1回改善指示書1-39）。
#
# 検出する対象は stat の直書き（オプション -f・-c）である。-f は macOS では
# 更新時刻を、GNU coreutils ではファイルシステムの情報を指す。-c は macOS に
# 無い。更新時刻は mtime_of のように系を判定するヘルパーを通して取る。
#
# ヘルパーの定義行だけは除く。定義そのものは両系のオプションを書く必要がある。
#
# 対照の文字列は printf の書式で組み立てる。この検査自身が走査の対象に含まれる
# ため、検出したい文字列をそのまま書くと自分自身を不合格にするからである。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引数が無ければ docs/skills と docs/rules の両方を走査する。体系の設計が
# 対象と定める範囲に合わせる（第1回改善指示書1-39・反証の指摘）。
if [ "$#" -ge 1 ]; then
  ROOTS="$*"
else
  ROOTS="$(cd "${SCRIPT_DIR}/../.." && pwd) $(cd "${SCRIPT_DIR}/../../../rules" && pwd)"
fi

for r in $ROOTS; do
  if [ ! -d "$r" ]; then
    echo "使い方: test-portable-commands.sh [<走査するルート> ...]" >&2
    exit 2
  fi
done

hits_in_file() {
  grep -nE 'stat[[:space:]]+-[cf]' "$1" 2>/dev/null | grep -v -e 'mtime_of()' -e 'stat-sim-fixture' || true
}

bad=0
ctl_bad=0
scanned=0
out=""

strip_root() {
  local path="$1" r
  for r in $ROOTS; do
    case "$path" in
      "$r"/*) echo "${path#"$r"/}"; return ;;
    esac
  done
  echo "$path"
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  scanned=$((scanned + 1))
  out="$(hits_in_file "$f")"
  if [ -n "$out" ]; then
    echo "[FAIL] 系依存-直書き: $(strip_root "$f")"
    printf '%s\n' "$out" | sed 's/^/         /'
    bad=$((bad + 1))
  fi
done <<EOF
$(find $ROOTS -type f -name '*.sh' | sort)
EOF

if [ "$scanned" -eq 0 ]; then
  echo "[FAIL] 走査-0件: ${ROOTS} に .sh が1本も無い"
  bad=$((bad + 1))
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/portable-commands.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

printf 'x="$(stat -%s %%m "$f")"\n' f > "${tmp}/positive-f.sh"
if [ -n "$(hits_in_file "${tmp}/positive-f.sh")" ]; then
  echo "[PASS 対照] 陽性-更新時刻の直書きを検出する"
else
  echo "[FAIL 対照] 陽性-更新時刻の直書きを検出できない"; ctl_bad=$((ctl_bad + 1))
fi

printf 'x="$(stat -%s %%Y "$f")"\n' c > "${tmp}/positive-c.sh"
if [ -n "$(hits_in_file "${tmp}/positive-c.sh")" ]; then
  echo "[PASS 対照] 陽性-片方の系にしか無い書き方を検出する"
else
  echo "[FAIL 対照] 陽性-片方の系にしか無い書き方を検出できない"; ctl_bad=$((ctl_bad + 1))
fi

printf 'x="$(stat -%s%%m "$f")"\n' f > "${tmp}/positive-nospace.sh"
if [ -n "$(hits_in_file "${tmp}/positive-nospace.sh")" ]; then
  echo "[PASS 対照] 陽性-空白を詰めた直書きを検出する"
else
  echo "[FAIL 対照] 陽性-空白を詰めた直書きを検出できない"; ctl_bad=$((ctl_bad + 1))
fi

printf 'x="$(mtime_of "$f")"\n' > "${tmp}/negative.sh"
if [ -z "$(hits_in_file "${tmp}/negative.sh")" ]; then
  echo "[PASS 対照] 陰性-ヘルパー経由は検出しない"
else
  echo "[FAIL 対照] 陰性-ヘルパー経由を誤検出する"; ctl_bad=$((ctl_bad + 1))
fi

printf 'mtime_of() { stat -%s %%Y "$1" 2>/dev/null || stat -%s %%m "$1" 2>/dev/null; }\n' c f > "${tmp}/definition.sh"
if [ -z "$(hits_in_file "${tmp}/definition.sh")" ]; then
  echo "[PASS 対照] 定義行-ヘルパーの定義は検出しない"
else
  echo "[FAIL 対照] 定義行-ヘルパーの定義を誤検出する"; ctl_bad=$((ctl_bad + 1))
fi

echo "走査 ${scanned} 件 + 対照 5 件 / 直書き ${bad} 件 / 対照の失敗 ${ctl_bad} 件"
if [ "$bad" -ne 0 ] || [ "$ctl_bad" -ne 0 ]; then
  exit 1
fi
exit 0
