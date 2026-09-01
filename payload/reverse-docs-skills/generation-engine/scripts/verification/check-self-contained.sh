#!/usr/bin/env bash
# check-self-contained.sh — 自立の判定。生成連鎖のスクリプトが、この配布物の外
# （マシン固有のホーム配下・絶対パス）へ依存していないかを走査する。
#
# 判定: 走査対象のスクリプト本文に、コメント行を除き、/Users/ または /home/ で
#   始まる絶対パス、もしくは ~/ 展開のホーム参照が現れたら違反として数える。
#   ${HOME} 変数参照そのものは、実行時に環境へ追従するため違反としない。
# 対象: 生成連鎖が実際に呼ぶ置き場（scripts 配下の主要ディレクトリ）。
#   リポジトリ全体を無差別に走査しない。保守用の道具（正本専用）は意図的に
#   ホーム配下を参照するため、対象を生成連鎖に絞る（設計判断は
#   .claude/rules/scoped/portal/page-conventions/rule.md の check-self-contained.sh 節）。
#
# 使い方:
#   check-self-contained.sh              実データを走査する（違反1件以上で終了コード1）
#   check-self-contained.sh --self-test  判定の妥当性を検査する
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SCAN_DIRS=(
  "generation-engine/scripts/portal-input"
  "generation-engine/scripts/extract"
  "generation-engine/scripts/unit-list"
  "generation-engine/scripts/detail-pages"
  "generation-engine/scripts/rules"
  "generation-engine/scripts/verification"
)

scan() {
  local base="$1" violations=0 f rel line
  local dirs=()
  local d
  for d in "${SCAN_DIRS[@]}"; do
    [ -d "$base/$d" ] && dirs+=("$base/$d")
  done
  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "[UNKNOWN] 走査対象のディレクトリが1件も見つからないため判定できません（base=${base}）"
    return 2
  fi
  local self_rel="generation-engine/scripts/verification/check-self-contained.sh"
  while IFS= read -r f; do
    rel="${f#"$base"/}"
    # 自分自身は対象外(自己テストの試験データが検出語を正当に含むため)
    [ "$rel" = "$self_rel" ] && continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "[FAIL] ${rel}:${line}"
      violations=$((violations + 1))
    done < <(awk '
      /^[[:space:]]*#/ { next }
      /(^|["=[:space:](])\/Users\/[A-Za-z0-9_.-]+\// || /(^|["=[:space:](])\/home\/[A-Za-z0-9_.-]+\// || /(^|["=[:space:]])~\// { print NR }
    ' "$f")
  done < <(find "${dirs[@]}" -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
  if [ "$violations" -eq 0 ]; then
    echo "[PASS] 自立: マシン固有パスへの依存なし"
  fi
  echo "自立違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0 out
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/self-contained.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
    return 2
  fi
  mkdir -p "$tmp/base/generation-engine/scripts/verification"
  printf '%s\n' '#!/usr/bin/env bash' 'cp /Users/somebody/data.txt ./out' > "$tmp/base/generation-engine/scripts/verification/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "  [FAIL] ホーム配下の絶対パスを違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  elif printf '%s' "$out" | grep -q 'a.sh:2'; then
    echo "  [PASS] ホーム配下の絶対パスを違反と判定し行番号を示す"; pass=$((pass + 1))
  else
    echo "  [FAIL] 違反は出たが行番号を示さない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  printf '%s\n' '#!/usr/bin/env bash' '# コメントの /Users/example は違反にしない' 'echo "${HOME}/ok"' > "$tmp/base/generation-engine/scripts/verification/a.sh"
  if out="$(scan "$tmp/base" 2>&1)"; then
    echo "  [PASS] コメントと \${HOME} 参照は違反にしない"; pass=$((pass + 1))
  else
    echo "  [FAIL] コメントと \${HOME} 参照は違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  --repo)
    # 検証ループ(run-verification-loop.sh)からの呼び出し契約。走査の起点を差し替える
    [ -n "${2:-}" ] || { echo "使い方: $(basename "$0") [--self-test|--repo <パス>]" >&2; exit 2; }
    scan "$2"; exit $?
    ;;
  "") scan "$REPO_ROOT"; exit $? ;;
  *) echo "使い方: $(basename "$0") [--self-test|--repo <パス>]" >&2; exit 2 ;;
esac
