#!/usr/bin/env bash
# detail-pages系(用語辞書/技術スタック/画面遷移図/ER図/環境実行手順)共通ビルダー。
# page-data.json + --page 指定から、対応するテンプレートへ描画したHTMLを固定ファイル名で
# <output-dir> 直下に書き出す。出力ファイル名は build-portal.sh の FUTURE_FILES と同値。
#
# Usage: build-detail-page.sh <page-data.json> <output-dir> --page glossary|techstack|transition|er|env
#        build-detail-page.sh --self-test
#
# page → (テンプレートファイル, 固定出力ファイル名) 対応は本スクリプト内の
# get_page_template/get_page_filename に固定する(build-unit-list.shの--unit-kindクロスチェックと同型)。
# data JSONのpageKindと--pageの不一致、不正なJSON、不正な--page値はexit 1とし、部分出力を残さない。
# validate-page-data.shを内部実行し、PASSしない限り生成しない。
# 出力は<output-dir>内の一時ファイル経由のatomic move(同一ファイルシステム内でmvする)。
#
# 正本スキーマ: shared/scripts/detail-pages/page-data-schema.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

get_page_template() { case "$1" in glossary) echo "detail-t2-dictionary.html";; techstack) echo "detail-t3-attributes.html";; transition) echo "detail-t4-diagram.html";; er) echo "detail-t4-diagram.html";; env) echo "detail-t5-procedure.html";; esac; }
get_page_filename() { case "$1" in glossary) echo "用語辞書.html";; techstack) echo "技術スタック.html";; transition) echo "画面遷移図.html";; er) echo "ER図.html";; env) echo "環境実行手順.html";; esac; }

