#!/usr/bin/env bash
set -u

# check-business-names.sh — 単位の業務名を機械検査する（一覧を作る機能の完了時の処理）
#
# 目的:
#   完了時の処理「業務名の確定」（AIが業務名.jsonへ書く）の後、4点
#   （業務名が全単位にある・同種別内でフォルダ名が一意・業務名が識別子形の5規則に
#   該当しない・業務名に括弧が無い）を機械で確かめる。加えて、AIが業務名を訂正する
#   ときの衝突解消（区別の割り当て・フォルダ名の作り直し）を、ファイルを書き換えずに
#   試算する機能（--propose）を持つ。業務名そのものの決定・重複解消はAIの仕事であり、
#   本スクリプトは確定済みの値の検査と、訂正候補の試算だけを行う。
#
# 使い方:
#   check-business-names.sh <対象リポジトリのルート> [--design-root <設計書の置き場>]
#   check-business-names.sh <対象リポジトリのルート> [--design-root <設計書の置き場>] --propose <種別> <識別子> <業務名>
#   check-business-names.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。オプションは第1引数の後ならどの
# 位置に置いてもよい。業務名.json・元データJSON・unit-kinds.jsonは設計書の置き場配下の
# 決まった置き場（docs/design/lists/業務名.json・docs/design/lists/<種別>.json・
# docs/design/common/unit-kinds.json）から解決する。
#
# 検査キー（内容を要約した意味語。連番禁止。ただし「規則N」は
# 「業務名の識別子形の判定」節が定める5規則そのものへの参照であり、本スクリプトが
# 独自に振る通し番号ではない）:
#   業務名なし          元データJSONにある単位が業務名.jsonに無い、または業務名が空
#   業務名-括弧          業務名に全角・半角の括弧が1つでもある
#   識別子形-規則N        業務名（括弧を含まない）が5規則のNに当てはまる
#   フォルダ名-重複        同種別内でフォルダ名がNFC正規化後・大文字小文字を区別しない比較で重複する
#
# 終了コード（`--propose`が無い呼び出し=一覧全体の検査）:
#   0 = 全単位が4点に合格
#   1 = 不合格の単位がある（標準出力に一覧）
#   2 = 認識しない余分な引数がある、または第1引数が欠ける
#       （標準エラー出力にキーcheck-引数不正で値。第1引数が欠けるときの値は「第1引数なし」）
#   3 = 業務名.json・元データJSON・unit-kinds.jsonのいずれかが無いか読めない
#       （標準エラー出力にキーcheck-入力不在で不在か読めないパスを1行ずつ。
#        unit-kinds.jsonが無いか読めないときはunit-kinds.jsonの1行だけを出す。
#        複数の元データJSONが無いときはunit-kinds.jsonのkeyの記載順に出す。
#        一覧の集計.json（docs/design/lists/一覧の集計.json）の判定が
#        「対象外」の種別は元データJSONの実在を求めず、走査からも外す。
#        一覧の集計.jsonが無いか読めないときは全種別を対象にする）
#
# 終了コード（`--propose <種別> <識別子> <業務名>`がある呼び出し=試算。ファイルは
# 一切書き換えない）:
#   0 = 試算を完了しJSONを標準出力へ返した（合否はJSONの項目「合否」で判定する。
#       試算が不合格でも終了コードは0のままである）
#   2 = 第1引数が欠ける、または`--propose`の後の引数が3つと一致しない（不足も超過も）、
#       または種別がunit-kinds.jsonのkeyに無い
#       （標準エラー出力にキーpropose-引数不正で値。値は`--propose`の後に続く
#        引数の列（`--propose`自身は含まない）。第1引数が欠けるときの値は「第1引数なし」）
#   3 = 業務名.json・元データJSON・unit-kinds.jsonのいずれかが無いか読めない
#       （標準エラー出力にキーpropose-入力不在。出力順はcheck時と同じ）
#   4 = 識別子が指定の種別で業務名.jsonに無い
#       （標準エラー出力にキーpropose-識別子不在で識別子の値。別の種別に識別子が
#        あっても4である）
#
# 業務名.jsonの形（詳細設計書§4）:
#   { "<種別key>": [ {"識別子":.., "業務名":.., "区別":.. または省略, "フォルダ名":..}, .. ],
#     ..., "退役フォルダ名": { "<種別key>": ["<フォルダ名>", ..], .. } }
#
# フォルダ名の作り方は本スクリプトが再実装せず、常に
# ../reverse-shared/scripts/unit-dir-name.sh（唯一の定義）へ委ねる。
#
# 識別子形の5規則（日本語の判定を含む）は、このマシンのawk（bwk awk）が
# 非ASCII文字列同士の==比較で常にtrueを返す既知の不具合を踏まずbashだけで
# 判定できるよう、UTF-8のバイト値を直接読んで組んでいる（contains_japanese）。
# python3に依存するのはNFC正規化だけであり、python3が無いときはNFC正規化を
# 省きcasefoldのみで比較する。
#
# 規則4・規則5の除外語（定着した略語に加え、対象リポジトリの規約
# docs/rules/business-domain/glossary/rule.md（無ければ空）の表のセルから
# 抜き出した英字だけの語）は glossary_extra_terms() が読む。
#
# 保守責任者: 人手（ユーザー）。業務名の識別子形の判定規則・フォルダ名の導出規則を
#   変えるときは、docs/design/common/リバースの流れの設計.mdの該当節と本スクリプトと
#   自己テストを同時に直す。
#
# 廃棄条件: 業務名の確定・検査を別の仕組みに変えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。jq・python3を使用する
# （python3不在時は上記のとおり劣化して動く）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/../../reverse-shared/scripts" && pwd)"
UNIT_DIR_NAME_SH="${SHARED_SCRIPTS_DIR}/unit-dir-name.sh"

ABBREVS="API ID URL CSV PDF HTML JSON SQL HTTP"

has_python3() {
  command -v python3 > /dev/null 2>&1
}

# --- NFC正規化してcasefoldした値を返す（一意性比較・衝突検出に使う） ---
nfc_fold() {
  local s="$1"
  if has_python3; then
    python3 -c 'import sys, unicodedata; print(unicodedata.normalize("NFC", sys.argv[1]).casefold())' "$s"
  else
    printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
  fi
}

# --- 対象リポジトリの規約docs/rules/business-domain/glossary/rule.mdの表から
# 規則4・5の除外語（英字だけ・長さ2以上のセル）を読む。ファイルが無ければ
# 空文字を返す（呼び出し元は失敗として扱わない） ---
glossary_extra_terms() {
  local target="$1"
  local path="${target%/}/docs/rules/business-domain/glossary/rule.md"
  [ -f "$path" ] || return 0
  grep '^|' "$path" 2> /dev/null \
    | tr '|' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -E '^[A-Za-z][A-Za-z0-9]+$' \
    | sort -u \
    | tr '\n' ' '
}

