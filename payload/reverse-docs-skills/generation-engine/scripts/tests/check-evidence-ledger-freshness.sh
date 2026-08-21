#!/usr/bin/env bash
# 根拠を記録する資料（設計単位根拠台帳.md・共通文書根拠台帳.md）の鮮度を検査する。
#
# 1-220が指摘するとおり、これらの台帳は対象コードのファイル名と行番号を記録するが、
# 対象コードへ1行でも挿入・削除があると記録済みの行番号は全件がずれる。既存の
# check-design-code-consistency.sh は対象コード・行の実在確認と数値の一致までは
# 行うが、行の中身が変わっていないかどうか（鮮度）そのものは見ていない。
#
# 本スクリプトは、台帳の前付け（frontmatter）に記録した source_commit（対象コードを
# 読み取った時点のコミットハッシュ）と、現在の対象コードとの差分を行ごとに突き合わせ、
# source_commit の時点から変更があった行を鮮度切れとして報告する。
#
# source_commit を持たない台帳（本方式の採用前に作った台帳）は判定不能として報告する
# にとどめ、不合格にはしない（既に生成済みの資料の是正は1-220の範囲外のため）。
#
# 使い方:
#   check-evidence-ledger-freshness.sh <project_root> <source_dir>
#   check-evidence-ledger-freshness.sh --self-test
#
# 終了コード:
#   0 = 評価できた台帳が1件以上あり、鮮度切れが無い（source_commit未記録等で判定不能の
#       台帳が他に混在してもよい。判定不能は不合格ではないため）
#   1 = 鮮度切れあり
#   2 = 判定不能（mktemp失敗、または評価できた台帳が1件も無い。全台帳がsource_commit
#       未記録・非git・評価対象行0件のいずれかだった場合を含む）
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

resolve_common_ledger() {
  local project_root="$1" layout_json rel
  layout_json="$(resolve_output_layout "$project_root")" || return 1
  rel="$(output_layout_get "$layout_json" commonDocumentEvidenceLedger 2>/dev/null)" || return 1
  [ -n "$rel" ] || return 1
  printf '%s\n' "$project_root/$rel"
}

