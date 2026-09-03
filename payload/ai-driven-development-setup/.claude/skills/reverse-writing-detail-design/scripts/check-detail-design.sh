#!/usr/bin/env bash
set -u

# check-detail-design.sh — 単位ごとの詳細設計書（表はテーブル定義書）の
# 実在・節の構成・事実の網羅・基本設計書との整合を検査する
#
# 目的:
#   工程2-8の完了条件（保留を除く全単位に詳細設計書がある・事実を網羅している・
#   基本設計書と整合する・file:lineが無い・対応するファイルの表が一覧と一致する）
#   を種別ごとに単位ごとへ回して機械で確かめる。
#
# 使い方:
#   check-detail-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別>
#   check-detail-design.sh --self-test
#
# 種別: screen / api / table / batch / report / external（featureは対象外）
#
# 依存（相対パスで呼ぶ。本スクリプトの場所からの相対解決）:
#   ../../reverse-shared/scripts/list-units-of.sh   一覧の取得
#   ../../reverse-shared/scripts/unit-dir-name.sh    識別子からフォルダ名を得る
#   ../../reverse-shared/references/unit-kinds.json  種別キーとフォルダの対応
#   ../../reverse-checking-basic-phase/scripts/check-acceptance-record.sh  合格の記録の確認
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   検査基盤-不在      上記の依存スクリプト・定義が見つからない（判定不能）
#   種別-不正          --kind が対象外（feature含む）または一覧に無い（判定不能）
#   一覧-不在          list-units-of.sh が一覧無しで終了コード2を返す（判定不能）
#   合格記録-不在      check-acceptance-record.sh の終了コードが0でなく、判定が保留でもない
#   文書-不在          詳細設計書（表はテーブル定義書）が実在しない
#   節-欠落            様式が定める`##`見出しが順に揃わない
#   位置づけ-欠落      （表を除く）各`##`見出しの直後に位置づけの行が無い
#   未記入-残存        `<...>`形式のプレースホルダーが残っている
#   位置-禁止          file:line形式の実装位置の記述がある
#   ファイル-不一致    「対応するファイル」表の1列目の集合が、一覧の場所＋属する
#                      ファイルの集合と一致しない
#   事実-未網羅        事実ファイルの値が空でない項目の値が文書本文に現れない
#   基本設計書-不在    対応する基本設計書.mdが実在しない
#   整合-欠落          基本設計書の`### <項目名>`見出しの項目名が詳細設計書に無い
#
# 保留の扱い: check-acceptance-record.shが0でないとき、合格の記録の判定が「保留」で
# あればその単位は飛ばす（不合格に数えない）。判定が保留以外（不在・不合格・
# 記録はあるが文書が変わり合格が失効）なら不合格として数える。
#
# 終了コード:
#   0 = 全単位合格（保留は飛ばした単位を除く）
#   1 = 1単位以上不合格
#   2 = 使い方の誤り・依存の不在・種別の不正・一覧の不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。様式の見出し構成を変えるときは、
#   ../templates/詳細設計書.md・../templates/テーブル定義書.md と
#   本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 詳細設計書の様式を構造化データに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_UNITS_OF="${SCRIPT_DIR}/../../reverse-shared/scripts/list-units-of.sh"
UNIT_DIR_NAME="${SCRIPT_DIR}/../../reverse-shared/scripts/unit-dir-name.sh"
UNIT_KINDS_JSON="${SCRIPT_DIR}/../../reverse-shared/references/unit-kinds.json"
ACCEPTANCE_RECORD_CHECK="${SCRIPT_DIR}/../../reverse-checking-basic-phase/scripts/check-acceptance-record.sh"

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

skipck() {
  echo "[SKIP] 保留-対象外: $1" >&2
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

usage_error() {
  echo "使い方: check-detail-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別>" >&2
  echo "        check-detail-design.sh --self-test" >&2
  exit 2
}

is_valid_kind() {
  case "$1" in
    screen|api|table|batch|report|external) return 0 ;;
    *) return 1 ;;
  esac
}

has_jq() {
  command -v jq > /dev/null 2>&1
}

# 様式の"## "見出しの並び（表とそれ以外）
expected_headings() {
  local kind="$1"
  if [ "$kind" = "table" ]; then
    printf '%s\n' "対応するファイル" "列" "制約" "関係" "要確認事項一覧" "関連資料"
  else
    printf '%s\n' "対応するファイル" "クラス設計" "メソッド設計" "ロジック設計" "戻り値と引数" "エラー処理" "データ定義" "要確認事項一覧" "関連資料"
  fi
}

