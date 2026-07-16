#!/usr/bin/env bash
# generating-feature-list-for-reverse-docs: 機能一覧.HTML 決定的生成
#
# Usage: build-feature-list.sh <manifest.json> <output-html-path>
#        build-feature-list.sh --self-test
#
# unit_kind=feature のマニフェストJSONを厳密な契約として扱い、
# shared/templates/unit-list/feature-list-template.html を土台に決定的にHTMLを生成する。
# Claudeによる手作業のプレースホルダ置換は一切行わない(データ混入防止)。
# 設計判断の正本は generating-feature-list-for-reverse-docs/SKILL.md の「## 設計判断」にある。
#
# 入力JSONスキーマ(契約。unitKind=feature):
# {
#   "generatedAt": "...", "sourceDir": "...", "unitKind": "feature",
#   "strategy": {"extractionMethod": "...", "approvedByUser": true, "unitIdRegex": null, "excludePatterns": []},
#   "detectionSummary": {"unitCount": 0, "unresolvedCount": 0},
#   "units": [{
#     "unitKey": "...", "unitId": null, "unitNameGuess": "...", "kind": "feature|unresolved",
#     "category": "...", "identifier": "...", "sourceFile": "...", "summary": "...",
#     "relatedScreens": [], "relatedApis": [], "relatedTables": [],
#     "confidence": "high|medium|low", "fileCount": 0, "detectionMethod": "..."
#   }]
# }
#
# 出力: <output-html-path> に単一ファイル自己完結のHTMLを書き出す。
#   - kind!=unresolved の units は category(未指定は「未分類」)ごとに大分類セクションへ分けて出力
#   - kind=unresolved は「要手動確認」セクションの別テーブルへ(0件なら「なし」)
#   - manifest.json の内容は <script type="application/json" id="unit-manifest"> にそのまま埋め込む

set -euo pipefail

