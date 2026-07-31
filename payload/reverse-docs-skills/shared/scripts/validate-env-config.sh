#!/usr/bin/env bash
# validate-env-config.sh — surveying-local-environment が出力する env-config.json の構文・キー充足を機械検査する
#
# 必要性: 改善課題 1-109 が指摘するとおり、本スキルは出力 JSON の構文検証・キー充足検証の手順を
#   持たず完了判定が自己申告になっている。決定的な検査の exit code を完了判定に使うため、本スクリプトを
#   新設する（counting-code-lines の validate-code-metrics.sh と対をなす）。
# 代替案を採用しなかった理由: surveying-local-environment スキル本文への検査手順の直書きは、検査ロジックが
#   SKILL.md の自然文に埋もれて機械実行できない。他スキルの validate-*.sh と同様に独立スクリプト化し、
#   終了コードで合否を判定できる形にする。
# 保守責任者: 人手（ユーザー）。env-config.json のスキーマ（必須キー・tools の内訳）を変更した場合は
#   本スクリプトの REQUIRED_TOP_KEYS・REQUIRED_TOOLS_KEYS を同時に更新する。
# 廃棄条件: surveying-local-environment スキル自体が廃止された時、またはスキーマ検証をビルド基盤が標準で
#   提供するようになった時。
#
# Usage:
#   validate-env-config.sh <env-config.json>
#   validate-env-config.sh --self-test
#
# exit code:
#   0 = 検査すべて合格
#   1 = 検査に不合格（不足キー・違反の内容を stderr へ列挙）
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

usage() {
  echo "使い方: $SCRIPT_NAME <env-config.json>" >&2
  echo "        $SCRIPT_NAME --self-test" >&2
}

# 必須キー（トップレベル）
REQUIRED_TOP_KEYS="os arch linux_compat_env pkg_manager tools install_commands surveyed_at"
# 必須キー（tools オブジェクト配下）
REQUIRED_TOOLS_KEYS="cloc node python3 jq git"
# 必須キー（install_commands オブジェクト配下。改善課題1-107: 全5種分のインストールコマンドを必須化）
REQUIRED_INSTALL_COMMANDS_KEYS="cloc node python3 jq git"

# $1 = json ファイル, $2 = jq has フィルタ, $3 = 報告用キー名
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
  for key in $REQUIRED_TOOLS_KEYS; do
    local m
    m="$(report_missing_key "$file" "(.tools // {}) | has(\"${key}\")" "tools.${key}")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done
  for key in $REQUIRED_INSTALL_COMMANDS_KEYS; do
    local m
    m="$(report_missing_key "$file" "(.install_commands // {}) | has(\"${key}\")" "install_commands.${key}")"
    [ -n "$m" ] && missing="${missing}${missing:+ }${m}"
  done

  if [ -n "$missing" ]; then
    echo "VIOLATION: 必須キーが不足しています: $missing" >&2
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
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-env-config-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  local pass=0 fail=0

  # ケース1: 全キーが揃った正常な JSON
  cat > "$tmp/valid.json" <<'JSON'
{
  "os": "darwin",
  "arch": "arm64",
  "linux_compat_env": false,
  "pkg_manager": "brew",
  "tools": {
    "cloc": true,
    "node": true,
    "python3": true,
    "jq": true,
    "git": true
  },
  "install_commands": {
    "cloc": "brew install cloc",
    "node": "brew install node",
    "python3": "brew install python3",
    "jq": "brew install jq",
    "git": "brew install git"
  },
  "surveyed_at": "2026-07-31T00:00:00Z"
}
JSON
  if validate_file "$tmp/valid.json" 2>"$tmp/valid.err"; then
    echo "PASS: ケース1 正常JSONで終了コード0"; pass=$((pass+1))
  else
    echo "FAIL: ケース1 正常JSONで終了コード0（$(cat "$tmp/valid.err")）"; fail=$((fail+1))
  fi

  # ケース2: 必須キー（トップレベル）が欠落した JSON
  jq 'del(.surveyed_at)' "$tmp/valid.json" > "$tmp/missing-top.json"
  if validate_file "$tmp/missing-top.json" 2>"$tmp/missing-top.err"; then
    echo "FAIL: ケース2 surveyed_at欠落で終了コード1になるべき"; fail=$((fail+1))
  else
    if grep -q "surveyed_at" "$tmp/missing-top.err"; then
      echo "PASS: ケース2 必須キー欠落で終了コード1・欠落キー列挙"; pass=$((pass+1))
    else
      echo "FAIL: ケース2 欠落キーがsurveyed_atを含んでいない（$(cat "$tmp/missing-top.err")）"; fail=$((fail+1))
    fi
  fi

  # ケース3: tools 配下の一部キーが欠落した JSON
  jq 'del(.tools.jq)' "$tmp/valid.json" > "$tmp/missing-tools.json"
  if validate_file "$tmp/missing-tools.json" 2>"$tmp/missing-tools.err"; then
    echo "FAIL: ケース3 tools.jq欠落で終了コード1になるべき"; fail=$((fail+1))
  else
    if grep -q "tools.jq" "$tmp/missing-tools.err"; then
      echo "PASS: ケース3 tools配下欠落で終了コード1・欠落キー列挙"; pass=$((pass+1))
    else
      echo "FAIL: ケース3 欠落キーがtools.jqを含んでいない（$(cat "$tmp/missing-tools.err")）"; fail=$((fail+1))
    fi
  fi

  # ケース4: install_commands 配下の一部キーが欠落した JSON（改善課題1-107）
  jq 'del(.install_commands.node)' "$tmp/valid.json" > "$tmp/missing-install-cmd.json"
  if validate_file "$tmp/missing-install-cmd.json" 2>"$tmp/missing-install-cmd.err"; then
    echo "FAIL: ケース4 install_commands.node欠落で終了コード1になるべき"; fail=$((fail+1))
  else
    if grep -q "install_commands.node" "$tmp/missing-install-cmd.err"; then
      echo "PASS: ケース4 install_commands配下欠落で終了コード1・欠落キー列挙"; pass=$((pass+1))
    else
      echo "FAIL: ケース4 欠落キーがinstall_commands.nodeを含んでいない（$(cat "$tmp/missing-install-cmd.err")）"; fail=$((fail+1))
    fi
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
  echo "OK: $1 は妥当な env-config.json です"
  exit 0
else
  exit 1
fi
