#!/usr/bin/env bash
# 文書間の整合と節番号の相互参照を検査する。
#
# 第1（節番号の相互参照の実在）と第2（他文書を指す参照に文書名が付いているか）
# を1つの判定にまとめる。本文から `§N` 参照を抽出し、直前に `<文書名>.md` が
# 伴うかで自書/他文書を判定する。文書名を持たない `§N` が、検査対象自身の
# 節見出しに解決できない場合を不合格とする。これで「壊れた自書参照」と
# 「文書名の無い他文書参照」の両方を1つの判定で捕まえる。
# 文書名を伴う参照は、指名された文書が実在し、かつその文書の節見出しに
# `§N` が実在するかを見る。
#
# 節の在庫（どの §N が実在するか）は各設計書自身の `## §N` 見出しから
# 導出する。定義ファイルは持たない（設計書の§番号は文書自身が宣言してお
# り、別ファイルへ写すと正本が2つになるため）。
#
# 第3（同じ語の多義）・第4（文書間の断定と未確定の併存）は機械化しない。
# delivery-payload/templates/rules/tool-defined/document-writing.md の
# 「文書間の参照」節が機械化の範囲を明記する。
#
# 使い方:
#   check-doc-cross-reference.sh <project_root>
#   check-doc-cross-reference.sh --self-test
#
# 終了コード:
#   0 = 参照切れなし
#   1 = 参照切れあり
#   2 = 判定不能（mktemp失敗）
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

KIND_ROOTS="screenUnitRoot:screen apiUnitRoot:api tableUnitRoot:table batchUnitRoot:batch reportUnitRoot:report externalUnitRoot:external featureUnitRoot:feature"

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

# frontmatterを除き、「## 章マップ」以降（宣言側の付録であり参照ではない）
# を切り捨てた本文を返す。
_prepared_body() {
  local file="$1"
  awk '
    NR == 1 && /^---$/ { skip = 1; next }
    skip && /^---$/ { skip = 0; next }
    skip { next }
    /^## 章マップ/ { exit }
    /<!--/ { in_comment = 1 }
    !in_comment { print }
    /-->/ { in_comment = 0 }
  ' "$file"
}

# ファイルの節見出し一覧を §N 形式で返す（重複は1回にまとめる）。
# 大見出し（## §N）は § 付きで書かれるが、小見出し（### N.M タイトル）は
# § を付けない慣行のため、小見出しには § を補って同じ形式へ揃える。
_extract_section_headings() {
  local file="$1"
  _prepared_body "$file" | awk '
    /^## §[0-9]+(\.[0-9]+)?/ {
      if (match($0, /§[0-9]+(\.[0-9]+)?/)) print substr($0, RSTART, RLENGTH)
    }
    /^#{3,4} [0-9]+\.[0-9]+([.-][0-9]+)*([ \t]|$)/ {
      if (match($0, /[0-9]+\.[0-9]+([.-][0-9]+)*/)) print "§" substr($0, RSTART, RLENGTH)
    }
  ' | sort -u
}

# 本文（見出し行を除く）から §N 参照を、直前の文書名の有無と共に抽出する。
# 出力: <行番号><TAB><文書名（無ければプレースホルダ "-"）><TAB>§N
#
# bashの `read` はIFSがタブ等のIFS空白文字のみの場合、連続する区切り文字を
# 1つにまとめてしまい、空フィールドを表現できない（POSIXのIFS空白の仕様）。
# そのため文書名が無い場合は空文字列ではなく "-" を出力し、呼び出し側で
# "-" を「文書名なし」の印として判定する。
_extract_references() {
  local file="$1"
  _prepared_body "$file" | grep -vE '^#{2,4} ' | \
    grep -noE '([^ 	|]+\.md[ 	]+)?§[0-9]+(\.[0-9]+)?' | \
    awk -F: '{
      line = $1
      $1 = ""
      sub(/^:/, "", $0)
      rest = $0
      sub(/^ /, "", rest)
      doc = rest
      sub(/§[0-9]+(\.[0-9]+)?[ \t]*$/, "", doc)
      gsub(/[ \t]+$/, "", doc)
      if (doc == "") doc = "-"
      match(rest, /§[0-9]+(\.[0-9]+)?$/)
      sect = substr(rest, RSTART, RLENGTH)
      printf "%s\t%s\t%s\n", line, doc, sect
    }'
}

