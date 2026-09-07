#!/usr/bin/env bash
set -u

# record-acceptance.sh — 基本設計の完了判定の記録を書く（単位・共通設計文書）
#
# 目的:
#   合格の記録は文書の同一性（sha256）とコミットを持たなければ、後で文書が
#   変わったときに古い合格が生き残る。記録の形を1つに決め、詳細設計へ進む
#   機能（check-acceptance-record.sh）がその形だけを読めば済むようにする。
#
# 使い方:
#   record-acceptance.sh <対象リポジトリのルート> --run <実行フォルダ> \
#     --kind <種別> --unit <識別子> --verdict <合格|不合格> \
#     --viewpoints "<観点=合|否|要確認;...>" --judged "<文書名>=<sha256>;..." \
#     [--reason "<理由>"] [--design-root <設計書のルート>] [--no-units-status]
#   record-acceptance.sh <対象リポジトリのルート> --run <実行フォルダ> \
#     --common <文書名> --verdict <合格|不合格> \
#     --viewpoints "<観点=合|否|要確認;...>" --judged "<文書名>=<sha256>" \
#     [--reason "<理由>"] [--design-root <設計書のルート>]
#   record-acceptance.sh --self-test
#
# --no-units-status を付けると単位の状態のファイルへ書き込まない（単位の
# 記録--kind/--unitのときだけ有効。共通設計文書の記録--commonは元々
# 単位の状態のファイルを触らないため対象外）。
#
# 単位・共通設計文書の保留は廃止（2026-09-05）。判定は合格・不合格の2値。
#
# --judged は判定した時点の文書の同一性の値（sha256）。判定の直前に
# `shasum -a 256 <文書>` で取る。共通設計文書は1件、単位は基本設計書の1件
# を渡す。実行フォルダのrun.jsonの「テスト設計書の出力」が「出力する」の
# ときだけ単体テスト設計書も加えた2件を渡す。「出力しない」は基本設計書の
# 1件のみ（第1回改善指示書1-31）。`--run`は常に必須のため、`--run`が
# 指定されているのに設定が読めない・値が不正なときは記録を作らず判定不能
# で止める（黙って「出力しない」に落とすと、単体テスト設計書が記録の
# `文書`から静かに抜け落ちる。2026-09-07反証対応）。記録を書く直前に現在
# の値と突き合わせ、1件でも一致しなければ記録を作らない（第1回改善指示書
# 1-23）。
#
# --design-root の既定は対象リポジトリのルート。合格の記録・基本設計書・
# 単体テスト設計書・共通設計文書は設計書のルート配下で読み書きする。
# コミットの値は対象コード（--design-root ではなく対象）のHEADを使う。
#
# 出力:
#   <対象>/ai-work/records/basic-design-acceptance/<種別>-<単位のフォルダ名>.json
#   （共通設計文書は common-<文書名>.json）に
#   {"種別","識別子","文書":{"<文書名>":"<sha256>"},"コミット":"<対象のHEAD>",
#    "判定","観点":{...},"理由","判定した実行"}
#
# 単位のフォルダ名はreverse-shared/scripts/list-units-of.shの出力（5列目）
# から得る（unit-dir-name.shは呼ばない）。一覧の元データが無い、または該当
# する識別子の行が無いときだけ、unit-dir-name.shへ識別子を渡した値を使う
# （一覧不在時の現行維持のためのfallbackであり唯一の定義の再実装ではない）。
# 種別ごとの文書名（基本設計書・単体テスト設計書。featureも他の6種別と
# 同じく2件）はreverse-shared/scripts/design-doc-name.shで作る
# （check-basic-design.shと共有し、実名の二重定義を持たない）。単位の
# 記録はreverse-shared/scripts/units-status.shの完了判定も更新する（無ければ
# この更新だけ省く）。
#
# 観点の値に要確認が含まれるとき、--reasonへ確認事項一覧のキーを含める。
# キーが<実行フォルダ>/confirmations/確認事項の記録.mdに実在しなければ
# 記録を作らない（第1回改善指示書1-18）。--runは常に必須（使い方の誤り）
# なので、確認事項の記録.mdが読めない場合は要確認-判定不能として記録を
# 作らない（2026-09-06改善。読む側のcheck-acceptance-record.shと同じ区別）。
#
# 観点のキーが空文字列の項目（例: "外部仕様の確定=合;=合"）も観点-キー空
# として拒む（読む側が空のキーを観点の値-不正として拒むのと対にする）。
#
# 終了コード:
#   0 = 記録を書いた
#   1 = 判定した時点と記録を書く時点で文書の同一性の値が食い違う（記録を作らない）
#   2 = 使い方の誤り・種別が不正・判定の値が不正・観点のキーが空・
#       要確認のキーが確認事項の記録に無い・確認事項の記録.mdを参照できない
#       （判定不能）
#
# 保守責任者: 人手（ユーザー）。記録の形（キー）を変えるときは、本スクリプトと
#   check-acceptance-record.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ファイルの更新時刻を秒で返す。系を判定して分岐する（第1回改善指示書1-39）。
# stat の -f は macOS では更新時刻、GNU coreutils ではファイルシステムの情報を
# 指す。-c は macOS に無い。先に -c を試し、失敗したら -f を使う。
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
LIST_UNITS_OF_SH="${SCRIPT_DIR}/list-units-of.sh"
DESIGN_DOC_NAME_SH="${SCRIPT_DIR}/design-doc-name.sh"
UNITS_STATUS_SH="${SCRIPT_DIR}/units-status.sh"
READ_RUN_SH="${SCRIPT_DIR}/read-run.sh"
# shellcheck source=viewpoint-validation.sh
. "${SCRIPT_DIR}/viewpoint-validation.sh"

# 実行フォルダのrun.jsonから「テスト設計書の出力」を読む。呼び出し元は
# `--run`を常に必須とするため、run_dirは常に読む（空文字列は使い方の誤りで
# usage_errorに掛かるため通常は到達しないが、到達してもread-run.shが
# run.json不在として判定不能を返すだけであり、特別扱いの分岐は持たない。
# 2026-09-07反証対応・第2版で「run_dirが空なら出力しないとみなす」という
# 到達不能な分岐を削った）。read-run.shが無い・失敗する・値が「出力する」
# ／「出力しない」のどちらでもないときは、標準出力に何も書かず終了コード2
# を返して呼び出し元へ判定不能を伝える（黙って「出力しない」に落とすと、
# 「出力する」構成の単位で単体テスト設計書のsha256が記録の`文書`から静かに
# 抜け落ち、以後その文書を消しても記録と一致し続けて合格し続ける。
# 2026-09-07反証対応）。判定不能のときは、値の代わりに理由（read-run.shの
# 検査キー`run-不在`／`jq-不在`／`run-形式`／`キー-不在`、または`値-不正`・
# `共有部品-不在`）を標準出力へ書く。呼び出し元は`$(...)`で受け取った文字列を
# そのままエラーメッセージへ添える（呼び出し元が`$(...)`で呼ぶとサブシェルに
# なりグローバル変数の書き換えが伝わらないため、戻り値の文字列そのものに理由
# を載せる。2026-09-07反証対応・第2版）。
# check-basic-design.shの`tests_output_of()`（検査側。設定が読めないときは
# 「出力しない」に倒す既定を持つ）とは既定が異なるため関数名を分け、複製では
# ないことを明示する（第1回改善指示書1-31）。
#
# 値の受け取り方: `$(...)`はコマンドの標準出力の末尾の改行をすべて取り除く。
# run.jsonの値そのものに末尾の改行や空白が混ざっていても素通しで取り除かれ、
# 「出力する」のような正規値と誤って一致してしまう（2026-09-07反証対応・
# 第3版・所見2）。改行では終わらない番人文字列と終了コードを値の直後に続けて
# 1回の`$(...)`で受け取ることで、末尾の取り除きを起こさせず、値をそのまま
# 復元する。read-run.shは正常時に必ずjq自身の終端改行を1つ付けて返す
# （`jq -r`の仕様）ため、番人文字列を取り除いた直後にその1つだけを取り除き、
# 残りの改行・空白（値そのものに混ざっていた分）は取り除かずに完全一致で
# 判定する。
tests_output_setting_of() {
  local run_dir="$1" raw value rc err_file reason marker
  if [ ! -f "$READ_RUN_SH" ]; then
    echo "共有部品-不在"
    return 2
  fi
  err_file="$(mktemp "${TMPDIR:-/tmp}/tests-output-setting.XXXXXX")" || {
    echo "一時領域-不可"
    return 2
  }
  # 関数内のtrap ... RETURNは呼び出し元が持つRETURN trapを上書きしうる
  # 潜在欠陥のため使わない。成功・失敗いずれの経路でも読み取り直後に
  # rm -fで後始末してから値を返す（2026-09-07反証対応・第4版・所見2）。
  marker="__設定終端__"
  raw="$(bash "$READ_RUN_SH" "$run_dir" "テスト設計書の出力" 2>"$err_file"; printf '%s%d' "$marker" "$?")"
  rc="${raw##*"${marker}"}"
  value="${raw%"${marker}${rc}"}"
  if [ "$rc" -ne 0 ]; then
    reason="$(sed -n 's/^\[FAIL\] \([^:]*\):.*/\1/p' "$err_file" | head -1)"
    rm -f "$err_file"
    echo "${reason:-理由不明}"
    return 2
  fi
  rm -f "$err_file"
  value="${value%$'\n'}"
  case "$value" in
    出力する|出力しない)
      echo "$value"
      return 0
      ;;
    *)
      echo "値-不正"
      return 2
      ;;
  esac
}

