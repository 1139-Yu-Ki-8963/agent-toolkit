#!/usr/bin/env bash
# 抽出エンジン: ソースディレクトリ配下のアイコン参照を抽出し、アイコンカタログ JSON を出力する。
#
# Usage: extract-icon-usage.sh <source-dir> <output.json>
#        extract-icon-usage.sh --self-test
#
# 入力契約:
#   <source-dir> : 原本ソースのルート。配下を再帰的に grep する
#   <output.json>: 出力先パス
#
# 出力契約(<output.json>。正本は shared/templates/detail-pages/detail-t10-icon-catalog.html
# 本文コメントの「page-data.json 想定構造」節・page-data-schema.md の T10 節。
# validate-page-data.sh のトップレベル必須キー(pageKind/generatedAt/title/description)も満たす):
#   {
#     pageKind: "icon-catalog", title: "アイコンカタログ", generatedAt, description,
#     icons: [{name, sourceType, usageCount, files: string[]}],
#     summary: [{label, value, note?}]   # 要約タイル(配列。テンプレートJSがforEachで反復する)
#   }
#
# icons[].files は "file:line" 形式の文字列配列(sourceRefと同じ表記に揃える)。
# icons[].sourceType は抽出パターンcに応じて material / svg / (それ以外はパターン名そのもの)。
# material-symbols-outlined 系は material、SVG importは svgへ正規化する(テンプレートの
# ソース種別チップ・グリフ描画がこの2値を特別扱いするため)。React iconsは分類名がテンプレート側の
# 固定チップに無いため、そのまま react-icons とし、テンプレートの汎用フォールバック描画に委ねる。
#
# 抽出パターン(3種類):
#   a. Material Icons  : material-symbols-outlined|material-icons を含むタグ内のアイコン名 → sourceType=material
#   b. SVG import       : import ... from '....svg' のファイル名(拡張子込み) → sourceType=svg
#   c. React icons      : <Lucide*/<Hero*/<FontAwesome* のコンポーネント名 → sourceType=react-icons
#
# grep 該当 0 件は正常系(icons: [] を出力する。fail ではない)。
# description は抽出結果(アイコン種類数・使用箇所数)から組み立てる(固定文字列ではない)。

set -euo pipefail

# --- --self-test モード ---
# (a) validate-page-data.sh を全項目PASSで通過すること
# (b) summary がオブジェクトではなく配列で出力されること
# (c) 生成したHTML(build-detail-page.sh経由)をNodeのDOMスタブ上で実行し、実行時例外が
#     発生しないこと
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local detail_pages_dir="$script_dir/../detail-pages"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-icon-usage-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/components"
  cat > "$tmp/src/components/Header.tsx" <<'EOF'
export function Header() {
  return (
    <div>
      <span class="material-symbols-outlined">home</span>
      <span class="material-symbols-outlined">search</span>
    </div>
  );
}
EOF
  cat > "$tmp/src/components/Icons.tsx" <<'EOF'
