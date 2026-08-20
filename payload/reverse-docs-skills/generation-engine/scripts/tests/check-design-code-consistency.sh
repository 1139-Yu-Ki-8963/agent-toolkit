#!/usr/bin/env bash
# 設計書の記述が対象プロジェクトの実装（ソースコード）と一致するかを検査する。
#
# delivery-payload/references/design-code-consistency.json が定める4種類を行う。
#   第1種: 定数の値の一致（根拠台帳の項目列の数値 vs 対象コード:行の数値リテラル）
#   第2種: 本文の件数と表の実数の一致（生成済み設計書のみ・コード不要）
#   第3種: 業務ルールの条件（機械化範囲=構文的手掛かりの検出まで。人手範囲は判定しない）
#   境界値の一致（単体テスト設計書 §6 境界値のキー vs 詳細設計書の判定表キー）
#
# 対応定義は既存の設計単位根拠台帳.md（対象文書・節・項目・対象コード・行の5列）を
# 再利用する。根拠台帳が未整備の設計単位は代替入力を用意せず判定不能として扱う
# （確度の低い判定を合否の判定と同じ形で並べない）。
#
# 使い方:
#   check-design-code-consistency.sh <project_root> <source_dir>
#   check-design-code-consistency.sh --self-test
#
# 終了コード:
#   0 = 不一致・判定不能単位のいずれも無い
#   1 = 不一致あり
#   2 = 判定不能（mktemp失敗、または根拠台帳が1件も無く検査対象が0件）
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

KIND_ROOTS="screenUnitRoot:screen apiUnitRoot:api tableUnitRoot:table batchUnitRoot:batch reportUnitRoot:report externalUnitRoot:external featureUnitRoot:feature"
LEDGER_BASENAME="設計単位根拠台帳.md"

resolve_kind_roots() {
  local project_root="$1" layout_json pair root_key kind rel abs
  layout_json="$(resolve_output_layout "$project_root")" || return 1
  for pair in $KIND_ROOTS; do
    root_key="${pair%%:*}"
    kind="${pair#*:}"
    rel="$(output_layout_get "$layout_json" "$root_key" 2>/dev/null)" || continue
    [ -n "$rel" ] || continue
    abs="$project_root/$rel"
    [ -d "$abs" ] || continue
    printf '%s\t%s\n' "$kind" "$abs"
  done
}

# 表のデータ行（先頭・末尾の | を除いた行）を1行1レコードで返す。
# ヘッダー行は見出しに「対象文書」を含む行として識別する。
parse_ledger_rows() {
  local file="$1"
  awk '
    BEGIN { state = 0 }
    /^\|.*\|[[:space:]]*$/ {
      if (state == 0) {
        if ($0 ~ /対象文書/) { state = 1 }
        next
      }
      if (state == 1) {
        if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
        state = 0
        next
      }
      if (state == 2) { print; next }
    }
    { if (state == 2) state = 0 }
  ' "$file"
}

# 5列パイプ区切り行を trim 済みの5値へ分解し、TAB区切りで返す。
_split_ledger_row() {
  local row="$1"
  row="${row#|}"
  row="${row%|}"
  printf '%s' "$row" | awk -F'|' '{
    for (i = 1; i <= NF; i++) {
      v = $i
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      printf "%s", v
      if (i < NF) printf "\t"
    }
    print ""
  }'
}

_extract_numbers() {
  grep -oE '[0-9]+(,[0-9]{3})*' | tr -d ',' | sort -u
}