doc_name_of() {
  if [ "$1" = "table" ]; then
    printf '%s' "テーブル定義書.md"
  else
    printf '%s' "詳細設計書.md"
  fi
}

# 「対応するファイル」表の1列目を1行1件で返す
extract_files_column() {
  local doc="$1"
  awk '
    /^## 対応するファイル/ {flag=1; next}
    /^## / {flag=0}
    flag && /^\|/ {print}
  ' "$doc" | while IFS= read -r line; do
    case "$line" in
      *"ファイル"*"役割"*) continue ;;
      *"---"*) continue ;;
    esac
    printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}'
  done
}

check_unit_doc() {
  local doc="$1" kind="$2" location="$3" files_csv="$4"

  if [ ! -f "$doc" ]; then
    fail "文書-不在" "$doc"
    return
  fi

  # 節-欠落
  local n_expected expected_list actual_list
  expected_list="$(expected_headings "$kind")"
  n_expected="$(printf '%s\n' "$expected_list" | grep -c '.')"
  actual_list="$(grep -E '^## ' "$doc" | sed 's/^## //' | head -n "$n_expected")"
  if [ "$expected_list" = "$actual_list" ]; then
    passck
  else
    fail "節-欠落" "${doc}: 見出しが規定と一致しません（実際: $(printf '%s' "$actual_list" | tr '\n' '/')）"
  fi

  # 位置づけ-欠落（表は対象外）
  if [ "$kind" != "table" ]; then
    local ok_place=1 h
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      local heading_line
      heading_line="$(grep -n -F "## ${h}" "$doc" | head -1 | cut -d: -f1)"
      [ -n "$heading_line" ] || continue
      local next_nonblank
      next_nonblank="$(awk -v start="$heading_line" 'NR>start && NF>0 {print; exit}' "$doc")"
      if [[ "$next_nonblank" != "**この節の位置づけ: "* ]]; then
        fail "位置づけ-欠落" "${doc}: 「## ${h}」の直後に位置づけの行がありません"
        ok_place=0
      fi
    done <<HLIST
$expected_list
HLIST
    [ "$ok_place" -eq 1 ] && passck
  fi

  # 未記入-残存
  local placeholder_lines
  placeholder_lines="$(grep -nE '<[^<>]+>' "$doc" || true)"
  if [ -n "$placeholder_lines" ]; then
    fail "未記入-残存" "${doc}: 未記入のプレースホルダーがあります（例: $(printf '%s\n' "$placeholder_lines" | head -1)）"
  else
    passck
  fi

  # 位置-禁止
  local pos_lines
  pos_lines="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$doc" || true)"
  if [ -n "$pos_lines" ]; then
    fail "位置-禁止" "${doc}: 実装位置(file:line)の記述があります（例: $(printf '%s\n' "$pos_lines" | head -1)）"
  else
    passck
  fi

  # ファイル-不一致
  local expected_files actual_files
  expected_files="$( { printf '%s\n' "$location"; printf '%s\n' "$files_csv" | tr ';' '\n'; } | sed '/^$/d' | sort -u)"
  actual_files="$(extract_files_column "$doc" | sed '/^$/d' | sort -u)"
  if [ "$expected_files" = "$actual_files" ]; then
    passck
  else
    fail "ファイル-不一致" "${doc}: 一覧（$(printf '%s' "$expected_files" | tr '\n' ';')）と文書（$(printf '%s' "$actual_files" | tr '\n' ';')）が一致しません"
  fi
}

check_facts_coverage() {
  local doc="$1" facts_json="$2"

  if [ ! -f "$facts_json" ]; then
    fail "事実-不在" "$facts_json が存在しません"
    return
  fi
  if ! has_jq; then
    fail "検査基盤-不在" "jqが使えません"
    return
  fi

  local items ok=1
  items="$(jq -r '.["事実"] | keys[]' "$facts_json" 2>/dev/null || true)"
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    local values
    values="$(jq -r --arg k "$item" '.["事実"][$k]["値"][]?' "$facts_json" 2>/dev/null || true)"
    local v
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      if ! grep -qF -- "$v" "$doc"; then
        fail "事実-未網羅" "${item}=${v}"
        ok=0
      fi
    done <<VLIST
$values
VLIST
  done <<ILIST
$items
ILIST
  [ "$ok" -eq 1 ] && passck
}

