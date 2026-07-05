#!/usr/bin/env bash
# audit-consistency.sh — Phase 2 の機械チェック / 実装契約章のファイル一覧取得
#
# 用途:
#   通常モード: 画面詳細設計書.md の内部整合性を機械的にチェックする。
#     (a) 機能一覧章の機能キー集合と、frontmatter の unit_test_sheet /
#         integration_test_sheet が指す観点表の機能キー集合の突合（両方向一致）
#     (b) 未記入プレースホルダ `<...>` の検出（HTML コメント内は除外）
#     (c) 連番キー検出（意味キー規約違反の WARN）
#     (d) 結合テスト観点表「## 往復検証観点表」の対応失敗クラス網羅チェック（WARN）
#   --list-contract-files モード: 実装契約章の「ファイル分割」表 1 列目のパス一覧を
#     stdout に 1 行 1 パスで出力する（rebuilding Phase 3 の白紙化対象取得用）。
#
# 章の特定は章番号の直書きではなく「## 章マップ」表の役割キー列から解決する
# （役割キー → §番号 の 2 段解決）。章マップ・役割キー列・該当行のいずれかが
# 欠落している場合は暗黙フォールバックせず明示 exit 1 とする。
#
# 引数:
#   $1 = 画面ディレクトリ（画面詳細設計書.md を含むディレクトリ）
#   または: --list-contract-files <画面ディレクトリ>
#
# 終了コード:
#   通常モード: 違反あり(a,b) = 1 / WARN のみ(c,d) = 0 / 正常 = 0
#   --list-contract-files: 取得成功 = 0 / 取得不可 = 1
#
# 使い方:
#   ./audit-consistency.sh <画面ディレクトリ>
#   ./audit-consistency.sh --list-contract-files <画面ディレクトリ>

set -euo pipefail

LIST_CONTRACT_MODE=0
if [ "${1:-}" = "--list-contract-files" ]; then
  LIST_CONTRACT_MODE=1
  SCREEN_DIR="${2:-}"
else
  SCREEN_DIR="${1:-}"
fi

if [ -z "$SCREEN_DIR" ]; then
  echo "使い方: $0 <画面ディレクトリ> | $0 --list-contract-files <画面ディレクトリ>" >&2
  exit 1
fi
if [ ! -d "$SCREEN_DIR" ]; then
  echo "エラー: ディレクトリが存在しません: $SCREEN_DIR" >&2
  exit 1
fi

# 設計書の特定: 画面詳細設計書.md を第一候補とし、無ければ frontmatter に
# `type: screen-detail-design` を持つ .md を探す。観点表にも doc_id があるため
# 「doc_id を含む最初の .md」では観点表を誤選択しうる（実証済みバグ）。
DESIGN_DOC=""
if [ -f "$SCREEN_DIR/画面詳細設計書.md" ]; then
  DESIGN_DOC="$SCREEN_DIR/画面詳細設計書.md"