# --runのフォルダのrun.jsonの実在・可読性・「実行の識別子」キーの実在と
# 値の形（空でない文字列）を確かめる。単位の記録（record_unit）・共通設計
# 文書の記録（record_common）の両方がこの1つの関数で同じ検査を受ける。
# read-run.shへstart-run.shが必ず書く「実行の識別子」を渡し、戻り値その
# ものはexecution_id_of()が改めて読む（本関数はrun.jsonの実在・可読性・
# キーの実在・値の形の判定にだけ使う）。かつては共通設計文書の記録だけが
# 専用のcommon_run_dir_readable()（同じ検査だが単位側には呼ばれていな
# かった）を持ち、単位の記録は「テスト設計書の出力」キーの読み取り可否
# しか確かめていなかったため、「実行の識別子」キーが無いrun.jsonでも
# 単位の記録だけは記録を書けてしまう非対称があった
# （2026-09-07反証対応・第4版・所見1）。
#
# run.jsonがファイルとして実在してもOSの権限で読めないとき、read-run.sh
# の`jq -e . "$run_json"`はファイルを開けずJSONの形式不正と区別が付かず
# 「run-形式」を返してしまう。read-run.shを呼ぶ前に読み取り権限そのもの
# を確かめ、権限が無ければ「run-不可読」として区別する（read-run.sh
# 自身は変えない。ファイルが実在しない場合はこの判定を素通りし、従来
# どおりread-run.shの「run-不在」に委ねる。2026-09-07反証対応・第5版・
# 所見2）。実行フォルダ自体に実行権限が無く中に入れないときは、
# run.jsonが実在していても`[ -e ]`がOS側で偽を返し上記の判定を素通り
# してしまい、read-run.shが見つからず誤って「run-不在」になる。実行
# フォルダの実在（`[ -d ]`）と実行権限（`[ -x ]`）を先に確かめ、実在
# するが入れないときも「run-不可読」とする（フォルダ自体が実在しない
# ときはこの判定も素通りする。2026-09-07反証対応・第6版・所見2）。
#
# 「実行の識別子」キーが実在しても、値がnull・空文字列・数値等であれば、
# 記録の`判定した実行`欄に`"null"`／`""`／`"123"`のような値がそのまま
# 書かれてしまう（execution_id_of()はキーの値をそのまま使うだけで、値の
# 形は問わない設計のため）。read-run.shはキーの実在しか確かめないため、
# read-run.shを変えずに本関数側で`jq -e`により値が空でない文字列である
# ことを確かめ、満たさなければ「識別子-不正」として判定不能にする
# （2026-09-07反証対応・第5版・所見1）。半角・全角の空白だけの文字列は
# `type == "string" and length > 0`だけでは「空でない文字列」として
# 通ってしまうため、空白を取り除いたうえで長さを確かめる
# （2026-09-07反証対応・第6版・所見1）。ゼロ幅空白U+200B・BOM U+FEFF
# のような不可視文字は`\s`にも全角空白にも一致せず、取り除いた後も
# 「空でない文字列」として通ってしまうため、list-units-of.shの
# is_blank_str()と同じ文字集合（jqの`\s`・全角空白・ゼロ幅空白・BOM）
# まで広げる（2026-09-07反証対応・第7版・所見1）。
run_dir_readable_or_reason() {
  local run_dir="$1" run_json="${run_dir%/}/run.json" rc err_file reason
  if [ ! -f "$READ_RUN_SH" ]; then
    echo "共有部品-不在"
    return 2
  fi
  if [ -d "$run_dir" ] && [ ! -x "$run_dir" ]; then
    echo "run-不可読"
    return 2
  fi
  if [ -e "$run_json" ] && [ ! -r "$run_json" ]; then
    echo "run-不可読"
    return 2
  fi
  err_file="$(mktemp "${TMPDIR:-/tmp}/run-dir-readable.XXXXXX")" || {
    echo "一時領域-不可"
    return 2
  }
  # 関数内のtrap ... RETURNは呼び出し元が持つRETURN trapを上書きしうる
  # 潜在欠陥のため使わない。成功・失敗いずれの経路でも読み取り直後に
  # rm -fで後始末する（2026-09-07反証対応・第4版・所見2）。
  bash "$READ_RUN_SH" "$run_dir" "実行の識別子" > /dev/null 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    reason="$(sed -n 's/^\[FAIL\] \([^:]*\):.*/\1/p' "$err_file" | head -1)"
    rm -f "$err_file"
    echo "${reason:-理由不明}"
    return 2
  fi
  rm -f "$err_file"
  if ! jq -e '.["実行の識別子"] | type == "string" and (gsub("[\\s　​﻿]"; "") | length > 0)' "$run_json" > /dev/null 2>&1; then
    echo "識別子-不正"
    return 2
  fi
  return 0
}

# 単位のフォルダ名をlist-units-of.shの5列目から得る。一覧が無い、または
# 該当する識別子の行が無ければ、unit-dir-name.shへ識別子を渡した値へ
# fallbackする（一覧不在時の現行維持）。
unit_folder_name() {
  local design_root="$1" kind="$2" unit="$3" folder=""
  if [ -f "$LIST_UNITS_OF_SH" ]; then
    folder="$(bash "$LIST_UNITS_OF_SH" "$design_root" "$kind" 2>/dev/null \
      | awk -F'\t' -v id="$unit" '$1==id{print $5; exit}')"
  fi
  if [ -z "$folder" ]; then
    folder="$(bash "$UNIT_DIR_NAME_SH" "$unit")"
  fi
  printf '%s' "$folder"
}

usage_error() {
  echo "使い方: record-acceptance.sh <対象> --run <実行フォルダ> --kind <種別> --unit <識別子> --verdict <合格|不合格> --viewpoints \"<観点=合|否|要確認;...>\" --judged \"<文書名>=<sha256>;...\" [--reason \"...\"] [--design-root <設計書のルート>] [--no-units-status]" >&2
  echo "        record-acceptance.sh <対象> --run <実行フォルダ> --common <文書名> --verdict <合格|不合格> --viewpoints \"...\" --judged \"<文書名>=<sha256>\" [--reason \"...\"] [--design-root <設計書のルート>]" >&2
  echo "        record-acceptance.sh --self-test" >&2
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

doc_sha_json() {
  local path="$1" name="$2" sha=""
  if [ -f "$path" ]; then
    sha="$(shasum -a 256 "$path" | awk '{print $1}')"
  fi
  jq -n --arg n "$name" --arg s "$sha" '{($n): $s}'
}


# 観点の値が 合・否・要確認 のいずれかであることを確かめる。$1: viewpoints。
# 値が空・`=`が無い項目・3値以外の値はすべて同じ扱いで拒否する（流れの設計
# 「完了判定の状態」の「観点の値は 合・否・要確認 の3つ」）。キーが空文字列
# の項目（例: "=合"）も拒む（読む側のcheck-acceptance-record.shが空のキー
# を観点の値-不正として拒むのと対にする。改善指示書対応）。
check_viewpoint_values_valid() {
  local viewpoints="$1"
  [ -n "$viewpoints" ] || return 0
  local old_ifs="$IFS" k v item
  IFS=';'
  local arr=($viewpoints)
  IFS="$old_ifs"
  for item in "${arr[@]}"; do
    [ -n "$item" ] || continue
    case "$item" in
      *=*)
        k="${item%%=*}"
        v="${item#*=}"
        ;;
      *)
        k="$item"
        v=""
        ;;
    esac
    if [ -z "$k" ]; then
      echo "[FAIL] 観点-キー空: 値=${v}" >&2
      return 1
    fi
    if ! is_valid_viewpoint_value "$v"; then
      echo "[FAIL] 観点-値不正: ${k}=${v}" >&2
      return 1
    fi
  done
  return 0
}

# 判定（--verdict）と観点（--viewpoints）の整合を確かめる。$1: verdict
# $2: viewpoints。否が1つでもあるのに合格、否が無く要確認と合だけなのに
# 不合格は、record-acceptance.shが観点との整合を検査して確定する
# （設計判断: 流れの設計「完了判定の状態」の「誰が決めるか」を参照）。
check_verdict_viewpoint_consistency() {
  local verdict="$1" viewpoints="$2"
  local has_no=1
  case "$viewpoints" in
    *=否*) has_no=0 ;;
  esac
  if [ "$has_no" -eq 0 ] && [ "$verdict" = "合格" ]; then
    return 1
  fi
  if [ "$has_no" -eq 1 ] && [ "$verdict" = "不合格" ]; then
    return 2
  fi
  return 0
}

# 判定した時点の同一性の値（judged_json）と、記録を書く時点の現在値
# （docs_json）を突き合わせる。docs_jsonの各文書名について一致しなければ
# 標準エラーへ差分を出し、1件でも食い違えば1を返す（第1回改善指示書1-23）。
check_judged_match() {
  local judged_json="$1" docs_json="$2"
  local name cur judged_val mismatch=0
  for name in $(printf '%s' "$docs_json" | jq -r 'keys[]'); do
    cur="$(printf '%s' "$docs_json" | jq -r --arg n "$name" '.[$n]')"
    judged_val="$(printf '%s' "$judged_json" | jq -r --arg n "$name" '.[$n] // "__不在__"')"
    if [ "$judged_val" = "__不在__" ] || [ "$judged_val" != "$cur" ]; then
      echo "[FAIL] 同一性-判定後変更: ${name} が判定した後に変わっています" >&2
      mismatch=1
    fi
  done
  return "$mismatch"
}


