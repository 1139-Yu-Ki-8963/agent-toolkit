#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not installed" >&2; exit 1; }

# build-portal.sh — 設計ポータルを生成する
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
TOKENS_CSS_FILE="$SCRIPT_DIR/../templates/tokens.css"

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

  echo "--- ケース3: FUTURE_PAGES 実在チェック ---"
  test3_dir="$(mktemp -d)"
  test3_docs="$test3_dir/docs"
  test3_portal="$test3_dir/portal"
  mkdir -p "$test3_docs" "$test3_portal"
  echo '{"total":100,"fe":50,"be":50,"file_count":10}' > "$test3_docs/code-metrics.json"
  echo '<html><body>test glossary</body></html>' > "$test3_docs/用語辞書.html"
  "$SCRIPT_DIR/build-portal.sh" "$test3_dir" "$test3_docs" "$test3_portal" 2>/dev/null
  if grep -q "用語辞書" "$test3_portal/index.html" && grep -q "プロジェクト基盤情報" "$test3_portal/index.html"; then
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
  mkdir -p "$test4_repo" "$test4_docs/プロジェクト共通" "$test4_portal"
  printf '\xEF\xBB\xBF# BOM付き見出し\n本文' > "$test4_docs/プロジェクト共通/bom-test.md"
  printf -- '---\ntitle: frontmatter\n---\n# FM後の見出し\n本文' > "$test4_docs/プロジェクト共通/fm-test.md"
  "$SCRIPT_DIR/build-portal.sh" "$test4_repo" "$test4_docs" "$test4_portal" 2>/dev/null
  bom_ok=0
  fm_ok=0
  grep -q 'BOM付き見出し' "$test4_portal/index.html" 2>/dev/null && bom_ok=1
  grep -q 'FM後の見出し' "$test4_portal/index.html" 2>/dev/null && fm_ok=1
  if [ "$bom_ok" = "1" ] && [ "$fm_ok" = "1" ]; then
    echo "PASS: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出）"
  else
    echo "FAIL: --self-test ケース4（BOM付き・frontmatter付きmdからのタイトル抽出, bom=$bom_ok fm=$fm_ok）" >&2
    rm -rf "$test4_dir"
    exit 1
  fi
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
  if ! grep -q 'test-doc.html' "$test5_portal/index.html"; then
    echo "FAIL: ケース5 — ポータルのリンク先が .html になっていない" >&2; rm -rf "$test5_dir"; exit 1
  fi
  if grep -q 'test-doc\.md"' "$test5_portal/index.html"; then
    echo "FAIL: ケース5 — ポータルにまだ .md リンクが残っている" >&2; rm -rf "$test5_dir"; exit 1
  fi
  echo "PASS: --self-test ケース5（共通文書 .md → .html 変換）"
  rm -rf "$test5_dir"

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
  "units": []
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
  "screens": []
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

  echo "--- ケース9: 交差ビュー・AI設定資産カード（実在時のみ出現、全不在時はセクション非表示） ---"
  test9_dir="$(mktemp -d)"
  test9_repo="$test9_dir/repo"
  test9_docs="$test9_dir/docs"
  test9_portal="$test9_dir/portal"
  mkdir -p "$test9_repo" "$test9_docs/交差ビュー/権限画面マトリクス" "$test9_docs/AI設定資産" "$test9_portal"
  echo '<html><body>perm screen matrix</body></html>' > "$test9_docs/交差ビュー/権限画面マトリクス/権限画面マトリクス.html"
  echo '<html><body>ai assets</body></html>' > "$test9_docs/AI設定資産/AI設定資産.html"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9_docs" "$test9_portal" 2>/dev/null
  if grep -q '権限画面マトリクス' "$test9_portal/index.html" && grep -q 'AI設定資産' "$test9_portal/index.html" \
     && ! grep -q '権限機能マトリクス' "$test9_portal/index.html"; then
    echo "PASS: --self-test ケース9a（実在ページのみカード出現）"
  else
    echo "FAIL: --self-test ケース9a（実在ページのみカード出現）" >&2
    rm -rf "$test9_dir"
    exit 1
  fi
  # 全不在ケース: 交差ビュー・AI設定資産のセクション自体が出ない
  test9b_docs="$test9_dir/docs-empty"
  test9b_portal="$test9_dir/portal-empty"
  mkdir -p "$test9b_docs" "$test9b_portal"
  "$SCRIPT_DIR/build-portal.sh" "$test9_repo" "$test9b_docs" "$test9b_portal" 2>/dev/null
  if ! grep -q '"id":"cross"' "$test9b_portal/index.html" && ! grep -q '"id":"ai"' "$test9b_portal/index.html"; then
    echo "PASS: --self-test ケース9b（全不在時はセクション非表示）"
  else
    echo "FAIL: --self-test ケース9b（全不在時はセクション非表示）" >&2
    rm -rf "$test9_dir"
    exit 1
  fi
  rm -rf "$test9_dir"

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