# ---------------------------------------------------------------------------
# 第1種: 定数の値の一致
# ---------------------------------------------------------------------------
check_constant_value() {
  local ledger_file="$1" source_dir="$2" rc=0
  local row target_doc target_section item target_code line_no
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    IFS=$'\t' read -r target_doc target_section item target_code line_no <<< "$(_split_ledger_row "$row")"
    if [ "$target_code" = "該当なし" ] || [ "$line_no" = "該当なし" ] || [ -z "$target_code" ]; then
      continue
    fi
    local item_numbers
    item_numbers="$(printf '%s' "$item" | _extract_numbers)"
    [ -n "$item_numbers" ] || continue

    local target_path="$source_dir/$target_code"
    if [ ! -f "$target_path" ]; then
      echo "FAIL 定数値-対象コード不在 ${ledger_file}: 対象コード「${target_code}」が実在しない"
      rc=1
      continue
    fi
    if ! [[ "$line_no" =~ ^[1-9][0-9]*$ ]]; then
      echo "FAIL 定数値-行番号不正 ${ledger_file}: 行「${line_no}」が1始まりの整数ではない"
      rc=1
      continue
    fi
    local code_line code_numbers
    code_line="$(sed -n "${line_no}p" "$target_path" 2>/dev/null)"
    code_numbers="$(printf '%s' "$code_line" | _extract_numbers)"

    local found=0 n
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      if printf '%s\n' "$code_numbers" | grep -qFx "$n"; then
        found=1
        break
      fi
    done <<< "$item_numbers"
    if [ "$found" -eq 0 ]; then
      echo "FAIL 定数値-不一致 ${ledger_file}: 項目「${item}」の数値が対象コード「${target_code}:${line_no}」に見つからない"
      rc=1
    fi
  done < <(parse_ledger_rows "$ledger_file")
  return "$rc"
}

# ---------------------------------------------------------------------------
# 第2種: 本文の件数と表の実数の一致
# ---------------------------------------------------------------------------
check_count_consistency() {
  local doc_file="$1" rc=0
  local matches
  matches="$(grep -noE '[0-9]+(個|件|箇所|サブルーチン)' "$doc_file" 2>/dev/null || true)"
  [ -n "$matches" ] || return 0

  local line_no match number table_rows
  while IFS=: read -r line_no match; do
    [ -n "$line_no" ] || continue
    number="$(printf '%s' "$match" | grep -oE '^[0-9]+')"
    table_rows="$(awk -v start="$line_no" '
      BEGIN { state = 0; count = 0 }
      NR <= start { next }
      /^\|.*\|[[:space:]]*$/ {
        if (state == 0) { state = 1; next }
        if (state == 1) {
          if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
          state = 0; next
        }
        if (state == 2) { count++; next }
      }
      !/^\|.*\|[[:space:]]*$/ {
        if (state == 2) { exit }
        state = 0
      }
      END { print count }
    ' "$doc_file")"
    if [ -z "$table_rows" ]; then
      continue
    fi
    if [ "$table_rows" != "$number" ]; then
      echo "FAIL 件数不一致 ${doc_file}:${line_no}: 本文の記述「${number}」に対し直後の表の実数は${table_rows}"
      rc=1
    fi
  done <<< "$matches"
  return "$rc"
}

# ---------------------------------------------------------------------------
# 第3種: 業務ルールの条件（機械化範囲=構文的手掛かりの検出のみ）
# ---------------------------------------------------------------------------
check_business_rule_hint() {
  local ledger_file="$1" source_dir="$2" rc=0
  local row target_doc target_section item target_code line_no
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    IFS=$'\t' read -r target_doc target_section item target_code line_no <<< "$(_split_ledger_row "$row")"
    if [ "$target_code" = "該当なし" ] || [ "$line_no" = "該当なし" ] || [ -z "$target_code" ]; then
      continue
    fi
    if ! [[ "$line_no" =~ ^[1-9][0-9]*$ ]]; then
      continue
    fi
    local target_path="$source_dir/$target_code"
    [ -f "$target_path" ] || continue

    local start end window
    start=$((line_no > 5 ? line_no - 5 : 1))
    end=$((line_no + 5))
    window="$(sed -n "${start},${end}p" "$target_path" 2>/dev/null)"
    if ! printf '%s\n' "$window" | grep -qE 'if[[:space:](]|else|switch|case|==|!=|>=|<=|[^=!<>]>[^=]|[^=!<>]<[^=]'; then
      echo "FAIL 業務ルール-構文的手掛かりなし ${ledger_file}: 対象コード「${target_code}:${line_no}」の前後5行に条件式・比較演算子が見つからない（機械検査の範囲。意味の一致は人手で判定する）"
      rc=1
    fi
  done < <(parse_ledger_rows "$ledger_file")
  return "$rc"
}

