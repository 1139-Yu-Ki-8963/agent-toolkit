#!/usr/bin/env bash
set -u

# check-requirement-mapping.sh — 要件定義書の機能要件と一覧の対応表を突き合わせる
#
# 目的:
#   reverse-listing-unitsの完了時の処理の完了条件を機械で確かめる。要件定義書
#   §3機能要件の「機能の一覧」の各行が対応表の「機能」列に現れるか、一覧
#   （docs/design/lists/<種別>.json）の各単位が対応表の「種別」「単位の識別子」
#   列の組に現れるかを検査する。対応そのものはAIが作る。本スクリプトは
#   突合の確認だけを行い、要件定義書は変更しない。
#
# 使い方:
#   check-requirement-mapping.sh <対象リポジトリのルート> [--design-root <設計書のルート>] [--lists <一覧フォルダの相対パス>] [--requirements <要件定義書の相対パス>]
#   check-requirement-mapping.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。要件定義書・一覧・対応表は
# すべて設計書のルート配下で読み書きする（対象リポジトリのルートは実在確認
# にのみ使う）。--lists の既定は docs/design/lists。--requirements の既定は
# docs/design/requirements/要件定義書.md。対応表は <lists>/機能と単位の対応表.md
# に固定する（一覧を作る機能の完了時の処理の出力先であり、変更する理由が無いため引数を持たない）。
# 対応表の「種別」列は一覧のjsonの「種別」フィールドと同じ表記
# （screen/api/table/batch/report/external/featureのいずれか）で書く。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   機能-単位なし  要件定義書の機能の一覧の行が、対応表の「機能」列に1件も現れない
#   単位-機能なし  一覧の単位（種別・識別子）が、対応表の「種別」「単位の識別子」
#                  列の組に1件も現れない
#
# 終了コード:
#   0 = 全件対応あり
#   1 = 1件以上対応なし（[FAIL]行を標準エラーへ列挙）
#   2 = 使い方の誤り・対象/対応表/要件定義書の不在・jq不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。対応表・要件定義書の列構成を変えるときは
#   reverse-writing-survey-definition の要件定義書の様式と本スクリプトと自己テストを
#   同時に直す。
#
# 廃棄条件: 機能と単位の対応を別の構造化データで持つ形に変えた時。
#
# macOS bash 3.2 互換（連想配列は不使用）。jqを使用する。

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

col() {
  # col <line> <n>  行を'|'で割り、n番目(1始まり、先頭の空要素の次から)を返す
  local line="$1" n="$2"
  local IFS='|'
  local -a arr
  read -ra arr <<< "$line"
  printf '%s' "$(trim "${arr[$n]:-}")"
}

table_data_rows() {
  # table_data_rows <text>  表のヘッダ行・区切り行を除いたデータ行だけを返す
  local text="$1"
  local rows
  rows="$(grep -E '^\|.*\|[[:space:]]*$' <<< "$text" || true)"
  rows="$(grep -vE '^\|[-:|[:space:]]+$' <<< "$rows" || true)"
  tail -n +2 <<< "$rows" 2>/dev/null | grep -v '^$' || true
}

first_table_text() {
  # first_table_text <text>  最初の表ブロック（'|'始まりの連続行）だけを返す
  awk '
    /^\|/ { intable=1; print; next }
    intable && !/^\|/ { exit }
  ' <<< "$1"
}