# --- 2. 一覧件数の抽出（規模側の kinds データもここで同時に収集し重複計測を避ける） ---
get_kind_label() { case "$1" in screen) echo "画面";; api) echo "API";; batch) echo "バッチ";; table) echo "テーブル";; report) echo "帳票";; external) echo "外部連携";; feature) echo "機能";; esac; }
get_kind_dir() { case "$1" in screen) echo "画面一覧";; api) echo "API一覧";; batch) echo "バッチ一覧";; table) echo "テーブル一覧";; report) echo "帳票一覧";; external) echo "外部連携一覧";; feature) echo "機能一覧";; esac; }
get_kind_icon() { case "$1" in screen) echo "monitor";; api) echo "api";; batch) echo "schedule";; table) echo "table_chart";; report) echo "print";; external) echo "link";; feature) echo "category";; esac; }
get_kind_desc() { case "$1" in screen) echo "全画面のルートパス・コンポーネント構成・複雑度プロファイルを一覧化。";; api) echo "全エンドポイントのパス・HTTPメソッド・リクエスト/レスポンス型・認証要否を網羅。";; batch) echo "定期実行ジョブのスケジュール・入出力・依存関係・実行頻度を整理。";; table) echo "全テーブルのカラム定義・型・制約・外部キーリレーションを一覧化。";; report) echo "出力帳票のフォーマット・生成条件・出力先・利用者を整理。";; external) echo "外部サービスとの連携インターフェース・プロトコル・認証方式を整理。";; feature) echo "画面一覧を入力に導出した機能単位の一覧（派生一覧）。";; esac; }
get_kind_unit() { case "$1" in screen) echo "画面";; api) echo "エンドポイント";; batch) echo "ジョブ";; table) echo "テーブル";; report) echo "帳票";; external) echo "連携先";; feature) echo "機能";; esac; }
get_kind_group() { case "$1" in screen) echo "画面";; api) echo "API";; batch) echo "バッチ";; table) echo "データ";; report) echo "帳票";; external) echo "外部連携";; feature) echo "機能";; esac; }

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

  label="$(get_kind_label "$kind")"
  dir_name="$(get_kind_dir "$kind")"
  icon="$(get_kind_icon "$kind")"
  desc="$(get_kind_desc "$kind")"
  unit="$(get_kind_unit "$kind")"
  group="$(get_kind_group "$kind")"
  html_file="$DOCS_ROOT/一覧/$dir_name/${label}一覧.html"
  unit_count=0

  if [ -f "$html_file" ]; then
    # 画面一覧は screen-manifest、他種別は unit-manifest
    if [ "$kind" = "screen" ]; then
      manifest_id="screen-manifest"
      count_field="screenCount"
    else
      manifest_id="unit-manifest"
      count_field="unitCount"
    fi
    # 複数行 JSON 対応: awk で script タグ間の内容を抽出（コメント内の誤マッチ防止のため type 属性も要求）
    manifest_json="$(awk -v id="$manifest_id" '
      /type="application\/json"/ && /id="'"$manifest_id"'"/ { found=1; sub(/.*>/, ""); if (/<\/script>/) { sub(/<\/script>.*/, ""); print; found=0; next } }
      found && /<\/script>/ { sub(/<\/script>.*/, ""); print; found=0; next }
      found { print }
    ' "$html_file" 2>/dev/null || true)"
    if [ -n "$manifest_json" ]; then
      unit_count="$(echo "$manifest_json" | jq -r ".detectionSummary.$count_field // 0" 2>/dev/null || echo 0)"
    fi
  fi

  href="$docs_relative/一覧/$dir_name/${label}一覧.html"
  count_text="$unit_count $unit →"

  [ -n "$list_tools_json" ] && list_tools_json="$list_tools_json,"
  list_tools_json="$list_tools_json{\"title\":\"${label}一覧\",\"group\":\"$group\",\"icon\":\"$icon\",\"href\":\"$href\",\"desc\":\"$desc\",\"count\":\"$count_text\"}"

  kinds_json="$(jq -n -c --argjson arr "$kinds_json" --arg kind "$kind" --arg label "$label" --argjson count "$unit_count" --arg unit "$unit" --arg href "$href" \
    '$arr + [{kind:$kind,label:$label,count:$count,unit:$unit,href:$href}]')"

  if [ "$kind" = "screen" ]; then
    transition_file="$DOCS_ROOT/画面遷移図.html"
    if [ -f "$transition_file" ]; then
      transition_href="$docs_relative/画面遷移図.html"
      [ -n "$list_tools_json" ] && list_tools_json="$list_tools_json,"
      list_tools_json="$list_tools_json{\"title\":\"画面遷移図\",\"group\":\"画面\",\"icon\":\"account_tree\",\"href\":\"$transition_href\",\"desc\":\"画面一覧とコード走査から生成する画面遷移マップ。\",\"count\":\"詳細を見る\"}"
    fi
  fi

  if [ "$kind" = "table" ]; then
    er_file="$DOCS_ROOT/ER図.html"
    if [ -f "$er_file" ]; then
      er_href="$docs_relative/ER図.html"
      [ -n "$list_tools_json" ] && list_tools_json="$list_tools_json,"
      list_tools_json="$list_tools_json{\"title\":\"ER図\",\"group\":\"データ\",\"icon\":\"schema\",\"href\":\"$er_href\",\"desc\":\"テーブル一覧と外部キー定義から生成するエンティティ関連図。\",\"count\":\"詳細を見る\"}"
    fi
  fi
