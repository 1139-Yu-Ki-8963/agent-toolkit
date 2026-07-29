#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

# build-portal.sh — 設計ポータルを生成する
#
# Usage:
#   bash shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
#     [--catalog <portal-catalog.json>] [--generated-at <ISO-8601>]
#     [--portal-only] [--screen-manifest <screen-manifest.ext.json>]
#
# 処理:
#   1. 対象リポジトリのコード行数・ファイル数を計測（FE/BE分離）
#   2. 各種別の一覧HTMLから件数を抽出（規模側の kinds と一覧カードで共用）
#   3. 共通文書リスト・将来ページ受け口（FUTURE_PAGES）を収集
#   4. METRICS_JSON（構造化: scale/tests/freshness/previous）/ CATEGORIES_JSON を組み立て
#   5. テンプレートのプレースホルダを置換して出力

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/portal-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../templates/tokens.css"
DEFAULT_CATALOG="$SCRIPT_DIR/../references/portal-catalog.json"
CATALOG_ENGINE="$SCRIPT_DIR/portal-catalog.mjs"

source "$SCRIPT_DIR/render-template.sh"
if [ -f "$SCRIPT_DIR/shell-injection.sh" ]; then
  . "$SCRIPT_DIR/shell-injection.sh"
fi

script_safe_json() {
  node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => { input += chunk; });
    process.stdin.on("end", () => {
      process.stdout.write(
        input
          .replaceAll("<", "\\u003c")
          .replaceAll(">", "\\u003e")
          .replaceAll("&", "\\u0026")
          .replaceAll("\u2028", "\\u2028")
          .replaceAll("\u2029", "\\u2029")
      );
    });
  '
}

