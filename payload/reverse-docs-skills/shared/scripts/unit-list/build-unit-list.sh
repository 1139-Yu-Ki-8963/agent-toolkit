#!/usr/bin/env bash
# 種別別一覧スキル群(generating-<種別>-list-for-reverse-docs)共通エンジン: 種別対応HTML一覧生成ディスパッチャ。
# unit_kind=screen なら build-screen-list.sh に委譲、他種別は汎用テンプレートから生成する。
#
# Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>]
#
# unit_kind=screen の場合:
#   同ディレクトリの build-screen-list.sh に <manifest.json> <output-html-path> をそのまま渡して
#   委譲する。従来の画面一覧.HTML生成と完全に同じ挙動になり、exit codeもそのまま返す。
#
# unit_kind=screen 以外の場合:
#   1. validate-manifest.sh <manifest.json> --unit-kind <kind> で検証(PASSしない限り生成しない)
#   2. shared/templates/unit-list/unit-list-template.html を土台に、jqでマニフェストJSONをパースして
#      プレースホルダ・注入マーカーを機械的に置換し、決定的にHTMLを生成する
#
# 汎用マニフェストの入力JSONスキーマ(契約。詳細は references/kind-detection-strategies.md):
# {
#   "generatedAt": "...", "sourceDir": "...", "unitKind": "api|table|batch|report|external",
#   "strategy": {"extractionMethod": "...", "approvedByUser": true, ...},
#   "detectionSummary": {"method": "...", "unitCount": 0, "unresolvedCount": 0},
#   "units": [{
#     "unitKey": "...", "unitId": null, "unitNameGuess": "...", "kind": "種別固有の区分値",
#     "identifier": "...", "sourceFile": "...", "confidence": "high|medium|low",
#     "fileCount": 0, "files": [], "detectionMethod": "..."
#   }]
# }
#
# 出力: <output-html-path> に単一ファイル自己完結のHTMLを書き出す。
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - manifest.json の内容は <script type="application/json" id="unit-manifest"> にそのまま埋め込む

set -euo pipefail

MANIFEST="${1:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>]}"
OUTPUT_HTML="${2:?Usage: build-unit-list.sh <manifest.json> <output-html-path> [--unit-kind <kind>]}"
shift 2 || true

UNIT_KIND_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unit-kind)
      UNIT_KIND_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$UNIT_KIND_ARG" ]; then
  UNIT_KIND="$UNIT_KIND_ARG"
else
  UNIT_KIND="$(jq -r '.unitKind // "screen"' "$MANIFEST")"
  [ "$UNIT_KIND" = "null" ] && UNIT_KIND="screen"
fi

# --- unit_kind=screen: build-screen-list.sh に委譲(exit codeをそのまま返す) ---
if [ "$UNIT_KIND" = "screen" ]; then
  "$SCRIPT_DIR/build-screen-list.sh" "$MANIFEST" "$OUTPUT_HTML"
  exit $?
fi

# --- unit_kind=screen 以外: 検証してから汎用テンプレートで生成 ---
if ! "$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST" --unit-kind "$UNIT_KIND"; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

case "$UNIT_KIND" in
  screen) LABEL="画面" ;;
  api) LABEL="API" ;;
  table) LABEL="テーブル" ;;
  batch) LABEL="バッチ" ;;
  report) LABEL="帳票" ;;
  external) LABEL="外部連携" ;;
  *) echo "ERROR: unknown unit_kind: $UNIT_KIND" >&2; exit 1 ;;
esac