# --- --self-test モード ---
# (a) バックスラッシュ・実マーカー文字列(\d+・{{PAGE_DATA_JSON}}・<!--DETAIL_TILES-->)を含む
#     フィクスチャで、埋め込みJSON(script#page-data)が入力のjq -S正規化と完全一致することを
#     techstackページで検証する
# (b) 出力HTMLに未解決の{{が残らないことを検証する
# (c) validate-page-dataが正常系PASS/異常系(pageKind不正)FAILを正しく返し、
#     build-detail-page.sh自体もpageKind不一致データをexit 1で拒否することを検証する。
#     加えて、存在しないtoを1本混ぜたtransitionの孤児edgeが、validate-page-data.shの
#     孤児参照検査でFAILし、build-detail-page.sh自体もexit 1で拒否することを検証する
# (d) glossary/transition/er/env の4種別それぞれについて、ファイル名対応(PAGE_FILENAME)・
#     埋め込みJSON完全一致・未解決{{なしを検証する(techstackはケースa/bで検証済み。
#     5種別全てのPASS行が出揃うことを条件とする)
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-detail-page-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  extract_page_data_json() {
    sed -n '/<script type="application\/json" id="page-data">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # --- ケースa/b共通フィクスチャ: バックスラッシュ・マーカー文字列衝突 ---
  local data_a="$tmp/page-data-a.json"
  jq -n \
    --arg note 'GET /api/users/\d+' \
    --arg itemVal '<div>値</div>{{PAGE_DATA_JSON}}<!--DETAIL_TILES-->' \
    '{
      pageKind: "techstack",
      generatedAt: "2026-01-01T00:00:00Z",
      title: "技術スタック",
      description: "self-test用フィクスチャ",
      tiles: [{label: "言語", value: "TypeScript", note: $note}],
      columns: {item: "項目", value: "値", sourceRef: "出所"},
      rows: [{item: $itemVal, value: "5.4", sourceRef: "package.json:1"}]
    }' > "$data_a"

  local outdir_a="$tmp/out-a"
  if bash "$script_path" "$data_a" "$outdir_a" --page techstack >/dev/null 2>&1; then
    local out_html="$outdir_a/技術スタック.html"
    if [ -f "$out_html" ]; then
      local embedded_a="$tmp/embedded-a.json"
      local expected_a="$tmp/expected-a.json"
      extract_page_data_json "$out_html" | jq -c -S . > "$embedded_a" 2>/dev/null || true
      jq -c -S . "$data_a" > "$expected_a"
      if diff -q "$embedded_a" "$expected_a" >/dev/null 2>&1; then
        echo "  [PASS] ケースa: バックスラッシュ・マーカー文字列衝突を含むpage-dataでも埋め込みJSONが原本と完全一致"
      else
        echo "  [FAIL] ケースa: 埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
        rc=1
      fi
      # page-data埋め込みブロック(意図的にマーカー衝突文字列を含む)を除いた範囲でのみ
      # 未解決{{を検査する(埋め込みJSON自体は原本の一部としてケースaで別途完全一致を確認済み)
      local outside_a="$tmp/outside-a.html"
      sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_html" > "$outside_a"
      if grep -qF '{{' "$outside_a"; then
        echo "  [FAIL] ケースb: page-data埋め込み範囲外に未解決の{{が残存" >&2
        rc=1
      else
        echo "  [PASS] ケースb: page-data埋め込み範囲外に未解決の{{が残らない"
      fi
    else
      echo "  [FAIL] ケースa: 出力ファイル ${out_html} が生成されなかった" >&2
      echo "  [FAIL] ケースb: 出力ファイル不在のため判定不能" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗したため判定不能" >&2
    rc=1
  fi

  # --- ケースc: validate-page-dataのPASS/FAIL判定 + build-detail-page.sh自体の拒否確認 ---
  local data_bad="$tmp/page-data-bad.json"
  jq '.pageKind = "unknown-kind"' "$data_a" > "$data_bad"

  if bash "$script_dir/validate-page-data.sh" "$data_a" >/dev/null 2>&1 \
     && ! bash "$script_dir/validate-page-data.sh" "$data_bad" >/dev/null 2>&1; then
    echo "  [PASS] ケースc: validate-page-dataが正常系PASS・異常系(pageKind不正)FAILを正しく返す"
  else
    echo "  [FAIL] ケースc: validate-page-dataのPASS/FAIL判定が期待通りでない" >&2
    rc=1
  fi

  local outdir_bad="$tmp/out-bad"
  if bash "$script_path" "$data_bad" "$outdir_bad" --page techstack >/dev/null 2>&1; then
    echo "  [FAIL] ケースc補: pageKind不正データの生成が誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースc補: pageKind不正データはbuild-detail-page.shでも正しくexit 1"
  fi

  # --- ケースc補2: 孤児edge(存在しないtoを1本混ぜたtransition)がvalidate-page-data.shでFAIL・
  #     build-detail-page.sh自体もexit 1で拒否することを確認 ---
  local data_orphan="$tmp/page-data-orphan.json"
  jq -n '{
    pageKind: "transition",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ(孤児edge混入)",
    legend: [{symbol: "□", meaning: "画面"}],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [
      {from: "home", to: "detail", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high", section: "メインコンテンツ", triggerType: "リンク遷移"},
      {from: "home", to: "ghost", trigger: "存在しない遷移", sourceRef: "src/router.tsx:20", confidence: "low", section: "メインコンテンツ", triggerType: "リンク遷移"}
    ],
    unresolved: []
  }' > "$data_orphan"

  if bash "$script_dir/validate-page-data.sh" "$data_orphan" >/dev/null 2>&1; then
    echo "  [FAIL] ケースc補2: 孤児edge混入データがvalidate-page-data.shで誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースc補2: 孤児edge混入データはvalidate-page-data.shで正しくexit 1"
  fi

  local outdir_orphan="$tmp/out-orphan"
  if bash "$script_path" "$data_orphan" "$outdir_orphan" --page transition >/dev/null 2>&1; then
    echo "  [FAIL] ケースc補2: 孤児edge混入データの生成がbuild-detail-page.shで誤ってPASSした" >&2
    rc=1
  else
    echo "  [PASS] ケースc補2: 孤児edge混入データはbuild-detail-page.shでも正しくexit 1"
  fi

  # --- ケースd: glossary/transition/er/env のファイル名対応・埋め込みJSON一致・未解決{{なし ---
  check_page_fixture() {
    local page="$1" data_file="$2"
    local outdir="$tmp/out-$page"
    local expected_filename="$(get_page_filename "$page")"
    if ! bash "$script_path" "$data_file" "$outdir" --page "$page" >/dev/null 2>&1; then
      echo "  [FAIL] ケースd(${page}): 生成コマンド自体が失敗した" >&2
      rc=1
      return
    fi
    local out_html="$outdir/$expected_filename"
    if [ ! -f "$out_html" ]; then
      echo "  [FAIL] ケースd(${page}): 出力ファイル ${out_html} が生成されなかった(ファイル名対応不一致の疑い)" >&2
      rc=1
      return
    fi
    echo "  [PASS] ケースd(${page}): ファイル名対応(${expected_filename})で出力"

    local embedded expected
    embedded="$tmp/embedded-${page}.json"
    expected="$tmp/expected-${page}.json"
    extract_page_data_json "$out_html" | jq -c -S . > "$embedded" 2>/dev/null || true
    jq -c -S . "$data_file" > "$expected"
    if diff -q "$embedded" "$expected" >/dev/null 2>&1; then
      echo "  [PASS] ケースd(${page}): 埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースd(${page}): 埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi

    local outside="$tmp/outside-${page}.html"
    sed '/<script type="application\/json" id="page-data">/,/<\/script>/d' "$out_html" > "$outside"
    if grep -qF '{{' "$outside"; then
      echo "  [FAIL] ケースd(${page}): page-data埋め込み範囲外に未解決の{{が残存" >&2
      rc=1
    else
      echo "  [PASS] ケースd(${page}): page-data埋め込み範囲外に未解決の{{が残らない"
    fi
  }

  local data_glossary="$tmp/page-data-glossary.json"
  jq -n '{
    pageKind: "glossary",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "用語辞書",
    description: "self-test用フィクスチャ",
    categories: [{key: "business", label: "業務"}, {key: "tech", label: "技術"}],
    terms: [
      {term: "注文", definition: "顧客が商品を購入する行為", codeRefs: ["src/models/order.ts:10"], category: "business", sourceRef: "src/models/order.ts:10"},
      {term: "セッション", definition: "認証状態を保持する仕組み", codeRefs: ["src/auth/session.ts:5"], category: "tech", sourceRef: "src/auth/session.ts:5"}
    ],
    unresolved: []
  }' > "$data_glossary"
  check_page_fixture glossary "$data_glossary"

  local data_transition="$tmp/page-data-transition.json"
  jq -n '{
    pageKind: "transition",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "画面遷移図",
    description: "self-test用フィクスチャ",
    legend: [{symbol: "□", meaning: "画面"}],
    nodes: [{unitKey: "home", label: "ホーム"}, {unitKey: "detail", label: "詳細"}],
    edges: [{from: "home", to: "detail", trigger: "クリック", sourceRef: "src/router.tsx:10", confidence: "high", section: "メインコンテンツ", triggerType: "リンク遷移"}],
    unresolved: [{label: "旧画面(route欠落)", reason: "旧形式manifestのためroute情報なし", sourceRef: "src/legacy/old-screen.tsx"}]
  }' > "$data_transition"
  check_page_fixture transition "$data_transition"

  local data_er="$tmp/page-data-er.json"
  jq -n '{
    pageKind: "er",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "ER図",
    description: "self-test用フィクスチャ",
    legend: [{symbol: "1:N", meaning: "一対多"}],
    entities: [{key: "users", label: "users"}, {key: "orders", label: "orders"}],
    relations: [{from: "users", to: "orders", cardinality: "1:N", sourceRef: "migrations/001_init.sql:12"}],
    unresolved: []
  }' > "$data_er"
  check_page_fixture er "$data_er"

  local data_env="$tmp/page-data-env.json"
  jq -n '{
    pageKind: "env",
    generatedAt: "2026-01-01T00:00:00Z",
    title: "環境実行手順",
    description: "self-test用フィクスチャ",
    prerequisites: [{name: "Node.js", note: "v18以上"}],
    steps: [
      {order: 2, command: "npm run dev", note: "開発サーバー起動"},
      {order: 1, command: "npm install", note: "依存関係インストール"}
    ],
    allocations: [{target: "devサーバー", value: "8000", sourceRef: "アーキテクチャ調査書.md#§3"}],
    unresolved: []
  }' > "$data_env"
  check_page_fixture env "$data_env"

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