parse_kv_pairs_json() {
  local vp="$1"
  [ -n "$vp" ] || { echo '{}'; return 0; }
  local old_ifs="$IFS" k v entries=""
  IFS=';'
  local arr=($vp)
  IFS="$old_ifs"
  local item
  for item in "${arr[@]}"; do
    [ -n "$item" ] || continue
    k="${item%%=*}"
    v="${item#*=}"
    entries="${entries}$(jq -n --arg k "$k" --arg v "$v" '{($k): $v}')
"
  done
  printf '%s' "$entries" | jq -s 'add // {}'
}

# 呼び出し元（record_unit・record_common）は本関数を呼ぶ前に必ず
# run_dir_readable_or_reason()で「実行の識別子」キーの実在を確かめている
# ため、本関数はその値をそのまま使う。キーが無いときにフォルダ名
# （basename）へ黙って落ちる既定は廃止した。落ちた先が実行フォルダの
# 取り違えや壊れたrun.jsonであっても判定不能にならず記録が書けてしまう
# ため（2026-09-07反証対応・第4版・所見1）。
execution_id_of() {
  local run_dir="$1"
  jq -r '.["実行の識別子"]' "${run_dir%/}/run.json" 2>/dev/null
}

record_unit() {
  local target="$1" run_dir="$2" kind="$3" unit="$4" verdict="$5" viewpoints="$6" reason="$7" design_root="$8" judged_json="$9" no_status="${10:-0}"
  local folder
  folder="$(species_folder "$kind")"
  if [ -z "$folder" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    return 2
  fi
  if [ ! -f "$UNIT_DIR_NAME_SH" ]; then
    echo "[FAIL] 共有部品-不在: unit-dir-name.sh がありません" >&2
    return 2
  fi
  if [ ! -f "$DESIGN_DOC_NAME_SH" ]; then
    echo "[FAIL] 共有部品-不在: design-doc-name.sh がありません" >&2
    return 2
  fi

  local dirname unit_path docs_json basic_name test_name tests_output tests_output_rc
  dirname="$(unit_folder_name "$design_root" "$kind" "$unit")"
  unit_path="${design_root}/docs/design/${folder}/${dirname}"

  basic_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" basic 2>/dev/null)"
  test_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" test 2>/dev/null)"
  if [ -z "$basic_name" ] || [ -z "$test_name" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    return 2
  fi

  # 実行フォルダはrun.jsonの実在・可読性・「実行の識別子」キーの実在を
  # 単位・共通の両方で同じ検査（run_dir_readable_or_reason）で確かめる。
  # 読めなければ判定不能で記録を作らない（2026-09-07反証対応・第4版・所見1）。
  local run_reason run_rc
  run_reason="$(run_dir_readable_or_reason "$run_dir")"
  run_rc=$?
  if [ "$run_rc" -ne 0 ]; then
    echo "[FAIL] 設定-判定不能: 実行フォルダを確認できません（${run_dir%/}/run.json、理由: ${run_reason:-理由不明}）" >&2
    return 2
  fi

  # 記録の「文書」は基本設計書を常に含み、単体テスト設計書は「テスト設計書
  # の出力」が「出力する」のときだけ含める（第1回改善指示書1-31）。設定が
  # 読めない・値が不正なときは判定不能で記録を作らない（2026-09-07反証対応）。
  tests_output="$(tests_output_setting_of "$run_dir")"
  tests_output_rc=$?
  if [ "$tests_output_rc" -ne 0 ]; then
    echo "[FAIL] 設定-判定不能: テスト設計書の出力の設定を読めません（${run_dir%/}/run.json、理由: ${tests_output:-不明}）" >&2
    return 2
  fi
  if [ "$tests_output" = "出力する" ]; then
    docs_json="$(printf '%s\n%s\n' \
      "$(doc_sha_json "${unit_path}/${basic_name}" "$basic_name")" \
      "$(doc_sha_json "${unit_path}/${test_name}" "$test_name")" \
      | jq -s 'add')"
  else
    docs_json="$(doc_sha_json "${unit_path}/${basic_name}" "$basic_name")"
  fi

  if ! check_judged_match "$judged_json" "$docs_json"; then
    return 1
  fi

  local commit vp_json exec_id out_dir out_file
  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_kv_pairs_json "$viewpoints")"
  exec_id="$(execution_id_of "$run_dir")"
  out_dir="${design_root}/ai-work/records/basic-design-acceptance"
  mkdir -p "$out_dir" 2>/dev/null
  out_file="${out_dir}/${kind}-${dirname}.json"

  jq -n --arg kind "$kind" --arg id "$unit" --argjson docs "$docs_json" \
    --arg commit "$commit" --arg verdict "$verdict" --argjson vp "$vp_json" \
    --arg reason "$reason" --arg exec "$exec_id" \
    '{"種別":$kind,"識別子":$id,"文書":$docs,"コミット":$commit,"判定":$verdict,"観点":$vp,"理由":$reason,"判定した実行":$exec}' \
    > "$out_file"

  if [ "$no_status" != "1" ] && [ -f "$UNITS_STATUS_SH" ]; then
    bash "$UNITS_STATUS_SH" "$run_dir" set "$kind" "$unit" 完了判定 "$verdict" > /dev/null 2>&1
  fi

  echo "記録: ${out_file}"
  return 0
}

record_common() {
  local target="$1" run_dir="$2" doc_name="$3" verdict="$4" viewpoints="$5" reason="$6" design_root="$7" judged_json="$8"
  local doc_path="${design_root}/docs/design/common/${doc_name}.md"
  local docs_json commit vp_json exec_id out_dir out_file
  local run_reason run_rc
  run_reason="$(run_dir_readable_or_reason "$run_dir")"
  run_rc=$?
  if [ "$run_rc" -ne 0 ]; then
    echo "[FAIL] 設定-判定不能: 実行フォルダを確認できません（${run_dir%/}/run.json、理由: ${run_reason:-理由不明}）" >&2
    return 2
  fi

  docs_json="$(doc_sha_json "$doc_path" "${doc_name}.md")"

  if ! check_judged_match "$judged_json" "$docs_json"; then
    return 1
  fi

  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_kv_pairs_json "$viewpoints")"
  exec_id="$(execution_id_of "$run_dir")"
  out_dir="${design_root}/ai-work/records/basic-design-acceptance"
  mkdir -p "$out_dir" 2>/dev/null
  out_file="${out_dir}/common-${doc_name}.json"

  jq -n --argjson docs "$docs_json" --arg commit "$commit" --arg verdict "$verdict" \
    --argjson vp "$vp_json" --arg reason "$reason" --arg exec "$exec_id" \
    '{"種別":null,"識別子":null,"文書":$docs,"コミット":$commit,"判定":$verdict,"観点":$vp,"理由":$reason,"判定した実行":$exec}' \
    > "$out_file"

  echo "記録: ${out_file}"
  return 0
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" kind="" unit="" common="" verdict="" viewpoints="" reason="" design_root="$target" judged="" no_status=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --common) common="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --viewpoints) viewpoints="$2"; shift 2 ;;
      --judged) judged="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      --no-units-status) no_status=1; shift ;;
      *) usage_error ;;
    esac
  done

  [ -n "$run_dir" ] || usage_error
  [ -n "$judged" ] || usage_error

  case "$verdict" in
    合格|不合格) ;;
    *)
      echo "[FAIL] 使い方-判定: ${verdict:-（空）} は 合格・不合格 のいずれでもありません" >&2
      exit 2
      ;;
  esac

  if ! check_viewpoint_values_valid "$viewpoints"; then
    exit 2
  fi

  check_verdict_viewpoint_consistency "$verdict" "$viewpoints"
  case "$?" in
    1)
      echo "[FAIL] 判定-観点不整合: 否があるため合格にできません" >&2
      exit 2
      ;;
    2)
      echo "[FAIL] 判定-観点不整合: 否が無いため不合格にできません" >&2
      exit 2
      ;;
  esac

  local yk_rc
  check_yakukakunin_key "$viewpoints" "$reason" "$run_dir"
  yk_rc=$?
  case "$yk_rc" in
    0) ;;
    2)
      echo "[FAIL] 要確認-判定不能: 確認事項の記録を参照できません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
      exit 2
      ;;
    *)
      echo "[FAIL] 要確認-キー不在: 理由に確認事項一覧のキーがありません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
      exit 2
      ;;
  esac

  local judged_json
  judged_json="$(parse_kv_pairs_json "$judged")"

  local rc
  if [ -n "$common" ]; then
    record_common "$target" "$run_dir" "$common" "$verdict" "$viewpoints" "$reason" "$design_root" "$judged_json"
    rc=$?
  elif [ -n "$kind" ] && [ -n "$unit" ]; then
    record_unit "$target" "$run_dir" "$kind" "$unit" "$verdict" "$viewpoints" "$reason" "$design_root" "$judged_json" "$no_status"
    rc=$?
  else
    usage_error
  fi
  exit "$rc"
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/record-acceptance-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

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

  sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

  # --- 使い方エラー系 ---
  bash "$SCRIPT_DIR/record-acceptance.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d="$base/target" run="$base/run"
  mkdir -p "$d" "$run"
  # gitのコミットは不要。対象のコミットが空でも記録は書ける（コミット=空文字）ことを確かめる
  # run.jsonは統括の実行の開始スクリプトが必ず作るため、テスト用の実行フォルダにも
  # 既定値（出力しない）を持たせる（2026-09-07反証対応。run.json不在は判定不能に
  # なるため、run.json不在そのものを検証する後続のケースとは分ける）。
  cat > "$run/run.json" <<'RUNBASEJSON'
{
  "実行の識別子": "2026-09-03-abc1234",
  "テスト設計書の出力": "出力しない"
}
RUNBASEJSON

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 不明 --viewpoints "" --judged "x=y" > "$base/u2.out" 2>"$base/u2.err"
  check "使い方-判定不正は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 保留 --viewpoints "" --judged "x=y" > "$base/u2b.out" 2>"$base/u2b.err"
  check "使い方-判定「保留」は廃止のため終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local yk_bad_record="$d/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  rm -f "$yk_bad_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 合格 --viewpoints "外部仕様の確定=不明" --judged "x=y" > "$base/u2c.out" 2>"$base/u2c.err"
  local rc2c=$?
  check "観点の値が不明なら終了コード2" "$([ "$rc2c" -eq 2 ] && echo 0 || echo 1)"
  check "観点の値が不明なら理由に観点-値不正" "$(grep -qF '観点-値不正' "$base/u2c.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$yk_bad_record" ]; then
    echo "PASS: 観点の値が不明なら記録を作らない"
  else
    echo "FAIL: 観点の値が不明なら記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 合格 --viewpoints "" > "$base/u3.out" 2>"$base/u3.err"
  check "使い方-judged無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  # --- 単位の記録 ---
  mkdir -p "$d/docs/design/screens/src_pages_OrderList.tsx"
  echo "# 画面基本設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  local judged1
  judged1="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合;単体テスト設計書の実在=合" --judged "$judged1" --reason "" \
    > "$base/r1.out" 2>"$base/r1.err"
  check "単位の記録: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  local record_file="$d/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  check "単位の記録: ファイルが実在" "$([ -f "$record_file" ] && echo 0 || echo 1)"

  local verdict1 sha1 sha_expected1
  verdict1="$(jq -r '.["判定"]' "$record_file" 2>/dev/null)"
  check "単位の記録: 判定が合格" "$([ "$verdict1" = "合格" ] && echo 0 || echo 1)"
  sha1="$(jq -r '.["文書"]["画面基本設計書.md"]' "$record_file" 2>/dev/null)"
  sha_expected1="$(shasum -a 256 "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md" | awk '{print $1}')"
  check "単位の記録: 画面基本設計書の文書名でsha256が一致" "$([ "$sha1" = "$sha_expected1" ] && echo 0 || echo 1)"
  check "単位の記録: 画面基本設計書のsha256が空でない" "$([ -n "$sha1" ] && echo 0 || echo 1)"

  local vp1
  vp1="$(jq -r '.["観点"]["外部仕様の確定"]' "$record_file" 2>/dev/null)"
  check "単位の記録: 観点が反映される" "$([ "$vp1" = "合" ] && echo 0 || echo 1)"

  local status1
  status1="$(bash "${SCRIPT_DIR}/units-status.sh" "$run" get screen "src/pages/OrderList.tsx" 完了判定 2>/dev/null)"
  check "単位の記録: units-status.shの完了判定が更新される" "$([ "$status1" = "合格" ] && echo 0 || echo 1)"

  # --- 更新時刻の取得が系によらない（第1回改善指示書1-39） ---
  # 数字を返すだけでなく、更新時刻の変化を実際に追うことを確かめる。
  # 値を固定で返す実装や空を返す実装は、後段の2つの判定で落ちる。
  local mt_probe="$base/mtime-probe.txt"
  : > "$mt_probe"
  touch -t 202001010000 "$mt_probe"
  local mt_old
  mt_old="$(mtime_of "$mt_probe")"
  touch "$mt_probe"
  local mt_new
  mt_new="$(mtime_of "$mt_probe")"
  check "更新時刻: mtime_of が数字だけの値を返す" "$(printf '%s' "$mt_old" | grep -qE '^[0-9]+$' && echo 0 || echo 1)"
  check "更新時刻: mtime_of が更新の前後で違う値を返す" "$([ -n "$mt_old" ] && [ -n "$mt_new" ] && [ "$mt_old" != "$mt_new" ] && echo 0 || echo 1)"
  check "更新時刻: mtime_of が新しいほど大きい値を返す" "$([ -n "$mt_old" ] && [ -n "$mt_new" ] && [ "$mt_new" -gt "$mt_old" ] && echo 0 || echo 1)"

  # GNU を模した系でも同じ値を返す（第1回改善指示書1-39）。
  # 偽の stat を PATH の先頭へ置く。書式指定のオプションだけが成功し、
  # ファイルシステム側のオプションは数値でない文字列を返す系を作る。
  # 書式指定の分岐を消した実装は、この系で数値を得られず落ちる。
  local gnu_bin="$base/gnu-stat-sim/bin"
  mkdir -p "$gnu_bin"
  cat > "$gnu_bin/stat" <<'GNUSTATSIM'
