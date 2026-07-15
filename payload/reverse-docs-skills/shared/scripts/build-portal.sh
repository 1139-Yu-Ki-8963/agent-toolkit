#!/usr/bin/env bash
set -euo pipefail

# build-portal.sh — リバース設計ポータルを生成する
#
# Usage:
#   bash shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
#
# 処理:
#   1. 対象リポジトリのコード行数・ファイル数を計測（FE/BE分離）
#   2. 各種別の一覧HTMLから件数を抽出
#   3. 共通文書リストを収集
#   4. METRICS_JSON / CATEGORIES_JSON を組み立て
#   5. テンプレートのプレースホルダを置換して出力

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/portal-template.html"

source "$SCRIPT_DIR/render-template.sh"

# --- 引数チェック ---
if [ $# -lt 3 ]; then
  echo "Usage: $0 <target_repo_path> <docs_root> <portal_output_dir>" >&2
  exit 1
fi

TARGET_REPO="$1"
DOCS_ROOT="$2"
PORTAL_DIR="$3"

if [ ! -d "$TARGET_REPO" ]; then
  echo "ERROR: target_repo_path does not exist: $TARGET_REPO" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$TARGET_REPO")"
GENERATED_DATE="$(date +%Y-%m-%d)"

# --- 1. コード行数・ファイル数計測 ---
count_lines() {
  local dir="$1"
  local pattern="$2"
  find "$dir" \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
              -o -name '*.py' -o -name '*.sql' -o -name '*.vue' -o -name '*.svelte' \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.next/*' \
    -not -path '*/coverage/*' \
    2>/dev/null | \
  if [ -n "$pattern" ]; then
    grep -E "$pattern"
  else
    cat
  fi | \
  xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}'
}

count_files() {
  local dir="$1"
  local pattern="$2"
  find "$dir" \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
              -o -name '*.py' -o -name '*.sql' -o -name '*.vue' -o -name '*.svelte' \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.next/*' \
    -not -path '*/coverage/*' \
    2>/dev/null | \
  if [ -n "$pattern" ]; then
    grep -E "$pattern"
  else
    cat
  fi | \
  wc -l | awk '{print $1}'
}

FE_PATTERN='/(frontend|src/pages|src/components|src/app)/'
BE_PATTERN='/(backend|api|server)/'

total_lines="$(count_lines "$TARGET_REPO" "")"
fe_lines="$(count_lines "$TARGET_REPO" "$FE_PATTERN")"
be_lines="$(count_lines "$TARGET_REPO" "$BE_PATTERN")"
total_files="$(count_files "$TARGET_REPO" "")"
fe_files="$(count_files "$TARGET_REPO" "$FE_PATTERN")"
be_files="$(count_files "$TARGET_REPO" "$BE_PATTERN")"

[ -z "$total_lines" ] && total_lines=0
[ -z "$fe_lines" ] && fe_lines=0
[ -z "$be_lines" ] && be_lines=0
[ -z "$total_files" ] && total_files=0
[ -z "$fe_files" ] && fe_files=0
[ -z "$be_files" ] && be_files=0

format_number() {
  printf "%'d" "$1" 2>/dev/null || printf "%d" "$1"
}

# --- 2. 一覧件数の抽出 ---
declare -A KIND_LABELS=(
  [screen]="画面"
  [api]="API"
  [batch]="バッチ"
  [table]="テーブル"
  [report]="帳票"
  [external]="外部連携"
)

declare -A KIND_DIRS=(
  [screen]="画面一覧"
  [api]="API一覧"
  [batch]="バッチ一覧"
  [table]="テーブル一覧"
  [report]="帳票一覧"
  [external]="外部連携一覧"
)

declare -A KIND_ICONS=(
  [screen]="monitor"
  [api]="api"
  [batch]="schedule"
  [table]="table_chart"
  [report]="print"
  [external]="link"
)

declare -A KIND_DESCS=(
  [screen]="全画面のルートパス・コンポーネント構成・複雑度プロファイルを一覧化。"
  [api]="全エンドポイントのパス・HTTPメソッド・リクエスト/レスポンス型・認証要否を網羅。"
  [batch]="定期実行ジョブのスケジュール・入出力・依存関係・実行頻度を整理。"
  [table]="全テーブルのカラム定義・型・制約・外部キーリレーションを一覧化。"
  [report]="出力帳票のフォーマット・生成条件・出力先・利用者を整理。"
  [external]="外部サービスとの連携インターフェース・プロトコル・認証方式を整理。"
)

declare -A KIND_UNITS=(
  [screen]="画面"
  [api]="エンドポイント"
  [batch]="ジョブ"
  [table]="テーブル"
  [report]="帳票"
  [external]="連携先"
)

excluded_kinds=""
excluded_json="$DOCS_ROOT/一覧/excluded-kinds.json"
if [ -f "$excluded_json" ]; then
  excluded_kinds="$(jq -r '.[]' "$excluded_json" 2>/dev/null || true)"
fi

is_excluded() {
  local kind="$1"
  echo "$excluded_kinds" | grep -qx "$kind" 2>/dev/null
}

docs_relative=""
if [ -d "$DOCS_ROOT" ]; then
  docs_relative="$(python3 -c "import os; print(os.path.relpath('$DOCS_ROOT', '$PORTAL_DIR'))" 2>/dev/null || echo "../docs")"
fi

KINDS_ORDER="screen api batch table report external"

list_tools_json=""
for kind in $KINDS_ORDER; do
  if is_excluded "$kind"; then
    continue
  fi

  label="${KIND_LABELS[$kind]}"
  dir_name="${KIND_DIRS[$kind]}"
  icon="${KIND_ICONS[$kind]}"
  desc="${KIND_DESCS[$kind]}"
  unit="${KIND_UNITS[$kind]}"
  html_file="$DOCS_ROOT/$dir_name/${label}一覧.html"
  unit_count=0

  if [ -f "$html_file" ]; then
    manifest_json="$(sed -n 's/.*<script[^>]*id="unit-manifest"[^>]*type="application\/json"[^>]*>\(.*\)<\/script>.*/\1/p' "$html_file" 2>/dev/null || true)"
    if [ -z "$manifest_json" ]; then
      manifest_json="$(sed -n 's/.*<script[^>]*type="application\/json"[^>]*id="unit-manifest"[^>]*>\(.*\)<\/script>.*/\1/p' "$html_file" 2>/dev/null || true)"
    fi
    if [ -n "$manifest_json" ]; then
      unit_count="$(echo "$manifest_json" | jq -r '.detectionSummary.unitCount // 0' 2>/dev/null || echo 0)"
    fi
  fi

  href="$docs_relative/$dir_name/${label}一覧.html"
  count_text="$unit_count $unit →"

  [ -n "$list_tools_json" ] && list_tools_json="$list_tools_json,"
  list_tools_json="$list_tools_json{\"title\":\"${label}一覧\",\"icon\":\"$icon\",\"href\":\"$href\",\"desc\":\"$desc\",\"count\":\"$count_text\"}"
done

# --- 3. 共通文書リストの収集 ---
common_tools_json=""
common_dir="$DOCS_ROOT/プロジェクト共通"
if [ -d "$common_dir" ]; then
  while IFS= read -r md_file; do
    title="$(head -1 "$md_file" | sed 's/^#\+ *//' 2>/dev/null || true)"
    if [ -z "$title" ]; then
      title="$(basename "$md_file" .md)"
    fi
    rel_href="$docs_relative/プロジェクト共通/$(basename "$md_file")"

    doc_icon="description"
    case "$title" in
      *規約*|*規則*) doc_icon="rule" ;;
      *エラー*) doc_icon="error" ;;
      *状態*|*ステート*) doc_icon="sync" ;;
      *認証*|*認可*|*権限*) doc_icon="lock" ;;
      *API*) doc_icon="api" ;;
      *設計*) doc_icon="architecture" ;;
      *データ*|*DB*) doc_icon="storage" ;;
      *UI*|*画面*) doc_icon="desktop_windows" ;;
      *メッセージ*) doc_icon="chat" ;;
    esac

    [ -n "$common_tools_json" ] && common_tools_json="$common_tools_json,"
    title_escaped="$(echo "$title" | sed 's/"/\\"/g')"
    common_tools_json="$common_tools_json{\"title\":\"$title_escaped\",\"icon\":\"$doc_icon\",\"href\":\"$rel_href\",\"desc\":\"\",\"count\":\"別タブで開く ↗\"}"
  done < <(find "$common_dir" -name '*.md' -type f 2>/dev/null | sort)
