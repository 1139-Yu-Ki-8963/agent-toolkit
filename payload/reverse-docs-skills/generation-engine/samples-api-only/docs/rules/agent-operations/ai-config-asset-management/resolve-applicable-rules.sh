#!/usr/bin/env bash
# 生成物である。直接編集しない（定義: delivery-payload/templates/rules/checkers/resolve-applicable-rules.sh）
# resolve-applicable-rules.sh — 対象ファイルに適用される規約（docs/rules 配下）を解決する
#
# 使い方: resolve-applicable-rules.sh <対象ファイル> [<対象ファイル>...]
# 出力:   <対象ファイル>\t<rule.md のパス>   （TSV。1マッチ1行）
#         適用が無いファイルは <対象ファイル>\t(none) を出力する
#
# 規約に対するレビューは1体のレビュアーが行うため、担当を返さない。
#
# グローバルの同名スクリプト（~/.claude/skills/managing-review-sets/scripts/resolve-applicable-rules.sh）
# との違い:
#   - 走査先: グローバルはグローバル規約フォルダ（Claude Code の設定ディレクトリ配下の scoped rule
#     置き場）を走査する。本スクリプトはカレントディレクトリ基準の docs/rules/ 配下
#     （納品先リポジトリに配布する規約フォルダ）を走査する。
#   - front matter の paths 形式: グローバルは YAML の複数行リスト（"- \"glob\"" が1行ずつ）。
#     本スクリプトは "paths: [\"glob1\",\"glob2\"]" という1行の JSON 配列
#     （docs/rules 配下の規約定義が使う形式）を読む。複数行にまたがる配列は対象外。
#   - scope: always の規約は paths の値によらず全ファイルへ適用する（本スクリプト固有の追加仕様。
#     グローバル側には scope フィールドの概念が無い）。
#
# 判定不能な場合（docs/rules/ が無い・front matter が読めない）は (none) を返して素通しする。
# エラーで止めない。状態ファイル・マーカーは作らない。
set -u

RULES_ROOT="docs/rules"

# --- rule.md の front matter 抽出 ---
# front matter は先頭行 "---" から次の "---" までの範囲に限る。

extract_scope() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && /^scope:[[:space:]]*/ {
      line=$0
      sub(/^scope:[[:space:]]*/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      print line
      exit
    }
  ' "$1" 2>/dev/null
}

extract_paths() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && /^paths:[[:space:]]*\[/ {
      line=$0
      sub(/^paths:[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$1" 2>/dev/null | tr ',' '\n' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' | sed '/^[[:space:]]*$/d'
}

# --- glob → 拡張正規表現(ERE)への変換 ---
# この環境の bash は globstar が使えるとは限らない（配布先の bash が古い可能性がある）ため、
# シェルの glob 展開（**）には頼らず、パターン文字列を ERE へ自前で変換して
# `[[ =~ ]]`（bash 3.0 以降で使用可能）で照合する。
#
#   "**/"（先頭・途中）     → 0個以上のディレクトリ階層 "([^/]+/)*"
#   "xxx/**"（末尾）        → "/" の後に1文字以上（ファイルを含む） "/.+" 相当
#   単独 "*"                → スラッシュを跨がない任意文字列 "[^/]*"
#   "?"                     → スラッシュを跨がない1文字 "[^/]"
#   その他の ERE メタ文字   → エスケープしてリテラル扱い
glob_to_ere() {
  local g="$1" out="" i=0 c len nxt prevchar
  len=${#g}
  while [ "$i" -lt "$len" ]; do
    c="${g:$i:1}"
    if [ "$c" = "*" ] && [ "${g:$((i+1)):1}" = "*" ]; then
      nxt="${g:$((i+2)):1}"
      prevchar="${out: -1}"
      if [ "$nxt" = "/" ]; then
        out="${out}([^/]+/)*"
        i=$((i+3))
        continue
      elif [ -z "$nxt" ]; then
        if [ "$prevchar" = "/" ]; then
          out="${out}.+"
        else
          out="${out}.*"
        fi
        i=$((i+2))
        continue
      else
        out="${out}[^/]*"
        i=$((i+2))
        continue
      fi
    fi
    case "$c" in
      '*') out="${out}[^/]*" ;;
      '?') out="${out}[^/]" ;;
      '.'|'+'|'('|')'|'{'|'}'|'^'|'$'|'|'|'\') out="${out}\\${c}" ;;
      *) out="${out}${c}" ;;
    esac
    i=$((i+1))
  done
  printf '%s' "$out"
}

glob_match() {
  local target="$1" glob="$2" ere
  ere="$(glob_to_ere "$glob")"
  [[ "$target" =~ ^${ere}$ ]]
}

# --- rule.md の収集（docs/rules 配下。深さ不問） ---
collect_rule_files() {
  if [ -d "$RULES_ROOT" ]; then
    find "$RULES_ROOT" -name rule.md 2>/dev/null | sort
  fi
}

# --- 1ファイル分の解決。TSV を標準出力へ書く ---
resolve_target() {
  local target="$1" found=0 rule scope glob matched
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    scope="$(extract_scope "$rule")"
    matched=0
    if [ "$scope" = "always" ]; then
      matched=1
    else
      while IFS= read -r glob; do
        [ -z "$glob" ] && continue
        if glob_match "$target" "$glob"; then
          matched=1
          break
        fi
      done <<EOF
$(extract_paths "$rule")
EOF
    fi
    if [ "$matched" -eq 1 ]; then
      printf '%s\t%s\n' "$target" "$rule"
      found=1
    fi
  done <<EOF
$(collect_rule_files)
EOF
  if [ "$found" -eq 0 ]; then
    printf '%s\t(none)\n' "$target"
  fi
}

run_cli() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $(basename "$0") <file> [<file>...]" >&2
    exit 1
  fi
  local target
  for target in "$@"; do
    resolve_target "$target"
  done
}

