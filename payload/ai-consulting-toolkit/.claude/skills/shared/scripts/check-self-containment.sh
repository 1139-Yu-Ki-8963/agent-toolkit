#!/usr/bin/env bash
set -euo pipefail

# 自己完結原則の指示語検出スクリプト
# 定義元: shared/references/self-containment-rule.md（二重管理禁止）
# 用途: Markdown/HTML の表示テキストから文外参照の指示語を検出する

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_FILE="$SCRIPT_DIR/../references/self-containment-rule.md"

# 検出パターン（self-containment-rule.md と同一）
PATTERN1='(この|その|あの)(レベル|課題|基準|段階|仕組み|作業|資料|一覧|文書|現場|場合|方法)'
PATTERN2='(これ|それ|あれ)(は|が|を|により|以降|以外)'
PATTERN3='(上記|下記|前述|先述|後述)'
COMBINED="$PATTERN1|$PATTERN2|$PATTERN3"

# 除外パターン
EXCLUDE='その他|それぞれ|そのまま|どの|どれ|どこ'

usage() {
  echo "Usage: $0 --check <file> | --self-test"
  exit 1
}

strip_html_tags() {
  # HTML からタグ・script・style を除去して表示テキストを抽出
  # 見出し(h1-h6)・箇条書き(li)は除去前にMarkdown記法へ変換し、
  # 後段の見出し・箇条書き判定（ERROR/WARNING分岐）に引き継ぐ
  sed -E '
    s/<script[^>]*>.*<\/script>//g
    s/<style[^>]*>.*<\/style>//g
    s/<h[1-6][^>]*>/# /g
    s/<\/h[1-6]>//g
    s/<li[^>]*>/- /g
    s/<\/li>//g
    s/<[^>]+>//g
    s/&lt;/</g
    s/&gt;/>/g
    s/&amp;/\&/g
    s/&quot;/"/g
  '
}

strip_md_blocks() {
  # Markdown の引用ブロック・コードブロックを除外
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
    # HTML: コメント内は除外、タグ除去後のテキストを検査
    sed 's/<!--.*-->//g' "$file" | strip_html_tags > "$tmpfile"
  elif [ "$ext" = "md" ]; then
    # Markdown: コードブロック・引用ブロックを除外
    strip_md_blocks < "$file" > "$tmpfile"
  else
    cp "$file" "$tmpfile"
  fi

  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))

    # 除外パターンに該当する語を一時的にマスク
    local masked
    masked=$(echo "$line" | sed -E "s/($EXCLUDE)/___EXCLUDED___/g")

    # 検出パターンに一致するか
    if echo "$masked" | grep -qE "$COMBINED"; then
      # 見出し・箇条書き先頭・表セルかどうか判定
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

  # エラーフィクスチャ 1: 見出しに指示語
  cat > "$tmpdir/err1.md" << 'FIXTURE'
# このレベルの説明
本文テキスト
FIXTURE
  if check_file "$tmpdir/err1.md" 2>/dev/null; then
    echo "FAIL: err1（見出し指示語）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err1（見出し指示語）を検出" >&2; pass=$((pass+1))
  fi

  # エラーフィクスチャ 2: 箇条書き先頭に指示語
  cat > "$tmpdir/err2.md" << 'FIXTURE'
- その課題について
- 正常な項目
FIXTURE
  if check_file "$tmpdir/err2.md" 2>/dev/null; then
    echo "FAIL: err2（箇条書き指示語）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err2（箇条書き指示語）を検出" >&2; pass=$((pass+1))
  fi

  # エラーフィクスチャ 3: 上記/下記
  cat > "$tmpdir/err3.md" << 'FIXTURE'
- 上記の手順に従う
FIXTURE
  if check_file "$tmpdir/err3.md" 2>/dev/null; then
    echo "FAIL: err3（上記/下記）が検出されなかった" >&2; fail=$((fail+1))
  else
    echo "PASS: err3（上記/下記）を検出" >&2; pass=$((pass+1))
  fi

  # 除外フィクスチャ 1: その他
  cat > "$tmpdir/exc1.md" << 'FIXTURE'
- その他の項目
FIXTURE
  if check_file "$tmpdir/exc1.md" 2>/dev/null; then
    echo "PASS: exc1（その他）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc1（その他）が誤検出された" >&2; fail=$((fail+1))
  fi

  # 除外フィクスチャ 2: それぞれ
  cat > "$tmpdir/exc2.md" << 'FIXTURE'
- それぞれの担当
FIXTURE
  if check_file "$tmpdir/exc2.md" 2>/dev/null; then
    echo "PASS: exc2（それぞれ）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc2（それぞれ）が誤検出された" >&2; fail=$((fail+1))
  fi

  # 除外フィクスチャ 3: そのまま
  cat > "$tmpdir/exc3.md" << 'FIXTURE'
- そのまま使う
FIXTURE
  if check_file "$tmpdir/exc3.md" 2>/dev/null; then
    echo "PASS: exc3（そのまま）は除外" >&2; pass=$((pass+1))
  else
    echo "FAIL: exc3（そのまま）が誤検出された" >&2; fail=$((fail+1))
  fi

  # HTML フィクスチャ: タグ除去後に検出
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

  rm -rf "$tmpdir"

  echo "---" >&2
  echo "self-test: PASS=$pass FAIL=$fail" >&2
  [ "$fail" -eq 0 ]
}

# メイン
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
