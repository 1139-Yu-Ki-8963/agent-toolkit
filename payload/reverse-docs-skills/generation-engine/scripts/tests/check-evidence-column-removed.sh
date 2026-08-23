#!/usr/bin/env bash
# check-evidence-column-removed.sh — 設計書の様式に根拠の欄が残っていないかを見る
#
# 納品先の判断で、設計書から根拠（対象コードのファイルと行）を外し、一から
# 書いた設計書と同じ体裁にする整理が決まった（改善課題1-199・1-206・1-227）。
# 42 の様式のうち 41 は外し終えたが、テーブル定義書の外部キーの表だけ「出典参照」
# という別の名前で残っていた（実測 2026-08-24）。名前を変えて残ると、根拠という
# 語だけを探しても見つからない。
#
# 根拠を書かせる欄は、名前が違っても役割で見分けられる。表の見出しに現れる
# 次の語を、根拠の欄として扱う。
#
#   根拠 / 出典 / 出典参照 / 根拠パス / 対象コード / 抽出元 / ソース参照
#
# 書き手向けの記入規則（HTML コメントや本文の説明）で「原本コードを根拠に
# しない」のように述べるのは、外す整理そのものを説明する記述であり対象外とする。
# 表の見出し行（先頭が縦棒の行）だけを見る。
#
# 使い方:
#   check-evidence-column-removed.sh              様式を走査する
#   check-evidence-column-removed.sh --self-test  このスクリプト自身の判定を確かめる
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATE_ROOT="${REPO_ROOT}/delivery-payload/templates/リバース検証"
# 様式だけを見ていると、生成済みの見本に古い欄が残っていても気づけない。
# 実測 2026-08-24: 様式は「参照先」へ改名済みだったが、見本の画面詳細設計書
# 10 件（md 5・HTML 5）は「根拠」のまま残っていた。見本も走査対象へ加える。
# 対象は設計書だけとする。規約の定義（docs/rules 配下）が持つ「根拠」の欄は、
# 規則ごとの根拠を書く別の仕組みであり、外す整理の対象ではない。
SAMPLE_ROOT="${REPO_ROOT}/generation-engine/samples/docs/design"

# 根拠の欄とみなす見出し語。名前を変えて残る取り残しを拾うため、役割が同じ語を並べる。
EVIDENCE_HEADS='根拠|出典|出典参照|根拠パス|対象コード|抽出元|ソース参照'

unknown() {
  echo "[UNKNOWN] $1" >&2
  exit 2
}

# 表の見出し行だけを見て、根拠の欄を持つ行を返す。
# 全角文字を含む正規表現での照合のため UTF-8 のロケールを明示する
# （.claude/rules/always/design-record/implementation-decision/rule.md の
# 「ロケールの使い分け」節）。
scan_evidence_columns() {
  local root="$1" f rel hit
  # 対象は Markdown だけとする。生成された HTML は元の Markdown を 1 行の
  # データとして埋め込むため、表の見出しが行頭に来ず、この走査では拾えない。
  # HTML は Markdown から作られるので、Markdown が直れば作り直しで揃う。
  find "$root" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$root"/}"
    hit="$(LC_ALL=en_US.UTF-8 awk -v heads="$EVIDENCE_HEADS" '
      /^\|/ {
        # 区切り行は横棒を含む。見出し行と区別する。
        if ($0 ~ /^\|[-: ]*-[-: ]*\|/) next
        n = split($0, c, "|")
        for (i = 2; i < n; i++) {
          v = c[i]; gsub(/^[ \t]+|[ \t]+$/, "", v)
          if (v ~ ("^(" heads ")$")) { print FNR ": " v; exit }
        }
      }
    ' "$f")"
    [ -n "$hit" ] && printf '%s\t%s\n' "$rel" "$hit"
  done
}

run_check() {
  local root="${1:-}"
  local found="" n roots=""

  if [ -n "$root" ]; then
    [ -d "$root" ] || unknown "指定された置き場が見つからないため判定できません（参照したパス: ${root}）"
    roots="$root"
  else
    [ -d "$TEMPLATE_ROOT" ] || unknown "様式の置き場が見つからないため判定できません（参照したパス: ${TEMPLATE_ROOT}。配布物の構成が変わった可能性があります）"
    roots="$TEMPLATE_ROOT"
    # 見本は無くても構わない。あれば対象へ加える。
    [ -d "$SAMPLE_ROOT" ] && roots="${roots}"$'\n'"$SAMPLE_ROOT"
  fi

  local r hit
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    hit="$(scan_evidence_columns "$r")"
    [ -n "$hit" ] && found="${found}${found:+$'\n'}${hit}"
  done <<< "$roots"
  n="$(printf '%s' "$found" | LC_ALL=C grep -c . || :)"

  if [ "${n:-0}" -eq 0 ]; then
    echo "[PASS] 根拠の欄を持つ様式=0件"
    return 0
  fi

  echo "[FAIL] 根拠の欄を持つ様式=${n}件"
  printf '%s\n' "$found" | while IFS=$'\t' read -r rel hit; do
    [ -n "$rel" ] && echo "  ${rel} — ${hit}"
  done
  return 1
}

run_self_test() {
  local tmp n_pass=0 n_fail=0

  if ! tmp="$(mktemp -d 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT

  assert() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
      echo "[PASS] ${name}"
      n_pass=$((n_pass + 1))
    else
      echo "[FAIL] ${name}（期待 ${want} / 実際 ${got}）"
      n_fail=$((n_fail + 1))
    fi
  }

  mkdir -p "$tmp/clean" "$tmp/dirty" "$tmp/alias" "$tmp/prose"

  printf '%s\n' '| カラム | 型 |' '|---|---|' '| id | 整数 |' > "$tmp/clean/a.md"
  ( run_check "$tmp/clean" >/dev/null 2>&1 )
  assert "根拠の欄が無ければ合格" 0 $?

  printf '%s\n' '| カラム | 型 | 根拠 |' '|---|---|---|' '| id | 整数 | a.js:1 |' > "$tmp/dirty/a.md"
  ( run_check "$tmp/dirty" >/dev/null 2>&1 )
  assert "根拠の欄があれば不合格" 1 $?

  printf '%s\n' '| カラム | 型 | 出典参照 |' '|---|---|---|' '| id | 整数 | a.js:1 |' > "$tmp/alias/a.md"
  ( run_check "$tmp/alias" >/dev/null 2>&1 )
  assert "別の名前で残っていても不合格" 1 $?

  printf '%s\n' '本文で「原本コードを根拠にしない」と述べる。' '' '| カラム | 型 |' '|---|---|' '| id | 整数 |' > "$tmp/prose/a.md"
  ( run_check "$tmp/prose" >/dev/null 2>&1 )
  assert "記入規則の説明は対象外" 0 $?

  ( run_check "$tmp/no-such-dir" >/dev/null 2>&1 )
  assert "置き場が無ければ判定不能" 2 $?

  echo "---"
  echo "SELF-TEST SUMMARY: 実行 $((n_pass + n_fail)) 件 合格 ${n_pass} 件 不合格 ${n_fail} 件"
  [ "$n_fail" -eq 0 ] || exit 1
  exit 0
}

case "${1:-}" in
  --self-test) run_self_test ;;
  *) run_check "${1:-}" ;;
esac