# --- self-test ---
if [ "${1:-}" = "--self-test" ]; then
  tmpdir="$(mktemp -d)"
  tmpdir2="$(mktemp -d)"
  trap 'rm -rf "$tmpdir" "$tmpdir2"' EXIT

  # ケース1: 旧スキーマ互換（既存フィクスチャそのまま。tests/commit/previous なし）
  mkdir -p "$tmpdir/repo/misc"
  echo "const x = 1;" > "$tmpdir/repo/misc/util.ts"

  mkdir -p "$tmpdir/portal"
  cat > "$tmpdir/portal/code-metrics.json" <<'FIXTURE'
{"total":1,"fe":0,"be":0,"file_count":1,"fe_files":0,"be_files":0,"method":"wc","measured_at":"2026-01-01T00:00:00Z"}
FIXTURE

  mkdir -p "$tmpdir/docs"

  case1_pass=0
  if bash "$0" "$tmpdir/repo" "$tmpdir/docs" "$tmpdir/portal" 2>/dev/null; then
    if [ -f "$tmpdir/portal/index.html" ]; then
      echo "PASS: --self-test ケース1（旧スキーマ互換, exit 0, index.html generated）" >&2
      case1_pass=1
    fi
  fi
  if [ "$case1_pass" -ne 1 ]; then
    echo "FAIL: --self-test ケース1（旧スキーマ互換）" >&2
    exit 1
  fi

  # ケース2: 新スキーマ + git 管理フィクスチャ（tests/commit/previous あり）
  mkdir -p "$tmpdir2/repo"
  git -C "$tmpdir2/repo" init -q
  git -C "$tmpdir2/repo" config user.email "test@example.com"
  git -C "$tmpdir2/repo" config user.name "Test"
  echo "const x = 1;" > "$tmpdir2/repo/util.ts"
  git -C "$tmpdir2/repo" add -A
  git -C "$tmpdir2/repo" commit -q -m "initial"
  commit_hash="$(git -C "$tmpdir2/repo" rev-parse HEAD)"

  mkdir -p "$tmpdir2/portal"
  cat > "$tmpdir2/portal/code-metrics.json" <<FIXTURE2
{"total":1000,"fe":600,"be":400,"file_count":10,"fe_files":6,"be_files":4,"method":"wc","measured_at":"2026-07-16T00:00:00Z","commit":"$commit_hash","tests":{"count":20,"fe":12,"be":8,"files":5},"previous":{"total":900,"tests_count":15,"measured_at":"2026-07-01T00:00:00Z"}}
FIXTURE2

  mkdir -p "$tmpdir2/docs"

  case2_pass=0
  if bash "$0" "$tmpdir2/repo" "$tmpdir2/docs" "$tmpdir2/portal" 2>/dev/null; then
    out="$tmpdir2/portal/index.html"
    if [ -f "$out" ] && [ "$(grep -c '{{' "$out" || true)" -eq 0 ] && grep -q '"scale"' "$out"; then
      echo "PASS: --self-test ケース2（新スキーマ + git 管理, exit 0, 未解決プレースホルダなし, scale 含む）" >&2
      case2_pass=1
    fi
  fi
  if [ "$case2_pass" -ne 1 ]; then
    echo "FAIL: --self-test ケース2（新スキーマ + git 管理）" >&2
    exit 1
  fi

  echo "--- ケース3: FUTURE_PAGES 実在チェック ---"
  test3_dir="$(mktemp -d)"
  test3_docs="$test3_dir/docs"
  test3_portal="$test3_dir/portal"
  mkdir -p "$test3_docs" "$test3_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test3_docs/code-metrics.json"
  echo '<html><body>test glossary</body></html>' > "$test3_docs/用語辞書.html"
  "$SCRIPT_DIR/build-portal.sh" "$test3_dir" "$test3_docs" "$test3_portal" 2>/dev/null
  if grep -q "用語辞書" "$test3_portal/index.html" && grep -q "基盤情報" "$test3_portal/index.html"; then
    echo "PASS: --self-test ケース3（FUTURE_PAGES 実在チェック, 用語辞書カード出現）"
  else
    echo "FAIL: --self-test ケース3" >&2; rm -rf "$test3_dir"; exit 1
  fi
  rm -rf "$test3_dir"

  echo "--- ケース4: BOM付き・frontmatter付きmdファイルからのタイトル抽出 ---"
  test4_dir="$(mktemp -d)"
  test4_repo="$test4_dir/repo"
  test4_docs="$test4_dir/docs"
  test4_portal="$test4_dir/portal"
  mkdir -p "$test4_repo" "$test4_docs/プロジェクト共通" "$test4_portal"
  printf '\xEF\xBB\xBF# BOM付き見出し\n本文' > "$test4_docs/プロジェクト共通/bom-test.md"
  printf -- '---\ntitle: frontmatter\n---\n# FM後の見出し\n本文' > "$test4_docs/プロジェクト共通/fm-test.md"
  "$SCRIPT_DIR/build-portal.sh" "$test4_repo" "$test4_docs" "$test4_portal" 2>/dev/null
  bom_ok=0
  fm_ok=0
  grep -q 'BOM付き見出し' "$test4_docs/プロジェクト共通/bom-test.html" 2>/dev/null && bom_ok=1
  grep -q 'FM後の見出し' "$test4_docs/プロジェクト共通/fm-test.html" 2>/dev/null && fm_ok=1
  if [ "$bom_ok" = "1" ] && [ "$fm_ok" = "1" ]; then
    echo "PASS: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出）"
  else
    echo "FAIL: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出, bom=$bom_ok fm=$fm_ok）" >&2
    rm -rf "$test4_dir"
    exit 1
  fi
  rm -rf "$test4_dir"

  echo "--- ケース5: 共通文書 .md → .html 変換 ---"
  test5_dir="$(mktemp -d)"
  test5_repo="$test5_dir/repo"
  test5_docs="$test5_dir/docs"
  test5_portal="$test5_dir/portal"
  mkdir -p "$test5_repo" "$test5_docs/プロジェクト共通" "$test5_portal"
  printf '# テスト文書\n\n本文テスト。\n\n| 列1 | 列2 |\n|---|---|\n| A | B |\n' > "$test5_docs/プロジェクト共通/test-doc.md"
  "$SCRIPT_DIR/build-portal.sh" "$test5_repo" "$test5_docs" "$test5_portal" 2>/dev/null
  if [ ! -f "$test5_docs/プロジェクト共通/test-doc.html" ]; then
    echo "FAIL: ケース5 — test-doc.html が生成されていない" >&2; rm -rf "$test5_dir"; exit 1
  fi
  if ! grep -q 'テスト文書' "$test5_docs/プロジェクト共通/test-doc.html"; then
    echo "FAIL: ケース5 — test-doc.html にタイトルが含まれていない" >&2; rm -rf "$test5_dir"; exit 1
  fi
  if grep -q 'test-doc\.md"' "$test5_portal/index.html"; then
    echo "FAIL: ケース5 — ポータルにまだ .md リンクが残っている" >&2; rm -rf "$test5_dir"; exit 1
  fi
  echo "PASS: --self-test ケース5（共通文書 .md → .html 変換）"
  rm -rf "$test5_dir"

  echo "--- ケース5b: サブディレクトリ配下の共通文書リンクがパスを保持する ---"
  test5b_dir="$(mktemp -d)"
  test5b_repo="$test5b_dir/repo"
  test5b_docs="$test5b_dir/docs"
  test5b_portal="$test5b_dir/portal"
  mkdir -p "$test5b_repo" "$test5b_docs/プロジェクト共通/規約" "$test5b_portal"
  printf '# サブ規約\n\n本文。\n' > "$test5b_docs/プロジェクト共通/規約/sub-rule.md"
  "$SCRIPT_DIR/build-portal.sh" "$test5b_repo" "$test5b_docs" "$test5b_portal" 2>/dev/null
  if [ ! -f "$test5b_docs/プロジェクト共通/規約/sub-rule.html" ]; then
    echo "FAIL: ケース5b — サブディレクトリ内に sub-rule.html が生成されていない" >&2; rm -rf "$test5b_dir"; exit 1
  fi
  echo "PASS: --self-test ケース5b（サブディレクトリ配下の共通文書変換）"
  rm -rf "$test5b_dir"

  echo "--- ケース5c: 共通文書の戻るリンクが出力先の深さに応じた相対パスになる ---"
  test5c_dir="$(mktemp -d)"
  test5c_repo="$test5c_dir/repo"
  test5c_docs="$test5c_dir/docs"
  mkdir -p "$test5c_repo" "$test5c_docs/プロジェクト共通/規約"
  printf '# 深さ1文書\n\n本文。\n' > "$test5c_docs/プロジェクト共通/depth1-doc.md"
  printf '# 深さ2規約\n\n本文。\n' > "$test5c_docs/プロジェクト共通/規約/depth2-rule.md"
  # 正本レイアウト: ポータル = docs ルートの index.html
  "$SCRIPT_DIR/build-portal.sh" "$test5c_repo" "$test5c_docs" "$test5c_docs" 2>/dev/null
  if ! grep -q 'href="\.\./index\.html"' "$test5c_docs/プロジェクト共通/depth1-doc.html"; then
    echo "FAIL: ケース5c — 深さ1の戻るリンクが ../index.html でない" >&2; rm -rf "$test5c_dir"; exit 1
  fi
  if ! grep -q 'href="\.\./\.\./index\.html"' "$test5c_docs/プロジェクト共通/規約/depth2-rule.html"; then
    echo "FAIL: ケース5c — 深さ2の戻るリンクが ../../index.html でない" >&2; rm -rf "$test5c_dir"; exit 1
  fi
  echo "PASS: --self-test ケース5c（戻るリンクの深さ別相対パス計算）"
  rm -rf "$test5c_dir"

  echo "--- ケース6: frontmatter 付き md → html で frontmatter が本文に表示されない ---"
  test6_dir="$(mktemp -d)"
  test6_repo="$test6_dir/repo"
  test6_docs="$test6_dir/docs"
  test6_portal="$test6_dir/portal"
  mkdir -p "$test6_repo" "$test6_docs/プロジェクト共通" "$test6_portal"
  printf -- '---\ndoc_id: test-doc\ntype: design\nstatus: traced\n---\n# テスト見出し\n\n本文テスト。' > "$test6_docs/プロジェクト共通/fm-body-test.md"
  "$0" "$test6_repo" "$test6_docs" "$test6_portal" 2>/dev/null
  if grep -q 'doc_id:' "$test6_docs/プロジェクト共通/fm-body-test.html" 2>/dev/null; then
    echo "FAIL: ケース6 — frontmatter が HTML 本文に残留" >&2
    rm -rf "$test6_dir"
    exit 1
  fi
  if ! grep -q 'テスト見出し' "$test6_docs/プロジェクト共通/fm-body-test.html" 2>/dev/null; then
    echo "FAIL: ケース6 — 見出しが消失" >&2
    rm -rf "$test6_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース6（frontmatter 除去）"
  rm -rf "$test6_dir"

  echo "--- ケース6b: 単一行 HTML コメントの除去 ---"
  test6b_dir="$(mktemp -d)"
  test6b_repo="$test6b_dir/repo"
  test6b_docs="$test6b_dir/docs"
  test6b_portal="$test6b_dir/portal"
  mkdir -p "$test6b_repo" "$test6b_docs/プロジェクト共通" "$test6b_portal"
  printf '# 見出し\n\n本文前。\n\n<!-- このコメントは除去される -->\n\n本文後。' > "$test6b_docs/プロジェクト共通/comment-single-test.md"
  "$0" "$test6b_repo" "$test6b_docs" "$test6b_portal" 2>/dev/null
  if grep -q 'このコメントは除去される' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null; then
    echo "FAIL: ケース6b — 単一行コメントが HTML に残留" >&2
    rm -rf "$test6b_dir"
    exit 1
  fi
  if ! grep -q '本文前' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null || ! grep -q '本文後' "$test6b_docs/プロジェクト共通/comment-single-test.html" 2>/dev/null; then
    echo "FAIL: ケース6b — コメント以外の本文が消失" >&2
    rm -rf "$test6b_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース6b（単一行 HTML コメントの除去）"
  rm -rf "$test6b_dir"

  echo "--- ケース6c: 複数行 HTML コメントブロックの除去 ---"
  test6c_dir="$(mktemp -d)"
  test6c_repo="$test6c_dir/repo"
  test6c_docs="$test6c_dir/docs"
  test6c_portal="$test6c_dir/portal"
  mkdir -p "$test6c_repo" "$test6c_docs/プロジェクト共通" "$test6c_portal"
  printf '# 見出し\n\n<!--\nブロック内テキスト\n-->\n\n本文。' > "$test6c_docs/プロジェクト共通/comment-block-test.md"
  "$0" "$test6c_repo" "$test6c_docs" "$test6c_portal" 2>/dev/null
  if grep -q 'ブロック内テキスト' "$test6c_docs/プロジェクト共通/comment-block-test.html" 2>/dev/null; then
    echo "FAIL: ケース6c — 複数行コメントブロックが HTML に残留" >&2
    rm -rf "$test6c_dir"
    exit 1
  fi
  if ! grep -q '本文。' "$test6c_docs/プロジェクト共通/comment-block-test.html" 2>/dev/null; then
    echo "FAIL: ケース6c — コメント以外の本文が消失" >&2
    rm -rf "$test6c_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース6c（複数行 HTML コメントブロックの除去）"
  rm -rf "$test6c_dir"

  echo "--- ケース6d: 行内コメントは除去しない ---"
  test6d_dir="$(mktemp -d)"
  test6d_repo="$test6d_dir/repo"
  test6d_docs="$test6d_dir/docs"
  test6d_portal="$test6d_dir/portal"
  mkdir -p "$test6d_repo" "$test6d_docs/プロジェクト共通" "$test6d_portal"
  printf '# 見出し\n\nテキスト <!-- コメント --> テキスト' > "$test6d_docs/プロジェクト共通/comment-inline-test.md"
  "$0" "$test6d_repo" "$test6d_docs" "$test6d_portal" 2>/dev/null
  test6d_json="$(sed -n 's|.*<script type="application/json" id="doc-md">\([^<]*\)</script>.*|\1|p' "$test6d_docs/プロジェクト共通/comment-inline-test.html")"
  if ! printf '%s' "$test6d_json" | jq -r . | grep -Fq 'テキスト <!-- コメント --> テキスト'; then
    echo "FAIL: ケース6d — 行内コメントを含む行が変化した" >&2
    rm -rf "$test6d_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース6d（行内コメントは除去しない）"
  rm -rf "$test6d_dir"

  echo "--- ケース7: 複数行 unit-manifest JSON からの件数抽出 ---"
  test7_dir="$(mktemp -d)"
  test7_repo="$test7_dir/repo"
  test7_docs="$test7_dir/docs"
  test7_portal="$test7_dir/portal"
  mkdir -p "$test7_repo" "$test7_docs/一覧/API一覧" "$test7_portal"
  cat > "$test7_docs/一覧/API一覧/API一覧.html" <<'TEST7HTML'
