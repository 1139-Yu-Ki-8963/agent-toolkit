#!/usr/bin/env bash
set -euo pipefail

# 自己完結原則の指示語検出スクリプト
# 定義元: shared/references/self-containment-rule.md（single source of truth）
# 検出パターン・除外リストは RULE_FILE から実行時に読み込む（二重管理禁止）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_FILE="$SCRIPT_DIR/../references/self-containment-rule.md"

parse_rule_file() {
  local rule="$1"
  COMBINED=""
  EXCLUDE=""
  local in_section=0
  while IFS= read -r line; do
    case "$line" in
      "## 検出パターン"*) in_section=1 ;;
      "## "*)
        if [ "$in_section" = 1 ]; then in_section=0; fi ;;
    esac
    if [ "$in_section" = 1 ]; then
      case "$line" in
        "- ("*)
          local pat="${line#- }"
          if [ -n "$COMBINED" ]; then
            COMBINED="$COMBINED|$pat"
          else
            COMBINED="$pat"
          fi ;;
      esac
    fi
    case "$line" in
      "除外:"*)
        EXCLUDE=$(echo "${line#除外: }" | tr '／' '|' | sed 's/|引用ブロック内.*$//' | tr -d ' ') ;;
    esac
  done < "$rule"
}

usage() {
  echo "Usage: $0 --check <file> | --self-test" >&2
  exit 1
}

strip_html_tags() {
  sed -E '
    s/<script[^>]*>.*<\/script>//g
    s/<style[^>]*>.*<\/style>//g
    s/<h[1-6][^>]*>/# /g
    s/<\/h[1-6]>//g
    s/<li[^>]*>/- /g
    s/<\/li>//g
    s/<[^>]+>//g
    s/\&lt;/</g
    s/\&gt;/>/g
    s/\&amp;/\&/g
    s/\&quot;/"/g
  '
}

strip_md_blocks() {
  awk '
    /^```/ { in_code = !in_code; next }
    in_code { next }
    /^>/ { next }
    { print }
  '
}

check_file() {
  local file="$1"
  local ext="${file##*.}"
  local errors=0
  local warnings=0
  local tmpfile
  tmpfile=$(mktemp)

  if [ "$ext" = "html" ] || [ "$ext" = "htm" ]; then
    sed 's/<!--.*-->//g' "$file" | strip_html_tags > "$tmpfile"
  elif [ "$ext" = "md" ]; then
    strip_md_blocks < "$file" > "$tmpfile"
  else
    cp "$file" "$tmpfile"
  fi

  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    local masked
    masked=$(echo "$line" | sed -E "s/($EXCLUDE)/___EXCLUDED___/g")
    if echo "$masked" | grep -qE "$COMBINED"; then
      if echo "$line" | grep -qE '^(#{1,6}\s|[-*+]\s|\|)'; then
        echo "ERROR: $file:$line_num: $line" >&2
        errors=$((errors + 1))
      else
        echo "WARNING: $file:$line_num: $line" >&2
        warnings=$((warnings + 1))
      fi
    fi
  done < "$tmpfile"

  rm -f "$tmpfile"

  if [ "$errors" -gt 0 ]; then
    echo "検出結果: エラー ${errors}件, 警告 ${warnings}件" >&2
    return 2
  elif [ "$warnings" -gt 0 ]; then
    echo "検出結果: 警告 ${warnings}件（エラーなし）" >&2
    return 0
  else
    echo "検出結果: 違反なし" >&2
    return 0
  fi
}

self_test() {
  local pass=0
  local fail=0
  local tmpdir
  tmpdir=$(mktemp -d)

  cat > "$tmpdir/err1.md" << 'FIXTURE'
# このレベルの説明
本文テキスト
FIXTURE
  if check_file "$tmpdir/err1.md" 2>/dev/null; then
    echo "FAIL: err1（見出し指示語）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err1（見出し指示語）を検出" >&2; pass=$((pass+1))
  fi

  cat > "$tmpdir/err2.md" << 'FIXTURE'
- その課題について
- 正常な項目
FIXTURE
  if check_file "$tmpdir/err2.md" 2>/dev/null; then
    echo "FAIL: err2（箇条書き指示語）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err2（箇条書き指示語）を検出" >&2; pass=$((pass+1))
  fi

  cat > "$tmpdir/err3.md" << 'FIXTURE'
- 上記の手順に従う
FIXTURE
  if check_file "$tmpdir/err3.md" 2>/dev/null; then
    echo "FAIL: err3（上記/下記）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err3（上記/下記）を検出" >&2; pass=$((pass+1))
  fi

  cat > "$tmpdir/exc1.md" << 'FIXTURE'
- その他の項目
FIXTURE
  if check_file "$tmpdir/exc1.md" 2>/dev/null; then
    echo "PASS: exc1（その他）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc1（その他）が誤検出された" >&2; fail=$((fail+1))
  fi

  cat > "$tmpdir/exc2.md" << 'FIXTURE'
- それぞれの担当
FIXTURE
  if check_file "$tmpdir/exc2.md" 2>/dev/null; then
    echo "PASS: exc2（それぞれ）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc2（それぞれ）が誤検出された" >&2; fail=$((fail+1))
  fi

  cat > "$tmpdir/exc3.md" << 'FIXTURE'
- そのまま使う
FIXTURE
  if check_file "$tmpdir/exc3.md" 2>/dev/null; then
    echo "PASS: exc3（そのまま）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc3（そのまま）が誤検出された" >&2; fail=$((fail+1))
  fi

  cat > "$tmpdir/err_html.html" << 'FIXTURE'
<html><body>
<h2>この基準について</h2>
<p>正常なテキスト</p>
</body></html>
FIXTURE
  if check_file "$tmpdir/err_html.html" 2>/dev/null; then
    echo "FAIL: err_html（HTML見出し指示語）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err_html（HTML見出し指示語）を検出" >&2; pass=$((pass+1))
  fi

  # パターン追従テスト: RULE_FILE の内容変更に検出結果が追従するか
  local backup
  backup=$(cat "$RULE_FILE")
  # 一時的に「方法」を検出パターンから削除
  sed -i.bak 's/|方法)/)/g' "$RULE_FILE"
  parse_rule_file "$RULE_FILE"  # 再パース
  cat > "$tmpdir/follow.md" << 'FIXTURE'
- この方法について
FIXTURE
  if check_file "$tmpdir/follow.md" 2>/dev/null; then
    echo "PASS: follow（パターン追従: 削除した語は検出されない）" >&2; pass=$((pass+1))
  else
    echo "FAIL: follow（パターン追従: 削除した語がまだ検出される）" >&2; fail=$((fail+1))
  fi
  # RULE_FILE を復元
  mv "$RULE_FILE.bak" "$RULE_FILE"
  parse_rule_file "$RULE_FILE"  # 再パース

  rm -rf "$tmpdir"

  echo "---" >&2
  echo "self-test: PASS=$pass FAIL=$fail" >&2
  [ "$fail" -eq 0 ]
}

# パターンをロード
parse_rule_file "$RULE_FILE"

case "${1:-}" in
  --check)
    [ -z "${2:-}" ] && usage
    check_file "$2"
    ;;
  --self-test)
    self_test
    ;;
  *)
    usage
    ;;
esac
