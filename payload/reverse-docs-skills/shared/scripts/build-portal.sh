#!/usr/bin/env bash
set -euo pipefail

# build-portal.sh — リバース設計ポータルを生成する
#
# Usage:
#   bash shared/scripts/build-portal.sh <target_repo_path> <docs_root> <portal_output_dir>
#
# 処理:
#   1. 対象リポジトリのコード行数・ファイル数を計測（FE/BE分離）
#   2. 各種別の一覧HTMLから件数を抽出（規模側の kinds と一覧カードで共用）
#   3. 共通文書リスト・将来ページ受け口（FUTURE_PAGES）を収集
#   4. METRICS_JSON（構造化: scale/tests/freshness/previous）/ CATEGORIES_JSON を組み立て
#   5. テンプレートのプレースホルダを置換して出力

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/portal-template.html"

source "$SCRIPT_DIR/render-template.sh"

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

  exit 0
fi

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

# --- 2. 一覧件数の抽出（規模側の kinds データもここで同時に収集し重複計測を避ける） ---
declare -A KIND_LABELS=(
  [screen]="画面"
  [api]="API"
  [batch]="バッチ"
  [table]="テーブル"
  [report]="帳票"
  [external]="外部連携"
  [feature]="機能"
)

declare -A KIND_DIRS=(
  [screen]="画面一覧"
  [api]="API一覧"
  [batch]="バッチ一覧"
  [table]="テーブル一覧"
  [report]="帳票一覧"
  [external]="外部連携一覧"
  [feature]="機能一覧"
)

declare -A KIND_ICONS=(
  [screen]="monitor"
  [api]="api"
  [batch]="schedule"
  [table]="table_chart"
  [report]="print"
  [external]="link"
  [feature]="category"
)

declare -A KIND_DESCS=(
  [screen]="全画面のルートパス・コンポーネント構成・複雑度プロファイルを一覧化。"
  [api]="全エンドポイントのパス・HTTPメソッド・リクエスト/レスポンス型・認証要否を網羅。"
  [batch]="定期実行ジョブのスケジュール・入出力・依存関係・実行頻度を整理。"
  [table]="全テーブルのカラム定義・型・制約・外部キーリレーションを一覧化。"
  [report]="出力帳票のフォーマット・生成条件・出力先・利用者を整理。"
  [external]="外部サービスとの連携インターフェース・プロトコル・認証方式を整理。"
  [feature]="画面一覧を入力に導出した機能単位の一覧（派生一覧）。"
)

declare -A KIND_UNITS=(
  [screen]="画面"
  [api]="エンドポイント"
  [batch]="ジョブ"
  [table]="テーブル"
  [report]="帳票"
  [external]="連携先"
  [feature]="機能"
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

KINDS_ORDER="screen api batch table report external feature"

list_tools_json=""
kinds_json="[]"
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

  kinds_json="$(jq -n -c --argjson arr "$kinds_json" --arg kind "$kind" --arg label "$label" --argjson count "$unit_count" --arg unit "$unit" --arg href "$href" \
    '$arr + [{kind:$kind,label:$label,count:$count,unit:$unit,href:$href}]')"
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

# --- 4. 将来ページ受け口（FUTURE_PAGES）: docs_root 直下に該当 HTML が実在する場合のみカード化 ---
declare -A FUTURE_LABELS=(
  [glossary]="用語辞書"
  [techstack]="技術スタック"
  [transition]="画面遷移図"
  [er]="ER図"
  [env]="環境・実行手順"
)
declare -A FUTURE_FILES=(
  [glossary]="用語辞書.html"
  [techstack]="技術スタック.html"
  [transition]="画面遷移図.html"
  [er]="ER図.html"
  [env]="環境実行手順.html"
)
declare -A FUTURE_ICONS=(
  [glossary]="dictionary"
  [techstack]="stacks"
  [transition]="account_tree"
  [er]="schema"
  [env]="terminal"
)
declare -A FUTURE_DESCS=(
  [glossary]="業務用語・技術用語・略語の定義とコード上の対応識別子の対訳。"
  [techstack]="言語・フレームワーク・主要依存パッケージのバージョンと採用箇所の整理。"
  [transition]="画面一覧のルーティング情報から生成する画面遷移マップ。"
  [er]="テーブル一覧の外部キー情報から生成するエンティティ関連図。"
  [env]="ローカル起動手順・必須ツール・ポート割当の整理。"
)
FUTURE_ORDER="glossary techstack transition er env"

future_tools_json=""
for key in $FUTURE_ORDER; do
  label="${FUTURE_LABELS[$key]}"
  file="${FUTURE_FILES[$key]}"
  icon="${FUTURE_ICONS[$key]}"
  desc="${FUTURE_DESCS[$key]}"
  html_file="$DOCS_ROOT/$file"

  if [ -f "$html_file" ]; then
    href="$docs_relative/$file"
    [ -n "$future_tools_json" ] && future_tools_json="$future_tools_json,"
    future_tools_json="$future_tools_json{\"title\":\"$label\",\"icon\":\"$icon\",\"href\":\"$href\",\"desc\":\"$desc\",\"count\":\"詳細を見る ↗\"}"
  fi
done

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

common_count=0
if [ -n "$common_tools_json" ]; then
  common_count="$(echo "$common_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
fi
future_count=0
if [ -n "$future_tools_json" ]; then
  future_count="$(echo "$future_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
fi

CATEGORIES_JSON="[{\"id\":\"list\",\"title\":\"一覧系資料\",\"icon\":\"list_alt\",\"sub\":\"画面・API・バッチ・テーブル・帳票・外部連携・機能の種別一覧\",\"tools\":[$list_tools_json]}"
if [ "$future_count" -gt 0 ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON,{\"id\":\"project\",\"title\":\"プロジェクト基盤情報\",\"icon\":\"domain\",\"sub\":\"プロジェクトの前提を横断的にまとめた資料\",\"tools\":[$future_tools_json]}"
fi
if [ "$common_count" -gt 0 ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON,{\"id\":\"common\",\"title\":\"共通文書\",\"icon\":\"library_books\",\"sub\":\"プロジェクト全体に適用される設計方針・規約\",\"tools\":[$common_tools_json]}"
fi
CATEGORIES_JSON="$CATEGORIES_JSON]"

# --- 7. テンプレート置換・出力 ---
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
