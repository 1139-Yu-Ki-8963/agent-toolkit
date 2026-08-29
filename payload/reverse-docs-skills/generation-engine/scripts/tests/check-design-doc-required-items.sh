#!/usr/bin/env bash
# 詳細設計書がドキュメント作成規約上求める6項目（クラス設計・メソッド設計・
# ロジック設計・戻り値と引数・エラー処理・データ定義）の記載を検査する。
#
# design-doc-required-sections.json（節見出しの存在・順序）とは関心が異なる。
# 本検査は delivery-payload/references/design-doc-required-items.json が定める
# 「項目 → 章・節・表列」の対応に基づき、2段で判定する。
#   第1段: 対応する節が生成物に実在するか（置き場の存在）
#   第2段: その節の直後に現れる表にデータ行が1行以上あり、全データ行の
#          全セルが非空か（値の存在。規約が「不明点があってはならない」と
#          定めるため、空欄を許さない）
#
# applicable=false の項目・種別は検査対象外とし、reason を記録するのみ。
#
# 使い方:
#   check-design-doc-required-items.sh <project_root>
#   check-design-doc-required-items.sh --self-test
#
# 環境変数:
#   REQUIRED_ITEMS_FILE  項目定義JSONの差し替え先（自己テスト用）
#
# 終了コード:
#   0 = 欠落なし
#   1 = 置き場または値の欠落、入力不備、定義JSONの形式不正
#   2 = 判定不能（mktemp失敗。実行環境のサンドボックス制約等）
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEFAULT_ITEMS_FILE="$REPO_ROOT/delivery-payload/references/design-doc-required-items.json"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

# output-layout.jsonのキーと項目定義で使う種別名の対応。
KIND_ROOTS="screenUnitRoot:screen apiUnitRoot:api tableUnitRoot:table batchUnitRoot:batch reportUnitRoot:report externalUnitRoot:external featureUnitRoot:feature"

items_file() {
  printf '%s\n' "${REQUIRED_ITEMS_FILE:-$DEFAULT_ITEMS_FILE}"
}

# 定義JSONの形式をfail closedで検証する。
validate_items_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: 必須項目定義ファイルが存在しません: $file" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to read the required-items definition" >&2
    return 1
  fi
  if ! jq -e '
    . as $root
    | ["screen", "api", "table", "batch", "report", "external", "feature"] as $kinds
    |
    .schemaVersion == 1 and
    (.requiredItems | type == "array") and (.requiredItems | length > 0) and
    (.documentTypes | type == "object") and
    ($kinds | all(. as $kind | ($root.documentTypes[$kind] | type == "object"))) and
    (
      [$root.documentTypes | to_entries[] | .value | to_entries[] | .value] as $docs
      | $docs | all(
          . as $doc
          | ($doc | type == "object") and
          (
            ($doc.applicable == false and ($doc.reason | type == "string") and ($doc.reason | length > 0))
            or
            (
              ($doc.items | type == "object") and
              ($root.requiredItems | all(. as $item
                | ($doc.items[$item]) as $entry
                | ($entry | type == "object") and
                  (
                    ($entry.applicable == false and ($entry.reason | type == "string") and ($entry.reason | length > 0))
                    or
                    ($entry.applicable == true and ($entry.sections | type == "array") and ($entry.sections | length > 0)
                      and ($entry.requiredColumns | type == "array") and ($entry.requiredColumns | length > 0))
                  )
              ))
            )
          )
        )
    )
  ' "$file" >/dev/null; then
    echo "ERROR: 必須項目定義ファイルの形式が不正です: $file" >&2
    return 1
  fi
}

# 対象ルート一覧（種別名<TAB>絶対パス。実在するものだけ）を返す。
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

doc_type_entry() {
  local file="$1" kind="$2" basename="$3"
  jq -c --arg kind "$kind" --arg basename "$basename" '.documentTypes[$kind][$basename]' "$file"
}

# 見出し行（## 〜 #### の行）から見出しテキストのみを取り出す。
_heading_text() {
  sed -E 's/^#{2,4} //'
}

# 見出し文字列が本文中に実在するかを確認し、実在すれば1を返す（0=不在）。
heading_exists() {
  local doc_file="$1" heading="$2"
  grep -q -F -x "## ${heading}" "$doc_file" 2>/dev/null && return 0
  grep -q -F -x "### ${heading}" "$doc_file" 2>/dev/null && return 0
  grep -q -F -x "#### ${heading}" "$doc_file" 2>/dev/null && return 0
  return 1
}