sub_section_text() {
  # sub_section_text <content> <開始見出しの完全一致文字列>
  # 次の「### 」または「## 」見出し行、またはEOFまでを返す
  local content="$1" start="$2"
  awk -v start="$start" '
    BEGIN{flag=0}
    index($0,start)==1 {flag=1; next}
    flag && (/^### / || /^## /) {flag=0}
    flag {print}
  ' <<< "$content"
}

has_jq() {
  command -v jq > /dev/null 2>&1
}

usage_error() {
  echo "使い方: check-requirement-mapping.sh <対象リポジトリのルート> [--design-root <設計書のルート>] [--lists <一覧フォルダの相対パス>] [--requirements <要件定義書の相対パス>]" >&2
  echo "        check-requirement-mapping.sh --self-test" >&2
  exit 2
}

check_mapping() {
  local target="$1" lists_rel="$2" req_rel="$3" design_root="$4"
  local lists_dir="${design_root%/}/${lists_rel}"
  local req_file="${design_root%/}/${req_rel}"
  local mapping_file="${lists_dir%/}/機能と単位の対応表.md"

  if [ ! -d "$target" ]; then
    echo "対象リポジトリが見つかりません: ${target}" >&2
    return 2
  fi
  if ! has_jq; then
    echo "jq が使えません" >&2
    return 2
  fi
  if [ ! -f "$req_file" ]; then
    echo "要件定義書が見つかりません: ${req_file}" >&2
    return 2
  fi
  if [ ! -f "$mapping_file" ]; then
    echo "対応表が見つかりません: ${mapping_file}" >&2
    return 2
  fi

  local mapping_content mapping_table mapping_rows
  mapping_content="$(cat "$mapping_file")"
  mapping_table="$(first_table_text "$mapping_content")"
  mapping_rows="$(table_data_rows "$mapping_table")"

  local features_list="" units_list=""
  local r
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    local f2 t2 i2
    f2="$(col "$r" 1)"
    t2="$(col "$r" 2)"
    i2="$(col "$r" 3)"
    if [ -n "$f2" ]; then
      features_list="${features_list}${f2}
"
    fi
    if [ -n "$t2" ] && [ -n "$i2" ]; then
      units_list="${units_list}${t2}/${i2}
"
    fi
  done <<< "$mapping_rows"

  # 機能-単位なし
  local req_content req_sub req_table req_rows
  req_content="$(cat "$req_file")"
  req_sub="$(sub_section_text "$req_content" "### 機能の一覧")"
  req_table="$(first_table_text "$req_sub")"
  req_rows="$(table_data_rows "$req_table")"

  local ok_feature=1
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    local feat
    feat="$(col "$r" 1)"
    [ -z "$feat" ] && continue
    [ "${feat:0:1}" = "<" ] && continue
    if ! grep -qxF "$feat" <<< "$features_list"; then
      fail "機能-単位なし" "$feat"
      ok_feature=0
    fi
  done <<< "$req_rows"
  [ "$ok_feature" -eq 1 ] && passck

  # 単位-機能なし
  local -a kinds=(screen api table batch report external feature)
  local ok_unit=1
  local kind lf
  for kind in "${kinds[@]}"; do
    lf="${lists_dir%/}/${kind}.json"
    [ -f "$lf" ] || continue
    if ! jq -e . "$lf" > /dev/null 2>&1; then
      fail "単位-機能なし" "${lf} がJSONとして読めません"
      ok_unit=0
      continue
    fi
    local n
    n="$(jq 'length' "$lf" 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
      local idx
      for idx in $(seq 0 $((n - 1))); do
        local sp id
        sp="$(jq -r --argjson i "$idx" '.[$i]["種別"] // empty' "$lf")"
        id="$(jq -r --argjson i "$idx" '.[$i]["識別子"] // empty' "$lf")"
        [ -z "$sp" ] && sp="$kind"
        [ -z "$id" ] && continue
        if ! grep -qxF "${sp}/${id}" <<< "$units_list"; then
          fail "単位-機能なし" "${sp}/${id}"
          ok_unit=0
        fi
      done
    fi
  done
  [ "$ok_unit" -eq 1 ] && passck

  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-requirement-mapping-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local self_fail=0
  local self_total=0

  build_target() {
    local root="$1"
    mkdir -p "${root}/docs/design/requirements" "${root}/docs/design/lists"
    cat > "${root}/docs/design/requirements/要件定義書.md" << 'REQEOF'
# 要件定義書

## §3 機能要件

### 機能の一覧

| 機能 | 目的 | 利用者 | 入力 | 出力 | 例外時の要求 | 権限の要求 | 対応する種別と単位の候補 |
|---|---|---|---|---|---|---|---|
| 注文一覧 | 注文を見る | 担当者 | なし | 一覧 | なし | ログイン | screen: order-list |
| 注文API | 注文を返す | システム | なし | JSON | なし | なし | api: order |

### 優先度

| 機能 | 優先度 | 根拠 |
|---|---|---|
| 注文一覧 | 高 | 業務上必須 |
REQEOF
    cat > "${root}/docs/design/lists/screen.json" << 'SCRJSON'
[
  {"種別":"screen","識別子":"src/screens/order-list.tsx","名前":"注文一覧","場所":"src/screens/order-list.tsx","根拠":"src/screens/order-list.tsx","単位の定義":"画面ファイル1つを1画面とする","属するファイル":["src/screens/order-list.tsx"],"分類軸":[]}
]
SCRJSON
    cat > "${root}/docs/design/lists/api.json" << 'APIJSON'
[
  {"種別":"api","識別子":"order","名前":"注文API","場所":"src/api/order.ts","根拠":"src/api/order.ts","単位の定義":"エンドポイント1つを1接続窓口とする","属するファイル":["src/api/order.ts"],"分類軸":[]}
]
APIJSON
  }

  build_mapping_full() {
    cat > "$1" << 'MAPEOF3'
# 機能と単位の対応表

| 機能 | 種別 | 単位の識別子 | 根拠 |
|---|---|---|---|
| 注文一覧 | screen | src/screens/order-list.tsx | 画面一覧 |
| 注文API | api | order | 接続窓口一覧 |
MAPEOF3
  }

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    self_total=$((self_total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} (期待終了コード ${expected} / 実際 ${actual})"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    self_total=$((self_total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} （${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  # 合格-完成形
  local root_ok="${tmp}/target-ok"
  build_target "$root_ok"
  build_mapping_full "${root_ok}/docs/design/lists/機能と単位の対応表.md"
  assert_exit "合格-完成形" 0 bash "$0" "$root_ok"

  # 不合格-機能単位なし（対応表から注文APIの行を消す）
  local root_missing_feature="${tmp}/target-missing-feature"
  build_target "$root_missing_feature"
  cat > "${root_missing_feature}/docs/design/lists/機能と単位の対応表.md" << 'MAPEOF4'
# 機能と単位の対応表

| 機能 | 種別 | 単位の識別子 | 根拠 |
|---|---|---|---|
| 注文一覧 | screen | src/screens/order-list.tsx | 画面一覧 |
MAPEOF4
  assert_exit "不合格-機能単位なし" 1 bash "$0" "$root_missing_feature"
  assert_contains "不合格-機能単位なし: 機能-単位なしが出る" "機能-単位なし"

  # 不合格-単位機能なし（対応表からapi行を消すが一覧にはapiが残る）
  local root_missing_unit="${tmp}/target-missing-unit"
  build_target "$root_missing_unit"
  cat > "${root_missing_unit}/docs/design/lists/機能と単位の対応表.md" << 'MAPEOF5'
# 機能と単位の対応表

| 機能 | 種別 | 単位の識別子 | 根拠 |
|---|---|---|---|
| 注文一覧 | screen | src/screens/order-list.tsx | 画面一覧 |
| 注文API | screen | src/screens/order-list.tsx | 誤り |
MAPEOF5
  assert_exit "不合格-単位機能なし" 1 bash "$0" "$root_missing_unit"
  assert_contains "不合格-単位機能なし: 単位-機能なしが出る" "単位-機能なし"

  # 判定不能-要件定義書不在
  local root_no_req="${tmp}/target-no-req"
  build_target "$root_no_req"
  build_mapping_full "${root_no_req}/docs/design/lists/機能と単位の対応表.md"
  rm -f "${root_no_req}/docs/design/requirements/要件定義書.md"
  assert_exit "判定不能-要件定義書不在" 2 bash "$0" "$root_no_req"

  # 判定不能-対応表不在
  local root_no_map="${tmp}/target-no-map"
  build_target "$root_no_map"
  assert_exit "判定不能-対応表不在" 2 bash "$0" "$root_no_map"

  # 設計書ルート分離-対象に書かない
  local root_code_only="${tmp}/target-code-only"
  mkdir -p "${root_code_only}"
  local design_only="${tmp}/design-only"
  build_target "$design_only"
  build_mapping_full "${design_only}/docs/design/lists/機能と単位の対応表.md"
  assert_exit "設計書ルート分離-合格" 0 bash "$0" "$root_code_only" --design-root "$design_only"
  self_total=$((self_total + 1))
  if [ ! -e "${root_code_only}/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側にdocsが作られています）"
    self_fail=$((self_fail + 1))
  fi

  # 使い方-引数不足
  assert_exit "使い方-引数不足" 2 bash "$0"

  echo "実行 ${self_total} 件 / 失敗 ${self_fail} 件"
  if [ "$self_fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

TARGET="$1"
shift
DESIGN_ROOT="$TARGET"
LISTS_REL="docs/design/lists"
REQ_REL="docs/design/requirements/要件定義書.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --design-root)
      DESIGN_ROOT="${2:-}"
      shift 2
      ;;
    --lists)
      LISTS_REL="${2:-}"
      shift 2
      ;;
    --requirements)
      REQ_REL="${2:-}"
      shift 2
      ;;
    *)
      echo "余分な引数です: $1" >&2
      exit 2
      ;;
  esac
done

check_mapping "$TARGET" "$LISTS_REL" "$REQ_REL" "$DESIGN_ROOT"
rc=$?
if [ "$rc" -eq 2 ]; then
  exit 2
fi

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
