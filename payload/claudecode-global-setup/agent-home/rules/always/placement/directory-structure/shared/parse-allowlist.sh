#!/usr/bin/env bash
# lib/parse-allowlist.sh — 許可リストパース共通関数
# check-mkdir-allowlist.sh と check-write-implicit-dir.sh から source される

parse_root_allowlist() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '/^## ルート直下許可ディレクトリ/{f=1;next} f && /^## /{exit} f' "$file" \
    | grep -E '^\|[^|]+\|' \
    | grep -v '^| *ディレクトリ名' \
    | grep -v '^| *---' \
    | grep -v '^| *-' \
    | sed 's/^ *| *//; s/ *|.*//' \
    | grep -v '^$'
}

parse_sub_allowlist() {
  local file="$1"
  local parent="$2"
  [ -f "$file" ] || return 1
  awk -v p="### ${parent}" 'BEGIN{f=0} $0==p{f=1;next} f && /^### /{exit} f' "$file" \
    | grep -E '^\|[^|]+\|' \
    | grep -v '^| *ディレクトリ名' \
    | grep -v '^| *---' \
    | grep -v '^| *-' \
    | sed 's/^ *| *//; s/ *|.*//' \
    | grep -v '^$'
}
