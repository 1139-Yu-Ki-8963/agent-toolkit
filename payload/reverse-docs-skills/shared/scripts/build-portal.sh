#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

# build-portal.sh — 設計ポータルを生成する
#
# Usage:
#   bash shared/scripts/build-portal.sh <target_repo_path> <output_dir> <portal_output_dir>
#     [--catalog <portal-catalog.json>] [--generated-at <ISO-8601>]
#     [--portal-only] [--screen-manifest <screen-manifest.ext.json>]
#     [--sites <file>] [--site-key <key>]
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

RELATED_MATERIAL_CLOSE_BRACKET_MARKER='__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__'

link_related_material_paths() {
  local markdown_dir="$1"
  local html_dir="$2"
  node - "$markdown_dir" "$html_dir" 3<&0 <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const markdownDir = path.resolve(process.argv[2]);
const htmlDir = path.resolve(process.argv[3]);
const lines = fs.readFileSync(3, 'utf8').split('\n');
let inRelatedMaterials = false;

function existingFileHref(relativePath) {
  const sourceFile = path.join(markdownDir, relativePath);
  try {
    if (!fs.statSync(sourceFile).isFile()) return null;
  } catch (_) {
    return null;
  }

  return path.relative(htmlDir, sourceFile)
    .split(path.sep)
    .join('/')
    .split('/')
    .map((segment) => segment === '.' || segment === '..'
      ? segment
      : encodeURIComponent(segment).replace(/\(/g, '%28').replace(/\)/g, '%29'))
    .join('/');
}

function markdownLinkLabel(relativePath) {
  return relativePath.replace(/\]/g, '__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__');
}

for (let index = 0; index < lines.length; index += 1) {
  const line = lines[index];
  if (/^##\s+/.test(line)) {
    inRelatedMaterials = /^## 関連資料（正の宣言(?:・付録A)?）$/.test(line.trim());
  }
  if (!inRelatedMaterials || !line.startsWith('|')) continue;

  lines[index] = line.replace(/`([^`]+)`/g, (match, relativePath) => {
    const href = existingFileHref(relativePath);
    return href ? `[${markdownLinkLabel(relativePath)}](${href})` : match;
  });
}

process.stdout.write(lines.join('\n'));
NODE
}

prepare_screen_doc_link_renderer() {
  node - 3<&0 <<'NODE'
const fs = require('node:fs');
const source = fs.readFileSync(3, 'utf8');
const original = `return sanitizedUrl ? '<a href="' + sanitizedUrl + '">' + label + '</a>' : label;`;
const replacement = `var displayLabel = label.split('__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__').join('&#93;');
    return sanitizedUrl ? '<a href="' + sanitizedUrl + '">' + displayLabel + '</a>' : label;`;

if (!source.includes(original)) {
  throw new Error('screen document link renderer return expression was not found');
}
process.stdout.write(source.replace(original, replacement));
NODE
}

run_related_material_links_self_test() {
  local test_dir test_repo test_docs test_portal test_detail test_edge test_html test_edge_html test_log

  echo "--- 関連資料リンク self-test: 主fixture リンク4/code4・混在セル、補助edge検査 ---"
  test_dir="$(mktemp -d)"
  test_repo="$test_dir/repo"
  test_docs="$test_dir/docs"
  test_portal="$test_dir/portal"
  test_detail="$test_docs/画面/screen-related-links/詳細設計"
  test_edge="$test_docs/画面/screen-related-links-edge/詳細設計"
  mkdir -p "$test_repo" "$test_detail" "$test_detail/../テスト項目書" "$test_edge" "$test_portal"
  touch "$test_detail/画面 (旧).md" "$test_detail/absolute-entry.md" "$test_detail/実在]D.md" "$test_detail/../テスト項目書/実在C.md" "$test_edge/実在&#93;E.md" "$test_edge/false-prefix.md"
  cat > "$test_detail/画面詳細設計書.md" <<'TEST_MD'
# 関連資料リンク検証

## 関連資料（正の宣言・付録A）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| 混在 | `./画面 (旧).md` / `./不存在A.md` | 同一セル内で個別判定する |
| 実在 | `/absolute-entry.md` | markdownDir連結の絶対形式入力 |
| 実在 | `../テスト項目書/実在C.md` | 出力HTML基準の相対リンク |
| 実在 | `./実在]D.md` | renderer互換のラベルエスケープ |
| 非実在 | `./不存在B.md` | 非実在はコード表記 |
| 非実在 | `./不存在C.md` | 非実在はコード表記 |
| 非実在 | `./不存在D.md` | 非実在はコード表記 |
TEST_MD
  cat > "$test_edge/画面詳細設計書.md" <<'TEST_EDGE_MD'
# 関連資料リンク edge検証

## 関連資料（正の宣言）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| literal entity | `./実在&#93;E.md` | 入力のentity文字列を維持する |

## 関連資料（正の宣言ではない）

| 正の種類 | ファイル | 本書との役割分担 |
|---|---|---|
| 対象外 | `./false-prefix.md` | 実在してもコード表記を維持する |
TEST_EDGE_MD

  test_log="$test_dir/build-portal.log"
  if ! "$0" "$test_repo" "$test_docs" "$test_portal" >"$test_log" 2>&1; then
    echo "FAIL: 関連資料リンク self-test（fixture生成が失敗）" >&2
    cat "$test_log" >&2
    rm -rf "$test_dir"
    return 1
  fi
  test_html="$test_detail/画面詳細設計書.html"
  test_edge_html="$test_edge/画面詳細設計書.html"
  if ! node - "$test_html" "$test_edge_html" <<'NODE'
const fs = require('node:fs');
const vm = require('node:vm');

function rendered(htmlFile) {
  const source = fs.readFileSync(htmlFile, 'utf8');
  const match = source.match(/<script type="application\/json" id="doc-md">([\s\S]*?)<\/script>\s*<script>([\s\S]*?)<\/script>/i);
  if (!match) throw new Error('doc-md or renderer script not found');
  const content = {
    _innerHTML: '', _h1: null,
    set innerHTML(value) {
      this._innerHTML = value;
      const h1Match = value.match(/<h1>([\s\S]*?)<\/h1>/i);
      if (h1Match) this._h1 = { nodeType: 1, tagName: 'H1', textContent: h1Match[1].replace(/<[^>]*>/g, ''), parentNode: { removeChild() { content._h1 = null; } } };
    },
    get innerHTML() { return this._innerHTML; },
    querySelector(selector) { return selector === 'h1' ? this._h1 : null; },
    querySelectorAll() { return []; },
  };
  const document = {
    getElementById(id) { return ({ 'doc-md': { textContent: match[1] }, 'doc-content': content, 'dp-hero-title': { textContent: '' }, 'toc-list': { appendChild() {}, querySelector() { return null; } }, 'screen-nav-title': { textContent: '' } })[id] || null; },
    createElement() { return { classList: { add() {} }, appendChild() {} }; }, querySelectorAll() { return []; },
  };
  vm.runInNewContext(match[2], { document, window: { addEventListener() {} }, requestAnimationFrame(callback) { callback(); } });
  return { markdown: JSON.parse(match[1]), html: content.innerHTML };
}