import LogoIcon from './assets/logo.svg';
import { LucideUser } from 'lucide-react';
export function Icons() {
  return (<div><LucideUser /></div>);
}
EOF

  local out_json="$tmp/page-data.json"
  bash "$script_path" "$tmp/src" "$out_json"

  # --- ケースa: validate-page-data.sh 全項目PASS ---
  if bash "$detail_pages_dir/validate-page-data.sh" "$out_json" >/dev/null 2>&1; then
    echo "  [PASS] ケースa: 出力JSONがvalidate-page-data.shを全項目PASSで通過"
  else
    echo "  [FAIL] ケースa: 出力JSONがvalidate-page-data.shをPASSしない" >&2
    bash "$detail_pages_dir/validate-page-data.sh" "$out_json" 2>&1 | sed 's/^/    /' >&2 || true
    rc=1
  fi

  # --- ケースb: summaryが配列であること ---
  local summary_type
  summary_type="$(jq -r '.summary | type' "$out_json")"
  if [ "$summary_type" = "array" ]; then
    echo "  [PASS] ケースb: summaryが配列として出力されている"
  else
    echo "  [FAIL] ケースb: summaryの型が配列ではない(実際: ${summary_type})" >&2
    rc=1
  fi

  # フィールド名の確認(テンプレートが読む名前と型に揃っていること)
  local fields_ok=1
  jq -e '.icons[0] | has("sourceType") and has("usageCount") and (.files | type == "array")' "$out_json" >/dev/null 2>&1 || fields_ok=0
  jq -e 'has("description") and (.description | length) > 0' "$out_json" >/dev/null 2>&1 || fields_ok=0
  jq -e '[.icons[].sourceType] | index("material") != null and index("svg") != null' "$out_json" >/dev/null 2>&1 || fields_ok=0
  if [ "$fields_ok" -eq 1 ]; then
    echo "  [PASS] フィールド名: icons.sourceType/usageCount/files・トップレベルdescriptionが存在、sourceTypeがmaterial/svgに正規化されている"
  else
    echo "  [FAIL] フィールド名: テンプレートが期待するフィールド名・値に一致しない項目がある" >&2
    jq . "$out_json" >&2 || true
    rc=1
  fi

  # --- ケースc: 生成HTMLをNodeのDOMスタブで実行し、実行時例外が発生しないこと ---
  if command -v node >/dev/null 2>&1; then
    local outdir_html="$tmp/out-html"
    if bash "$detail_pages_dir/build-detail-page.sh" "$out_json" "$outdir_html" --page icon-catalog >/dev/null 2>&1; then
      local html_file="$outdir_html/アイコンカタログ.html"
      cat > "$tmp/dom-smoke.cjs" <<'NODE'
const fs = require('fs');
const htmlPath = process.argv[2];
const html = fs.readFileSync(htmlPath, 'utf8');

const jsonMatch = html.match(/<script type="application\/json" id="page-data">\n?([\s\S]*?)<\/script>/);
if (!jsonMatch) { console.error('page-data script not found'); process.exit(1); }
const pageDataText = jsonMatch[1];

const scriptRe = /<script>([\s\S]*?)<\/script>/g;
let m, lastScript = null;
while ((m = scriptRe.exec(html)) !== null) { lastScript = m[1]; }
if (!lastScript) { console.error('executable script not found'); process.exit(1); }

class FakeNode {
  constructor(tag) {
    this.tagName = tag; this.attributes = {}; this.children = [];
    this.style = {}; this._text = ''; this.listeners = {};
  }
  setAttribute(k, v) { this.attributes[k] = String(v); }
  getAttribute(k) { return this.attributes[k]; }
  appendChild(c) { this.children.push(c); return c; }
  addEventListener(evt, fn) { (this.listeners[evt] = this.listeners[evt] || []).push(fn); }
  set innerHTML(v) { this._text = v; this.children = []; }
  get innerHTML() { return this._text; }
  set textContent(v) { this._text = v; this.children = []; }
  get textContent() {
    if (this.children.length) {
      return this.children.map((c) => (typeof c === 'string' ? c : (c.textContent || ''))).join('');
    }
    return this._text;
  }
  querySelector(sel) {
    if (sel[0] !== '.') return null;
    const cls = sel.slice(1);
    const stack = [...this.children];
    while (stack.length) {
      const n = stack.shift();
      if (n && n.attributes && (n.attributes.class || '').split(/\s+/).includes(cls)) return n;
      if (n && n.children) stack.push(...n.children);
    }
    return null;
  }
}

const mounts = new Map();
const fakeDocument = {
  createElement: (tag) => new FakeNode(tag),
  createTextNode: (text) => ({ textContent: String(text), children: [] }),
  getElementById: (id) => {
    if (id === 'page-data') return { textContent: pageDataText };
    if (!mounts.has(id)) mounts.set(id, new FakeNode('div'));
    return mounts.get(id);
  },
};

