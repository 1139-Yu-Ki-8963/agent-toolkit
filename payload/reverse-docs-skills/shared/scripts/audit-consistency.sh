#!/usr/bin/env bash
# audit-consistency.sh — Phase 2 の機械チェック / 実装契約章のファイル一覧取得
#
# 用途:
#   通常モード: 画面詳細設計書.md の内部整合性を機械的にチェックする。
#     (a) 機能一覧章の機能キー集合と、frontmatter の unit_test_sheet /
#         integration_test_sheet が指す観点表の機能キー集合の突合（両方向一致）
#     (b) 未記入プレースホルダ `<...>` の検出（HTML コメント内・fenced code block 内は除外）
#     (c) 連番キー検出（意味キー規約違反の WARN）
#     (d) 結合テスト観点表「## 往復検証観点表」の対応失敗クラス網羅チェック（WARN）
#     (i) §16 要確認事項一覧の未解消（状態≠解消済み）チェック（既定 WARN・
#         AUDIT_STRICT_P16=1 で違反扱いに昇格）
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
#   ./audit-consistency.sh --self-test

set -euo pipefail

# --- --self-test モード ---
# 検査g（§15.2テーブル型名抽出）・検査i（§16未解消チェック）の回帰保護。
# 既存検査a〜fは対象外（今回無変更のため）。最小構成の画面詳細設計書.mdフィクスチャを
# mktemp -d 配下に生成し、"$0" <dir> を呼び出して出力・終了コードを検証する。
self_test() {
  local script_path="$0"
  local tmp fail=0
  tmp="$(mktemp -d -p "${TMPDIR:-/tmp}")"

  make_fixture() {
    local dir="$1" p16_body="$2"
    mkdir -p "$dir"
    cat > "$dir/画面詳細設計書.md" <<MDEOF
---
unit_test_sheet: ./none.md
integration_test_sheet: ./none.md
---

## 章マップ

| 役割キー | § |
|---|---|
| 機能一覧 | §2 |
| 実装契約 | §15 |
| 要確認事項 | §16 |

## §2 機能一覧

| キー | 内容 |
|---|---|
| foo-view | 表示 |

## §15 実装契約

### 15.1 ファイル分割と export 一覧

| ファイルパス | export 名 | 種別 | 配置ディレクトリ |
|---|---|---|---|
| components/Foo.tsx | Foo | コンポーネント | components/ |

### 15.2 型定義

| 型名 | フィールド名 | 型 | 必須/任意 |
|---|---|---|---|
| \`FooValues\` | \`name\` | \`string\` | 必須 |
| \`FooValues\` | \`age\` | \`number\` | 任意 |

### 15.3 依存（import）一覧

| モジュール | import 内容 | 種別 |
|---|---|---|
| \`./Foo\` | \`Foo\` | 内部 |
| \`./FooValues\` | \`FooValues\` | 内部 |

## §16 要確認事項一覧

${p16_body}
MDEOF
  }

  # フィクスチャ a: §16 全解消済み（6列）
  make_fixture "$tmp/a" '| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 | 状態 |
|---|---|---|---|---|---|
| foo-issue | `2026-01-01` | 何らかの確認事項 | §15 | 実装完了 | 解消済み |'

  # フィクスチャ b: §16 未解消あり（6列）
  make_fixture "$tmp/b" '| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 | 状態 |
|---|---|---|---|---|---|
| foo-issue | `2026-01-01` | 何らかの確認事項 | §15 | 実装完了 | 未解消 |'

  # フィクスチャ c: 旧5列テンプレ（状態列なし）
  make_fixture "$tmp/c" '| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 |
|---|---|---|---|---|
| foo-issue | `2026-01-01` | 何らかの確認事項 | §15 | 実装完了 |'

  # ケース1: 検査g陽性（§15.2テーブル型名抽出 + §15.3内部import解決）
  if out_a="$(bash "$script_path" "$tmp/a" 2>&1)"; then rc_a=0; else rc_a=$?; fi
  if printf '%s' "$out_a" | grep -q "内部 import はすべて §15.1/§15.2 に対応が見つかりました"; then
    echo "[PASS] 検査g陽性: §15.2テーブルの型名(FooValues)が抽出され内部importが解決される"
  else
    echo "[FAIL] 検査g陽性: 内部importの解決に失敗（型名抽出ロジックの回帰の疑い）"
    fail=1
  fi

  # ケース2: 検査i陽性（全解消済み→WARN/違反なし）
  if [ "$rc_a" -eq 0 ] && printf '%s' "$out_a" | grep -q "要確認事項一覧はすべて解消済みです"; then
    echo "[PASS] 検査i陽性: 状態=解消済みのみでは違反・WARNが発生しない"
  else
    echo "[FAIL] 検査i陽性: 全解消済みフィクスチャでの判定に失敗（exit=${rc_a}）"
    fail=1
  fi

  # ケース3: 検査i陰性1（未解消行があっても既定はWARN止まり・exit0）
  if out_b_default="$(bash "$script_path" "$tmp/b" 2>&1)"; then rc_b_default=0; else rc_b_default=$?; fi
  if [ "$rc_b_default" -eq 0 ] && printf '%s' "$out_b_default" | grep -q "WARN:.*要確認事項一覧に未解消"; then
    echo "[PASS] 検査i陰性1: 未解消行があっても既定はWARN止まり(exit0)"
  else
    echo "[FAIL] 検査i陰性1: 期待した既定WARN挙動になっていません（exit=${rc_b_default}）"
    fail=1
  fi

  # ケース4: 検査i陰性2（AUDIT_STRICT_P16=1で違反に昇格しexit1）
  if out_b_strict="$(AUDIT_STRICT_P16=1 bash "$script_path" "$tmp/b" 2>&1)"; then rc_b_strict=0; else rc_b_strict=$?; fi
  if [ "$rc_b_strict" -eq 1 ] && printf '%s' "$out_b_strict" | grep -q "違反:.*要確認事項一覧に未解消"; then
    echo "[PASS] 検査i陰性2: AUDIT_STRICT_P16=1で未解消行が違反に昇格しexit1になる"
  else
    echo "[FAIL] 検査i陰性2: STRICT指定時に違反へ昇格しませんでした（exit=${rc_b_strict}）"
    fail=1
  fi

  # ケース5: 検査i陰性3（旧5列テンプレはSTRICT指定でもexit0のまま・fail-safe）
  if out_c_strict="$(AUDIT_STRICT_P16=1 bash "$script_path" "$tmp/c" 2>&1)"; then rc_c_strict=0; else rc_c_strict=$?; fi
  if [ "$rc_c_strict" -eq 0 ] && printf '%s' "$out_c_strict" | grep -q "旧テンプレのため状態列で解消判定できません"; then
    echo "[PASS] 検査i陰性3: 旧5列テンプレはAUDIT_STRICT_P16=1でも違反に昇格しない（fail-safe）"
  else
    echo "[FAIL] 検査i陰性3: 旧5列テンプレのfail-safe挙動が崩れています（exit=${rc_c_strict}）"
    fail=1
  fi

  rm -rf "$tmp"

  if [ "$fail" -ne 0 ]; then
    echo "=== self-test: FAIL ==="
    return 1
  fi
  echo "=== self-test: すべてPASS ==="
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

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
  local key="$1" raw
  raw="$(awk -v k="$key" '
    /^---$/ { c++; next }
    c==1 && $0 ~ "^"k":" { sub("^"k": *", ""); print; exit }
  ' "$DESIGN_DOC")"
  printf '%s' "$raw" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
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

# 参照先ドキュメントの種別（frontmatter type:）と必須見出しを検証する。
# ファイル存在チェックだけでは「実体はあるが別スキル・別画面用の資産だった」
# という取り違えを検出できないため、type: とセクション見出しの両方を確認する。
validate_referenced_doc() {
  local file="$1" label="$2" expected_type="$3"; shift 3
  local actual_type h
  actual_type="$(awk '/^---$/ { c++; next } c==1 && /^type:/ { sub(/^type: */, ""); print; exit }' "$file")"
  if [ "$actual_type" != "$expected_type" ]; then
    echo "  違反: ${label} の type が想定と異なります（期待: $expected_type / 実際: ${actual_type:-なし}）: $file" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  for h in "$@"; do
    if ! grep -qE "^## ${h}" "$file"; then
      echo "  違反: ${label} に必須見出し '## ${h}' が見つかりません: $file" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
  return 0
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

  # 行のいずれかの列に「参考情報」と明記された行（画面固有でない共有ファイル・
  # ルーター定義ファイル等の注記行）は白紙化対象から除外する。
  subbody="$(printf '%s\n' "$subbody" | awk '
    /^\|/ && $0 ~ /参考情報/ { next }
    { print }
  ')"

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
# インラインコメント除去は frontmatter_value() 内で共通化済み。
OPTEST_SPEC_REL="$(frontmatter_value operation_test_spec)"
OPTEST_SPEC="$(resolve_rel_path "$SCREEN_DIR" "$OPTEST_SPEC_REL" || true)"

# unit_test_spec / integration_test_spec / design_md は任意キー。検査 j・m（テスト仕様書
# 空殻検出・DESIGN.md 実測欄検出）が使う。
UNIT_SPEC_REL="$(frontmatter_value unit_test_spec)"
INTEG_SPEC_REL="$(frontmatter_value integration_test_spec)"
UNIT_SPEC="$(resolve_rel_path "$SCREEN_DIR" "$UNIT_SPEC_REL" || true)"
INTEG_SPEC="$(resolve_rel_path "$SCREEN_DIR" "$INTEG_SPEC_REL" || true)"
DESIGN_MD_REL="$(frontmatter_value design_md)"
DESIGN_MD="$(resolve_rel_path "$SCREEN_DIR" "$DESIGN_MD_REL" || true)"

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
  validate_referenced_doc "$UNIT_SHEET" "単体テスト観点表" "unit-test-sheet" "観点表"
  UNIT_KEYS="$(extract_sheet_keys "$UNIT_SHEET")"
  UNIT_COUNT=$(printf '%s\n' "$UNIT_KEYS" | grep -c . || true)
  echo "  単体テスト観点表 ($UNIT_SHEET_REL) のキー行数: $UNIT_COUNT"
else
  echo "  WARN: 単体テスト観点表が見つかりません ($UNIT_SHEET_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
fi

if [ -f "$INTEG_SHEET" ]; then
  validate_referenced_doc "$INTEG_SHEET" "結合テスト観点表" "integration-test-sheet" "観点表" "往復検証観点表"
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
echo "[検査 b] 未記入プレースホルダ検出（HTML コメント外・fenced code block 外の <...>）"

# 検出方式: `<...>` の「中身（inner）」で判定する（直前文字による判定は
# `<T>(x)` や `<Type>value`（旧式アサーション）を見逃すため廃止）。
# inner が次のいずれかに該当すれば未記入プレースホルダとみなす:
#   非 ASCII（日本語プレースホルダ）／ YYYY 日付／ HH:MM・MM:SS 等の時刻／
#   vX.Y バージョン／ 全大文字ハイフン区切り（MSG-ID 等）／ " / " を含む選択肢列挙。
# TS ジェネリクス（<T>, <T,>, Dispatch<SetStateAction<T>>, Record<string, number>,
# styled("td")<{...}> 等）は inner がいずれの条件にも該当しないため誤検出しない。
# 注意: 本テンプレートのプレースホルダは `<画面名>` のように単一バッククォートで
# 囲むのが標準記法（実測: テンプレート本文の 83 行がこの記法）。バッククォート
# 区間を丸ごと検出対象から除外する実装は、この標準記法のプレースホルダを大量に
# 見逃す（実測: 除外ありだと 99 件中 18 件しか検出できない）ため採用しない。
# 関数化: 検査 j（DESIGN.md への同一検出の再利用）のために切り出す。
scan_placeholder_lines() {
  local file="$1"
  awk '
    /^```/ { in_fence=!in_fence; next }
    in_fence { next }
    /<!--/ { in_comment=1 }
    {
      line=$0
      if (in_comment) { if (line ~ /-->/) in_comment=0; next }
      rest=line
      while (match(rest, /<[^\/!<>][^<>]*>/)) {
        inner=substr(rest, RSTART+1, RLENGTH-2)
        if (inner ~ /[^ -~]/ || inner ~ /Y{2,4}/ || inner ~ /MM-DD|HH:MM|MM:SS/ \
            || inner ~ /^v?X\.Y/ || inner ~ /^[A-Z]+(-[A-Z]+)+$/ || inner ~ / \/ /) {
          print NR": "line; break
        }
        rest=substr(rest, RSTART+RLENGTH)
      }
    }
  ' "$file" || true
}

PLACEHOLDER_LINES="$(scan_placeholder_lines "$DESIGN_DOC")"

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

# --- (f) §15.1 ファイル分割表の配置ディレクトリ列の記入チェック ---
echo ""
echo "[検査 f] §15.1 ファイル分割表の配置ディレクトリ列の記入チェック"

CONTRACT_SECNUM="$(resolve_role_section "実装契約")"
if [ -z "$CONTRACT_SECNUM" ]; then
  echo "  エラー: 章マップに役割キー '実装契約' の行が見つかりません: $DESIGN_DOC" >&2
  exit 1
fi
CONTRACT_BODY="$(extract_design_section_body "$CONTRACT_SECNUM")"
SPLIT_15_1="$(printf '%s\n' "$CONTRACT_BODY" | awk '
  /^### / && $0 ~ /ファイル分割/ { insub=1; next }
  /^### / && insub { exit }
  insub { print }
')"
HDR_15_1="$(printf '%s\n' "$SPLIT_15_1" | awk '/^\|/{print; exit}')"
if printf '%s' "$HDR_15_1" | grep -q '配置ディレクトリ'; then
  BAD_15_1="$(printf '%s\n' "$SPLIT_15_1" | awk '
    BEGIN { row=0 }
    /^\|/ {
      row++
      if (row == 1) next
      if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
      n = split($0, cols, "|")
      p = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", p)
      d = cols[5]; gsub(/^[ \t]+|[ \t]+$/, "", d)
      if (d == "" || d ~ /^<.*>$/) print "    - "p" (配置ディレクトリ未記入)"
    }
  ')"
  if [ -n "$BAD_15_1" ]; then
    echo "  違反: 配置ディレクトリ未記入の行があります" >&2
    printf '%s\n' "$BAD_15_1" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "  配置ディレクトリすべて記入済み"
  fi
else
  echo "  配置ディレクトリ列なし（旧テンプレ）。検査 f をスキップします"
fi

# --- (g) §15.3 依存(import)一覧・内部モジュールの実在確認（WARN） ---
echo ""
echo "[検査 g] §15.3 依存(import)一覧・内部モジュールの実在確認（WARN・barrel export 等の誤検出があるため hard fail にしない）"

SPLIT_15_2="$(printf '%s\n' "$CONTRACT_BODY" | awk '
  /^### / && $0 ~ /型定義/ { insub=1; next }
  /^### / && insub { exit }
  insub { print }
')"
# §15.2はテーブル様式（型名/フィールド名/型/必須任意）。型名は1列目から抽出する。
TYPE_NAMES="$(extract_table_column "$SPLIT_15_2" 1 | sed 's/`//g' | sort -u)"

FILE_BASENAMES="$(printf '%s\n' "$SPLIT_15_1" | awk '
  BEGIN { row=0 }
  /^\|/ {
    row++
    if (row == 1) next
    if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
    n = split($0, cols, "|")
    p = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", p)
    if (p != "" && p !~ /^<.*>$/) print p
  }
' | xargs -I{} basename {} 2>/dev/null | sed -E 's/\.[A-Za-z0-9]+$//' | sort -u)"

SPLIT_15_3="$(printf '%s\n' "$CONTRACT_BODY" | awk '
  /^### / && $0 ~ /依存/ && $0 ~ /import/ { insub=1; next }
  /^### / && insub { exit }
  insub { print }
')"
INTERNAL_MODULES="$(printf '%s\n' "$SPLIT_15_3" | awk '
  BEGIN { row=0 }
  /^\|/ {
    row++
    if (row == 1) next
    if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
    n = split($0, cols, "|")
    m = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", m); gsub(/`/, "", m)
    t = cols[4]; gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "内部" && m != "" && m !~ /^<.*>$/) print m
  }