# --- --self-test モード ---
# render_template()の単一パス置換が、埋め込み値中の他マーカー文字列衝突・
# バックスラッシュ・山括弧を含む自由記述フィールドでも誤爆しないことを検証する。
self_test() {
  local script_path="$0"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local tmp rc=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-feature-list-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src/features"
  cat > "$tmp/src/features/user-list.ts" <<'EOF'
export function userList() {}
EOF

  extract_manifest_json() {
    sed -n '/<script type="application\/json" id="unit-manifest">/,/<\/script>/p' "$1" | sed '1d;$d'
  }

  # --- ケースa: バックスラッシュ(正規表現風 \d+)を含むidentifier ---
  local manifest_a="$tmp/manifest-a.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    --arg identifier '/master/\d+' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: $identifier,
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
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
      echo "  [PASS] ケースa: バックスラッシュ(\\d+)を含むidentifierでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースa: バックスラッシュを含むidentifierで埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースa: 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- ケースb: 山括弧+実マーカー文字列そのものを含むunitNameGuess ---
  local manifest_b="$tmp/manifest-b.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFile "$tmp/src/features/user-list.ts" \
    --arg unitNameGuess '<div>ユーザー一覧</div>{{MANIFEST_JSON}}<!--CATEGORY_SECTIONS-->' \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 1, unresolvedCount: 0},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: $unitNameGuess,
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFile,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_b"

  local out_b="$tmp/out-b.html"
  if bash "$script_path" "$manifest_b" "$out_b" >/dev/null 2>&1; then
    local embedded_b="$tmp/embedded-b.json"
    local expected_b="$tmp/expected-b.json"
    extract_manifest_json "$out_b" | jq -c -S . > "$embedded_b" 2>/dev/null || true
    jq -c -S . "$manifest_b" > "$expected_b"
    if diff -q "$embedded_b" "$expected_b" >/dev/null 2>&1; then
      echo "  [PASS] ケースb: 山括弧+実マーカー文字列衝突を含むunitNameGuessでも埋め込みJSONが原本と完全一致"
    else
      echo "  [FAIL] ケースb: 山括弧+マーカー文字列衝突で埋め込みJSONが原本と不一致(誤爆の疑い)" >&2
      rc=1
    fi
  else
    echo "  [FAIL] ケースb: 生成コマンド自体が失敗した" >&2
    rc=1
  fi

  # --- 回帰確認: 通常マニフェスト(大分類2種・機能2件・unresolved 1件)の可視出力と
  #     validate-manifest.sh --unit-kind feature への影響なし ---
  mkdir -p "$tmp/src/features"
  cat > "$tmp/src/features/inventory-sync.ts" <<'EOF'
export function inventorySync() {}
EOF
  cat > "$tmp/src/features/legacy-batch.ts" <<'EOF'
export function legacyBatch() {}
EOF

  local manifest_normal="$tmp/manifest-normal.json"
  jq -n \
    --arg sourceDir "$tmp/src" \
    --arg sourceFileA "$tmp/src/features/user-list.ts" \
    --arg sourceFileB "$tmp/src/features/inventory-sync.ts" \
    --arg sourceFileC "$tmp/src/features/legacy-batch.ts" \
    '{
      generatedAt: "2026-01-01T00:00:00Z",
      sourceDir: $sourceDir,
      unitKind: "feature",
      strategy: {extractionMethod: "custom", approvedByUser: true, unitIdRegex: null, excludePatterns: []},
      detectionSummary: {unitCount: 3, unresolvedCount: 1},
      units: [
        {
          unitKey: "user-list-view",
          kind: "feature",
          category: "ユーザー管理",
          identifier: "/master/users",
          unitNameGuess: "ユーザー一覧表示",
          summary: "ユーザー一覧を表示する",
          sourceFile: $sourceFileA,
          relatedScreens: ["user-list-screen"],
          relatedApis: ["GET /api/users"],
          relatedTables: ["users"],
          confidence: "high",
          fileCount: 1,
          detectionMethod: "manual"
        },
        {
          unitKey: "inventory-sync-job",
          kind: "feature",
          category: "在庫管理",
          identifier: "/batch/inventory-sync",
          unitNameGuess: "在庫同期バッチ",
          summary: "在庫データを外部システムと同期する",
          sourceFile: $sourceFileB,
          relatedScreens: [],
          relatedApis: ["POST /api/inventory/sync"],
          relatedTables: ["inventory", "inventory_log"],
          confidence: "medium",
          fileCount: 1,
          detectionMethod: "manual"
        },
        {
          unitKey: "unresolved-legacy-batch",
          kind: "unresolved",
          category: "未分類",
          identifier: "/batch/legacy",
          unitNameGuess: "旧バッチ処理(要確認)",
          summary: "用途が不明な旧バッチ",
          sourceFile: $sourceFileC,
          relatedScreens: [],
          relatedApis: [],
          relatedTables: [],
          confidence: "low",
          fileCount: 1,
          detectionMethod: "manual"
        }
      ]
    }' > "$manifest_normal"

  local out_normal="$tmp/out-normal.html"
  local regression_ok=1
  if ! bash "$script_path" "$manifest_normal" "$out_normal" >/dev/null 2>&1; then
    regression_ok=0
  elif ! grep -q '在庫データを外部システムと同期する' "$out_normal"; then
    regression_ok=0
  elif ! grep -q '<td>user-list-screen</td>' "$out_normal"; then
    regression_ok=0
  elif ! bash "$script_dir/validate-manifest.sh" "$manifest_normal" --unit-kind feature >/dev/null 2>&1; then
    regression_ok=0
  fi

  if [ "$regression_ok" -eq 1 ]; then
    echo "  [PASS] 回帰確認: 大分類summary文字列・関連画面セル値が出力されvalidate-manifest.sh --unit-kind featureもPASS"
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

MANIFEST="${1:?Usage: build-feature-list.sh <manifest.json> <output-html-path> [--portal-dir <path>]}"
OUTPUT_HTML="${2:?Usage: build-feature-list.sh <manifest.json> <output-html-path> [--portal-dir <path>]}"
shift 2 || true