# ---------------------------------------------------------------------------
# 境界値の一致（詳細設計書と単体テスト設計書の突合）
# ---------------------------------------------------------------------------

# ファイル内の全表について、1列目が「キー」であるものの値を1行1レコードで返す。
_extract_key_column_values() {
  local file="$1"
  awk '
    BEGIN { state = 0 }
    /^\|.*\|[[:space:]]*$/ {
      if (state == 0) {
        n = split($0, cells, "|")
        first = cells[2]
        gsub(/^[ \t]+|[ \t]+$/, "", first)
        if (first == "キー") { state = 1 } else { state = 0 }
        next
      }
      if (state == 1) {
        if ($0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
        state = 0
        next
      }
      if (state == 2) {
        n = split($0, cells, "|")
        val = cells[2]
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (val != "") print val
        next
      }
    }
    { if (state == 2) state = 0 }
  ' "$file"
}

check_boundary_value() {
  local unit_dir="$1" rc=0
  local test_doc
  test_doc="$(find "$unit_dir" -type f -name '*単体テスト設計書.md' 2>/dev/null | sort | head -1)"
  [ -n "$test_doc" ] || return 0

  local test_keys
  test_keys="$(_extract_key_column_values "$test_doc")"
  [ -n "$test_keys" ] || return 0

  local detail_docs all_detail_keys d
  detail_docs="$(find "$unit_dir" -type f -name '*詳細設計書.md' 2>/dev/null | sort)"
  all_detail_keys=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    all_detail_keys="${all_detail_keys}$(_extract_key_column_values "$d")"$'\n'
  done <<< "$detail_docs"

  local key
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! printf '%s\n' "$all_detail_keys" | grep -qFx "$key"; then
      echo "FAIL 境界値-キー不整合 ${test_doc}: キー「${key}」が同一設計単位の詳細設計書の判定表に見つからない"
      rc=1
    fi
  done <<< "$test_keys"
  return "$rc"
}

# ---------------------------------------------------------------------------
# 集約
# ---------------------------------------------------------------------------
run_check() {
  local project_root="$1" source_dir="$2" rc=0
  local ledgers_checked=0 units_without_ledger=0

  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  if [ ! -d "$source_dir" ]; then
    echo "ERROR: source_dir が存在しません: $source_dir" >&2
    return 1
  fi

  local kind_roots kind kind_root unit_dir ledger_file
  kind_roots="$(resolve_kind_roots "$project_root")" || return 1

  while IFS=$'\t' read -r kind kind_root; do
    [ -n "$kind_root" ] || continue
    while IFS= read -r unit_dir; do
      [ -n "$unit_dir" ] || continue
      ledger_file="$unit_dir/$LEDGER_BASENAME"
      if [ ! -f "$ledger_file" ]; then
        units_without_ledger=$((units_without_ledger + 1))
        continue
      fi
      ledgers_checked=$((ledgers_checked + 1))
      check_constant_value "$ledger_file" "$source_dir" || rc=1
      check_business_rule_hint "$ledger_file" "$source_dir" || rc=1
      check_boundary_value "$unit_dir" || rc=1
    done < <(find "$kind_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  done <<EOF
$kind_roots
EOF

  local doc_file
  while IFS= read -r doc_file; do
    [ -n "$doc_file" ] || continue
    check_count_consistency "$doc_file" || rc=1
  done < <(find "$project_root" -type f -name '*.md' 2>/dev/null | sort)

  if [ "$ledgers_checked" -eq 0 ]; then
    echo "[UNKNOWN] 根拠台帳が1件も見つからないため第1種・第3種・境界値の検査は判定不能です（未整備の設計単位: ${units_without_ledger}件）"
    return 2
  fi
  if [ "$units_without_ledger" -gt 0 ]; then
    echo "[UNKNOWN] 根拠台帳が未整備の設計単位が${units_without_ledger}件あり、これらは判定不能として検査対象から除外しました（代替入力は用意しません）"
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

SELF_TEST_DIRS=()

cleanup_self_test_dirs() {
  local dir
  for dir in "${SELF_TEST_DIRS[@]}"; do
    [ -n "$dir" ] || continue
    case "$dir" in
      "${TMPDIR:-/tmp}"/design-code-consistency-self-test.*)
        [ ! -e "$dir" ] || rm -rf -- "$dir"
        ;;
    esac
  done
}

self_test() {
  local pass=0 fail=0
  trap cleanup_self_test_dirs EXIT

  assert_eq() {
    local name="$1" want="$2" actual="$3"
    if [ "$want" = "$actual" ]; then
      echo "  [PASS] $name"
      pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*) echo "  [PASS] $name"; pass=$((pass + 1)) ;;
      *) echo "  [FAIL] ${name}（出力: ${haystack}）"; fail=$((fail + 1)) ;;
    esac
  }

  assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*) echo "  [FAIL] ${name}（出力: ${haystack}）"; fail=$((fail + 1)) ;;
      *) echo "  [PASS] $name"; pass=$((pass + 1)) ;;
    esac
  }

  new_tmp_dir() {
    local dir
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/design-code-consistency-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
      exit 2
    fi
    SELF_TEST_DIRS+=("$dir")
    printf '%s\n' "$dir"
  }

  write_layout_override() {
    cat > "$1/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "apiUnitRoot": "api" } }
JSON
  }

  write_ledger() {
    local file="$1" item="$2" target_code="$3" line_no="$4"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
---
unit_kind: api
unit_key: fixture
status: draft
---

# fixture 設計単位根拠台帳

本台帳は対象コードの位置を管理する。

| 対象文書 | 節 | 項目 | 対象コード | 行 |
|---|---|---|---|---|
| API詳細設計書.md | §9.2 業務判断 | ${item} | ${target_code} | ${line_no} |
EOF
  }

  # 検収1: 根拠台帳の項目の数値が対象コード:行に実在する→終了コード0。
  local tmp_1 unit_1 ledger_1 code_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  write_layout_override "$tmp_1"
  unit_1="$tmp_1/api/api-fixture"
  ledger_1="$unit_1/設計単位根拠台帳.md"
  mkdir -p "$tmp_1/source"
  code_1="$tmp_1/source/handler.py"
  {
    echo "def check_price(v):"
    echo "    LIMIT = 500"
    echo "    return v <= LIMIT"
  } > "$code_1"
  write_ledger "$ledger_1" "上限価格は500" "handler.py" 2
  out_1="$(run_check "$tmp_1" "$tmp_1/source")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_not_contains "検収1-定数値不一致は出ない" 'FAIL 定数値-不一致' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: 実装の定数を1つ変えると不合格になる。
  local tmp_2 unit_2 ledger_2 code_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  write_layout_override "$tmp_2"
  unit_2="$tmp_2/api/api-fixture"
  ledger_2="$unit_2/設計単位根拠台帳.md"
  mkdir -p "$tmp_2/source"
  code_2="$tmp_2/source/handler.py"
  {
    echo "def check_price(v):"
    echo "    LIMIT = 400"
    echo "    return v <= LIMIT"
  } > "$code_2"
  write_ledger "$ledger_2" "上限価格は500" "handler.py" 2
  out_2="$(run_check "$tmp_2" "$tmp_2/source")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-定数値不一致をFAIL" 'FAIL 定数値-不一致' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: 本文の件数と直後の表の実数が一致すれば終了コード0。
  # 第2種は根拠台帳が無くても走るが、run_check全体の判定不能(exit 2)を
  # 避けるため、検収対象外の該当なし台帳を1件添える。
  local tmp_3 doc_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  write_layout_override "$tmp_3"
  mkdir -p "$tmp_3/api/api-fixture"
  write_ledger "$tmp_3/api/api-fixture/設計単位根拠台帳.md" "確定できなかった事項" "該当なし" "該当なし"
  doc_3="$tmp_3/api/api-fixture/API詳細設計書.md"
  cat > "$doc_3" <<'DOC'