')"

UNRESOLVED_IMPORTS=""
if [ -n "$INTERNAL_MODULES" ]; then
  while IFS= read -r mod; do
    [ -z "$mod" ] && continue
    seg="$(basename "$mod")"
    seg="${seg%.*}"
    if ! printf '%s\n' "$FILE_BASENAMES" | grep -qxF "$seg" && ! printf '%s\n' "$TYPE_NAMES" | grep -qxF "$seg"; then
      UNRESOLVED_IMPORTS="${UNRESOLVED_IMPORTS}${mod}
"
    fi
  done <<< "$INTERNAL_MODULES"
fi

if [ -n "$(printf '%s' "$UNRESOLVED_IMPORTS" | tr -d '[:space:]')" ]; then
  echo "  WARN: §15.1/§15.2 に対応が見つからない内部 import があります（barrel export 等の可能性）:" >&2
  printf '%s\n' "$UNRESOLVED_IMPORTS" | grep . | sort -u | sed 's/^/    - /' >&2
  WARNINGS=$((WARNINGS + 1))
else
  echo "  内部 import はすべて §15.1/§15.2 に対応が見つかりました（または内部 import なし）"
fi

# --- 状態キーの表記ゆれ検出（WARN・最小: lowercase 完全一致 + 原表記差分のみ） ---
# 日英ゆれ・同義語は機械判定不能なため対象外とする（Claude レビューのチェックリストに委ねる）。
echo ""
echo "[検査] 状態管理キーの表記ゆれ検出（WARN・大小/区切りゆれのみを対象とする最小判定）"