done

# --- 3. 共通文書リストの収集 ---
common_tools_json=""
common_dir="$DOCS_ROOT/プロジェクト共通"
COMMON_DOC_TEMPLATE_FILE="$SCRIPT_DIR/../templates/common-doc-template.html"

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

if [ -d "$common_dir" ]; then
  while IFS= read -r md_file; do
    title="$(sed -e '1s/^\xEF\xBB\xBF//' "$md_file" | grep -m1 '^#' | sed 's/^#\+ *//' 2>/dev/null || true)"
    if [ -z "$title" ]; then
      title="$(basename "$md_file" .md)"
    fi

    # .md → .html 変換
    html_basename="$(basename "$md_file" .md).html"
    html_file="$(dirname "$md_file")/$html_basename"
    if [ -f "$COMMON_DOC_TEMPLATE_FILE" ]; then
      md_content="$(sed -e '1s/^\xEF\xBB\xBF//' "$md_file" | awk 'NR==1 && /^---$/ {skip=1; next} skip && /^---$/ {skip=0; next} !skip')"
      local_render_args=(
        "{{PROJECT_NAME}}" "$PROJECT_NAME"
        "{{DOC_TITLE}}" "$(html_escape "$title")"
        "{{GENERATED_DATE}}" "$GENERATED_DATE"
        "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
      )
      if [ -f "$TOKENS_CSS_FILE" ]; then
        local_render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
      fi
      local_render_args+=("{{DOC_MARKDOWN}}" "$md_content")
      doc_html="$(render_template "$(cat "$COMMON_DOC_TEMPLATE_FILE")" "${local_render_args[@]}")"
      printf '%s\n' "$doc_html" > "$html_file"
    fi

    rel_href="$docs_relative/プロジェクト共通/$html_basename"

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
    common_tools_json="$common_tools_json{\"title\":\"$title_escaped\",\"icon\":\"$doc_icon\",\"href\":\"$rel_href\",\"desc\":\"\",\"count\":\"詳細を見る\"}"
  done < <(find "$common_dir" -name '*.md' -type f 2>/dev/null | sort)