# 前付け（--- ... ---）から指定キーの値を1行取り出す。
extract_frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { infm = 0 }
    /^---[[:space:]]*$/ { infm = infm + 1; if (infm == 2) exit; next }
    infm == 1 {
      if ($0 ~ "^" key ":") {
        sub("^" key ":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "$file"
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

# パイプ区切り行を trim 済みの値へ分解し、TAB区切りで返す。列数は可変。
_split_row() {
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

# 対象コード・行の組が読み取り可能な状態かどうか（該当なし・空は対象外）。
_is_evaluable_ref() {
  local target_code="$1" line_no="$2"
  [ -n "$target_code" ] || return 1
  [ "$target_code" = "該当なし" ] && return 1
  [ "$line_no" = "該当なし" ] && return 1
  return 0
}

# 単一台帳を検査する。列数（5列=単位根拠台帳／4列=共通文書根拠台帳）を渡す。
#   check_ledger_freshness <file> <source_dir> <columns>
# 出力する行頭ラベル: FAIL 鮮度切れ / [UNKNOWN] 鮮度判定不能
# 戻り値: 0=鮮度切れ無し（判定不能のみ含みうる） 1=鮮度切れあり 2=この台帳は1件も評価できない
check_ledger_freshness() {
  local file="$1" source_dir="$2" columns="$3" rc=0
  local source_commit evaluated=0

  source_commit="$(extract_frontmatter_value "$file" source_commit)"
  if [ -z "$source_commit" ]; then
    echo "[UNKNOWN] 鮮度判定不能 ${file}: source_commit が記録されていません（本方式の採用前に作った台帳の可能性があります）"
    return 2
  fi

  if ! git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[UNKNOWN] 鮮度判定不能 ${file}: source_dir「${source_dir}」がgitリポジトリではないため鮮度を判定できません"
    return 2
  fi

  if ! git -C "$source_dir" cat-file -e "${source_commit}^{commit}" 2>/dev/null; then
    echo "[UNKNOWN] 鮮度判定不能 ${file}: source_commit「${source_commit}」がsource_dirのgit履歴に見つかりません"
    return 2
  fi

  local row target_doc target_section item target_code line_no rest
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    if [ "$columns" = 5 ]; then
      IFS=$'\t' read -r target_doc target_section item target_code line_no <<< "$(_split_row "$row")"
    else
      IFS=$'\t' read -r target_doc target_section target_code line_no <<< "$(_split_row "$row")"
    fi
    _is_evaluable_ref "$target_code" "$line_no" || continue
    evaluated=$((evaluated + 1))

    local diff_rc
    git -C "$source_dir" diff --quiet "$source_commit" -- "$target_code" >/dev/null 2>&1
    diff_rc=$?
    if [ "$diff_rc" -eq 1 ]; then
      echo "FAIL 鮮度切れ ${file}: 対象コード「${target_code}」が source_commit「${source_commit}」以降に変更されており、行「${line_no}」の対応がずれている可能性があります"
      rc=1
    elif [ "$diff_rc" -gt 1 ]; then
      echo "[UNKNOWN] 鮮度判定不能 ${file}: 対象コード「${target_code}」の差分取得に失敗しました（source_dir内に実在しない可能性があります）"
    fi
  done < <(parse_ledger_rows "$file")

  if [ "$evaluated" -eq 0 ]; then
    echo "[UNKNOWN] 鮮度判定不能 ${file}: 評価対象の行（該当なし以外）が1件もありません"
    return 2
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# 集約
# ---------------------------------------------------------------------------
run_check() {
  local project_root="$1" source_dir="$2" rc=0
  local ledgers_evaluated=0 ledgers_unknown=0

  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  if [ ! -d "$source_dir" ]; then
    echo "ERROR: source_dir が存在しません: $source_dir" >&2
    return 1
  fi

  local kind_roots kind kind_root unit_dir ledger_file ledger_rc
  kind_roots="$(resolve_kind_roots "$project_root")" || return 1

  while IFS=$'\t' read -r kind kind_root; do
    [ -n "$kind_root" ] || continue
    while IFS= read -r unit_dir; do
      [ -n "$unit_dir" ] || continue
      ledger_file="$unit_dir/$LEDGER_BASENAME"
      [ -f "$ledger_file" ] || continue
      check_ledger_freshness "$ledger_file" "$source_dir" 5
      ledger_rc=$?
      if [ "$ledger_rc" -eq 2 ]; then
        ledgers_unknown=$((ledgers_unknown + 1))
      else
        ledgers_evaluated=$((ledgers_evaluated + 1))
        [ "$ledger_rc" -eq 1 ] && rc=1
      fi
    done < <(find "$kind_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  done <<EOF
$kind_roots
EOF

  local common_ledger
  common_ledger="$(resolve_common_ledger "$project_root" 2>/dev/null)" || common_ledger=""
  if [ -n "$common_ledger" ] && [ -f "$common_ledger" ]; then
    check_ledger_freshness "$common_ledger" "$source_dir" 4
    ledger_rc=$?
    if [ "$ledger_rc" -eq 2 ]; then
      ledgers_unknown=$((ledgers_unknown + 1))
    else
      ledgers_evaluated=$((ledgers_evaluated + 1))
      [ "$ledger_rc" -eq 1 ] && rc=1
    fi
  fi

  if [ "$ledgers_evaluated" -eq 0 ]; then
    echo "[UNKNOWN] 評価できた台帳が1件もありません（台帳0件、またはsource_commit未記録・非git等で全件が判定不能でした。判定不能: ${ledgers_unknown}件）"
    return 2
  fi
  if [ "$ledgers_unknown" -gt 0 ]; then
    echo "[UNKNOWN] 判定不能の台帳が${ledgers_unknown}件ありました（source_commit未記録・非git等）"
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
      "${TMPDIR:-/tmp}"/evidence-ledger-freshness-self-test.*)
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
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/evidence-ledger-freshness-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
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

  write_unit_ledger() {
    local file="$1" target_code="$2" line_no="$3" source_commit="$4"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
---
unit_kind: api
unit_key: fixture
status: draft
updated: 2026-08-20
source_commit: ${source_commit}
---

# fixture 設計単位根拠台帳

| 対象文書 | 節 | 項目 | 対象コード | 行 |
|---|---|---|---|---|
| API詳細設計書.md | §9.2 業務判断 | 上限価格 | ${target_code} | ${line_no} |
EOF
  }

  init_source_repo() {
    local dir="$1" rc
    git -C "$dir" init -q >/dev/null 2>&1
    git -C "$dir" -c user.name=fixture -c user.email=fixture@example.com config user.email fixture@example.com >/dev/null 2>&1
    rc=$?
    return $rc
  }

  git_commit_all() {
    local dir="$1" msg="$2"
    git -C "$dir" add -A >/dev/null 2>&1
    git -C "$dir" -c user.name=fixture -c user.email=fixture@example.com commit -q -m "$msg" >/dev/null 2>&1
  }

  # 検収1: source_commit の時点から対象コードが変わっていなければ鮮度切れ無し（終了コード0）。
  local tmp_1 source_1 unit_1 ledger_1 code_1 head_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  write_layout_override "$tmp_1"
  unit_1="$tmp_1/api/api-fixture"
  ledger_1="$unit_1/設計単位根拠台帳.md"
  source_1="$tmp_1/source"
  mkdir -p "$source_1"
  init_source_repo "$source_1"
  code_1="$source_1/handler.py"
  { echo "def check_price(v):"; echo "    LIMIT = 500"; echo "    return v <= LIMIT"; } > "$code_1"
  git_commit_all "$source_1" "初回コミット"
  head_1="$(git -C "$source_1" rev-parse HEAD)"
  write_unit_ledger "$ledger_1" "handler.py" 2 "$head_1"
  out_1="$(run_check "$tmp_1" "$source_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_not_contains "検収1-鮮度切れは出ない" 'FAIL 鮮度切れ' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: source_commit記録後に対象コードへ1行挿入すると鮮度切れとして検知する（終了コード1）。
  local tmp_2 source_2 unit_2 ledger_2 code_2 head_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  write_layout_override "$tmp_2"
  unit_2="$tmp_2/api/api-fixture"
  ledger_2="$unit_2/設計単位根拠台帳.md"
  source_2="$tmp_2/source"
  mkdir -p "$source_2"
  init_source_repo "$source_2"
  code_2="$source_2/handler.py"
  { echo "def check_price(v):"; echo "    LIMIT = 500"; echo "    return v <= LIMIT"; } > "$code_2"
  git_commit_all "$source_2" "初回コミット"
  head_2="$(git -C "$source_2" rev-parse HEAD)"
  write_unit_ledger "$ledger_2" "handler.py" 2 "$head_2"
  # 対象コードの先頭へ1行挿入する（記録済みの行2以降が全件ずれる）。
  { echo "# 追加された1行"; cat "$code_2"; } > "${code_2}.new"
  mv "${code_2}.new" "$code_2"
  out_2="$(run_check "$tmp_2" "$source_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-鮮度切れをFAIL" 'FAIL 鮮度切れ' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: source_commitを記録していない台帳は判定不能として扱い、不合格にはしない。
  local tmp_3 source_3 unit_3 ledger_3 code_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  write_layout_override "$tmp_3"
  unit_3="$tmp_3/api/api-fixture"
  ledger_3="$unit_3/設計単位根拠台帳.md"
  source_3="$tmp_3/source"
  mkdir -p "$source_3"
  init_source_repo "$source_3"
  code_3="$source_3/handler.py"
  { echo "value = 1"; } > "$code_3"
  git_commit_all "$source_3" "初回コミット"
  write_unit_ledger "$ledger_3" "handler.py" 1 ""
  out_3="$(run_check "$tmp_3" "$source_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 2 "$rc_3"
  assert_contains "検収3-UNKNOWNラベル" '[UNKNOWN]' "$out_3"
  assert_not_contains "検収3-鮮度切れとしては報告しない" 'FAIL 鮮度切れ' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: source_commitがsource_dirのgit履歴に存在しない場合も判定不能として扱う。
  local tmp_4 source_4 unit_4 ledger_4 code_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  write_layout_override "$tmp_4"
  unit_4="$tmp_4/api/api-fixture"
  ledger_4="$unit_4/設計単位根拠台帳.md"
  source_4="$tmp_4/source"
  mkdir -p "$source_4"
  init_source_repo "$source_4"
  code_4="$source_4/handler.py"
  { echo "value = 1"; } > "$code_4"
  git_commit_all "$source_4" "初回コミット"
  write_unit_ledger "$ledger_4" "handler.py" 1 "0000000000000000000000000000000000000000"
  out_4="$(run_check "$tmp_4" "$source_4")"; rc_4=$?
  assert_eq "検収4-終了コード" 2 "$rc_4"
  assert_contains "検収4-UNKNOWNラベル" '[UNKNOWN]' "$out_4"
  rm -rf "$tmp_4"

  # 検収5: 該当なし行は評価対象から除く（対象コードが1件も無ければ判定不能）。
  local tmp_5 source_5 unit_5 ledger_5 head_5 out_5 rc_5
  tmp_5="$(new_tmp_dir)"
  write_layout_override "$tmp_5"
  unit_5="$tmp_5/api/api-fixture"
  ledger_5="$unit_5/設計単位根拠台帳.md"
  source_5="$tmp_5/source"
  mkdir -p "$source_5"
  init_source_repo "$source_5"
  { echo "value = 1"; } > "$source_5/handler.py"
  git_commit_all "$source_5" "初回コミット"
  head_5="$(git -C "$source_5" rev-parse HEAD)"
  write_unit_ledger "$ledger_5" "該当なし" "該当なし" "$head_5"
  out_5="$(run_check "$tmp_5" "$source_5")"; rc_5=$?
  assert_eq "検収5-終了コード" 2 "$rc_5"
  assert_contains "検収5-評価対象0件はUNKNOWN" '[UNKNOWN]' "$out_5"
  rm -rf "$tmp_5"

  # 検収6: 台帳が1件も無ければ判定不能（終了コード2）。
  local tmp_6 source_6 out_6 rc_6
  tmp_6="$(new_tmp_dir)"
  write_layout_override "$tmp_6"
  mkdir -p "$tmp_6/api/api-fixture"
  source_6="$tmp_6/source"
  mkdir -p "$source_6"
  init_source_repo "$source_6"
  out_6="$(run_check "$tmp_6" "$source_6")"; rc_6=$?
  assert_eq "検収6-台帳0件は終了コード2" 2 "$rc_6"
  assert_contains "検収6-UNKNOWNラベル" '[UNKNOWN]' "$out_6"
  rm -rf "$tmp_6"

  # 検収7: 共通文書根拠台帳（4列）も同じ方式で鮮度切れを検知する。
  local tmp_7 source_7 common_ledger_7 code_7 head_7 out_7 rc_7
  tmp_7="$(new_tmp_dir)"
  cat > "$tmp_7/output-layout.json" <<'JSON'
{ "specVersion": 1, "layout": { "commonDocumentEvidenceLedger": "docs/design/cross-cutting/共通文書根拠台帳.md" } }
JSON
  mkdir -p "$tmp_7/docs/design/cross-cutting"
  source_7="$tmp_7/source"
  mkdir -p "$source_7"
  init_source_repo "$source_7"
  code_7="$source_7/package.json"
  { echo "{"; echo "  \"name\": \"fixture\""; echo "}"; } > "$code_7"
  git_commit_all "$source_7" "初回コミット"
  head_7="$(git -C "$source_7" rev-parse HEAD)"
  common_ledger_7="$tmp_7/docs/design/cross-cutting/共通文書根拠台帳.md"
  cat > "$common_ledger_7" <<EOF
---
doc_id: common-document-evidence-ledger
type: cross-cutting-evidence-ledger
status: draft
updated: 2026-08-20
source_commit: ${head_7}
---

# 共通文書根拠台帳

| 対象文書 | 節・項目 | 対象コード | 行 |
|---|---|---|---|
| 共通設計書.md | 認証・認可 | package.json | 2 |
EOF
  { echo "# 追加された1行"; cat "$code_7"; } > "${code_7}.new"
  mv "${code_7}.new" "$code_7"
  out_7="$(run_check "$tmp_7" "$source_7")"; rc_7=$?
  assert_eq "検収7-終了コード" 1 "$rc_7"
  assert_contains "検収7-共通文書根拠台帳の鮮度切れをFAIL" 'FAIL 鮮度切れ' "$out_7"
  rm -rf "$tmp_7"

  # 検収8: source_dirがgitリポジトリでない場合は判定不能として扱う（終了コード2）。
  local tmp_8 source_8 unit_8 ledger_8 out_8 rc_8
  tmp_8="$(new_tmp_dir)"
  write_layout_override "$tmp_8"
  unit_8="$tmp_8/api/api-fixture"
  ledger_8="$unit_8/設計単位根拠台帳.md"
  source_8="$tmp_8/source"
  mkdir -p "$source_8"
  { echo "value = 1"; } > "$source_8/handler.py"
  write_unit_ledger "$ledger_8" "handler.py" 1 "abc1234"
  out_8="$(run_check "$tmp_8" "$source_8")"; rc_8=$?
  assert_eq "検収8-非gitは終了コード2" 2 "$rc_8"
  assert_contains "検収8-UNKNOWNラベル" '[UNKNOWN]' "$out_8"
  rm -rf "$tmp_8"

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
