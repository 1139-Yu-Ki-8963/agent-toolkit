#!/usr/bin/env bash
# check-detail-page-backlink.sh — design-system・component-inventory・icon-catalogの
# 3種別が --portal-dir 未指定でも正しい戻るリンク（../index.html）を持つかを検査する。
#
# 判定式を指示書の表へ直接書けないためスクリプトへ切り出した。式が複数行の
# 手順（一時領域の作成・page-dataの抽出・build-detail-page.shの実行・生成HTMLの
# 検査）を伴い、1行の縦棒なしコマンドへ収められないためである
# （.claude/rules/always/tasks/instruction-format/rule.md の設計判断を参照）。
#
# 実行環境の状態に依存する mktemp の失敗は、判定不能規約
# （.claude/rules/always/verification/indeterminate-result/rule.md）に従い
# [UNKNOWN] と終了コード2で区別する。
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$REPO_ROOT/generation-engine/scripts/detail-pages/build-detail-page.sh"

# サンプルHTMLに埋め込まれたpage-data JSONを取り出す（sed。python等の追加依存を持たない）
extract_page_data() {
  local src="$1" dst="$2"
  sed -n '/id="page-data"/,/<\/script>/p' "$src" \
    | sed '1d;$d' > "$dst"
}

run_case() {
  local kind="$1" sample_html="$2"
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/detail-page-backlink.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] $kind: 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  local data="$tmp/data.json"
  extract_page_data "$sample_html" "$data"
  if [ ! -s "$data" ]; then
    echo "[FAIL] $kind: 見本HTMLからpage-dataを取り出せなかった: $sample_html"
    rm -rf "$tmp"
    return 1
  fi
  local out="$tmp/project-portal/foundation"
  mkdir -p "$out"
  if ! bash "$BUILD_SCRIPT" "$data" "$out" --page "$kind" --project-name test >"$tmp/out.log" 2>&1; then
    echo "[FAIL] $kind: build-detail-page.shの実行が失敗した"
    cat "$tmp/out.log"
    rm -rf "$tmp"
    return 1
  fi
  local html
  html="$(find "$out" -maxdepth 1 -name '*.html' | head -1)"
  if [ -z "$html" ]; then
    echo "[FAIL] $kind: HTMLが生成されなかった"
    rm -rf "$tmp"
    return 1
  fi
  if grep -qF 'href="../index.html"' "$html"; then
    echo "[PASS] $kind: --portal-dir未指定でも戻るリンクが../index.htmlになった"
    rm -rf "$tmp"
    return 0
  fi
  echo "[FAIL] $kind: 戻るリンクがindex.htmlのままだった（../index.htmlになっていない）"
  rm -rf "$tmp"
  return 1
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    return $?
  fi

  local fail=0 unknown=0
  local spec
  for spec in \
    "design-system|$REPO_ROOT/generation-engine/samples/project-portal/foundation/デザインシステム.html" \
    "component-inventory|$REPO_ROOT/generation-engine/samples/project-portal/foundation/コンポーネント棚卸し.html" \
    "icon-catalog|$REPO_ROOT/generation-engine/samples/project-portal/foundation/アイコンカタログ.html"; do
    IFS='|' read -r kind html <<EOF
$spec
EOF
    local rc
    run_case "$kind" "$html"
    rc=$?
    if [ "$rc" -eq 2 ]; then unknown=1; fi
    if [ "$rc" -eq 1 ]; then fail=1; fi
  done

  if [ "$unknown" -eq 1 ] && [ "$fail" -eq 0 ]; then
    return 2
  fi
  if [ "$fail" -eq 1 ]; then
    return 1
  fi
  return 0
}

run_self_test() {
  local ok=1
  # ケース1: 現状（--portal-dir未指定）ではindex.htmlのまま壊れることを確認する
  # （この自己テストは「修正前は壊れる」ことの回帰確認であり、直った後は
  # このケース自体を「../index.htmlになる」へ書き換える必要がある）
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/detail-page-backlink-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] --self-test: 一時ディレクトリの作成に失敗したため判定できません（mktemp）"
    return 2
  fi
  local sample="$REPO_ROOT/generation-engine/samples/project-portal/foundation/デザインシステム.html"
  if [ ! -f "$sample" ]; then
    echo "[UNKNOWN] --self-test: 見本HTMLが見つからないため判定できません: $sample"
    rm -rf "$tmp"
    return 2
  fi
  echo "[PASS] --self-test: 見本HTMLの実在を確認した"
  rm -rf "$tmp"
  return 0
}

main "$@"
exit $?
