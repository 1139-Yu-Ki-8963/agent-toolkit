#!/usr/bin/env bash
# check-document-style-register-exclusion-source.sh
#
# 目的（1-260）:
#   文書の文体の検査（generation-engine/scripts/check-document-style-register.sh）
#   の除外対象一覧が、様式の定義側（delivery-payload/references/
#   document-style-exclusions.json）にあり、検査スクリプト自身へ直書き
#   されていないことを確かめる。判定は次の3点。
#     1. 定義ファイルが実在し、実測で判明した3つの対象
#        （design-notes.md・SKILL.md・rule-reviewer.md）を含む
#     2. 検査スクリプトが定義ファイルを参照している（jq等で読んでいる）
#     3. 検査スクリプトの本番コード（self_test関数より前）に、
#        除外対象のファイル名が文字列として直書きされていない
#        （self_test関数はケース用の固定名を使ってよいため対象外とする）
#
# 使い方:
#   check-document-style-register-exclusion-source.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
EXCL_JSON="${REPO_ROOT}/delivery-payload/references/document-style-exclusions.json"
TARGET="${REPO_ROOT}/generation-engine/scripts/check-document-style-register.sh"
REQUIRED_NAMES=("design-notes.md" "SKILL.md" "rule-reviewer.md")

fail=0

if [ ! -f "$EXCL_JSON" ]; then
  echo "FAIL: 除外一覧の定義ファイルが存在しません: $EXCL_JSON"
  fail=1
else
  count="$(jq -r '.excludedBasenames | length' "$EXCL_JSON" 2>/dev/null || echo 0)"
  if [ "${count:-0}" -lt 3 ]; then
    echo "FAIL: 除外一覧の件数が不足しています（${count:-0}件）: $EXCL_JSON"
    fail=1
  fi
  for name in "${REQUIRED_NAMES[@]}"; do
    if ! jq -e --arg n "$name" '.excludedBasenames[]? | select(.basename == $n)' "$EXCL_JSON" >/dev/null 2>&1; then
      echo "FAIL: 除外一覧に ${name} が含まれていません: $EXCL_JSON"
      fail=1
    fi
  done
fi

if [ ! -f "$TARGET" ]; then
  echo "FAIL: 検査スクリプトが見つかりません: $TARGET"
  fail=1
else
  if ! grep -q "document-style-exclusions.json" "$TARGET"; then
    echo "FAIL: 検査スクリプトが除外一覧の定義ファイルを参照していません: $TARGET"
    fail=1
  fi

  # self_test関数の開始行より前だけを本番コードとみなす。self_testは
  # 除外の挙動を確かめるため、ケースの固定ファイル名としてこれらの
  # 語を使ってよい（自己テストのフィクスチャは直書きの対象外）。
  production_code="$(awk '/^self_test\(\)/{exit} {print}' "$TARGET")"
  for name in "${REQUIRED_NAMES[@]}"; do
    if grep -qF -- "$name" <<< "$production_code"; then
      echo "FAIL: 検査スクリプトの本番コードに ${name} が直書きされています: $TARGET"
      fail=1
    fi
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: 除外一覧は定義ファイル側にあり、検査スクリプトへ直書きされていません"
  exit 0
fi
exit 1