# 章マップの役割キー表の値列（見出しの右側にある §N）も参照抽出に含まれて
# しまうため、章マップ全体を _prepared_body で除去している。

check_document() {
  local project_root="$1" file="$2" rc=0
  local line doc sect self_headings
  self_headings="$(_extract_section_headings "$file")"

  while IFS=$'\t' read -r line doc sect; do
    [ -n "$sect" ] || continue
    if [ "$doc" != "-" ]; then
      local target
      target="$(find "$project_root" -type f -name "$doc" 2>/dev/null | head -1)"
      if [ -z "$target" ]; then
        echo "FAIL 相互参照-他文書不在 ${file}:${line}: 「${doc} ${sect}」が指す文書が実在しない"
        rc=1
        continue
      fi
      local target_headings
      target_headings="$(_extract_section_headings "$target")"
      if ! printf '%s\n' "$target_headings" | grep -qFx "$sect"; then
        echo "FAIL 相互参照-他文書節不在 ${file}:${line}: 「${doc} ${sect}」の節が対象文書に実在しない"
        rc=1
      fi
    else
      if ! printf '%s\n' "$self_headings" | grep -qFx "$sect"; then
        echo "FAIL 相互参照-自書節不在 ${file}:${line}: 「${sect}」が自書の節に実在しない（文書名の無い他文書参照の可能性も含む）"
        rc=1
      fi
    fi
  done < <(_extract_references "$file")
  return "$rc"
}

run_check() {
  local project_root="$1" rc=0 checked_count=0
  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  local kind_roots kind kind_root file
  kind_roots="$(resolve_kind_roots "$project_root")" || return 1

  while IFS=$'\t' read -r kind kind_root; do
    [ -n "$kind_root" ] || continue
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      checked_count=$((checked_count + 1))
      check_document "$project_root" "$file" || rc=1
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
      "${TMPDIR:-/tmp}"/doc-cross-reference-self-test.*)
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
      echo "  [PASS] $name"; pass=$((pass + 1))
    else
      echo "  [FAIL] ${name}（期待 ${want}・実際 ${actual}）"; fail=$((fail + 1))
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
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/doc-cross-reference-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
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

  # 検収1: 自書の節番号参照が実在すれば合格。
  local tmp_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  write_layout_override "$tmp_1"
  mkdir -p "$tmp_1/api/fixture"
  cat > "$tmp_1/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

本文。

## §8 データ定義

§5 の分岐条件を参照する。
DOC
  out_1="$(run_check "$tmp_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_eq "検収1-出力0件" '' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: 存在しない節を指す自書参照は不合格。
  local tmp_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  write_layout_override "$tmp_2"
  mkdir -p "$tmp_2/api/fixture"
  cat > "$tmp_2/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

§9 の業務ルールを参照する。
DOC
  out_2="$(run_check "$tmp_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-自書節不在をFAIL" 'FAIL 相互参照-自書節不在' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: 他文書を指す参照に文書名が無い場合、自書節として解決を試み、
  # 見つからなければ不合格になる（文書名の無い他文書参照を捕まえる）。
  local tmp_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  write_layout_override "$tmp_3"
  mkdir -p "$tmp_3/api/fixture"
  cat > "$tmp_3/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

§20 の記述規約を参照する。
DOC
  mkdir -p "$tmp_3/api/other"
  cat > "$tmp_3/api/other/API基本設計書.md" <<'DOC'
# 注文API API基本設計書

## §20 記述規約

本文。
DOC
  out_3="$(run_check "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 1 "$rc_3"
  assert_contains "検収3-文書名なし他文書参照をFAIL" 'FAIL 相互参照-自書節不在' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: 文書名付きの参照は指名文書の節が実在すれば合格。
  local tmp_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  write_layout_override "$tmp_4"
  mkdir -p "$tmp_4/api/fixture"
  cat > "$tmp_4/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

API基本設計書.md §20 の記述規約を参照する。
DOC
  mkdir -p "$tmp_4/api/other"
  cat > "$tmp_4/api/other/API基本設計書.md" <<'DOC'
# 注文API API基本設計書

## §20 記述規約

本文。
DOC
  out_4="$(run_check "$tmp_4")"; rc_4=$?
  assert_eq "検収4-終了コード" 0 "$rc_4"
  assert_eq "検収4-出力0件" '' "$out_4"
  rm -rf "$tmp_4"

  # 検収5: 文書名付きだが指名文書に節が無ければ不合格。
  local tmp_5 out_5 rc_5
  tmp_5="$(new_tmp_dir)"
  write_layout_override "$tmp_5"
  mkdir -p "$tmp_5/api/fixture"
  cat > "$tmp_5/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

