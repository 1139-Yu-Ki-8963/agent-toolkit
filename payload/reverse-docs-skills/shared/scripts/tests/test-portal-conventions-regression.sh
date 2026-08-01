#!/usr/bin/env bash
# 改善課題 1-138 の横断検収条件の対象外: 本ファイル自体が test-portal-conventions.sh の
# 回帰テストであり、--self-test フラグを持つ本番経路スクリプトではないため、追加の
# --self-test 実装は行わない（本ファイルの実行自体が回帰検証にあたる）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK="$SCRIPT_DIR/test-portal-conventions.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

positive_output="$(bash "$CHECK" "$REPO_ROOT/shared/templates/common-doc-template.html")"
if ! grep -Fq 'SKIP: 色トークン（生成時に tokens.css を注入）' <<< "$positive_output"; then
  echo "FAIL: raw template のトークン検査がSKIPされない" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/portal-conventions-regression.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
fixture="$tmp_dir/generated-with-unresolved-token-marker.html"
printf '%s\n' \
  '<!doctype html>' \
  '<html><head><style>/* TOKENS_CSS */ body { height: 100vh; overflow: hidden; } main { overflow-y: auto; }</style></head>' \
  '<body><main>generated output</main></body></html>' > "$fixture"

set +e
negative_output="$(bash "$CHECK" "$fixture" 2>&1)"
negative_status=$?
set -e

if [ "$negative_status" -eq 0 ]; then
  echo "FAIL: templates外の未解決TOKENS_CSSマーカーを拒否しなかった" >&2
  exit 1
fi
if grep -Fq 'SKIP: 色トークン（生成時に tokens.css を注入）' <<< "$negative_output"; then
  echo "FAIL: templates外の未解決TOKENS_CSSマーカーをSKIPした" >&2
  exit 1
fi
if ! grep -Fq 'FAIL: 色トークン-新値存在' <<< "$negative_output"; then
  echo "FAIL: templates外fixtureが色トークン欠落で失敗していない" >&2
  exit 1
fi

echo "PASS portal conventions raw-template scope regression"