const main = rendered(process.argv[2]);
const edge = rendered(process.argv[3]);
const links = [
  '[./画面 (旧).md](%E7%94%BB%E9%9D%A2%20%28%E6%97%A7%29.md)',
  '[/absolute-entry.md](absolute-entry.md)',
  '[../テスト項目書/実在C.md](../%E3%83%86%E3%82%B9%E3%83%88%E9%A0%85%E7%9B%AE%E6%9B%B8/%E5%AE%9F%E5%9C%A8C.md)',
  '[./実在__PORTAL_RELATED_MATERIAL_CLOSE_BRACKET__D.md](%E5%AE%9F%E5%9C%A8%5DD.md)',
];
const codes = ['`./不存在A.md`', '`./不存在B.md`', '`./不存在C.md`', '`./不存在D.md`'];
const expectedDomLinks = [
  '<a href="%E7%94%BB%E9%9D%A2%20%28%E6%97%A7%29.md">./画面 (旧).md</a>',
  '<a href="absolute-entry.md">/absolute-entry.md</a>',
  '<a href="../%E3%83%86%E3%82%B9%E3%83%88%E9%A0%85%E7%9B%AE%E6%9B%B8/%E5%AE%9F%E5%9C%A8C.md">../テスト項目書/実在C.md</a>',
  '<a href="%E5%AE%9F%E5%9C%A8%5DD.md">./実在&#93;D.md</a>',
];
const expectedDomCodes = codes.map((entry) => `<code>${entry.slice(1, -1)}</code>`);
const complete = (main.markdown.match(/\[[^\]]+\]\([^\)]+\)/g) || []).length === 4
  && (main.markdown.match(/`[^`]+`/g) || []).length === 4
  && (main.html.match(/<a href="[^"]+">/g) || []).length === 4
  && (main.html.match(/<code>[^<]+<\/code>/g) || []).length === 4
  && [...links, ...codes].every((entry) => main.markdown.includes(entry))
  && [...expectedDomLinks, ...expectedDomCodes].every((entry) => main.html.includes(entry))
  && edge.markdown.includes('[./実在&#93;E.md](%E5%AE%9F%E5%9C%A8%26%2393%3BE.md)')
  && edge.markdown.includes('`./false-prefix.md`')
  && edge.html.includes('<a href="%E5%AE%9F%E5%9C%A8%26%2393%3BE.md">./実在&amp;#93;E.md</a>')
  && edge.html.includes('<code>./false-prefix.md</code>');
if (!complete) process.exit(1);
NODE
  then
    echo "FAIL: 関連資料リンク self-test（主fixture Markdown/portable DOMのリンク4件・コード4件、補助edge検査）" >&2
    rm -rf "$test_dir"
    return 1
  fi
  echo "PASS: 関連資料リンク self-test（主fixture 正本見出し・実在4/非実在4・混在セル、Markdown/portable DOMのリンク4件・コード4件；補助fixture false-prefix/literal &#93;）"
  rm -rf "$test_dir"
}

# --- self-test ---
if [ "${1:-}" = "--self-test-related-material-links" ]; then
  run_related_material_links_self_test
  exit $?
fi

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
  mkdir -p "$test4_repo" "$test4_docs/プロジェクト共通" "$test4_docs/画面/screen-title/詳細設計" "$test4_portal"
  printf '\xEF\xBB\xBF# BOM付き見出し\n本文' > "$test4_docs/プロジェクト共通/bom-test.md"
  printf -- '---\ntitle: frontmatter\n---\n# FM後の見出し\n本文' > "$test4_docs/プロジェクト共通/fm-test.md"
  printf -- '---\n# 執筆者向け内部指示: この見出しを文書名に使わない\n---\n# 共通本文タイトル\n本文' > "$test4_docs/プロジェクト共通/title-frontmatter.md"
  printf -- '---\n# 執筆者向け内部指示: この見出しを文書名に使わない\n---\n# 画面本文タイトル\n本文' > "$test4_docs/画面/screen-title/詳細設計/画面詳細設計書.md"
  printf '見出しのない本文' > "$test4_docs/プロジェクト共通/fallback-title.md"
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

  test4_common_html="$test4_docs/プロジェクト共通/title-frontmatter.html"
  test4_screen_html="$test4_docs/画面/screen-title/詳細設計/画面詳細設計書.html"
  test4_fallback_html="$test4_docs/プロジェクト共通/fallback-title.html"
  if ! node -e '
    const fs = require("node:fs");
    const vm = require("node:vm");
    const pages = process.argv.slice(1);
    let failed = false;
    const text = (value) => (value || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").trim();
    for (let i = 0; i < pages.length; i += 2) {
      const [file, expected] = pages.slice(i, i + 2);
      const source = fs.readFileSync(file, "utf8");
      const title = text((source.match(/<title>([\s\S]*?)<\/title>/i) || [])[1]);
      const crumb = text((source.match(/<span class="pt-crumb-current">([\s\S]*?)<\/span>/i) || [])[1]);
      const initialH1 = text((source.match(/<h1[^>]*id="dp-hero-title"[^>]*>([\s\S]*?)<\/h1>/i) || [])[1]);
      const scriptMatch = source.match(/<script\s+type="application\/json"\s+id="doc-md">([\s\S]*?)<\/script>\s*<script>([\s\S]*?)<\/script>/i);
      let runtimeH1 = "(script extraction failed)";
      if (!scriptMatch) {
        console.error(`FAIL: --self-test ケース4（意味語名のNode DOM検査） file=${file} expected=${expected} title=${title} crumb=${crumb} initialH1=${initialH1} runtimeH1=${runtimeH1}`);
        failed = true;
        continue;
      }
      const hero = { textContent: initialH1 };
      const content = {
        _innerHTML: "",
        _h1: null,
        set innerHTML(value) {
          this._innerHTML = value;
          const h1Match = value.match(/<h1>([\s\S]*?)<\/h1>/i);
          if (!h1Match) return;
          const h1 = {
            nodeType: 1,
            tagName: "H1",
            textContent: text(h1Match[1]),
            parentNode: { removeChild(node) { if (node === h1) content._h1 = null; } },
          };
          this._h1 = h1;
        },
        get innerHTML() { return this._innerHTML; },
        querySelector(selector) { return selector === "h1" ? this._h1 : null; },
        querySelectorAll() { return []; },
      };
      const tocList = { querySelector() { return null; }, appendChild() {} };
      const screenNavTitle = { textContent: "" };
      const document = {
        getElementById(id) {
          return ({ "doc-md": { textContent: scriptMatch[1] }, "doc-content": content, "dp-hero-title": hero, "toc-list": tocList, "screen-nav-title": screenNavTitle })[id] || null;
        },
        createElement() { return { appendChild() {}, classList: { add() {} } }; },
        querySelectorAll() { return []; },
      };
      const window = { addEventListener() {} };
      try {
        vm.runInNewContext(scriptMatch[2], { document, window, requestAnimationFrame(callback) { callback(); } });
        runtimeH1 = hero.textContent;
      } catch (error) {
        runtimeH1 = `(vm error: ${error.message})`;
      }
      if (title !== expected || crumb !== expected || initialH1 !== expected || runtimeH1 !== expected) {
        console.error(`FAIL: --self-test ケース4（意味語名のNode DOM検査） file=${file} expected=${expected} title=${title} crumb=${crumb} initialH1=${initialH1} runtimeH1=${runtimeH1}`);
        failed = true;
      }
    }
    process.exit(failed ? 1 : 0);
  ' "$test4_common_html" '共通本文タイトル' "$test4_screen_html" '画面本文タイトル' "$test4_fallback_html" 'fallback-title'; then
    rm -rf "$test4_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース4（frontmatter内の内部指示を意味語名に採用しない）"
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
  if ! grep -qF 'grid-template-columns: 200px minmax(0, 1fr)' "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF "className = 'table-scroll-shell'" "$test5_docs/プロジェクト共通/test-doc.html" \
     || ! grep -qF 'can-scroll-right' "$test5_docs/プロジェクト共通/test-doc.html"; then
    echo "FAIL: ケース5 — 詳細文書の可変幅カラムまたは横スクロール合図が欠落" >&2
    rm -rf "$test5_dir"
    exit 1
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

  echo "--- ケース9: マトリクス・対応表・AI設定資産カード（実在時のみ出現、全不在時は空状態表示） ---"
  test9_dir="$(mktemp -d)"
  test9_repo="$test9_dir/repo"
  test9_docs="$test9_dir/docs"
  test9_portal="$test9_dir/portal"
  mkdir -p "$test9_repo" "$test9_docs/マトリクス・対応表/権限画面マトリクス" "$test9_docs/AI設定資産" "$test9_portal"
  echo '<html><body>perm screen matrix</body></html>' > "$test9_docs/マトリクス・対応表/権限画面マトリクス/権限画面マトリクス.html"
  echo '<html><body>ai assets</body></html>' > "$test9_docs/AI設定資産/AI設定資産.html"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9_docs" "$test9_portal" 2>/dev/null
  # 全不在ケース: 全カテゴリを空状態付きで保持し、サイドバーのアンカー先を本文生成契約へ接続する
  test9b_docs="$test9_dir/docs-empty"
  test9b_portal="$test9_dir/portal-empty"
  mkdir -p "$test9b_docs" "$test9b_portal"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9b_docs" "$test9b_portal" 2>/dev/null
  if node - "$test9_portal/index.html" "$test9b_portal/index.html" "$DEFAULT_CATALOG" <<'NODE'
const fs = require('fs');
const assert = require('assert/strict');
const vm = require('vm');
const mixedSource = fs.readFileSync(process.argv[2], 'utf8');
const emptySource = fs.readFileSync(process.argv[3], 'utf8');
const catalog = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
function embeddedJson(source, id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing embedded JSON: ${id}`);
  return JSON.parse(match[1]);
}
class TestNode {
  constructor(tagName, text = '') {
    this.tagName = tagName.toUpperCase();
    this.attributes = {};
    this.childNodes = [];
    this.parentNode = null;
    this._text = text;
    this._listeners = {};
    this.classList = {
      add: (...names) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        this.className = [...classes].join(' ');
      },
      contains: (name) => this.className.split(/\s+/).includes(name),
      toggle: (name, force) => {
        const present = this.classList.contains(name);
        const enabled = force === undefined ? !present : Boolean(force);
        if (enabled && !present) this.classList.add(name);
        if (!enabled && present) {
          this.className = this.className.split(/\s+/).filter((item) => item && item !== name).join(' ');
        }
        return enabled;
      },
    };
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') nodesById.set(String(value), this);
  }
  getAttribute(name) { return this.attributes[name] || null; }
  set className(value) { this.attributes.class = String(value); }
  get className() { return this.attributes.class || ''; }
  set id(value) { this.setAttribute('id', value); }
  get id() { return this.getAttribute('id') || ''; }
  set href(value) { this.setAttribute('href', value); }
  get href() { return this.getAttribute('href') || ''; }
  set textContent(value) {
    this._text = String(value);
    this.childNodes = [];
  }
  get textContent() {
    return this._text + this.childNodes.map((child) => child.textContent).join('');
  }
  set innerHTML(value) { this._innerHTML = String(value); }
  get innerHTML() { return this._innerHTML || ''; }
  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) this.childNodes.splice(index, 1);
    child.parentNode = null;
    return child;
  }
  addEventListener(type, listener) { this._listeners[type] = listener; }
  querySelectorAll(selector) { return descendants(this).filter((node) => matches(node, selector)); }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function descendants(node) {
  return node.childNodes.flatMap((child) => [child, ...descendants(child)]);
}
function matches(node, selector) {
  const parts = selector.split('.');
  const tag = !selector.startsWith('.') ? parts.shift().toUpperCase() : '';
  return (!tag || node.tagName === tag) && parts.filter(Boolean).every((name) => node.classList.contains(name));
}
let nodesById = new Map();
function element(tag, attrs = {}, text = '') {
  const node = new TestNode(tag, text);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
}
function verifyFixture(source, expectedAllEmpty) {
nodesById = new Map();
const categories = embeddedJson(source, 'portal-categories');
const sidebar = embeddedJson(source, 'pt-nav-data');
assert(categories.length > 0, 'fixture must retain catalog categories');
if (expectedAllEmpty) {
  assert(categories.every((category) => category.tools.length === 0), 'all-zero fixture must have zero discoveries');
} else {
  assert(categories.some((category) => category.tools.length > 0), 'mixed fixture must contain discovered tools');
  assert(categories.some((category) => category.tools.length === 0), 'mixed fixture must contain empty categories');
}
assert(categories.every((category) => category.tools.length > 0
  || (category.empty
    && category.empty.title === '生成済み資料はありません'
    && category.empty.desc === `${category.title}の資料はまだ生成されていません。`
    && category.empty.count === '0 件')),
  'every empty category requires canonical display content');
const sidebarKeys = sidebar.map((item) => item.key);
const categoryIds = categories.map((category) => category.id);
assert.equal(new Set(sidebarKeys).size, sidebarKeys.length, 'sidebar category keys must be unique');
assert.equal(new Set(categoryIds).size, categoryIds.length, 'rendered category ids must be unique');
assert.deepEqual(sidebarKeys, categoryIds, 'sidebar keys and rendered category ids must match in order');
const catalogCategories = new Map(catalog.categories.map((category) => [category.key, category]));
assert(sidebar.every((item) => {
  const definition = catalogCategories.get(item.key);
  return definition && item.count === definition.blueprints.length;
}), 'sidebar counts must match catalog blueprint counts');
const catsMountMatch = source.match(/<div\b(?=[^>]*\bid=["']pm-cats["'])(?=[^>]*\bclass=["'][^"']*\bpm-cats\b[^"']*["'])[^>]*>([\s\S]*?)<\/div>/);
assert(catsMountMatch, 'generated HTML must contain the pm-cats container');
function attributesFromStartTag(startTag) {
  return Object.fromEntries(
    [...startTag.matchAll(/\s([:\w-]+)\s*=\s*(["'])(.*?)\2/g)]
      .map((match) => [match[1], match[3]])
  );
}
function categorySections(html) {
  return [...html.matchAll(/(<section\b[^>]*>)/g)]
    .map((match) => attributesFromStartTag(match[1]))
    .filter((attributes) => /^cat-[a-z0-9-]+$/.test(attributes.id || ''));
}
const containerSections = categorySections(catsMountMatch[1]);
const bodySections = categorySections(source);
const containerIdList = containerSections.map((attributes) => attributes.id);
const bodyIdList = bodySections.map((attributes) => attributes.id);
assert.equal(containerSections.length, categories.length, 'pm-cats must contain exactly one section per category');
assert(containerSections.every((attributes) => (attributes.class || '').split(/\s+/).includes('pm-cat')), 'generated category sections must retain the pm-cat class');
assert.equal(new Set(containerIdList).size, containerIdList.length, 'pm-cats category section ids must not be duplicated');
assert.equal(bodySections.length, containerSections.length, 'all category sections in generated HTML must belong to pm-cats');
assert.equal(new Set(bodyIdList).size, bodyIdList.length, 'category section ids in generated HTML must not be duplicated');
assert(sidebar.length === categories.length, 'sidebar and body must retain the same category count');
assert(sidebar.every((item) => containerIdList.includes(`cat-${item.key}`)), 'every sidebar category must have a pm-cats category id');

const documentElement = element('html');
const metricsMount = element('div', { id: 'metrics-mount' });
const catsMount = element('div', { id: 'pm-cats' });
const searchInput = element('input', { id: 'pm-search-input' });
const nav = element('nav', { id: 'pt-nav' });
const sideMatch = source.match(/<aside\b(?=[^>]*\bclass=["'][^"']*\bpt-sidebar\b[^"']*["'])[^>]*>/);
assert(sideMatch, 'generated HTML must contain the portal sidebar');
const side = element('aside', attributesFromStartTag(sideMatch[0]));
const portalHref = side.getAttribute('data-portal-href');
assert(portalHref, 'generated portal sidebar must declare data-portal-href');
containerSections.forEach((attributes) => catsMount.appendChild(element('section', attributes)));
for (const id of ['portal-metrics', 'portal-categories', 'pt-nav-data', 'pt-sites-data']) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing script data: ${id}`);
  element('script', { id }, match[1]);
}
const document = {
  documentElement,
  readyState: 'complete',
  activeElement: null,
  getElementById(id) { return nodesById.get(id) || null; },
  createElement(tag) { return element(tag); },
  createTextNode(text) { return new TestNode('#text', String(text)); },
  querySelector(selector) { return selector === '.pt-sidebar' ? side : null; },
  querySelectorAll() { return []; },
  addEventListener() {},
};
const scripts = [...source.matchAll(/<script(?![^>]*type=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
const sidebarScript = scripts.find((script) => script.includes('var portalHref =') && script.includes('cats.forEach'));
const portalScript = scripts.find((script) => script.includes("var categories = JSON.parse") && script.includes('categories.forEach'));
assert(sidebarScript, 'generated sidebar runtime script must exist');
assert(portalScript, 'generated portal runtime script must exist');
const context = {
  document,
  window: { matchMedia() { return { matches: false }; } },
  localStorage: { getItem() { return null; }, setItem() {} },
};
vm.runInNewContext(sidebarScript, context);
vm.runInNewContext(portalScript, context);

const sections = catsMount.querySelectorAll('section.pm-cat');
assert.equal(sections.length, categories.length, 'runtime DOM must retain exactly one section per category');
assert.equal(new Set(sections.map((section) => section.id)).size, sections.length, 'runtime DOM category section ids must not be duplicated');
categories.forEach((category) => {
  const section = sections.find((candidate) => candidate.id === `cat-${category.id}`);
  assert(section, `missing runtime category section: ${category.id}`);
  const emptyCards = section.querySelectorAll('.card.is-empty');
  const toolCards = section.querySelectorAll('.card.is-tool');
  assert.equal(toolCards.length, category.tools.length, `runtime tool card count mismatch: ${category.id}`);
  assert.equal(emptyCards.length, category.tools.length === 0 ? 1 : 0, `runtime empty-state card count mismatch: ${category.id}`);
  if (category.tools.length > 0) return;
  const card = emptyCards[0];
  assert.equal(card.tagName, 'DIV', `empty-state card must be a non-link div: ${category.id}`);
  assert.equal(card.getAttribute('href'), null, `empty-state card must not have an href: ${category.id}`);
  assert.equal(card.getAttribute('role'), 'status', `empty-state card must expose role=status: ${category.id}`);
  assert.equal(card.querySelector('.card-title')?.textContent, category.empty.title, `empty title mismatch: ${category.id}`);
  assert.equal(card.querySelector('.card-desc')?.textContent, category.empty.desc, `empty description mismatch: ${category.id}`);
  assert.equal(card.querySelector('.card-count')?.textContent, category.empty.count, `empty count mismatch: ${category.id}`);
});
const navCategoryLinks = nav.querySelectorAll('a.pt-nav-item').filter((link) => (link.getAttribute('href') || '').includes('#cat-'));
assert.equal(navCategoryLinks.length, sidebar.length, 'runtime sidebar must render one anchor per category');
const navCategoryHrefs = navCategoryLinks.map((link) => link.getAttribute('href') || '');
assert.equal(new Set(navCategoryHrefs).size, navCategoryHrefs.length, 'runtime sidebar category hrefs must be unique');
sidebar.forEach((item, index) => {
  const expectedHref = `${portalHref}#cat-${item.key}`;
  assert.equal(navCategoryHrefs[index], expectedHref, `runtime sidebar href mismatch: ${item.key}`);
  assert(sections.some((section) => section.id === `cat-${item.key}`), `runtime sidebar target section missing: ${item.key}`);
});
}
verifyFixture(mixedSource, false);
verifyFixture(emptySource, true);
NODE
  then
    echo "PASS: --self-test ケース9a（混在カテゴリの通常カードと空状態カード）"
    echo "PASS: --self-test ケース9b（全不在カテゴリの空状態とサイドバーアンカー先ID）"
  else
    echo "FAIL: --self-test ケース9a/9b（実生成DOMのカテゴリカード契約）" >&2
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
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17_docs/index.html"; then
    echo "PASS: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリに入らない）"
  else
    echo "FAIL: --self-test ケース17（規約・設計いずれにも一致しない文書が規約カテゴリへ混入した）" >&2
    rm -rf "$test17_dir"
    exit 1
  fi
  rm -rf "$test17_dir"

  echo "--- ケース17b: standardsカテゴリが欠落した合成カタログでは、ケース17の検査ロジックがFAILを返す（検査自体の健全性確認・陰性フィクスチャ） ---"
  test17b_dir="$(mktemp -d)"
  test17b_repo="$test17b_dir/repo"
  test17b_docs="$test17b_dir/docs"
  mkdir -p "$test17b_repo" "$test17b_docs"
  cat > "$test17b_dir/catalog.json" <<'TEST17BCATALOG'
{"schemaVersion":1,"categories":[{"key":"project","label":"Project","group":"共通","icon":"folder","sub":"test","blueprints":[]}]}
TEST17BCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17b_repo" "$test17b_docs" "$test17b_docs" \
    --portal-only --catalog "$test17b_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17b_docs/index.html"; then
    echo "FAIL: --self-test ケース17b（standardsカテゴリの欠落を検査が見逃した）" >&2
    rm -rf "$test17b_dir"
    exit 1
  else
    echo "PASS: --self-test ケース17b（standardsカテゴリの欠落をケース17ロジックがFAILとして検知した）"
  fi
  rm -rf "$test17b_dir"

  echo "--- ケース17c: 想定外タイトルがstandardsカテゴリへ混入した合成カタログでは、ケース17の検査ロジックがFAILを返す（検査自体の健全性確認・陰性フィクスチャ） ---"
  test17c_dir="$(mktemp -d)"
  test17c_repo="$test17c_dir/repo"
  test17c_docs="$test17c_dir/docs"
  mkdir -p "$test17c_repo" "$test17c_docs/プロジェクト共通"
  printf '<h1>作業記録</h1>\n' > "$test17c_docs/プロジェクト共通/作業記録.html"
  cat > "$test17c_dir/catalog.json" <<'TEST17CCATALOG'
{"schemaVersion":1,"categories":[{"key":"standards","label":"規約","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"contaminated-standard","label":"Contaminated","icon":"rule","desc":"test","dir":"プロジェクト共通","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"contaminated-standard-page","root":"output-dir","glob":"プロジェクト共通/作業記録.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST17CCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17c_repo" "$test17c_docs" "$test17c_docs" \
    --portal-only --catalog "$test17c_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17c_docs/index.html"; then
    echo "FAIL: --self-test ケース17c（想定外タイトルの混入を検査が見逃した）" >&2
    rm -rf "$test17c_dir"
    exit 1
  else
    echo "PASS: --self-test ケース17c（想定外タイトルの混入をケース17ロジックがFAILとして検知した）"
  fi
  rm -rf "$test17c_dir"

  echo "--- ケース17d: 合成カタログ経由でも汚染が無ければケース17の検査ロジックはPASSする（正常系） ---"
  test17d_dir="$(mktemp -d)"
  test17d_repo="$test17d_dir/repo"
  test17d_docs="$test17d_dir/docs"
  mkdir -p "$test17d_repo" "$test17d_docs/プロジェクト共通"
  printf '<h1>コーディング規約</h1>\n' > "$test17d_docs/プロジェクト共通/作業記録.html"
  cat > "$test17d_dir/catalog.json" <<'TEST17DCATALOG'
{"schemaVersion":1,"categories":[{"key":"standards","label":"規約","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"clean-standard","label":"Clean","icon":"rule","desc":"test","dir":"プロジェクト共通","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"clean-standard-page","root":"output-dir","glob":"プロジェクト共通/作業記録.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}]}
TEST17DCATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test17d_repo" "$test17d_docs" "$test17d_docs" \
    --portal-only --catalog "$test17d_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
    if (!match) process.exit(1);
    const categories = JSON.parse(match[1]);
    const standards = categories.find((c) => c.id === "standards");
    if (!standards) process.exit(1);
    const titles = standards.tools.map((t) => t.title);
    if (titles.includes("作業記録")) process.exit(1);
  ' "$test17d_docs/index.html"; then
    echo "PASS: --self-test ケース17d（合成カタログ経由でも汚染が無ければ検査はPASSする）"
  else
    echo "FAIL: --self-test ケース17d（汚染が無いのに検査がFAILした）" >&2
    rm -rf "$test17d_dir"
    exit 1
  fi
  rm -rf "$test17d_dir"

  echo "--- ケース18: 規約20種の正規配置をstandardsカテゴリへ反映する ---"
  test18_dir="$(mktemp -d)"
  test18_repo="$test18_dir/repo"
  test18_docs="$test18_dir/docs"
  test18_portal="$test18_dir/portal"
  mkdir -p "$test18_repo" "$test18_docs/規約" "$test18_portal"
  test18_fixture_dir="$SCRIPT_DIR/../templates/リバース検証/規約"
  test18_standard_names=(
    "コーディング規約"
    "命名規約"
    "ディレクトリ構成規約"
    "コンポーネント設計規約"
    "レビュー観点表"
    "テスト方針書"
    "AIエージェント運用"
    "安全な操作"
    "セッション管理"
    "AI設定資産管理"
    "定型運用"
    "開発フロー"
    "ツール・コマンド実行"
    "開発環境"
    "Git運用"
    "デリバリー"
    "セキュリティ"
    "ドキュメント"
    "ポータル"
    "コミュニケーション"
  )
  test18_fixture_ok=1
  for standard_name in "${test18_standard_names[@]}"; do
    if [ -f "$test18_fixture_dir/$standard_name.md" ]; then
      cp "$test18_fixture_dir/$standard_name.md" "$test18_docs/規約/$standard_name.md"
    else
      test18_fixture_ok=0
    fi
  done
  if [ "$test18_fixture_ok" -ne 1 ]; then
    echo "FAIL: --self-test ケース18（規約雛形20種が $test18_fixture_dir に揃っていない）" >&2
    rm -rf "$test18_dir"
    exit 1
  fi
  "$SCRIPT_DIR/build-portal.sh" "$test18_repo" "$test18_docs" "$test18_portal" --generated-at 2026-07-29T00:00:00Z 2>/dev/null
  if ! node - "$test18_docs" "$test18_portal/index.html" <<'NODE'
const fs = require("fs");
const path = require("path");
const [docsRoot, portalHtml] = process.argv.slice(2);
const standardNames = [
  "コーディング規約", "命名規約", "ディレクトリ構成規約", "コンポーネント設計規約",
  "レビュー観点表", "テスト方針書", "AIエージェント運用", "安全な操作",
  "セッション管理", "AI設定資産管理", "定型運用", "開発フロー",
  "ツール・コマンド実行", "開発環境", "Git運用", "デリバリー",
  "セキュリティ", "ドキュメント", "ポータル", "コミュニケーション",
];
for (const name of standardNames) {
  if (!fs.existsSync(path.join(docsRoot, "規約", `${name}.html`))) process.exit(1);
}
const source = fs.readFileSync(portalHtml, "utf8");
const match = source.match(/<script type="application\/json" id="portal-categories">([\s\S]*?)<\/script>/);
if (!match) process.exit(1);
const categories = JSON.parse(match[1]);
const standards = categories.find((category) => category.id === "standards");
if (!standards || standards.tools.length !== standardNames.length) process.exit(1);
if (standards.tools.some((tool) => !tool.href.startsWith("../docs/規約/"))) process.exit(1);
NODE
  then
    echo "FAIL: --self-test ケース18（規約20種の正規配置がstandardsカテゴリへ反映されない）" >&2
    rm -rf "$test18_dir"
    exit 1
  fi
  echo "PASS: --self-test ケース18（規約20種の正規配置・standards件数一致）"
  rm -rf "$test18_dir"

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

  echo "--- ケース19: 画面詳細設計書の本文・付録順序 ---"
  SECTION_ORDER_TEST="$SCRIPT_DIR/test-screen-doc-section-order.cjs"
  if [ ! -f "$SECTION_ORDER_TEST" ]; then
    echo "FAIL: --self-test ケース19（章順序検査スクリプトが見つからない）" >&2
    exit 1
  fi
  if node "$SECTION_ORDER_TEST"; then
    echo "PASS: --self-test ケース19（実テンプレート・正式生成経路のDOM章順序）"
  else
    echo "FAIL: --self-test ケース19（実テンプレート・正式生成経路のDOM章順序）" >&2
    exit 1
  fi

  echo "--- ケース20: サイドバーとメインコンテンツの見出し番号が全カテゴリで一致する（DOM比較） ---"
  test20_dir="$(mktemp -d)"
  test20_repo="$test20_dir/repo"
  test20_docs="$test20_dir/docs"
  mkdir -p "$test20_repo" "$test20_docs/docs"
  printf '<h1>Gamma Doc</h1>\n' > "$test20_docs/docs/gamma.html"
  printf '<h1>Beta Doc</h1>\n' > "$test20_docs/docs/beta.html"
  # alpha カテゴリの glob はどのファイルにも一致させず、空状態カテゴリを意図的に作る
  cat > "$test20_dir/catalog.json" <<'TEST20CATALOG'
{"schemaVersion":1,"categories":[
  {"key":"gamma","label":"Gamma","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"gamma-doc","label":"Gamma Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"gamma-doc-page","root":"output-dir","glob":"docs/gamma.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]},
  {"key":"alpha","label":"Alpha","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"alpha-doc","label":"Alpha Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"alpha-doc-page","root":"output-dir","glob":"docs/nomatch-alpha.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]},
  {"key":"beta","label":"Beta","group":"共通","icon":"rule","sub":"test","blueprints":[{"kind":"beta-doc","label":"Beta Doc","icon":"rule","desc":"test","dir":"docs","generator":"test-generator","unit":"件","countFormat":"detail","discovery":{"artifactType":"beta-doc-page","root":"output-dir","glob":"docs/beta.html","matchKind":"file","titleSource":"html-h1","dirSource":"match-parent","instanceKeySource":"relative-path","sort":"relative-path-bytewise"}}]}
]}
TEST20CATALOG
  "$SCRIPT_DIR/build-portal.sh" "$test20_repo" "$test20_docs" "$test20_docs" \
    --portal-only --catalog "$test20_dir/catalog.json" --generated-at 2026-07-28T00:00:00Z 2>/dev/null
  if node - "$test20_docs/index.html" <<'NODE'
const fs = require('fs');
const assert = require('assert/strict');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

function embeddedJson(id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing embedded JSON: ${id}`);
  return JSON.parse(match[1]);
}

let nodesById = new Map();
class TestNode {
  constructor(tagName, text = '') {
    this.tagName = tagName.toUpperCase();
    this.attributes = {};
    this.childNodes = [];
    this.parentNode = null;
    this._text = text;
    this._listeners = {};
    this.classList = {
      add: (...names) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        this.className = [...classes].join(' ');
      },
      contains: (name) => this.className.split(/\s+/).includes(name),
      toggle: (name, force) => {
        const present = this.classList.contains(name);
        const enabled = force === undefined ? !present : Boolean(force);
        if (enabled && !present) this.classList.add(name);
        if (!enabled && present) {
          this.className = this.className.split(/\s+/).filter((item) => item && item !== name).join(' ');
        }
        return enabled;
      },
    };
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') nodesById.set(String(value), this);
  }
  getAttribute(name) { return this.attributes[name] || null; }
  set className(value) { this.attributes.class = String(value); }
  get className() { return this.attributes.class || ''; }
  set id(value) { this.setAttribute('id', value); }
  get id() { return this.getAttribute('id') || ''; }
  set href(value) { this.setAttribute('href', value); }
  get href() { return this.getAttribute('href') || ''; }
  set textContent(value) {
    this._text = String(value);
    this.childNodes = [];
  }
  get textContent() {
    return this._text + this.childNodes.map((child) => child.textContent).join('');
  }
  set innerHTML(value) { this._innerHTML = String(value); }
  get innerHTML() { return this._innerHTML || ''; }
  appendChild(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) this.childNodes.splice(index, 1);
    child.parentNode = null;
    return child;
  }
  addEventListener(type, listener) { this._listeners[type] = listener; }
  querySelectorAll(selector) { return descendants(this).filter((node) => matches(node, selector)); }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function descendants(node) {
  return node.childNodes.flatMap((child) => [child, ...descendants(child)]);
}
function matches(node, selector) {
  const parts = selector.split('.');
  const tag = !selector.startsWith('.') ? parts.shift().toUpperCase() : '';
  return (!tag || node.tagName === tag) && parts.filter(Boolean).every((name) => node.classList.contains(name));
}
function element(tag, attrs = {}, text = '') {
  const node = new TestNode(tag, text);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
}
function attributesFromStartTag(startTag) {
  return Object.fromEntries(
    [...startTag.matchAll(/\s([:\w-]+)\s*=\s*(["'])(.*?)\2/g)]
      .map((match) => [match[1], match[3]])
  );
}

const categories = embeddedJson('portal-categories');
const sidebar = embeddedJson('pt-nav-data');
assert(categories.length >= 3, 'fixture must retain every synthetic category (including the empty one)');
assert(categories.some((category) => category.tools.length === 0), 'fixture must include an empty category to exercise index continuity');

const metricsMount = element('div', { id: 'metrics-mount' });
const catsMount = element('div', { id: 'pm-cats' });
const searchInput = element('input', { id: 'pm-search-input' });
const nav = element('nav', { id: 'pt-nav' });
const sideMatch = source.match(/<aside\b(?=[^>]*\bclass=["'][^"']*\bpt-sidebar\b[^"']*["'])[^>]*>/);
assert(sideMatch, 'generated HTML must contain the portal sidebar');
const side = element('aside', attributesFromStartTag(sideMatch[0]));
for (const id of ['portal-metrics', 'portal-categories', 'pt-nav-data', 'pt-sites-data']) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = source.match(new RegExp(`<script[^>]*id=["']${escaped}["'][^>]*>([\\s\\S]*?)<\\/script>`));
  assert(match, `missing script data: ${id}`);
  element('script', { id }, match[1]);
}
const document = {
  documentElement: element('html'),
  readyState: 'complete',
  activeElement: null,
  getElementById(id) { return nodesById.get(id) || null; },
  createElement(tag) { return element(tag); },
  createTextNode(text) { return new TestNode('#text', String(text)); },
  querySelector(selector) { return selector === '.pt-sidebar' ? side : null; },
  querySelectorAll() { return []; },
  addEventListener() {},
};
const scripts = [...source.matchAll(/<script(?![^>]*type=["']application\/json["'])[^>]*>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
const sidebarScript = scripts.find((script) => script.includes('var portalHref =') && script.includes('cats.forEach'));
const portalScript = scripts.find((script) => script.includes('var categories = JSON.parse') && script.includes('categories.forEach'));
assert(sidebarScript, 'generated sidebar runtime script must exist');
assert(portalScript, 'generated portal runtime script must exist');
const context = {
  document,
  window: { matchMedia() { return { matches: false }; } },
  localStorage: { getItem() { return null; }, setItem() {} },
};
vm.runInNewContext(sidebarScript, context);
vm.runInNewContext(portalScript, context);

const sections = catsMount.querySelectorAll('section.pm-cat');
assert.equal(sections.length, categories.length, 'runtime DOM must retain exactly one section per category');
const navItems = nav.querySelectorAll('a.pt-nav-item');
const navCategoryItems = navItems.filter((item) => (item.getAttribute('href') || '').includes('#cat-'));
assert.equal(navCategoryItems.length, sidebar.length, 'runtime sidebar must render one anchor per category');

categories.forEach((category) => {
  const section = sections.find((candidate) => candidate.id === `cat-${category.id}`);
  assert(section, `missing runtime category section: ${category.id}`);
  const mainNumEl = section.querySelector('.pm-cat-num');
  assert(mainNumEl, `missing main content heading number: ${category.id}`);
  const mainNum = mainNumEl.textContent;

  const navItem = navCategoryItems.find((item) => (item.getAttribute('href') || '').endsWith(`#cat-${category.id}`));
  assert(navItem, `missing sidebar nav item: ${category.id}`);
  const navNumEl = navItem.querySelector('.pt-nav-num');
  assert(navNumEl, `missing sidebar heading number: ${category.id}`);
  const sideNum = navNumEl.textContent;

  assert.equal(mainNum, sideNum, `heading number mismatch for category ${category.id}: main=${mainNum} sidebar=${sideNum}`);
});
NODE
  then
    echo "PASS: --self-test ケース20（サイドバーとメインコンテンツの見出し番号がDOM上で全カテゴリ一致）"
  else
    echo "FAIL: --self-test ケース20（サイドバーとメインコンテンツの見出し番号が不一致）" >&2
    rm -rf "$test20_dir"
    exit 1
  fi
  rm -rf "$test20_dir"

  echo "--- ケース21: 画面詳細/基本設計書テンプレートのコンテンツカラム幅拡張・横スクロール発生率（DOM計測） ---"
  COLUMN_WIDTH_TEST="$SCRIPT_DIR/test-screen-doc-column-width.cjs"
  if [ ! -f "$COLUMN_WIDTH_TEST" ]; then
    echo "FAIL: --self-test ケース21（コンテンツカラム幅検査スクリプトが見つからない）" >&2
    exit 1
  fi
  if node "$COLUMN_WIDTH_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース21（コンテンツカラム幅拡張・横スクロール発生率の検証に失敗）" >&2
    exit 1
  fi

  echo "--- ケース22: 画面詳細設計書テンプレートの参照用付録折りたたみ（生コード全文・API全量列挙、DOM計測） ---"
  APPENDIX_COLLAPSE_TEST="$SCRIPT_DIR/test-screen-doc-appendix-collapse.cjs"
  if [ ! -f "$APPENDIX_COLLAPSE_TEST" ]; then
    echo "FAIL: --self-test ケース22（付録折りたたみ検査スクリプトが見つからない）" >&2
    exit 1
  fi
  if node "$APPENDIX_COLLAPSE_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース22（参照用付録折りたたみの検証に失敗）" >&2
    exit 1
  fi

  echo "--- ケース23: §16要確認事項一覧の行数自動判定によるpt-calloutコールアウト付与（DOM計測） ---"
  UNRESOLVED_CALLOUT_TEST="$SCRIPT_DIR/test-screen-doc-unresolved-callout.cjs"
  if [ ! -f "$UNRESOLVED_CALLOUT_TEST" ]; then
    echo "FAIL: --self-test ケース23（要確認事項コールアウト検査スクリプトが見つからない）" >&2
    exit 1
  fi
  if node "$UNRESOLVED_CALLOUT_TEST"; then
    :
  else
    echo "FAIL: --self-test ケース23（要確認事項コールアウトの検証に失敗）" >&2
    exit 1
  fi

  run_related_material_links_self_test

  exit 0
fi

# --- 引数チェック ---
if [ $# -lt 3 ]; then
  echo "Usage: $0 <target_repo_path> <output_dir> <portal_output_dir> [--catalog <file>] [--generated-at <ISO-8601>] [--portal-only] [--screen-manifest <file>] [--sites <file>] [--site-key <key>]" >&2
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
SITES_FILE=""
SITE_KEY=""
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
    --sites)
      [ $# -ge 2 ] || { echo "ERROR: --sites requires a value" >&2; exit 1; }
      SITES_FILE="$2"; shift 2 ;;
    --site-key)
      [ $# -ge 2 ] || { echo "ERROR: --site-key requires a value" >&2; exit 1; }
      SITE_KEY="$2"; shift 2 ;;
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
common_roots=("$DOCS_ROOT/プロジェクト共通" "$DOCS_ROOT/規約")
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

extract_md_title() {
  local content="$1"
  local fallback="$2"
  local title
  title="$(printf '%s\n' "$content" | awk '/^#[[:space:]]+/ { sub(/^#[[:space:]]+/, ""); print; exit }')"
  if [ -z "$title" ]; then
    title="$fallback"
  fi
  printf '%s\n' "$title"
}

# JSON文字列として埋め込み、HTMLパーサーが </script> を終端として解釈しないよう「<」をUnicode escapeする。
markdown_to_script_json() {
  printf '%s' "$1" | jq -Rsr 'tojson | gsub("<"; "\\u003c")'
}

for common_dir in "${common_roots[@]}"; do
if [ "$common_dir" = "$DOCS_ROOT/規約" ]; then
  common_category="standards"
else
  common_category="design"
fi
if [ -d "$common_dir" ]; then
  while IFS= read -r md_file; do
    md_content="$(prepare_md_content "$md_file")"
    title="$(extract_md_title "$md_content" "$(basename "$md_file" .md)")"

    # .md → .html 変換
    html_basename="$(basename "$md_file" .md).html"
    html_file="$(dirname "$md_file")/$html_basename"
    if [ -f "$COMMON_DOC_TEMPLATE_FILE" ]; then
      # 戻るリンク: 出力先の深さに応じてポータル index.html への相対パスを計算する
      # （深さ1: ../index.html、深さ2: ../../index.html。固定文字列だと深さ2で1段足りない）
      portal_index_rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$PORTAL_DIR" "$(dirname "$md_file")" 2>/dev/null || echo "..")"
      portal_index_href="$portal_index_rel/index.html"
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
        shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" "$common_category" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$md_file")"
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
done

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

      html_basename="$(basename "$target_md" .md).html"
      html_file="$(dirname "$target_md")/$html_basename"
      md_content="$(prepare_md_content "$target_md")"
      md_content="$(link_related_material_paths "$(dirname "$target_md")" "$(dirname "$html_file")" <<< "$md_content")"
      title="$(extract_md_title "$md_content" "$(basename "$target_md" .md)")"
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
        shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "$portal_index_href" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" "list" "${SITES_FILE:-}" "${SITE_KEY:-}" "$(dirname "$target_md")"
        if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
          screen_render_args+=("${SHELL_RENDER_ARGS[@]}")
        fi
      fi
      screen_render_args+=("{{DOC_MARKDOWN_JSON}}" "$md_content_json")

      screen_doc_template="$(cat "$SCREEN_DOC_TEMPLATE_FILE")"
      if [[ "$md_content" == *"$RELATED_MATERIAL_CLOSE_BRACKET_MARKER"* ]]; then
        screen_doc_template="$(prepare_screen_doc_link_renderer <<< "$screen_doc_template")"
      fi
      screen_doc_html="$(render_template "$screen_doc_template" "${screen_render_args[@]}")"
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
CATEGORY_SECTIONS_HTML="$(jq -r '.categories[] | "<section class=\"pm-cat\" id=\"cat-\(.id)\"></section>"' <<<"$catalog_render")"
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
  "{{CATEGORY_SECTIONS_HTML}}" "$CATEGORY_SECTIONS_HTML"
  "{{SCREEN_MANIFEST_JSON}}" "$SCREEN_MANIFEST_JSON_SAFE"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
# 共通シェル注入（partials が存在する場合のみ）
if type shell_injection_args >/dev/null 2>&1; then
  shell_injection_args "$SCRIPT_DIR/../templates" "$CATALOG" "index.html" "$PROJECT_NAME" "$GENERATED_DATE" "$COMMIT_SHORT" "shared/scripts/build-portal.sh" "" "${SITES_FILE:-}" "${SITE_KEY:-}" "$PORTAL_DIR"
  if [ ${#SHELL_RENDER_ARGS[@]} -gt 0 ]; then
    render_args+=("${SHELL_RENDER_ARGS[@]}")
  fi
fi
output="$(render_template "$template_content" "${render_args[@]}")"

printf '%s' "$output" > "$PORTAL_DIR/index.html"
echo "OK: wrote $PORTAL_DIR/index.html" >&2