self_test() {
  local rc=0

  # 系1: glob にマッチしないファイルで (none) が返る
  local tmp1
  if ! tmp1="$(mktemp -d "${TMPDIR:-/tmp}/resolve-applicable-rules-self-test1.XXXXXX" 2>/dev/null)" || [ -z "$tmp1" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp1/docs/rules/code/naming"
  cat > "$tmp1/docs/rules/code/naming/rule.md" <<'EOF'
---
key: naming
scope: scoped
paths: ["src/**"]
---
# naming
EOF
  cat > "$tmp1/docs/rules/code/parent.yml" <<'EOF'
key: code
title: コード規約
EOF
  local out1
  out1="$(cd "$tmp1" && resolve_target "docs/readme.md")"
  if [ "$out1" = "$(printf 'docs/readme.md\t(none)')" ]; then
    echo "  [PASS] 系1: glob 非マッチは (none) が返る（${out1}）"
  else
    echo "  [FAIL] 系1: 期待と異なる出力（${out1}）" >&2
    rc=1
  fi
  rm -rf "$tmp1"

  # 系2: scope: always の規約が glob によらず全ファイルに適用される
  local tmp2
  if ! tmp2="$(mktemp -d "${TMPDIR:-/tmp}/resolve-applicable-rules-self-test2.XXXXXX" 2>/dev/null)" || [ -z "$tmp2" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp2/docs/rules/agent/behavior"
  cat > "$tmp2/docs/rules/agent/behavior/rule.md" <<'EOF'
---
key: behavior
scope: always
paths: []
---
# behavior
EOF
  cat > "$tmp2/docs/rules/agent/parent.yml" <<'EOF'
key: agent
title: AI運用
EOF
  local out2
  out2="$(cd "$tmp2" && resolve_target "anything/random/path.xyz")"
  if [ "$out2" = "$(printf 'anything/random/path.xyz\tdocs/rules/agent/behavior/rule.md')" ]; then
    echo "  [PASS] 系2: scope:always は glob によらず適用される（${out2}）"
  else
    echo "  [FAIL] 系2: 期待と異なる出力（${out2}）" >&2
    rc=1
  fi
  rm -rf "$tmp2"

  # 系3: 1つのファイルに複数の規約が適用されるとき、複数行が返る
  local tmp3
  if ! tmp3="$(mktemp -d "${TMPDIR:-/tmp}/resolve-applicable-rules-self-test3.XXXXXX" 2>/dev/null)" || [ -z "$tmp3" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp3/docs/rules/a/one" "$tmp3/docs/rules/b/two"
  cat > "$tmp3/docs/rules/a/one/rule.md" <<'EOF'
---
key: one
scope: scoped
paths: ["src/**"]
---
# one
EOF
  cat > "$tmp3/docs/rules/a/parent.yml" <<'EOF'
key: a
title: カテゴリA
EOF
  cat > "$tmp3/docs/rules/b/two/rule.md" <<'EOF'
---
key: two
scope: always
paths: []
---
# two
EOF
  cat > "$tmp3/docs/rules/b/parent.yml" <<'EOF'
key: b
title: カテゴリB
EOF
  local out3 lines3
  out3="$(cd "$tmp3" && resolve_target "src/foo.ts")"
  lines3="$(printf '%s\n' "$out3" | wc -l | tr -d '[:space:]')"
  if [ "$lines3" = "2" ] && printf '%s\n' "$out3" | grep -q 'docs/rules/a/one/rule.md' && printf '%s\n' "$out3" | grep -q 'docs/rules/b/two/rule.md'; then
    echo "  [PASS] 系3: 複数規約が適用されるファイルは複数行返る（${lines3}行）"
  else
    echo "  [FAIL] 系3: 期待と異なる出力（${out3}）" >&2
    rc=1
  fi
  rm -rf "$tmp3"

  # 系4: docs/rules/ が存在しない場合は判定不能として (none) を返す（素通し）
  local tmp4
  if ! tmp4="$(mktemp -d "${TMPDIR:-/tmp}/resolve-applicable-rules-self-test4.XXXXXX" 2>/dev/null)" || [ -z "$tmp4" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  local out4
  out4="$(cd "$tmp4" && resolve_target "src/app.ts")"
  if [ "$out4" = "$(printf 'src/app.ts\t(none)')" ]; then
    echo "  [PASS] 系4: docs/rules/ 不在は (none) で素通しする（${out4}）"
  else
    echo "  [FAIL] 系4: 期待と異なる出力（${out4}）" >&2
    rc=1
  fi
  rm -rf "$tmp4"

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) run_cli "$@" ;;
esac
