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
# 出力契約(<output.json>。正本は delivery-payload/templates/detail-pages/detail-t10-icon-catalog.html
# 本文コメントの「page-data.json 想定構造」節・page-data-schema.md の T10 節。
# validate-page-data.sh のトップレベル必須キー(pageKind/generatedAt/title/description)も満たす):
#   {
#     pageKind: "icon-catalog", title: "アイコンカタログ", generatedAt, description,
#     icons: [{name, sourceType, usageCount, files: string[]}],
#     summary: [{label, value, note?}]   # 要約タイル(配列。テンプレートJSがforEachで反復する)
#   }
#
# icons[].files は "file:line" 形式の文字列配列(sourceRefと同じ表記に揃える)。
# file 部分は <source-dir> を起点とした相対パスとする(page-data-schema.md の
# 「sourceRefの形式」節が正。呼び出し側スキルは <source-dir> に対象リポジトリの
# ルート絶対パスを渡す契約のため、この相対パスは対象リポジトリからの相対パスと一致する)。
# icons[].sourceType は抽出パターンcに応じて material / svg / (それ以外はパターン名そのもの)。
# material-symbols-outlined 系は material、SVG importは svgへ正規化する(テンプレートの
# ソース種別チップ・グリフ描画がこの2値を特別扱いするため)。React iconsは分類名がテンプレート側の
# 固定チップに無いため、そのまま react-icons とし、テンプレートの汎用フォールバック描画に委ねる。
#
# 抽出パターン(4種類):
#   a. Material Icons  : material-symbols-outlined|material-icons を含むタグ内のアイコン名 → sourceType=material
#   b. SVG import       : import ... from '....svg' のファイル名(拡張子込み) → sourceType=svg
#   c. React icons      : <Lucide*/<Hero*/<FontAwesome* のコンポーネント名 → sourceType=react-icons
#   d. Icon wrapper component(1-XXX): アイコン名をpropとして受け取る共通コンポーネント
#      (例: frontend/src/components/Icon.tsx 相当。定義に material-symbols-outlined を
#      含み、`export function <Name>` または `export default function <Name>` で
#      export されているコンポーネント)を呼び出す側のJSXから、`name="<literal>"` の
#      ように引用符付きリテラルで渡されたアイコン名を抜き出す → sourceType=material。
#      タグは複数行にまたがってもよい(閉じ`>`が現れる行まで連結して読む)。
#      追える記法: `<Icon name="swords" ... />` のような文字列リテラル直渡し。
#      追えない記法: `name={variable}` のように変数・式で渡す動的な値(静的走査では
#      解決不能。icons[] には含めず、summary の「動的参照(追跡不能)」件数にのみ計上する)、
#      `const Icon = (...) => {...}; export default Icon;` のようなアロー関数
#      export(パターンdのコンポーネント名検出が関数宣言のexportのみに対応するため未対応)。
#
# grep 該当 0 件は正常系(icons: [] を出力する。fail ではない)。
# description は抽出結果(アイコン種類数・使用箇所数)から組み立てる(固定文字列ではない)。

set -euo pipefail

# --- --self-test モード ---
# (a) validate-page-data.sh を全項目PASSで通過すること
# (b) summary がオブジェクトではなく配列で出力されること
# (c) 生成したHTML(build-detail-page.sh経由)をNodeのDOMスタブ上で実行し、実行時例外が
#     発生しないこと
# (d) アイコン名をpropとして受け取る共通コンポーネント越しの参照(name="<literal>"、複数行タグ含む)を
#     抽出でき、name={変数}の動的参照はicons[]に含めずsummaryの件数にのみ計上すること
# (e) icons[].filesの値が<source-dir>を起点とした相対パスであり、絶対パスを含まないこと
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local detail_pages_dir="$script_dir/../detail-pages"
  local tmp rc=0
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-icon-usage-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/components" "$tmp/src/pages"
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
  cat > "$tmp/src/components/Icon.tsx" <<'EOF'
export default function Icon({ name, label }) {
  const classes = ['material-symbols-outlined', 'icon'].join(' ');
  return (
    <span className={classes} aria-label={label}>
      {name}
    </span>
  );
}
EOF
  cat > "$tmp/src/pages/Sample.tsx" <<'EOF'
