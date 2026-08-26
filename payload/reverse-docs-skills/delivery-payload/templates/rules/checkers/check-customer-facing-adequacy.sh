#!/usr/bin/env bash
# 顧客へ提示する文書としての適合を検査する。
#
# delivery-payload/references/customer-facing-terms.json が定める語彙で、
# 生成物（<project_root> 配下の基本設計書・詳細設計書、および生成HTML）を
# 走査する。
#   machine=true の語: 出現したら FAIL（機械で確定する不合格）
#   machine="detect-only" の語: 出現したら REVIEW（人手の判定待ち。合否には
#     影響しない。第5=実装言語の用語と略語・第6=指示語の自己完結が対象）
#
# 走査対象は <project_root> 配下の生成物に限る。テンプレート
# （delivery-payload/templates/）と本検査が読む定義ファイル自身は走査しない。
# 「納品先」「納品物」等の語が規約・テンプレートの本文で正当に使われている
# ため、対象を絞らないと規約が自分自身を不合格にする。
#
# REVIEW は第5・第6の機械化できない部分（自然文の意味の判定）を人手へ
# 引き継ぐための出力であり、合否には影響しない。REVIEW の件数・該当箇所を
# 出力しないと、人手の判定が実行されないまま検査が通ってしまう。この出力
# だけでは「人手が実際に確認したか」までは保証できず、残余のリスクとして
# 残る（設計の限界）。人手の判定手段自体（誰が・いつ確認するか）は本検査の
# 範囲外とする。
#
# 使い方:
#   check-customer-facing-adequacy.sh <project_root>
#   check-customer-facing-adequacy.sh --self-test
#
# 終了コード:
#   0 = FAILなし（REVIEWのみ、または該当なし）
#   1 = FAILあり
#   2 = 判定不能（mktemp失敗。実行環境のサンドボックス制約等）
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TERMS_FILE="$SCRIPT_DIR/../../../references/customer-facing-terms.json"

terms_file() {
  printf '%s\n' "${CUSTOMER_FACING_TERMS_FILE:-$DEFAULT_TERMS_FILE}"
}

validate_terms_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: 対応定義ファイルが存在しません: $file" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required" >&2
    return 1
  fi
  if ! jq -e '
    (.terms | type == "array") and (.terms | length > 0) and
    (.terms | all(
      type == "object" and
      (.term | type == "string") and (.term | length > 0) and
      (.category | type == "string") and (.category | length > 0) and
      (.machine == true or .machine == "detect-only") and
      (.matchType == "exact" or .matchType == "pattern")
    ))
  ' "$file" >/dev/null; then
    echo "ERROR: 対応定義ファイルの形式が不正です: $file" >&2
    return 1
  fi
}

# 対象ファイル一覧（基本設計書.md・詳細設計書.md・*.html）を返す。
target_files() {
  local project_root="$1"
  find "$project_root" -type f \
    \( -name '*基本設計書.md' -o -name '*詳細設計書.md' -o -name '*.html' \) 2>/dev/null | sort
}

# 語の検出を行う。matchType=exact は grep -F（固定文字列・LC_ALL=C。
# 1-231の教訓どおり多バイト文字列の完全一致比較にはLC_ALL=Cを明示する）。
# matchType=pattern は grep -E（正規表現・LC_ALL=en_US.UTF-8。1-235で
# 実測したとおり、全角文字を含む正規表現をLC_ALL=Cで解釈すると壊れる）。
# 同一スクリプト内で用途に応じてロケールを使い分け、どちらか一方に統一
# しない。呼び出し元の環境変数にLC_ALL=Cが前置きされていても、pattern側は
# コマンド呼び出しへ都度LC_ALL=en_US.UTF-8を明示するため壊れない。
_grep_matches() {
  local match_type="$1" term="$2" file="$3"
  if [ "$match_type" = "pattern" ]; then
    LC_ALL=en_US.UTF-8 grep -n -E -- "$term" "$file" 2>/dev/null || true
  else
    grep -n -F -- "$term" "$file" 2>/dev/null || true
  fi
}

check_document() {
  local terms_json="$1" file="$2" rc=0
  local term category machine_flag match_type
  while IFS=$'\t' read -r term category machine_flag match_type; do
    [ -n "$term" ] || continue
    local match line no_
    while IFS=: read -r no_ match; do
      [ -n "$no_" ] || continue
      if [ "$machine_flag" = "true" ]; then
        echo "FAIL ${category}-${term} ${file}:${no_}: ${match}"
        rc=1
      else
        echo "REVIEW ${category}-${term} ${file}:${no_}: ${match}"
      fi
    done < <(_grep_matches "$match_type" "$term" "$file")
  done < <(jq -r '.terms[] | [.term, .category, (.machine|tostring), .matchType] | @tsv' "$terms_json")
  return "$rc"
}

