#!/usr/bin/env bash
# generating-screen-list-for-reverse-docs: Phase 4 画面一覧.HTML 決定的生成
#
# Usage: build-screen-list.sh <manifest.json> <output-html-path>
#
# detect-screens.sh (および整合検証フェーズ) が出力するマニフェストJSONを
# 厳密な契約として扱い、shared/templates/unit-list/screen-list-template.html を土台に決定的にHTMLを
# 生成する。Claudeによる手作業のプレースホルダ置換は一切行わない(データ混入防止)。
#
# 入力JSONスキーマ(契約):
# {
#   "generatedAt": "...", "sourceDir": "...",
#   "strategy": {"screenIdRegex": "...またはnull", "viewSwitchPattern": "...またはnull"},
#   "detectionSummary": {
#     "method": "...", "screenCount": 0, "clusterCount": 0,
#     "sharedScreenCount": 0, "embeddedCandidateCount": 0, "unresolvedCount": 0
#   },
#   "screens": [{
#     "screenKey": "...", "screenId": null, "kind": "route|embedded-view|unresolved",
#     "screenNameGuess": "...", "route": "...", "detectionMethod": "...",
#     "confidence": "high|medium|low",
#     "entryFile": "...", "fileCount": 0, "files": [],
#     "sharedWith": [], "clusterId": null, "embeddedIn": null, "routeDupCount": 1,
#     "screenType": "list|detail|form|confirm|complete|error|top|processing_endpoint|unknown",
#     "accountGroup": "user|admin|editor|report|feature_phone|unknown",
#     "accountSubType": "common", "hasTemplate": true, "parentScreen": null,
#     "childComponents": [], "isProcessingEndpoint": false
#   }]
# }
#
# 出力: <output-html-path> に単一ファイル自己完結のHTMLを書き出す。
#   - kind=route / kind=embedded-view は通常テーブルへ
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - screen-manifest.json の内容は <script type="application/json"> にそのまま埋め込む

## 設計判断
##
## **必要性**: 画面一覧.HTMLの生成をClaudeによる手作業のプレースホルダ置換から
## スクリプトによる決定的生成に置き換える。手作業組み立てはentryFile=None等の
## データ混入・列ズレ・JSONエスケープ漏れを起こしやすく、実際に発生した。
## jqによるJSONパース・11列テーブルのHTMLエスケープ・kind別振り分け・
## sharedWith集計・routeDupCount注記という複数の決定的処理をひとまとまりの
## スクリプトに固定することで、生成物を再現可能かつレビュー可能にする。
##
## **代替案を採用しなかった理由**:
## - Bash ツール直叩き(Claudeが都度プレースホルダ置換): 本タスクの発端そのもの。
##   手作業組み立てによるデータ混入(entryFile=None等)を根絶する目的で本スクリプトが必要
## - 既存 Makefile ターゲット拡張: 本スキルはリポジトリ非依存で任意プロジェクトの
##   ソースを探索するため、対象プロジェクトのMakefileに依存させられない
## - package.json scripts 追加: 同上。対象プロジェクトがNode.js製とは限らない
##
## **保守責任者**: 人手（ユーザー）。マニフェストJSONスキーマ変更時に同時更新する
##
## **廃棄条件**: generating-screen-list-for-reverse-docs スキルが廃止された時、
## またはHTML生成が別基盤（テンプレートエンジン等）へ移行した時

set -euo pipefail

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-screen-list-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/screens"
  cat > "$tmp/src/screens/Home.tsx" <<'EOF'