try {
  const fn = new Function('document', lastScript);
  fn(fakeDocument);
  console.log('OK');
} catch (e) {
  console.error('EXCEPTION: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
}
NODE
      if [ -f "$html_file" ] && node "$tmp/dom-smoke.cjs" "$html_file" >/dev/null 2>"$tmp/dom-smoke.err"; then
        echo "  [PASS] ケースc: 生成HTMLをNode DOMスタブ上で実行し、実行時例外が発生しない"
      else
        echo "  [FAIL] ケースc: 生成HTMLの実行で例外が発生した" >&2
        sed 's/^/    /' "$tmp/dom-smoke.err" >&2 2>/dev/null || true
        rc=1
      fi
    else
      echo "  [FAIL] ケースc: build-detail-page.shによるHTML生成自体が失敗した" >&2
      rc=1
    fi
  else
    echo "  [SKIP] ケースc: nodeコマンドが見つからないため実行時例外検査を省略" >&2
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <source-dir> <output.json>" >&2
  exit 1
fi

SOURCE_DIR="$1"
OUTPUT_JSON="$2"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: source-dir not found: $SOURCE_DIR" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RAW_HITS="$TMP_DIR/raw-hits.tsv"
: > "$RAW_HITS"

# ---------------------------------------------------------------------------
# a. Material Icons: material-symbols-outlined / material-icons を含む行から
#    アイコン名(タグ内テキスト、または class 指定直後のトークン)を抽出する
# ---------------------------------------------------------------------------
extract_material_icons() {
  # ディレクトリ横断の再帰走査は1ファイルずつのUTF-8変換を適用できないため、
  # LC_ALL=C でバイト単位走査にし、非UTF-8原本でも「不正なマルチバイト列」警告と
  # 誤ったバイナリ判定を避ける(改善課題1-131。抽出対象パターンはASCIIのためバイト一致で足りる)。
  { LC_ALL=C grep -rnE 'material-symbols-outlined|material-icons' \
    --include='*.tsx' --include='*.ts' --include='*.jsx' --include='*.js' --include='*.html' \
    "$SOURCE_DIR" 2>/dev/null || true; } | while IFS=: read -r file line content; do
    # タグ内テキスト: <span class="material-symbols-outlined">home</span> 等
    # content は非UTF-8原本の行をLC_ALL=Cで拾ったバイト列のため、後段のgrepも
    # LC_ALL=Cで統一し「不正なマルチバイト列」による不一致・警告を避ける(改善課題1-131)。
    name="$(printf '%s' "$content" | LC_ALL=C grep -oE '(material-symbols-outlined|material-icons)[^>]*>[[:space:]]*[A-Za-z0-9_]+' \
      | LC_ALL=C grep -oE '[A-Za-z0-9_]+$' | head -1 || true)"
    if [ -n "$name" ]; then
      printf '%s\t%s\t%s\tmaterial\n' "$name" "$file" "$line" >> "$RAW_HITS"
    fi
  done
}

# ---------------------------------------------------------------------------
# b. SVG import: import X from '....svg' のファイル名(拡張子込み)を抽出する
# ---------------------------------------------------------------------------
extract_svg_imports() {
  # ディレクトリ横断の再帰走査は1ファイルずつのUTF-8変換を適用できないため、
  # LC_ALL=C でバイト単位走査にし、非UTF-8原本でも「不正なマルチバイト列」警告と
  # 誤ったバイナリ判定を避ける(改善課題1-131。抽出対象パターンはASCIIのためバイト一致で足りる)。
  { LC_ALL=C grep -rnE "import.*from.*\.svg" \
    --include='*.tsx' --include='*.ts' --include='*.jsx' --include='*.js' \
    "$SOURCE_DIR" 2>/dev/null || true; } | while IFS=: read -r file line content; do
    # content は非UTF-8原本の行をLC_ALL=Cで拾ったバイト列のため、後段のgrepも
    # LC_ALL=Cで統一し「不正なマルチバイト列」による不一致・警告を避ける(改善課題1-131)。
    name="$(printf '%s' "$content" | LC_ALL=C grep -oE "[A-Za-z0-9_.-]+\.svg" | head -1 || true)"
    if [ -n "$name" ]; then
      printf '%s\t%s\t%s\tsvg\n' "$name" "$file" "$line" >> "$RAW_HITS"
    fi
  done
}

# ---------------------------------------------------------------------------
# c. React icons: <Lucide*/<Hero*/<FontAwesome* のコンポーネント名を抽出する
# ---------------------------------------------------------------------------
extract_react_icons() {
  # ディレクトリ横断の再帰走査は1ファイルずつのUTF-8変換を適用できないため、
  # LC_ALL=C でバイト単位走査にし、非UTF-8原本でも「不正なマルチバイト列」警告と
  # 誤ったバイナリ判定を避ける(改善課題1-131。抽出対象パターンはASCIIのためバイト一致で足りる)。
  { LC_ALL=C grep -rnE '<(Lucide|Hero|FontAwesome)[A-Za-z0-9_]+' \
    --include='*.tsx' --include='*.ts' --include='*.jsx' --include='*.js' \
    "$SOURCE_DIR" 2>/dev/null || true; } | while IFS=: read -r file line content; do
    # content は非UTF-8原本の行をLC_ALL=Cで拾ったバイト列のため、後段のgrepも
    # LC_ALL=Cで統一し「不正なマルチバイト列」による不一致・警告を避ける(改善課題1-131)。
    name="$(printf '%s' "$content" | LC_ALL=C grep -oE '<(Lucide|Hero|FontAwesome)[A-Za-z0-9_]+' | head -1 | sed 's/^<//' || true)"
    if [ -n "$name" ]; then
      printf '%s\t%s\t%s\treact-icons\n' "$name" "$file" "$line" >> "$RAW_HITS"
    fi
  done
}

extract_material_icons
extract_svg_imports
extract_react_icons

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ ! -s "$RAW_HITS" ]; then
  jq -n \
    --arg generatedAt "$GENERATED_AT" \
    --arg description "${SOURCE_DIR} 配下でアイコン参照を検出しなかった(0件)" \
    '{
      pageKind: "icon-catalog",
      title: "アイコンカタログ",
      generatedAt: $generatedAt,
      description: $description,
      icons: [],
      summary: [
        {label: "アイコン種類数", value: 0},
        {label: "使用箇所数", value: 0}
      ]
    }' > "$OUTPUT_JSON"
  exit 0