PORTAL_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --portal-dir)
      PORTAL_DIR_ARG="${2:-}"
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

if ! "$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST" --unit-kind feature; then
  echo "ERROR: manifestがvalidate-manifest.shの検証に失敗しました。Phase 3の整合検証を先に完了してください" >&2
  exit 1
fi

TEMPLATE="$SCRIPT_DIR/../../templates/unit-list/feature-list-template.html"
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
extraction_method="$(jq -r '.strategy.extractionMethod // ""' "$MANIFEST")"
tile_unit_count="$(jq -r '.detectionSummary.unitCount // 0' "$MANIFEST")"
tile_unresolved_count="$(jq -r '.detectionSummary.unresolvedCount // 0' "$MANIFEST")"

# --- 1機能分の <tr> を生成する ---
# 行データはjqの@tsv+bash readではなく、1行1JSONオブジェクト(jq -c)を個別に
# jq -r抽出する方式を採る。@tsv+IFS=タブのreadはタブがPOSIX上「IFS空白」に
# 分類されるため、unitId等の空フィールドが連続すると先頭の空フィールドが
# 消失し列がずれる(実測済みの既知不具合)。build-screen-list.shのrow_html()と
# 同じ「1行分のJSONを丸ごと受け取りjqで各フィールドを引く」方式に統一する。
row_html() {
  local row="$1"
  local unit_id unit_key unit_name summary related_screens related_apis related_tables
  local confidence detection_method source_file

  unit_id="$(jq -r '.unitId // empty' <<<"$row")"
  [ -z "$unit_id" ] && unit_id="—"
  unit_key="$(jq -r '.unitKey // ""' <<<"$row")"
  unit_name="$(jq -r '.unitNameGuess // ""' <<<"$row")"
  summary="$(jq -r '.summary // ""' <<<"$row")"
  related_screens="$(jq -r '(.relatedScreens // []) | join(", ")' <<<"$row")"
  [ -z "$related_screens" ] && related_screens="—"
  related_apis="$(jq -r '(.relatedApis // []) | join(", ")' <<<"$row")"
  [ -z "$related_apis" ] && related_apis="—"
  related_tables="$(jq -r '(.relatedTables // []) | join(", ")' <<<"$row")"
  [ -z "$related_tables" ] && related_tables="—"
  confidence="$(jq -r '.confidence // ""' <<<"$row")"
  detection_method="$(jq -r '.detectionMethod // ""' <<<"$row")"
  source_file="$(jq -r '.sourceFile // ""' <<<"$row")"

  printf '<tr>\n'
  printf '<td>%s</td>\n' "$(html_escape "$unit_id")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$unit_key")"
  printf '<td>%s</td>\n' "$(html_escape "$unit_name")"
  printf '<td>%s</td>\n' "$(html_escape "$summary")"
  printf '<td>%s</td>\n' "$(html_escape "$related_screens")"
  printf '<td>%s</td>\n' "$(html_escape "$related_apis")"
  printf '<td>%s</td>\n' "$(html_escape "$related_tables")"
  printf '<td><span class="badge %s">%s</span></td>\n' "$(html_escape "$confidence")" "$(html_escape "$confidence")"
  printf '<td>%s</td>\n' "$(html_escape "$detection_method")"
  printf '<td><code>%s</code></td>\n' "$(html_escape "$source_file")"
  printf '</tr>\n'
}

thead_html() {
  cat <<'EOF'
<thead>
<tr>
<th data-key="unitId">機能ID</th><th data-key="unitKey">機能キー</th><th data-key="unitNameGuess">機能名</th>
<th data-key="summary">概要</th><th data-key="relatedScreens">関連画面</th><th data-key="relatedApis">関連API</th>
<th data-key="relatedTables">関連テーブル</th><th data-key="confidence">confidence</th>
<th data-key="detectionMethod">検出方式</th><th data-key="sourceFile">主ファイル</th>
</tr>
</thead>
EOF
}

