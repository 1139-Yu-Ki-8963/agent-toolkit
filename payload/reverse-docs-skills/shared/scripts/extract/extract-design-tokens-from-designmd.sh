#!/usr/bin/env bash
# 抽出エンジン(shared/scripts/extract): DESIGN.md からデザイントークンを抽出し、
# デザインシステムページ用の page-data JSON を出力する。
#
# Usage: extract-design-tokens-from-designmd.sh <DESIGN.md> <output.json>
#        extract-design-tokens-from-designmd.sh --self-test
#
# 入力契約:
#   <DESIGN.md>   : shared/templates/リバース検証/プロジェクト共通/DESIGN.md 準拠のファイル。
#                   先頭に YAML frontmatter（`---` で囲まれたブロック）を持つ想定。
#                   frontmatter は colors: / typography: / components: が
#                   2 スペース固定インデントのネストされたキー: 値、
#                   spacing: / rounded: がスカラー値というテンプレート契約に従う
#                   （facts-schema.md と同様、固定インデント前提の awk パーサで読む）。
#   <output.json> : 出力先パス
#
# 出力契約(<output.json>。正本は shared/templates/detail-pages/detail-t8-design-system.html
# 本文コメントの「page-data.json 想定構造」節。validate-page-data.sh のトップレベル必須キー
# (pageKind/generatedAt/title/description)も満たす):
#   {
#     pageKind: "design-system", title: "デザインシステム", generatedAt, description,
#     tokens: {
#       colors:      [{name, hex, usage}],
#       typography:  [{name, fontFamily, description}],
#       spacing:     [{name, value}],   # rounded: も spacing 配列へ合流させる
#       components:  [{name, description}]
#     },
#     summary: [{label, value, note?}]   # 要約タイル(配列。テンプレートJSがforEachで反復する)
#   }
#
# 抽出手順:
#   1. frontmatter が存在する場合:
#      a. colors: / typography: / components: の 2 スペース indent 配下のキー: 値を読む
#      b. spacing: / rounded: のスカラー値を読み、両方 spacing 配列へ合流させる
#      c. usage(colors)/description(typography) は frontmatter に存在しないため、本文の
#         Markdown 表（## Colors / ## Typography、列「トークン名 | 用途 | 実測値の抽出元」）
#         からトークン名で突合して補う（表が無い・該当行が無い場合は空文字とする。fail ではない）
#      d. components: が 0 件の場合は本文「## Components」表（列「共通コンポーネント | 実装済みの視覚原則」）
#         へフォールバックする（それも 0 件なら components: [] のまま）
#   2. frontmatter が存在しない場合:
#      a. 本文から CSS 変数定義を正規表現フォールバック抽出する
#         （`--color-*` → colors / `--font-*` → typography / `--spacing-*` → spacing。usage/description は空文字）
#      b. CSS変数宣言が0件の場合、表形式フォールバックとして「## Colors」「## Typography」「## Spacing」の
#         Markdown 表（列「トークン名 | 実測値 | 用途」の3列。frontmatterケースの表とは列の意味が異なる。
#         frontmatterが無い=値の置き場がfrontmatterに無いため、表の2列目に実測値そのものを書く運用を許容する）
#         から name/value/usage を読む
#   3. components は frontmatter・no-frontmatter を問わず、0 件なら「## Components」表への
#      フォールバックを試みる(共通処理)
#
# frontmatter 該当キー 0 件・フォールバック該当 0 件はいずれも正常系
# (該当カテゴリの配列を [] で出力する。fail ではない)。DESIGN.md 自体が存在しない場合のみ exit 1。
#
# description は抽出結果(カテゴリ別件数)から組み立てる(固定文字列ではない)。

set -euo pipefail