# heading の直後（次の見出し行まで）の本文を返す。
_body_after_heading() {
  local doc_file="$1" heading="$2"
  awk -v heading="$heading" '
    BEGIN { found = 0 }
    /^#{2,4} / {
      htext = $0
      sub(/^#{2,4} /, "", htext)
      if (found) { exit }
      if (htext == heading) { found = 1; next }
      next
    }
    found { print }
  ' "$doc_file"
}

# 本文の先頭付近に、ヘッダー行+区切り行を持つ表があるかを判定する。
# 表があれば "found" を出力する（無ければ何も出力しない）。
_has_table() {
  awk '
    BEGIN { state = 0 }
    /^\|.*\|[[:space:]]*$/ {
      if (state == 0) { state = 1; next }
      if (state == 1 && $0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { print "found"; exit }
      state = 0
      next
    }
    { state = 0 }
  '
}

# 直後の本文から最初の表（ヘッダー行+区切り行+0行以上のデータ行）を検出し、
# データ行（ヘッダー・区切りを除く | 区切り行）を1行1レコードで返す。
# 表が無い、または表はあるがデータ行が0件の場合は何も出力しない。
_first_table_data_rows() {
  awk '
    BEGIN { state = 0 }
    /^\|.*\|[[:space:]]*$/ {
      if (state == 0) { header = $0; state = 1; next }
      if (state == 1 && $0 ~ /^\|[|: -]+\|[[:space:]]*$/ && $0 ~ /---/) { state = 2; next }
      if (state == 2) { print; next }
      if (state == 1) { state = 0 }
      next
    }
    {
      if (state == 2) { exit }
      state = 0
    }
  '
}

# 表のデータ行群のうち、いずれかのセルが空（空白のみ含む）の行があれば1を返す。
_has_empty_cell() {
  awk -F'|' '
    {
      for (i = 2; i < NF; i++) {
        cell = $i
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell == "") { print "EMPTY"; exit }
      }
    }
  '
}

# 文書内の「非該当項目」宣言に、対象の節が理由付きで挙がっているかを判定する。
# 宣言の形式（31箇所の実測に基づく）:
#   > 非該当項目: §14.1 ユーザー入力チェック（入力フォームを持たない画面のため）
#   複数はセミコロン区切り。丸括弧の理由が無いものは認めない（理由なしの逃げ道を塞ぐため）。
# 標準出力: 認める場合のみ理由を出力する。
#
# 実装判断（ロケール）: 全角括弧を含む正規表現によるパターン抽出のため
# LC_ALL=en_US.UTF-8 を都度明示する。LC_ALL=C の下では awk の match() が
# 負の文字クラスに含む全角文字を認識できず、常に0件になる
# （.claude/rules/always/design-record/implementation-decision/rule.md「ロケールの使い分け」既定2）。
non_applicable_reason() {
  local doc_file="$1" heading="$2" key
  # 見出しから節番号の部分だけを取り出す（"### 14.1 ユーザー入力チェック" → "14.1"）
  key="$(printf '%s' "$heading" | sed -E 's/^#+[[:space:]]*//; s/^§//; s/^([0-9]+(\.[0-9]+)*).*/\1/')"
  [ -n "$key" ] || return 1
  LC_ALL=en_US.UTF-8 awk -v key="$key" '
    /非該当項目/ {
      n = split($0, parts, /;/)
      for (i = 1; i <= n; i++) {
        seg = parts[i]
        if (index(seg, "§" key) == 0) continue
        # 節番号の直後が数字（14.1 に対する 14.10 等）なら別の節として扱う
        pos = index(seg, "§" key) + length("§" key)
        nxt = substr(seg, pos, 1)
        if (nxt ~ /[0-9.]/) continue
        if (match(seg, /（[^（）]+）/)) {
          print substr(seg, RSTART, RLENGTH)
          found = 1
          exit
        }
      }
    }
    END { if (!found) exit 1 }
  ' "$doc_file"
}

