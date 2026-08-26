#!/usr/bin/env bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
template="$repo_root/delivery-payload/templates/リバース検証/プロジェクト共通/結合テスト仕様書.md"

generate_spec() {
  local output_root="$1"
  local project_name="$2"
  local output="$output_root/docs/test-cases/結合テスト仕様書.md"
  mkdir -p "$(dirname "$output")"
  awk -v project="$project_name" '{gsub(/<プロジェクト名>/, project); print}' "$template" > "$output"
  printf '%s\n' "$output"
}

self_test() {
  local tmp output rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/integration-test-spec.XXXXXX")" || return 2
  trap 'rm -rf "$tmp"' RETURN
  output="$(generate_spec "$tmp" "検証用プロジェクト")" || return 1
  test -f "$output" || rc=1
  grep -q '^# 検証用プロジェクト 結合テスト仕様書$' "$output" || rc=1
  grep -q '^## テストケース一覧$' "$output" || rc=1
  grep -q '^| キー | 連携キー | ケースの名前 | 区分 | 前提条件 | 操作手順 | 期待結果 |$' "$output" || rc=1
  grep -q '複数の画面・機能・API・テーブル・バッチ・帳票・外部連携' "$output" || rc=1
  if [ "$rc" -eq 0 ]; then
    echo 'PASS: プロジェクト横断の結合テスト仕様書を生成'
  else
    echo 'FAIL: 結合テスト仕様書の生成結果が契約を満たさない' >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: generate-integration-test-spec.sh <output_root> [project_name]' >&2
  exit 2
fi

generate_spec "$1" "${2:-プロジェクト}"