import Icon from '../components/Icon';
export function Sample({ dynamicName }) {
  return (
    <div>
      <Icon name="swords" label="剣" />
      <Icon
        name="settings"
        label="設定"
      />
      <Icon name={dynamicName} label="動的" />
    </div>
  );
}
EOF

  local out_json="$tmp/page-data.json"
  bash "$script_path" "$tmp/src" "$out_json"

  # --- ケースa: validate-page-data.sh 全項目PASS ---
  local validate_out
  if validate_out="$(bash "$detail_pages_dir/validate-page-data.sh" "$out_json" 2>&1)"; then
    echo "  [PASS] ケースa: 出力JSONがvalidate-page-data.shを全項目PASSで通過"
  else
    echo "  [FAIL] ケースa: 出力JSONがvalidate-page-data.shをPASSしない" >&2
    printf '%s\n' "$validate_out" | sed 's/^/    /' >&2
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

  # --- ケースd: Iconラッパーコンポーネント越しのリテラル参照(複数行タグ含む)を抽出し、
  #     name={変数}の動的参照はicons[]に含めずsummaryの件数にのみ計上する ---
  local swords_ok settings_ok dynamic_count
  swords_ok="$(jq -r '[.icons[] | select(.name == "swords" and .sourceType == "material")] | length' "$out_json")"
  settings_ok="$(jq -r '[.icons[] | select(.name == "settings" and .sourceType == "material")] | length' "$out_json")"
  dynamic_count="$(jq -r '[.summary[] | select(.label == "動的参照(追跡不能)")][0].value' "$out_json")"
  if [ "$swords_ok" = "1" ] && [ "$settings_ok" = "1" ] && [ "$dynamic_count" = "1" ]; then
    echo "  [PASS] ケースd: Iconラッパー越しのリテラル参照(単一行・複数行)を抽出し、動的参照1件をsummaryに計上"
  else
    echo "  [FAIL] ケースd: Iconラッパー越しの抽出が期待と異なる(swords=${swords_ok}, settings=${settings_ok}, dynamic=${dynamic_count})" >&2
    jq . "$out_json" >&2 || true
    rc=1
  fi

  # --- ケースe: icons[].filesが<source-dir>を起点とした相対パスであり、絶対パスを含まないこと ---
  local absolute_files
  absolute_files="$(jq -r '[.icons[].files[] | select(startswith("/"))] | length' "$out_json")"
  if [ "$absolute_files" = "0" ]; then
    echo "  [PASS] ケースe: icons[].filesに絶対パスが混入していない"
  else
    echo "  [FAIL] ケースe: icons[].filesに絶対パスが${absolute_files}件混入している" >&2
    jq -r '[.icons[].files[] | select(startswith("/"))]' "$out_json" >&2 || true
    rc=1
  fi

  # --- 説明-絶対パス不在: descriptionに環境固有の絶対パス(SOURCE_DIR自体)が焼き込まれないこと ---
  local description_text
  description_text="$(jq -r '.description' "$out_json")"
  if [[ "$description_text" != *"$tmp"* ]] && [[ "$description_text" != /Users/* ]] && [[ "$description_text" != */Users/* ]]; then
    echo "  [PASS] 説明-絶対パス不在: descriptionに絶対パスが含まれない"
  else
    echo "  [FAIL] 説明-絶対パス不在: descriptionに絶対パスが混入している(${description_text})" >&2
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

  # --- 走査-除外ディレクトリ: .venv 等の除外対象配下のファイルが走査結果に含まれないこと ---
  mkdir -p "$tmp/src/.venv/pkg"
  cat > "$tmp/src/.venv/pkg/Excluded.tsx" <<'EOF'
export function Excluded() {
  return (<span class="material-symbols-outlined">venv_excluded_icon</span>);
}
EOF
  local out_excl_json="$tmp/out-exclude.json"
  bash "$script_path" "$tmp/src" "$out_excl_json"
  local excluded_count
  excluded_count="$(jq -r '[.icons[] | select(.name == "venv_excluded_icon")] | length' "$out_excl_json")"
  if [ "$excluded_count" = "0" ]; then
    echo "  [PASS] 走査-除外ディレクトリ: .venv配下のファイルが走査結果に含まれない"
  else
    echo "  [FAIL] 走査-除外ディレクトリ: .venv配下のファイルが走査結果に含まれている(${excluded_count}件)" >&2
    rc=1
  fi

  # 改善課題 一時ディレクトリ-作成先: TMP_DIR生成が明示テンプレート
  # ("${TMPDIR:-/tmp}/extract-icon-usage-work.XXXXXX")を使っており、
  # ${TMPDIRを無視する裸}のmktemp -dに戻っていないことを、mktempラッパーで
  # 呼び出し引数を記録して構造的に検証する（システムの既定一時領域が書き込み
  # 可能かどうかに依存しない判定）。
  mktemp_shim_dir="$tmp/mktemp-shim"
  mkdir -p "$mktemp_shim_dir"
  mktemp_log="$tmp/mktemp-calls.log"
  : > "$mktemp_log"
  cat > "$mktemp_shim_dir/mktemp" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$mktemp_log"
exec /usr/bin/mktemp "\$@"
SHIM
  chmod +x "$mktemp_shim_dir/mktemp"

  if PATH="$mktemp_shim_dir:$PATH" bash "$script_path" "$tmp/src" "$tmp/out-mktemp-check.json" >/dev/null 2>&1 \
    && grep -q -- '-d .*extract-icon-usage-work' "$mktemp_log"; then
    echo "  [PASS] TMP_DIR生成が明示テンプレートを使う（\${TMPDIRを無視する裸}のmktemp -dではない）"
  else
    echo "  [FAIL] TMP_DIR生成が\${TMPDIRを無視する裸}のmktemp -dのままである、または検証に失敗した" >&2
    rc=1
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

# SOURCE_DIR を末尾スラッシュなしへ正規化(相対パス表示の起点に使う。改善課題: 証跡パス-絶対パスの混入)
SOURCE_DIR="${SOURCE_DIR%/}"

# TMP_DIR は明示テンプレート("${TMPDIR:-/tmp}/...")で作る。裸の `mktemp -d` は
# $TMPDIR を無視し書き込み許可の外にある既定の一時領域を使うため、サンドボックス実行環境では
# 失敗する(改善課題「一時ディレクトリ-作成先」。手元の許可された環境で動いても裸の形へ戻すな)。
if ! TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-icon-usage-work.XXXXXX" 2>/dev/null)" || [ -z "$TMP_DIR" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi

# --- 非UTF-8原本の走査対応(改善課題1-131): detect-encoding.sh の走査ヘルパーを読み込む ---
_EXTRACT_ICON_USAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../detect-encoding.sh
source "$_EXTRACT_ICON_USAGE_SCRIPT_DIR/../detect-encoding.sh"
if ! SCAN_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/extract-icon-usage-scan.XXXXXX" 2>/dev/null)" || [ -z "$SCAN_WORKDIR" ]; then
  echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
  exit 2
fi

trap 'rm -rf "$TMP_DIR" "$SCAN_WORKDIR"' EXIT

RAW_HITS="$TMP_DIR/raw-hits.tsv"
: > "$RAW_HITS"

# ---------------------------------------------------------------------------
# a. Material Icons: material-symbols-outlined / material-icons を含む行から
#    アイコン名(タグ内テキスト、または class 指定直後のトークン)を抽出する
# ---------------------------------------------------------------------------
extract_material_icons() {
  # 非UTF-8原本の走査対応(改善課題1-131): ファイルを1つずつ列挙し、to_utf8_for_scanで
  # UTF-8化した一時コピーに対して走査する。RAW_HITSへは<source-dir>起点の相対パス(relpath)を
  # 記録する(改善課題: 証跡パス-絶対パスの混入。fileは検索起点のfind結果=絶対または呼び出し時の
  # 表記そのままのため、そのまま記録すると絶対パスが混入する)。
  local file relpath scan_file line content name
  while IFS= read -r -d '' file; do
    relpath="${file#"$SOURCE_DIR"/}"
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    while IFS=: read -r line content; do
      [ -z "$line" ] && continue
      # タグ内テキスト: <span class="material-symbols-outlined">home</span> 等
      name="$(printf '%s' "$content" | grep -oE '(material-symbols-outlined|material-icons)[^>]*>[[:space:]]*[A-Za-z0-9_]+' \
        | grep -oE '[A-Za-z0-9_]+$' | head -1 || true)"
      if [ -n "$name" ]; then
        printf '%s\t%s\t%s\tmaterial\n' "$name" "$relpath" "$line" >> "$RAW_HITS"
      fi
    done < <(grep -nE 'material-symbols-outlined|material-icons' "$scan_file" 2>/dev/null || true)
  done < <(find "$SOURCE_DIR" \
    \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name __pycache__ -o -name .git \) -prune -o \
    \( -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' -o -name '*.html' \) \
    -type f -print0 2>/dev/null)
}

# ---------------------------------------------------------------------------
# b. SVG import: import X from '....svg' のファイル名(拡張子込み)を抽出する
# ---------------------------------------------------------------------------
extract_svg_imports() {
  # 非UTF-8原本の走査対応(改善課題1-131): ファイルを1つずつ列挙し、to_utf8_for_scanで
  # UTF-8化した一時コピーに対して走査する。RAW_HITSへは<source-dir>起点の相対パス(relpath)を
  # 記録する(改善課題: 証跡パス-絶対パスの混入)。
  local file relpath scan_file line content name
  while IFS= read -r -d '' file; do
    relpath="${file#"$SOURCE_DIR"/}"
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    while IFS=: read -r line content; do
      [ -z "$line" ] && continue
      name="$(printf '%s' "$content" | grep -oE "[A-Za-z0-9_.-]+\.svg" | head -1 || true)"
      if [ -n "$name" ]; then
        printf '%s\t%s\t%s\tsvg\n' "$name" "$relpath" "$line" >> "$RAW_HITS"
      fi
    done < <(grep -nE "import.*from.*\.svg" "$scan_file" 2>/dev/null || true)
  done < <(find "$SOURCE_DIR" \
    \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name __pycache__ -o -name .git \) -prune -o \
    \( -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' \) \
    -type f -print0 2>/dev/null)
}

# ---------------------------------------------------------------------------
# c. React icons: <Lucide*/<Hero*/<FontAwesome* のコンポーネント名を抽出する
# ---------------------------------------------------------------------------
extract_react_icons() {
  # 非UTF-8原本の走査対応(改善課題1-131): ファイルを1つずつ列挙し、to_utf8_for_scanで
  # UTF-8化した一時コピーに対して走査する。RAW_HITSへは<source-dir>起点の相対パス(relpath)を
  # 記録する(改善課題: 証跡パス-絶対パスの混入)。
  local file relpath scan_file line content name
  while IFS= read -r -d '' file; do
    relpath="${file#"$SOURCE_DIR"/}"
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    while IFS=: read -r line content; do
      [ -z "$line" ] && continue
      name="$(printf '%s' "$content" | grep -oE '<(Lucide|Hero|FontAwesome)[A-Za-z0-9_]+' | head -1 | sed 's/^<//' || true)"
      if [ -n "$name" ]; then
        printf '%s\t%s\t%s\treact-icons\n' "$name" "$relpath" "$line" >> "$RAW_HITS"
      fi
    done < <(grep -nE '<(Lucide|Hero|FontAwesome)[A-Za-z0-9_]+' "$scan_file" 2>/dev/null || true)
  done < <(find "$SOURCE_DIR" \
    \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name __pycache__ -o -name .git \) -prune -o \
    \( -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' \) \
    -type f -print0 2>/dev/null)
}

# ---------------------------------------------------------------------------
# d. Icon wrapper component(改善課題: アイコン抽出-変数展開を追えない): アイコン名を
#    propとして受け取る共通コンポーネント越しの参照を抽出する。
#    d-1: コンポーネント自身の定義から material-symbols-outlined を描画するコンポーネント名を集める
#    d-2: そのコンポーネント名を呼ぶ側のJSXから name="<literal>" 形式のリテラル値を抜き出す。
#         name={variable} のような動的な値は静的走査では解決できないため、icons[] には含めず、
#         DYNAMIC_REF_COUNT_FILE へ1行ずつ積み上げて件数のみ summary に残す。
# ---------------------------------------------------------------------------
find_material_wrapper_components() {
  local file scan_file
  while IFS= read -r -d '' file; do
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    if grep -qE 'material-symbols-outlined' "$scan_file" 2>/dev/null; then
      grep -oE 'export[[:space:]]+(default[[:space:]]+)?function[[:space:]]+[A-Za-z0-9_]+' "$scan_file" 2>/dev/null \
        | grep -oE '[A-Za-z0-9_]+$'
    fi
  done < <(find "$SOURCE_DIR" \
    \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name __pycache__ -o -name .git \) -prune -o \
    \( -name '*.tsx' -o -name '*.jsx' \) \
    -type f -print0 2>/dev/null)
}

extract_icon_wrapper_usage() {
  local wrapper="$1"
  local file relpath scan_file regex startln buf name
  regex="<${wrapper}([[:space:]/>]|\$)"
  while IFS= read -r -d '' file; do
    relpath="${file#"$SOURCE_DIR"/}"
    scan_file="$(to_utf8_for_scan "$file" "$SCAN_WORKDIR")"
    while IFS=$'\t' read -r startln buf; do
      [ -z "$startln" ] && continue
      name="$(printf '%s' "$buf" | grep -oE "name[[:space:]]*=[[:space:]]*[\"'][A-Za-z0-9_]+[\"']" | head -1 \
        | sed -E "s/^name[[:space:]]*=[[:space:]]*[\"']//; s/[\"']\$//" || true)"
      if [ -n "$name" ]; then
        printf '%s\t%s\t%s\tmaterial\n' "$name" "$relpath" "$startln" >> "$RAW_HITS"
      elif printf '%s' "$buf" | grep -qE 'name[[:space:]]*=[[:space:]]*\{'; then
        echo x >> "$DYNAMIC_REF_COUNT_FILE"
      fi
    done < <(awk -v re="$regex" '
      $0 ~ re && !instag {
        buf = $0; startln = NR; instag = 1
        if ($0 ~ />/) { print startln "\t" buf; instag = 0; buf = ""; next }
        next
      }
      instag {
        buf = buf " " $0
        if ($0 ~ />/) { print startln "\t" buf; instag = 0; buf = "" }
        next
      }
    ' "$scan_file" 2>/dev/null || true)
  done < <(find "$SOURCE_DIR" \
    \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name __pycache__ -o -name .git \) -prune -o \
    \( -name '*.tsx' -o -name '*.jsx' \) \
    -type f -print0 2>/dev/null)
}

DYNAMIC_REF_COUNT_FILE="$TMP_DIR/dynamic-icon-refs.count"
: > "$DYNAMIC_REF_COUNT_FILE"

extract_material_icons
extract_svg_imports
extract_react_icons

while IFS= read -r wrapper; do
  [ -z "$wrapper" ] && continue
  extract_icon_wrapper_usage "$wrapper"
done < <(find_material_wrapper_components | sort -u)

DYNAMIC_REF_COUNT="$(wc -l < "$DYNAMIC_REF_COUNT_FILE" | tr -d ' ')"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ ! -s "$RAW_HITS" ]; then
  jq -n \
    --arg generatedAt "$GENERATED_AT" \
    --arg description "アイコン参照を検出しなかった(0件)" \
    --argjson dynamicRefCount "$DYNAMIC_REF_COUNT" \
    '{
      pageKind: "icon-catalog",
      title: "アイコンカタログ",
      generatedAt: $generatedAt,
      description: $description,
      icons: [],
      summary: [
        {label: "アイコン種類数", value: 0},
        {label: "使用箇所数", value: 0},
        {label: "動的参照(追跡不能)", value: $dynamicRefCount}
      ]
    }' > "$OUTPUT_JSON"
  exit 0
fi

# raw-hits.tsv: name \t file \t line \t sourceType(material|svg|react-icons)
# name+sourceType をキーに files を集約して icons[] を構築する
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --argjson dynamicRefCount "$DYNAMIC_REF_COUNT" \
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
    description: ("検出したアイコン参照(種類 " + ($icons | length | tostring) + "・使用箇所 " + ($hits | length | tostring) + "件)"),
    icons: $icons,
    summary: (
      [
        {label: "アイコン種類数", value: ($icons | length)},
        {label: "使用箇所数", value: ($hits | length)}
      ]
      + ($bySource | map({label: .key, value: .value}))
      + [{label: "動的参照(追跡不能)", value: $dynamicRefCount}]
    )
  }
  ' > "$OUTPUT_JSON"