# --- 業務名に全角・半角の括弧が1つでもあれば真（0） ---
has_parens() {
  case "$1" in
    *'('*|*')'*|*'（'*|*'）'*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- ひらがな（U+3040-309F）・カタカナ（U+30A0-30FF）・漢字（U+4E00-9FFF）を
# 1文字でも含めば真（0）。bwk awk（このマシンのawk）が非ASCII文字列同士の
# ==比較で常にtrueを返す既知の不具合を踏まないよう、python3にもawkの文字列
# 比較にも頼らず、UTF-8のバイト値をLC_ALL=Cのod（バイト単位の8進/16進
# ダンプ）で読み、3バイト系列（先頭バイト0xE0-0xEF）だけをコードポイントへ
# 組み直して数値で判定する（対象の3範囲はいずれも3バイト系列のため） ---
contains_japanese() {
  local s="$1"
  local -a b=()
  local h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    b+=("$h")
  done < <(LC_ALL=C od -An -tx1 -v <<< "$s" | tr -s ' ' '\n' | sed '/^$/d')

  local n=${#b[@]}
  local i=0 b1 b2 b3 cp
  while [ "$i" -lt "$n" ]; do
    b1=$((16#${b[$i]}))
    if [ "$b1" -ge 224 ] && [ "$b1" -le 239 ]; then
      if [ $((i + 2)) -lt "$n" ]; then
        b2=$((16#${b[$((i + 1))]}))
        b3=$((16#${b[$((i + 2))]}))
        cp=$(( ((b1 & 15) << 12) | ((b2 & 63) << 6) | (b3 & 63) ))
        if { [ "$cp" -ge 12352 ] && [ "$cp" -le 12543 ]; } \
          || { [ "$cp" -ge 19968 ] && [ "$cp" -le 40959 ]; }; then
          return 0
        fi
      fi
      i=$((i + 3))
    elif [ "$b1" -ge 240 ]; then
      i=$((i + 4))
    elif [ "$b1" -ge 192 ]; then
      i=$((i + 2))
    else
      i=$((i + 1))
    fi
  done
  return 1
}

# --- 業務名の識別子形の判定（5規則）。当てはまる規則の番号をカンマ区切りで返す
# （無ければ空文字）。$3に用語表由来の追加除外語（空白区切り）を渡せる。
# python3には頼らずbashだけで判定する（python3が要るのはNFC正規化だけ） ---
identifier_form_reasons() {
  # macOS標準のbash3.2では、LC_COLLATEがen_US.UTF-8等のロケールのとき、
  # caseパターンの文字クラス（[a-z]・[A-Z]）が大文字・小文字を区別せず
  # 一致してしまう既知の不具合がある（規則5の遷移判定[a-z][A-Z]が実測で
  # 誤判定していた）。本関数内だけCロケールに固定し、ASCIIの範囲どおりに
  # 判定させる。
  local LC_ALL=C
  local name="$1" id="$2" extra="${3:-}"
  local out=""

  [ "$name" = "$id" ] && out="1"

  if ! contains_japanese "$name"; then
    out="${out:+$out,}2"
  fi

  case "$name" in
    *[/\\_:]*) out="${out:+$out,}3" ;;
  esac

  # --- 規則4・規則5。除外語（略語＋用語表由来）は大文字化した前後空白付きの
  # 1行にして部分一致で判定する ---
  local abbrevs_upper
  abbrevs_upper=" $(printf '%s' "${ABBREVS} ${extra}" | tr '[:lower:]' '[:upper:]') "

  local tokens_upper
  tokens_upper=" $(printf '%s' "$id" | tr -s ' \t/._{}:-' '\n' | grep -v '^$' | tr '[:lower:]' '[:upper:]' | tr '\n' ' ') "

  local runs
  runs="$(printf '%s' "$name" | grep -oE '[A-Za-z]+')"

  local rule4_hit=1 rule5_hit=1
  local run ru len
  while IFS= read -r run; do
    [ -n "$run" ] || continue
    ru="$(printf '%s' "$run" | tr '[:lower:]' '[:upper:]')"
    case "$abbrevs_upper" in
      *" $ru "*) continue ;;
    esac

    len=${#run}
    if [ "$rule4_hit" -ne 0 ] && [ "$len" -ge 4 ]; then
      case "$tokens_upper" in
        *" $ru "*) rule4_hit=0 ;;
      esac
    fi

    if [ "$rule5_hit" -ne 0 ]; then
      local transitions=0 idx n
      n=${#run}
      idx=1
      while [ "$idx" -lt "$n" ]; do
        case "${run:$((idx - 1)):1}${run:$idx:1}" in
          [a-z][A-Z]) transitions=$((transitions + 1)) ;;
        esac
        idx=$((idx + 1))
      done
      [ "$transitions" -ge 2 ] && rule5_hit=0
    fi
  done <<< "$runs"

  [ "$rule4_hit" -eq 0 ] && out="${out:+$out,}4"
  [ "$rule5_hit" -eq 0 ] && out="${out:+$out,}5"

  printf '%s' "$out"
}

# --- 表示名からフォルダ名を作る。唯一の定義であるunit-dir-name.shへ委ねる ---
derive_folder_name() {
  bash "$UNIT_DIR_NAME_SH" "$1" 2>/dev/null
}

# --- 識別子から区別の既定値を作る（末尾の要素。tableは識別子そのまま） ---
derive_distinguisher() {
  local id="$1" kind="${2:-}"
  if [ "$kind" = "table" ]; then
    printf '%s' "$id"
    return
  fi
  local base
  base="$(basename "$id")"
  case "$base" in
    *.*) base="${base%.*}" ;;
  esac
  case "$base" in
    '{'*'}') base="${base#\{}"; base="${base%\}}" ;;
  esac
  printf '%s' "$base"
}

# --- foldedな値の一覧ファイルに、foldedな値が含まれるか ---
fold_contains() {
  local folded="$1" file="$2"
  [ -f "$file" ] || return 1
  grep -Fxq -- "$folded" "$file" 2>/dev/null
}

# ============================================================
# 新規単位のバッチ解決（区別の割り当て・表示名・フォルダ名を作る）
# ============================================================
# 引数:
#   $1 kind
#   $2 candidates_tsv  (行: 識別子<TAB>業務名。すでに識別子形・括弧なしを満たす前提)
#   $3 existing_folded_file （生きた既存単位のフォルダ名。1行1件、fold済みでなくてよい=生の値）
#   $4 retired_folded_file  （退役フォルダ名。同上、生の値）
#   $5 out_tsv (出力: 識別子<TAB>区別(無ければ空)<TAB>表示名<TAB>フォルダ名)
resolve_new_batch() {
  local kind="$1" candidates="$2" existing_raw="$3" retired_raw="$4" out="$5"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/check-business-names-resolve.XXXXXX")"

  : > "$work/existing_fold.txt"
  if [ -f "$existing_raw" ]; then
    local l
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      nfc_fold "$l" >> "$work/existing_fold.txt"
    done < "$existing_raw"
  fi

  : > "$work/retired_fold.txt"
  if [ -f "$retired_raw" ]; then
    local l
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      nfc_fold "$l" >> "$work/retired_fold.txt"
    done < "$retired_raw"
  fi

  : > "$work/rows.tsv"
  local id name naive naive_fold forced
  while IFS=$'\t' read -r id name; do
    [ -n "$id" ] || continue
    naive="$(derive_folder_name "$name")"
    naive_fold="$(nfc_fold "$naive")"
    forced=0
    if fold_contains "$naive_fold" "$work/existing_fold.txt"; then forced=1; fi
    if fold_contains "$naive_fold" "$work/retired_fold.txt"; then forced=1; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$naive" "$naive_fold" "$forced" >> "$work/rows.tsv"
  done < "$candidates"

  # --- 新規同士の衝突グループ（forcedでない行のnaive_foldの重複）を検出する ---
  : > "$work/needs_distinguish.txt"
  local folds_unforced
  folds_unforced="$(awk -F'\t' '$5==0{print $4}' "$work/rows.tsv" | sort -u)"
  local fv
  while IFS= read -r fv; do
    [ -n "$fv" ] || continue
    local members
    members="$(awk -F'\t' -v f="$fv" '$4==f && $5==0{print $1}' "$work/rows.tsv" | LC_ALL=C sort)"
    local cnt
    cnt="$(printf '%s\n' "$members" | grep -c . || true)"
    if [ "${cnt:-0}" -gt 1 ]; then
      # 先頭1件は区別なし、2番目以降に区別
      printf '%s\n' "$members" | tail -n +2 >> "$work/needs_distinguish.txt"
    fi
  done <<< "$folds_unforced"

  : > "$out"
  : > "$work/resolved_fold.txt"
  while IFS=$'\t' read -r id name naive naive_fold forced; do
    [ -n "$id" ] || continue
    local need=0
    if [ "$forced" -eq 1 ]; then
      need=1
    elif grep -Fxq -- "$id" "$work/needs_distinguish.txt" 2>/dev/null; then
      need=1
    fi

    local distinguisher="" display folder folder_fold
    if [ "$need" -eq 1 ]; then
      distinguisher="$(derive_distinguisher "$id" "$kind")"
      display="${name}（${distinguisher}）"
      folder="$(derive_folder_name "$display")"
      folder_fold="$(nfc_fold "$folder")"
      if fold_contains "$folder_fold" "$work/existing_fold.txt" \
        || fold_contains "$folder_fold" "$work/retired_fold.txt" \
        || fold_contains "$folder_fold" "$work/resolved_fold.txt"; then
        distinguisher="$id"
        display="${name}（${distinguisher}）"
        folder="$(derive_folder_name "$display")"
        folder_fold="$(nfc_fold "$folder")"
      fi
    else
      display="$name"
      folder="$(derive_folder_name "$name")"
      folder_fold="$naive_fold"
    fi
    printf '%s\n' "$folder_fold" >> "$work/resolved_fold.txt"
    printf '%s\t%s\t%s\t%s\n' "$id" "$distinguisher" "$display" "$folder" >> "$out"
  done < "$work/rows.tsv"

  rm -rf "$work"
}

# ============================================================
# 引数エラー・入力不在・識別子不在の出力
# ============================================================

arg_error() {
  echo "$1: $2" >&2
  exit 2
}

input_missing_and_exit() {
  local key="$1"; shift
  local p
  for p in "$@"; do
    echo "${key}: ${p}" >&2
  done
  exit 3
}

identifier_missing_and_exit() {
  echo "$1: $2" >&2
  exit 4
}

usage_error() {
  echo "使い方: check-business-names.sh <対象リポジトリのルート> [--design-root <設計書の置き場>]" >&2
  echo "        check-business-names.sh <対象> [--design-root <置き場>] --propose <種別> <識別子> <業務名>" >&2
  echo "        check-business-names.sh --self-test" >&2
  exit 2
}

# ============================================================
# 引数解析
# ============================================================
# 大域変数 P_TARGET/P_DESIGN_ROOT/P_MODE/P_KIND/P_ID/P_NAME へ結果を書く。
# コマンド置換（$(...)）を経由すると、この関数内のexitがサブシェルだけを
# 終了させ呼び出し元へ終了コードが伝わらないため、標準出力へは書かず
# 大域変数へ直接代入する（本関数は必ずコマンド置換を使わず直接呼ぶこと）。
# 引数不正・第1引数なしはこの関数の中で直接 arg_error を呼び exit する。
P_TARGET=""
P_DESIGN_ROOT=""
P_MODE=""
P_KIND=""
P_ID=""
P_NAME=""
parse_args() {
  local has_propose=0
  local a
  for a in "$@"; do
    [ "$a" = "--propose" ] && has_propose=1
  done
  local prefix="check"
  [ "$has_propose" -eq 1 ] && prefix="propose"

  if [ $# -eq 0 ]; then
    arg_error "${prefix}-引数不正" "第1引数なし"
  fi
  case "$1" in
    --*) arg_error "${prefix}-引数不正" "第1引数なし" ;;
  esac

  local target="$1"; shift
  local design_root="$target"

  # --- 事前に --design-root を取り出す（--proposeより前でも後でもよい） ---
  local -a filtered=()
  local x
  while [ $# -gt 0 ]; do
    x="$1"
    if [ "$x" = "--design-root" ]; then
      if [ $# -lt 2 ]; then
        arg_error "${prefix}-引数不正" "--design-root"
      fi
      design_root="$2"
      shift 2
      continue
    fi
    filtered+=("$x")
    shift
  done

  local mode="check"
  local propose_kind="" propose_id="" propose_name=""
  local -a extra=()
  local n=${#filtered[@]}
  local i=0
  local found_propose=0
  while [ $i -lt $n ]; do
    if [ "${filtered[$i]}" = "--propose" ]; then
      found_propose=1
      mode="propose"
      local -a p_rest=()
      local j=$((i + 1))
      while [ $j -lt $n ]; do
        p_rest+=("${filtered[$j]}")
        j=$((j + 1))
      done
      if [ ${#p_rest[@]} -ne 3 ]; then
        local joined=""
        local t
        if [ ${#p_rest[@]} -gt 0 ]; then
          for t in "${p_rest[@]}"; do
            joined="${joined:+$joined }$t"
          done
        fi
        arg_error "propose-引数不正" "$joined"
      fi
      propose_kind="${p_rest[0]}"
      propose_id="${p_rest[1]}"
      propose_name="${p_rest[2]}"
      i=$n
    else
      extra+=("${filtered[$i]}")
      i=$((i + 1))
    fi
  done

  if [ "$mode" = "check" ] && [ ${#extra[@]} -gt 0 ]; then
    local joined=""
    local t
    for t in "${extra[@]}"; do
      joined="${joined:+$joined }$t"
    done
    arg_error "check-引数不正" "$joined"
  fi

  P_TARGET="$target"
  P_DESIGN_ROOT="$design_root"
  P_MODE="$mode"
  P_KIND="$propose_kind"
  P_ID="$propose_id"
  P_NAME="$propose_name"
}

# ============================================================
# 入力解決（unit-kinds.json・業務名.json・元データJSON）
# ============================================================
# 成功時は大域変数 RESOLVED_KINDS へ kinds（改行区切り、unit-kinds.jsonの記載順）を
# 書く。unit-kinds.json・業務名.json・元データJSONの不在はこの中でexitする。
# 到達範囲が対象外の種別（一覧の集計.jsonの判定が「対象外」）は一覧を
# 持たないのが正しいため、不在の判定と走査の対象（RESOLVED_KINDS）の
# 両方から外す。対象外かどうかは一覧の集計.jsonに記録された値から読み、
# 推測しない。一覧の集計.jsonが無いか読めないときは従来どおり全種別を
# 対象にする（対象外の集合が空。第1回改善指示書1-32）。
# 併せて大域変数 ALL_KINDS へ、対象外を除く前のunit-kinds.jsonの全key
# （改行区切り、記載順）を書く。試算（--propose）の種別の照合は、対象外
# の種別を渡した場合でも識別子不在（終了コード4）に落ちる必要があるため
# ALL_KINDSを使い、RESOLVED_KINDS（対象外を除いた集合）は使わない
# （第1回改善指示書1-32）。
# さらに大域変数 OUT_OF_SCOPE_KINDS へ、一覧の集計.jsonの判定が「対象外」
# の種別（改行区切り）を書く。試算（--propose）は、渡された種別がこの
# 集合に含まれるとき、業務名.jsonの実在と可読性は確かめるが、中身
# （識別子）は参照せずに識別子不在（終了コード4）へ進む。対象外の種別は
# 元データJSONを持たない設計のため、業務名.json側に残る古い記載を
# 書き戻しの材料にしないための区別である（第1回改善指示書1-32 第2版反証）。
# コマンド置換（$(...)）を経由すると、この関数内のexitがサブシェルだけを
# 終了させ呼び出し元へ終了コードが伝わらないため、標準出力へは書かず
# 大域変数へ直接代入する（本関数は必ずコマンド置換を使わず直接呼ぶこと）。
RESOLVED_KINDS=""
ALL_KINDS=""
OUT_OF_SCOPE_KINDS=""
resolve_inputs_or_exit() {
  local design_root="$1" prefix="$2"
  local unit_kinds_rel="docs/design/common/unit-kinds.json"
  local business_names_rel="docs/design/lists/業務名.json"
  local aggregate_rel="docs/design/lists/一覧の集計.json"
  local unit_kinds_path="${design_root%/}/${unit_kinds_rel}"
  local business_names_path="${design_root%/}/${business_names_rel}"
  local aggregate_path="${design_root%/}/${aggregate_rel}"

  if [ ! -f "$unit_kinds_path" ] || ! jq -e . "$unit_kinds_path" > /dev/null 2>&1; then
    input_missing_and_exit "${prefix}-入力不在" "$unit_kinds_rel"
  fi

  local kinds
  kinds="$(jq -r '.[]["key"]' "$unit_kinds_path")"
  ALL_KINDS="$kinds"

  local out_of_scope=""
  if [ -f "$aggregate_path" ] && jq -e . "$aggregate_path" > /dev/null 2>&1; then
    out_of_scope="$(jq -r 'to_entries[] | select(.value["判定"] == "対象外") | .key' "$aggregate_path")"
  fi
  OUT_OF_SCOPE_KINDS="$out_of_scope"

  local -a missing=()
  if [ ! -f "$business_names_path" ] || ! jq -e . "$business_names_path" > /dev/null 2>&1; then
    missing+=("$business_names_rel")
  fi
  local -a scoped_kinds=()
  local k
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if [ -n "$out_of_scope" ] && printf '%s\n' "$out_of_scope" | grep -Fxq -- "$k"; then
      continue
    fi
    scoped_kinds+=("$k")
    local p="${design_root%/}/docs/design/lists/${k}.json"
    if [ ! -f "$p" ] || ! jq -e . "$p" > /dev/null 2>&1; then
      missing+=("docs/design/lists/${k}.json")
    fi
  done <<< "$kinds"

  if [ ${#missing[@]} -gt 0 ]; then
    input_missing_and_exit "${prefix}-入力不在" "${missing[@]}"
  fi

  RESOLVED_KINDS=""
  if [ ${#scoped_kinds[@]} -gt 0 ]; then
    RESOLVED_KINDS="$(printf '%s\n' "${scoped_kinds[@]}")"
  fi
}

# ============================================================
# 一覧全体の検査
# ============================================================
run_check() {
  local target="$1" design_root="$2"
  resolve_inputs_or_exit "$design_root" "check"
  local kinds="$RESOLVED_KINDS"

  local business_names_path="${design_root%/}/docs/design/lists/業務名.json"
  local violations=""
  local ng_total=0
  local extra_terms
  extra_terms="$(glossary_extra_terms "$target")"

  local kind
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    local data_path="${design_root%/}/docs/design/lists/${kind}.json"
    local names_json
    names_json="$(jq -c --arg k "$kind" '.[$k] // []' "$business_names_path")"

    # --- 業務名なし ---
    local id
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      local has_name
      has_name="$(printf '%s' "$names_json" | jq -r --arg id "$id" '[.[] | select(.["識別子"] == $id and ((.["業務名"] // "") != ""))] | length')"
      if [ "${has_name:-0}" -eq 0 ]; then
        violations="${violations}${kind}/${id}: 業務名なし
"
        ng_total=$((ng_total + 1))
      fi
    done < <(jq -r '.[]["識別子"]' "$data_path")

    # --- フォルダ名一意性（同種別内、NFC正規化後・大文字小文字を区別しない） ---
    local folders_work
    folders_work="$(mktemp "${TMPDIR:-/tmp}/check-business-names-folders.XXXXXX")"
    : > "$folders_work"
    local n
    n="$(printf '%s' "$names_json" | jq 'length')"
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
      local idx
      for idx in $(seq 0 $((n - 1))); do
        local eid ename efolder
        eid="$(printf '%s' "$names_json" | jq -r --argjson i "$idx" '.[$i]["識別子"]')"
        ename="$(printf '%s' "$names_json" | jq -r --argjson i "$idx" '.[$i]["業務名"] // ""')"
        efolder="$(printf '%s' "$names_json" | jq -r --argjson i "$idx" '.[$i]["フォルダ名"] // ""')"
        [ -n "$ename" ] || continue

        if has_parens "$ename"; then
          violations="${violations}${kind}/${eid}: 業務名-括弧
"
          ng_total=$((ng_total + 1))
        fi

        local reasons
        reasons="$(identifier_form_reasons "$ename" "$eid" "$extra_terms")"
        if [ -n "$reasons" ]; then
          local r rlist=""
          local IFS_OLD="$IFS"
          IFS=','
          for r in $reasons; do
            rlist="${rlist:+$rlist,}識別子形-規則${r}"
          done
          IFS="$IFS_OLD"
          violations="${violations}${kind}/${eid}: ${rlist}
"
          ng_total=$((ng_total + 1))
        fi

        local ffold
        ffold="$(nfc_fold "$efolder")"
        printf '%s\t%s\n' "$ffold" "$eid" >> "$folders_work"
      done
    fi

    local dup_folds
    dup_folds="$(awk -F'\t' '{print $1}' "$folders_work" | sort | uniq -d)"
    local df
    while IFS= read -r df; do
      [ -n "$df" ] || continue
      local dupid
      while IFS= read -r dupid; do
        [ -n "$dupid" ] || continue
        violations="${violations}${kind}/${dupid}: フォルダ名-重複
"
        ng_total=$((ng_total + 1))
      done < <(awk -F'\t' -v f="$df" '$1==f{print $2}' "$folders_work")
    done <<< "$dup_folds"
    rm -f "$folders_work"
  done <<< "$kinds"

  if [ "$ng_total" -gt 0 ]; then
    printf '%s' "$violations"
    exit 1
  fi
  echo "合格: 全単位が4点に合格しました"
  exit 0
}

# ============================================================
# 試算（--propose）
# ============================================================
run_propose() {
  local design_root="$1" kind="$2" id="$3" name="$4"
  resolve_inputs_or_exit "$design_root" "propose"
  # 種別の照合はunit-kinds.jsonの全key（ALL_KINDS）で行う。対象外の種別
  # （RESOLVED_KINDSから除かれる）を渡した場合でも、その種別の一覧を
  # 読まずに識別子不在（終了コード4）へ進む必要があるため、対象外を
  # 除いたRESOLVED_KINDSは使わない（第1回改善指示書1-32）。
  local kinds="$ALL_KINDS"

  if ! printf '%s\n' "$kinds" | grep -Fxq -- "$kind"; then
    arg_error "propose-引数不正" "$kind $id $name"
  fi

  # 対象外の種別（一覧の集計.jsonの判定が「対象外」）は、業務名.jsonに
  # その種別の識別子が残骸として残っていても書き戻しの材料にしない。
  # 業務名.jsonの実在と可読性は確かめるが、中身（識別子）は参照せずに
  # 識別子不在（終了コード4）へ直接進む（第1回改善指示書1-32 第2版反証）。
  if [ -n "$OUT_OF_SCOPE_KINDS" ] && printf '%s\n' "$OUT_OF_SCOPE_KINDS" | grep -Fxq -- "$kind"; then
    identifier_missing_and_exit "propose-識別子不在" "$id"
  fi

  local business_names_path="${design_root%/}/docs/design/lists/業務名.json"
  local names_json
  names_json="$(jq -c --arg k "$kind" '.[$k] // []' "$business_names_path")"

  local found
  found="$(printf '%s' "$names_json" | jq -r --arg id "$id" '[.[] | select(.["識別子"] == $id)] | length')"
  if [ "${found:-0}" -eq 0 ]; then
    identifier_missing_and_exit "propose-識別子不在" "$id"
  fi

  local old_folder
  old_folder="$(printf '%s' "$names_json" | jq -r --arg id "$id" '[.[] | select(.["識別子"] == $id)][0]["フォルダ名"] // ""')"

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/check-business-names-propose.XXXXXX")"
  printf '%s' "$names_json" | jq -r --arg id "$id" '.[] | select(.["識別子"] != $id) | .["フォルダ名"] // empty' > "$work/existing.txt"
  jq -r --arg k "$kind" '.["退役フォルダ名"][$k] // [] | .[]' "$business_names_path" > "$work/retired.txt" 2>/dev/null || : > "$work/retired.txt"

  printf '%s\t%s\n' "$id" "$name" > "$work/candidates.tsv"
  resolve_new_batch "$kind" "$work/candidates.tsv" "$work/existing.txt" "$work/retired.txt" "$work/out.tsv"

  local out_id distinguisher display folder
  # bashのreadはタブをIFSの空白とみなし連続分をまとめて削るため、区別
  # （2列目）が空だと列がずれ込む。タブを一度\037（IFSの空白扱いされない
  # 制御文字）へ置換してから読む
  IFS=$'\037' read -r out_id distinguisher display folder < <(tr '\t' '\037' < "$work/out.tsv")

  local reasons_json="[]"
  local pass="true"
  local reason_list=""
  if has_parens "$name"; then
    reason_list="${reason_list:+$reason_list\n}業務名-括弧"
  fi
  local extra_terms
  extra_terms="$(glossary_extra_terms "$P_TARGET")"
  local reasons
  reasons="$(identifier_form_reasons "$name" "$id" "$extra_terms")"
  if [ -n "$reasons" ]; then
    local r
    local IFS_OLD="$IFS"
    IFS=','
    for r in $reasons; do
      reason_list="${reason_list:+$reason_list\n}識別子形-規則${r}"
    done
    IFS="$IFS_OLD"
  fi
  if [ -n "$reason_list" ]; then
    pass="false"
    reasons_json="$(printf "%b" "$reason_list" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  fi

  local gouhi="合格"
  [ "$pass" = "false" ] && gouhi="不合格"

  local distinguisher_json="null"
  [ -n "$distinguisher" ] && distinguisher_json="$(jq -n --arg v "$distinguisher" '$v')"

  local new_fold old_fold retire_json="null"
  new_fold="$(nfc_fold "$folder")"
  old_fold="$(nfc_fold "$old_folder")"
  if [ -n "$old_folder" ] && [ "$new_fold" != "$old_fold" ]; then
    retire_json="$(jq -n --arg v "$old_folder" '$v')"
  fi

  jq -n --arg gouhi "$gouhi" --argjson reasons "$reasons_json" \
    --argjson distinguisher "$distinguisher_json" --arg display "$display" --arg folder "$folder" \
    --argjson retire "$retire_json" \
    '{"合否": $gouhi, "不合格の理由": $reasons, "区別": $distinguisher, "表示名": $display, "フォルダ名": $folder, "退役へ移す旧フォルダ名": $retire}'

  rm -rf "$work"
  exit 0
}

# ============================================================
# 自己テスト
# ============================================================
self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/check-business-names-self-test.XXXXXX")" || { echo "[FAIL] 自己テスト用一時領域を作れません"; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

  check() {
    local desc="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc}"
      fail=$((fail + 1))
    fi
  }

  write_unit_kinds() {
    cat > "$1" <<'EOF'
[
  { "key": "screen", "名前": "画面", "フォルダ": "screens" },
  { "key": "api", "名前": "接続窓口", "フォルダ": "apis" },
  { "key": "table", "名前": "表", "フォルダ": "tables" },
  { "key": "batch", "名前": "バッチ", "フォルダ": "batches" },
  { "key": "report", "名前": "帳票", "フォルダ": "reports" },
  { "key": "external", "名前": "外部連携", "フォルダ": "externals" },
  { "key": "feature", "名前": "機能", "フォルダ": "features" }
]
EOF
  }

  build_fixture_ab() {
    # 業務名.jsonにA(受注一覧)・B(出荷一覧)を持つ現場コード（case17-20の前提）
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d/docs/design/common" "$d/docs/design/lists"
    write_unit_kinds "$d/docs/design/common/unit-kinds.json"
    for k in screen api table batch report external feature; do
      echo "[]" > "$d/docs/design/lists/${k}.json"
    done
    cat > "$d/docs/design/lists/screen.json" <<'EOF'
[
  {"種別":"screen","識別子":"screens/a-list.tsx","名前":"a","場所":"screens/a-list.tsx","根拠":"screens/a-list.tsx","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"screens/b-list.tsx","名前":"b","場所":"screens/b-list.tsx","根拠":"screens/b-list.tsx","単位の定義":"","属するファイル":[],"分類軸":[]}
]
EOF
    cat > "$d/docs/design/lists/業務名.json" <<'EOF'
{
  "screen": [
    {"識別子":"screens/a-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"受注一覧"},
    {"識別子":"screens/b-list.tsx","業務名":"出荷一覧","区別":null,"フォルダ名":"出荷一覧"}
  ],
  "退役フォルダ名": {}
}
EOF
  }

  # ============================================================
  # ケース11: 一覧-業務名重複-区別-検証（内部関数を直接呼ぶ）
  # ============================================================
  local w11="$base/case11"
  mkdir -p "$w11"
  printf 'screens/a.tsx\t注文一覧\nscreens/b.tsx\t注文一覧\nscreens/c.tsx\t注文一覧\n' > "$w11/candidates.tsv"
  : > "$w11/existing.txt"
  : > "$w11/retired.txt"
  resolve_new_batch "screen" "$w11/candidates.tsv" "$w11/existing.txt" "$w11/retired.txt" "$w11/out.tsv"
  local dis_a dis_b dis_c disp_a folder_a
  dis_a="$(awk -F'\t' '$1=="screens/a.tsx"{print $2}' "$w11/out.tsv")"
  dis_b="$(awk -F'\t' '$1=="screens/b.tsx"{print $2}' "$w11/out.tsv")"
  dis_c="$(awk -F'\t' '$1=="screens/c.tsx"{print $2}' "$w11/out.tsv")"
  folder_a="$(awk -F'\t' '$1=="screens/a.tsx"{print $4}' "$w11/out.tsv")"
  check "一覧-業務名重複-区別: 先頭(a)は区別なし" "$([ -z "$dis_a" ] && echo 0 || echo 1)"
  check "一覧-業務名重複-区別: 2番目(b)に区別が付く" "$([ -n "$dis_b" ] && echo 0 || echo 1)"
  check "一覧-業務名重複-区別: 3番目(c)に区別が付く" "$([ -n "$dis_c" ] && echo 0 || echo 1)"
  check "一覧-業務名重複-区別: フォルダ名が一意(b≠c)" "$([ -n "$dis_b" ] && [ -n "$dis_c" ] && [ "$dis_b" != "$dis_c" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース12: 一覧-業務名-識別子形不可-検証（identifier_form_reasonsを直接呼ぶ）
  # ============================================================
  local r1 r2 r3 r4 r5 r6
  r1="$(identifier_form_reasons "orders一覧" "/orders")"
  r2="$(identifier_form_reasons "getOrderList画面" "/orders/{id}")"
  r3="$(identifier_form_reasons "OrderList" "src/pages/OrderList.tsx")"
  r4="$(identifier_form_reasons "Web注文一覧" "web/order-list.tsx")"
  r5="$(identifier_form_reasons "PayPay決済画面" "pay/checkout.tsx")"
  r6="$(identifier_form_reasons "ID発行API" "/ids")"
  check "一覧-業務名-識別子形不可: orders一覧は不合格(規則4)" "$([ -n "$r1" ] && echo 0 || echo 1)"
  check "一覧-業務名-識別子形不可: getOrderList画面は不合格(規則5)" "$([ -n "$r2" ] && echo 0 || echo 1)"
  # macOS標準のbash3.2では、$( )の中に1行のcase ... esacを書くとパーサが
  # 誤ってesac以降を未解析のまま外へ漏らす既知の不具合があるため（実測:
  # 入れ子の有無・多バイトの有無を問わず単発でも再現）、caseではなく
  # [[ ]]のワイルドカード一致で判定する。
  check "一覧-業務名-識別子形不可: OrderListは不合格(規則2と規則4)" "$([[ ",$r3," == *,2,* && ",$r3," == *,4,* ]] && echo 0 || echo 1)"
  check "一覧-業務名-識別子形不可(日本語判定): Web注文一覧は合格(日本語を含み識別子形でない)" "$([ -z "$r4" ] && echo 0 || echo 1)"
  check "一覧-業務名-識別子形不可: PayPay決済画面は合格" "$([ -z "$r5" ] && echo 0 || echo 1)"
  check "一覧-業務名-識別子形不可(日本語判定): ID発行APIは合格(日本語を含み略語は対象外)" "$([ -z "$r6" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース13: 一覧-フォルダ名-一意-検証（内部関数を直接呼ぶ）
  # ============================================================
  local w13="$base/case13"
  mkdir -p "$w13"
  printf 'screens/list-page.tsx\t注文 一覧\nscreens/order-list.tsx\t注文?一覧\n' > "$w13/candidates.tsv"
  : > "$w13/existing.txt"
  : > "$w13/retired.txt"
  resolve_new_batch "screen" "$w13/candidates.tsv" "$w13/existing.txt" "$w13/retired.txt" "$w13/out.tsv"
  local dis_list dis_order disp_order folder_order
  dis_list="$(awk -F'\t' '$1=="screens/list-page.tsx"{print $2}' "$w13/out.tsv")"
  dis_order="$(awk -F'\t' '$1=="screens/order-list.tsx"{print $2}' "$w13/out.tsv")"
  disp_order="$(awk -F'\t' '$1=="screens/order-list.tsx"{print $3}' "$w13/out.tsv")"
  folder_order="$(awk -F'\t' '$1=="screens/order-list.tsx"{print $4}' "$w13/out.tsv")"
  check "一覧-フォルダ名-一意: バイト順で後の単位(order-list.tsx)に区別" "$([ "$dis_order" = "order-list" ] && echo 0 || echo 1)"
  check "一覧-フォルダ名-一意: 先頭(list-page.tsx)は区別なし" "$([ -z "$dis_list" ] && echo 0 || echo 1)"
  check "一覧-フォルダ名-一意: 表示名が『注文?一覧（order-list）』" "$([ "$disp_order" = "注文?一覧（order-list）" ] && echo 0 || echo 1)"
  check "一覧-フォルダ名-一意: フォルダ名が『注文_一覧（order-list）』" "$([ "$folder_order" = "注文_一覧（order-list）" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース14: 一覧-フォルダ名-再利用禁止-検証
  #   退役フォルダ名にある名前が、無関係の新規単位の解決結果に紛れ込まない
  #   （退役名を新規単位へ再割当てするプールとして使わない）ことと、
  #   試算(--propose)がファイルを一切書き換えないことの2点で検証する。
  # ============================================================
  local w14="$base/case14"
  mkdir -p "$w14"
  printf 'screens/new-page.tsx\t新画面一覧\n' > "$w14/candidates.tsv"
  printf '旧一覧\n' > "$w14/retired.txt"
  : > "$w14/existing.txt"
  resolve_new_batch "screen" "$w14/candidates.tsv" "$w14/existing.txt" "$w14/retired.txt" "$w14/out.tsv"
  local folder14
  folder14="$(awk -F'\t' '$1=="screens/new-page.tsx"{print $4}' "$w14/out.tsv")"
  check "一覧-フォルダ名-再利用禁止: 無関係の新規単位に退役名が再利用されない" "$([ "$folder14" != "旧一覧" ] && echo 0 || echo 1)"

  local w14b="$base/case14b"
  build_fixture_ab "$w14b"
  cp "$w14b/docs/design/lists/業務名.json" "$base/case14b-before.json"
  bash "$0" "$w14b" --propose screen screens/b-list.tsx 受注一覧 > "$base/case14b.out" 2>"$base/case14b.err"
  check "一覧-フォルダ名-再利用禁止: 試算後も業務名.jsonが変わらない" "$(cmp -s "$base/case14b-before.json" "$w14b/docs/design/lists/業務名.json" && echo 0 || echo 1)"

  # ============================================================
  # ケース15: 一覧-業務名-括弧-検証
  # ============================================================
  check "一覧-業務名-括弧: 全角括弧を含む候補は不合格" "$(has_parens "注文一覧（管理者）画面" && echo 0 || echo 1)"
  check "一覧-業務名-括弧: 半角括弧を含む候補は不合格" "$(has_parens "注文一覧(管理者)画面" && echo 0 || echo 1)"
  check "一覧-業務名-括弧: 括弧を含まない業務名は合格" "$(has_parens "注文一覧・管理者画面" && echo 1 || echo 0)"

  # ============================================================
  # ケース16: 一覧-フォルダ名-退役名衝突-検証
  # ============================================================
  local w16="$base/case16"
  mkdir -p "$w16"
  printf 'screens/orders.tsx\t受注一覧\n' > "$w16/candidates.tsv"
  : > "$w16/existing.txt"
  printf '受注一覧\n' > "$w16/retired.txt"
  resolve_new_batch "screen" "$w16/candidates.tsv" "$w16/existing.txt" "$w16/retired.txt" "$w16/out.tsv"
  local dis16 disp16 folder16
  dis16="$(awk -F'\t' '$1=="screens/orders.tsx"{print $2}' "$w16/out.tsv")"
  disp16="$(awk -F'\t' '$1=="screens/orders.tsx"{print $3}' "$w16/out.tsv")"
  folder16="$(awk -F'\t' '$1=="screens/orders.tsx"{print $4}' "$w16/out.tsv")"
  check "一覧-フォルダ名-退役名衝突: 新規単位に区別orders" "$([ "$dis16" = "orders" ] && echo 0 || echo 1)"
  check "一覧-フォルダ名-退役名衝突: 表示名『受注一覧（orders）』" "$([ "$disp16" = "受注一覧（orders）" ] && echo 0 || echo 1)"
  check "一覧-フォルダ名-退役名衝突: フォルダ名『受注一覧（orders）』" "$([ "$folder16" = "受注一覧（orders）" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース17: 一覧-業務名訂正-試算-検証
  # ============================================================
  local w17="$base/case17"
  build_fixture_ab "$w17"
  bash "$0" "$w17" --propose screen screens/b-list.tsx 受注一覧 > "$base/case17.out" 2>"$base/case17.err"
  local rc17=$?
  local gouhi17 dis17 disp17 folder17 retire17
  gouhi17="$(jq -r '.["合否"]' "$base/case17.out" 2>/dev/null)"
  dis17="$(jq -r '.["区別"]' "$base/case17.out" 2>/dev/null)"
  disp17="$(jq -r '.["表示名"]' "$base/case17.out" 2>/dev/null)"
  folder17="$(jq -r '.["フォルダ名"]' "$base/case17.out" 2>/dev/null)"
  retire17="$(jq -r '.["退役へ移す旧フォルダ名"]' "$base/case17.out" 2>/dev/null)"
  check "一覧-業務名訂正-試算: 終了コード0" "$([ "$rc17" -eq 0 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: 合否=合格" "$([ "$gouhi17" = "合格" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: 区別=b-list" "$([ "$dis17" = "b-list" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: 表示名=受注一覧（b-list）" "$([ "$disp17" = "受注一覧（b-list）" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: フォルダ名=受注一覧（b-list）" "$([ "$folder17" = "受注一覧（b-list）" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: 退役へ移す旧フォルダ名=出荷一覧" "$([ "$retire17" = "出荷一覧" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算: 業務名.jsonが変わらない" "$(cmp -s "$w14b/docs/design/lists/業務名.json" "$w17/docs/design/lists/業務名.json" 2>/dev/null; [ -f "$w17/docs/design/lists/業務名.json" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース18: 一覧-業務名訂正-試算エラー-検証（識別子不在）
  # ============================================================
  local w18="$base/case18"
  build_fixture_ab "$w18"
  bash "$0" "$w18" --propose screen screens/c-list.tsx 受付一覧 > "$base/case18.out" 2>"$base/case18.err"
  local rc18=$?
  check "一覧-業務名訂正-試算エラー(識別子不在): 終了コード4" "$([ "$rc18" -eq 4 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算エラー(識別子不在): 標準エラー出力" "$(grep -qF 'propose-識別子不在: screens/c-list.tsx' "$base/case18.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース19: 一覧-業務名訂正-試算エラー-引数不正-検証
  # ============================================================
  local w19="$base/case19"
  build_fixture_ab "$w19"
  bash "$0" "$w19" --propose screen screens/b-list.tsx > "$base/case19.out" 2>"$base/case19.err"
  local rc19=$?
  check "一覧-業務名訂正-試算エラー(引数不正): 終了コード2" "$([ "$rc19" -eq 2 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算エラー(引数不正): 標準エラー出力" "$(grep -qF 'propose-引数不正: screen screens/b-list.tsx' "$base/case19.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース20: 一覧-業務名訂正-試算エラー-入力不在-検証
  # ============================================================
  local w20="$base/case20"
  build_fixture_ab "$w20"
  rm -f "$w20/docs/design/lists/業務名.json"
  bash "$0" "$w20" --propose screen screens/a-list.tsx 受注一覧 > "$base/case20.out" 2>"$base/case20.err"
  local rc20=$?
  check "一覧-業務名訂正-試算エラー(入力不在): 終了コード3" "$([ "$rc20" -eq 3 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算エラー(入力不在): 標準エラー出力" "$(grep -qF 'propose-入力不在: docs/design/lists/業務名.json' "$base/case20.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース21: 一覧-業務名-検査不合格-検証
  # ============================================================
  local w21="$base/case21"
  mkdir -p "$w21/docs/design/common" "$w21/docs/design/lists"
  write_unit_kinds "$w21/docs/design/common/unit-kinds.json"
  for k in screen api table batch report external feature; do
    echo "[]" > "$w21/docs/design/lists/${k}.json"
  done
  cat > "$w21/docs/design/lists/screen.json" <<'EOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx","単位の定義":"","属するファイル":[],"分類軸":[]}
]
EOF
  cat > "$w21/docs/design/lists/業務名.json" <<'EOF'
{
  "screen": [
    {"識別子":"src/pages/OrderList.tsx","業務名":"OrderList","区別":null,"フォルダ名":"OrderList"}
  ],
  "退役フォルダ名": {}
}
EOF
  bash "$0" "$w21" > "$base/case21.out" 2>"$base/case21.err"
  local rc21=$?
  check "一覧-業務名-検査不合格: 終了コード1" "$([ "$rc21" -eq 1 ] && echo 0 || echo 1)"
  check "一覧-業務名-検査不合格: 規則2が出る" "$(grep -q '規則2' "$base/case21.out" && echo 0 || echo 1)"
  check "一覧-業務名-検査不合格: 規則4が出る" "$(grep -q '規則4' "$base/case21.out" && echo 0 || echo 1)"

  # ============================================================
  # ケース22: 一覧-業務名-検査入力不在-検証
  # ============================================================
  local w22="$base/case22"
  build_fixture_ab "$w22"
  rm -f "$w22/docs/design/lists/screen.json"
  bash "$0" "$w22" > "$base/case22.out" 2>"$base/case22.err"
  local rc22=$?
  check "一覧-業務名-検査入力不在: 終了コード3" "$([ "$rc22" -eq 3 ] && echo 0 || echo 1)"
  check "一覧-業務名-検査入力不在: 標準エラー出力" "$(grep -qF 'check-入力不在: docs/design/lists/screen.json' "$base/case22.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース23: 一覧-業務名-検査引数不正-検証
  # ============================================================
  local w23="$base/case23"
  build_fixture_ab "$w23"
  bash "$0" "$w23" 余分 > "$base/case23.out" 2>"$base/case23.err"
  local rc23=$?
  check "一覧-業務名-検査引数不正: 終了コード2" "$([ "$rc23" -eq 2 ] && echo 0 || echo 1)"
  check "一覧-業務名-検査引数不正: 標準エラー出力" "$(grep -qF 'check-引数不正: 余分' "$base/case23.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース24: 一覧-業務名-検査第1引数欠け-検証
  # ============================================================
  local w24="$base/case24"
  build_fixture_ab "$w24"
  bash "$0" --design-root "$w24" > "$base/case24.out" 2>"$base/case24.err"
  local rc24=$?
  check "一覧-業務名-検査第1引数欠け: 終了コード2" "$([ "$rc24" -eq 2 ] && echo 0 || echo 1)"
  check "一覧-業務名-検査第1引数欠け: 標準エラー出力" "$(grep -qF 'check-引数不正: 第1引数なし' "$base/case24.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース25: 一覧-業務名訂正-試算無衝突-検証
  #   衝突する他の単位が無いときの試算が、列ずれ無く区別=null・
  #   表示名/フォルダ名=新業務名そのものを返すことを検証する
  # ============================================================
  local w25="$base/case25"
  mkdir -p "$w25/docs/design/common" "$w25/docs/design/lists"
  write_unit_kinds "$w25/docs/design/common/unit-kinds.json"
  local k25
  for k25 in screen api table batch report external feature; do
    echo "[]" > "$w25/docs/design/lists/${k25}.json"
  done
  cat > "$w25/docs/design/lists/screen.json" <<'EOF'
[
  {"種別":"screen","識別子":"screens/a-list.tsx","名前":"a","場所":"screens/a-list.tsx","根拠":"screens/a-list.tsx","単位の定義":"","属するファイル":[],"分類軸":[]}
]
EOF
  cat > "$w25/docs/design/lists/業務名.json" <<'EOF'
{
  "screen": [
    {"識別子":"screens/a-list.tsx","業務名":"受注一覧","区別":null,"フォルダ名":"受注一覧"}
  ],
  "退役フォルダ名": {}
}
EOF
  bash "$0" "$w25" --propose screen screens/a-list.tsx 出荷一覧 > "$base/case25.out" 2>"$base/case25.err"
  local rc25=$?
  local gouhi25 dis25 disp25 folder25 retire25
  gouhi25="$(jq -r '.["合否"]' "$base/case25.out" 2>/dev/null)"
  dis25="$(jq -r '.["区別"]' "$base/case25.out" 2>/dev/null)"
  disp25="$(jq -r '.["表示名"]' "$base/case25.out" 2>/dev/null)"
  folder25="$(jq -r '.["フォルダ名"]' "$base/case25.out" 2>/dev/null)"
  retire25="$(jq -r '.["退役へ移す旧フォルダ名"]' "$base/case25.out" 2>/dev/null)"
  check "一覧-業務名訂正-試算無衝突: 終了コード0" "$([ "$rc25" -eq 0 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算無衝突: 合否=合格" "$([ "$gouhi25" = "合格" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算無衝突: 区別=null" "$([ "$dis25" = "null" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算無衝突: 表示名=出荷一覧" "$([ "$disp25" = "出荷一覧" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算無衝突: フォルダ名=出荷一覧" "$([ "$folder25" = "出荷一覧" ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算無衝突: 退役へ移す旧フォルダ名=受注一覧" "$([ "$retire25" = "受注一覧" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース26: 一覧-業務名-用語表除外-検証
  #   対象リポジトリのdocs/rules/business-domain/glossary/rule.mdの表に
  #   ある英字語が、規則4の除外語として働くことを検証する
  # ============================================================
  local w26="$base/case26"
  mkdir -p "$w26/docs/design/common" "$w26/docs/design/lists"
  write_unit_kinds "$w26/docs/design/common/unit-kinds.json"
  local k26
  for k26 in screen api table batch report external feature; do
    echo "[]" > "$w26/docs/design/lists/${k26}.json"
  done
  cat > "$w26/docs/design/lists/screen.json" <<'EOF'
[
  {"種別":"screen","識別子":"paypay/checkout.tsx","名前":"checkout","場所":"paypay/checkout.tsx","根拠":"paypay/checkout.tsx","単位の定義":"","属するファイル":[],"分類軸":[]}
]
EOF
  cat > "$w26/docs/design/lists/業務名.json" <<'EOF'
{
  "screen": [
    {"識別子":"paypay/checkout.tsx","業務名":"決済画面","区別":null,"フォルダ名":"決済画面"}
  ],
  "退役フォルダ名": {}
}
EOF
  bash "$0" "$w26" --propose screen paypay/checkout.tsx PayPay決済画面 > "$base/case26-before.out" 2>"$base/case26-before.err"
  local gouhi26_before
  gouhi26_before="$(jq -r '.["合否"]' "$base/case26-before.out" 2>/dev/null)"
  check "一覧-業務名-用語表除外: 用語表が無いときは規則4で不合格(回帰確認)" "$([ "$gouhi26_before" = "不合格" ] && echo 0 || echo 1)"

  mkdir -p "$w26/docs/rules/business-domain/glossary"
  cat > "$w26/docs/rules/business-domain/glossary/rule.md" <<'EOF'
# 業務の言葉の決まり

## このプロジェクトの規則

| 語 | 識別子 | 定義 |
|---|---|---|
| PayPay | paypay/checkout.tsx | 決済サービスの名称 |
EOF
  bash "$0" "$w26" --propose screen paypay/checkout.tsx PayPay決済画面 > "$base/case26-after.out" 2>"$base/case26-after.err"
  local gouhi26_after
  gouhi26_after="$(jq -r '.["合否"]' "$base/case26-after.out" 2>/dev/null)"
  check "一覧-業務名-用語表除外: 用語表にある英字語(PayPay)は規則4の対象外になり合格" "$([ "$gouhi26_after" = "合格" ] && echo 0 || echo 1)"

  # ============================================================
  # ケース27: 入力不在-対象外の種別-検証
  #   一覧の集計.jsonの判定が「対象外」の種別は、元データJSONの実在を
  #   求める対象と走査の対象の両方から外れることを検証する
  #   （第1回改善指示書1-32）
  # ============================================================
  write_unit_kinds_3() {
    cat > "$1" <<'EOF'
[
  { "key": "screen", "名前": "画面", "フォルダ": "screens" },
  { "key": "api", "名前": "接続窓口", "フォルダ": "apis" },
  { "key": "table", "名前": "表", "フォルダ": "tables" }
]
EOF
  }

  # --- (a) 対象外の種別（table）の一覧が無くても終了コード0 ---
  local w27a="$base/case27a"
  mkdir -p "$w27a/docs/design/common" "$w27a/docs/design/lists"
  write_unit_kinds_3 "$w27a/docs/design/common/unit-kinds.json"
  echo "[]" > "$w27a/docs/design/lists/screen.json"
  echo "[]" > "$w27a/docs/design/lists/api.json"
  echo '{"退役フォルダ名":{}}' > "$w27a/docs/design/lists/業務名.json"
  echo '{"table":{"判定":"対象外"}}' > "$w27a/docs/design/lists/一覧の集計.json"
  bash "$0" "$w27a" > "$base/case27a.out" 2>"$base/case27a.err"
  local rc27a=$?
  check "入力不在-対象外の種別: 一覧が無くても終了コード0" "$([ "$rc27a" -eq 0 ] && echo 0 || echo 1)"

  # --- (b) 対象の種別（api）の一覧が無ければ終了コード3で、
  #         標準エラーの不在の一覧に対象外の種別（table）を含めない ---
  local w27b="$base/case27b"
  mkdir -p "$w27b/docs/design/common" "$w27b/docs/design/lists"
  write_unit_kinds_3 "$w27b/docs/design/common/unit-kinds.json"
  echo "[]" > "$w27b/docs/design/lists/screen.json"
  echo '{"退役フォルダ名":{}}' > "$w27b/docs/design/lists/業務名.json"
  echo '{"table":{"判定":"対象外"}}' > "$w27b/docs/design/lists/一覧の集計.json"
  bash "$0" "$w27b" > "$base/case27b.out" 2>"$base/case27b.err"
  local rc27b=$?
  check "入力不在-対象外の種別: 対象の種別が無いと終了コード3" "$([ "$rc27b" -eq 3 ] && echo 0 || echo 1)"
  check "入力不在-対象外の種別: 対象外はエラー出力に出ない" "$(grep -q 'docs/design/lists/api.json' "$base/case27b.err" && ! grep -q 'docs/design/lists/table.json' "$base/case27b.err" && echo 0 || echo 1)"

  # --- (c) 一覧の集計.jsonが無いときは従来どおり全種別が対象 ---
  local w27c="$base/case27c"
  mkdir -p "$w27c/docs/design/common" "$w27c/docs/design/lists"
  write_unit_kinds_3 "$w27c/docs/design/common/unit-kinds.json"
  echo "[]" > "$w27c/docs/design/lists/screen.json"
  echo "[]" > "$w27c/docs/design/lists/api.json"
  echo '{"退役フォルダ名":{}}' > "$w27c/docs/design/lists/業務名.json"
  bash "$0" "$w27c" > "$base/case27c.out" 2>"$base/case27c.err"
  local rc27c=$?
  check "入力不在-一覧の集計が無いとき: 全種別が対象で終了コード3" "$([ "$rc27c" -eq 3 ] && echo 0 || echo 1)"

  # --- (d) --propose の試算でも同じ解決を使い、対象外の種別（table）の
  #         一覧の不在で終了コード3にならない（識別子不在の終了コード4になる） ---
  local w27d="$base/case27d"
  mkdir -p "$w27d/docs/design/common" "$w27d/docs/design/lists"
  write_unit_kinds_3 "$w27d/docs/design/common/unit-kinds.json"
  echo "[]" > "$w27d/docs/design/lists/screen.json"
  echo "[]" > "$w27d/docs/design/lists/api.json"
  echo '{"退役フォルダ名":{}}' > "$w27d/docs/design/lists/業務名.json"
  echo '{"table":{"判定":"対象外"}}' > "$w27d/docs/design/lists/一覧の集計.json"
  bash "$0" "$w27d" --propose screen 存在しない識別子 テスト > "$base/case27d.out" 2>"$base/case27d.err"
  local rc27d=$?
  check "入力不在-対象外の種別-試算: 終了コード4" "$([ "$rc27d" -eq 4 ] && echo 0 || echo 1)"

  # --- (e) --propose で対象外の種別（table）自身を渡しても、その種別の
  #         一覧を読まず識別子不在（終了コード4）になる（第1回改善指示書1-32） ---
  bash "$0" "$w27d" --propose table 存在しない識別子 テスト > "$base/case27e.out" 2>"$base/case27e.err"
  local rc27e=$?
  check "入力不在-対象外の種別-試算-種別自身: 終了コード4でpropose-識別子不在" "$([ "$rc27e" -eq 4 ] && grep -q 'propose-識別子不在' "$base/case27e.err" && echo 0 || echo 1)"

  # --- (g) 対象外の種別（table）の業務名.jsonに識別子の残骸（T_ORDER）が
  #         残っていても、実在と可読性は確かめるが中身は参照せず識別子
  #         不在（終了コード4）になる（第1回改善指示書1-32 第2版反証） ---
  local w27g="$base/case27g"
  mkdir -p "$w27g/docs/design/common" "$w27g/docs/design/lists"
  write_unit_kinds_3 "$w27g/docs/design/common/unit-kinds.json"
  echo "[]" > "$w27g/docs/design/lists/screen.json"
  echo "[]" > "$w27g/docs/design/lists/api.json"
  cat > "$w27g/docs/design/lists/業務名.json" <<'EOF'
{"table":[{"識別子":"T_ORDER","業務名":"受注一覧","フォルダ名":"受注一覧"}],"退役フォルダ名":{}}
EOF
  echo '{"table":{"判定":"対象外"}}' > "$w27g/docs/design/lists/一覧の集計.json"
  bash "$0" "$w27g" --propose table T_ORDER 受注一覧 > "$base/case27g.out" 2>"$base/case27g.err"
  local rc27g=$?
  check "入力不在-対象外の種別-試算-識別子残骸: 終了コード4でpropose-識別子不在" "$([ "$rc27g" -eq 4 ] && grep -q 'propose-識別子不在' "$base/case27g.err" && echo 0 || echo 1)"

  # --- (f) --propose にunit-kinds.jsonのkeyに無い種別（bogus）を渡すと
  #         終了コード2（propose-引数不正）になる ---
  bash "$0" "$w27d" --propose bogus 存在しない識別子 テスト > "$base/case27f.out" 2>"$base/case27f.err"
  local rc27f=$?
  check "入力不在-対象外の種別-試算-未知種別: 終了コード2でpropose-引数不正" "$([ "$rc27f" -eq 2 ] && grep -q 'propose-引数不正' "$base/case27f.err" && echo 0 || echo 1)"

  # ============================================================
  # ケース28: 一覧-業務名訂正-試算エラー-引数無し-検証
  #   --propose の後に引数が1つも無い（p_restが0件）ときに、bash 3.2の
  #   空配列展開の不具合（set -u下でunbound variable）で落ちず、
  #   終了コード2・propose-引数不正（値は空）で止まることを検証する
  # ============================================================
  local w28="$base/case28"
  build_fixture_ab "$w28"
  bash "$0" "$w28" --propose > "$base/case28.out" 2>"$base/case28.err"
  local rc28=$?
  check "一覧-業務名訂正-試算エラー(引数無し): 終了コード2" "$([ "$rc28" -eq 2 ] && echo 0 || echo 1)"
  check "一覧-業務名訂正-試算エラー(引数無し): 標準エラー出力" "$(grep -qF 'propose-引数不正:' "$base/case28.err" && echo 0 || echo 1)"

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

parse_args "$@"

if [ ! -d "$P_TARGET" ]; then
  echo "対象リポジトリが見つかりません: ${P_TARGET}" >&2
  exit 2
fi

if [ "$P_MODE" = "propose" ]; then
  run_propose "$P_DESIGN_ROOT" "$P_KIND" "$P_ID" "$P_NAME"
else
  run_check "$P_TARGET" "$P_DESIGN_ROOT"
fi