fi

# --- 4. 将来ページ受け口（FUTURE_PAGES）: docs_root 直下に該当 HTML が実在する場合のみカード化 ---
get_future_label() { case "$1" in glossary) echo "用語辞書";; techstack) echo "技術スタック";; transition) echo "画面遷移図";; er) echo "ER図";; env) echo "環境構築手順";; esac; }
get_future_file() { case "$1" in glossary) echo "用語辞書.html";; techstack) echo "技術スタック.html";; transition) echo "画面遷移図.html";; er) echo "ER図.html";; env) echo "環境構築手順.html";; esac; }
get_future_icon() { case "$1" in glossary) echo "dictionary";; techstack) echo "stacks";; transition) echo "account_tree";; er) echo "schema";; env) echo "terminal";; esac; }
get_future_desc() { case "$1" in glossary) echo "業務用語・技術用語・略語の定義とコード上の対応識別子の対訳。";; techstack) echo "言語・フレームワーク・主要依存パッケージのバージョンと採用箇所の整理。";; transition) echo "画面一覧とコード走査から生成する画面遷移マップ。";; er) echo "テーブル一覧と外部キー定義から生成するエンティティ関連図。";; env) echo "環境構築・必須ツール・ポート割当の整理。";; esac; }
FUTURE_ORDER="techstack env glossary"

future_tools_json=""
for key in $FUTURE_ORDER; do
  label="$(get_future_label "$key")"
  file="$(get_future_file "$key")"
  icon="$(get_future_icon "$key")"
  desc="$(get_future_desc "$key")"
  html_file="$DOCS_ROOT/$file"

  if [ -f "$html_file" ]; then
    href="$docs_relative/$file"
    [ -n "$future_tools_json" ] && future_tools_json="$future_tools_json,"
    future_tools_json="$future_tools_json{\"title\":\"$label\",\"icon\":\"$icon\",\"href\":\"$href\",\"desc\":\"$desc\",\"count\":\"詳細を見る\"}"
  fi
done

# --- 4b. 交差ビュー 4 ページ: docs_root/交差ビュー/<名前>/<名前>.html が実在する場合のみカード化 ---
get_cross_label() { case "$1" in permscreen) echo "権限画面マトリクス";; permfeature) echo "権限機能マトリクス";; crud) echo "CRUD図";; trace) echo "追跡可能性";; esac; }
get_cross_icon() { case "$1" in permscreen) echo "lock";; permfeature) echo "key";; crud) echo "grid_on";; trace) echo "route";; esac; }
get_cross_desc() { case "$1" in permscreen) echo "ロール×画面の行×列で閲覧可否の関係を示すマトリクス。";; permfeature) echo "ロール×機能の行×列で操作可否（CRUD）の関係を示すマトリクス。";; crud) echo "機能×テーブルの行×列でCRUD操作の関係を示すマトリクス。";; trace) echo "画面-API-テーブルの対応連鎖を行×列で追跡する対応表。";; esac; }
CROSS_ORDER="permscreen permfeature crud trace"