# --- --self-test モード ---
# (a) validate-page-data.sh を全項目PASSで通過すること
# (b) summary がオブジェクトではなく配列で出力されること
# (c) 表形式(frontmatterなし)の合成DESIGN.mdから抽出し、件数が記載件数と一致すること
# (d) 生成したHTML(build-detail-page.sh経由)をNodeのDOMスタブ上で実行し、実行時例外が
#     発生しないこと(summary配列化前は object.forEach が無いためここで例外が再現していた)
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local detail_pages_dir="$script_dir/../detail-pages"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-design-tokens-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  # --- ケースa/b/d共通フィクスチャ: frontmatterありのDESIGN.md ---
  local design_md_fm="$tmp/DESIGN.md"
  cat > "$design_md_fm" <<'EOF'
---
doc_id: design-common
type: design
status: draft
target_screen: _プロジェクト共通
updated: 2026-01-01
colors:
  primary: "#3366FF"
  surface: "#FFFFFF"
typography:
  heading: "24px/1.4 'Noto Sans JP'"
components:
  # 複数画面で共通して使われるコンポーネントの視覚原則をキーで記述する
rounded: "4px"
spacing: "8px"
---

# 共通デザインシステム

## Colors

| トークン名 | 用途 | 実測値の抽出元 |
|---|---|---|
| primary | 主要ボタン・リンク | `src/styles/theme.css` |
| surface | 画面背景 | `src/styles/theme.css` |

## Typography

| トークン名 | 用途 | 実測値の抽出元 |
|---|---|---|
| heading | 画面タイトル | `src/styles/theme.css` |

## Components

| 共通コンポーネント | 実装済みの視覚原則 |
|---|---|
| `Button` | 角丸なし・影はオフセットのみ |
EOF

  local out_json_fm="$tmp/page-data-fm.json"
  bash "$script_path" "$design_md_fm" "$out_json_fm"

  # --- ケースa: validate-page-data.sh 全項目PASS ---
  if bash "$detail_pages_dir/validate-page-data.sh" "$out_json_fm" >/dev/null 2>&1; then
    echo "  [PASS] ケースa: 出力JSONがvalidate-page-data.shを全項目PASSで通過"
  else
    echo "  [FAIL] ケースa: 出力JSONがvalidate-page-data.shをPASSしない" >&2
    bash "$detail_pages_dir/validate-page-data.sh" "$out_json_fm" 2>&1 | sed 's/^/    /' >&2 || true
    rc=1
  fi

  # --- ケースb: summaryが配列であること ---
  local summary_type
  summary_type="$(jq -r '.summary | type' "$out_json_fm")"
  if [ "$summary_type" = "array" ]; then
    echo "  [PASS] ケースb: summaryが配列として出力されている"
  else
    echo "  [FAIL] ケースb: summaryの型が配列ではない(実際: ${summary_type})" >&2
    rc=1
  fi

  # フィールド名の確認(テンプレートが読む名前と型に揃っていること)
  local fields_ok=1
  jq -e '.tokens.colors[0] | has("hex") and has("usage")' "$out_json_fm" >/dev/null 2>&1 || fields_ok=0
  jq -e '.tokens.typography[0] | has("fontFamily") and has("description")' "$out_json_fm" >/dev/null 2>&1 || fields_ok=0
  jq -e '.tokens.components[0] | has("description")' "$out_json_fm" >/dev/null 2>&1 || fields_ok=0
  jq -e 'has("description") and (.description | length) > 0' "$out_json_fm" >/dev/null 2>&1 || fields_ok=0
  if [ "$fields_ok" -eq 1 ]; then
    echo "  [PASS] フィールド名: colors.hex/usage・typography.fontFamily/description・components.description・トップレベルdescriptionが存在"
  else
    echo "  [FAIL] フィールド名: テンプレートが期待するフィールド名に一致しない項目がある" >&2
    rc=1
  fi

  # --- ケースc: 表形式(frontmatterなし)からの抽出、件数一致 ---
  local design_md_table="$tmp/DESIGN-table.md"
  cat > "$design_md_table" <<'EOF'
# 共通デザインシステム(表形式のみ・frontmatterなし)

## Colors