run_check() {
  local project_root="$1" terms_json rc=0 checked_count=0 file
  terms_json="$(terms_file)"

  if [ ! -d "$project_root" ]; then
    echo "ERROR: ディレクトリが存在しません: $project_root" >&2
    return 1
  fi
  validate_terms_file "$terms_json" || return 1

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    checked_count=$((checked_count + 1))
    check_document "$terms_json" "$file" || rc=1
  done < <(target_files "$project_root")

  if [ "$checked_count" -eq 0 ]; then
    echo "ERROR: 検査対象の生成物が0件です: project_root=$project_root" >&2
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
      "${TMPDIR:-/tmp}"/customer-facing-adequacy-self-test.*)
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
    if ! dir="$(mktemp -d "${TMPDIR:-/tmp}/customer-facing-adequacy-self-test.XXXXXX" 2>/dev/null)" || [ -z "$dir" ]; then
      echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
      exit 2
    fi
    SELF_TEST_DIRS+=("$dir")
    printf '%s\n' "$dir"
  }
  write_terms() {
    cat > "$1" <<'JSON'
{
  "terms": [
    {"term": "納品先", "category": "第2: 第三者呼称", "machine": true, "matchType": "exact"},
    {"term": "対象コード", "category": "第3: 作る側の事情語", "machine": true, "matchType": "exact"},
    {"term": "パッケージ", "category": "第5: 実装言語の用語と略語", "machine": "detect-only", "matchType": "exact"},
    {"term": "から移した", "category": "第3: 作る側の事情語", "machine": true, "matchType": "pattern"}
  ]
}
JSON
  }

  # 検収1: machine=true の語が本文に無ければ終了コード0・出力0件。
  local tmp_1 terms_1 doc_1 out_1 rc_1
  tmp_1="$(new_tmp_dir)"
  terms_1="$tmp_1/terms.json"
  write_terms "$terms_1"
  mkdir -p "$tmp_1/api"
  doc_1="$tmp_1/api/API詳細設計書.md"
  cat > "$doc_1" <<'DOC'
# 注文API API詳細設計書

対象読者が確認する内容を記す。
DOC
  out_1="$(CUSTOMER_FACING_TERMS_FILE="$terms_1" run_check "$tmp_1")"; rc_1=$?
  assert_eq "検収1-終了コード" 0 "$rc_1"
  assert_eq "検収1-出力0件" '' "$out_1"
  rm -rf "$tmp_1"

  # 検収2: machine=true の語（第2: 第三者呼称）が見つかれば不合格。
  local tmp_2 terms_2 doc_2 out_2 rc_2
  tmp_2="$(new_tmp_dir)"
  terms_2="$tmp_2/terms.json"
  write_terms "$terms_2"
  mkdir -p "$tmp_2/api"
  doc_2="$tmp_2/api/API詳細設計書.md"
  cat > "$doc_2" <<'DOC'
# 注文API API詳細設計書

納品先に確認していただく事項である。
DOC
  out_2="$(CUSTOMER_FACING_TERMS_FILE="$terms_2" run_check "$tmp_2")"; rc_2=$?
  assert_eq "検収2-終了コード" 1 "$rc_2"
  assert_contains "検収2-第三者呼称をFAIL" 'FAIL 第2: 第三者呼称-納品先' "$out_2"
  rm -rf "$tmp_2"

  # 検収3: machine=true の語（第3: 作る側の事情語）が見つかれば不合格。
  local tmp_3 terms_3 doc_3 out_3 rc_3
  tmp_3="$(new_tmp_dir)"
  terms_3="$tmp_3/terms.json"
  write_terms "$terms_3"
  mkdir -p "$tmp_3/api"
  doc_3="$tmp_3/api/API詳細設計書.md"
  cat > "$doc_3" <<'DOC'
# 注文API API詳細設計書