cross_tools_json=""
for key in $CROSS_ORDER; do
  label="$(get_cross_label "$key")"
  icon="$(get_cross_icon "$key")"
  desc="$(get_cross_desc "$key")"
  html_file="$DOCS_ROOT/交差ビュー/$label/$label.html"

  if [ -f "$html_file" ]; then
    href="$docs_relative/交差ビュー/$label/$label.html"
    [ -n "$cross_tools_json" ] && cross_tools_json="$cross_tools_json,"
    cross_tools_json="$cross_tools_json{\"title\":\"$label\",\"icon\":\"$icon\",\"href\":\"$href\",\"desc\":\"$desc\",\"count\":\"詳細を見る\"}"
  fi
done

# --- 4c. AI設定資産ページ: docs_root/AI設定資産/AI設定資産.html が実在する場合のみカード化 ---
ai_tools_json=""
ai_html_file="$DOCS_ROOT/AI設定資産/AI設定資産.html"
if [ -f "$ai_html_file" ]; then
  ai_href="$docs_relative/AI設定資産/AI設定資産.html"
  ai_tools_json="{\"title\":\"AI設定資産\",\"icon\":\"smart_toy\",\"href\":\"$ai_href\",\"desc\":\"rules・skills・サブエージェント・hooks の設定資産の俯瞰。\",\"count\":\"詳細を見る\"}"
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

common_count=0
if [ -n "$common_tools_json" ]; then
  common_count="$(echo "$common_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
fi
future_count=0
if [ -n "$future_tools_json" ]; then
  future_count="$(echo "$future_tools_json" | grep -o '{' | wc -l | awk '{print $1}')"
fi

CATEGORIES_JSON="["
if [ "$future_count" -gt 0 ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON{\"id\":\"project\",\"title\":\"プロジェクト基盤情報\",\"icon\":\"domain\",\"sub\":\"プロジェクトの前提を横断的にまとめた資料\",\"tools\":[$future_tools_json]},"
fi
if [ "$common_count" -gt 0 ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON{\"id\":\"common\",\"title\":\"プロジェクト規約\",\"icon\":\"library_books\",\"sub\":\"プロジェクト全体に適用される設計方針・規約\",\"tools\":[$common_tools_json]},"
fi
CATEGORIES_JSON="$CATEGORIES_JSON{\"id\":\"list\",\"title\":\"一覧・設計図\",\"icon\":\"list_alt\",\"sub\":\"画面・API・テーブル等の種別一覧と、画面遷移図・ER図\",\"tools\":[$list_tools_json]}"
if [ -n "$cross_tools_json" ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON,{\"id\":\"cross\",\"title\":\"交差ビュー\",\"icon\":\"grid_view\",\"sub\":\"画面・機能・テーブル・権限の関係を行×列で示すマトリクス\",\"tools\":[$cross_tools_json]}"
fi
if [ -n "$ai_tools_json" ]; then
  CATEGORIES_JSON="$CATEGORIES_JSON,{\"id\":\"ai\",\"title\":\"AI設定資産\",\"icon\":\"smart_toy\",\"sub\":\"rules・skills・サブエージェント・hooks の設定を俯瞰する資料\",\"tools\":[$ai_tools_json]}"
fi
CATEGORIES_JSON="$CATEGORIES_JSON]"

# --- 7. テンプレート置換・出力 ---
mkdir -p "$PORTAL_DIR"

template_content="$(cat "$TEMPLATE")"
render_args=(
  "{{PROJECT_NAME}}" "$PROJECT_NAME"
  "{{GENERATED_DATE}}" "$GENERATED_DATE"
  "{{COMMIT_SHORT}}" "$COMMIT_SHORT"
  "{{METRICS_JSON}}" "$METRICS_JSON"
  "{{CATEGORIES_JSON}}" "$CATEGORIES_JSON"
)
# トークンCSS注入（tokens.css が存在する場合のみ）
if [ -f "$TOKENS_CSS_FILE" ]; then
  render_args+=("/* TOKENS_CSS */" "$(cat "$TOKENS_CSS_FILE")")
fi
output="$(render_template "$template_content" "${render_args[@]}")"

printf '%s' "$output" > "$PORTAL_DIR/index.html"
echo "OK: wrote $PORTAL_DIR/index.html" >&2