export function Home() { return null; }
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="screen-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # --- ケースa: バックスラッシュ(正規表現風 \d+)を含む detectionMethod ---
  local manifest_a="$tmp/manifest-a.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    --arg detectionMethod 'route-regex:/home/\d+' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: $detectionMethod,
          confidence: "high"
        }
      ]
    }' > "$manifest_a"

  local out_a="$tmp/out-a.html"
  if bash "$script_path" "$manifest_a" "$out_a" >/dev/null 2>&1; then
    local embedded_a="$tmp/embedded-a.json"
    local expected_a="$tmp/expected-a.json"
    extract_manifest_json "$out_a" | jq -c -S . > "$embedded_a" 2>/dev/null || true
    jq -c -S . "$manifest_a" > "$expected_a"
    if diff -q "$embedded_a" "$expected_a" >/dev/null 2>&1; then
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むdetectionMethodでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むdetectionMethodで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- ケースb: 山括弧+実マーカー文字列そのものを含む diagnostics ---
  local manifest_b="$tmp/manifest-b.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    --arg diag '<span>要確認</span>{{GENERATED_AT}}<!--SCREEN_MANIFEST_JSON-->' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high"
        }
      ],
      diagnostics: [$diag]
    }' > "$manifest_b"

  local out_b="$tmp/out-b.html"
  if bash "$script_path" "$manifest_b" "$out_b" >/dev/null 2>&1; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    jq -c -S . "$manifest_b" > "$expected_b"
    if diff -q "$embedded_b" "$expected_b" >/dev/null 2>&1; then
      echo "  [PASS] ケースb: 山括弧+実マーカー文字列衝突を含むdiagnosticsでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 回帰確認: 通常マニフェストの可視テーブル出力と machine gate(validate-manifest.sh)への影響なし ---
  local manifest_normal="$tmp/manifest-normal.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg entryFile "$tmp/src/screens/Home.tsx" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      strategy: {extractionMethod: "custom", approvedByUser: true, screenIdRegex: null, excludePatterns: []},
      detectionSummary: {screenCount: 1, clusterCount: 0, sharedScreenCount: 0, embeddedCandidateCount: 0, unresolvedCount: 0},
      screens: [
        {
          screenKey: "home-screen",
          kind: "route",
          route: "/home",
          entryFile: $entryFile,
          detectionMethod: "manual",
          confidence: "high"
        }
      ]
    }' > "$manifest_normal"

  local out_normal="$tmp/out-normal.html"
  local regression_ok=1
  if ! bash "$script_path" "$manifest_normal" "$out_normal" >/dev/null 2>&1; then
    regression_ok=0
  elif ! grep -q '<code>/home</code>' "$out_normal"; then
    regression_ok=0
  elif ! bash "$script_dir/validate-manifest.sh" "$manifest_normal" >/dev/null 2>&1; then
    regression_ok=0
  fi

  if [ "$regression_ok" -eq 1 ]; then
    echo "  [PASS] 回帰確認: 可視テーブル内容は維持されvalidate-manifest.shも引き続きPASS"
  else
    echo "  [FAIL] 回帰確認: 可視テーブル内容またはvalidate-manifest.shのPASSに退行が発生した" >&2
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

MANIFEST="${1:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>]}"
OUTPUT_HTML="${2:?Usage: build-screen-list.sh <manifest.json> <output-html-path> [--portal-dir <path>] [--project-name <name>]}"
shift 2 || true

PORTAL_DIR_ARG=""
PROJECT_NAME_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --portal-dir)
      PORTAL_DIR_ARG="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME_ARG="${2:-}"
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

if ! "$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST"; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

TEMPLATE="$SCRIPT_DIR/../../templates/unit-list/screen-list-template.html"
TOKENS_CSS_FILE="$SCRIPT_DIR/../../templates/tokens.css"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_HTML")"

# --- HTMLエスケープ(& < > のみ。& を最初に処理する) ---
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# render_template — 共通関数を source（shared/scripts/render-template.sh）
source "$(cd "$(dirname "$0")/.." && pwd)/render-template.sh"