対象コードの位置は本書に含めない。
DOC
  out_3="$(CUSTOMER_FACING_TERMS_FILE="$terms_3" run_check "$tmp_3")"; rc_3=$?
  assert_eq "検収3-終了コード" 1 "$rc_3"
  assert_contains "検収3-作る側の事情語をFAIL" 'FAIL 第3: 作る側の事情語-対象コード' "$out_3"
  rm -rf "$tmp_3"

  # 検収4: machine="detect-only" の語（第5）は REVIEW を出すが終了コードは0のまま。
  local tmp_4 terms_4 doc_4 out_4 rc_4
  tmp_4="$(new_tmp_dir)"
  terms_4="$tmp_4/terms.json"
  write_terms "$terms_4"
  mkdir -p "$tmp_4/api"
  doc_4="$tmp_4/api/API詳細設計書.md"
  cat > "$doc_4" <<'DOC'
# 注文API API詳細設計書

パッケージの構成を説明する。
DOC
  out_4="$(CUSTOMER_FACING_TERMS_FILE="$terms_4" run_check "$tmp_4")"; rc_4=$?
  assert_eq "検収4-detect-onlyは終了コード0" 0 "$rc_4"
  assert_contains "検収4-REVIEWを出力する" 'REVIEW 第5: 実装言語の用語と略語-パッケージ' "$out_4"
  assert_not_contains "検収4-FAILは出さない" 'FAIL' "$out_4"
  rm -rf "$tmp_4"

  # 検収5（1-238）: matchType=pattern の語（文末表現・言い回し）が本文に
  # あれば不合格。「移送」（exact・名詞）とは表記形が違う「から移した」
  # （pattern・動詞句）を、既存の exact 判定へ影響を与えずに検出できること
  # を確認する。
  local tmp_p1 terms_p1 doc_p1 out_p1 rc_p1
  tmp_p1="$(new_tmp_dir)"
  terms_p1="$tmp_p1/terms.json"
  write_terms "$terms_p1"
  mkdir -p "$tmp_p1/api"
  doc_p1="$tmp_p1/api/API詳細設計書.md"
  cat > "$doc_p1" <<'DOC'
# 注文API API詳細設計書

要確認事項は3つの設計書から移した。
DOC
  out_p1="$(CUSTOMER_FACING_TERMS_FILE="$terms_p1" run_check "$tmp_p1")"; rc_p1=$?
  assert_eq "検収5-パターン一致の終了コード" 1 "$rc_p1"
  assert_contains "検収5-文末表現をFAIL" 'FAIL 第3: 作る側の事情語-から移した' "$out_p1"
  rm -rf "$tmp_p1"

  # 検収6（1-238）: 呼び出し元の環境変数に LC_ALL=C が前置きされていても、
  # matchType=pattern（全角文字を含む正規表現）が正しく検出されること。
  # 1-235 で実測したとおり、LC_ALL=C は awk/grep の全角文字マッチングを
  # 壊すため、pattern 側の grep 呼び出しへ都度 LC_ALL=en_US.UTF-8 を明示
  # する設計にしている。この回帰テストはその設計が機能していることを
  # 確認する。
  local tmp_p2 terms_p2 doc_p2 out_p2 rc_p2
  tmp_p2="$(new_tmp_dir)"
  terms_p2="$tmp_p2/terms.json"
  write_terms "$terms_p2"
  mkdir -p "$tmp_p2/api"
  doc_p2="$tmp_p2/api/API詳細設計書.md"
  cat > "$doc_p2" <<'DOC'
# 注文API API詳細設計書

要確認事項は3つの設計書から移した。
DOC
  out_p2="$(LC_ALL=C CUSTOMER_FACING_TERMS_FILE="$terms_p2" run_check "$tmp_p2")"; rc_p2=$?
  assert_eq "検収6-呼び出し元LC_ALL=C下でも終了コード1" 1 "$rc_p2"
  assert_contains "検収6-呼び出し元LC_ALL=C下でも文末表現をFAIL" 'FAIL 第3: 作る側の事情語-から移した' "$out_p2"
  rm -rf "$tmp_p2"

  # 検収7（1-238）: 既存の exact 判定（第三者呼称・作る側の事情語）は、
  # pattern 判定を追加した後も引き続き機能する（既存の完全一致の判定を
  # 壊していないことの確認）。
  local tmp_p3 terms_p3 doc_p3 out_p3 rc_p3
  tmp_p3="$(new_tmp_dir)"
  terms_p3="$tmp_p3/terms.json"
  write_terms "$terms_p3"
  mkdir -p "$tmp_p3/api"
  doc_p3="$tmp_p3/api/API詳細設計書.md"
  cat > "$doc_p3" <<'DOC'
# 注文API API詳細設計書