DATA="${1:?Usage: build-detail-page.sh <page-data.json> <output-dir> --page glossary|techstack|transition|er|env}"
OUTPUT_DIR="${2:?Usage: build-detail-page.sh <page-data.json> <output-dir> --page glossary|techstack|transition|er|env}"
shift 2 || true

PAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --page)
      PAGE="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PAGE" ] || [ -z "$(get_page_template "$PAGE")" ]; then
  echo "ERROR: --page must be one of: glossary techstack transition er env" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$DATA" ]; then
  echo "ERROR: page-data not found: $DATA" >&2
  exit 1
fi

if ! jq empty "$DATA" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON: $DATA" >&2
  exit 1
fi

DATA_PAGE_KIND="$(jq -r '.pageKind // ""' "$DATA")"
if [ "$DATA_PAGE_KIND" != "$PAGE" ]; then
  echo "ERROR: page-dataのpageKind(${DATA_PAGE_KIND})と--page(${PAGE})が不一致です" >&2
  exit 1
fi

if ! "$SCRIPT_DIR/validate-page-data.sh" "$DATA"; then
  echo "ERROR: page-dataがvalidate-page-data.shの検証に失敗しました" >&2
  exit 1
fi

TEMPLATE_FILE="$(get_page_template "$PAGE")"
TEMPLATE="$SCRIPT_DIR/../../templates/detail-pages/$TEMPLATE_FILE"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

OUTPUT_FILENAME="$(get_page_filename "$PAGE")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILENAME"

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# render_template — 共通関数を source（shared/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"

TITLE="$(jq -r '.title // ""' "$DATA")"
DESCRIPTION="$(jq -r '.description // ""' "$DATA")"
GENERATED_AT="$(jq -r '.generatedAt // ""' "$DATA")"
PAGE_DATA_JSON="$(cat "$DATA")"

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# page-dataのJSONはテンプレート内で物理的に最後に出現するため、単一パスの
# document-order走査により自動的に最後に処理される(JSON内容に他マーカー文字列が
# 偶然含まれた場合の誤爆を避けるため)。
render_args=(
  "{{TITLE}}" "$(html_escape "$TITLE")"
  "{{DESCRIPTION}}" "$(html_escape "$DESCRIPTION")"
  "{{GENERATED_AT}}" "$(html_escape "$GENERATED_AT")"
  "{{COMMIT_SHORT}}" ""
  "{{PAGE_DATA_JSON}}" "$PAGE_DATA_JSON"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

TMP_OUT="$(mktemp "$OUTPUT_DIR/.build-detail-page.XXXXXX")"
printf '%s\n' "$out" > "$TMP_OUT"
mv "$TMP_OUT" "$OUTPUT_PATH"

echo "OK: wrote $OUTPUT_PATH" >&2