<!DOCTYPE html><html><head><title>API一覧</title></head><body>
<script type="application/json" id="unit-manifest">
{
  "detectionSummary": {
    "unitCount": 5,
    "analyzedFiles": 10
  },
  "units": [{},{},{},{},{}]
}
</script>
</body></html>
TEST7HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test7_portal/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test7_repo" "$test7_docs" "$test7_portal" 2>/dev/null
  if tr -d ' \n' < "$test7_portal/index.html" | grep -q '"kind":"api".*"count":5'; then
    echo "PASS: --self-test ケース7（複数行 unit-manifest JSON からの件数抽出, count=5）"
  else
    echo "FAIL: --self-test ケース7（複数行 unit-manifest JSON からの件数抽出）" >&2
    rm -rf "$test7_dir"
    exit 1
  fi
  rm -rf "$test7_dir"

  echo "--- ケース8: screen-manifest + screenCount からの件数抽出 ---"
  test8_dir="$(mktemp -d)"
  test8_repo="$test8_dir/repo"
  test8_docs="$test8_dir/docs"
  test8_portal="$test8_dir/portal"
  mkdir -p "$test8_repo" "$test8_docs/一覧/画面一覧" "$test8_portal"
  cat > "$test8_docs/一覧/画面一覧/画面一覧.html" <<'TEST8HTML'