check_basic_design_consistency() {
  local doc="$1" basic_doc="$2"

  if [ ! -f "$basic_doc" ]; then
    fail "基本設計書-不在" "$basic_doc が存在しません"
    return
  fi

  local headings ok=1 h
  headings="$(grep -E '^### ' "$basic_doc" | sed 's/^### //')"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    if ! grep -qF -- "$h" "$doc"; then
      fail "整合-欠落" "${h}"
      ok=0
    fi
  done <<HLIST
$headings
HLIST
  [ "$ok" -eq 1 ] && passck
}

run_units() {
  local target="$1" run_dir="$2" kind="$3"
  local species_folder
  species_folder="$(jq -r --arg k "$kind" '.[] | select(.key==$k) | .["フォルダ"]' "$UNIT_KINDS_JSON")"
  if [ -z "$species_folder" ]; then
    echo "[FAIL] 種別-不正: unit-kinds.jsonに${kind}がありません" >&2
    return 2
  fi
  local doc_name
  doc_name="$(doc_name_of "$kind")"

  local units_out rc=0
  units_out="$(bash "$LIST_UNITS_OF" "$target" "$kind" 2>"${TMPDIR:-/tmp}/check-detail-design-list.$$")" || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "[FAIL] 一覧-不在: ${kind}の一覧がありません" >&2
    cat "${TMPDIR:-/tmp}/check-detail-design-list.$$" >&2
    rm -f "${TMPDIR:-/tmp}/check-detail-design-list.$$"
    return 2
  fi
  rm -f "${TMPDIR:-/tmp}/check-detail-design-list.$$"

  local line identifier name location files_csv folder
  while IFS=$'\t' read -r identifier name location files_csv; do
    [ -n "$identifier" ] || continue
    folder="$(bash "$UNIT_DIR_NAME" "$identifier")"
    local doc="${target%/}/docs/design/${species_folder}/${folder}/${doc_name}"
    local basic_doc="${target%/}/docs/design/${species_folder}/${folder}/基本設計書.md"
    local record="${target%/}/ai-work/records/basic-design-acceptance/${kind}-${folder}.json"
    local facts_json="${run_dir%/}/facts/${kind}/${folder}.json"

    local vrc=0
    bash "$ACCEPTANCE_RECORD_CHECK" "$target" --kind "$kind" --unit "$identifier" > /dev/null 2>&1 || vrc=$?
    if [ "$vrc" -ne 0 ]; then
      local hantei=""
      if [ -f "$record" ] && has_jq; then
        hantei="$(jq -r '.["判定"] // empty' "$record" 2>/dev/null || true)"
      fi
      if [ "$hantei" = "保留" ]; then
        skipck "${kind}/${identifier}"
        continue
      fi
      fail "合格記録-不在" "${kind}/${identifier}"
      continue
    fi

    check_unit_doc "$doc" "$kind" "$location" "$files_csv"
    [ -f "$doc" ] || continue
    check_facts_coverage "$doc" "$facts_json"
    check_basic_design_consistency "$doc" "$basic_doc"
  done <<UNITLIST
$units_out
UNITLIST

  return 0
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-detail-design-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local total=0 fail=0

  # 自分自身と依存(reverse-sharedのlist-units-of.sh・unit-dir-name.sh、
  # reverse-checking-basic-phaseのcheck-acceptance-record.sh。いずれも別担当が
  # 並行して構築する)を隔離したfixtureへ複製し、実リポジトリの構築状況に
  # 左右されずに検査ロジックを確かめる。unit-dir-name.shのスタブは規約
  # （agent-operations/skill-naming）に定めるのと同じ置換規則で実装する。
  local self_dir own_name
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  own_name="$(basename "$0")"
  local fixture_root="${tmp}/fixture-skills"
  local copy_dir="${fixture_root}/reverse-writing-detail-design/scripts"
  local shared_dir="${fixture_root}/reverse-shared/scripts"
  local shared_ref_dir="${fixture_root}/reverse-shared/references"
  local record_dir="${fixture_root}/reverse-checking-basic-phase/scripts"
  mkdir -p "$copy_dir" "$shared_dir" "$shared_ref_dir" "$record_dir"
  cp "${self_dir}/${own_name}" "${copy_dir}/${own_name}"
  chmod +x "${copy_dir}/${own_name}"
  local under_test="${copy_dir}/${own_name}"

  cp "${SCRIPT_DIR}/../../reverse-shared/references/unit-kinds.json" "${shared_ref_dir}/unit-kinds.json" 2>/dev/null \
    || cat > "${shared_ref_dir}/unit-kinds.json" <<'KINDSEOF'
[
  { "key": "screen", "名前": "画面", "フォルダ": "screens" },
  { "key": "api", "名前": "接続窓口", "フォルダ": "apis" },
  { "key": "table", "名前": "表", "フォルダ": "tables" },
  { "key": "batch", "名前": "バッチ", "フォルダ": "batches" },
  { "key": "report", "名前": "帳票", "フォルダ": "reports" },
  { "key": "external", "名前": "外部連携", "フォルダ": "externals" },
  { "key": "feature", "名前": "機能", "フォルダ": "features" }
]
KINDSEOF

  cat > "${shared_dir}/unit-dir-name.sh" <<'DIRNAMEEOF'
#!/usr/bin/env bash
id="${1:-}"
printf '%s' "$id" | sed -E 's#[/ {}:\\?*]#_#g' | sed -E 's/^_+//'
DIRNAMEEOF
  chmod +x "${shared_dir}/unit-dir-name.sh"

  local list_data="${tmp}/list-data.tsv"
  cat > "${shared_dir}/list-units-of.sh" <<LISTEOF
#!/usr/bin/env bash
if [ ! -f "${list_data}" ]; then
  echo "一覧がありません" >&2
  exit 2
fi
cat "${list_data}"
LISTEOF
  chmod +x "${shared_dir}/list-units-of.sh"

  local record_rc_file="${tmp}/record-rc.txt"
  echo 0 > "$record_rc_file"
  cat > "${record_dir}/check-acceptance-record.sh" <<RECORDCHECKEOF
#!/usr/bin/env bash
exit "\$(cat "${record_rc_file}")"
RECORDCHECKEOF
  chmod +x "${record_dir}/check-acceptance-record.sh"

  local target="${tmp}/target"
  local run_dir="${tmp}/run"
  local ident="src/pages/OrderList.tsx"
  local folder="src_pages_OrderList.tsx"
  local doc_dir="${target}/docs/design/screens/${folder}"
  mkdir -p "$doc_dir" "${target}/ai-work/records/basic-design-acceptance" "${run_dir}/facts/screen"

  printf '%s\t%s\t%s\t%s\n' "$ident" "OrderList一覧" "$ident" "${ident};src/api/orders.ts" > "$list_data"

  cat > "${doc_dir}/基本設計書.md" <<'BASICEOF'
# 基本設計書

## 外部仕様

### 入力項目

記入済み

### 表示項目

記入済み
BASICEOF

  cat > "${run_dir}/facts/screen/${folder}.json" <<'FACTSEOF'
{
  "種別": "screen",
  "識別子": "src/pages/OrderList.tsx",
  "事実": {
    "入力項目": {"値": ["注文ID"], "出所": "機械", "根拠": ["src/pages/OrderList.tsx"]},
    "表示項目": {"値": ["注文一覧"], "出所": "機械", "根拠": ["src/pages/OrderList.tsx"]},
    "操作": {"値": [], "出所": "機械", "根拠": []}
  },
  "未": ["操作"]
}
FACTSEOF

  write_doc_good() {
    cat > "${doc_dir}/詳細設計書.md" <<'DOCEOF'
# 詳細設計書

## 対応するファイル

**この節の位置づけ: 現行実装**

| ファイル | 役割 |
|---|---|
| src/pages/OrderList.tsx | 画面本体 |
| src/api/orders.ts | 一覧取得 |

## クラス設計

**この節の位置づけ: 現行実装**

記入済み（入力項目・表示項目を扱う）

## メソッド設計

**この節の位置づけ: 現行実装**

記入済み

## ロジック設計

**この節の位置づけ: 現行実装**

記入済み

## 戻り値と引数

**この節の位置づけ: 現行実装**

記入済み

## エラー処理

**この節の位置づけ: 現行実装**

記入済み（理由（観測）: 既存の実装を踏まえる）

## データ定義

**この節の位置づけ: 現行実装**

記入済み。注文ID・注文一覧を扱う。

## 要確認事項一覧

**この節の位置づけ: 現行実装**

なし

## 関連資料

**この節の位置づけ: 現行実装**

なし
DOCEOF
  }

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    total=$((total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（期待終了コード ${expected} / 実際 ${actual}）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    total=$((total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  assert_skip() {
    local desc="$1"
    total=$((total + 1))
    if grep -qF "[SKIP] 保留-対象外" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}（skipが出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      fail=$((fail + 1))
    fi
  }

  # 合格
  write_doc_good
  echo 0 > "$record_rc_file"
  assert_exit "合格" 0 bash "$under_test" "$target" --run "$run_dir" --kind screen

  # 不合格-合格記録なし
  echo 1 > "$record_rc_file"
  assert_exit "不合格-合格記録なし" 1 bash "$under_test" "$target" --run "$run_dir" --kind screen
  assert_contains "不合格-合格記録なし: 合格記録-不在が出る" "合格記録-不在"

  # 保留はスキップして全体は合格
  cat > "${target}/ai-work/records/basic-design-acceptance/screen-${folder}.json" <<'RECEOF'
{"種別":"screen","識別子":"src/pages/OrderList.tsx","判定":"保留"}
RECEOF
  assert_exit "保留は不合格にしない" 0 bash "$under_test" "$target" --run "$run_dir" --kind screen
  assert_skip "保留は不合格にしない: skipが出る"
  rm -f "${target}/ai-work/records/basic-design-acceptance/screen-${folder}.json"
  echo 0 > "$record_rc_file"

  # 不合格（複合）: 節の欠落・未記入・file:line・ファイル不一致・事実未網羅・整合欠落
  cat > "${doc_dir}/詳細設計書.md" <<'BADEOF'
# 詳細設計書

## 対応するファイル

**この節の位置づけ: 現行実装**

| ファイル | 役割 |
|---|---|
| src/pages/OrderList.tsx | 画面本体 |

## クラス設計

**この節の位置づけ: 現行実装**

<ここを埋める>

## メソッド設計

**この節の位置づけ: 現行実装**

src/app/order.ts:88 を参照する。
BADEOF
  assert_exit "不合格-複合" 1 bash "$under_test" "$target" --run "$run_dir" --kind screen
  assert_contains "不合格-複合: 節-欠落が出る" "節-欠落"
  assert_contains "不合格-複合: 未記入-残存が出る" "未記入-残存"
  assert_contains "不合格-複合: 位置-禁止が出る" "位置-禁止"
  assert_contains "不合格-複合: ファイル-不一致が出る" "ファイル-不一致"
  assert_contains "不合格-複合: 事実-未網羅が出る" "事実-未網羅"
  assert_contains "不合格-複合: 整合-欠落が出る" "整合-欠落"
  write_doc_good

  # 判定不能-文書不在
  rm -f "${doc_dir}/詳細設計書.md"
  assert_exit "不合格-文書不在" 1 bash "$under_test" "$target" --run "$run_dir" --kind screen
  assert_contains "不合格-文書不在: 文書-不在が出る" "文書-不在"
  write_doc_good

  # 判定不能-一覧不在
  mv "$list_data" "${list_data}.bak"
  assert_exit "判定不能-一覧不在" 2 bash "$under_test" "$target" --run "$run_dir" --kind screen
  mv "${list_data}.bak" "$list_data"

  # 判定不能-種別不正
  assert_exit "判定不能-種別不正" 2 bash "$under_test" "$target" --run "$run_dir" --kind feature

  # 判定不能-使い方の誤り
  assert_exit "判定不能-使い方の誤り" 2 bash "$under_test"

  # 判定不能-検査基盤不在
  rm -f "${shared_dir}/list-units-of.sh"
  assert_exit "判定不能-検査基盤不在" 2 bash "$under_test" "$target" --run "$run_dir" --kind screen

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
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

if ! has_jq; then
  echo "[FAIL] 検査基盤-不在: jqが使えません" >&2
  exit 2
fi
if [ ! -f "$LIST_UNITS_OF" ] || [ ! -f "$UNIT_DIR_NAME" ] || [ ! -f "$UNIT_KINDS_JSON" ] || [ ! -f "$ACCEPTANCE_RECORD_CHECK" ]; then
  echo "[FAIL] 検査基盤-不在: 依存スクリプト・定義のいずれかが見つかりません" >&2
  exit 2
fi

TARGET=""
RUN_DIR=""
KIND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_DIR="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-}"; shift 2 ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"; shift
      else
        usage_error
      fi
      ;;
  esac
done

if [ -z "$TARGET" ] || [ -z "$RUN_DIR" ] || [ -z "$KIND" ]; then
  usage_error
fi
if ! is_valid_kind "$KIND"; then
  echo "[FAIL] 種別-不正: ${KIND} は対象外です" >&2
  exit 2
fi

run_units "$TARGET" "$RUN_DIR" "$KIND"
rrc=$?
if [ "$rrc" -eq 2 ]; then
  exit 2
fi

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件 / 保留 ${SKIP_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