#!/bin/bash
case "$1" in
  -c) [ "$2" = "%Y" ] && { /usr/bin/stat -f %m "$3"; exit 0; }; exit 1 ;;  # stat-sim-fixture: 偽stat内の実体呼び出し（本検査の対象外）
  -f) echo "filesystem-info"; exit 0 ;;
  *) exec /usr/bin/stat "$@" ;;
esac
GNUSTATSIM
  chmod +x "$gnu_bin/stat"
  local mt_gnu
  mt_gnu="$(PATH="$gnu_bin:$PATH" mtime_of "$mt_probe")"
  check "更新時刻: GNU を模した系でも同じ値を返す" "$([ -n "$mt_gnu" ] && [ "$mt_gnu" = "$mt_new" ] && echo 0 || echo 1)"

  # --- --no-units-status: 既存の状態のファイルは中身も更新時刻も変わらない
  #     （第1回改善指示書1-38）。更新時刻を大きく過去へ戻してから実行し、
  #     書き込みが起きれば時刻が今に変わることで検知する。 ---
  local status_file_run="$run/logs/units-status.json"
  local status_before_flag
  status_before_flag="$(cat "$status_file_run" 2>/dev/null)"
  touch -t 202001010000 "$status_file_run"
  local status_mtime_before_flag
  status_mtime_before_flag="$(mtime_of "$status_file_run")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 不合格 --viewpoints "外部仕様の確定=否;単体テスト設計書の実在=合" --judged "$judged1" --reason "確認のため" \
    --no-units-status > "$base/nostatus1.out" 2>"$base/nostatus1.err"
  local rc_nostatus1=$?
  local status_after_flag status_mtime_after_flag
  status_after_flag="$(cat "$status_file_run" 2>/dev/null)"
  status_mtime_after_flag="$(mtime_of "$status_file_run")"
  check "no-units-status-既存有り: 終了コード0" "$([ "$rc_nostatus1" -eq 0 ] && echo 0 || echo 1)"
  check "no-units-status-既存有り: 状態のファイルの中身が変わらない" "$([ "$status_before_flag" = "$status_after_flag" ] && echo 0 || echo 1)"
  check "no-units-status-既存有り: 状態のファイルの更新時刻が変わらない" "$([ "$status_mtime_before_flag" = "$status_mtime_after_flag" ] && echo 0 || echo 1)"

  # --- --no-units-status: 状態のファイルが無い状態では作られない・終了コード0 ---
  local d9="$base/target9" run9="$base/run9"
  mkdir -p "$d9/docs/design/screens/src_pages_OrderList.tsx" "$run9"
  cat > "$run9/run.json" <<'RUN9JSON'
{
  "実行の識別子": "2026-09-03-abc1234",
  "テスト設計書の出力": "出力しない"
}
RUN9JSON
  echo "# 画面基本設計書" > "$d9/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  local judged9
  judged9="画面基本設計書.md=$(sha_of "$d9/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d9" --run "$run9" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged9" --reason "" \
    --no-units-status > "$base/nostatus2.out" 2>"$base/nostatus2.err"
  local rc_nostatus2=$?
  check "no-units-status-無い状態: 終了コード0" "$([ "$rc_nostatus2" -eq 0 ] && echo 0 || echo 1)"
  check "no-units-status-無い状態: 状態のファイルが作られない" "$([ ! -f "$run9/logs/units-status.json" ] && echo 0 || echo 1)"

  # --- 指定なしはこれまでどおり状態のファイルへ書き込む（単位の記録:
  #     units-status.shの完了判定が更新されるで既に確認済みだが、無い状態
  #     からの新規作成も併せて確かめる） ---
  check "指定なし: 状態のファイルへ書き込む（これまでどおり）" "$([ -f "$run/logs/units-status.json" ] && echo 0 || echo 1)"

  # --- 共通設計文書の記録 ---
  mkdir -p "$d/docs/design/common"
  echo "# 基盤設計書" > "$d/docs/design/common/基盤設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --common 基盤設計書 \
    --verdict 不合格 --viewpoints "非機能の方式の確定=否" --judged "基盤設計書.md=$(sha_of "$d/docs/design/common/基盤設計書.md")" --reason "性能方式が未確定" \
    > "$base/r2.out" 2>"$base/r2.err"
  check "共通設計文書の記録: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  local common_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書.json"
  local verdict2 reason2
  verdict2="$(jq -r '.["判定"]' "$common_record" 2>/dev/null)"
  reason2="$(jq -r '.["理由"]' "$common_record" 2>/dev/null)"
  check "共通設計文書の記録: 判定が不合格" "$([ "$verdict2" = "不合格" ] && echo 0 || echo 1)"
  check "共通設計文書の記録: 理由が反映される" "$([ "$reason2" = "性能方式が未確定" ] && echo 0 || echo 1)"

  # --- 共通設計文書の記録も--runの実行フォルダの実在を確かめる（第3版・所見1） ---
  local run_missing="$base/run-does-not-exist"
  local common_missing_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書2.json"
  echo "# 基盤設計書2" > "$d/docs/design/common/基盤設計書2.md"
  rm -f "$common_missing_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run_missing" --common 基盤設計書2 \
    --verdict 合格 --viewpoints "非機能の方式の確定=合" --judged "基盤設計書2.md=$(sha_of "$d/docs/design/common/基盤設計書2.md")" --reason "" \
    > "$base/r2b.out" 2>"$base/r2b.err"
  local rc2b=$?
  check "共通設計文書の記録: run.json不在は終了コード2" "$([ "$rc2b" -eq 2 ] && echo 0 || echo 1)"
  check "共通設計文書の記録: run.json不在の理由に設定-判定不能とrun-不在" "$(grep -qF '設定-判定不能' "$base/r2b.err" && grep -qF 'run-不在' "$base/r2b.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$common_missing_record" ]; then
    echo "PASS: 共通設計文書の記録: run.json不在は記録を作らない"
  else
    echo "FAIL: 共通設計文書の記録: run.json不在は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 共通設計文書の記録もrun.jsonがJSONとして読めない・「実行の識別子」
  # キーが無いときは単位の記録と同じ検査（run_dir_readable_or_reason）で
  # 判定不能になる（2026-09-07反証対応・第4版） ---
  local run_common_json_invalid="$base/run-common-json-invalid"
  local common_json_invalid_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書3.json"
  mkdir -p "$run_common_json_invalid"
  echo "# 基盤設計書3" > "$d/docs/design/common/基盤設計書3.md"
  printf '{ invalid json' > "$run_common_json_invalid/run.json"
  rm -f "$common_json_invalid_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run_common_json_invalid" --common 基盤設計書3 \
    --verdict 合格 --viewpoints "非機能の方式の確定=合" --judged "基盤設計書3.md=$(sha_of "$d/docs/design/common/基盤設計書3.md")" --reason "" \
    > "$base/r2c.out" 2>"$base/r2c.err"
  local rc2c=$?
  check "共通設計文書の記録: run.json形式不正-判定不能で記録を作らない" "$([ "$rc2c" -eq 2 ] && grep -qF '設定-判定不能' "$base/r2c.err" && grep -qF 'run-形式' "$base/r2c.err" && [ ! -f "$common_json_invalid_record" ] && echo 0 || echo 1)"

  local run_common_id_missing="$base/run-common-id-missing"
  local common_id_missing_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書4.json"
  mkdir -p "$run_common_id_missing"
  echo "# 基盤設計書4" > "$d/docs/design/common/基盤設計書4.md"
  cat > "$run_common_id_missing/run.json" <<'RUNCOMMONIDJSON'
{
  "対象リポジトリ": "/path/to/target"
}
RUNCOMMONIDJSON
  rm -f "$common_id_missing_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run_common_id_missing" --common 基盤設計書4 \
    --verdict 合格 --viewpoints "非機能の方式の確定=合" --judged "基盤設計書4.md=$(sha_of "$d/docs/design/common/基盤設計書4.md")" --reason "" \
    > "$base/r2d.out" 2>"$base/r2d.err"
  local rc2d=$?
  check "共通設計文書の記録: 実行の識別子キー不在-判定不能で記録を作らない" "$([ "$rc2d" -eq 2 ] && grep -qF '設定-判定不能' "$base/r2d.err" && grep -qF 'キー-不在' "$base/r2d.err" && [ ! -f "$common_id_missing_record" ] && echo 0 || echo 1)"

  # --- 設計書ルート分離-対象に書かない ---
  local dc="$base/target-code-only" design2="$base/design2"
  mkdir -p "$dc" "$design2/docs/design/screens/src_pages_OrderList.tsx"
  echo "# 画面基本設計書" > "$design2/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$design2/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  local judged3
  judged3="画面基本設計書.md=$(sha_of "$design2/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$design2/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$dc" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged3" --reason "" --design-root "$design2" \
    > "$base/r3.out" 2>"$base/r3.err"
  check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -e "$dc/ai-work" ] && [ ! -e "$dc/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側に書かれています）"
    fail=$((fail + 1))
  fi
  local record_file2="$design2/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  check "設計書ルート分離-記録が設計書のルートにある" "$([ -f "$record_file2" ] && echo 0 || echo 1)"

  # --- 種別ごとの文書名が実名と一致（api・table・feature） ---
  local d2="$base/target2" run2="$base/run2"
  mkdir -p "$d2" "$run2"
  # 以降のjudgedはすべて基本設計書・単体テスト設計書の2件を渡すため、
  # このrun2は「テスト設計書の出力」を「出力する」にしておく
  # （第1回改善指示書1-31。既定「出力しない」だと単体テスト設計書の
  # sha256が記録の文書へ含まれず、以下のケースが揃わなくなる）。
  cat > "$run2/run.json" <<'RUN2JSON'
{
  "実行の識別子": "2026-09-07-run2",
  "テスト設計書の出力": "出力する"
}
RUN2JSON

  mkdir -p "$d2/docs/design/apis/api_get_orders"
  echo "# API基本設計書" > "$d2/docs/design/apis/api_get_orders/API基本設計書.md"
  echo "# API単体テスト設計書" > "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md"
  local judged4
  judged4="API基本設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API基本設計書.md");API単体テスト設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged4" --reason "" > "$base/r4.out" 2>"$base/r4.err"
  check "api種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local api_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  local api_basic api_test
  api_basic="$(jq -r '.["文書"]["API基本設計書.md"] // empty' "$api_record" 2>/dev/null)"
  api_test="$(jq -r '.["文書"]["API単体テスト設計書.md"] // empty' "$api_record" 2>/dev/null)"
  check "api種別: 文書名がAPI基本設計書.mdでsha256が空でない" "$([ -n "$api_basic" ] && echo 0 || echo 1)"
  check "api種別: 文書名がAPI単体テスト設計書.mdでsha256が空でない" "$([ -n "$api_test" ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/tables/orders"
  echo "# 論理データモデル" > "$d2/docs/design/tables/orders/論理データモデル.md"
  echo "# テーブル単体テスト設計書" > "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md"
  local judged5
  judged5="論理データモデル.md=$(sha_of "$d2/docs/design/tables/orders/論理データモデル.md");テーブル単体テスト設計書.md=$(sha_of "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind table --unit "orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged5" --reason "" > "$base/r5.out" 2>"$base/r5.err"
  check "table種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local table_record="$d2/ai-work/records/basic-design-acceptance/table-orders.json"
  local table_basic table_test
  table_basic="$(jq -r '.["文書"]["論理データモデル.md"] // empty' "$table_record" 2>/dev/null)"
  table_test="$(jq -r '.["文書"]["テーブル単体テスト設計書.md"] // empty' "$table_record" 2>/dev/null)"
  check "table種別: 文書名が論理データモデル.mdでsha256が空でない" "$([ -n "$table_basic" ] && echo 0 || echo 1)"
  check "table種別: 文書名がテーブル単体テスト設計書.mdでsha256が空でない" "$([ -n "$table_test" ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/features/注文機能"
  echo "# 機能設計書" > "$d2/docs/design/features/注文機能/機能設計書.md"
  echo "# 機能単体テスト設計書" > "$d2/docs/design/features/注文機能/機能単体テスト設計書.md"
  local judged6
  judged6="機能設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能設計書.md");機能単体テスト設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind feature --unit "注文機能" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged6" --reason "" > "$base/r6.out" 2>"$base/r6.err"
  check "feature種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local feature_record="$d2/ai-work/records/basic-design-acceptance/feature-注文機能.json"
  local feature_basic feature_test
  feature_basic="$(jq -r '.["文書"]["機能設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  feature_test="$(jq -r '.["文書"]["機能単体テスト設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  check "feature種別: 文書名が機能設計書.mdでsha256が空でない" "$([ -n "$feature_basic" ] && echo 0 || echo 1)"
  check "feature種別: 文書名が機能単体テスト設計書.mdでsha256が空でない" "$([ -n "$feature_test" ] && echo 0 || echo 1)"

  # --- 解釈できない種別は記録を作らず終了コード2 ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind 不正種別 --unit "何か" \
    --verdict 合格 --viewpoints "" --judged "x=y" --reason "" > "$base/r7.out" 2>"$base/r7.err"
  local rc7=$?
  check "解釈できない種別は終了コード2" "$([ "$rc7" -eq 2 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$d2/ai-work/records/basic-design-acceptance/不正種別-何か.json" ]; then
    echo "PASS: 解釈できない種別は記録を作らない"
  else
    echo "FAIL: 解釈できない種別は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 要確認を含む合格の記録（確認事項一覧にキーが実在） ---
  mkdir -p "${run2}/confirmations"
  cat > "${run2}/confirmations/確認事項の記録.md" <<'CONFEOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 性能-数値目標 | api/get_orders | 確認事項 | 性能の数値目標が無い | 既定なし | 方式設計書 | 未回答 | 未回答 |