# sections配列の中から「直後に表を持つ最初の見出し」を選び、その見出しと
# 見出し不在フラグ・表なしフラグ・空セルフラグを呼び出し側へ返す。
# 標準出力: "<status>\t<heading>"
#   status: missing（全見出しが不在）/ no-table（見出しはあるが表を持つものが無い）
#           / ok（表があり全行非空）/ empty（表はあるが空セルがある）
resolve_item_status() {
  local doc_file="$1" sections_json="$2"
  local heading found_any=0 has_table_any=0 table_body has_table rows
  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    if ! heading_exists "$doc_file" "$heading"; then
      continue
    fi
    found_any=1
    table_body="$(_body_after_heading "$doc_file" "$heading")"
    has_table="$(printf '%s\n' "$table_body" | _has_table)"
    if [ -z "$has_table" ]; then
      if non_applicable_reason "$doc_file" "$heading" >/dev/null 2>&1; then
        printf 'ok\t%s\n' "$heading"
        return 0
      fi
      continue
    fi
    has_table_any=1
    rows="$(printf '%s\n' "$table_body" | _first_table_data_rows)"
    if [ -z "$rows" ]; then
      printf 'empty\t%s\n' "$heading"
      return 0
    fi
    if printf '%s\n' "$rows" | _has_empty_cell | grep -q EMPTY; then
      printf 'empty\t%s\n' "$heading"
      return 0
    fi
    printf 'ok\t%s\n' "$heading"
    return 0
  done < <(printf '%s' "$sections_json" | jq -r '.[]')

  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    if non_applicable_reason "$doc_file" "$heading" >/dev/null 2>&1; then
      printf 'ok\t%s\n' "$heading"
      return 0
    fi
  done < <(printf '%s' "$sections_json" | jq -r '.[]')

  if [ "$found_any" -eq 0 ]; then
    printf 'missing\t\n'
  elif [ "$has_table_any" -eq 0 ]; then
    printf 'no-table\t\n'
  else
    printf 'empty\t\n'
  fi
}

check_document() {
  local items_json="$1" kind="$2" basename="$3" doc_file="$4"
  local entry applicable reason item item_entry item_applicable item_reason \
    sections status heading rc=0

  entry="$(doc_type_entry "$items_json" "$kind" "$basename")"
  # jqの `//` は左辺が false/null の両方でフォールバックするため使わない
  # （applicable:false を誤って true に落としてしまう）。明示比較で判定する。
  applicable="$(printf '%s' "$entry" | jq -r 'if .applicable == false then "false" else "true" end')"
  if [ "$applicable" = "false" ]; then
    return 0
  fi

  while IFS= read -r item; do
    [ -n "$item" ] || continue
    item_entry="$(printf '%s' "$entry" | jq -c --arg item "$item" '.items[$item]')"
    item_applicable="$(printf '%s' "$item_entry" | jq -r '.applicable')"
    if [ "$item_applicable" = "false" ]; then
      continue
    fi
    sections="$(printf '%s' "$item_entry" | jq -c '.sections')"
    status="$(resolve_item_status "$doc_file" "$sections")"
    heading="${status#*$'\t'}"
    status="${status%%$'\t'*}"
    case "$status" in
      missing)
        echo "FAIL 必須項目-置き場欠落 ${doc_file}: 種別（${kind}/${basename}）の項目「${item}」に対応する節が無い"
        rc=1
        ;;
      no-table)
        echo "FAIL 必須項目-表欠落 ${doc_file}: 種別（${kind}/${basename}）の項目「${item}」の節は存在するが表を持たない"
        rc=1
        ;;
      empty)
        echo "FAIL 必須項目-値欠落 ${doc_file}: 種別（${kind}/${basename}）の項目「${item}」の表に記入がない、または空欄の行がある"
        rc=1
        ;;
      ok) ;;
    esac
  done < <(jq -r '.requiredItems[]' "$items_json")
  return "$rc"
}