# 注文API API詳細設計書

対象は2個である。

| 名前 |
|---|
| a |
| b |
DOC
  out_3="$(run_check "$tmp_3" "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 0 "$rc_3"
  assert_not_contains "検収3-件数一致時はFAILしない" 'FAIL 件数不一致' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: 本文の件数を1つずらすと不合格になる。
  local tmp_4 doc_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  write_layout_override "$tmp_4"
  mkdir -p "$tmp_4/api/api-fixture"
  write_ledger "$tmp_4/api/api-fixture/設計単位根拠台帳.md" "確定できなかった事項" "該当なし" "該当なし"
  doc_4="$tmp_4/api/api-fixture/API詳細設計書.md"
  cat > "$doc_4" <<'DOC'
# 注文API API詳細設計書

対象は3個である。

| 名前 |
|---|
| a |
| b |
DOC
  out_4="$(run_check "$tmp_4" "$tmp_4")"; rc_4=$?
  assert_eq "検収4-終了コード" 1 "$rc_4"
  assert_contains "検収4-件数不一致をFAIL" 'FAIL 件数不一致' "$out_4"
  rm -rf "$tmp_4"

  # 検収5: 業務ルールの条件-構文的手掛かりが対象コード近傍にあれば合格。
  local tmp_5 unit_5 ledger_5 code_5 out_5
  tmp_5="$(new_tmp_dir)"
  write_layout_override "$tmp_5"
  unit_5="$tmp_5/api/api-fixture"
  ledger_5="$unit_5/設計単位根拠台帳.md"
  mkdir -p "$tmp_5/source"
  code_5="$tmp_5/source/handler.py"
  {
    echo "def check(v):"
    echo "    if v >= LOWER:"
    echo "        return True"
    echo "    return False"
  } > "$code_5"
  write_ledger "$ledger_5" "下限価格以上でなければならない" "handler.py" 2
  out_5="$(run_check "$tmp_5" "$tmp_5/source")"
  assert_not_contains "検収5-構文的手掛かりありは合格" 'FAIL 業務ルール-構文的手掛かりなし' "$out_5"
  rm -rf "$tmp_5"

  # 検収6: 業務ルールの条件-構文的手掛かりが無ければ不合格。
  local tmp_6 unit_6 ledger_6 code_6 out_6 rc_6
  tmp_6="$(new_tmp_dir)"
  write_layout_override "$tmp_6"
  unit_6="$tmp_6/api/api-fixture"
  ledger_6="$unit_6/設計単位根拠台帳.md"
  mkdir -p "$tmp_6/source"
  code_6="$tmp_6/source/handler.py"
  {
    echo "# 単なるコメント行"
    echo "value = 1"
    echo "result = value"
  } > "$code_6"
  write_ledger "$ledger_6" "下限価格以上でなければならない" "handler.py" 2
  out_6="$(run_check "$tmp_6" "$tmp_6/source")"; rc_6=$?
  assert_eq "検収6-終了コード" 1 "$rc_6"
  assert_contains "検収6-構文的手掛かりなしをFAIL" 'FAIL 業務ルール-構文的手掛かりなし' "$out_6"
  rm -rf "$tmp_6"

  # 検収7: 単体テスト設計書の境界値キーが詳細設計書の判定表に無ければ不合格。
  local tmp_7 unit_7 ledger_7 detail_7 test_7 out_7 rc_7
  tmp_7="$(new_tmp_dir)"
  write_layout_override "$tmp_7"
  unit_7="$tmp_7/api/api-fixture"
  ledger_7="$unit_7/設計単位根拠台帳.md"
  mkdir -p "$tmp_7/source"
  write_ledger "$ledger_7" "該当なし" "該当なし" "該当なし"
  detail_7="$unit_7/API詳細設計書.md"
  cat > "$detail_7" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

