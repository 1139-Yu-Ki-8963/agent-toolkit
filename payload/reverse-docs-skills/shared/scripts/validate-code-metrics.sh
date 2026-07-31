#!/usr/bin/env bash
# validate-code-metrics.sh — counting-code-lines が出力する code-metrics.json の構文・キー充足を機械検査する
#
# 必要性: 改善課題 1-109 が指摘するとおり、本スキルは出力 JSON の構文検証・キー充足検証の手順を
#   持たず完了判定が自己申告になっている。決定的な検査の exit code を完了判定に使うため、本スクリプトを
#   新設する。
# 代替案を採用しなかった理由: counting-code-lines スキル本文への検査手順の直書きは、検査ロジックが
#   SKILL.md の自然文に埋もれて機械実行できない。他スキルの validate-*.sh と同様に独立スクリプト化し、
#   終了コードで合否を判定できる形にする。
# 保守責任者: 人手（ユーザー）。code-metrics.json のスキーマ（必須キー）を変更した場合は本スクリプトの
#   REQUIRED_TOP_KEYS 等の対応表を同時に更新する。
# 廃棄条件: counting-code-lines スキル自体が廃止された時、またはスキーマ検証をビルド基盤が標準で
#   提供するようになった時。
#
# Usage:
#   validate-code-metrics.sh <code-metrics.json>
#   validate-code-metrics.sh --self-test
#
# exit code:
#   0 = 検査すべて合格
#   1 = 検査に不合格（不足キー・違反の内容を stderr へ列挙）
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

usage() {
  echo "使い方: $SCRIPT_NAME <code-metrics.json>" >&2
  echo "        $SCRIPT_NAME --self-test" >&2
}

# 既存スキーマの必須キー（トップレベル）
REQUIRED_TOP_KEYS="total fe be file_count fe_files be_files method measured_at commit tests previous"
# 既存スキーマの必須キー（tests オブジェクト配下）
REQUIRED_TESTS_KEYS="count fe be files"
# 新規スキーマの必須キー（トップレベル）
REQUIRED_NEW_TOP_KEYS="scanScope unclassified testDetectionFailed"
# 新規スキーマの必須キー（scanScope オブジェクト配下）
REQUIRED_SCANSCOPE_KEYS="extensions extensionSource excludedFileCount excludedDirs excludedDirFileCount"
# 新規スキーマの必須キー（unclassified オブジェクト配下）
REQUIRED_UNCLASSIFIED_KEYS="files lines ratio warning"

# $1 = json ファイル, $2 = jq パス（例: ".tests.count"）, $3 = 報告用キー名
# キーが欠落（値が null または未定義）していれば標準出力へキー名を出す（呼び出し側で収集する）
report_missing_key() {
  local file="$1" jqhasfilter="$2" label="$3"
  if ! jq -e "$jqhasfilter" "$file" >/dev/null 2>&1; then
    echo "$label"
  fi
}

