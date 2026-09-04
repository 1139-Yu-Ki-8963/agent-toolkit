#!/usr/bin/env bash
set -u

# check-basic-design.sh — 種別ごとの基本設計書・単体テスト設計書（旧様式の
#   ファイル名を使う。機能は機能設計書・機能単体テスト設計書）の実在・様式・
#   事実の転記・確認事項の登録を検査する
#
# 目的:
#   基本設計書はAIが事実を業務の言葉に写して書くため文面は毎回変わる。
#   詳細設計へ進んでよいかを判定するために機械で読める部分（必須節の順序・
#   位置づけの行・未記入の不在・実装位置の不在・事実の転記・確認事項の
#   登録）を検査する。文面の当否は問わない。
#
# 使い方:
#   check-basic-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書のルート>]
#   check-basic-design.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。一覧・基本設計書・単体テスト
# 設計書は設計書のルート配下で読み書きする。
#
# 種別ごとの単位一覧はreverse-shared/scripts/list-units-of.shで読み、単位の
# フォルダ名はreverse-shared/scripts/unit-dir-name.shで作る（唯一の定義を
# 再実装しない）。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   共有部品-不在        reverse-sharedのunit-dir-name.sh・list-units-of.shが無い
#   規約-不在            支援ツール側の写しの設計書の書き方・単体テスト設計書の検査スクリプトが無い
#   一覧-不在            対象の一覧（docs/design/lists/<種別>.json）が読めない
#   文書-不在            種別ごとの基本設計書・単体テスト設計書（機能は機能設計書・機能単体テスト設計書）が実在しない
#   節-欠落              必須見出しが順に揃っていない
#   位置づけ-欠落        必須見出しの直後に位置づけの行が無い
#   未記入-残存          山括弧のプレースホルダーが残っている
#   位置-禁止            file:line形式の実装位置の記述がある
#   規約-見出し          対象の設計書の書き方の検査が不合格
#   単体テスト規約-不合格  対象の単体テスト設計書の決まりの検査が不合格
#   事実-未転記          事実ファイルの値が空でない項目が転記されていない
#   確認事項-未登録      要確認事項一覧のキーが確認事項の記録に無い
#
# 終了コード:
#   0 = 種別内の全単位が合格
#   1 = 1単位以上が不合格
#   2 = 使い方の誤り・共有部品や規約スクリプトの不在・一覧が読めない（判定不能）
#
# 既知の限界:
#   - 見出しの様式は種別ごとにbasic_expected_headings()が持つ表で判定する
#     （章構成の正はテンプレートであり、この表はテンプレートの実測を写した
#     ものにすぎない。テンプレートを変えたら本表を追従させる）
#   - 論理データモデル.md・機能設計書.mdはファイル名に「基本設計書」という
#     文字列を含まないため、設計書の書き方の決まり（reverse-sharedの
#     check-doc-heading-addendum.sh）のファイル名一致による検査は
#     table・feature種別には効かない（no-op）。この2種別の様式検査は本
#     スクリプト自身のcheck_headings_order/check_placement_linesが担う
#   - 画面基本設計書.mdはファイル名に「基本設計書」を含み、上記の共有
#     チェッカーが持つ完了状態見出し（外部仕様・業務仕様・方式設計・データ
#     仕様・エラーと例外）と、実際の画面の様式（画面の目的・画面構成・
#     機能仕様・業務ルール・入出力の業務的意味・画面遷移の業務文脈・関連
#     資料）が一致しない。そのためscreen種別ではこの共有チェッカーの呼び
#     出しを行わず、様式の妥当性は本スクリプト自身の
#     check_headings_order/check_placement_linesに委ねる（章構成の正は
#     テンプレートという規約に従う）
#   - table種別の事実-未転記は、論理データモデルの様式（型・制約を書かない）
#     に合わせて「列」「関係」だけを対象にする。「型」「制約」の転記確認は
#     詳細設計（テーブル定義書）のcheck-detail-design.shが担う
#
# 保守責任者: 人手（ユーザー）。事実の項目や様式を変えるときは、
#   docs/design/common/fact-shapes.json・templates/・本スクリプトを同時に直す。
#
# 廃棄条件: 基本設計書の様式を構造化データから生成する仕組みに置き換えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="${SCRIPT_DIR}/../../reverse-shared/scripts"
UNIT_DIR_NAME_SH="${SHARED_DIR}/unit-dir-name.sh"
LIST_UNITS_OF_SH="${SHARED_DIR}/list-units-of.sh"
HEADING_SCRIPT="${SHARED_DIR}/check-doc-heading-addendum.sh"
UNITTEST_SCRIPT="${SHARED_DIR}/check-unit-test-design-doc-sections.sh"