| トークン名 | 実測値 | 用途 |
|---|---|---|
| primary | #3366FF | 主要ボタン |
| surface | #FFFFFF | 画面背景 |
| error | #D92D20 | エラー表示 |

## Typography

| トークン名 | 実測値 | 用途 |
|---|---|---|
| heading | 24px/1.4 | 画面タイトル |
| body | 14px/1.7 | 本文 |

## Spacing

| トークン名 | 実測値 | 用途 |
|---|---|---|
| base | 8px | 基準スペーシング |
EOF

  local out_json_table="$tmp/page-data-table.json"
  bash "$script_path" "$design_md_table" "$out_json_table"
  local n_colors n_typography n_spacing
  n_colors="$(jq '.tokens.colors | length' "$out_json_table")"
  n_typography="$(jq '.tokens.typography | length' "$out_json_table")"
  n_spacing="$(jq '.tokens.spacing | length' "$out_json_table")"
  if [ "$n_colors" = "3" ] && [ "$n_typography" = "2" ] && [ "$n_spacing" = "1" ]; then
    echo "  [PASS] ケースc: 表形式(frontmatterなし)から記載件数どおりに抽出(colors=3,typography=2,spacing=1)"
  else
    echo "  [FAIL] ケースc: 表形式からの抽出件数が記載件数と不一致(colors=${n_colors},typography=${n_typography},spacing=${n_spacing})" >&2
    rc=1
  fi

  # --- ケースe: 日本語の番号付き見出し・日本語列名(1-173)からの記載件数一致 + 判定不能表の計上 ---
  local design_md_ja="$tmp/DESIGN-table-ja.md"
  cat > "$design_md_ja" <<'EOF'
# 共通デザインシステム(表形式のみ・frontmatterなし・日本語番号付き見出し)

### 1. 色

| 色名 | HEXコード | 用途 |
|---|---|---|
| プライマリ | #3366FF | 主要ボタン |
| サーフェス | #FFFFFF | 画面背景 |
| エラー | #D92D20 | エラー表示 |
| 警告 | #F79009 | 警告表示 |

### 2. 書体

| 書体名 | サイズ行間 | 用途 |
|---|---|---|
| 見出し | 24px/1.4 | 画面タイトル |
| 本文 | 14px/1.7 | 本文 |

### 3. 余白

| 余白名 | 値 | 用途 |
|---|---|---|
| 基準 | 8px | 基準スペーシング |

### 4. 附録(カテゴリ判定不能な表)

| 項目 | 説明 |
|---|---|
| 予備 | 対象外表のテスト用 |
EOF

  local out_json_ja="$tmp/page-data-ja.json"
  bash "$script_path" "$design_md_ja" "$out_json_ja"
  local n_colors_ja n_typography_ja n_spacing_ja n_skipped_ja
  n_colors_ja="$(jq '.tokens.colors | length' "$out_json_ja")"
  n_typography_ja="$(jq '.tokens.typography | length' "$out_json_ja")"
  n_spacing_ja="$(jq '.tokens.spacing | length' "$out_json_ja")"
  n_skipped_ja="$(jq '.summary[] | select(.label == "判定できない表") | .value' "$out_json_ja")"
  if [ "$n_colors_ja" = "4" ] && [ "$n_typography_ja" = "2" ] && [ "$n_spacing_ja" = "1" ]; then
    echo "  [PASS] ケースe-1: 日本語番号付き見出し・日本語列名から記載件数どおりに抽出(colors=4,typography=2,spacing=1)"
  else
    echo "  [FAIL] ケースe-1: 日本語見出し・列名からの抽出件数が記載件数と不一致(colors=${n_colors_ja},typography=${n_typography_ja},spacing=${n_spacing_ja})" >&2
    rc=1
  fi
  if [ "$n_skipped_ja" = "1" ]; then
    echo "  [PASS] ケースe-2: カテゴリ判定できない表(附録)の件数(1件)が出力に現れる"
  else
    echo "  [FAIL] ケースe-2: 判定できない表の件数が出力に現れない、または不一致(実際: ${n_skipped_ja})" >&2
    rc=1
  fi

  # --- ケースd: 生成HTMLをNodeのDOMスタブで実行し、実行時例外が発生しないこと ---
  if command -v node >/dev/null 2>&1; then
    local outdir_html="$tmp/out-html"
    if bash "$detail_pages_dir/build-detail-page.sh" "$out_json_fm" "$outdir_html" --page design-system >/dev/null 2>&1; then
      local html_file="$outdir_html/デザインシステム.html"
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
        echo "  [PASS] ケースd: 生成HTMLをNode DOMスタブ上で実行し、実行時例外が発生しない"
      else
        echo "  [FAIL] ケースd: 生成HTMLの実行で例外が発生した" >&2
        sed 's/^/    /' "$tmp/dom-smoke.err" >&2 2>/dev/null || true
        rc=1
      fi
    else
      echo "  [FAIL] ケースd: build-detail-page.shによるHTML生成自体が失敗した" >&2
      rc=1
    fi
  else
    echo "  [SKIP] ケースd: nodeコマンドが見つからないため実行時例外検査を省略" >&2
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
  echo "Usage: $0 <DESIGN.md> <output.json>" >&2
  exit 1