CONFEOF
  local yk_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r8.out" 2>"$base/r8.err"
  check "要確認を含む合格の記録は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local yk_vp
  yk_vp="$(jq -r '.["観点"]["非機能の方式の確定"]' "$yk_record" 2>/dev/null)"
  check "要確認を含む合格の記録: 観点の値が要確認" "$([ "$yk_vp" = "要確認" ] && echo 0 || echo 1)"

  # --- 要確認でキー不在なら終了コード2で記録を作らない ---
  rm -f "$yk_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "根拠のないキー" \
    > "$base/r9.out" 2>"$base/r9.err"
  local rc9=$?
  check "要確認でキー不在は終了コード2" "$([ "$rc9" -eq 2 ] && echo 0 || echo 1)"
  check "要確認でキー不在の理由に要確認-キー不在" "$(grep -qF '要確認-キー不在' "$base/r9.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$yk_record" ]; then
    echo "PASS: 要確認でキー不在は記録を作らない"
  else
    echo "FAIL: 要確認でキー不在は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 方式設計書の7節が要求水準を持たない状態で要確認の単位の判定が定まり照合が0を返す ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 \
    --viewpoints "外部仕様の確定=合;業務ルールと例外系の確定=合;非機能の方式の確定=要確認;データの整合性・トランザクション境界・排他の確定=合;不明点の不在=合;単体テスト設計書の実在=合" \
    --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r10.out" 2>"$base/r10.err"
  local rc10r=$?
  local rc10c=1
  if [ "$rc10r" -eq 0 ]; then
    bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
      > "$base/r10chk.out" 2>"$base/r10chk.err"
    rc10c=$?
  fi
  check "方式設計書の7節が要求水準を持たない状態で要確認の単位の判定が定まり照合が0を返す" "$([ "$rc10r" -eq 0 ] && [ "$rc10c" -eq 0 ] && echo 0 || echo 1)"

  # --- 外部仕様の確定が要確認でも判定が定まり照合が0を返す（第1回改善指示書1-22・再検証） ---
  local ext_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 \
    --viewpoints "外部仕様の確定=要確認;業務ルールと例外系の確定=合;非機能の方式の確定=合;データの整合性・トランザクション境界・排他の確定=合;不明点の不在=合;単体テスト設計書の実在=合" \
    --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r10x.out" 2>"$base/r10x.err"
  local rc10xr=$?
  local rc10xc1=1
  local vp_ext1=""
  if [ "$rc10xr" -eq 0 ]; then
    bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
      > "$base/r10xchk1.out" 2>"$base/r10xchk1.err"
    rc10xc1=$?
    vp_ext1="$(jq -r '.["観点"]["外部仕様の確定"]' "$ext_record" 2>/dev/null)"
  fi
  check "外部仕様の確定が要確認でも判定が定まり照合が0を返す" "$([ "$rc10xr" -eq 0 ] && [ "$rc10xc1" -eq 0 ] && [ "$vp_ext1" = "要確認" ] && echo 0 || echo 1)"

  # --- 同じ記録を2回照合しても外部仕様の確定の値が変わらない（第1回改善指示書1-22・再検証） ---
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
    > "$base/r10xchk2.out" 2>"$base/r10xchk2.err"
  local rc10xc2=$?
  local vp_ext2
  vp_ext2="$(jq -r '.["観点"]["外部仕様の確定"]' "$ext_record" 2>/dev/null)"
  check "外部仕様の確定が要確認の記録を2回照合しても観点の値が一致する" "$([ "$rc10xc2" -eq 0 ] && [ "$vp_ext1" = "$vp_ext2" ] && echo 0 || echo 1)"

  # --- 判定と観点の整合（コードレビュー警告1: 否ありなのに合格・要確認のみなのに不合格） ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=否" --judged "$judged4" --reason "" \
    > "$base/r12.out" 2>"$base/r12.err"
  local rc12=$?
  check "否ありなのに合格は終了コード2" "$([ "$rc12" -eq 2 ] && echo 0 || echo 1)"
  check "否ありなのに合格の理由に判定-観点不整合" "$(grep -qF '判定-観点不整合' "$base/r12.err" && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 不合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r13.out" 2>"$base/r13.err"
  local rc13=$?
  check "要確認のみなのに不合格は終了コード2" "$([ "$rc13" -eq 2 ] && echo 0 || echo 1)"
  check "要確認のみなのに不合格の理由に判定-観点不整合" "$(grep -qF '判定-観点不整合' "$base/r13.err" && echo 0 || echo 1)"

  # --- 判定した時点と記録を書く時点の同一性の食い違い（第1回改善指示書1-23） ---
  local judged_old="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  echo "# 画面基本設計書（改訂）" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged_old" --reason "" \
    > "$base/r10.out" 2>"$base/r10.err"
  local rc10=$?
  check "判定後に文書が変わったら終了コード1" "$([ "$rc10" -eq 1 ] && echo 0 || echo 1)"
  check "判定後に文書が変わったら理由に同一性-判定後変更" "$(grep -qF '同一性-判定後変更' "$base/r10.err" && echo 0 || echo 1)"
  local before_mtime after_mtime
  before_mtime="$(jq -r '.["文書"]["画面基本設計書.md"]' "$record_file" 2>/dev/null)"
  check "判定後に文書が変わっても既存の記録は上書きされない" "$([ "$before_mtime" = "$sha_expected1" ] && echo 0 || echo 1)"

  # --- 判定した時点と記録を書く時点が同じなら終了コード0 ---
  local judged_now
  judged_now="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged_now" --reason "" \
    > "$base/r11.out" 2>"$base/r11.err"
  check "判定した時点と記録を書く時点が同じなら終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 観点のキーが空文字列なら終了コード2（書く側。観点-キー空） ---
  local emptykey_record="$d/ai-work/records/basic-design-acceptance/screen-src_pages_EmptyKeyWrite.tsx.json"
  rm -f "$emptykey_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/EmptyKeyWrite.tsx" \
    --verdict 合格 --viewpoints "=合" --judged "x=y" \
    > "$base/r14.out" 2>"$base/r14.err"
  local rc14=$?
  check "観点のキーが空文字列なら終了コード2" "$([ "$rc14" -eq 2 ] && echo 0 || echo 1)"
  check "観点のキーが空文字列なら理由に観点-キー空" "$(grep -qF '観点-キー空' "$base/r14.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$emptykey_record" ]; then
    echo "PASS: 観点のキーが空文字列なら記録を作らない"
  else
    echo "FAIL: 観点のキーが空文字列なら記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 要確認ありで確認事項の記録.mdが読めないなら終了コード2（要確認-判定不能） ---
  local run3="$base/run3-no-confirmations"
  mkdir -p "$run3"
  local noyk_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  rm -f "$noyk_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run3" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r15.out" 2>"$base/r15.err"
  local rc15b=$?
  check "要確認ありで確認事項の記録.mdが読めないなら終了コード2" "$([ "$rc15b" -eq 2 ] && echo 0 || echo 1)"
  check "要確認ありで確認事項の記録.mdが読めない理由に要確認-判定不能" "$(grep -qF '要確認-判定不能' "$base/r15.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$noyk_record" ]; then
    echo "PASS: 要確認ありで確認事項の記録.mdが読めないなら記録を作らない"
  else
    echo "FAIL: 要確認ありで確認事項の記録.mdが読めないなら記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 第1回改善指示書1-31: テスト設計書の出力設定に応じて単体テスト設計書を
  # 記録の文書へ含めるかどうかを切り替える。記録直後にcheck-acceptance-record.sh
  # で照合し、期待どおりの合否になることを確かめる ---
  local d31="$base/target-tests-output"

  # 出力しない・基本設計書のみ実在 → 合格
  local run31a="$d31/run-off-basic-only" unit31a="$d31/docs/design/screens/src_pages_TestsOffBasicOnly.tsx"
  mkdir -p "$run31a" "$unit31a"
  echo "# 画面基本設計書" > "$unit31a/画面基本設計書.md"
  cat > "$run31a/run.json" <<'RUN31AJSON'
{
  "実行の識別子": "2026-09-07-run31a",
  "テスト設計書の出力": "出力しない"
}
RUN31AJSON
  local judged31a="画面基本設計書.md=$(sha_of "$unit31a/画面基本設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31a" --kind screen --unit "src/pages/TestsOffBasicOnly.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31a" --reason "" \
    > "$base/r31a.out" 2>"$base/r31a.err"
  local rc31a_record=$?
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d31" --kind screen --unit "src/pages/TestsOffBasicOnly.tsx" --run "$run31a" \
    > "$base/r31achk.out" 2>"$base/r31achk.err"
  local rc31a_check=$?
  check "テスト出力設定-出力しない基本のみ実在-記録と照合が合格" "$([ "$rc31a_record" -eq 0 ] && [ "$rc31a_check" -eq 0 ] && echo 0 || echo 1)"

  # 出力する・両方実在 → 合格
  local run31b="$d31/run-on-both" unit31b="$d31/docs/design/screens/src_pages_TestsOnBoth.tsx"
  mkdir -p "$run31b" "$unit31b"
  echo "# 画面基本設計書" > "$unit31b/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$unit31b/画面単体テスト設計書.md"
  cat > "$run31b/run.json" <<'RUN31BJSON'
{
  "実行の識別子": "2026-09-07-run31b",
  "テスト設計書の出力": "出力する"
}
RUN31BJSON
  local judged31b="画面基本設計書.md=$(sha_of "$unit31b/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$unit31b/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31b" --kind screen --unit "src/pages/TestsOnBoth.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31b" --reason "" \
    > "$base/r31b.out" 2>"$base/r31b.err"
  local rc31b_record=$?
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d31" --kind screen --unit "src/pages/TestsOnBoth.tsx" --run "$run31b" \
    > "$base/r31bchk.out" 2>"$base/r31bchk.err"
  local rc31b_check=$?
  check "テスト出力設定-出力する両方実在-記録と照合が合格" "$([ "$rc31b_record" -eq 0 ] && [ "$rc31b_check" -eq 0 ] && echo 0 || echo 1)"

  # 出力する・テスト設計書が不在 → 不合格
  local run31c="$d31/run-on-missing" unit31c="$d31/docs/design/screens/src_pages_TestsOnMissing.tsx"
  mkdir -p "$run31c" "$unit31c"
  echo "# 画面基本設計書" > "$unit31c/画面基本設計書.md"
  cat > "$run31c/run.json" <<'RUN31CJSON'
{
  "実行の識別子": "2026-09-07-run31c",
  "テスト設計書の出力": "出力する"
}
RUN31CJSON
  local judged31c="画面基本設計書.md=$(sha_of "$unit31c/画面基本設計書.md");画面単体テスト設計書.md="
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31c" --kind screen --unit "src/pages/TestsOnMissing.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31c" --reason "" \
    > "$base/r31c.out" 2>"$base/r31c.err"
  local rc31c_record=$?
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d31" --kind screen --unit "src/pages/TestsOnMissing.tsx" --run "$run31c" \
    > "$base/r31cchk.out" 2>"$base/r31cchk.err"
  local rc31c_check=$?
  check "テスト出力設定-出力するテスト不在-照合が不合格" "$([ "$rc31c_record" -eq 0 ] && [ "$rc31c_check" -eq 1 ] && echo 0 || echo 1)"

  # 出力しない・基本設計書も不在 → 不合格
  local run31d="$d31/run-off-missing" unit31d="$d31/docs/design/screens/src_pages_TestsOffMissing.tsx"
  mkdir -p "$run31d" "$unit31d"
  cat > "$run31d/run.json" <<'RUN31DJSON'
{
  "実行の識別子": "2026-09-07-run31d",
  "テスト設計書の出力": "出力しない"
}
RUN31DJSON
  local judged31d="画面基本設計書.md="
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31d" --kind screen --unit "src/pages/TestsOffMissing.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31d" --reason "" \
    > "$base/r31d.out" 2>"$base/r31d.err"
  local rc31d_record=$?
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d31" --kind screen --unit "src/pages/TestsOffMissing.tsx" --run "$run31d" \
    > "$base/r31dchk.out" 2>"$base/r31dchk.err"
  local rc31d_check=$?
  check "テスト出力設定-出力しない基本不在-照合が不合格" "$([ "$rc31d_record" -eq 0 ] && [ "$rc31d_check" -eq 1 ] && echo 0 || echo 1)"

  # --- 反証対応: --run指定でrun.jsonが読めない・値が不正なときは判定不能
  # で止まり記録を作らない。空の分岐は使い方の誤り検査で到達不能なため
  # 持たない（2026-09-07反証対応・第2版。第1回改善指示書1-31） ---

  # run.jsonが無い（実行フォルダの取り違え等）→ 判定不能。理由に
  # read-run.shの検査キー（run-不在）が含まれる（2026-09-07反証対応・第2版）
  local run31e="$d31/run-runjson-missing" unit31e="$d31/docs/design/screens/src_pages_TestsRunjsonMissing.tsx"
  mkdir -p "$run31e" "$unit31e"
  echo "# 画面基本設計書" > "$unit31e/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$unit31e/画面単体テスト設計書.md"
  local judged31e="画面基本設計書.md=$(sha_of "$unit31e/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$unit31e/画面単体テスト設計書.md")"
  local record31e="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsRunjsonMissing.tsx.json"
  rm -f "$record31e"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31e" --kind screen --unit "src/pages/TestsRunjsonMissing.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31e" --reason "" \
    > "$base/r31e.out" 2>"$base/r31e.err"
  local rc31e=$?
  check "テスト出力設定-run.json不在-判定不能で記録を作らない" "$([ "$rc31e" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31e.err" && grep -qF 'run-不在' "$base/r31e.err" && [ ! -f "$record31e" ] && echo 0 || echo 1)"

  # 値が出力する・出力しないのどちらでもない → 判定不能
  local run31f="$d31/run-invalid-value" unit31f="$d31/docs/design/screens/src_pages_TestsInvalidValue.tsx"
  mkdir -p "$run31f" "$unit31f"
  echo "# 画面基本設計書" > "$unit31f/画面基本設計書.md"
  cat > "$run31f/run.json" <<'RUN31FJSON'
{
  "実行の識別子": "2026-09-07-run31f",
  "テスト設計書の出力": "出力するかも"
}
RUN31FJSON
  local judged31f="画面基本設計書.md=$(sha_of "$unit31f/画面基本設計書.md")"
  local record31f="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsInvalidValue.tsx.json"
  rm -f "$record31f"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31f" --kind screen --unit "src/pages/TestsInvalidValue.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31f" --reason "" \
    > "$base/r31f.out" 2>"$base/r31f.err"
  local rc31f=$?
  check "テスト出力設定-値が不正-判定不能で記録を作らない" "$([ "$rc31f" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31f.err" && [ ! -f "$record31f" ] && echo 0 || echo 1)"

  # 値が「出力する」に末尾の改行が混ざる → $(...)の末尾改行除去に紛れて正規値と
  # 誤って一致しない。完全一致でだけ受理し、末尾に余計な文字が付く値は不正
  # とする（2026-09-07反証対応・第3版・所見2）
  local run31g="$d31/run-trailing-newline" unit31g="$d31/docs/design/screens/src_pages_TestsTrailingNewline.tsx"
  mkdir -p "$run31g" "$unit31g"
  echo "# 画面基本設計書" > "$unit31g/画面基本設計書.md"
  cat > "$run31g/run.json" <<'RUN31GJSON'
{
  "実行の識別子": "2026-09-07-run31g",
  "テスト設計書の出力": "出力する\n"
}
RUN31GJSON
  local judged31g="画面基本設計書.md=$(sha_of "$unit31g/画面基本設計書.md")"
  local record31g="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsTrailingNewline.tsx.json"
  rm -f "$record31g"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31g" --kind screen --unit "src/pages/TestsTrailingNewline.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31g" --reason "" \
    > "$base/r31g.out" 2>"$base/r31g.err"
  local rc31g=$?
  check "テスト出力設定-値に末尾改行-判定不能で記録を作らない" "$([ "$rc31g" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31g.err" && grep -qF '値-不正' "$base/r31g.err" && [ ! -f "$record31g" ] && echo 0 || echo 1)"

  # run.jsonがJSONとして読めない（壊れたJSON）→ 判定不能。理由に
  # read-run.shの検査キー（run-形式）が含まれる（2026-09-07反証対応・第4版）
  local run31h="$d31/run-json-invalid" unit31h="$d31/docs/design/screens/src_pages_TestsJsonInvalid.tsx"
  mkdir -p "$run31h" "$unit31h"
  echo "# 画面基本設計書" > "$unit31h/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$unit31h/画面単体テスト設計書.md"
  printf '{ invalid json' > "$run31h/run.json"
  local judged31h="画面基本設計書.md=$(sha_of "$unit31h/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$unit31h/画面単体テスト設計書.md")"
  local record31h="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsJsonInvalid.tsx.json"
  rm -f "$record31h"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31h" --kind screen --unit "src/pages/TestsJsonInvalid.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31h" --reason "" \
    > "$base/r31h.out" 2>"$base/r31h.err"
  local rc31h=$?
  check "テスト出力設定-run.json形式不正-判定不能で記録を作らない" "$([ "$rc31h" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31h.err" && grep -qF 'run-形式' "$base/r31h.err" && [ ! -f "$record31h" ] && echo 0 || echo 1)"

  # run.jsonに「実行の識別子」キーが無い（「テスト設計書の出力」キーは
  # 実在する）→ 判定不能。理由にread-run.shの検査キー（キー-不在）が
  # 含まれる（2026-09-07反証対応・第4版・所見1）
  local run31i="$d31/run-id-missing" unit31i="$d31/docs/design/screens/src_pages_TestsIdMissing.tsx"
  mkdir -p "$run31i" "$unit31i"
  echo "# 画面基本設計書" > "$unit31i/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$unit31i/画面単体テスト設計書.md"
  cat > "$run31i/run.json" <<'RUN31IJSON'
{
  "テスト設計書の出力": "出力する"
}
RUN31IJSON
  local judged31i="画面基本設計書.md=$(sha_of "$unit31i/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$unit31i/画面単体テスト設計書.md")"
  local record31i="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdMissing.tsx.json"
  rm -f "$record31i"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31i" --kind screen --unit "src/pages/TestsIdMissing.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31i" --reason "" \
    > "$base/r31i.out" 2>"$base/r31i.err"
  local rc31i=$?
  check "テスト出力設定-実行の識別子キー不在-判定不能で記録を作らない" "$([ "$rc31i" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31i.err" && grep -qF 'キー-不在' "$base/r31i.err" && [ ! -f "$record31i" ] && echo 0 || echo 1)"

  # --- 反証対応・第5版・所見1: run.jsonに「実行の識別子」キーは実在する
  # がnull・空文字列・数値のときも判定不能とし理由に「識別子-不正」を
  # 含める（単位の記録・共通設計文書の記録の両方） ---
  local run31j="$d31/run-id-null" unit31j="$d31/docs/design/screens/src_pages_TestsIdNull.tsx"
  mkdir -p "$run31j" "$unit31j"
  echo "# 画面基本設計書" > "$unit31j/画面基本設計書.md"
  cat > "$run31j/run.json" <<'RUN31JJSON'
{
  "実行の識別子": null,
  "テスト設計書の出力": "出力しない"
}
RUN31JJSON
  local judged31j="画面基本設計書.md=$(sha_of "$unit31j/画面基本設計書.md")"
  local record31j="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdNull.tsx.json"
  rm -f "$record31j"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31j" --kind screen --unit "src/pages/TestsIdNull.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31j" --reason "" \
    > "$base/r31j.out" 2>"$base/r31j.err"
  local rc31j=$?
  check "実行識別子-null-判定不能で記録を作らない" "$([ "$rc31j" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31j.err" && grep -qF '識別子-不正' "$base/r31j.err" && [ ! -f "$record31j" ] && echo 0 || echo 1)"

  local run31k="$d31/run-id-empty" unit31k="$d31/docs/design/screens/src_pages_TestsIdEmpty.tsx"
  mkdir -p "$run31k" "$unit31k"
  echo "# 画面基本設計書" > "$unit31k/画面基本設計書.md"
  cat > "$run31k/run.json" <<'RUN31KJSON'
{
  "実行の識別子": "",
  "テスト設計書の出力": "出力しない"
}
RUN31KJSON
  local judged31k="画面基本設計書.md=$(sha_of "$unit31k/画面基本設計書.md")"
  local record31k="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdEmpty.tsx.json"
  rm -f "$record31k"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31k" --kind screen --unit "src/pages/TestsIdEmpty.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31k" --reason "" \
    > "$base/r31k.out" 2>"$base/r31k.err"
  local rc31k=$?
  check "実行識別子-空文字列-判定不能で記録を作らない" "$([ "$rc31k" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31k.err" && grep -qF '識別子-不正' "$base/r31k.err" && [ ! -f "$record31k" ] && echo 0 || echo 1)"

  local run31l="$d31/run-id-numeric" unit31l="$d31/docs/design/screens/src_pages_TestsIdNumeric.tsx"
  mkdir -p "$run31l" "$unit31l"
  echo "# 画面基本設計書" > "$unit31l/画面基本設計書.md"
  cat > "$run31l/run.json" <<'RUN31LJSON'
{
  "実行の識別子": 123,
  "テスト設計書の出力": "出力しない"
}
RUN31LJSON
  local judged31l="画面基本設計書.md=$(sha_of "$unit31l/画面基本設計書.md")"
  local record31l="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdNumeric.tsx.json"
  rm -f "$record31l"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31l" --kind screen --unit "src/pages/TestsIdNumeric.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31l" --reason "" \
    > "$base/r31l.out" 2>"$base/r31l.err"
  local rc31l=$?
  check "実行識別子-数値-判定不能で記録を作らない" "$([ "$rc31l" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31l.err" && grep -qF '識別子-不正' "$base/r31l.err" && [ ! -f "$record31l" ] && echo 0 || echo 1)"

  local run_common_id_null="$base/run-common-id-null"
  mkdir -p "$run_common_id_null"
  cat > "$run_common_id_null/run.json" <<'RUNCOMMONIDNULLJSON'
{
  "実行の識別子": null
}
RUNCOMMONIDNULLJSON
  echo "# 基盤設計書5" > "$d/docs/design/common/基盤設計書5.md"
  local common_id_null_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書5.json"
  rm -f "$common_id_null_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run_common_id_null" --common 基盤設計書5 \
    --verdict 合格 --viewpoints "非機能の方式の確定=合" --judged "基盤設計書5.md=$(sha_of "$d/docs/design/common/基盤設計書5.md")" --reason "" \
    > "$base/r_common_id_null.out" 2>"$base/r_common_id_null.err"
  local rc_common_id_null=$?
  check "共通設計記録-実行識別子null-判定不能で記録を作らない" "$([ "$rc_common_id_null" -eq 2 ] && grep -qF '設定-判定不能' "$base/r_common_id_null.err" && grep -qF '識別子-不正' "$base/r_common_id_null.err" && [ ! -f "$common_id_null_record" ] && echo 0 || echo 1)"

  # --- 反証対応・第5版・所見2: run.jsonが実在してもOSの権限で読めない
  # とき「run-不可読」で判定不能にする（read-run.shの「run-形式」と
  # 誤って混同しない）。rootはファイル権限の制約を受けないため検証
  # できず、この観点だけ自動PASS扱いにする ---
  if [ "$(id -u)" = "0" ]; then
    check "run読取不可-判定不能で記録を作らない" 0
  else
    local run31m="$d31/run-unreadable" unit31m="$d31/docs/design/screens/src_pages_TestsUnreadable.tsx"
    mkdir -p "$run31m" "$unit31m"
    echo "# 画面基本設計書" > "$unit31m/画面基本設計書.md"
    cat > "$run31m/run.json" <<'RUN31MJSON'
{
  "実行の識別子": "2026-09-07-run31m",
  "テスト設計書の出力": "出力しない"
}
RUN31MJSON
    chmod 000 "$run31m/run.json"
    local judged31m="画面基本設計書.md=$(sha_of "$unit31m/画面基本設計書.md")"
    local record31m="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsUnreadable.tsx.json"
    rm -f "$record31m"
    bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31m" --kind screen --unit "src/pages/TestsUnreadable.tsx" \
      --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31m" --reason "" \
      > "$base/r31m.out" 2>"$base/r31m.err"
    local rc31m=$?
    chmod 644 "$run31m/run.json"
    check "run読取不可-判定不能で記録を作らない" "$([ "$rc31m" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31m.err" && grep -qF 'run-不可読' "$base/r31m.err" && [ ! -f "$record31m" ] && echo 0 || echo 1)"
  fi

  # --- 反証対応・第6版・所見1: 「実行の識別子」が空白だけの文字列でも
  # 「空でない文字列」として通してしまう抜けを塞ぐ ---
  local run31n="$d31/run-id-blank" unit31n="$d31/docs/design/screens/src_pages_TestsIdBlank.tsx"
  mkdir -p "$run31n" "$unit31n"
  echo "# 画面基本設計書" > "$unit31n/画面基本設計書.md"
  cat > "$run31n/run.json" <<'RUN31NJSON'
{
  "実行の識別子": "   ",
  "テスト設計書の出力": "出力しない"
}
RUN31NJSON
  local judged31n="画面基本設計書.md=$(sha_of "$unit31n/画面基本設計書.md")"
  local record31n="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdBlank.tsx.json"
  rm -f "$record31n"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31n" --kind screen --unit "src/pages/TestsIdBlank.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31n" --reason "" \
    > "$base/r31n.out" 2>"$base/r31n.err"
  local rc31n=$?
  check "実行識別子-空白のみ-判定不能で記録を作らない" "$([ "$rc31n" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31n.err" && grep -qF '識別子-不正' "$base/r31n.err" && [ ! -f "$record31n" ] && echo 0 || echo 1)"

  # --- 反証対応・第6版・所見2: 実行フォルダ自体に実行権限が無く中に
  # 入れないときも「run-不可読」で判定不能にする。rootは権限の制約を
  # 受けないため検証できず、この観点だけ自動PASS扱いにする ---
  if [ "$(id -u)" = "0" ]; then
    check "実行フォルダ実行権限なし-判定不能で記録を作らない" 0
  else
    local run31o="$d31/run-dir-unreadable" unit31o="$d31/docs/design/screens/src_pages_TestsDirUnreadable.tsx"
    mkdir -p "$run31o" "$unit31o"
    echo "# 画面基本設計書" > "$unit31o/画面基本設計書.md"
    cat > "$run31o/run.json" <<'RUN31OJSON'
{
  "実行の識別子": "2026-09-07-run31o",
  "テスト設計書の出力": "出力しない"
}
RUN31OJSON
    chmod 600 "$run31o"
    local judged31o="画面基本設計書.md=$(sha_of "$unit31o/画面基本設計書.md")"
    local record31o="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsDirUnreadable.tsx.json"
    rm -f "$record31o"
    bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31o" --kind screen --unit "src/pages/TestsDirUnreadable.tsx" \
      --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31o" --reason "" \
      > "$base/r31o.out" 2>"$base/r31o.err"
    local rc31o=$?
    chmod 755 "$run31o"
    check "実行フォルダ実行権限なし-判定不能で記録を作らない" "$([ "$rc31o" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31o.err" && grep -qF 'run-不可読' "$base/r31o.err" && [ ! -f "$record31o" ] && echo 0 || echo 1)"
  fi

  # --- 反証対応・第7版・所見1: 「実行の識別子」がゼロ幅空白U+200B
  # だけの文字列だと`[\s　]`に一致せず「空でない文字列」として通って
  # しまう抜けを塞ぐ ---
  local run31p="$d31/run-id-invisible" unit31p="$d31/docs/design/screens/src_pages_TestsIdInvisible.tsx"
  mkdir -p "$run31p" "$unit31p"
  echo "# 画面基本設計書" > "$unit31p/画面基本設計書.md"
  cat > "$run31p/run.json" <<'RUN31PJSON'
{
  "実行の識別子": "​",
  "テスト設計書の出力": "出力しない"
}
RUN31PJSON
  local judged31p="画面基本設計書.md=$(sha_of "$unit31p/画面基本設計書.md")"
  local record31p="$d31/ai-work/records/basic-design-acceptance/screen-src_pages_TestsIdInvisible.tsx.json"
  rm -f "$record31p"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d31" --run "$run31p" --kind screen --unit "src/pages/TestsIdInvisible.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged31p" --reason "" \
    > "$base/r31p.out" 2>"$base/r31p.err"
  local rc31p=$?
  check "実行識別子-不可視文字のみ-判定不能で記録を作らない" "$([ "$rc31p" -eq 2 ] && grep -qF '設定-判定不能' "$base/r31p.err" && grep -qF '識別子-不正' "$base/r31p.err" && [ ! -f "$record31p" ] && echo 0 || echo 1)"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
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