# --- 大分類の抽出(初出順を保って重複排除。unresolvedは対象外) ---
categories=""
while IFS= read -r cat; do
  [ -z "$cat" ] && continue
  categories="${categories}${cat}"$'\n'
done < <(jq -r '[.units[] | select(.kind != "unresolved") | (.category // "未分類")] | reduce .[] as $c ([]; if index($c) then . else . + [$c] end) | .[]' "$MANIFEST")

category_count=0
category_sections=""
unresolved_rows=""

if [ -n "$categories" ]; then
  while IFS= read -r cat; do
    [ -z "$cat" ] && continue
    category_count=$((category_count + 1))
    cat_esc="$(html_escape "$cat")"

    cat_rows=""
    cat_feature_count=0
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      cat_feature_count=$((cat_feature_count + 1))
      cat_rows="${cat_rows}$(row_html "$row")"
    done < <(jq -c --arg cat "$cat" '.units[] | select(.kind != "unresolved") | select((.category // "未分類") == $cat)' "$MANIFEST")

    category_sections="$(cat <<EOF
${category_sections}<details class="module-group" open>
<summary>${cat_esc}（${cat_feature_count}機能）</summary>
<table class="units">
$(thead_html)
<tbody>
${cat_rows}
</tbody>
</table>
</details>
EOF
)"
  done <<< "$categories"
fi

if [ "$category_count" -eq 0 ]; then
  category_sections='<p class="note">なし</p>'
fi

while IFS= read -r row; do
  [ -z "$row" ] && continue
  unresolved_rows="${unresolved_rows}$(row_html "$row")"
done < <(jq -c '.units[] | select(.kind == "unresolved")' "$MANIFEST")

if [ -z "$unresolved_rows" ]; then
  unresolved_section='<p class="note">なし</p>'
else
  unresolved_section="$(cat <<EOF
<table class="units" id="unresolved-table">
$(thead_html)
<tbody>
${unresolved_rows}
</tbody>
</table>
EOF
)"
fi

unit_manifest_json="$(cat "$MANIFEST")"

# --- ポータルへの相対パス算出(--portal-dir 未指定時は無効リンク"#") ---
if [ -n "$PORTAL_DIR_ARG" ]; then
  portal_relative="$(python3 -c "import os; print(os.path.relpath('$PORTAL_DIR_ARG', '$(dirname "$OUTPUT_HTML")'))" 2>/dev/null || echo "..")/index.html"
else
  portal_relative="#"
fi

# --- テンプレートへの注入(単一パス方式。render_template()参照) ---
# マニフェストJSONのマーカーはテンプレート内で物理的に最後に出現するため、
# 単一パスのdocument-order走査により自動的に最後に処理される
# (JSON内容に他マーカー文字列が偶然含まれた場合の誤爆を避けるため)
render_args=(
  "{{GENERATED_AT}}" "$(html_escape "$generated_at")"
  "{{SOURCE_DIR}}" "$(html_escape "$source_dir")"
  "{{EXTRACTION_METHOD}}" "$(html_escape "$extraction_method")"
  "{{CATEGORY_COUNT}}" "$category_count"
  "{{UNIT_COUNT}}" "$tile_unit_count"
  "{{UNRESOLVED_COUNT}}" "$tile_unresolved_count"
  "<!--CATEGORY_SECTIONS-->" "$category_sections"
  "<!--UNRESOLVED_SECTION-->" "$unresolved_section"
  "{{PORTAL_RELATIVE}}" "$portal_relative"
  "{{MANIFEST_JSON}}" "$unit_manifest_json"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
out="$(render_template "$(cat "$TEMPLATE")" "${render_args[@]}")"

printf '%s\n' "$out" > "$OUTPUT_HTML"

echo "OK: wrote $OUTPUT_HTML" >&2