<!DOCTYPE html><html><head><title>画面一覧</title></head><body>
<script type="application/json" id="screen-manifest">
{
  "detectionSummary": {
    "screenCount": 12,
    "analyzedFiles": 20
  },
  "screens": [{},{},{},{},{},{},{},{},{},{},{},{}]
}
</script>
</body></html>
TEST8HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test8_portal/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test8_repo" "$test8_docs" "$test8_portal" 2>/dev/null
  if tr -d ' \n' < "$test8_portal/index.html" | grep -q '"kind":"screen".*"count":12'; then
    echo "PASS: --self-test ケース8（screen-manifest + screenCount からの件数抽出, count=12）"
  else
    echo "FAIL: --self-test ケース8（screen-manifest + screenCount からの件数抽出）" >&2
    rm -rf "$test8_dir"
    exit 1
  fi
  rm -rf "$test8_dir"

  echo "--- ケース9: マトリクス・対応表・AI設定資産カード（実在時のみ出現、全不在時はセクション非表示） ---"
  test9_dir="$(mktemp -d)"
  test9_repo="$test9_dir/repo"
  test9_docs="$test9_dir/docs"
  test9_portal="$test9_dir/portal"
  mkdir -p "$test9_repo" "$test9_docs/マトリクス・対応表/権限画面マトリクス" "$test9_docs/AI設定資産" "$test9_portal"
  echo '<html><body>perm screen matrix</body></html>' > "$test9_docs/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
  echo '<html><body>ai assets</body></html>' > "$test9_docs/AI設定資産/AI設定資産.html"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9_docs" "$test9_portal" 2>/dev/null
  if grep -q '権限画面マトリクス' "$test9_portal/index.html" && grep -q 'AI設定資産' "$test9_portal/index.html" \
     && ! grep -q '権限機能マトリクス' "$test9_portal/index.html"; then
    echo "PASS: --self-test ケース9a（実在ページのみカード出現）"
  else
    echo "FAIL: --self-test ケース9a（実在ページのみカード出現）" >&2
    rm -rf "$test9_dir"
    exit 1
  fi
  # 全不在ケース: マトリクス・対応表・AI設定資産のセクション自体が出ない
  test9b_docs="$test9_dir/docs-empty"
  test9b_portal="$test9_dir/portal-empty"
  mkdir -p "$test9b_docs" "$test9b_portal"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9b_docs" "$test9b_portal" 2>/dev/null
  if ! grep -q '"id":"cross"' "$test9b_portal/index.html" && ! grep -q '"id":"ai"' "$test9b_portal/index.html"; then
    echo "PASS: --self-test ケース9b（全不在時はセクション非表示）"
  else
    echo "FAIL: --self-test ケース9b（全不在時はセクション非表示）" >&2
    rm -rf "$test9_dir"
    exit 1
  fi
  rm -rf "$test9_dir"

  echo "--- ケース10: catalog外の旧レイアウトを暗黙発見しない ---"
  test10_dir="$(mktemp -d)"
  test10_repo="$test10_dir/repo"
  test10_docs="$test10_dir/docs"
  test10_portal="$test10_dir/portal"
  mkdir -p "$test10_repo" "$test10_docs/API一覧" "$test10_portal"
  cat > "$test10_docs/API一覧/API一覧.html" <<'TEST10HTML'
<!DOCTYPE html><html><head><title>API一覧</title></head><body>
<script type="application/json" id="unit-manifest">
{"detectionSummary":{"unitCount":7,"analyzedFiles":10},"units":[{},{},{},{},{},{},{}]}
</script>
</body></html>
TEST10HTML
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test10_portal/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test10_repo" "$test10_docs" "$test10_portal" 2>/dev/null
  if ! grep -q '"kind":"api"' "$test10_portal/index.html" \
     && ! grep -q '"title":"API一覧"' "$test10_portal/index.html"; then
    echo "PASS: --self-test ケース10（catalog外artifact typeを暗黙発見しない）"
  else
    echo "FAIL: --self-test ケース10（catalog外artifact typeを発見した）" >&2
    rm -rf "$test10_dir"
    exit 1
  fi
  rm -rf "$test10_dir"

  echo "--- ケース11: .pt-main の縦スクロール指定 ---"
  test11_dir="$(mktemp -d)"
  test11_repo="$test11_dir/repo"
  test11_docs="$test11_dir/docs"
  test11_portal="$test11_dir/portal"
  mkdir -p "$test11_repo" "$test11_docs" "$test11_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test11_portal/code-metrics.json"
  "$SCRIPT_DIR/build-portal.sh" "$test11_repo" "$test11_docs" "$test11_portal" 2>/dev/null
  if grep -A3 '\.pt-main {' "$test11_portal/index.html" | grep -q 'overflow-y: auto'; then
    echo "PASS: --self-test ケース11（.pt-main の縦スクロール指定, 共通シェル partials 由来）"
  else
    echo "FAIL: --self-test ケース11（.pt-main の縦スクロール指定）" >&2
    rm -rf "$test11_dir"
    exit 1
  fi
  rm -rf "$test11_dir"

  echo "--- ケース12: テスト観点表は正本ディレクトリから派生一覧カードになる ---"
  test12_dir="$(mktemp -d)"
  test12_repo="$test12_dir/repo"
  test12_docs="$test12_dir/docs"
  test12_portal="$test12_dir/portal"
  mkdir -p "$test12_repo" "$test12_docs/一覧/テスト観点表" "$test12_portal"
  cat > "$test12_docs/一覧/テスト観点表/テスト観点表.html" <<'TEST12HTML'