else
  for cand in "$SCREEN_DIR"/*.md; do
    if [ -f "$cand" ] && grep -qE '^type: *screen-detail-design *$' "$cand" 2>/dev/null; then
      DESIGN_DOC="$cand"
      break
    fi
  done
fi
if [ -z "$DESIGN_DOC" ]; then
  echo "エラー: 設計書を特定できません（画面詳細設計書.md が無く、type: screen-detail-design を持つ .md も見つかりません）: $SCREEN_DIR" >&2
  exit 1
fi

# --- frontmatter から観点表パスを取得 ---
frontmatter_value() {
  local key="$1"
  awk -v k="$key" '
    /^---$/ { c++; next }
    c==1 && $0 ~ "^"k":" { sub("^"k": *", ""); print; exit }
  ' "$DESIGN_DOC"
}

# BSD realpath（macOS）には -m が無いため、cd + pwd によるポータブルな解決を行う。
# 相対パスの親ディレクトリが存在しない場合は空文字を返す。
resolve_rel_path() {
  local base_dir="$1" rel="$2" rel_dir rel_base abs_dir
  [ -z "$rel" ] && return 1
  rel_dir="$(dirname "$rel")"
  rel_base="$(basename "$rel")"
  if [ -d "$base_dir/$rel_dir" ]; then
    abs_dir="$(cd "$base_dir/$rel_dir" && pwd)"
    printf '%s/%s\n' "$abs_dir" "$rel_base"
    return 0
  fi
  return 1
}

# --- 章マップ解決（役割キー → §番号）---

# 指定ファイル内で見出し行 $2（正規表現）にマッチした行の次の行から、
# 次の "^## " 見出し（トップレベル見出し）手前までの本文を出力する。
# 見出し行自体・境界の "## " 行自体は含まない。
extract_heading_body() {
  local file="$1" heading="$2"
  awk -v pat="$heading" '
    $0 ~ pat { in_sec=1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$file"
}

# テーブル本文（extract_heading_body の出力等）から指定列（1始まり）の値を
# 抽出する。構造的ヘッダー処理: テーブル 1 行目（ヘッダー行）は無条件スキップ、
# 2 行目が区切り行 `^\|[ \t:|\-]+$` に一致すればスキップする。ラベル文字列に
# 依存した除外（"キー" 等の名指し）は行わない。
extract_table_column() {
  local text="$1" col="$2"
  printf '%s\n' "$text" | awk -v col="$col" '
    BEGIN { row=0 }
    /^\|/ {
      row++
      if (row == 1) next
      if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
      n = split($0, cols, "|")
      v = cols[col+1]
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v != "" && v !~ /^-+$/) print v
    }
  '
}

# 「## 章マップ」表が存在し、1 列目のヘッダーが「役割キー」であることを検証する。
# 章マップが無い・表が無い・役割キー列が無い場合は理由を stderr に出し 1 を返す。
validate_chapter_map() {
  if ! grep -qE '^## 章マップ' "$DESIGN_DOC"; then
    echo "エラー: '## 章マップ' セクションが見つかりません: $DESIGN_DOC" >&2
    return 1
  fi
  local header_line header_col1
  header_line="$(extract_heading_body "$DESIGN_DOC" '^## 章マップ' | awk '/^\|/ { print; exit }')"
  if [ -z "$header_line" ]; then
    echo "エラー: '## 章マップ' セクションに表がありません: $DESIGN_DOC" >&2
    return 1
  fi
  header_col1="$(printf '%s' "$header_line" | awk -F'|' '{ v=$2; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }')"
  if [ "$header_col1" != "役割キー" ]; then
    echo "エラー: 章マップ表に役割キー列がありません（1 列目のヘッダーが '役割キー' ではなく '$header_col1' でした）: $DESIGN_DOC" >&2
    return 1
  fi
  return 0
}

# 章マップ表から役割キーに対応する §番号を解決する（見つからなければ空文字）。
# validate_chapter_map による事前検証を前提とする。
# 章マップの § 列は `§2` のように § 記号付きで記述されるのが実テンプレートの
# 正規形だが、`2` のような記号なし表記も許容する。取得した値の先頭の § を
# 正規化のため除去し、残りが数字のみでなければ明示エラーとする
# （extract_design_section_body が `## §${num}` を組み立てるため、
# § を除去せずに渡すと `## §§2` になり全セクション抽出が失敗する）。
resolve_role_section() {
  local role="$1" sec
  sec="$(extract_heading_body "$DESIGN_DOC" '^## 章マップ' | awk -v role="$role" '
    BEGIN { row=0 }
    /^\|/ {
      row++
      if (row == 1) next
      if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
      n = split($0, cols, "|")
      key = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", key)
      val = cols[3]; gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (key == role) { print val; exit }
    }
  ')"
  [ -z "$sec" ] && return 0
  sec="${sec#§}"
  if ! printf '%s' "$sec" | grep -qE '^[0-9]+$'; then
    echo "エラー: 章マップの § 列の値が数字として解釈できません（役割キー '$role': '$sec'）: $DESIGN_DOC" >&2
    return 1
  fi
  printf '%s\n' "$sec"
}

# 章マップで解決した §番号の章本文を抽出する（次の "^## " 見出し手前まで）。
# 番号の直後が数字でないことを要求し、§1 が §10 に誤マッチしないようにする。
extract_design_section_body() {
  local num="$1"
  local pat="^## §${num}([^0-9]|\$)"
  extract_heading_body "$DESIGN_DOC" "$pat"
}

# 観点表ファイルの「## 観点表」セクションから機能キー（1 列目）を抽出する。
# 観点表ファイルにはテストサイズ対応表・本書に書かないもの・観点の導出元マップ等の
# ガイドテーブルが「## 観点表」セクションの前後に存在するため、見出し配下のみを対象にする。
# 「## 観点表」アンカーは維持する。新設される「## 往復検証観点表」セクションは別見出し
# のため extract_heading_body '^## 観点表' では拾われず、本検査 a の対象外となる
# （往復検証観点表は検査 d が別途対象にする）。
extract_sheet_keys() {
  local sheet="$1"
  [ -f "$sheet" ] || return 0
  local body
  body="$(extract_heading_body "$sheet" '^## 観点表')"
  extract_table_column "$body" 1 | sort -u
}

# --- --list-contract-files モード ---
# 実装契約章内の「ファイル分割」表（### 見出しに「ファイル分割」を含む節の表。
# 無ければ実装契約章の最初の表）の 1 列目からファイルパスを抽出し、
# 1 行 1 パスで stdout に出力する。取得不可条件は理由を stderr に出し 1 を返す。
list_contract_files() {
  if ! validate_chapter_map; then
    return 1
  fi

  local secnum body subbody col1 total_count non_placeholder_count
  secnum="$(resolve_role_section "実装契約")"
  if [ -z "$secnum" ]; then
    echo "エラー: 章マップに役割キー '実装契約' の行が見つかりません: $DESIGN_DOC" >&2
    return 1
  fi

  body="$(extract_design_section_body "$secnum")"
  if [ -z "$body" ]; then
    echo "エラー: 実装契約章（§${secnum}）の本文が見つかりません: $DESIGN_DOC" >&2
    return 1
  fi

  subbody="$(printf '%s\n' "$body" | awk '
    /^### / && $0 ~ /ファイル分割/ { insub=1; next }
    /^### / && insub { exit }
    insub { print }
  ')"
  if [ -z "$subbody" ]; then
    subbody="$body"
  fi

  col1="$(extract_table_column "$subbody" 1)"
  total_count=$(printf '%s\n' "$col1" | grep -c . || true)
  if [ "$total_count" -eq 0 ]; then
    echo "エラー: 実装契約章のファイル分割表からファイルパスを抽出できません（表なし/有効行 0）: $DESIGN_DOC" >&2
    return 1
  fi

  non_placeholder_count=$(printf '%s\n' "$col1" | grep -vE '^<.*>$' | grep -c . || true)
  if [ "$non_placeholder_count" -eq 0 ]; then
    echo "エラー: 実装契約章のファイル分割表が全行プレースホルダです: $DESIGN_DOC" >&2
    return 1
  fi

  printf '%s\n' "$col1"
  return 0
}

if [ "$LIST_CONTRACT_MODE" -eq 1 ]; then
  if list_contract_files; then
    exit 0
  else
    exit 1
  fi
fi

echo "対象設計書: $DESIGN_DOC"
VIOLATIONS=0
WARNINGS=0

UNIT_SHEET_REL="$(frontmatter_value unit_test_sheet)"
INTEG_SHEET_REL="$(frontmatter_value integration_test_sheet)"
UNIT_SHEET="$(resolve_rel_path "$SCREEN_DIR" "$UNIT_SHEET_REL" || true)"
INTEG_SHEET="$(resolve_rel_path "$SCREEN_DIR" "$INTEG_SHEET_REL" || true)"

# operation_test_spec は任意キー（L5 操作シーケンス突合が無い画面には存在しない）。
# frontmatter のインライン `# 任意。...` コメントを除去してからパス解決する。
OPTEST_SPEC_REL="$(frontmatter_value operation_test_spec)"
OPTEST_SPEC_REL="$(printf '%s' "$OPTEST_SPEC_REL" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
OPTEST_SPEC="$(resolve_rel_path "$SCREEN_DIR" "$OPTEST_SPEC_REL" || true)"

# --- (a) 機能一覧章 × 観点表 の機能キー集合突合（両方向一致） ---
echo ""
echo "[検査 a] 機能一覧章 × 観点表 の機能キーの集合突合（両方向一致）"

if ! validate_chapter_map; then
  exit 1
fi

FUNC_SECNUM="$(resolve_role_section "機能一覧")"
if [ -z "$FUNC_SECNUM" ]; then
  echo "  エラー: 章マップに役割キー '機能一覧' の行が見つかりません: $DESIGN_DOC" >&2
  exit 1
fi

FUNC_SECTION_BODY="$(extract_design_section_body "$FUNC_SECNUM")"
FUNC_KEYS=$(extract_table_column "$FUNC_SECTION_BODY" 1 | sort -u)
FUNC_COUNT=$(printf '%s\n' "$FUNC_KEYS" | grep -c . || true)
echo "  機能一覧章（§${FUNC_SECNUM}）の機能キー数: $FUNC_COUNT"

UNIT_KEYS=""
INTEG_KEYS=""

if [ -f "$UNIT_SHEET" ]; then
  UNIT_KEYS="$(extract_sheet_keys "$UNIT_SHEET")"
  UNIT_COUNT=$(printf '%s\n' "$UNIT_KEYS" | grep -c . || true)
  echo "  単体テスト観点表 ($UNIT_SHEET_REL) のキー行数: $UNIT_COUNT"
else
  echo "  WARN: 単体テスト観点表が見つかりません ($UNIT_SHEET_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
fi

if [ -f "$INTEG_SHEET" ]; then
  INTEG_KEYS="$(extract_sheet_keys "$INTEG_SHEET")"
  INTEG_COUNT=$(printf '%s\n' "$INTEG_KEYS" | grep -c . || true)
  echo "  結合テスト観点表 ($INTEG_SHEET_REL) のキー行数: $INTEG_COUNT"
else
  echo "  WARN: 結合テスト観点表が見つかりません ($INTEG_SHEET_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
fi

if [ "$FUNC_COUNT" -eq 0 ]; then
  echo "  違反: 機能一覧章にキーが 1 件もありません" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# --- 機能キーと観点表キーの実突合 ---
# 観点表が単体/結合の 2 枚構成でも、機能一覧章の各機能キーが「少なくとも一方」の
# 観点表に出現すればよい（単純な総数比較は 2 枚構成で必ずずれるため行わない）。
# 逆に観点表側にしか無いキーは機能一覧の記載漏れとして違反にする。
if [ -f "$UNIT_SHEET" ] || [ -f "$INTEG_SHEET" ]; then
  ALL_SHEET_KEYS="$(printf '%s\n%s\n' "$UNIT_KEYS" "$INTEG_KEYS" | grep . | sort -u || true)"
  FUNC_KEYS_NONEMPTY="$(printf '%s\n' "$FUNC_KEYS" | grep . || true)"
  MISSING_IN_SHEETS="$(comm -23 <(printf '%s\n' "$FUNC_KEYS_NONEMPTY") <(printf '%s\n' "$ALL_SHEET_KEYS") || true)"
  EXTRA_IN_SHEETS="$(comm -13 <(printf '%s\n' "$FUNC_KEYS_NONEMPTY") <(printf '%s\n' "$ALL_SHEET_KEYS") || true)"

  if [ -n "$MISSING_IN_SHEETS" ]; then
    echo "  違反: 観点表未整備のキー（機能一覧章にあるが単体/結合いずれの観点表にも無い）:" >&2
    printf '%s\n' "$MISSING_IN_SHEETS" | sed 's/^/    - /' >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [ -n "$EXTRA_IN_SHEETS" ]; then
    echo "  違反: 機能一覧の記載漏れ（観点表にあるが機能一覧章に無いキー）:" >&2
    printf '%s\n' "$EXTRA_IN_SHEETS" | sed 's/^/    - /' >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [ -z "$MISSING_IN_SHEETS" ] && [ -z "$EXTRA_IN_SHEETS" ]; then
    echo "  機能一覧章の機能キーと観点表キーの突合 OK（過不足なし）"
  fi
else
  echo "  観点表が 1 枚も見つからないためキー突合をスキップします（WARN 済み）"
fi

# --- (b) 未記入プレースホルダ検出 ---
echo ""
echo "[検査 b] 未記入プレースホルダ検出（HTML コメント外の <...>）"

PLACEHOLDER_LINES=$(awk '
  /<!--/ { in_comment=1 }
  {
    line=$0
    if (in_comment) {
      if (line ~ /-->/) { in_comment=0 }
      next
    }
    if (line ~ /<[^\/!][^>]*>/ && line ~ /<[^>]+>/) {
      # frontmatter のプレースホルダ行 <値> のような単純表現を対象
      if (line ~ /<[^<>]+>/) print NR": "line
    }
  }
' "$DESIGN_DOC" | grep -E '<[^<>]+>' || true)

if [ -n "$PLACEHOLDER_LINES" ]; then
  PLACEHOLDER_COUNT=$(printf '%s\n' "$PLACEHOLDER_LINES" | grep -c .)
  echo "  違反: 未記入プレースホルダが $PLACEHOLDER_COUNT 件見つかりました" >&2
  printf '%s\n' "$PLACEHOLDER_LINES" | head -20 >&2
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "  未記入プレースホルダなし"
fi

# --- (c) 連番キー検出（WARN） ---
echo ""
echo "[検査 c] 連番キー検出（意味キー規約違反の疑い・WARN）"

SEQ_KEYS=$(grep -nE '\b[A-Z]{1,4}-[0-9]+\b' "$DESIGN_DOC" | grep -viE 'utf-8|sha-256|iso-8601' || true)
ID_COLUMNS=$(grep -nE '^\| *ID *\|' "$DESIGN_DOC" || true)

if [ -n "$SEQ_KEYS" ] || [ -n "$ID_COLUMNS" ]; then
  echo "  WARN: 連番キー・ID 列の疑いがあります（意味キー規約 semantic-key-rules 参照）" >&2
  [ -n "$SEQ_KEYS" ] && printf '%s\n' "$SEQ_KEYS" >&2
  [ -n "$ID_COLUMNS" ] && printf '%s\n' "$ID_COLUMNS" >&2
  WARNINGS=$((WARNINGS + 1))
else
  echo "  連番キー・ID 列なし"
fi

# --- (d) 往復検証観点表の対応失敗クラス網羅チェック（WARN） ---
echo ""
echo "[検査 d] 結合テスト観点表「## 往復検証観点表」の対応失敗クラス網羅チェック（WARN）"

# 失敗クラス 10 種はスクリプト内定義。正本は ng-classification.md の表 B であり、
# 表 B が更新された場合は本リストも追従させること。
FAILURE_CLASSES="export-import-型不一致
状態変数欠落・初期値差
表示制御方式差（常時マウント vs 条件レンダー）
イベント処理挙動差
スタイル数値差
文言差
API呼び出し条件・型差
遷移方式・パラメータ差
定数値差
空状態・エラー状態差"

if [ -z "$INTEG_SHEET" ] || [ ! -f "$INTEG_SHEET" ]; then
  echo "  WARN: 結合テスト観点表が見つからないため検査 d をスキップします" >&2
  WARNINGS=$((WARNINGS + 1))
else
  RECIPROCAL_BODY="$(extract_heading_body "$INTEG_SHEET" '^## 往復検証観点表')"
  if [ -z "$RECIPROCAL_BODY" ]; then
    echo "  WARN: '## 往復検証観点表' セクションが結合テスト観点表に見つかりません: $INTEG_SHEET" >&2
    WARNINGS=$((WARNINGS + 1))
  else
    PRESENT_CLASSES="$(extract_table_column "$RECIPROCAL_BODY" 2 | sort -u)"
    MISSING_CLASSES="$(comm -23 <(printf '%s\n' "$FAILURE_CLASSES" | sort -u) <(printf '%s\n' "$PRESENT_CLASSES" | sort -u) || true)"
    if [ -n "$MISSING_CLASSES" ]; then
      echo "  WARN: 往復検証観点表に対応失敗クラスの欠落があります:" >&2
      printf '%s\n' "$MISSING_CLASSES" | sed 's/^/    - /' >&2
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  往復検証観点表の対応失敗クラス 10 種すべて充足"
    fi
  fi
fi

# --- (e) 往復検証観点表の L5 観点 × 操作シナリオ仕様書のシナリオ実在チェック（WARN） ---
echo ""
echo "[検査 e] 往復検証観点表の L5 観点 × 操作シナリオ仕様書のシナリオ突合（WARN）"

# operation_test_spec 自体が無い画面は L5 が任意機能のためスキップする（後方互換）。
# キーはあるが実体ファイルが無い場合はここで WARN + スキップする（audit スクリプト
# 自身の既存規約＝unit_test_sheet/integration_test_sheet 不在時の扱いに揃える。
# rebuilding SKILL.md Phase 1 のランタイム preflight はエラー扱いだが、こちらは
# 静的検査のため WARN に留める）。
if [ -z "$OPTEST_SPEC_REL" ]; then
  echo "  operation_test_spec が未設定のため検査 e をスキップします（L5 は任意機能）"
elif [ ! -f "$OPTEST_SPEC" ]; then
  echo "  WARN: 操作シナリオ仕様書が見つかりません ($OPTEST_SPEC_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
elif [ -z "$INTEG_SHEET" ] || [ ! -f "$INTEG_SHEET" ]; then
  echo "  WARN: 結合テスト観点表が見つからないため検査 e をスキップします" >&2
  WARNINGS=$((WARNINGS + 1))
else
  RECIPROCAL_BODY_E="$(extract_heading_body "$INTEG_SHEET" '^## 往復検証観点表')"
  if [ -z "$RECIPROCAL_BODY_E" ]; then
    echo "  WARN: '## 往復検証観点表' セクションが結合テスト観点表に見つかりません: $INTEG_SHEET" >&2
    WARNINGS=$((WARNINGS + 1))
  else
    # 検証層列（5列目）が L5 の行のキー（1列目）を抽出する。
    # extract_table_column と同じヘッダー・区切り行スキップ規則を踏襲する。
    L5_KEYS="$(printf '%s\n' "$RECIPROCAL_BODY_E" | awk '
      BEGIN { row=0 }
      /^\|/ {
        row++
        if (row == 1) next
        if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
        n = split($0, cols, "|")
        layer = cols[6]; gsub(/^[ \t]+|[ \t]+$/, "", layer)
        key = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/`/, "", key)
        if (layer == "L5" && key != "" && key !~ /^-+$/) print key
      }
    ' | sort -u)"
    L5_COUNT=$(printf '%s\n' "$L5_KEYS" | grep -c . || true)

    if [ "$L5_COUNT" -eq 0 ]; then
      echo "  往復検証観点表に L5 の行がないため検査 e は対象外です"
    else
      SCENARIO_BODY_E="$(extract_heading_body "$OPTEST_SPEC" '^## シナリオ一覧表')"
      SCENARIO_KEYS="$(extract_table_column "$SCENARIO_BODY_E" 2 | sed 's/`//g' | sort -u)"
      MISSING_L5="$(comm -23 <(printf '%s\n' "$L5_KEYS") <(printf '%s\n' "$SCENARIO_KEYS") || true)"
      if [ -n "$MISSING_L5" ]; then
        echo "  WARN: 往復検証観点表の L5 観点に対応するシナリオが操作シナリオ仕様書に見つかりません:" >&2
        printf '%s\n' "$MISSING_L5" | sed 's/^/    - /' >&2
        WARNINGS=$((WARNINGS + 1))
      else
        echo "  往復検証観点表の L5 観点（${L5_COUNT} 件）はすべて操作シナリオ仕様書にシナリオが存在します"
      fi
    fi
  fi
fi

# --- 結果集計 ---
echo ""
echo "=== 検査結果 ==="
echo "違反: $VIOLATIONS 件 / WARN: $WARNINGS 件"

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
exit 0