納品先に確認していただく。対象コードの位置は本書に含めない。
DOC
  out_p3="$(CUSTOMER_FACING_TERMS_FILE="$terms_p3" run_check "$tmp_p3")"; rc_p3=$?
  assert_eq "検収7-既存exact判定は引き続き終了コード1" 1 "$rc_p3"
  assert_contains "検収7-既存exact判定(第三者呼称)は健在" 'FAIL 第2: 第三者呼称-納品先' "$out_p3"
  assert_contains "検収7-既存exact判定(作る側の事情語)は健在" 'FAIL 第3: 作る側の事情語-対象コード' "$out_p3"
  rm -rf "$tmp_p3"

  # 追加回帰1: 走査対象は基本設計書・詳細設計書・HTMLのみ。それ以外の
  # ファイル（例: メモ.md）に対象語があっても検査対象に含めない。
  local tmp_5 terms_5 out_5 rc_5
  tmp_5="$(new_tmp_dir)"
  terms_5="$tmp_5/terms.json"
  write_terms "$terms_5"
  mkdir -p "$tmp_5/api"
  cat > "$tmp_5/api/API詳細設計書.md" <<'DOC'
# 注文API API詳細設計書

本文。
DOC
  cat > "$tmp_5/api/メモ.md" <<'DOC'
納品先への申し送り事項。
DOC
  out_5="$(CUSTOMER_FACING_TERMS_FILE="$terms_5" run_check "$tmp_5")"; rc_5=$?
  assert_eq "追加回帰1-対象外ファイルの語は無視され終了コード0" 0 "$rc_5"
  assert_eq "追加回帰1-出力0件" '' "$out_5"
  rm -rf "$tmp_5"

  # 追加回帰2: 実物の定義ファイル（customer-facing-terms.json）が形式適合する。
  local rc_real
  validate_terms_file "$DEFAULT_TERMS_FILE" >/dev/null 2>&1; rc_real=$?
  assert_eq "追加回帰2-実物定義ファイルの形式適合" 0 "$rc_real"

  # 追加回帰3: 実物定義ファイルが7カテゴリの語をすべて持つ（1-261で
  # 第7: 対話エージェントの編集単位語を追加した）。
  local categories_present
  categories_present="$(jq -r '[.terms[].category] | unique | length' "$DEFAULT_TERMS_FILE")"
  assert_eq "追加回帰3-7カテゴリすべての語が存在する" "7" "$categories_present"

  # 追加回帰4: LC_ALL=C を明示していることを自己確認する。
  local locale_out
  locale_out="$(LC_ALL=en_US.UTF-8 bash -c 'export LC_ALL=C; echo "$LC_ALL"')"
  assert_eq "追加回帰4-LC_ALL=Cが有効" "C" "$locale_out"

  # 追加回帰5（1-238）: 実物定義ファイルに matchType=pattern の語が
  # 3件（ためである・から移した・本書の最初の節に置いた）存在する。
  local pattern_count
  pattern_count="$(jq -r '[.terms[] | select(.matchType == "pattern")] | length' "$DEFAULT_TERMS_FILE")"
  assert_eq "追加回帰5-pattern語彙が3件存在する" "3" "$pattern_count"

  # 追加回帰6（1-238）: 実物定義ファイルの全エントリが matchType を持つ
  # （exact/pattern いずれか。validate_terms_file の fail-closed 検証と
  # 一致することの二重確認）。
  local missing_match_type
  missing_match_type="$(jq -r '[.terms[] | select(.matchType != "exact" and .matchType != "pattern")] | length' "$DEFAULT_TERMS_FILE")"
  assert_eq "追加回帰6-matchType欠落は0件" "0" "$missing_match_type"

  # 追加回帰7（1-265）: 言い換え後の様式（原本→実装・納品物→本資料・
  # 抽出→取り出し）が、実物定義ファイル（DEFAULT_TERMS_FILE）に対して
  # 不合格にならないこと。配布物自身の様式・定義・生成物がこの3語を含む
  # 事故の再発を防ぐ回帰テスト。
  local tmp_7 doc_7 out_7 rc_7
  tmp_7="$(new_tmp_dir)"
  mkdir -p "$tmp_7/api"
  doc_7="$tmp_7/api/API詳細設計書.md"
  cat > "$doc_7" <<'DOC'
# 注文API API詳細設計書

情報源は API 一覧の拡張マニフェストと実装コードの読解です。実装から確定できない事項は推測で埋めず、空欄のままとする。
選ばなかった選択肢または不採用理由を実装から読み取れない場合は `不明（実装に記述なし）` とし、補わない。