fi

# --- 4. JSON 組み立て ---
METRICS_JSON="[{\"icon\":\"code\",\"label\":\"コード行数\",\"value\":\"$(format_number "$total_lines")\",\"unit\":\"行\",\"sub\":\"<b>FE</b> $(format_number "$fe_lines") ／ <b>BE</b> $(format_number "$be_lines")\"\"},{\"icon\":\"folder\",\"label\":\"ファイル数\",\"value\":\"$(format_number "$total_files")\",\"unit\":\"件\",\"sub\":\"<b>FE</b> $(format_number "$fe_files") ／ <b>BE</b> $(format_number "$be_files")\"}"

screen_count=0
api_count=0
table_count=0
for kind in screen api table; do
  label="${KIND_LABELS[$kind]}"
  dir_name="${KIND_DIRS[$kind]}"
  html_file="$DOCS_ROOT/$dir_name/${label}一覧.html"
  if [ -f "$html_file" ]; then
    manifest_json="$(sed -n 's/.*<script[^>]*id="unit-manifest"[^>]*type="application\/json"[^>]*>\(.*\)<\/script>.*/\1/p' "$html_file" 2>/dev/null || true)"
    if [ -z "$manifest_json" ]; then
      manifest_json="$(sed -n 's/.*<script[^>]*type="application\/json"[^>]*id="unit-manifest"[^>]*>\(.*\)<\/script>.*/\1/p' "$html_file" 2>/dev/null || true)"
    fi
    if [ -n "$manifest_json" ]; then
      cnt="$(echo "$manifest_json" | jq -r '.detectionSummary.unitCount // 0' 2>/dev/null || echo 0)"
      case "$kind" in
        screen) screen_count=$cnt ;;
        api) api_count=$cnt ;;
        table) table_count=$cnt ;;
      esac
    fi
  fi