TEMPLATE="$SCRIPT_DIR/../../templates/unit-list/unit-list-template.html"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- HTMLエスケープ(& < > のみ。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

label_esc="$(html_escape "$LABEL")"

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
extraction_method="$(jq -r '.strategy.extractionMethod // ""' "$MANIFEST")"
tile_unit_count="$(jq -r '.detectionSummary.unitCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

# --- 1ユニット分の <tr> を生成する ---
# 行データはjqの@tsv+bash readではなく、1行1JSONオブジェクト(jq -c)を個別に
# jq -r抽出する方式を採る。@tsv+IFS=タブのreadはタブがPOSIX上「IFS空白」に
# 分類されるため、unitId等の空フィールドが連続すると先頭の空フィールドが
# 消失し列がずれる(実測済みの既知不具合)。build-screen-list.shのrow_html()と
# 同じ「1行分のJSONを丸ごと受け取りjqで各フィールドを引く」方式に統一する。
row_html() {
  local row="$1"
  local unit_id unit_key kind unit_name identifier detection_method confidence file_count source_file
  local kind_class kind_label

  unit_id="$(jq -r '.unitId // empty' <<<"$row")"
  [ -z "$unit_id" ] && unit_id="—"
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  kind="$(jq -r '.kind // ""' <<<"$row")"
  unit_name="$(jq -r '.unitNameGuess // ""' <<<"$row")"
  identifier="$(jq -r '.identifier // ""' <<<"$row")"
  detection_method="$(jq -r '.detectionMethod // ""' <<<"$row")"
  confidence="$(jq -r '.confidence // ""' <<<"$row")"
  file_count="$(jq -r '.fileCount // 0' <<<"$row")"
  source_file="$(jq -r '.sourceFile // ""' <<<"$row")"

  case "$kind" in
    unresolved) kind_class="kind-unresolved"; kind_label="要確認" ;;
    *)          kind_class="kind-generic";    kind_label="$(html_escape "$kind")" ;;
  esac

  printf '<tr>\n'
  printf '<td>%s</td>\n' "$(html_escape "$unit_id")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$unit_key")"
  printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  printf '<td>%s</td>\n' "$(html_escape "$unit_name")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$identifier")"
  printf '<td>%s</td>\n' "$(html_escape "$detection_method")"
  printf '<td><span class="badge %s">%s</span></td>\n' "$(html_escape "$confidence")" "$(html_escape "$confidence")"
  printf '<td>%s</td>\n' "$(html_escape "$file_count")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$source_file")"
  printf '</tr>\n'
}

unit_rows=""
unresolved_rows=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  row_kind="$(jq -r '.kind // ""' <<<"$row")"
  html="$(row_html "$row")"
  if [ "$row_kind" = "unresolved" ]; then
    unresolved_rows="${unresolved_rows}${html}"
  else
    unit_rows="${unit_rows}${html}"
  fi
done < <(jq -c '.units[]' "$MANIFEST")

if [ -z "$unit_rows" ]; then
  unit_rows='<tr><td colspan="9">なし</td></tr>'
fi

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
else
  unresolved_section="$(cat <<EOF
<table class="units" id="unresolved-table">
<thead>
<tr>
<th>${label_esc}ID</th><th>${label_esc}キー</th><th>区分</th><th>${label_esc}名</th><th>識別子</th>
<th>検出方式</th><th>confidence</th><th>構成ファイル数</th><th>主ファイル</th>
</tr>
</thead>
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
fi

unit_manifest_json="$(cat "$MANIFEST")"

# --- テンプレートへの注入(単純文字列置換。パターン中に glob 特殊文字は無いため安全) ---
out="$(cat "$TEMPLATE")"
out="${out//"{{UNIT_KIND_LABEL}}"/$label_esc}"
out="${out//"{{GENERATED_AT}}"/$(html_escape "$generated_at")}"
out="${out//"{{SOURCE_DIR}}"/$(html_escape "$source_dir")}"
out="${out//"{{EXTRACTION_METHOD}}"/$(html_escape "$extraction_method")}"
out="${out//"{{UNIT_COUNT}}"/$tile_unit_count}"
out="${out//"{{UNRESOLVED_COUNT}}"/$tile_unresolved_count}"
out="${out//"<!--UNIT_TABLE_ROWS-->"/$unit_rows}"
out="${out//"<!--UNRESOLVED_SECTION-->"/$unresolved_section}"
# マニフェストJSONの埋め込みは他マーカーの置換完了後に最後へ回す
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
out="${out//"{{MANIFEST_JSON}}"/$unit_manifest_json}"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