本資料ごとに、出力先・生成元・状態・理由を示す。
メッセージの取り出し元は本節を参照する。
DOC
  out_7="$(run_check "$tmp_7")"; rc_7=$?
  assert_eq "追加回帰7-言い換え後の様式は終了コード0" 0 "$rc_7"
  assert_not_contains "追加回帰7-原本はFAILしない(既に出現なし)" 'FAIL 第3: 作る側の事情語-原本' "$out_7"
  assert_not_contains "追加回帰7-納品物はFAILしない(既に出現なし)" 'FAIL 第2: 第三者呼称-納品物' "$out_7"
  assert_not_contains "追加回帰7-抽出はFAILしない(既に出現なし)" 'FAIL 第3: 作る側の事情語-抽出' "$out_7"
  rm -rf "$tmp_7"

  # 追加回帰8（1-261）: 第7: 対話エージェントの編集単位語（機械化定義の
  # write_terms ではなく、実物定義ファイル DEFAULT_TERMS_FILE を使う）。
  # 対話エージェント自身の編集単位（やり取りの回・下書きファイル）を指す
  # 語が本文に混入すれば不合格になることを確認する。
  local tmp_8 doc_8 out_8 rc_8
  tmp_8="$(new_tmp_dir)"
  mkdir -p "$tmp_8/api"
  doc_8="$tmp_8/api/API詳細設計書.md"
  cat > "$doc_8" <<'DOC'
# 注文API API詳細設計書

本ターンで追記した内容を以下にまとめる。下書きファイルの内容をそのまま転記した。
DOC
  out_8="$(run_check "$tmp_8")"; rc_8=$?
  assert_eq "追加回帰8-対話エージェントの編集単位語の終了コード" 1 "$rc_8"
  assert_contains "追加回帰8-本ターンをFAIL" 'FAIL 第7: 対話エージェントの編集単位語-本ターン' "$out_8"
  assert_contains "追加回帰8-下書きファイルをFAIL" 'FAIL 第7: 対話エージェントの編集単位語-下書きファイル' "$out_8"
  rm -rf "$tmp_8"

  # 追加回帰9（1-238）: 配布する全種別の設計書テンプレートが、冒頭案内の
  # 記入規則を適用すると宣言している。ファイル総数との一致で、新しい種別を
  # 追加した際の宣言漏れも不合格にする。
  local reverse_template_root template_root_rc template_count guidance_count style_guidance_count
  reverse_template_root="$SCRIPT_DIR/../../リバース検証"
  [ -d "$reverse_template_root" ]; template_root_rc=$?
  assert_eq "追加回帰9-実物テンプレートディレクトリが存在" 0 "$template_root_rc"
  template_count="$(find "$reverse_template_root" -type f -name '*.md' | wc -l | tr -d ' ')"
  guidance_count="$(grep -rl 'INTRODUCTION_GUIDANCE' "$reverse_template_root" --include='*.md' | wc -l | tr -d ' ')"
  assert_eq "追加回帰9-全テンプレートが冒頭記入規則を宣言" "$template_count" "$guidance_count"
  style_guidance_count="$(grep -rl '生成する本文の自由記述は敬体（です・ます）で書く。' "$reverse_template_root" --include='*.md' | wc -l | tr -d ' ')"
  assert_eq "追加回帰9-全テンプレートが本文の敬体を指定" "$template_count" "$style_guidance_count"

  # 追加回帰10（1-238）: 2節の試験入力から冒頭案内を組み立て、節数と
  # 「節・内容・読み手へのお願い」の案内行数が一致することを確認する。
  local tmp_intro intro_doc section_count guidance_row_count
  tmp_intro="$(new_tmp_dir)"
  intro_doc="$tmp_intro/複数節設計書.md"
  cat > "$intro_doc" <<'DOC'
# 注文API 設計書

| 節 | 内容 | 読み手へのお願い |
|---|---|---|
| §1 利用条件 | 利用者と前提条件 | 条件が業務運用と一致するか確認してください。 |
| §2 応答 | 正常時と異常時の応答 | 呼出元が各応答を処理できるか確認してください。 |

## §1 利用条件

本文。

## §2 応答

本文。
DOC
  section_count="$(grep -c '^## §' "$intro_doc")"
  guidance_row_count="$(grep -c '^| §' "$intro_doc")"
  assert_eq "追加回帰10-複数節の案内行数が節数と一致" "$section_count" "$guidance_row_count"
  assert_contains "追加回帰10-内容列を持つ" '| 節 | 内容 | 読み手へのお願い |' "$(cat "$intro_doc")"
  rm -rf "$tmp_intro"

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