run_check() {
  local project_root="$1" items_json_file kind_roots rc=0 checked_count=0
  items_json_file="$(items_file)"

  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  validate_items_file "$items_json_file" || return 1
  kind_roots="$(resolve_kind_roots "$project_root")" || return 1

  local kind kind_root file basename
  while IFS=$'\t' read -r kind kind_root; do
    [ -n "$kind_root" ] || continue
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      basename="$(basename "$file")"
      if ! jq -e --arg kind "$kind" --arg basename "$basename" \
        '.documentTypes[$kind][$basename]? | type == "object"' "$items_json_file" >/dev/null; then
        continue
      fi
      checked_count=$((checked_count + 1))
      check_document "$items_json_file" "$kind" "$basename" "$file" || rc=1
    done < <(find "$kind_root" -type f -name '*.md' 2>/dev/null | sort)
  done <<EOF
$kind_roots
EOF

  if [ "$checked_count" -eq 0 ]; then
    echo "ERROR: 検査対象の設計文書が0件です: project_root=$project_root" >&2
    return 1
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
      "${TMPDIR:-/tmp}"/design-doc-required-items-self-test.*)
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
      *"$needle"*)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
      *)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
    esac
  }

  assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
      *"$needle"*)
        echo "  [FAIL] ${name}（出力: ${haystack}）"
        fail=$((fail + 1))
        ;;
      *)
        echo "  [PASS] $name"
        pass=$((pass + 1))
        ;;
    esac
  }

  # 判定不能規約: mktemp の失敗を対象の不合格と区別する。
  new_tmp_dir() {
    local dir
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/design-doc-required-items-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
      exit 2
    fi
    SELF_TEST_DIRS+=("$dir")
    printf '%s\n' "$dir"
  }

  write_layout_override() {
    mkdir -p "$1/api"
    cat > "$1/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "apiUnitRoot": "api" } }
JSON
  }

  write_items_def() {
    cat > "$1" <<'JSON'
{
  "schemaVersion": 1,
  "requiredItems": ["クラス設計", "メソッド設計"],
  "documentTypes": {
    "screen": {},
    "api": {
      "API詳細設計書.md": {
        "items": {
          "クラス設計": {
            "applicable": true,
            "sections": ["12.1 関数と役割"],
            "requiredColumns": ["関数", "役割"]
          },
          "メソッド設計": {
            "applicable": false,
            "reason": "自己テスト用の対象外項目"
          }
        }
      }
    },
    "table": {},
    "batch": {},
    "report": {},
    "external": {},
    "feature": {
      "機能設計書.md": {
        "applicable": false,
        "reason": "自己テスト用の対象外種別"
      }
    }
  }
}
JSON
  }

  write_api_doc() {
    local file="$1" body="$2"
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$body" > "$file"
  }

  # 検収1: 全項目の置き場と値が揃った合成フィクスチャは exit 0・出力0件。
  local tmp_1 def_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  def_1="$tmp_1/items.json"
  write_layout_override "$tmp_1"; write_items_def "$def_1"
  write_api_doc "$tmp_1/api/A/API詳細設計書.md" '## §12 実装契約

### 12.1 関数と役割

| 関数 | 役割 |
|---|---|
| doOrder | 注文を確定する |
'
  out_1="$(REQUIRED_ITEMS_FILE="$def_1" run_check "$tmp_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_eq "検収1-出力0件" '' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: 対応する節そのものが無い（1項目の置き場を削った）合成フィクスチャは不合格。
  local tmp_2 def_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  def_2="$tmp_2/items.json"
  write_layout_override "$tmp_2"; write_items_def "$def_2"
  write_api_doc "$tmp_2/api/A/API詳細設計書.md" '## §12 実装契約

### 12.9 無関係な節

本文
'
  out_2="$(REQUIRED_ITEMS_FILE="$def_2" run_check "$tmp_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-置き場欠落をFAIL" 'FAIL 必須項目-置き場欠落' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: 節はあるが表の値が空の合成フィクスチャは不合格。
  local tmp_3 def_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  def_3="$tmp_3/items.json"
  write_layout_override "$tmp_3"; write_items_def "$def_3"
  write_api_doc "$tmp_3/api/A/API詳細設計書.md" '## §12 実装契約

### 12.1 関数と役割

| 関数 | 役割 |
|---|---|
| doOrder |  |
'
  out_3="$(REQUIRED_ITEMS_FILE="$def_3" run_check "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 1 "$rc_3"
  assert_contains "検収3-値欠落をFAIL" 'FAIL 必須項目-値欠落' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: 節はあるが表そのものが無い場合も不合格。
  local tmp_4 def_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  def_4="$tmp_4/items.json"
  write_layout_override "$tmp_4"; write_items_def "$def_4"
  write_api_doc "$tmp_4/api/A/API詳細設計書.md" '## §12 実装契約