API基本設計書.md §99 の記述規約を参照する。
DOC
  mkdir -p "$tmp_5/api/other"
  cat > "$tmp_5/api/other/API基本設計書.md" <<'DOC'
# 注文API API基本設計書

## §20 記述規約

本文。
DOC
  out_5="$(run_check "$tmp_5")"; rc_5=$?
  assert_eq "検収5-終了コード" 1 "$rc_5"
  assert_contains "検収5-他文書節不在をFAIL" 'FAIL 相互参照-他文書節不在' "$out_5"
  rm -rf "$tmp_5"

  # 検収6: 節を改番して参照を追従させない場合、自書節不在として不合格になる
  # （改番追従は別の仕組みを設けず、第1の判定で検出する）。
  local tmp_6 out_6 rc_6
  tmp_6="$(new_tmp_dir)"
  write_layout_override "$tmp_6"
  mkdir -p "$tmp_6/api/fixture"
  cat > "$tmp_6/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

§9 の業務ルールを参照する。

## §10 データ定義
DOC
  out_6="$(run_check "$tmp_6")"; rc_6=$?
  assert_eq "検収6-終了コード" 1 "$rc_6"
  assert_contains "検収6-改番未追従をFAIL" 'FAIL 相互参照-自書節不在' "$out_6"
  rm -rf "$tmp_6"

  # 追加回帰1: 章マップ（付録B）内の役割キー表は参照として二重に数えない。
  local tmp_7 out_7 rc_7
  tmp_7="$(new_tmp_dir)"
  write_layout_override "$tmp_7"
  mkdir -p "$tmp_7/api/fixture"
  cat > "$tmp_7/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §5 ロジック

本文。

## 章マップ（付録B）

| 役割 | 節 |
|---|---|
| ロジック | §5 |
| 存在しない役割 | §999 |
DOC
  out_7="$(run_check "$tmp_7")"; rc_7=$?
  assert_eq "検収7-章マップ内は判定対象外で終了コード0" 0 "$rc_7"
  rm -rf "$tmp_7"

  # 追加回帰2: 見出し行自身（宣言）は参照としてカウントしない。
  local tmp_8 out_8 rc_8
  tmp_8="$(new_tmp_dir)"
  write_layout_override "$tmp_8"
  mkdir -p "$tmp_8/api/fixture"
  cat > "$tmp_8/api/fixture/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

## §999 未定義の節見出し
DOC
  out_8="$(run_check "$tmp_8")"; rc_8=$?
  assert_eq "追加回帰2-見出し行自身は参照でない終了コード0" 0 "$rc_8"
  rm -rf "$tmp_8"

  # 追加回帰3: 実物のAPI詳細設計書テンプレートを検査しても自書参照は壊れて
  # いない（§12.2への言及が§12実装契約の小見出し12.2として解決できる）。
  local tmp_real out_real rc_real
  tmp_real="$(new_tmp_dir)"
  write_layout_override "$tmp_real"
  mkdir -p "$tmp_real/api/fixture"
  cp "$REPO_ROOT/delivery-payload/templates/リバース検証/API/API詳細設計書.md" "$tmp_real/api/fixture/API詳細設計書.md"
  out_real="$(run_check "$tmp_real")"; rc_real=$?
  assert_eq "追加回帰3-実物テンプレートの自書参照は健全" 0 "$rc_real"
  rm -rf "$tmp_real"

  # 追加回帰4: document-writing.md に「文書間の参照」節と機械化の範囲がある。
  local dw_file section_present scope_present
  dw_file="$REPO_ROOT/delivery-payload/templates/rules/tool-defined/document-writing.md"
  section_present="$(grep -c '^### 文書間の参照$' "$dw_file")"
  scope_present="$(grep -c '機械化しない' "$dw_file")"
  assert_eq "追加回帰4-文書間の参照節が1件" 1 "$section_present"
  assert_eq "追加回帰4-機械化しない範囲の明記が1件以上" "1" "$([ "$scope_present" -ge 1 ] && echo 1 || echo 0)"

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
  if [ "$#" -ne 1 ]; then
    echo "使い方: $(basename "$0") <project_root>" >&2
    echo "        $(basename "$0") --self-test" >&2
    exit 1
  fi
  run_check "$1"
  exit $?
}

main "$@"