STATE_SECNUM="$(resolve_role_section "状態管理")"
if [ -z "$STATE_SECNUM" ]; then
  echo "  WARN: 章マップに役割キー '状態管理' の行が見つかりません。表記ゆれ検査をスキップします" >&2
  WARNINGS=$((WARNINGS + 1))
else
  STATE_BODY="$(extract_design_section_body "$STATE_SECNUM")"
  STATE_KEYS="$(printf '%s\n' "$STATE_BODY" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort -u)"

  REST_BODY="$(awk -v pat="^## §${STATE_SECNUM}([^0-9]|\$)" '
    $0 ~ pat { in_sec=1; next }
    in_sec && /^## / { in_sec=0 }
    !in_sec { print }
  ' "$DESIGN_DOC")"
  REST_KEYS="$(printf '%s\n' "$REST_BODY" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort -u)"

  MISMATCHES=""
  if [ -n "$STATE_KEYS" ] && [ -n "$REST_KEYS" ]; then
    while IFS= read -r sk; do
      [ -z "$sk" ] && continue
      sk_lower="$(printf '%s' "$sk" | tr 'A-Z' 'a-z')"
      while IFS= read -r rk; do
        [ -z "$rk" ] && continue
        [ "$rk" = "$sk" ] && continue
        rk_lower="$(printf '%s' "$rk" | tr 'A-Z' 'a-z')"
        if [ "$rk_lower" = "$sk_lower" ]; then
          MISMATCHES="${MISMATCHES}${sk} (§${STATE_SECNUM}) <-> ${rk}
