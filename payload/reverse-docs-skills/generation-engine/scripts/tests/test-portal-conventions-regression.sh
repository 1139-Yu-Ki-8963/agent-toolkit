#!/usr/bin/env bash
# 集約には名前で収集される（run-layer-machine-checks.sh が test-*.sh を無条件に拾う）。
# 回帰テストであり、--self-test フラグを持つ本番経路スクリプトではないため、追加の
# --self-test 実装は行わない（本ファイルの実行自体が回帰検証にあたる）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK="$SCRIPT_DIR/test-portal-conventions.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

positive_output="$(bash "$CHECK" "$REPO_ROOT/delivery-payload/templates/common-doc-template.html")"
if ! grep -Fq 'SKIP: 色トークン（生成時に tokens.css を注入）' <<< "$positive_output"; then
  echo "FAIL: raw template のトークン検査がSKIPされない" >&2
  exit 1
fi

if ! tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/portal-conventions-regression.XXXXXX" 2>/dev/null)" || [ -z "$tmp_dir" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
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

# --- 改善課題キー: ポータル規約検査-対象範囲 ---
# ディレクトリ指定（既定挙動）は配下の*.htmlを無差別に走査するため、対象アプリが元から
# 持つ無関係なHTMLと生成物が混ざる。--file-list で生成物だけを渡した場合、無関係な
# HTML由来のFAILが出ないことを確認する（ディレクトリ指定では両方のFAILが混在する）。
if ! scope_dir="$(mktemp -d "${TMPDIR:-/tmp}/portal-conventions-scope.XXXXXX" 2>/dev/null)" || [ -z "$scope_dir" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi
trap 'rm -rf "$tmp_dir" "$scope_dir"' EXIT
# 作った直後に実体のパスへ解決する。macOS の TMPDIR は /var/... を返すが、
# 検査の側は対象を cd と pwd で解決するため出力は /private/var/... になる。
# 解決せずに文字列で突き合わせると、同じ場所を指しているのに一致せず、
# 「fixture の前提が崩れている」と誤って報告する（2026-08-19 実測。走査の
# 挙動は変わっておらず、照合の仕方だけが甘かった）。
scope_dir="$(cd "$scope_dir" && pwd)"

generated_html="$scope_dir/generated/index.html"
mkdir -p "$(dirname "$generated_html")"
printf '%s\n' \
  '<!doctype html>' \
  '<html><head><style>' \
  ':root { --bg: #0F1217; --accent: #4CC2FE; --accent2: #FF6E4F; }' \
  '@media (prefers-color-scheme: dark) { body { background: var(--bg); } }' \
  '[data-theme="dark"] body { background: var(--bg); }' \
  '[data-theme="light"] body { background: #fff; }' \
  '.pt-page { height: 100vh; overflow: hidden; background-size: 24px 24px; }' \
  '.pt-sidebar { width: 240px; }' \
  '.table-area { overflow-y: auto; }' \
  '</style></head>' \
  '<body><div class="pt-page"><div class="pt-sidebar"></div><div class="table-area"></div></div></body></html>' \
  > "$generated_html"

preexisting_html="$scope_dir/legacy/旧仕様書.html"
mkdir -p "$(dirname "$preexisting_html")"
printf '%s\n' \
  '<!doctype html>' \
  '<html><body><h1>対象アプリが元から持つ既存ドキュメント（本ツール群の生成物ではない）</h1></body></html>' \
  > "$preexisting_html"

set +e
dir_output="$(bash "$CHECK" "$scope_dir" 2>&1)"
set -e
if ! grep -Fq "$preexisting_html" <<< "$dir_output"; then
  echo "FAIL: ディレクトリ指定で既存HTMLが検査対象に含まれていない（fixture前提が崩れている）" >&2
  exit 1
fi

file_list="$scope_dir/generated-only.txt"
printf '%s\n' "$generated_html" > "$file_list"

set +e
filelist_output="$(bash "$CHECK" --file-list "$file_list" 2>&1)"
filelist_status=$?
set -e

if [ "$filelist_status" -ne 0 ]; then
  echo "FAIL: --file-list で生成物だけを渡したのに不合格になった" >&2
  echo "$filelist_output" >&2
  exit 1
fi
if grep -Fq "$preexisting_html" <<< "$filelist_output"; then
  echo "FAIL: --file-list なのに対象アプリの既存HTMLが検査対象に混入した" >&2
  exit 1
fi

echo "PASS portal conventions --file-list scope isolation"