validate_file() {
  local file="$1"
  local violations=0

  if [ ! -f "$file" ]; then
    echo "ERROR: ファイルが存在しません: $file" >&2
    return 1
  fi

  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "VIOLATION: 正しい JSON ではありません: $file" >&2
    return 1
  fi

  local missing=""
  for key in $REQUIRED_TOP_KEYS; do
    local m
    m="$(report_missing_key "$file" "has(\"${key}\")" "$key")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done
  for key in $REQUIRED_TESTS_KEYS; do
    local m
    m="$(report_missing_key "$file" "(.tests // {}) | has(\"${key}\")" "tests.${key}")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done
  for key in $REQUIRED_NEW_TOP_KEYS; do
    local m
    m="$(report_missing_key "$file" "has(\"${key}\")" "$key")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done
  for key in $REQUIRED_SCANSCOPE_KEYS; do
    local m
    m="$(report_missing_key "$file" "(.scanScope // {}) | has(\"${key}\")" "scanScope.${key}")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done
  for key in $REQUIRED_UNCLASSIFIED_KEYS; do
    local m
    m="$(report_missing_key "$file" "(.unclassified // {}) | has(\"${key}\")" "unclassified.${key}")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done

  if [ -n "$missing" ]; then
    echo "VIOLATION: 必須キーが不足しています: $missing" >&2
    violations=$((violations + 1))
  fi

  # unclassified.ratio > 0.5 なのに unclassified.warning が false なら違反
  if jq -e '(.unclassified.ratio // 0) > 0.5 and (.unclassified.warning // false) == false' "$file" >/dev/null 2>&1; then
    echo "VIOLATION: unclassified.ratio が 0.5 超過なのに unclassified.warning が false です" >&2
    violations=$((violations + 1))
  fi

  if [ "$violations" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-code-metrics-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local pass=0 fail=0

  # ケース1: 全キーが揃った正常な JSON
  cat > "$tmp/valid.json" <<'JSON'
{
  "total": 67738,
  "fe": 52230,
  "be": 15508,
  "file_count": 512,
  "fe_files": 371,
  "be_files": 141,
  "method": "cloc",
  "measured_at": "2026-07-31T00:00:00Z",
  "commit": "abc123",
  "tests": { "count": 128, "fe": 84, "be": 44, "files": 37 },
  "previous": null,
  "scanScope": {
    "extensions": ["ts", "tsx"],
    "extensionSource": "default",
    "excludedFileCount": 0,
    "excludedDirs": [],
    "excludedDirFileCount": 0
  },
  "unclassified": { "files": 3, "lines": 10, "ratio": 0.05, "warning": false },
  "testDetectionFailed": false
}
JSON
  if validate_file "$tmp/valid.json" 2>"$tmp/valid.err"; then
    echo "PASS: ケース1 正常JSONで終了コード0"; pass=$((pass+1))
  else
    echo "FAIL: ケース1 正常JSONで終了コード0（$(cat "$tmp/valid.err")）"; fail=$((fail+1))
  fi

  # ケース2: scanScope が欠けた JSON
  jq 'del(.scanScope)' "$tmp/valid.json" > "$tmp/missing-scanscope.json"
  if validate_file "$tmp/missing-scanscope.json" 2>"$tmp/missing-scanscope.err"; then
    echo "FAIL: ケース2 scanScope欠落で終了コード1になるべき"; fail=$((fail+1))
  else
    if grep -q "scanScope" "$tmp/missing-scanscope.err"; then
      echo "PASS: ケース2 scanScope欠落で終了コード1・欠落キー列挙"; pass=$((pass+1))
    else
      echo "FAIL: ケース2 欠落キーがscanScopeを含んでいない（$(cat "$tmp/missing-scanscope.err")）"; fail=$((fail+1))
    fi
  fi

  # ケース3: unclassified.ratio=0.8, warning=false
  jq '.unclassified.ratio = 0.8 | .unclassified.warning = false' "$tmp/valid.json" > "$tmp/ratio-nowarn.json"
  if validate_file "$tmp/ratio-nowarn.json" 2>"$tmp/ratio-nowarn.err"; then
    echo "FAIL: ケース3 ratio超過かつwarning falseで終了コード1になるべき"; fail=$((fail+1))
  else
    echo "PASS: ケース3 ratio超過かつwarning falseで終了コード1"; pass=$((pass+1))
  fi

  # ケース4: unclassified.ratio=0.8, warning=true
  jq '.unclassified.ratio = 0.8 | .unclassified.warning = true' "$tmp/valid.json" > "$tmp/ratio-warn.json"
  if validate_file "$tmp/ratio-warn.json" 2>"$tmp/ratio-warn.err"; then
    echo "PASS: ケース4 ratio超過かつwarning trueで終了コード0"; pass=$((pass+1))
  else
    echo "FAIL: ケース4 ratio超過かつwarning trueで終了コード0のはず（$(cat "$tmp/ratio-warn.err")）"; fail=$((fail+1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then return 0; else return 1; fi
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

if validate_file "$1"; then
  echo "OK: $1 は妥当な code-metrics.json です"
  exit 0
else
  exit 1
fi