"
        fi
      done <<< "$REST_KEYS"
    done <<< "$STATE_KEYS"
  fi

  if [ -n "$(printf '%s' "$MISMATCHES" | tr -d '[:space:]')" ]; then
    echo "  WARN: 状態キーの表記ゆれの疑いがあります（大文字小文字・区切り文字違い）:" >&2
    printf '%s\n' "$MISMATCHES" | grep . | sort -u | sed 's/^/    - /' >&2
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  状態キーの表記ゆれなし"
  fi
fi

# --- (h) 起動時初期化（§6.1.1）の記載有無チェック（条件付き WARN） ---
echo ""
echo "[検査 h] 起動時初期化（§6.1.1）の記載有無チェック（URL パラメータ実在 かつ 画面専用ストア実在の画面が対象）"

STATE_SECNUM_H="$(resolve_role_section "状態管理")"
FLOW_SECNUM_H="$(resolve_role_section "データフロー")"

if [ -z "$STATE_SECNUM_H" ] || [ -z "$FLOW_SECNUM_H" ]; then
  echo "  WARN: 章マップに役割キー '状態管理' または 'データフロー' の行が見つかりません。検査 h をスキップします" >&2
  WARNINGS=$((WARNINGS + 1))
else
  STATE_BODY_H="$(extract_design_section_body "$STATE_SECNUM_H")"

  URL_PARAM_BODY="$(printf '%s\n' "$STATE_BODY_H" | awk '
    /^### / && $0 ~ /URL パラメータ/ { insub=1; next }
    /^### / && insub { exit }
    insub { print }
  ')"
  URL_PARAM_ROWS="$(extract_table_column "$URL_PARAM_BODY" 1 | grep -vE '^<.*>$' || true)"
  URL_PARAM_COUNT=$(printf '%s\n' "$URL_PARAM_ROWS" | grep -c . || true)

  STORE_BODY="$(printf '%s\n' "$STATE_BODY_H" | awk '
    /^### / && $0 ~ /画面専用ストア/ { insub=1; next }
    /^### / && insub { exit }
    insub { print }
  ')"
  STORE_TEXT="$(printf '%s\n' "$STORE_BODY" | grep -v '^$' | grep -v '^<!--' || true)"
  STORE_TEXT_COMPACT="$(printf '%s' "$STORE_TEXT" | tr -d '[:space:]')"
  if [ -z "$STORE_TEXT_COMPACT" ] \
     || printf '%s' "$STORE_TEXT" | grep -qE '該当なし' \
     || printf '%s' "$STORE_TEXT" | grep -qE '^`?<[^<>]*>`?$'; then
    STORE_FILLED=0
  else
    STORE_FILLED=1
  fi

  if [ "$URL_PARAM_COUNT" -eq 0 ]; then
    echo "  URL パラメータが無い画面のため検査 h は対象外です"
  elif [ "$STORE_FILLED" -eq 0 ]; then
    echo "  画面専用ストアが無い画面のため検査 h は対象外です"
  else
    FLOW_BODY_H="$(extract_design_section_body "$FLOW_SECNUM_H")"
    INIT_BODY="$(printf '%s\n' "$FLOW_BODY_H" | awk '
      /^#### / && $0 ~ /起動時初期化/ { insub=1; next }
      insub && /^#### / { exit }
      insub && /^### / { exit }
      insub { print }
    ')"
    INIT_TEXT="$(printf '%s\n' "$INIT_BODY" | grep -v '^$' | grep -v '^<!--' || true)"
    INIT_TEXT_COMPACT="$(printf '%s' "$INIT_TEXT" | tr -d '[:space:]')"
    if [ -z "$INIT_TEXT_COMPACT" ] \
       || printf '%s' "$INIT_TEXT" | grep -qE '^`?<[^<>]*>`?$'; then
      echo "  WARN: URL パラメータと画面専用ストアが存在するにもかかわらず §6.1.1 起動時初期化が未記載です" >&2
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  §6.1.1 起動時初期化が記載済みです"
    fi
  fi