### 12.1 関数と役割

本文のみで表が無い
'
  out_4="$(REQUIRED_ITEMS_FILE="$def_4" run_check "$tmp_4")"; rc_4=$?
  assert_eq "検収4-終了コード" 1 "$rc_4"
  assert_contains "検収4-表欠落をFAIL" 'FAIL 必須項目-表欠落' "$out_4"
  rm -rf "$tmp_4"

  # 検収5: applicable=false の項目・種別はスキップされ、他が揃っていれば exit 0。
  local tmp_5 def_5 out_5 rc_5
  tmp_5="$(new_tmp_dir)"
  def_5="$tmp_5/items.json"
  write_layout_override "$tmp_5"; write_items_def "$def_5"
  write_api_doc "$tmp_5/api/A/API詳細設計書.md" '## §12 実装契約

### 12.1 関数と役割

| 関数 | 役割 |
|---|---|
| doOrder | 注文を確定する |
'
  mkdir -p "$tmp_5/feature"
  write_api_doc "$tmp_5/feature/F/機能設計書.md" '本文のみ'
  out_5="$(REQUIRED_ITEMS_FILE="$def_5" run_check "$tmp_5")"; rc_5=$?
  assert_eq "検収5-終了コード" 0 "$rc_5"
  assert_eq "検収5-出力0件" '' "$out_5"
  rm -rf "$tmp_5"

  # 追加回帰1: 定義JSONの構造をfail closedで検証する（applicable宣言の欠落等）。
  local tmp_val def_val
  tmp_val="$(new_tmp_dir)"
  def_val="$tmp_val/items.json"
  write_items_def "$def_val"
  jq 'del(.documentTypes.screen)' "$def_val" > "$tmp_val/kind-missing.json"
  jq '.documentTypes.api["API詳細設計書.md"].items."クラス設計".sections = []' "$def_val" > "$tmp_val/sections-empty.json"
  jq '.documentTypes.api["API詳細設計書.md"].items."クラス設計" |= del(.applicable)' "$def_val" > "$tmp_val/applicable-missing.json"
  jq '.documentTypes.feature."機能設計書.md" |= del(.reason)' "$def_val" > "$tmp_val/reason-missing.json"
  local rc_kind_missing rc_sections_empty rc_applicable_missing rc_reason_missing
  validate_items_file "$tmp_val/kind-missing.json" >/dev/null 2>&1; rc_kind_missing=$?
  validate_items_file "$tmp_val/sections-empty.json" >/dev/null 2>&1; rc_sections_empty=$?
  validate_items_file "$tmp_val/applicable-missing.json" >/dev/null 2>&1; rc_applicable_missing=$?
  validate_items_file "$tmp_val/reason-missing.json" >/dev/null 2>&1; rc_reason_missing=$?
  assert_eq "追加回帰1-種別欠落を拒否" 1 "$rc_kind_missing"
  assert_eq "追加回帰1-sections空配列を拒否" 1 "$rc_sections_empty"
  assert_eq "追加回帰1-applicable欠落を拒否" 1 "$rc_applicable_missing"
  assert_eq "追加回帰1-reason欠落を拒否" 1 "$rc_reason_missing"
  rm -rf "$tmp_val"

  # 追加回帰2: 実物の定義ファイル（design-doc-required-items.json）自体が形式適合する。
  local rc_real
  validate_items_file "$DEFAULT_ITEMS_FILE" >/dev/null 2>&1; rc_real=$?
  assert_eq "追加回帰2-実物定義ファイルの形式適合" 0 "$rc_real"

  # 追加回帰3: 実物定義ファイルが6種別すべて（feature含む）を持つ。
  local kinds_present
  kinds_present="$(jq -r '.documentTypes | keys | sort | join(",")' "$DEFAULT_ITEMS_FILE")"
  assert_eq "追加回帰3-6種別すべての定義存在" "api,batch,external,feature,report,screen,table" "$kinds_present"

  # 追加回帰4: 実物定義ファイルで画面のメソッド設計だけが applicable=false・理由に1-190を含む。
  local screen_method_applicable screen_method_reason
  screen_method_applicable="$(jq -r '.documentTypes.screen."画面詳細設計書.md".items."メソッド設計".applicable' "$DEFAULT_ITEMS_FILE")"
  screen_method_reason="$(jq -r '.documentTypes.screen."画面詳細設計書.md".items."メソッド設計".reason' "$DEFAULT_ITEMS_FILE")"
  assert_eq "追加回帰4-画面メソッド設計はapplicable false" "false" "$screen_method_applicable"
  assert_contains "追加回帰4-理由に1-190を参照" "1-190" "$screen_method_reason"

  # 追加回帰5: 実物のAPI詳細設計書テンプレート（プレースホルダのみで値が空）は、
  # 節・表の置き場は実在するため「置き場欠落」にはならず、値が空のため
  # 「値欠落」でFAILになる。テンプレート自身が意図的に空欄であることの確認。
  local tmp_real out_real rc_real_doc
  tmp_real="$(new_tmp_dir)"
  cat > "$tmp_real/output-layout.json" <<JSON
{
  "specVersion": 1,
  "layout": {
    "screenUnitRoot": "screen",
    "apiUnitRoot": "api",
    "tableUnitRoot": "table",
    "batchUnitRoot": "batch",
    "reportUnitRoot": "report",
    "externalUnitRoot": "external",
    "featureUnitRoot": "feature"
  }
}
JSON
  mkdir -p "$tmp_real/api/fixture"
  cp "$REPO_ROOT/delivery-payload/templates/リバース検証/API/API詳細設計書.md" "$tmp_real/api/fixture/API詳細設計書.md"
  out_real="$(run_check "$tmp_real")"; rc_real_doc=$?
  assert_eq "追加回帰5-空テンプレートは値欠落で終了コード1" 1 "$rc_real_doc"
  assert_contains "追加回帰5-置き場欠落は起きない" 'FAIL 必須項目-値欠落' "$out_real"
  assert_not_contains "追加回帰5-置き場欠落メッセージは出ない" 'FAIL 必須項目-置き場欠落' "$out_real"
  rm -rf "$tmp_real"

  # 追加回帰7: 実物の定義ファイル（6項目・6種別）を使い、API種別の6項目すべての
  # 置き場に実データを1行ずつ持つ合成文書は終了コード0・出力0件になる。
  local tmp_filled out_filled rc_filled
  tmp_filled="$(new_tmp_dir)"
  cat > "$tmp_filled/output-layout.json" <<JSON
{
  "specVersion": 1,
  "layout": {
    "screenUnitRoot": "screen",
    "apiUnitRoot": "api",
    "tableUnitRoot": "table",
    "batchUnitRoot": "batch",
    "reportUnitRoot": "report",
    "externalUnitRoot": "external",
    "featureUnitRoot": "feature"
  }
}
JSON
  mkdir -p "$tmp_filled/api/fixture"
  cat > "$tmp_filled/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §2 リクエスト