usage_error() {
  echo "使い方: check-basic-design.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書のルート>]" >&2
  echo "        check-basic-design.sh --self-test" >&2
  exit 2
}

species_folder() {
  case "$1" in
    screen) echo screens ;;
    api) echo apis ;;
    table) echo tables ;;
    batch) echo batches ;;
    report) echo reports ;;
    external) echo externals ;;
    feature) echo features ;;
    *) echo "" ;;
  esac
}

# 種別ごとの基本設計書のファイル名（旧様式の名前をそのまま使う）
basic_doc_name() {
  case "$1" in
    screen) echo "画面基本設計書.md" ;;
    api) echo "API基本設計書.md" ;;
    table) echo "論理データモデル.md" ;;
    batch) echo "バッチ基本設計書.md" ;;
    report) echo "帳票基本設計書.md" ;;
    external) echo "外部連携基本設計書.md" ;;
    feature) echo "機能設計書.md" ;;
    *) echo "" ;;
  esac
}

# 種別ごとの単体テスト設計書のファイル名（旧様式の名前をそのまま使う）
test_doc_name() {
  case "$1" in
    screen) echo "画面単体テスト設計書.md" ;;
    api) echo "API単体テスト設計書.md" ;;
    table) echo "テーブル単体テスト設計書.md" ;;
    batch) echo "バッチ単体テスト設計書.md" ;;
    report) echo "帳票単体テスト設計書.md" ;;
    external) echo "外部連携単体テスト設計書.md" ;;
    feature) echo "機能単体テスト設計書.md" ;;
    *) echo "" ;;
  esac
}

# 種別ごとの基本設計書の様式（見出しはテンプレートの実測どおり「§N ...」を
# 含めて1行ずつ書く。並び順はテンプレートの節の順）
basic_expected_headings() {
  case "$1" in
    screen)
      printf '%s\n' \
        "§1 画面の目的" "§2 画面構成" "§3 機能仕様（業務機能の一覧）" \
        "§4 業務ルール" "§5 入出力の業務的意味" "§6 画面遷移の業務文脈" "§7 関連資料"
      ;;
    feature)
      printf '%s\n' \
        "§1 機能概要" "§2 機能の範囲" "§3 業務フロー" "§4 業務ルール" "§5 データ" \
        "§6 構成要素間の状態受け渡し" "§7 呼び出し仕様" "§8 エラーと業務メッセージ" \
        "§9 非機能" "§10 共通仕様への準拠" "§11 関連資料"
      ;;
    *)
      printf '%s\n' \
        "§1 外部仕様" "§2 業務仕様" "§3 方式設計" "§4 データ仕様" "§5 エラーと例外" "§6 関連資料"
      ;;
  esac
}

deps_available() {
  [ -f "$UNIT_DIR_NAME_SH" ] && [ -f "$LIST_UNITS_OF_SH" ]
}

# --- 見出しの並びが期待どおりか（`## `見出しの先頭からn行を比べる） ---
check_headings_order() {
  local file="$1" expected="$2" n actual
  n="$(printf '%s\n' "$expected" | grep -c .)"
  actual="$(grep -E '^## ' "$file" | head -n "$n")"
  [ "$actual" = "$expected" ]
}