fi

# --- (i) §16 要確認事項一覧の未解消チェック（既定WARN・AUDIT_STRICT_P16=1で違反扱い） ---
echo ""
echo "[検査 i] §16 要確認事項一覧の未解消チェック（既定WARN。AUDIT_STRICT_P16=1で違反扱い）"

CONFIRM_SECNUM="$(resolve_role_section "要確認事項")"
if [ -z "$CONFIRM_SECNUM" ]; then
  echo "  WARN: 章マップに役割キー '要確認事項' の行が見つかりません。検査iをスキップします" >&2
  WARNINGS=$((WARNINGS + 1))
else
  CONFIRM_BODY="$(extract_design_section_body "$CONFIRM_SECNUM")"
  CONFIRM_HDR="$(printf '%s\n' "$CONFIRM_BODY" | awk '/^\|/{print; exit}')"

  if printf '%s' "$CONFIRM_HDR" | grep -q '状態'; then
    UNRESOLVED_ROWS="$(printf '%s\n' "$CONFIRM_BODY" | awk '
      BEGIN { row=0 }
      /^\|/ {
        row++
        if (row == 1) next
        if (row == 2 && $0 ~ /^\|[ \t:|\-]+$/) next
        n = split($0, cols, "|")
        key = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", key)
        st  = cols[7]; gsub(/^[ \t]+|[ \t]+$/, "", st)
        if (key != "" && key !~ /^<.*>$/ && st != "解消済み") print key" ("st")"
      }
    ')"
    UNRESOLVED_COUNT=$(printf '%s\n' "$UNRESOLVED_ROWS" | grep -c . || true)
    if [ "$UNRESOLVED_COUNT" -gt 0 ]; then
      if [ "${AUDIT_STRICT_P16:-0}" = "1" ]; then
        echo "  違反: §${CONFIRM_SECNUM} 要確認事項一覧に未解消（状態≠解消済み）が ${UNRESOLVED_COUNT} 件あります（AUDIT_STRICT_P16=1）:" >&2
        printf '%s\n' "$UNRESOLVED_ROWS" | grep . | sed 's/^/    - /' >&2
        VIOLATIONS=$((VIOLATIONS + 1))
      else
        echo "  WARN: §${CONFIRM_SECNUM} 要確認事項一覧に未解消（状態≠解消済み）が ${UNRESOLVED_COUNT} 件あります:" >&2
        printf '%s\n' "$UNRESOLVED_ROWS" | grep . | sed 's/^/    - /' >&2
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo "  §${CONFIRM_SECNUM} 要確認事項一覧はすべて解消済みです（0件を含む）"
    fi
  else
    UNRESOLVED_COUNT="$(extract_table_column "$CONFIRM_BODY" 1 | grep -vE '^<.*>$' | grep -c . || true)"
    if [ "$UNRESOLVED_COUNT" -gt 0 ]; then
      echo "  WARN: §${CONFIRM_SECNUM} 要確認事項一覧に ${UNRESOLVED_COUNT} 件の記載があります（旧テンプレのため状態列で解消判定できません。6列テンプレへの更新を検討してください）" >&2
      WARNINGS=$((WARNINGS + 1))
    else
      echo "  §${CONFIRM_SECNUM} 要確認事項一覧は0件です"
    fi
  fi
