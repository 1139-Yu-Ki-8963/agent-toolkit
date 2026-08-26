#!/usr/bin/env bash
# 見本とテンプレートに、docs/references/retired-terms.json の廃止語が残っていないか検査する。
# 「廃止」「旧」「かつて」を同じ行に含む使用は、廃止経緯の説明として除外する。
# この行単位の判定には限界がある。経緯を別行で説明した引用は誤検出し、現役の指示へ
# 除外語を添えた行は見逃すため、文脈全体の意味を機械的に判定するものではない。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_TERMS_FILE="$REPO_ROOT/docs/references/retired-terms.json"
SELF_TEST_TMPDIR=""

cleanup_self_test() {
  if [ -n "$SELF_TEST_TMPDIR" ] && [ -d "$SELF_TEST_TMPDIR" ]; then
    rm -rf -- "$SELF_TEST_TMPDIR"
  fi
}

run_check() {
  local repo_root="$1"
  local terms_file="${RETIRED_TERMS_FILE:-$DEFAULT_TERMS_FILE}"
  local term file line line_number hit_count=0 file_count=0 target file_list content
  local -a terms=() targets=()

  if ! command -v jq >/dev/null 2>&1; then
    echo "[UNKNOWN] jqが無いため判定できません" >&2
    return 2
  fi
  if [ ! -f "$terms_file" ]; then
    echo "[UNKNOWN] 廃止語の一覧が存在しません: $terms_file" >&2
    return 2
  fi
  if ! jq -e '.terms | type == "array" and length > 0 and all(.term? | type == "string" and length > 0)' "$terms_file" >/dev/null 2>&1; then
    echo "[UNKNOWN] 廃止語の一覧の形式が不正です: $terms_file" >&2
    return 2
  fi

  while IFS= read -r term; do
    terms+=("$term")
  done < <(jq -r '.terms[].term' "$terms_file")

  targets=("$repo_root/generation-engine/samples" "$repo_root/delivery-payload/templates")
  for target in "${targets[@]}"; do
    if [ ! -d "$target" ]; then
      echo "[UNKNOWN] 走査対象が存在しません: $target" >&2
      return 2
    fi
    if ! file_list="$(find "$target" -type f 2>/dev/null)"; then
      echo "[UNKNOWN] 走査対象の列挙に失敗しました: $target" >&2
      return 2
    fi
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      if ! content="$(cat -- "$file" 2>/dev/null)"; then
        echo "[UNKNOWN] 走査対象を読み取れません: $file" >&2
        return 2
      fi
      file_count=$((file_count + 1))
      line_number=0
      while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        case "$line" in
          *廃止*|*旧*|*かつて*) continue ;;
        esac
        for term in "${terms[@]}"; do
          case "$line" in
            *"$term"*)
              echo "[FAIL] ${file}:${line_number}:${line}"
              hit_count=$((hit_count + 1))
              break
              ;;
          esac
        done
      done <<< "$content"
    done <<< "$(printf '%s\n' "$file_list" | LC_ALL=C sort)"
  done

  if [ "$file_count" -eq 0 ]; then
    echo "[UNKNOWN] 走査対象が1件も無いため判定できません" >&2
    return 2
  fi
  if [ "$hit_count" -gt 0 ]; then
    echo "[FAIL] 廃止語が ${hit_count} 件残っています"
    return 1
  fi
  echo "[PASS] 見本とテンプレートの廃止語は0件です"
  return 0
}

run_self_test() {
  local pass=0 fail=0 case_dir terms_file output rc
  if ! SELF_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/check-retired-terms-in-samples.XXXXXX" 2>/dev/null)" || [ -z "$SELF_TEST_TMPDIR" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作成できないため自己テストを判定できません" >&2
    return 2
  fi
  trap cleanup_self_test EXIT HUP INT TERM

  assert_case() {
    local name="$1" expected_rc="$2" expected_text="$3" expected_text2="${4:-}"
    if [ "$rc" -eq "$expected_rc" ] \
      && printf '%s\n' "$output" | grep -qF "$expected_text" \
      && { [ -z "$expected_text2" ] || printf '%s\n' "$output" | grep -qF "$expected_text2"; }; then
      echo "[PASS] $name"
      pass=$((pass + 1))
    else
      echo "[FAIL] $name: 終了コード=$rc 出力=$output"
      fail=$((fail + 1))
    fi
  }

  terms_file="$SELF_TEST_TMPDIR/retired-terms.json"
  printf '%s\n' '{"terms":[{"term":"禁止語甲"},{"term":"禁止語乙"}]}' > "$terms_file"

  case_dir="$SELF_TEST_TMPDIR/clean"
  mkdir -p "$case_dir/generation-engine/samples" "$case_dir/delivery-payload/templates"
  printf '%s\n' '現行の文言' > "$case_dir/generation-engine/samples/clean.md"
  output="$(RETIRED_TERMS_FILE="$terms_file" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "残存なし" 0 "[PASS]"

  case_dir="$SELF_TEST_TMPDIR/hit"
  mkdir -p "$case_dir/generation-engine/samples" "$case_dir/delivery-payload/templates"
  printf '%s\n' '禁止語甲を使う' > "$case_dir/delivery-payload/templates/bad.md"
  printf '%s\n' '禁止語乙を使う' > "$case_dir/generation-engine/samples/bad2.md"
  output="$(RETIRED_TERMS_FILE="$terms_file" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "見本とテンプレートで一覧の全語を検出" 1 "bad.md:1:禁止語甲を使う" "bad2.md:1:禁止語乙を使う"

  case_dir="$SELF_TEST_TMPDIR/exceptions"
  mkdir -p "$case_dir/generation-engine/samples" "$case_dir/delivery-payload/templates"
  printf '%s\n' '廃止した禁止語甲' '旧名称は禁止語乙' 'かつて禁止語甲を使った' > "$case_dir/generation-engine/samples/history.md"
  output="$(RETIRED_TERMS_FILE="$terms_file" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "経緯説明の3語を除外" 0 "[PASS]"

  case_dir="$SELF_TEST_TMPDIR/missing"
  mkdir -p "$case_dir/generation-engine/samples"
  output="$(RETIRED_TERMS_FILE="$case_dir/missing.json" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "一覧なしは判定不能" 2 "[UNKNOWN]"

  case_dir="$SELF_TEST_TMPDIR/empty"
  mkdir -p "$case_dir/generation-engine/samples" "$case_dir/delivery-payload/templates"
  output="$(RETIRED_TERMS_FILE="$terms_file" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "走査ファイルなしは判定不能" 2 "[UNKNOWN]"

  case_dir="$SELF_TEST_TMPDIR/missing-target"
  mkdir -p "$case_dir/generation-engine/samples"
  printf '%s\n' '現行の文言' > "$case_dir/generation-engine/samples/clean.md"
  output="$(RETIRED_TERMS_FILE="$terms_file" run_check "$case_dir" 2>&1)"; rc=$?
  assert_case "片方の走査対象欠落は判定不能" 2 "[UNKNOWN]"

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  "")
    run_check "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