# --- メタ情報・サマリ集計をマニフェストから抽出 ---
generated_at="$(jq -r '.generatedAt // ""' "$MANIFEST")"
source_dir="$(jq -r '.sourceDir // ""' "$MANIFEST")"
# 表示用: 絶対パスはマシン固有パスの漏洩防止でbasenameに丸め、相対パスはそのまま表示する
case "$source_dir" in
  /*) source_dir_display="$(basename "$source_dir")" ;;
  *)  source_dir_display="$source_dir" ;;
esac
extraction_method="$(jq -r '.strategy.extractionMethod // ""' "$MANIFEST")"
detection_method="$(jq -r '.detectionSummary.method // ""' "$MANIFEST")"
tile_screen_count="$(jq -r '.detectionSummary.screenCount // 0' "$MANIFEST")"
tile_cluster_count="$(jq -r '.detectionSummary.clusterCount // 0' "$MANIFEST")"
tile_shared_screen_count="$(jq -r '.detectionSummary.sharedScreenCount // 0' "$MANIFEST")"
tile_embedded_count="$(jq -r '.detectionSummary.embeddedCandidateCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

# --- sharedWithキー -> {screenId, route} の逆引きテーブル(manifest全体から1回だけ構築) ---
shared_lookup_json="$(jq -c '
  [ .screens[]? | {key: (.screenKey // ""), screenId: (.screenId // null), route: (.route // "")} ]
  | map({(.key): {screenId: .screenId, route: .route}}) | add // {}
' "$MANIFEST")"

# --- 1画面分の <tr> を生成する ---
row_html() {
  local row="$1"
  local screen_id screen_key kind screen_name route detection_method_row confidence
  local file_count entry_file route_dup_count shared_count shared_text
  local dup_note kind_class kind_label embedded_in embedded_text shared_mode shared_detail

  screen_id="$(jq -r '.screenId // empty' <<<"$row")"
  [ -z "$screen_id" ] && screen_id="—"
  screen_key="$(jq -r '.screenKey // ""' <<<"$row")"
  kind="$(jq -r '.kind // ""' <<<"$row")"
  screen_name="$(jq -r '.screenNameGuess // ""' <<<"$row")"
  route="$(jq -r '.route // ""' <<<"$row")"
  detection_method_row="$(jq -r '.detectionMethod // ""' <<<"$row")"
  confidence="$(jq -r '.confidence // ""' <<<"$row")"
  file_count="$(jq -r '.fileCount // 0' <<<"$row")"
  entry_file="$(jq -r '.entryFile // ""' <<<"$row")"
  route_dup_count="$(jq -r '.routeDupCount // 1' <<<"$row")"
  shared_count="$(jq -r '(.sharedWith // []) | length' <<<"$row")"
  embedded_in="$(jq -r '
    (.embeddedIn // "") as $e
    | if ($e | type) == "array" then ($e | map(tostring) | join(", "))
      elif ($e | type) == "string" then $e
      else "" end
  ' <<<"$row")"

  # --- 共有列: sharedWithの各キーをmanifestから引き、screenId(なければキー):routeの
  #     詳細を優先表示する。全メンバーがscreenId欠落の場合のみ「N件: キー一覧」にフォールバック ---
  if [ "$shared_count" -eq 0 ]; then
    shared_text="—"
  else
    shared_mode="$(jq -r --argjson lookup "$shared_lookup_json" '
      (.sharedWith // []) as $sw
      | ($sw | map($lookup[.].screenId) | map(select(. != null)) | length) as $with_id
      | if $with_id > 0 then "detail" else "fallback" end
    ' <<<"$row")"
    if [ "$shared_mode" = "detail" ]; then
      shared_detail="$(jq -r --argjson lookup "$shared_lookup_json" '
        (.sharedWith // []) as $sw
        | $sw | map(
            ($lookup[.] // {"screenId":null,"route":null}) as $m
            | ((if $m.screenId != null then $m.screenId else . end) + ": " + ($m.route // ""))
          ) | join(", ")
      ' <<<"$row")"
      shared_text="$(html_escape "$shared_detail")"
    else
      shared_text="${shared_count}件: $(html_escape "$(jq -r '(.sharedWith // []) | join(", ")' <<<"$row")")"
    fi
  fi

  # 埋め込み元・親画面列: embeddedIn が非空なら kind を問わず表示する。
  # kind=="embedded-view" に限定しない理由: 独立ルートを持ちつつ他画面からも
  # 呼ばれる二重の性質の画面(kind=route で embeddedIn を持つ)で親が空欄になるため。
  # embeddedIn は「値があれば表示」という普遍的な表示ルールで扱う(kindは表示可否の判断材料にしない)。
  # この制限は過去に繰り返し再導入されたため、変更しないこと。route画面で embeddedIn が
  # null/空の通常ケースは $embedded_in が空になり「—」表示のままで挙動は変わらない。
  if [ -n "$embedded_in" ]; then
    embedded_text="<code>$(html_escape "$embedded_in")</code>"
  else
    embedded_text="—"
  fi

  dup_note=""
  if [ "$route_dup_count" -gt 1 ]; then
    dup_note="<span class=\"dup-note\">route定義${route_dup_count}箇所</span>"
  fi

  case "$kind" in
    route)          kind_class="kind-route";      kind_label="ルート" ;;
    embedded-view)   kind_class="kind-embedded";   kind_label="埋め込みビュー" ;;
    unresolved)      kind_class="kind-unresolved"; kind_label="要確認" ;;
    *)               kind_class="kind-unresolved"; kind_label="$(html_escape "$kind")" ;;
  esac

  printf '<tr>\n'
  printf '<td>%s</td>\n' "$(html_escape "$screen_id")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$screen_key")"
  printf '<td><span class="badge %s">%s</span></td>\n' "$kind_class" "$kind_label"
  printf '<td>%s</td>\n' "$(html_escape "$screen_name")"
  if [ -n "$route" ]; then
    printf '<td><code>%s</code>%s</td>\n' "$(html_escape "$route")" "$dup_note"
  else
    printf '<td>—%s</td>\n' "$dup_note"
  fi
  printf '<td>%s</td>\n' "$(html_escape "$detection_method_row")"
  # badge CSSクラス(.badge.high等)は小文字定義のため、confidence値の大文字小文字に依らずクラスは小文字化する
  printf '<td><span class="badge %s">%s</span></td>\n' "$(html_escape "$(printf '%s' "$confidence" | tr '[:upper:]' '[:lower:]')")" "$(html_escape "$confidence")"
  printf '<td>%s</td>\n' "$shared_text"
  printf '<td>%s</td>\n' "$embedded_text"
  printf '<td>%s</td>\n' "$(html_escape "$file_count")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$entry_file")"
  printf '</tr>\n'
}

screen_rows=""
unresolved_rows=""
while IFS= read -r row; do
  [ -z "$row" ] && continue
  row_kind="$(jq -r '.kind // ""' <<<"$row")"
  html="$(row_html "$row")"
  if [ "$row_kind" = "unresolved" ]; then
    unresolved_rows="${unresolved_rows}${html}"
  else
    screen_rows="${screen_rows}${html}"
  fi
done < <(jq -c '.screens[]' "$MANIFEST")

if [ -z "$screen_rows" ]; then
  screen_rows='<tr><td colspan="11">なし</td></tr>'
fi

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
else
  unresolved_section="$(cat <<EOF
<table class="screens" id="unresolved-table">
<thead>
<tr>
<th>画面ID</th><th>画面キー</th><th>区分</th><th>画面名</th><th>ルート</th>
<th>検出方式</th><th>confidence</th><th>共有</th><th>埋め込み元</th><th>構成ファイル数</th><th>主ファイル</th>
</tr>
</thead>
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
fi

# --- diagnostics(警告)一覧をHTML断片へ整形。空なら何も出力しない ---
diag_items=""
while IFS= read -r diag; do
  [ -z "$diag" ] && continue
  diag_items="${diag_items}<li>$(html_escape "$diag")</li>"
done < <(jq -r '(.diagnostics // [])[]' "$MANIFEST")

if [ -z "$diag_items" ]; then
  diagnostics_html=""
else
  diagnostics_html="<div class=\"diag-warn\"><strong>診断・警告</strong><ul>${diag_items}</ul></div>"
fi

screen_manifest_json="$(cat "$MANIFEST")"

# --- ポータルへの相対パス算出(--portal-dir 未指定時は正本レイアウトの既定値) ---
# 正本レイアウト: <docs_root>/index.html と <docs_root>/一覧/<種別>一覧/<種別>一覧.html。
# 一覧HTMLから見たポータルは2階層上のため、未指定時は ../../index.html を既定とする。
if [ -n "$PORTAL_DIR_ARG" ]; then
  portal_relative="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$(dirname "$OUTPUT_HTML")'))" 2>/dev/null || echo "..")/index.html"
else
  portal_relative="../../index.html"
fi

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# マニフェストJSONのマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=(
  "{{PROJECT_NAME}}" "$(html_escape "$PROJECT_NAME_ARG")"
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{SOURCE_DIR}}" "$(html_escape "$source_dir_display")"
  "{{EXTRACTION_METHOD}}" "$(html_escape "$extraction_method")"
  "{{DETECTION_METHOD}}" "$(html_escape "$detection_method")"
  "{{TILE_SCREEN_COUNT}}" "$tile_screen_count"
  "{{TILE_CLUSTER_COUNT}}" "$tile_cluster_count"
  "{{TILE_SHARED_SCREEN_COUNT}}" "$tile_shared_screen_count"
  "{{TILE_EMBEDDED_COUNT}}" "$tile_embedded_count"
  "{{TILE_UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "<!--SCREEN_TABLE_ROWS-->" "$screen_rows"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "<!--DIAGNOSTICS-->" "$diagnostics_html"
  "{{PORTAL_RELATIVE}}" "$portal_relative"
  "<!--SCREEN_MANIFEST_JSON-->" "$screen_manifest_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