fi

# --- (j) DESIGN.md の未記入プレースホルダ検出（実測値の抽出元欄等の省略。design_md 未設定なら対象外） ---
echo ""
echo "[検査 j] DESIGN.md の未記入プレースホルダ検出（実測値の抽出元欄等の省略。design_md 未設定なら対象外）"

if [ -z "$DESIGN_MD" ]; then
  echo "  design_md が frontmatter に未設定のため検査 j をスキップします"
elif [ ! -f "$DESIGN_MD" ]; then
  echo "  WARN: design_md が指すファイルが見つかりません ($DESIGN_MD_REL)" >&2
  WARNINGS=$((WARNINGS + 1))
else
  DESIGN_MD_PLACEHOLDER_LINES="$(scan_placeholder_lines "$DESIGN_MD")"
  if [ -n "$DESIGN_MD_PLACEHOLDER_LINES" ]; then
    DESIGN_MD_PLACEHOLDER_COUNT=$(printf '%s\n' "$DESIGN_MD_PLACEHOLDER_LINES" | grep -c .)
    echo "  違反: DESIGN.md に未記入プレースホルダが $DESIGN_MD_PLACEHOLDER_COUNT 件見つかりました（実測値の抽出元欄等の省略）:" >&2
    printf '%s\n' "$DESIGN_MD_PLACEHOLDER_LINES" | head -20 >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "  DESIGN.md に未記入プレースホルダなし"
  fi
fi

# --- (k) 未確定値のプレースホルダ文字列検出（根拠なしの実測委譲・TBD・TODO・未定・FIXME・PLACEHOLDER） ---
echo ""
echo "[検査 k] 未確定値のプレースホルダ文字列検出（根拠なしの実測委譲・TBD・TODO・未定・FIXME・PLACEHOLDER）"

RAW_PLACEHOLDER_FILES="$DESIGN_DOC"
[ -n "$DESIGN_MD" ] && [ -f "$DESIGN_MD" ] && RAW_PLACEHOLDER_FILES="$RAW_PLACEHOLDER_FILES $DESIGN_MD"

# 唯一の許容表記は「実測委譲（画面単位検証で確定）」（writing-rules.md「実測委譲の書式」参照）。
# 根拠の丸括弧を伴わない生の実測委譲・その他語彙はすべて違反とする。
RAW_PLACEHOLDER_LINES="$(grep -nE '実測委譲|TBD|TODO|未定|FIXME|PLACEHOLDER' $RAW_PLACEHOLDER_FILES 2>/dev/null | grep -v '実測委譲（画面単位検証で確定）' || true)"
if [ -n "$RAW_PLACEHOLDER_LINES" ]; then
  echo "  違反: 根拠のないプレースホルダ文字列が見つかりました（唯一の許容表記は「実測委譲（画面単位検証で確定）」）:" >&2
  printf '%s\n' "$RAW_PLACEHOLDER_LINES" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo "  未確定値のプレースホルダ文字列なし"