| 名前 | 型 | 必須 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 制約 |
|---|---|---|---|---|---|---|---|
| orderId | string | 必須 | 1-64文字 | 不可 | なし | 固定長 | UUID |

## §3 レスポンス

### 3.1 正常系の構造

| 項目 | 型 | 常に存在 | 有効な範囲 | NULL許容 | 初期値 | 桁と精度 | 意味 |
|---|---|---|---|---|---|---|---|
| status | string | 必須 | ok/ng | 不可 | なし | 固定長 | 結果 |

## §5 ロジック

### 5.1 分岐

| キー | 条件 | 真の場合 | 偽の場合 |
|---|---|---|---|
| k1 | 在庫あり | 確定 | 拒否 |

## §7 エラー

### 7.1 エラー一覧

| キー | 発生条件 | 応答コード | 利用者に見える結果 |
|---|---|---|---|
| e1 | 在庫不足 | 409 | 在庫不足エラー |
DOC
  cat > "$tmp_filled/api/fixture/API実装記録.md" <<'DOC'
# 注文API API実装記録

## §3 データ定義

### 3.1 内部データ構造

| 名前 | 型 | 構成要素 | 組み立てる箇所 | 用途 | 有効な範囲 | 寿命 |
|---|---|---|---|---|---|---|
| OrderCtx | struct | id,status | handler | 内部処理 | リクエスト内 | リクエスト単位 |

## §4 実装契約

### 4.1 関数と役割

| 関数 | 役割 |
|---|---|
| doOrder | 注文を確定する |