# --- 各見出しの直後に位置づけの行があるか ---
check_placement_lines() {
  local file="$1" headings="$2" h lineno next
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    lineno="$(grep -n -F "## ${h}" "$file" | head -1 | cut -d: -f1)"
    [ -n "$lineno" ] || continue
    next="$(awk -v start="$lineno" 'NR>start && NF>0 {print; exit}' "$file")"
    case "$next" in
      "**この節の位置づけ: "*) ;;
      *) return 1 ;;
    esac
  done <<HLIST
$headings
HLIST
  return 0
}

# --- 対象の設計書の書き方の検査をhook入力のJSONで呼ぶ（--check-fileを
#     持たないため、stdinへのJSONで呼ぶ形に合わせる） ---
run_heading_addendum_check() {
  local script="$1" file="$2"
  jq -Rs --arg fp "$file" '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":.}}' \
    < "$file" | bash "$script" > /dev/null 2>/dev/null
}

run_unit_test_doc_check() {
  local script="$1" file="$2"
  bash "$script" --check-file "$file" > /dev/null 2>/dev/null
}

extract_confirmation_keys() {
  local file="$1"
  awk '
    /^## 要確認事項一覧/ { insec=1; next }
    /^## / && insec==1 { insec=0 }
    insec==1 && /^\|/ {
      line=$0
      if (line ~ /^\| *キー *\|/) next
      if (line ~ /^\|[-: ]+\|/) next
      n=split(line, cols, "|")
      key=cols[2]
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      if (key != "" && key !~ /^<.*>$/) print key
    }
  ' "$file"
}

check_confirmations_registered() {
  local doc="$1" run_dir="$2" confirmations keys k
  confirmations="${run_dir%/}/confirmations/確認事項の記録.md"
  keys="$(extract_confirmation_keys "$doc")"
  [ -n "$keys" ] || return 0
  [ -f "$confirmations" ] || return 1
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    grep -qF "| ${k} |" "$confirmations" || return 1
  done <<KEYS
$keys
KEYS
  return 0
}

check_placeholder_and_position() {
  # $1: file  戻り値: 0=両方問題なし
  local file="$1" ok=0
  if grep -qE '<[^<>]+>' "$file"; then
    echo "[FAIL] 未記入-残存: ${file} に未記入のプレースホルダーがあります" >&2
    ok=1
  fi
  if grep -qE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$file"; then
    echo "[FAIL] 位置-禁止: ${file} に実装位置(file:line)の記述があります" >&2
    ok=1
  fi
  return "$ok"
}