### 5.3 判定表

| キー | 入力の組み合わせ | 結果 |
|---|---|---|
| k1 | 在庫あり | 確定 |
DOC
  test_7="$unit_7/API単体テスト設計書.md"
  cat > "$test_7" <<'DOC'
# 注文API API単体テスト設計書

## §6 境界値

| キー | 関数・メソッド名 | 対象の引数・状態 | 境界の値 | 境界の直前と直後の扱い |
|---|---|---|---|---|
| k1 | doOrder | qty | 0 | 直前拒否・直後許可 |
| k2 | doOrder | qty | 100 | 直前許可・直後拒否 |
DOC
  out_7="$(run_check "$tmp_7" "$tmp_7/source")"; rc_7=$?
  assert_eq "検収7-終了コード" 1 "$rc_7"
  assert_contains "検収7-境界値キー不整合をFAIL" 'FAIL 境界値-キー不整合' "$out_7"
  assert_contains "検収7-未整合キーk2を報告" 'k2' "$out_7"
  assert_not_contains "検収7-整合済みキーk1は報告しない" 'キー「k1」' "$out_7"
  rm -rf "$tmp_7"

  # 追加回帰1: 根拠台帳が1件も無ければ[UNKNOWN]・終了コード2。
  local tmp_8 out_8 rc_8
  tmp_8="$(new_tmp_dir)"
  write_layout_override "$tmp_8"
  mkdir -p "$tmp_8/api/api-fixture" "$tmp_8/source"
  out_8="$(run_check "$tmp_8" "$tmp_8/source")"; rc_8=$?
  assert_eq "追加回帰1-根拠台帳0件は終了コード2" 2 "$rc_8"
  assert_contains "追加回帰1-UNKNOWNラベル" '[UNKNOWN]' "$out_8"
  rm -rf "$tmp_8"

  # 追加回帰2: 対象コード・行が「該当なし」の行は対象外として素通りする。
  local tmp_9 unit_9 ledger_9 out_9 rc_9
  tmp_9="$(new_tmp_dir)"
  write_layout_override "$tmp_9"
  unit_9="$tmp_9/api/api-fixture"
  ledger_9="$unit_9/設計単位根拠台帳.md"
  mkdir -p "$tmp_9/source"
  write_ledger "$ledger_9" "確定できなかった事項" "該当なし" "該当なし"
  out_9="$(run_check "$tmp_9" "$tmp_9/source")"; rc_9=$?
  assert_eq "追加回帰2-該当なし行は終了コード0" 0 "$rc_9"
  rm -rf "$tmp_9"

  # 追加回帰3: 定義ファイルが実在しJSONとして妥当である。
  local def_valid
  def_valid="$(jq -e '.categories | has("constantValue") and has("countConsistency") and has("businessRuleCondition") and has("boundaryValueConsistency")' \
    "$REPO_ROOT/delivery-payload/references/design-code-consistency.json" 2>/dev/null)"
  assert_eq "追加回帰3-定義ファイルが4種類を持つ" "true" "$def_valid"

  local mechanizable_3
  mechanizable_3="$(jq -r '.categories.businessRuleCondition.mechanizable' "$REPO_ROOT/delivery-payload/references/design-code-consistency.json")"
  assert_eq "追加回帰4-第3種はmechanizable=false" "false" "$mechanizable_3"

  # 追加回帰5: LC_ALL=C を明示していることを自己確認する。
  local locale_out
  locale_out="$(LC_ALL=en_US.UTF-8 bash -c 'export LC_ALL=C; echo "$LC_ALL"')"
  assert_eq "追加回帰5-LC_ALL=Cが有効" "C" "$locale_out"

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -ne 2 ]; then
    echo "使い方: $(basename "$0") <project_root> <source_dir>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1" "$2"
  exit $?
}

main "$@"