done

METRICS_JSON="$METRICS_JSON,{\"icon\":\"monitor\",\"label\":\"画面\",\"value\":\"$screen_count\",\"unit\":\"\",\"sub\":\"検出済み画面コンポーネント\"}"
METRICS_JSON="$METRICS_JSON,{\"icon\":\"api\",\"label\":\"API\",\"value\":\"$api_count\",\"unit\":\"\",\"sub\":\"エンドポイント\"}"
METRICS_JSON="$METRICS_JSON,{\"icon\":\"table_chart\",\"label\":\"テーブル\",\"value\":\"$table_count\",\"unit\":\"\",\"sub\":\"マイグレーション定義\"}"
METRICS_JSON="$METRICS_JSON]"

common_count=0
if [ -n "$common_tools_json" ]; then
  common_count="$(echo "$common_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
fi
list_count="$(echo "$list_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
[ -z "$list_count" ] && list_count=0

CATEGORIES_JSON="[{\"id\":\"list\",\"title\":\"一覧系資料\",\"icon\":\"list_alt\",\"sub\":\"画面・API・バッチ・テーブル・帳票・外部連携の種別一覧\",\"tools\":[$list_tools_json]}"
if [ "$common_count" -gt 0 ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON,{\"id\":\"common\",\"title\":\"共通文書\",\"icon\":\"library_books\",\"sub\":\"プロジェクト全体に適用される設計方針・規約\",\"tools\":[$common_tools_json]}"
fi
CATEGORIES_JSON="$CATEGORIES_JSON]"

# --- 5. テンプレート置換・出力 ---
mkdir -p "$PORTAL_DIR"

template_content="$(cat "$TEMPLATE")"
output="$(render_template "$template_content" \
  "{{PROJECT_NAME}}" "$PROJECT_NAME" \
  "{{GENERATED_DATE}}" "$GENERATED_DATE" \
  "{{METRICS_JSON}}" "$METRICS_JSON" \
  "{{CATEGORIES_JSON}}" "$CATEGORIES_JSON" \
)"

printf '%s' "$output" > "$PORTAL_DIR/index.html"
echo "OK: wrote $PORTAL_DIR/index.html" >&2