fi

DESIGN_MD="$1"
OUTPUT_JSON="$2"

if [ ! -f "$DESIGN_MD" ]; then
  echo "Error: DESIGN.md not found: $DESIGN_MD" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOKENS_TSV="$TMP_DIR/tokens.tsv"       # category \t name \t value \t role
COMPONENTS_TSV="$TMP_DIR/components.tsv" # name \t desc
FRONTMATTER_TXT="$TMP_DIR/frontmatter.txt"
FM_RAW_TSV="$TMP_DIR/fm-raw.tsv"       # section \t name \t value（frontmatter全キー、未フィルタ）
: > "$TOKENS_TSV"
: > "$COMPONENTS_TSV"
SKIPPED_TABLE_COUNT_FILE="$TMP_DIR/skipped-tables.count"
: > "$SKIPPED_TABLE_COUNT_FILE"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# has_frontmatter: 先頭行が厳密に "---" かどうかで frontmatter の有無を判定する
# ---------------------------------------------------------------------------
FIRST_LINE="$(head -n1 "$DESIGN_MD" || true)"
HAS_FRONTMATTER=0
if [ "$FIRST_LINE" = "---" ]; then
  HAS_FRONTMATTER=1
fi

# ---------------------------------------------------------------------------
# extract_role_map: 本文の Markdown 表（見出し行 $1、例 "## Colors"）から
#   「トークン名 | 用途 | ...」の先頭2列を name\trole として抽出する。
#   ヘッダ行・区切り行(|---|---|)は tail -n +3 で読み飛ばす。
# ---------------------------------------------------------------------------
extract_role_map() {
  local heading="$1"
  awk -v h="$heading" '
    $0 == h { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^\|/ { print }
  ' "$DESIGN_MD" | tail -n +3 | while IFS= read -r row; do
    name="$(printf '%s' "$row" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    role="$(printf '%s' "$row" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$name" ] && continue
    printf '%s\t%s\n' "$name" "$role"
  done
}

# ---------------------------------------------------------------------------
# lookup_role: name\trole の対応表($2)から $1 に一致する role を引く。無ければ空文字。
# ---------------------------------------------------------------------------
lookup_role() {
  local name="$1" map="$2" n r
  while IFS=$'\t' read -r n r; do
    if [ "$n" = "$name" ]; then
      printf '%s' "$r"
      return 0
    fi
  done <<< "$map"
  printf ''
}

# ---------------------------------------------------------------------------
# classify_table_header: 表の直前の見出し行($1)とヘッダ行($2)を合わせた文字列から
#   colors/typography/spacingのいずれかを判定する。固定英語見出し名や番号付けには
#   依存せず、日本語・英語いずれのキーワードでも判定できるようにする。
#   どの語にも一致しない場合は空文字を返す(呼び出し側で「判定できない表」として計上)。
# ---------------------------------------------------------------------------
classify_table_header() {
  local combined="$1 $2"
  if printf '%s' "$combined" | grep -qiE '色|カラー|color|hex'; then
    printf 'colors'
  elif printf '%s' "$combined" | grep -qiE '書体|フォント|font|typo|文字'; then
    printf 'typography'
  elif printf '%s' "$combined" | grep -qiE '余白|スペーシング|spacing|間隔'; then
    printf 'spacing'
  else
    printf ''
  fi
}

# ---------------------------------------------------------------------------
# extract_tables_by_column_name: frontmatterが無いDESIGN.md向けの表形式フォールバック。
#   固定英語見出し名(旧: "## Colors"等との完全一致)には依存せず、本文中の全Markdown表を
#   検出し、各表の直前の見出し行+ヘッダ行(列名)を classify_table_header に渡して
#   カテゴリを判定する。判定できた表は category\tname\tvalue\trole 行を TOKENS_TSV へ
#   追加する。判定できない表は抽出対象外とし、件数を SKIPPED_TABLE_COUNT_FILE へ
#   1行ずつ積み上げる(呼び出し元が行数で件数を数える)。
#   列の意味(name/value/usage)は表内の並び順(1,2,3列目)に従う(列名テキストは
#   カテゴリ判定にのみ使い、値の抽出は位置ベースを維持する)。
# ---------------------------------------------------------------------------
extract_tables_by_column_name() {
  awk '
    /^#/ { last_heading = $0 }
    /^\|/ {
      if (state == 0) { header = $0; state = 1; next }
      if (state == 1) {
        if ($0 ~ /^\|[ :|-]+\|?[ \t]*$/) {
          print "###TABLE###"
          print last_heading
          print header
          print "###ROWS###"
          state = 2
          next
        } else { header = $0; next }
      }
      if (state == 2) { print; next }
    }
    !/^\|/ { if (state) { print "###END###"; state = 0 } }
    END { if (state) print "###END###" }
  ' "$DESIGN_MD" > "$TMP_DIR/tables_raw.txt"

  local line mode=0 heading="" header="" cur_category=""
  while IFS= read -r line; do
    case "$line" in
      "###TABLE###") mode=1; heading=""; header=""; cur_category=""; continue ;;
      "###ROWS###") mode=3; continue ;;
      "###END###") cur_category=""; mode=0; continue ;;
    esac
    if [ "$mode" -eq 1 ]; then
      heading="$line"
      mode=2
      continue
    fi
    if [ "$mode" -eq 2 ]; then
      header="$line"
      cur_category="$(classify_table_header "$heading" "$header")"
      if [ -z "$cur_category" ]; then
        echo x >> "$SKIPPED_TABLE_COUNT_FILE"
      fi
      mode=3
      continue
    fi
    [ -z "$cur_category" ] && continue
    name="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    value="$(printf '%s' "$line" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    usage="$(printf '%s' "$line" | awk -F'|' '{print $4}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$name" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$cur_category" "$name" "$value" "$usage" >> "$TOKENS_TSV"
  done < "$TMP_DIR/tables_raw.txt"
}