### 4.2 関数単位の契約

| 関数 | 公開範囲 | 引数 | 戻り値 | 前提条件 | 副作用 | 例外・エラー |
|---|---|---|---|---|---|---|
| doOrder | public | orderId | Order | 認証済み | 在庫を減らす | InvalidOrder |
DOC
  out_filled="$(run_check "$tmp_filled")"; rc_filled=$?
  assert_eq "追加回帰7-実データ充足済み合成文書は終了コード0" 0 "$rc_filled"
  assert_eq "追加回帰7-実データ充足済み合成文書は出力0件" '' "$out_filled"
  rm -rf "$tmp_filled"

  # 追加回帰6: LC_ALL=C を明示していることを自己確認する（実行環境ロケール非依存）。
  local locale_out
  locale_out="$(LC_ALL=en_US.UTF-8 bash -c 'export LC_ALL=C; echo "$LC_ALL"')"
  assert_eq "追加回帰6-LC_ALL=Cが有効" "C" "$locale_out"

  # 追加回帰8: 実物定義ファイルでは feature（機能設計書）は applicable:false が
  # トップレベルにあるため、jqの `//` フォールバックの罠（false//true→true化）で
  # 誤って検査対象になっていないかを確認する。プレースホルダのみの機能設計書を
  # 実物定義で検査しても「置き場欠落」が1件も出ないこと（=正しくスキップされて
  # いること）を見る。
  local tmp_feature out_feature rc_feature feature_fail_count
  tmp_feature="$(new_tmp_dir)"
  cat > "$tmp_feature/output-layout.json" <<JSON
{ "specVersion": 1, "layout": { "featureUnitRoot": "feature" } }
JSON
  mkdir -p "$tmp_feature/feature/fixture"
  cp "$REPO_ROOT/delivery-payload/templates/リバース検証/機能/機能設計書.md" "$tmp_feature/feature/fixture/機能設計書.md"
  out_feature="$(run_check "$tmp_feature")"; rc_feature=$?
  assert_eq "追加回帰8-機能設計書は終了コード0" 0 "$rc_feature"
  feature_fail_count="$(printf '%s\n' "$out_feature" | grep -c '^FAIL' || true)"
  assert_eq "追加回帰8-機能設計書のFAILは0件" 0 "$feature_fail_count"
  rm -rf "$tmp_feature"

  # 追加回帰9: 「非該当項目」の宣言（理由を丸括弧で伴うもの）を持つ節は、
  # 表を持たなくても合格とする。理由の無い宣言は認めない（逃げ道を作らないため）。
  # この宣言は見本・テンプレートで31箇所に使われている確立した方式であり、
  # 検査が読まないと理由付きで正しく非該当を宣言した文書まで不合格になる。
  local tmp_na out_na rc_na
  tmp_na="$(new_tmp_dir)"
  cat > "$tmp_na/output-layout.json" <<JSON
{ "specVersion": 1, "layout": { "screenUnitRoot": "screen" } }
JSON
  mkdir -p "$tmp_na/screen/fixture"
  cp "$REPO_ROOT/generation-engine/samples/docs/design/screens/screen-home/詳細設計/画面詳細設計書.md" \
     "$tmp_na/screen/fixture/画面詳細設計書.md"
  out_na="$(run_check "$tmp_na")"; rc_na=$?
  assert_eq "追加回帰9-理由付き非該当宣言は終了コード0" 0 "$rc_na"
  assert_not_contains "追加回帰9-表欠落は出ない" 'FAIL 必須項目-表欠落' "$out_na"

  # 理由の丸括弧を削ると、非該当として認めず表欠落でFAILになること
  LC_ALL=en_US.UTF-8 perl -i -pe 's/（入力フォームを持たない画面のため）//' \
    "$tmp_na/screen/fixture/画面詳細設計書.md"
  out_na="$(run_check "$tmp_na")"; rc_na=$?
  assert_eq "追加回帰9-理由なし宣言は終了コード1" 1 "$rc_na"
  assert_contains "追加回帰9-理由なし宣言は表欠落でFAIL" 'FAIL 必須項目-表欠落' "$out_na"
  rm -rf "$tmp_na"

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "$#" -ne 1 ]; then
    echo "使い方: $(basename "$0") <project_root>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1"
  exit $?
}

main "$@"