fi

# raw-hits.tsv: name \t file \t line \t sourceType(material|svg|react-icons)
# name+sourceType をキーに files を集約して icons[] を構築する
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg sourceDir "$SOURCE_DIR" \
  --rawfile raw "$RAW_HITS" \
  '
  ($raw
    | rtrimstr("\n")
    | split("\n")
    | map(select(length > 0) | split("\t") | {name: .[0], file: .[1], line: (.[2] | tonumber), sourceType: .[3]})
  ) as $hits
  |
  ($hits
    | group_by(.name + " " + .sourceType)
    | map({
        name: .[0].name,
        sourceType: .[0].sourceType,
        files: (map(.file + ":" + (.line | tostring))),
        usageCount: length
      })
    | sort_by(.sourceType, .name)
  ) as $icons
  |
  ($hits | group_by(.sourceType) | map({key: .[0].sourceType, value: length})) as $bySource
  |
  {
    pageKind: "icon-catalog",
    title: "アイコンカタログ",
    generatedAt: $generatedAt,
    description: ($sourceDir + " 配下で検出したアイコン参照(種類 " + ($icons | length | tostring) + "・使用箇所 " + ($hits | length | tostring) + "件)"),
    icons: $icons,
    summary: (
      [
        {label: "アイコン種類数", value: ($icons | length)},
        {label: "使用箇所数", value: ($hits | length)}
      ]
      + ($bySource | map({label: .key, value: .value}))
    )
  }
  ' > "$OUTPUT_JSON"