<!DOCTYPE html><html><body><script type="application/json" id="unit-manifest">{"unitKind":"test_viewpoint","detectionSummary":{"unitCount":3,"unresolvedCount":0},"units":[]}</script></body></html>
TEST12HTML
  "$SCRIPT_DIR/build-portal.sh" "$test12_repo" "$test12_docs" "$test12_portal" 2>/dev/null
  if grep -q '"title":"テスト観点表"' "$test12_portal/index.html" \
     && grep -q '一覧/テスト観点表/テスト観点表.html' "$test12_portal/index.html"; then
    echo "PASS: --self-test ケース12（テスト観点表の正本パスを派生一覧カードへ反映）"
  else
    echo "FAIL: --self-test ケース12（テスト観点表の派生一覧カード）" >&2
    rm -rf "$test12_dir"
    exit 1
  fi
  rm -rf "$test12_dir"

  echo "--- ケース13: --portal-only は index.html 以外を変更しない ---"
  test13_dir="$(mktemp -d)"
  test13_repo="$test13_dir/repo"
  test13_docs="$test13_dir/docs"
  mkdir -p "$test13_repo" "$test13_docs/プロジェクト共通"
  printf '# 変換禁止\n\n本文。\n' > "$test13_docs/プロジェクト共通/source.md"
  printf '<html><body>glossary</body></html>\n' > "$test13_docs/用語辞書.html"
  before13="$(find "$test13_docs" -type f ! -name index.html -print0 | sort -z | xargs -0 shasum -a 256)"
  "$SCRIPT_DIR/build-portal.sh" "$test13_repo" "$test13_docs" "$test13_docs" --portal-only --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  after13="$(find "$test13_docs" -type f ! -name index.html -print0 | sort -z | xargs -0 shasum -a 256)"
  if [ "$before13" != "$after13" ] || [ -f "$test13_docs/プロジェクト共通/source.html" ]; then
    echo "FAIL: --portal-only changed or generated a non-index artifact" >&2
    rm -rf "$test13_dir"
    exit 1
  fi
  echo "PASS: --portal-only preserves every non-index artifact"
  rm -rf "$test13_dir"

  echo "--- ケース14: generatedAt と manifestContentHash の受け渡し（ラベルの文言に依存せず、値が埋め込まれていることを確認する） ---"
  test14_dir="$(mktemp -d)"
  test14_repo="$test14_dir/repo"
  test14_docs="$test14_dir/docs"
  mkdir -p "$test14_repo" "$test14_docs"
  test14_hash="$(printf 'a%.0s' {1..64})"
  printf '{"manifestContentHash":"%s","screens":[]}\n' "$test14_hash" > "$test14_dir/screen-manifest.ext.json"
  "$SCRIPT_DIR/build-portal.sh" "$test14_repo" "$test14_docs" "$test14_docs" \
    --portal-only --generated-at 2026-07-28T00:00:00Z \
    --screen-manifest "$test14_dir/screen-manifest.ext.json" 2>/dev/null
  if ! grep -qF '2026-07-28' "$test14_docs/index.html" \
     || ! grep -qF "$test14_hash" "$test14_docs/index.html"; then
    echo "FAIL: generatedAt or manifestContentHash was not embedded" >&2
    rm -rf "$test14_dir"
    exit 1
  fi
  echo "PASS: generatedAt and manifestContentHash are embedded deterministically"
  rm -rf "$test14_dir"

  echo "--- ケース15: 埋め込みJSONのscript終端文字列を無害化して復号できる ---"
  test15_dir="$(mktemp -d)"
  test15_repo="$test15_dir/repo"
  test15_docs="$test15_dir/docs"
  mkdir -p "$test15_repo" "$test15_docs/pages"
  printf '<h1>&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;</h1>\n' > "$test15_docs/pages/unsafe.html"
  cat > "$test15_dir/catalog.json" <<'TEST15CATALOG'
{"schemaVersion":1,"categories":[{"key":"unsafe","label":"Unsafe","group":"Test","icon":"warning","sub":"test","blueprints":[{"kind":"unsafe-page","label":"Unsafe page","icon":"warning","desc":"test","dir":"pages","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"unsafe-page","root":"output-dir","glob":"pages/*.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST15CATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test15_repo" "$test15_docs" "$test15_docs" \
    --portal-only --catalog "$test15_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if grep -Fq '</script><img' "$test15_docs/index.html"; then
    echo "FAIL: raw script terminator escaped from embedded JSON" >&2
    rm -rf "$test15_dir"
    exit 1
  fi
  if ! node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const title = JSON.parse(match[1])[0].tools[0].title;
    if (title !== "</script><img src=x onerror=alert(1)>") process.exit(1);
  ' "$test15_docs/index.html"; then
    echo "FAIL: script-safe JSON did not decode to the original title" >&2
    rm -rf "$test15_dir"
    exit 1
  fi
  echo "PASS: embedded JSON is script-safe and JSON.parse restores the original title"
  rm -rf "$test15_dir"

  echo "--- ケース17: 規約・設計いずれのパターンにも一致しない共通文書が『規約』カテゴリに混入しない ---"
  test17_dir="$(mktemp -d)"
  test17_repo="$test17_dir/repo"
  test17_docs="$test17_dir/docs"
  mkdir -p "$test17_repo" "$test17_docs/プロジェクト共通"
  printf '# 作業記録\n\n本文。\n' > "$test17_docs/プロジェクト共通/作業記録.md"
  "$SCRIPT_DIR/build-portal.sh" "$test17_repo" "$test17_docs" "$test17_docs" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.key === "standards");
    const titles = (standards && standards.tools) ? standards.tools.map((t) => t.title) : [];
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17_docs/index.html"; then
    echo "PASS: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリに入らない）"
  else
    echo "FAIL: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリへ混入した）" >&2
    rm -rf "$test17_dir"
    exit 1
  fi
  rm -rf "$test17_dir"

  echo "--- ケース16: ポータル規約検査 ---"
  CONVENTIONS_TEST="$SCRIPT_DIR/test-portal-conventions.sh"
  if [ -f "$CONVENTIONS_TEST" ]; then
    test16_dir="$(mktemp -d)"
    test16_repo="$test16_dir/repo"
    test16_docs="$test16_dir/docs"
    test16_portal="$test16_dir/portal"
    mkdir -p "$test16_repo" "$test16_docs" "$test16_portal"
    echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test16_portal/code-metrics.json"
    "$SCRIPT_DIR/build-portal.sh" "$test16_repo" "$test16_docs" "$test16_portal" 2>/dev/null
    if bash "$CONVENTIONS_TEST" "$test16_portal/index.html"; then
      echo "PASS: --self-test ケース16（ポータル規約検査）"
    else
      echo "FAIL: --self-test ケース16（ポータル規約検査）" >&2
      rm -rf "$test16_dir"
      exit 1
    fi
    rm -rf "$test16_dir"
  else
    echo "SKIP: --self-test ケース16（ポータル規約検査, test-portal-conventions.sh 不在）" >&2
  fi

  exit 0
fi

# --- 引数チェック ---
if [ $# -lt 3 ]; then
  echo "Usage: $0 <target_repo_path> <output_dir> <portal_output_dir> [--catalog <file>] [--generated-at <ISO-8601>] [--portal-only] [--screen-manifest <file>]" >&2
  exit 1
fi

TARGET_REPO="$1"
DOCS_ROOT="$2"
PORTAL_DIR="$3"
shift 3

CATALOG="$DEFAULT_CATALOG"
GENERATED_AT=""
PORTAL_ONLY=0
SCREEN_MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --catalog)
      [ $# -ge 2 ] || { echo "ERROR: --catalog requires a value" >&2; exit 1; }
      CATALOG="$2"; shift 2 ;;
    --generated-at)
      [ $# -ge 2 ] || { echo "ERROR: --generated-at requires a value" >&2; exit 1; }
      GENERATED_AT="$2"; shift 2 ;;
    --portal-only)
      PORTAL_ONLY=1; shift ;;
    --screen-manifest)
      [ $# -ge 2 ] || { echo "ERROR: --screen-manifest requires a value" >&2; exit 1; }
      SCREEN_MANIFEST="$2"; shift 2 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1 ;;
  esac
done

if [ ! -d "$TARGET_REPO" ]; then
  echo "ERROR: target_repo_path does not exist: $TARGET_REPO" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi
if [ ! -f "$CATALOG" ]; then
  echo "ERROR: portal catalog not found: $CATALOG" >&2
  exit 1
fi
if [ ! -f "$CATALOG_ENGINE" ]; then
  echo "ERROR: portal catalog engine not found: $CATALOG_ENGINE" >&2
  exit 1
fi
if [ -n "$SCREEN_MANIFEST" ] && [ ! -f "$SCREEN_MANIFEST" ]; then
  echo "ERROR: screen manifest not found: $SCREEN_MANIFEST" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$TARGET_REPO")"
if [ -n "$GENERATED_AT" ]; then
  GENERATED_DATE="$(node -e 'const d=new Date(process.argv[1]);if(Number.isNaN(d.valueOf()))process.exit(1);process.stdout.write(d.toISOString().slice(0,10))' "$GENERATED_AT")" \
    || { echo "ERROR: --generated-at must be a valid ISO-8601 value" >&2; exit 1; }
else
  GENERATED_DATE="$(date +%Y-%m-%d)"
fi

# 対象リポジトリの短縮コミット SHA（git 管理外は空文字）
if git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  COMMIT_SHORT=" · コミット番号: $(git -C "$TARGET_REPO" rev-parse --short HEAD)"
else
  COMMIT_SHORT=""
fi

# --- 1. コード計測結果の読み取り（counting-code-lines スキルが出力した JSON） ---
CODE_METRICS="$PORTAL_DIR/code-metrics.json"
if [ -f "$CODE_METRICS" ]; then
  total_lines="$(jq -r '.total // 0' "$CODE_METRICS")"
  fe_lines="$(jq -r '.fe // 0' "$CODE_METRICS")"
  be_lines="$(jq -r '.be // 0' "$CODE_METRICS")"
  total_files="$(jq -r '.file_count // 0' "$CODE_METRICS")"
  measured_at="$(jq -r '.measured_at // empty' "$CODE_METRICS")"
  commit_field="$(jq -r '.commit // empty' "$CODE_METRICS")"
  tests_raw="$(jq -c '.tests // null' "$CODE_METRICS")"
  previous_json="$(jq -c '.previous // null' "$CODE_METRICS")"
else
  echo "WARN: code-metrics.json not found at $CODE_METRICS. Using zeros." >&2
  total_lines=0; fe_lines=0; be_lines=0; total_files=0
  measured_at=""
  commit_field=""
  tests_raw="null"
  previous_json="null"
fi

# --- 2. portal catalogが一覧件数とカードを一括導出する ---
kinds_json="[]"

# --- 3. 共通文書リストの収集（standards: 規約系 / design: 設計書系 に分割。category-grouping/rule.md 準拠） ---
common_dir="$DOCS_ROOT/プロジェクト共通"
COMMON_DOC_TEMPLATE_FILE="$SCRIPT_DIR/../templates/common-doc-template.html"

if [ "$PORTAL_ONLY" -eq 0 ]; then
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# md 本文の前処理（BOM 除去・frontmatter スキップ・HTML コメント除去）
# 共通文書ループ・画面設計書ループの両方から使う共通関数。挙動は従来のインライン処理と同一。
prepare_md_content() {
  local file="$1"
  sed -e '1s/^\xEF\xBB\xBF//' "$file" | awk 'NR==1 && /^---$/ {skip=1; next} skip && /^---$/ {skip=0; next} !skip' | awk '
    in_comment {
      buf[++n] = $0
      if ($0 ~ /-->/) { in_comment = 0; n = 0; next }
      next
    }
    /^<!--/ {
      if ($0 ~ /-->/) { next }
      in_comment = 1
      n = 1
      buf[1] = $0
      next
    }
    { print }
    END {
      if (in_comment) { for (i = 1; i <= n; i++) print buf[i] }
    }
  '
}

# JSON文字列として埋め込み、HTMLパーサーが </script> を終端として解釈しないよう「<」をUnicode escapeする。
markdown_to_script_json() {
  printf '%s' "$1" | jq -Rsr 'tojson | gsub("<"; "\\u003c")'
}

if [ -d "$common_dir" ]; then
  while IFS= read -r md_file; do
    title="$(sed -e '1s/^\xEF\xBB\xBF//' "$md_file" | grep -m1 '^#' | sed 's/^##* *//' 2>/dev/null || true)"
    if [ -z "$title" ]; then
      title="$(basename "$md_file" .md)"
    fi

    # .md → .html 変換
    html_basename="$(basename "$md_file" .md).html"
    html_file="$(dirname "$md_file")/$html_basename"
    if [ -f "$COMMON_DOC_TEMPLATE_FILE" ]; then
      # 戻るリンク: 出力先の深さに応じてポータル index.html への相対パスを計算する
      # （深さ1: ../index.html、深さ2: ../../index.html。固定文字列だと深さ2で1段足りない）
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$(dirname "$md_file")" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"
      md_content="$(prepare_md_content "$md_file")"
      md_content_json="$(markdown_to_script_json "$md_content")"
      local_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
        "{{PORTAL_INDEX_HREF}}" "$portal_index_href"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        local_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      # 共通シェル注入（partials が存在する場合のみ）
      if type shell_injection_args >/dev/null 2>&1; then
        shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" "design"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          local_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      local_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")
      doc_html="$(render_template "$(cat "$COMMON_DOC_TEMPLATE_FILE")" "${local_render_args[@]}")"
      printf '%s\n' "$doc_html" > "$html_file"
    fi

  done < <(find "$common_dir" -name '*.md' -type f 2>/dev/null | sort)
fi

# --- 3.5. 画面設計書の変換 ---
SCREEN_DOC_TEMPLATE_FILE="$SCRIPT_DIR/../templates/screen-doc-template.html"
screen_list_dir="$DOCS_ROOT/一覧/画面一覧"

if [ -d "$DOCS_ROOT/画面" ] && [ -f "$SCREEN_DOC_TEMPLATE_FILE" ]; then
  for screen_dir in "$DOCS_ROOT"/画面/screen-*/; do
    [ -d "$screen_dir" ] || continue

    base_md="${screen_dir}基本設計/画面基本設計書.md"
    detail_md="${screen_dir}詳細設計/画面詳細設計書.md"

    for target_md in "$base_md" "$detail_md"; do
      [ -f "$target_md" ] || continue

      title="$(sed -e '1s/^\xEF\xBB\xBF//' "$target_md" | grep -m1 '^#' | sed 's/^##* *//' 2>/dev/null || true)"
      if [ -z "$title" ]; then
        title="$(basename "$target_md" .md)"
      fi

      html_basename="$(basename "$target_md" .md).html"
      html_file="$(dirname "$target_md")/$html_basename"
      md_content="$(prepare_md_content "$target_md")"
      md_content_json="$(markdown_to_script_json "$md_content")"

      # 戻るリンク（ブランド）: 出力先の深さに応じてポータル index.html への相対パスを計算する
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$(dirname "$target_md")" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"

      # 戻るリンク（doc-nav）: 出力先フォルダ → 画面一覧.html への相対パス
      screen_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$screen_list_dir" "$(dirname "$target_md")" 2>/dev/null || echo "../..")"
      screen_index_href="$screen_index_rel/画面一覧.html"

      doc_nav="<a class=\"back-link\" href=\"$screen_index_href\">← 画面一覧へ戻る</a>"
      if [ -f "$base_md" ]; then
        if [ "$target_md" = "$base_md" ]; then
          doc_nav="$doc_nav<span class=\"nav-item active\">基本設計</span>"
        else
          doc_nav="$doc_nav<a class=\"nav-item\" href=\"../基本設計/画面基本設計書.html\">基本設計</a>"
        fi
      fi
      if [ -f "$detail_md" ]; then
        if [ "$target_md" = "$detail_md" ]; then
          doc_nav="$doc_nav<span class=\"nav-item active\">詳細設計</span>"
        else
          doc_nav="$doc_nav<a class=\"nav-item\" href=\"../詳細設計/画面詳細設計書.html\">詳細設計</a>"
        fi
      fi
      if [ -f "${screen_dir}シーケンス図.html" ]; then
        doc_nav="$doc_nav<a class=\"nav-item\" href=\"../シーケンス図.html\">シーケンス図</a>"
      fi
      if [ -f "${screen_dir}テスト項目書/単体テスト仕様書.md" ]; then
        doc_nav="$doc_nav<a class=\"nav-item\" href=\"../テスト項目書/単体テスト仕様書.md\">テストケース</a>"
      fi

      screen_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
        "{{PORTAL_INDEX_HREF}}" "$portal_index_href"
        "{{DOC_NAV}}" "$doc_nav"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        screen_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      # 共通シェル注入（partials が存在する場合のみ）
      if type shell_injection_args >/dev/null 2>&1; then
        shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" "list"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          screen_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      screen_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")

      screen_doc_html="$(render_template "$(cat "$SCREEN_DOC_TEMPLATE_FILE")" "${screen_render_args[@]}")"
      printf '%s\n' "$screen_doc_html" > "$html_file"
    done
  done
fi
fi

# --- 5. テスト計測・鮮度・前回値の JSON 化 ---
if [ "$tests_raw" != "null" ]; then
  tests_count="$(echo "$tests_raw" | jq -r '.count // 0')"
  if [ "$total_lines" -gt 0 ]; then
    density="$(awk -v c="$tests_count" -v t="$total_lines" 'BEGIN{printf "%.1f", c / (t/1000)}')"
  else
    density="0.0"
  fi
  tests_json="$(echo "$tests_raw" | jq -c --argjson density "$density" '. + {density:$density}')"
else
  tests_json="null"
fi

freshness_behind="null"
freshness_note=""
if [ -n "$commit_field" ] && git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if behind_count="$(git -C "$TARGET_REPO" rev-list --count "${commit_field}..HEAD" 2>/dev/null)"; then
    freshness_behind="$behind_count"
    if [ "$behind_count" -eq 0 ]; then
      freshness_note="最新コミットと一致"
    else
      freshness_note="計測後 ${behind_count} コミット・要再計測"
    fi
  else
    # 計測時コミットが履歴に不在（rebase・squash 等で失われた場合）。
    # 事実の表示のみであり合否の判断はしない（再計測を行うかは人・フロー再実行に委ねる）。
    freshness_note="計測時コミットが履歴に不在・要再計測"
  fi
else
  # git 管理外、または commit フィールド欠落。measured_at のみが手がかり。
  freshness_note=""
fi
freshness_json="$(jq -n --arg measured_at "$measured_at" --argjson behind "$freshness_behind" --arg note "$freshness_note" \
  '{measured_at:$measured_at, behind:$behind, note:$note}')"

# --- 6. JSON 組み立て ---
scale_json="$(jq -n --argjson total "$total_lines" --argjson fe "$fe_lines" --argjson be "$be_lines" --argjson files "$total_files" --argjson kinds "$kinds_json" \
  '{total:$total, fe:$fe, be:$be, files:$files, kinds:$kinds}')"

METRICS_JSON="$(jq -n --argjson scale "$scale_json" --argjson tests "$tests_json" --argjson freshness "$freshness_json" --argjson previous "$previous_json" \
  '{scale:$scale, tests:$tests, freshness:$freshness, previous:$previous}')"

catalog_render="$(node "$CATALOG_ENGINE" render --catalog "$CATALOG" --output-root "$DOCS_ROOT" --portal-dir "$PORTAL_DIR")"
CATEGORIES_JSON="$(jq -c '.categories' <<<"$catalog_render")"
kinds_json="$(jq -c '.kinds' <<<"$catalog_render")"

# catalogから導出した一覧件数をmetricsにも渡す。カード定義と規模表示の二重管理をしない。
scale_json="$(jq -n --argjson total "$total_lines" --argjson fe "$fe_lines" --argjson be "$be_lines" --argjson files "$total_files" --argjson kinds "$kinds_json" \
  '{total:$total, fe:$fe, be:$be, files:$files, kinds:$kinds}')"
METRICS_JSON="$(jq -n --argjson scale "$scale_json" --argjson tests "$tests_json" --argjson freshness "$freshness_json" --argjson previous "$previous_json" \
  '{scale:$scale, tests:$tests, freshness:$freshness, previous:$previous}')"

SCREEN_MANIFEST_JSON="{}"
if [ -n "$SCREEN_MANIFEST" ]; then
  SCREEN_MANIFEST_JSON="$(jq -c '.' "$SCREEN_MANIFEST")" \
    || { echo "ERROR: invalid screen manifest JSON: $SCREEN_MANIFEST" >&2; exit 1; }
  manifest_content_hash="$(jq -r '.manifestContentHash // empty' "$SCREEN_MANIFEST")"
  [[ "$manifest_content_hash" =~ ^[0-9a-f]{64}$ ]] \
    || { echo "ERROR: screen manifest must contain a 64 lowercase hex manifestContentHash" >&2; exit 1; }
fi

METRICS_JSON_SAFE="$(printf '%s' "$METRICS_JSON" | script_safe_json)"
CATEGORIES_JSON_SAFE="$(printf '%s' "$CATEGORIES_JSON" | script_safe_json)"
SCREEN_MANIFEST_JSON_SAFE="$(printf '%s' "$SCREEN_MANIFEST_JSON" | script_safe_json)"

# --- 7. テンプレート置換・出力 ---
mkdir -p "$PORTAL_DIR"

template_content="$(cat "$TEMPLATE")"
render_args=(
  "{{PROJECT_NAME}}" "$PROJECT_NAME"
  "{{GENERATED_DATE}}" "$GENERATED_DATE"
  "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
  "{{METRICS_JSON}}" "$METRICS_JSON_SAFE"
  "{{CATEGORIES_JSON}}" "$CATEGORIES_JSON_SAFE"
  "{{SCREEN_MANIFEST_JSON}}" "$SCREEN_MANIFEST_JSON_SAFE"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "index.html" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" ""
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
output="$(render_template "$template_content" "${render_args[@]}")"

printf '%s' "$output" > "$PORTAL_DIR/index.html"
echo "OK: wrote $PORTAL_DIR/index.html" >&2