fi

# --- (l) 「該当なし」記述の根拠併記チェック（WARN・同一行に丸括弧の根拠が無い場合に警告） ---
echo ""
echo "[検査 l] 「該当なし」記述の根拠併記チェック（WARN・同一行に丸括弧の根拠が無い場合に警告）"

NO_GROUND_LINES="$(grep -nE '該当なし' "$DESIGN_DOC" | grep -vE '該当なし[[:space:]]*[（(]' || true)"
if [ -n "$NO_GROUND_LINES" ]; then
  echo "  WARN: 根拠（丸括弧書き）を伴わない「該当なし」が見つかりました:" >&2
  printf '%s\n' "$NO_GROUND_LINES" >&2
  WARNINGS=$((WARNINGS + 1))
else
  echo "  「該当なし」はすべて根拠を伴っています（該当箇所なしを含む）"
fi

# --- (m) テスト仕様書の空殻検出・draft据え置き検出・観点網羅チェック（WARN） ---
echo ""
echo "[検査 m] テスト仕様書の空殻検出・draft据え置き検出・観点網羅チェック（WARN）"

check_spec_shell() {
  local spec="$1" label="$2" heading="$3"
  [ -z "$spec" ] && return 0
  [ ! -f "$spec" ] && return 0
  local status body rows
  status="$(awk '/^---$/ { c++; next } c==1 && /^status:/ { sub(/^status: */, ""); sub(/[[:space:]]*#.*$/, ""); print; exit }' "$spec")"
  body="$(extract_heading_body "$spec" "$heading")"
  rows="$(extract_table_column "$body" 1 | grep -vE '^<.*>$|^`<.*>`$' | grep -c . || true)"
  if [ "$rows" -eq 0 ]; then
    echo "  WARN: ${label} が空殻です（プレースホルダのみで実データがありません）: $spec" >&2
    WARNINGS=$((WARNINGS + 1))
  elif [ "$status" = "draft" ]; then
    echo "  WARN: ${label} は実データ記入済みですが status が draft のままです（テストコード実装後に implemented へ更新すること）: $spec" >&2
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_spec_shell "$UNIT_SPEC" "単体テスト仕様書" '^## テストケース一覧'
check_spec_shell "$INTEG_SPEC" "結合テスト仕様書" '^## テストケース一覧'
check_spec_shell "$OPTEST_SPEC" "操作シナリオ仕様書" '^## シナリオ一覧表'

check_sheet_spec_coverage() {
  local sheet="$1" spec="$2" label="$3" heading="$4"
  [ -f "$sheet" ] || return 0
  local sheet_keys spec_keys saved_keys all_covered uncovered
  sheet_keys="$(extract_sheet_keys "$sheet")"
  [ -z "$sheet_keys" ] && return 0
  spec_keys=""
  if [ -n "$spec" ] && [ -f "$spec" ]; then
    spec_keys="$(extract_table_column "$(extract_heading_body "$spec" "$heading")" 2 | sed 's/`//g' | grep -vE '^<.*>$' | sort -u)"
  fi
  saved_keys=""
  if [ -d "$SCREEN_DIR/検証記録" ]; then
    saved_keys="$(find "$SCREEN_DIR/検証記録" -type d -name 'テストコード' -exec find {} -type f \; 2>/dev/null \
      | xargs -I{} basename {} 2>/dev/null | sed -E 's/\.[A-Za-z0-9]+$//' | sort -u)"
  fi
  all_covered="$(printf '%s\n%s\n' "$spec_keys" "$saved_keys" | grep . | sort -u || true)"
  uncovered="$(comm -23 <(printf '%s\n' "$sheet_keys") <(printf '%s\n' "$all_covered") || true)"
  if [ -n "$uncovered" ]; then
    echo "  WARN: ${label} の観点キーのうち、テスト仕様書の具体ケース・保存済みテストコードのいずれにも対応が見つからないもの:" >&2
    printf '%s\n' "$uncovered" | sed 's/^/    - /' >&2
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_sheet_spec_coverage "$UNIT_SHEET" "$UNIT_SPEC" "単体テスト観点表" '^## テストケース一覧'
check_sheet_spec_coverage "$INTEG_SHEET" "$INTEG_SPEC" "結合テスト観点表" '^## テストケース一覧'

# --- (n) 画面横断章（業務語彙抽象化章）の実装依存語彙逸脱検出（WARN） ---
echo ""
echo "[検査 n] 画面横断章の実装依存語彙逸脱検出（コード識別子・フレームワーク用語・型構文・ファイルパス・ライブラリ名。役割キーが章マップに無い章はスキップ。WARN）"

BUSINESS_ROLE_KEYS="機能一覧 画面遷移"
BUSINESS_BODY=""
BUSINESS_CHECKED=""
for role in $BUSINESS_ROLE_KEYS; do
  secnum="$(resolve_role_section "$role" || true)"
  [ -z "$secnum" ] && continue
  BUSINESS_BODY="${BUSINESS_BODY}
$(extract_design_section_body "$secnum")"
  BUSINESS_CHECKED="${BUSINESS_CHECKED} §${secnum}(${role})"
done

if [ -z "$(printf '%s' "$BUSINESS_BODY" | tr -d '[:space:]')" ]; then
  echo "  章マップに画面横断章の役割キーが見つからないため検査 n をスキップします"
else
  echo "  検査対象:${BUSINESS_CHECKED}（画面概要・業務ルール・非機能要件・共通仕様準拠は章マップに役割キー未登録のため対象外）"
  IMPL_LEAK="$(printf '%s\n' "$BUSINESS_BODY" | grep -nE '\buseState\b|\buseEffect\b|\buseReducer\b|\bProps\b|styled-components|\bReact\b|\bVue\b|\bAngular\b|\binterface [A-Z]|: *(string|number|boolean)\b|/[A-Za-z0-9_-]+\.(tsx|ts|jsx|js|css)\b' || true)"
  if [ -n "$IMPL_LEAK" ]; then
    echo "  WARN: 画面横断章に実装依存語彙（コード識別子・フレームワーク用語・型構文・ファイルパス）の疑いがあります:" >&2
    printf '%s\n' "$IMPL_LEAK" | sed 's/^/    - /' >&2
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  画面横断章に実装依存語彙の疑いなし"
  fi
fi

# --- (o) 配布物の正本参照ヘッダ検査（デプロイ先 SKILL.md の直接修正防止） ---
echo ""
echo "[検査 o] 配布物の正本参照ヘッダ検査（デプロイされた SKILL.md の frontmatter 内/直後に '# 正本: reverse-docs-skills' があるか。正本リポジトリ自体ではスキップ・WARN）"

# フロントマター（1行目 --- 〜 次の ---）内、またはフロントマター終了直後5行以内に
# '# 正本: reverse-docs-skills' があるかを判定する。1行目が --- でなければ検査対象外(NOFM)。
check_skill_canonical_header() {
  local file="$1" first_line fm_end check_end
  first_line="$(head -n1 "$file")"
  if [ "$first_line" != "---" ]; then
    echo "NOFM"
    return
  fi
  fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$file")"
  if [ -z "$fm_end" ]; then
    echo "NOFM"
    return
  fi
  check_end=$((fm_end + 5))
  if sed -n "1,${check_end}p" "$file" | grep -q '^# 正本: reverse-docs-skills'; then
    echo "OK"
  else
    echo "MISSING"
  fi
}

REPO_ROOT_O="$(cd "$SCREEN_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT_O" ]; then
  echo "  git リポジトリを特定できないため検査 o をスキップします"
elif [ -f "$REPO_ROOT_O/.claude/rules/always/publish/complete/rule.md" ]; then
  # 正本リポジトリ（reverse-docs-skills）自体の判定は basename（worktree ではリポジトリ名と
  # 一致しないため使えない）ではなく、正本にのみ存在し配布先へは同期されないファイル
  # （publish-complete 規約。sync-manifest.json の同期対象は .claude/skills・shared・
  # README.md・reverse-docs-overview.html の4点のみで .claude/rules は含まれない）の
  # 実在をフィンガープリントとして使う。worktree でも同一リポジトリなら実在するため正しく判定できる。
  echo "  正本リポジトリ（reverse-docs-skills）自体での実行のため検査 o をスキップします"
elif [ ! -d "$REPO_ROOT_O/.claude/skills" ]; then
  echo "  .claude/skills が見つからないため検査 o をスキップします"
else
  MISSING_HEADER_SKILLS=""
  while IFS= read -r skill_md; do
    [ -z "$skill_md" ] && continue
    if [ "$(check_skill_canonical_header "$skill_md")" = "MISSING" ]; then
      MISSING_HEADER_SKILLS="${MISSING_HEADER_SKILLS}${skill_md}
"
    fi
  done < <(find "$REPO_ROOT_O/.claude/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null)

  if [ -n "$(printf '%s' "$MISSING_HEADER_SKILLS" | tr -d '[:space:]')" ]; then
    echo "  WARN: 正本参照ヘッダ（# 正本: reverse-docs-skills）が無い SKILL.md があります（配布先での直接修正の疑い。修正は正本リポジトリ reverse-docs-skills で行うこと）:" >&2
    printf '%s\n' "$MISSING_HEADER_SKILLS" | grep . | sed 's/^/    - /' >&2
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  配布先の SKILL.md はすべて正本参照ヘッダを含んでいます（対象 0 件を含む）"
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