# 事実の項目名が本文の見出し（##・###）または表の見出し行に現れるかを確認する。
# $1: doc  $2: 事実の項目名  戻り値: 0=現れる・1=現れない
fact_key_covered() {
  local doc="$1" key="$2"
  if grep -E '^#{2,3}[[:space:]]' "$doc" | grep -qF -- "$key"; then
    return 0
  fi
  awk -v key="$key" '
    /^\|/ {
      header = $0
      if ((getline nextline) > 0) {
        if (nextline ~ /^\|[ :|-]+\|?$/ && index(header, key) > 0) { found = 1 }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$doc"
}

check_regular_unit() {
  local target="$1" run_dir="$2" unit_path="$3" kind="$4" dirname="$5" heading_script="$6" unittest_script="$7"
  local doc="${unit_path}/$(basic_doc_name "$kind")"
  local test_doc="${unit_path}/$(test_doc_name "$kind")"
  local ok=1

  if [ ! -f "$doc" ]; then
    echo "[FAIL] 文書-不在: ${doc} が実在しません" >&2
    ok=0
  fi
  if [ ! -f "$test_doc" ]; then
    echo "[FAIL] 文書-不在: ${test_doc} が実在しません" >&2
    ok=0
  fi
  [ "$ok" -eq 1 ] || return 1

  local headings expected
  headings="$(basic_expected_headings "$kind")"
  expected="$(printf '%s\n' "$headings" | sed 's/^/## /')"
  if ! check_headings_order "$doc" "$expected"; then
    echo "[FAIL] 節-欠落: ${doc} の必須見出しが順に揃っていません" >&2
    ok=0
  fi

  if ! check_placement_lines "$doc" "$headings"; then
    echo "[FAIL] 位置づけ-欠落: ${doc} に位置づけの行が無い見出しがあります" >&2
    ok=0
  fi

  check_placeholder_and_position "$doc" || ok=0

  # 既知の限界: 画面基本設計書の様式（画面の目的・画面構成…）は、設計書の書き方の
  # 決まりが定める共通の完了状態見出し（外部仕様・業務仕様・方式設計・データ仕様・
  # エラーと例外）と一致しない。screen種別ではこの共有チェッカーを呼ばず、様式の
  # 妥当性は本スクリプト自身のcheck_headings_order/check_placement_linesに委ねる
  if [ "$kind" != "screen" ]; then
    if ! run_heading_addendum_check "$heading_script" "$doc"; then
      echo "[FAIL] 規約-見出し: ${doc} が設計書の書き方の検査に不合格です" >&2
      ok=0
    fi
  fi

  if ! run_unit_test_doc_check "$unittest_script" "$test_doc"; then
    echo "[FAIL] 単体テスト規約-不合格: ${test_doc} が単体テスト設計書の決まりの検査に不合格です" >&2
    ok=0
  fi

  local facts_file="${run_dir%/}/facts/${kind}/${dirname}.json"
  if [ -f "$facts_file" ]; then
    local keys k
    keys="$(jq -r '.["事実"] // {} | to_entries[] | select((.value["値"] // []) | length > 0) | .key' "$facts_file" 2>/dev/null)"
    # 表（table）の基本設計（論理データモデル）は型・制約を書かない様式。
    # 型・制約の転記は詳細設計（テーブル定義書）のcheck-detail-design.shが見る
    if [ "$kind" = "table" ]; then
      keys="$(printf '%s\n' "$keys" | grep -vE '^(型|制約)$' || true)"
    fi
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      if ! fact_key_covered "$doc" "$k"; then
        echo "[FAIL] 事実-未転記: ${doc} に事実の項目「${k}」が転記されていません" >&2
        ok=0
      fi
    done <<KEYS
$keys
KEYS
  else
    echo "[FAIL] 事実-未転記: ${facts_file} が実在しません" >&2
    ok=0
  fi

  if ! check_confirmations_registered "$doc" "$run_dir"; then
    echo "[FAIL] 確認事項-未登録: ${doc} の要確認事項一覧のキーが確認事項の記録にありません" >&2
    ok=0
  fi

  [ "$ok" -eq 1 ]
}

check_kind() {
  local target="$1" run_dir="$2" kind="$3" heading_script="$4" unittest_script="$5" design_root="$6"
  local folder units_tsv rc
  folder="$(species_folder "$kind")"

  units_tsv="$(bash "$LIST_UNITS_OF_SH" "$target" "$kind" --lists "${design_root%/}/docs/design/lists" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "[FAIL] 一覧-不在: ${kind} の一覧を読めません（終了コード${rc}）" >&2
    return 2
  fi
  [ -n "$units_tsv" ] || return 0

  local fail=0 id name place belongs dirname unit_path
  while IFS=$'\t' read -r id name place belongs; do
    [ -n "$id" ] || continue
    dirname="$(bash "$UNIT_DIR_NAME_SH" "$id")"
    unit_path="${design_root}/docs/design/${folder}/${dirname}"

    check_regular_unit "$target" "$run_dir" "$unit_path" "$kind" "$dirname" "$heading_script" "$unittest_script" || fail=1
  done <<UNITS
$units_tsv
UNITS

  return "$fail"
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" kind="" design_root="$target"
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done
  [ -n "$run_dir" ] && [ -n "$kind" ] || usage_error

  local folder
  folder="$(species_folder "$kind")"
  if [ -z "$folder" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    exit 2
  fi

  if ! deps_available; then
    echo "[FAIL] 共有部品-不在: unit-dir-name.sh または list-units-of.sh がありません" >&2
    exit 2
  fi

  if [ ! -f "$HEADING_SCRIPT" ] || [ ! -f "$UNITTEST_SCRIPT" ]; then
    echo "[FAIL] 規約-不在: 支援ツール側の写しの検査スクリプトがありません" >&2
    exit 2
  fi

  check_kind "$target" "$run_dir" "$kind" "$HEADING_SCRIPT" "$UNITTEST_SCRIPT" "$design_root"
  local rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 2
  elif [ "$rc" -ne 0 ]; then
    echo "不合格: ${kind}" >&2
    exit 1
  fi
  echo "合格: ${kind}"
  exit 0
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/check-basic-design-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0 skip=0

  check() {
    local name="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${name}"
    else
      echo "FAIL: ${name}"
      fail=$((fail + 1))
    fi
  }

  skip_case() {
    local name="$1"
    total=$((total + 1))
    skip=$((skip + 1))
    echo "SKIP: ${name}（reverse-sharedのunit-dir-name.sh/list-units-of.shが無いため）"
  }

  # --- 使い方エラー系（共有部品に依存しない） ---
  bash "$SCRIPT_DIR/check-basic-design.sh" > "$base/usage.out" 2>"$base/usage.err"
  check "使い方-引数不足は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  # --- 対象フィクスチャを作る（検査は支援ツール側の写しの実物を使う） ---
  make_fixture() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d/docs/design/lists" \
             "$d/docs/design/screens/src_pages_OrderList.tsx"

    cat > "$d/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  }

  write_facts() {
    local run="$1"
    mkdir -p "$run/facts/screen"
    cat > "$run/facts/screen/src_pages_OrderList.tsx.json" <<'FACTEOF'
{"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx",
 "属するファイル":[],
 "事実":{"入力項目":{"値":["受注番号"],"出所":"機械","根拠":["src/pages/OrderList.tsx"]},
         "表示項目":{"値":[],"出所":"機械","根拠":[]},
         "操作":{"値":[],"出所":"機械","根拠":[]},
         "遷移":{"値":[],"出所":"機械","根拠":[]},
         "呼ぶ接続窓口":{"値":[],"出所":"機械","根拠":[]}},
 "未":["表示項目","操作","遷移","呼ぶ接続窓口"],"取り出した実行":"self-test"}
FACTEOF
  }

  write_valid_docs() {
    local unit_path="$1"
    cat > "$unit_path/画面基本設計書.md" <<'DOCEOF'
# OrderList 画面基本設計書

- 種別: 画面
- 識別子: src/pages/OrderList.tsx
- 対応する機能: 受注一覧

## §1 画面の目的
**この節の位置づけ: 現行実装**

受注の一覧を確認する。

## §2 画面構成
**この節の位置づけ: 現行実装**

一覧表とページ送りで構成する。

## §3 機能仕様（業務機能の一覧）
**この節の位置づけ: 現行実装**

一覧の検索・表示を行う。

## §4 業務ルール
**この節の位置づけ: 現行実装**

取消は行わない。

## §5 入出力の業務的意味
**この節の位置づけ: 現行実装**

### 入力項目
受注番号を入力する。

### 表示項目
一覧を表示する。

### 操作
検索する。

### 遷移
詳細画面へ遷移する。

### 呼ぶ接続窓口
一覧取得の接続窓口を呼ぶ。

## §6 画面遷移の業務文脈
**この節の位置づけ: 現行実装**

一覧から詳細へ遷移する。

## §7 関連資料
**この節の位置づけ: 現行実装**

- なし

## 要確認事項一覧

| キー | 事項 | 既定 | 状態 |
|---|---|---|---|
| 受注番号-桁数 | 受注番号の桁数 | 8桁とする | 未回答 |
DOCEOF

    cat > "$unit_path/画面単体テスト設計書.md" <<'TESTDOCEOF'
## 本書が検証するもの

| 段 | 検証する状態 | 対応する設計書 | 文書 |
|---|---|---|---|
| 単体 | 入力の受理 | 画面基本設計書 | 本書 |

## テスト対象
OrderList

## テストの粒度と自動化の方針
画面単位で自動化する

## 本書が扱わない範囲
他の画面

## §1 テスト観点

| キー | 観点 |
|---|---|
| `受注番号入力` | `受注番号を入力できる` |

## §2 テストケース一覧

| キー | 番号 | 対応する観点のキー | 入力 | 期待結果 |
|---|---|---|---|---|
| `正常系` | 1 | `受注番号入力` | `12345678` | `受理される` |

## §3 入力条件
受注番号は8桁の数字とする

## §4 期待結果
一覧に反映される

## §5 異常系

| 観点のキー | 条件 | 期待結果 |
|---|---|---|
| `受注番号入力` | `桁数不足` | `エラーを表示する` |

## §6 境界値

| 観点のキー | 境界 | 期待結果 |
|---|---|---|
| `受注番号入力` | `8桁ちょうど` | `受理される` |

## §7 網羅基準
全観点を1件以上のケースで覆う

## §8 前提条件と終了条件
前提条件は無し。終了条件はテスト結果の記録。
TESTDOCEOF
  }

  write_confirmations() {
    local run="$1"
    mkdir -p "$run/confirmations"
    cat > "$run/confirmations/確認事項の記録.md" <<'CONFEOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 受注番号-桁数 | screen/src/pages/OrderList.tsx | 業務ルール | 受注番号の桁数 | 8桁とする | 基本設計書 | 未回答 | 未回答 |
CONFEOF
  }

  run_full_cases() {
    # --- 合格-見本 ---
    local d1="$base/case1" run1="$base/run1"
    make_fixture "$d1"
    mkdir -p "$run1"
    write_facts "$run1"
    write_confirmations "$run1"
    write_valid_docs "$d1/docs/design/screens/src_pages_OrderList.tsx"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d1" --run "$run1" --kind screen > "$base/case1.out" 2>"$base/case1.err"
    check "合格-見本: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

    # --- 設計書ルート分離-対象に書かない ---
    local d1c="$base/case1-code-only" design1="$base/case1-design"
    mkdir -p "$d1c"
    make_fixture "$design1"
    write_valid_docs "$design1/docs/design/screens/src_pages_OrderList.tsx"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d1c" --run "$run1" --kind screen --design-root "$design1" > "$base/case1d.out" 2>"$base/case1d.err"
    check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"
    total=$((total + 1))
    if [ ! -e "$d1c/docs" ]; then
      echo "PASS: 設計書ルート分離-対象に書かない"
    else
      echo "FAIL: 設計書ルート分離-対象に書かない（対象側にdocsが作られています）"
      fail=$((fail + 1))
    fi

    # --- 不合格-文書不在 ---
    local d2="$base/case2" run2="$base/run2"
    make_fixture "$d2"
    mkdir -p "$run2"
    write_facts "$run2"
    write_confirmations "$run2"
    mkdir -p "$d2/docs/design/screens/src_pages_OrderList.tsx"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d2" --run "$run2" --kind screen > "$base/case2.out" 2>"$base/case2.err"
    local rc2=$?
    check "不合格-文書不在: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"
    check "不合格-文書不在: 理由に文書-不在" "$(grep -qF '文書-不在' "$base/case2.err" && echo 0 || echo 1)"

    # --- 不合格-事実未転記 ---
    local d3="$base/case3" run3="$base/run3"
    make_fixture "$d3"
    mkdir -p "$run3"
    write_facts "$run3"
    write_confirmations "$run3"
    write_valid_docs "$d3/docs/design/screens/src_pages_OrderList.tsx"
    sed -i.bak '/^### 入力項目$/,/^$/d' "$d3/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d3" --run "$run3" --kind screen > "$base/case3.out" 2>"$base/case3.err"
    local rc3=$?
    check "不合格-事実未転記: 終了コード1" "$([ "$rc3" -eq 1 ] && echo 0 || echo 1)"
    check "不合格-事実未転記: 理由に事実-未転記" "$(grep -qF '事実-未転記' "$base/case3.err" && echo 0 || echo 1)"

    # --- 不合格-確認事項未登録 ---
    local d4="$base/case4" run4="$base/run4"
    make_fixture "$d4"
    mkdir -p "$run4"
    write_facts "$run4"
    write_valid_docs "$d4/docs/design/screens/src_pages_OrderList.tsx"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d4" --run "$run4" --kind screen > "$base/case4.out" 2>"$base/case4.err"
    local rc4=$?
    check "不合格-確認事項未登録: 終了コード1" "$([ "$rc4" -eq 1 ] && echo 0 || echo 1)"
    check "不合格-確認事項未登録: 理由に確認事項-未登録" "$(grep -qF '確認事項-未登録' "$base/case4.err" && echo 0 || echo 1)"

    # --- 不合格-節の欠落 ---
    local d5="$base/case5" run5="$base/run5"
    make_fixture "$d5"
    mkdir -p "$run5"
    write_facts "$run5"
    write_confirmations "$run5"
    write_valid_docs "$d5/docs/design/screens/src_pages_OrderList.tsx"
    sed -i.bak '/^## §2 画面構成$/,/^$/d' "$d5/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d5" --run "$run5" --kind screen > "$base/case5.out" 2>"$base/case5.err"
    local rc5=$?
    check "不合格-節の欠落: 終了コード1" "$([ "$rc5" -eq 1 ] && echo 0 || echo 1)"
    check "不合格-節の欠落: 理由に節-欠落" "$(grep -qF '節-欠落' "$base/case5.err" && echo 0 || echo 1)"

    # --- 支援ツール側の写しが無い（一時的にどかして確かめ、必ず戻す） ---
    local d6="$base/case6" run6="$base/run6"
    make_fixture "$d6"
    mkdir -p "$run6"
    mv "$HEADING_SCRIPT" "${HEADING_SCRIPT}.case6-moved"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d6" --run "$run6" --kind screen > "$base/case6.out" 2>"$base/case6.err"
    local rc6=$?
    mv "${HEADING_SCRIPT}.case6-moved" "$HEADING_SCRIPT"
    check "規約不在: 終了コード2" "$([ "$rc6" -eq 2 ] && echo 0 || echo 1)"
    check "規約不在: 理由に規約-不在" "$(grep -qF '規約-不在' "$base/case6.err" && echo 0 || echo 1)"

    # --- 一覧が無い種別 ---
    local d7="$base/case7" run7="$base/run7"
    make_fixture "$d7"
    mkdir -p "$run7"
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d7" --run "$run7" --kind api > "$base/case7.out" 2>"$base/case7.err"
    local rc7=$?
    check "一覧不在: 終了コード2" "$([ "$rc7" -eq 2 ] && echo 0 || echo 1)"
    check "一覧不在: 理由に一覧-不在" "$(grep -qF '一覧-不在' "$base/case7.err" && echo 0 || echo 1)"

    # --- 機能の単位（機能設計書・機能単体テスト設計書） ---
    local d8="$base/case8" run8="$base/run8"
    make_fixture "$d8"
    mkdir -p "$run8/facts/feature" "$d8/docs/design/features/受注"
    cat > "$d8/docs/design/lists/feature.json" <<'FEATFIXEOF'
[
  {"種別":"feature","識別子":"受注","名前":"受注","場所":"受注","根拠":"","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FEATFIXEOF
    cat > "$run8/facts/feature/受注.json" <<'FEATFACTEOF'
{"種別":"feature","識別子":"受注","名前":"受注","場所":"受注",
 "属するファイル":[],
 "事実":{"含む単位":{"値":["screen: src/pages/OrderList.tsx"],"出所":"機械","根拠":["受注"]}},
 "未":[],"取り出した実行":"self-test"}
FEATFACTEOF
    cat > "$d8/docs/design/features/受注/機能設計書.md" <<'FEATDOCEOF'
# 受注 機能設計書

## §1 機能概要
**この節の位置づけ: 現行実装**

受注業務をまとめる。

## §2 機能の範囲
**この節の位置づけ: 現行実装**

### 含む単位

| 種別 | 識別子 | 役割 |
|---|---|---|
| screen | src/pages/OrderList.tsx | 一覧表示 |

## §3 業務フロー
**この節の位置づけ: 現行実装**

受注一覧から詳細へ遷移する。

## §4 業務ルール
**この節の位置づけ: 現行実装**

取消は行わない。

## §5 データ
**この節の位置づけ: 現行実装**

受注を扱う。

## §6 構成要素間の状態受け渡し
**この節の位置づけ: 現行実装**

一覧から詳細へ識別子を渡す。

## §7 呼び出し仕様
**この節の位置づけ: 現行実装**

一覧取得の接続窓口を呼ぶ。

## §8 エラーと業務メッセージ
**この節の位置づけ: 現行実装**

通信失敗は再試行しない。

## §9 非機能
**この節の位置づけ: 現行実装**

性能要件は無し。

## §10 共通仕様への準拠
**この節の位置づけ: 現行実装**

共通部品を利用する。

## §11 関連資料
**この節の位置づけ: 現行実装**

- なし

## 要確認事項一覧

| キー | 事項 | 既定 | 状態 |
|---|---|---|---|
FEATDOCEOF

    cat > "$d8/docs/design/features/受注/機能単体テスト設計書.md" <<'FEATTESTDOCEOF'
## 本書が検証するもの

| 段 | 検証する状態 | 対応する設計書 | 文書 |
|---|---|---|---|
| 単体 | 一覧の表示 | 機能設計書 | 本書 |

## テスト対象
受注

## テストの粒度と自動化の方針
機能単位で自動化する

## 本書が扱わない範囲
他の機能

## §1 テスト観点

| キー | 観点 |
|---|---|
| `一覧表示` | `一覧を表示できる` |

## §2 テストケース一覧

| キー | 番号 | 対応する観点のキー | 入力 | 期待結果 |
|---|---|---|---|---|
| `正常系` | 1 | `一覧表示` | `受注一覧を開く` | `一覧が表示される` |

## §3 入力条件
受注一覧を開く

## §4 期待結果
一覧が表示される

## §5 異常系

| 観点のキー | 条件 | 期待結果 |
|---|---|---|
| `一覧表示` | `通信失敗` | `エラーを表示する` |

## §6 境界値

| 観点のキー | 境界 | 期待結果 |
|---|---|---|
| `一覧表示` | `0件` | `空の一覧を表示する` |

## §7 網羅基準
全観点を1件以上のケースで覆う

## §8 前提条件と終了条件
前提条件は無し。終了条件はテスト結果の記録。
FEATTESTDOCEOF
    bash "$SCRIPT_DIR/check-basic-design.sh" "$d8" --run "$run8" --kind feature > "$base/case8.out" 2>"$base/case8.err"
    check "機能-機能設計書で合格: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  }

  if deps_available; then
    run_full_cases
  else
    skip_case "合格-見本"
    skip_case "不合格-文書不在"
    skip_case "不合格-事実未転記"
    skip_case "不合格-確認事項未登録"
    skip_case "不合格-節の欠落"
    skip_case "規約不在"
    skip_case "一覧不在"
    skip_case "機能-機能設計書で合格"
    if deps_available; then
      echo "共有部品を再確認し本体ケースを実行します"
      run_full_cases
    fi
  fi

  echo "実行 ${total} 件 / 失敗 ${fail} 件 / skip ${skip} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================
# エントリポイント
# ============================================================

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

run_main "$@"