# ---------------------------------------------------------------------------
# extract_components_table: 「## Components」表(共通コンポーネント | 実装済みの視覚原則)から
#   COMPONENTS_TSV(name\tdesc)へ追加する。frontmatterの有無を問わない共通処理。
# ---------------------------------------------------------------------------
extract_components_table() {
  awk '
    $0 == "## Components" { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^\|/ { print }
  ' "$DESIGN_MD" | tail -n +3 | while IFS= read -r row; do
    cname="$(printf '%s' "$row" | awk -F'|' '{print $2}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    cdesc="$(printf '%s' "$row" | awk -F'|' '{print $3}' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
    [ -z "$cname" ] && continue
    printf '%s\t%s\n' "$cname" "$cdesc" >> "$COMPONENTS_TSV"
  done
}

if [ "$HAS_FRONTMATTER" -eq 1 ]; then
  # 1行目・2行目の "---" に挟まれた本体を取り出す
  awk 'BEGIN{c=0} /^---[ \t]*$/{c++; if(c==2){exit} else {next}} c==1{print}' "$DESIGN_MD" > "$FRONTMATTER_TXT"

  # frontmatter 固定インデント(2スペース)パーサ。
  #   トップレベル "key:"(値なし) → section 見出し(colors: / typography: / components:)
  #   トップレベル "key: value"   → スカラーキー(spacing: / rounded: 等)。section=name=key
  #   "  key: value"(2スペース)  → section 配下のネストキー
  awk '
    /^[A-Za-z0-9_-]+:[[:space:]]*$/ {
      cursec = $0
      sub(/:[[:space:]]*$/, "", cursec)
      next
    }
    /^[A-Za-z0-9_-]+:/ {
      key = $0
      sub(/:.*/, "", key)
      val = $0
      sub(/^[^:]+:[[:space:]]*/, "", val)
      gsub(/^"|"$/, "", val)
      printf "%s\t%s\t%s\n", key, key, val
      cursec = ""
      next
    }
    /^  [A-Za-z0-9_.-]+:/ {
      if (cursec != "") {
        line = $0
        sub(/^  /, "", line)
        key = line
        sub(/:.*/, "", key)
        val = line
        sub(/^[^:]+:[[:space:]]*/, "", val)
        gsub(/^"|"$/, "", val)
        printf "%s\t%s\t%s\n", cursec, key, val
      }
      next
    }
  ' "$FRONTMATTER_TXT" > "$FM_RAW_TSV" || true

  COLOR_ROLE_MAP="$(extract_role_map "## Colors" || true)"
  TYPOGRAPHY_ROLE_MAP="$(extract_role_map "## Typography" || true)"

  # colors / typography: fm-raw から section 一致行を抽出し role(colorsはusage/typographyはdescription) を突合する
  while IFS=$'\t' read -r section name value; do
    [ "$section" = "colors" ] || continue
    role="$(lookup_role "$name" "$COLOR_ROLE_MAP")"
    printf 'colors\t%s\t%s\t%s\n' "$name" "$value" "$role" >> "$TOKENS_TSV"
  done < "$FM_RAW_TSV"

  while IFS=$'\t' read -r section name value; do
    [ "$section" = "typography" ] || continue
    role="$(lookup_role "$name" "$TYPOGRAPHY_ROLE_MAP")"
    printf 'typography\t%s\t%s\t%s\n' "$name" "$value" "$role" >> "$TOKENS_TSV"
  done < "$FM_RAW_TSV"

  # spacing: spacing: 自体（スカラー or ネスト）と rounded: を合流させる。roleは使わないため空文字のまま
  while IFS=$'\t' read -r section name value; do
    if [ "$section" = "spacing" ] || [ "$section" = "rounded" ]; then
      printf 'spacing\t%s\t%s\t\n' "$name" "$value" >> "$TOKENS_TSV"
    fi
  done < "$FM_RAW_TSV"

  # components: frontmatter 側にキーがあれば name\tdesc として採用
  while IFS=$'\t' read -r section name value; do
    [ "$section" = "components" ] || continue
    printf '%s\t%s\n' "$name" "$value" >> "$COMPONENTS_TSV"
  done < "$FM_RAW_TSV"
else
  # frontmatter 不在: 本文の CSS 変数定義から正規表現フォールバック抽出する(usage/descriptionは空文字)
  extract_css_vars() {
    local prefix="$1" category="$2"
    grep -oE -- "--${prefix}-[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*[^;]+" "$DESIGN_MD" 2>/dev/null | while IFS= read -r decl; do
      varname="$(printf '%s' "$decl" | sed -E 's/[[:space:]]*:.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
      value="$(printf '%s' "$decl" | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]+$//')"
      [ -z "$varname" ] && continue
      printf '%s\t%s\t%s\t\n' "$category" "$varname" "$value" >> "$TOKENS_TSV"
    done
    return 0
  }
  extract_css_vars "color" "colors" || true
  extract_css_vars "font" "typography" || true
  extract_css_vars "spacing" "spacing" || true

  # CSS変数宣言が0件の場合、表形式フォールバック(見出し文字列に依存せず列名でカテゴリ判定)を試みる
  if [ ! -s "$TOKENS_TSV" ]; then
    extract_tables_by_column_name || true
  fi
fi

SKIPPED_TABLE_COUNT="$(wc -l < "$SKIPPED_TABLE_COUNT_FILE" | tr -d ' ')"

# components: frontmatter有無を問わず0件なら「## Components」表へフォールバックする(共通処理)
if [ ! -s "$COMPONENTS_TSV" ]; then
  extract_components_table || true
fi

# ---------------------------------------------------------------------------
# description組み立て(抽出結果の件数から。固定文字列ではない)
# ---------------------------------------------------------------------------
N_COLORS="$(awk -F'\t' '$1=="colors"' "$TOKENS_TSV" | wc -l | tr -d ' ')"
N_TYPOGRAPHY="$(awk -F'\t' '$1=="typography"' "$TOKENS_TSV" | wc -l | tr -d ' ')"
N_SPACING="$(awk -F'\t' '$1=="spacing"' "$TOKENS_TSV" | wc -l | tr -d ' ')"
N_COMPONENTS="$(wc -l < "$COMPONENTS_TSV" | tr -d ' ')"
DESCRIPTION="DESIGN.md から抽出したデザイントークン一覧(Colors ${N_COLORS}件・Typography ${N_TYPOGRAPHY}件・Spacing ${N_SPACING}件・Components ${N_COMPONENTS}件)"

# ---------------------------------------------------------------------------
# 最終 JSON 組み立て
# ---------------------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg description "$DESCRIPTION" \
  --argjson skippedTables "$SKIPPED_TABLE_COUNT" \
  --rawfile tokensRaw "$TOKENS_TSV" \
  --rawfile componentsRaw "$COMPONENTS_TSV" \
  '
  ($tokensRaw
    | rtrimstr("\n")
    | (if length == 0 then [] else split("\n") end)
    | map(select(length > 0) | split("\t") | {category: .[0], name: .[1], value: .[2], role: (.[3] // "")})
  ) as $rows
  |
  ($componentsRaw
    | rtrimstr("\n")
    | (if length == 0 then [] else split("\n") end)
    | map(select(length > 0) | split("\t") | {name: .[0], desc: (.[1] // "")})
  ) as $componentsRows
  |
  ([$rows[] | select(.category == "colors") | {name: .name, hex: .value, usage: .role}]) as $colors
  |
  ([$rows[] | select(.category == "typography") | {name: .name, fontFamily: .value, description: .role}]) as $typography
  |
  ([$rows[] | select(.category == "spacing") | {name: .name, value: .value}]) as $spacing
  |
  ([$componentsRows[] | {name: .name, description: .desc}]) as $components
  |
  {
    pageKind: "design-system",
    title: "デザインシステム",
    generatedAt: $generatedAt,
    description: $description,
    tokens: {
      colors: $colors,
      typography: $typography,
      spacing: $spacing,
      components: $components
    },
    summary: [
      {label: "トークン総数", value: (($colors | length) + ($typography | length) + ($spacing | length) + ($components | length))},
      {label: "Colors", value: ($colors | length)},
      {label: "Typography", value: ($typography | length)},
      {label: "Spacing", value: ($spacing | length)},
      {label: "Components", value: ($components | length)},
      {label: "判定できない表", value: $skippedTables}
    ]
  }
  ' > "$OUTPUT_JSON"
