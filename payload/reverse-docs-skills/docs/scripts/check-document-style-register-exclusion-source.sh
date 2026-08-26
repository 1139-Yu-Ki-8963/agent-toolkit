#!/usr/bin/env bash
# 文体検査の除外一覧が定義側にあり、配置条件を持つことを検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXCL_JSON="$REPO_ROOT/delivery-payload/references/document-style-exclusions.json"
TARGET="$REPO_ROOT/delivery-payload/templates/rules/checkers/check-document-style-register.sh"
REQUIRED_NAMES=('design-notes.md' 'SKILL.md' 'rule-reviewer.md')

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[UNKNOWN] 必須コマンドが見つからないため判定できません: $command_name" >&2
    return 2
  fi
}

check_definition() {
  local exclusion_json="$1" target="$2"
  local fail=0 production_code="" name=""

  if [ ! -r "$exclusion_json" ]; then
    echo "FAIL: 除外一覧の定義ファイルを読めません: $exclusion_json"
    fail=1
  elif ! jq -e '
    (.schemaVersion | type == "number") and
    .schemaVersion >= 2 and
    (.excludedBasenames | type == "array" and length > 0) and
    all(.excludedBasenames[];
      (.basename | type == "string" and length > 0) and
      (.allowedPathFragments | type == "array" and length > 0) and
      all(.allowedPathFragments[];
        type == "string" and
        startswith("/") and endswith("/") and
        (split("/") | length) >= 3
      )
    )
  ' "$exclusion_json" >/dev/null 2>&1; then
    echo 'FAIL: 全除外項目にbasenameとディレクトリ境界付きallowedPathFragmentsが必要です'
    fail=1
  fi

  if [ -r "$exclusion_json" ]; then
    for name in "${REQUIRED_NAMES[@]}"; do
      if ! jq -e --arg name "$name" '
        .excludedBasenames[]? |
        select(.basename == $name and (.allowedPathFragments | length > 0))
      ' "$exclusion_json" >/dev/null 2>&1; then
        echo "FAIL: 除外一覧に配置条件付きの$nameがありません"
        fail=1
      fi
    done
  fi

  if [ ! -r "$target" ]; then
    echo "FAIL: 配布物側の検査本体を読めません: $target"
    fail=1
  else
    production_code="$(awk '/^self_test\(\)/{exit} {print}' "$target")"
    if ! grep -q 'document-style-exclusions.json' <<< "$production_code"; then
      echo 'FAIL: 検査本体が除外一覧の定義ファイルを参照していません'
      fail=1
    fi
    if ! grep -q 'allowedPathFragments' <<< "$production_code"; then
      echo 'FAIL: 検査本体が配置条件を参照していません'
      fail=1
    fi
    for name in "${REQUIRED_NAMES[@]}"; do
      if grep -qF -- "$name" <<< "$production_code"; then
        echo "FAIL: 検査本体の本番コードに$nameが直書きされています"
        fail=1
      fi
    done
  fi

  [ "$fail" -eq 0 ]
}

run_production_check() {
  require_command jq || return 2
  if check_definition "$EXCL_JSON" "$TARGET"; then
    echo 'PASS: 除外一覧は定義側にあり、全項目が配置条件を持ちます'
    return 0
  fi
  return 1
}

self_test() {
  local tmpdir="" pass=0 fail=0 actual_rc=0
  require_command jq || return 2
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo '[UNKNOWN] 一時ディレクトリを作成できないため判定できません' >&2
    return 2
  fi
  self_test_tmpdir="$tmpdir"
  self_test_owner_pid="$BASHPID"
  trap 'if [ "$BASHPID" = "${self_test_owner_pid:-}" ] && [ -n "${self_test_tmpdir:-}" ]; then rm -rf "$self_test_tmpdir"; fi' EXIT

  assert_rc() {
    local label="$1" expected="$2"
    shift 2
    if ( "$@" ) >/dev/null 2>&1; then
      actual_rc=0
    else
      actual_rc=$?
    fi
    if [ "$actual_rc" -eq "$expected" ]; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label (期待=$expected 実際=$actual_rc)" >&2
      fail=$((fail + 1))
    fi
  }

  jq 'del(.excludedBasenames[0].allowedPathFragments)' \
    "$EXCL_JSON" > "$tmpdir/missing-fragments.json"
  jq '.excludedBasenames[0].allowedPathFragments = ["/"]' \
    "$EXCL_JSON" > "$tmpdir/global-fragment.json"
  jq '.schemaVersion = "2"' \
    "$EXCL_JSON" > "$tmpdir/string-schema-version.json"

  assert_rc '実物の定義と配布checkerは構造に適合' 0 \
    check_definition "$EXCL_JSON" "$TARGET"
  assert_rc '配置条件が欠けた除外項目を拒否' 1 \
    check_definition "$tmpdir/missing-fragments.json" "$TARGET"
  assert_rc 'basename単独相当の全域除外を拒否' 1 \
    check_definition "$tmpdir/global-fragment.json" "$TARGET"
  assert_rc '文字列のschemaVersionを拒否' 1 \
    check_definition "$tmpdir/string-schema-version.json" "$TARGET"
  assert_rc '不足した依存コマンドは判定不能' 2 \
    require_command 'document-style-source-missing-command'

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  case "${1:-}" in
    '') run_production_check ;;
    --self-test) self_test ;;
    *) echo "usage: $0 [--self-test]" >&2; return 2 ;;
  esac
}

main "$@"
