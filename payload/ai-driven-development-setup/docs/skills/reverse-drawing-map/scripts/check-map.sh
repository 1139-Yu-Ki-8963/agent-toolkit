#!/usr/bin/env bash
set -u

# check-map.sh — 道標（reverse-drawing-map の成果物）の構造と実在を検査する
#
# 目的:
#   道標.md は AI が読んで書くため文面は毎回変わるが、第二フェーズが機械で読む
#   部分（節の構成・検出条件のJSONの形・例と場所の実在・候補数・到達範囲の
#   網羅）は毎回同じ形でなければならない。本スクリプトはその形と実在だけを
#   検査し、文面の良し悪しは検査しない。
#
# 使い方:
#   check-map.sh <道標.md> [--target <対象リポジトリのルート>] [--max-lines <N>]
#   check-map.sh --self-test
#
# --max-lines は道標には課さない。互換のため受けるだけで検査には使わない。
# --target を省略した場合、ファイル実在確認を伴う検査（検出条件-例不在・
# 領域-欠落の一部・共通方式-欠落の一部・調査-欠落の一部）は実在確認を行わず、
# 値が埋まっているかどうかだけを検査する。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   節-構成          見出しが「## 0. 対象と時点」〜「## 10. 読みの記録」の11個、この順
#   対象-欠落        節0の6行の値が埋まっている
#   文字コード-形式  節0の文字コードの値がUTF-8/EUC-JP/Shift_JIS/ISO-2022-JPのいずれか
#   調査-欠落        節1の15項目の値・場所が埋まっている（--target指定時は場所の実在も見る）
#   領域-欠落        節2に1行以上あり、--target指定時はフォルダが実在する
#   除外-理由        節3の各行に種類と理由がある（行が無くてもよい）
#   見つけ方-欠落    節4に4.1〜4.7の見出しがあり10行の表が埋まっている。4.8にも本文がある
#   検出条件-形式    各json検出条件の囲みが規定のキーを持つ
#   検出条件-例不在  --target指定時、例・走査の含むが対象配下に実在する
#   取り出し-欠落    4.1〜4.7の事実の項目の表の元が埋まっている
#   動的定義-形式    節5の表の各行に4列がある（行が無くてもよい）
#   候補数-欠落      節6に7種別の行があり、概数が0以上の整数
#   共通方式-欠落    節7に10行があり場所が埋まっている（--target指定時は実在も見る）
#   到達範囲-欠落    節9に7種別の行があり4列が規定の値、理由が埋まっている
#   読み-欠落        節10に節2の全領域の行があり、読み方が規定の値
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格（[FAIL]行を標準エラーへ列挙）
#   2 = 使い方の誤り・ファイル不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。様式（templates/道標.md）の節・検出条件の形を
#   変えるときは、本スクリプトと自己テストを同時に更新する。
#
# macOS bash 3.2 互換（連想配列は不使用）。

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

path_list_missing() {
  # path_list_missing <target> <;区切りのパス一覧>
  # 各パスをtrimして実在確認し、対象配下に実在しないものをカンマ区切りで返す（すべて実在すれば空文字）
  local target="$1" list="$2"
  local -a parts
  local old_ifs="$IFS"
  IFS=';' read -ra parts <<< "$list"
  IFS="$old_ifs"
  local p missing=""
  for p in "${parts[@]}"; do
    p="$(trim "$p")"
    [ -z "$p" ] && continue
    if [ ! -e "${target}/${p}" ]; then
      missing="${missing}${missing:+, }${p}"
    fi
  done
  printf '%s' "$missing"
}

section_text() {
  # section_text <content> <開始見出しの完全一致文字列>
  # 次の「## 」見出し行、またはEOFまでを返す
  local content="$1" start="$2"
  awk -v start="$start" '
    BEGIN{flag=0}
    index($0,start)==1 {flag=1; next}
    flag && /^## / {flag=0}
    flag {print}
  ' <<< "$content"
}

sub4_text() {
  # sub4_text <content> <開始見出しの完全一致文字列(### 4.N ...)>
  # 次の「### 」または「## 」見出し行、またはEOFまでを返す
  local content="$1" start="$2"
  awk -v start="$start" '
    BEGIN{flag=0}
    index($0,start)==1 {flag=1; next}
    flag && (/^### / || /^## /) {flag=0}
    flag {print}
  ' <<< "$content"
}

table_data_rows() {
  # table_data_rows <text>  表のヘッダ行・区切り行を除いたデータ行だけを返す
  local text="$1"
  local rows
  rows="$(grep -E '^\|.*\|[[:space:]]*$' <<< "$text" || true)"
  rows="$(grep -vE '^\|[-:|[:space:]]+$' <<< "$rows" || true)"
  # 先頭行(ヘッダ)を除く
  tail -n +2 <<< "$rows" 2>/dev/null | grep -v '^$' || true
}

first_table_text() {
  # first_table_text <text>  最初の表ブロック（'|'始まりの連続行）だけを返す
  awk '
    /^\|/ { intable=1; print; next }
    intable && !/^\|/ { exit }
  ' <<< "$1"
}

json_block_count() {
  # json_block_count <text>  ```json 検出条件 の囲みの個数を返す
  awk '/^```json 検出条件[[:space:]]*$/{c++} END{print c+0}' <<< "$1"
}

json_block_at() {
  # json_block_at <text> <n>  n番目(1始まり)の検出条件ブロックの中身を返す
  local text="$1" n="$2"
  awk -v want="$n" '
    BEGIN{flag=0; idx=0}
    /^```json 検出条件[[:space:]]*$/ { idx++; if (idx==want) flag=1; next }
    /^```[[:space:]]*$/ { if (flag) { flag=0 } next }
    flag { print }
  ' <<< "$text"
}

has_jq() {
  command -v jq > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 本体
# ---------------------------------------------------------------------------

check_map() {
  local file="$1" target="$2"
  local content
  content="$(cat "$file")"

  # 節-構成
  local -a expected_headings=(
    "## 0. 対象と時点"
    "## 1. 調査"
    "## 2. 領域"
    "## 3. 除外"
    "## 4. 単位の見つけ方"
    "## 5. 動的な定義"
    "## 6. 候補数"
    "## 7. 共通方式の場所"
    "## 8. 用語の候補"
    "## 9. 到達範囲"
    "## 10. 読みの記録"
  )
  local actual
  actual="$(grep -E '^## ' "$file" || true)"
  local expected_joined actual_joined
  expected_joined="$(printf '%s\n' "${expected_headings[@]}")"
  actual_joined="$actual"
  if [ "$expected_joined" = "$actual_joined" ]; then
    passck
  else
    fail "節-構成" "見出しが規定の11個・順序と一致しません（実際: $(printf '%s' "$actual_joined" | tr '\n' '/')）"
  fi

  # 対象-欠落 (節0)
  local sec0
  sec0="$(section_text "$content" "## 0. 対象と時点")"
  local -a labels0=("対象" "ブランチ" "コミット" "作成日" "文字コード" "構成の形")
  local rows0
  rows0="$(table_data_rows "$sec0")"
  local label0 i0 ok0
  ok0=1
  for label0 in "${labels0[@]}"; do
    local matched=""
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      if [ "$(col "$r" 1)" = "$label0" ]; then matched="$r"; break; fi
    done <<< "$rows0"
    if [ -z "$matched" ]; then
      fail "対象-欠落" "「${label0}」の行がありません"
      ok0=0
      continue
    fi
    local v0
    v0="$(col "$matched" 2)"
    if [ -z "$v0" ] || [ "${v0:0:1}" = "<" ]; then
      fail "対象-欠落" "「${label0}」の値が未記入です"
      ok0=0
    fi
  done
  [ "$ok0" -eq 1 ] && passck

  # 文字コード-形式 (節0)
  local charset_row=""
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    if [ "$(col "$r" 1)" = "文字コード" ]; then charset_row="$r"; break; fi
  done <<< "$rows0"
  if [ -n "$charset_row" ]; then
    local charset_val
    charset_val="$(col "$charset_row" 2)"
    case "$charset_val" in
      UTF-8|EUC-JP|Shift_JIS|ISO-2022-JP)
        passck
        ;;
      *)
        fail "文字コード-形式" "「文字コード」の値が規定の4種（UTF-8/EUC-JP/Shift_JIS/ISO-2022-JP）のいずれでもありません（実際: ${charset_val}）"
        ;;
    esac
  fi

  # 調査-欠落 (節1)
  local sec1
  sec1="$(section_text "$content" "## 1. 調査")"
  local -a labels1=("言語と版" "フレームワークと版" "実行環境の前提" "フォルダ構造" "層構造" "入口" "外部接続" "データの保存先" "ミドルウェア" "依存の定義" "ビルド・起動・テストの定義" "環境の値の定義" "テストの枠組みと場所" "UI 共通部品" "共通と単位固有の境界")
  local rows1 label1 ok1
  rows1="$(table_data_rows "$sec1")"
  ok1=1
  for label1 in "${labels1[@]}"; do
    local matched1=""
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      if [ "$(col "$r" 1)" = "$label1" ]; then matched1="$r"; break; fi
    done <<< "$rows1"
    if [ -z "$matched1" ]; then
      fail "調査-欠落" "「${label1}」の行がありません"
      ok1=0
      continue
    fi
    local v1 loc1
    v1="$(col "$matched1" 2)"
    loc1="$(col "$matched1" 3)"
    if [ -z "$v1" ] || [ "${v1:0:1}" = "<" ]; then
      fail "調査-欠落" "「${label1}」の値が未記入です"
      ok1=0
    fi
    if [ -z "$loc1" ] || [ "${loc1:0:1}" = "<" ]; then
      fail "調査-欠落" "「${label1}」の場所が未記入です"
      ok1=0
    elif [ -n "$target" ] && [ "$loc1" != "なし" ]; then
      local missing1
      missing1="$(path_list_missing "$target" "$loc1")"
      if [ -n "$missing1" ]; then
        fail "調査-欠落" "「${label1}」の場所が対象配下に実在しません: ${missing1}"
        ok1=0
      fi
    fi
  done
  [ "$ok1" -eq 1 ] && passck

  # 領域-欠落 (節2)
  local sec2 rows2
  sec2="$(section_text "$content" "## 2. 領域")"
  rows2="$(table_data_rows "$sec2")"
  if [ -z "$(trim "$rows2")" ]; then
    fail "領域-欠落" "節2に行が1つもありません"
  else
    local ok2=1
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      local folder2
      folder2="$(col "$r" 2)"
      if [ -z "$folder2" ] || [ "${folder2:0:1}" = "<" ]; then
        fail "領域-欠落" "フォルダが未記入の行があります: $(col "$r" 1)"
        ok2=0
      elif [ -n "$target" ] && [ ! -d "${target}/${folder2}" ]; then
        fail "領域-欠落" "フォルダが対象配下に実在しません: ${folder2}"
        ok2=0
      fi
    done <<< "$rows2"
    [ "$ok2" -eq 1 ] && passck
  fi

  # 除外-理由 (節3)
  local sec3 rows3 ok3
  sec3="$(section_text "$content" "## 3. 除外")"
  rows3="$(table_data_rows "$sec3")"
  ok3=1
  if [ -n "$(trim "$rows3")" ]; then
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      local kind3 reason3
      kind3="$(col "$r" 2)"
      reason3="$(col "$r" 3)"
      if [ -z "$kind3" ] || [ "${kind3:0:1}" = "<" ] || [ -z "$reason3" ] || [ "${reason3:0:1}" = "<" ]; then
        fail "除外-理由" "種類または理由が未記入の行があります: $(col "$r" 1)"
        ok3=0
      fi
    done <<< "$rows3"
  fi
  [ "$ok3" -eq 1 ] && passck

  # 節4: 見つけ方-欠落 / 検出条件-形式 / 検出条件-例不在 / 取り出し-欠落
  local sec4
  sec4="$(section_text "$content" "## 4. 単位の見つけ方")"

  local -a sub_names=("画面" "接続窓口" "表" "バッチ" "帳票" "外部連携" "機能")
  local -a sub_types=("screen" "api" "table" "batch" "report" "external" "feature")
  local -a sub_facts=(
    "入力項目,表示項目,操作,遷移,呼ぶ接続窓口"
    "経路,入力,出力,検証,呼ぶ処理,触る表"
    "列,型,制約,関係"
    "起動条件,入力,出力,処理の流れ"
    "出力条件,項目,レイアウトの元"
    "相手先,形式,項目,応答,再試行"
    "含む単位"
  )
  local -a labels4=("単位の定義" "走査の範囲" "目印" "分割の規則" "識別子の付け方" "名前の取り方" "説明の取り方" "属するファイル" "分類軸の取り方" "動的な定義の扱い")

  local n
  for n in 1 2 3 4 5 6 7; do
    local name="${sub_names[$((n-1))]}"
    local type="${sub_types[$((n-1))]}"
    local facts="${sub_facts[$((n-1))]}"
    local heading="### 4.${n} ${name}"
    local subtext
    subtext="$(sub4_text "$sec4" "$heading")"
    if [ -z "$(trim "$subtext")" ]; then
      fail "見つけ方-欠落" "${heading} が見つかりません"
      continue
    fi

    local tbl
    tbl="$(first_table_text "$subtext")"
    local rows4
    rows4="$(table_data_rows "$tbl")"
    local ok4=1
    local mark_value=""
    local label4
    for label4 in "${labels4[@]}"; do
      local matched4=""
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if [ "$(col "$r" 1)" = "$label4" ]; then matched4="$r"; break; fi
      done <<< "$rows4"
      if [ -z "$matched4" ]; then
        fail "見つけ方-欠落" "${heading}: 「${label4}」の行がありません"
        ok4=0
        continue
      fi
      local v4
      v4="$(col "$matched4" 2)"
      if [ "$label4" = "目印" ]; then mark_value="$v4"; fi
      if [ -z "$v4" ] || [ "${v4:0:1}" = "<" ]; then
        fail "見つけ方-欠落" "${heading}: 「${label4}」が未記入です"
        ok4=0
      fi
    done

    # json 検出条件 の囲み
    local block_count
    block_count="$(json_block_count "$subtext")"

    if [ "$mark_value" != "AI の読み取り" ]; then
      if [ "${block_count:-0}" -lt 1 ] 2>/dev/null; then
        fail "見つけ方-欠落" "${heading}: json 検出条件 の囲みがありません"
        ok4=0
      fi
      if has_jq; then
        local bk
        for bk in $(seq 1 "${block_count:-0}" 2>/dev/null); do
          local b
          b="$(json_block_at "$subtext" "$bk")"
          if ! jq empty <<< "$b" > /dev/null 2>&1; then
            fail "検出条件-形式" "${heading}: JSONとして読めません"
            continue
          fi
          local jtype jsplit jid
          jtype="$(jq -r '.["種別"] // empty' <<< "$b")"
          jsplit="$(jq -r '.["分割"] // empty' <<< "$b")"
          jid="$(jq -r '.["識別子"]["元"] // empty' <<< "$b")"
          local jscan jmatch jexamples
          jscan="$(jq '(.["走査"]["含む"] // []) | length' <<< "$b")"
          jmatch="$(jq '(.["一致"] // []) | length' <<< "$b")"
          jexamples="$(jq '(.["例"] // []) | length' <<< "$b")"
          if [ "$jtype" != "$type" ]; then
            fail "検出条件-形式" "${heading}: 種別が${type}ではありません（実際: ${jtype}）"
          fi
          if [ "${jscan:-0}" -lt 1 ] 2>/dev/null; then
            fail "検出条件-形式" "${heading}: 走査.含む が空です"
          fi
          if [ "${jmatch:-0}" -lt 1 ] 2>/dev/null; then
            fail "検出条件-形式" "${heading}: 一致 が空です"
          fi
          if [ "$jsplit" != "ファイル" ] && [ "$jsplit" != "一致" ]; then
            fail "検出条件-形式" "${heading}: 分割 が ファイル/一致 のいずれでもありません（実際: ${jsplit}）"
          fi
          if [ -z "$jid" ]; then
            fail "検出条件-形式" "${heading}: 識別子.元 が空です"
          fi
          if [ "${jexamples:-0}" -lt 1 ] 2>/dev/null; then
            fail "検出条件-形式" "${heading}: 例 が空です"
          fi
          if [ "$jsplit" = "一致" ]; then
            local unit_true
            unit_true="$(jq '[.["一致"][]? | select(.["単位"]==true)] | length' <<< "$b")"
            if [ "${unit_true:-0}" -lt 1 ] 2>/dev/null; then
              fail "検出条件-形式" "${heading}: 分割が一致なのに単位:trueの要素がありません"
            fi
          fi

          # 補完（真偽値、省略可）
          if jq -e 'has("補完")' <<< "$b" > /dev/null 2>&1; then
            local jsupp_type
            jsupp_type="$(jq -r '.["補完"] | type' <<< "$b")"
            if [ "$jsupp_type" != "boolean" ]; then
              fail "検出条件-形式" "${heading}: 補完 が真偽値ではありません"
            fi
          fi

          # 除外の一致（配列、省略可。各要素は対象・正規表現・捕捉を持つ）
          if jq -e 'has("除外の一致")' <<< "$b" > /dev/null 2>&1; then
            local jexcl_type jexcl_len
            jexcl_type="$(jq -r '.["除外の一致"] | type' <<< "$b")"
            if [ "$jexcl_type" != "array" ]; then
              fail "検出条件-形式" "${heading}: 除外の一致 が配列ではありません"
            else
              jexcl_len="$(jq '.["除外の一致"] | length' <<< "$b")"
              if [ "${jexcl_len:-0}" -gt 0 ] 2>/dev/null; then
                local ei
                for ei in $(seq 0 $((jexcl_len - 1))); do
                  local etarget eregex ecapture
                  etarget="$(jq -r ".[\"除外の一致\"][$ei][\"対象\"] // empty" <<< "$b")"
                  eregex="$(jq -r ".[\"除外の一致\"][$ei][\"正規表現\"] // empty" <<< "$b")"
                  ecapture="$(jq -r ".[\"除外の一致\"][$ei][\"捕捉\"] // 1" <<< "$b")"
                  if [ -z "$etarget" ] || [ -z "$eregex" ]; then
                    fail "検出条件-形式" "${heading}: 除外の一致 の対象または正規表現が空です"
                  fi
                  if ! [[ "$ecapture" =~ ^[0-9]+$ ]]; then
                    fail "検出条件-形式" "${heading}: 除外の一致 の捕捉が整数ではありません"
                  fi
                done
              fi
            fi
          fi

          if [ -n "$target" ]; then
            local ex
            while IFS= read -r ex; do
              [ -z "$ex" ] && continue
              if [ ! -e "${target}/${ex}" ]; then
                fail "検出条件-例不在" "${heading}: 例が対象配下に実在しません: ${ex}"
              fi
            done < <(jq -r '.["例"][]? // empty' <<< "$b")
            while IFS= read -r ex; do
              [ -z "$ex" ] && continue
              if [ ! -d "${target}/${ex}" ]; then
                fail "検出条件-例不在" "${heading}: 走査.含む が対象配下に実在しません: ${ex}"
              fi
            done < <(jq -r '.["走査"]["含む"][]? // empty' <<< "$b")
          fi
        done
      fi
    fi

    # 取り出しの規則（事実の項目）
    if [ "$mark_value" != "AI の読み取り" ]; then
      local fact_tbl
      fact_tbl="$(awk '
        BEGIN{seen=0}
        /^\| 事実の項目 /{seen=1}
        seen {print}
      ' <<< "$subtext")"
      fact_tbl="$(first_table_text "$fact_tbl")"
      local fact_rows
      fact_rows="$(table_data_rows "$fact_tbl")"
      local -a fact_arr
      IFS=',' read -ra fact_arr <<< "$facts"
      local fitem
      for fitem in "${fact_arr[@]}"; do
        local fmatched=""
        while IFS= read -r r; do
          [ -z "$r" ] && continue
          if [ "$(col "$r" 1)" = "$fitem" ]; then fmatched="$r"; break; fi
        done <<< "$fact_rows"
        if [ -z "$fmatched" ]; then
          fail "取り出し-欠落" "${heading}: 「${fitem}」の行がありません"
          ok4=0
          continue
        fi
        local fv
        fv="$(col "$fmatched" 2)"
        if [ -z "$fv" ] || [ "${fv:0:1}" = "<" ]; then
          fail "取り出し-欠落" "${heading}: 「${fitem}」の元が未記入です"
          ok4=0
        fi
      done
    fi

    [ "$ok4" -eq 1 ] && passck
  done

  # 4.8
  local sub8
  sub8="$(sub4_text "$sec4" "### 4.8 機能のまとめ方")"
  local sub8_trim
  sub8_trim="$(trim "$sub8")"
  if [ -z "$sub8_trim" ] || [ "${sub8_trim:0:1}" = "<" ]; then
    fail "見つけ方-欠落" "4.8 機能のまとめ方 の本文が未記入です"
  else
    passck
  fi

  # 動的定義-形式 (節5)
  local sec5 rows5 ok5
  sec5="$(section_text "$content" "## 5. 動的な定義")"
  rows5="$(table_data_rows "$sec5")"
  ok5=1
  if [ -n "$(trim "$rows5")" ]; then
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      local c1 c2 c3 c4
      c1="$(col "$r" 1)"; c2="$(col "$r" 2)"; c3="$(col "$r" 3)"; c4="$(col "$r" 4)"
      if [ -z "$c1" ] || [ "${c1:0:1}" = "<" ] || [ -z "$c2" ] || [ "${c2:0:1}" = "<" ] || [ -z "$c3" ] || [ "${c3:0:1}" = "<" ] || [ -z "$c4" ]; then
        fail "動的定義-形式" "4列のいずれかが未記入の行があります"
        ok5=0
      fi
    done <<< "$rows5"
  fi
  [ "$ok5" -eq 1 ] && passck

  # 候補数-欠落 (節6)
  local sec6 rows6 ok6
  sec6="$(section_text "$content" "## 6. 候補数")"
  rows6="$(table_data_rows "$sec6")"
  local -a types6=("画面" "接続窓口" "表" "バッチ" "帳票" "外部連携" "機能")
  ok6=1
  local t6
  for t6 in "${types6[@]}"; do
    local m6=""
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      if [ "$(col "$r" 1)" = "$t6" ]; then m6="$r"; break; fi
    done <<< "$rows6"
    if [ -z "$m6" ]; then
      fail "候補数-欠落" "「${t6}」の行がありません"
      ok6=0
      continue
    fi
    local num6
    num6="$(col "$m6" 3)"
    if ! [[ "$num6" =~ ^[0-9]+$ ]]; then
      fail "候補数-欠落" "「${t6}」の概数が0以上の整数ではありません: ${num6}"
      ok6=0
    fi
  done
  [ "$ok6" -eq 1 ] && passck

  # 共通方式-欠落 (節7)
  local sec7 rows7 ok7
  sec7="$(section_text "$content" "## 7. 共通方式の場所")"
  rows7="$(table_data_rows "$sec7")"
  local -a items7=("認証" "権限" "エラー" "ログ" "データアクセス" "設定" "入力検証" "メッセージ" "トランザクション" "排他")
  ok7=1
  local it7
  for it7 in "${items7[@]}"; do
    local m7=""
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      if [ "$(col "$r" 1)" = "$it7" ]; then m7="$r"; break; fi
    done <<< "$rows7"
    if [ -z "$m7" ]; then
      fail "共通方式-欠落" "「${it7}」の行がありません"
      ok7=0
      continue
    fi
    local loc7
    loc7="$(col "$m7" 2)"
    if [ -z "$loc7" ] || [ "${loc7:0:1}" = "<" ]; then
      fail "共通方式-欠落" "「${it7}」の場所が未記入です"
      ok7=0
    elif [ -n "$target" ] && [ "$loc7" != "なし" ]; then
      local missing7
      missing7="$(path_list_missing "$target" "$loc7")"
      if [ -n "$missing7" ]; then
        fail "共通方式-欠落" "「${it7}」の場所が対象配下に実在しません: ${missing7}"
        ok7=0
      fi
    fi
  done
  [ "$ok7" -eq 1 ] && passck

  # 到達範囲-欠落 (節9)
  local sec9 rows9 ok9
  sec9="$(section_text "$content" "## 9. 到達範囲")"
  rows9="$(table_data_rows "$sec9")"
  ok9=1
  local t9
  for t9 in "${types6[@]}"; do
    local m9=""
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      if [ "$(col "$r" 1)" = "$t9" ]; then m9="$r"; break; fi
    done <<< "$rows9"
    if [ -z "$m9" ]; then
      fail "到達範囲-欠落" "「${t9}」の行がありません"
      ok9=0
      continue
    fi
    local ci
    for ci in 2 3 4 5 6; do
      local v9
      v9="$(col "$m9" "$ci")"
      if [ "$ci" -le 5 ]; then
        if [ "$v9" != "機械" ] && [ "$v9" != "AI の読み取り" ] && [ "$v9" != "対象外" ]; then
          fail "到達範囲-欠落" "「${t9}」の列が規定値ではありません: ${v9}"
          ok9=0
        fi
      else
        if [ -z "$v9" ] || [ "${v9:0:1}" = "<" ]; then
          fail "到達範囲-欠落" "「${t9}」の理由が未記入です"
          ok9=0
        fi
      fi
    done
  done
  [ "$ok9" -eq 1 ] && passck

  # 読み-欠落 (節10)
  local sec10 rows10 ok10
  sec10="$(section_text "$content" "## 10. 読みの記録")"
  rows10="$(table_data_rows "$sec10")"
  ok10=1
  if [ -z "$(trim "$rows2")" ]; then
    : # 領域が無ければ検査のしようがない（領域-欠落 側で既に不合格）
  else
    while IFS= read -r r2; do
      [ -z "$r2" ] && continue
      local area
      area="$(col "$r2" 1)"
      local m10=""
      while IFS= read -r r; do
        [ -z "$r" ] && continue
        if [ "$(col "$r" 1)" = "$area" ]; then m10="$r"; break; fi
      done <<< "$rows10"
      if [ -z "$m10" ]; then
        fail "読み-欠落" "「${area}」の行が節10にありません"
        ok10=0
        continue
      fi
      local way10
      way10="$(col "$m10" 4)"
      if [ "$way10" != "全文" ] && [ "$way10" != "要約" ] && [ "$way10" != "未読" ]; then
        fail "読み-欠落" "「${area}」の読み方が規定値ではありません: ${way10}"
        ok10=0
      fi
    done <<< "$rows2"
  fi
  [ "$ok10" -eq 1 ] && passck
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-map-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local self_fail=0
  local self_total=0

  # 見本の対象を作る
  local target="${tmp}/target"
  mkdir -p "${target}/src/screens" "${target}/src/api" "${target}/db" "${target}/batch" "${target}/report" "${target}/external" "${target}/features" "${target}/lib"
  echo "// screen" > "${target}/src/screens/order-list.tsx"
  echo "// api" > "${target}/src/api/order.ts"
  echo "-- table" > "${target}/db/schema.sql"
  echo "# batch" > "${target}/batch/nightly.sh"
  echo "report" > "${target}/report/invoice.rpt"
  echo "// external" > "${target}/external/partner.ts"
  echo "// feature" > "${target}/features/order.ts"
  echo "// auth" > "${target}/lib/auth.ts"
  echo "# README" > "${target}/README.md"
  echo "{}" > "${target}/package.json"

  build_map() {
    local out="$1" with_report_json="$2"
    local report_block=""
    if [ "$with_report_json" = "1" ]; then
      report_block='```json 検出条件
{
  "種別": "report",
  "単位の定義": "帳票1枚を1件とする",
  "走査": { "含む": ["report"], "除く": [], "拡張子": [".rpt"] },
  "一致": [
    { "対象": "ファイル名", "正規表現": ".*\\\\.rpt$" }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "ファイル名", "正規表現": "(.*)\\\\.rpt" },
  "属するファイル": ["report/*.rpt"],
  "分類軸": [{ "名前": "種類", "取り方": "フォルダ名" }],
  "例": ["report/invoice.rpt"]
}
```'
    fi
    local mark_report="通常"
    local extract_report='| 出力条件 | ファイル名の規則 |
| 項目 | 帳票内の見出し行 |
| レイアウトの元 | サンプルファイル |'
    if [ "$with_report_json" != "1" ]; then
      mark_report="AI の読み取り"
      extract_report=""
    fi

    cat > "$out" << MAPEOF2
# 道標

## 0. 対象と時点

| 項目 | 値 |
|---|---|
| 対象 | サンプル対象 |
| ブランチ | main |
| コミット | abc1234 |
| 作成日 | 2026-09-03 |
| 文字コード | UTF-8 |
| 構成の形 | 単一 |

## 1. 調査

| 項目 | 値 | 場所 |
|---|---|---|
| 言語と版 | TypeScript 5 | package.json |
| フレームワークと版 | React 18 | package.json |
| 実行環境の前提 | Node 20 | package.json |
| フォルダ構造 | src配下に画面とAPI | README.md |
| 層構造 | 画面/API/データの3層 | README.md |
| 入口 | src/index.tsx | README.md |
| 外部接続 | なし | なし |
| データの保存先 | db配下のSQL | db/schema.sql |
| ミドルウェア | なし | なし |
| 依存の定義 | package.json | package.json |
| ビルド・起動・テストの定義 | package.json | package.json |
| 環境の値の定義 | package.json | package.json |
| テストの枠組みと場所 | 記載なしのため package.json | package.json |
| UI 共通部品 | なし | なし |
| 共通と単位固有の境界 | libが共通 | lib/auth.ts |

## 2. 領域

| 領域 | 対応するフォルダ | 役割 | 規模（ファイル数） | 読む順 |
|---|---|---|---|---|
| 画面領域 | src/screens | 画面 | 1 | 1 |
| 接続窓口領域 | src/api | API | 1 | 2 |
| データ領域 | db | 表 | 1 | 3 |
| バッチ領域 | batch | バッチ | 1 | 4 |
| 帳票領域 | report | 帳票 | 1 | 5 |
| 外部連携領域 | external | 外部連携 | 1 | 6 |
| 機能領域 | features | 機能 | 1 | 7 |

## 3. 除外

| フォルダ | 種類 | 理由 |
|---|---|---|
| node_modules | ベンダー | 依存パッケージのため |

## 4. 単位の見つけ方

### 4.1 画面

| 項目 | 内容 |
|---|---|
| 単位の定義 | 画面ファイル1つを1画面とする |
| 走査の範囲 | src/screens配下 |
| 目印 | ファイル名がscreenで終わる |
| 分割の規則 | 1ファイル1画面 |
| 識別子の付け方 | ファイルパス |
| 名前の取り方 | ファイル名の先頭部分 |
| 説明の取り方 | 先頭コメント |
| 属するファイル | 同名の.tsxファイル |
| 分類軸の取り方 | フォルダ名 |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "screen",
  "単位の定義": "画面ファイル1つを1画面とする",
  "走査": { "含む": ["src/screens"], "除く": [], "拡張子": [".tsx"] },
  "一致": [
    { "対象": "ファイル名", "正規表現": ".*\\\\.tsx$" }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "ファイル名", "正規表現": "(.*)\\\\.tsx" },
  "属するファイル": ["src/screens/*.tsx"],
  "分類軸": [{ "名前": "種類", "取り方": "フォルダ名" }],
  "例": ["src/screens/order-list.tsx"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | input要素 |
| 表示項目 | JSXの表示部 |
| 操作 | onClick等のハンドラ |
| 遷移 | ルーティング定義 |
| 呼ぶ接続窓口 | fetch呼び出し |

### 4.2 接続窓口

| 項目 | 内容 |
|---|---|
| 単位の定義 | エンドポイント1つを1接続窓口とする |
| 走査の範囲 | src/api配下 |
| 目印 | エクスポートされた関数 |
| 分割の規則 | 1関数1接続窓口 |
| 識別子の付け方 | 関数名 |
| 名前の取り方 | 関数名 |
| 説明の取り方 | 先頭コメント |
| 属するファイル | 同名の.tsファイル |
| 分類軸の取り方 | HTTPメソッド |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "api",
  "単位の定義": "エンドポイント1つを1接続窓口とする",
  "走査": { "含む": ["src/api"], "除く": [], "拡張子": [".ts"] },
  "一致": [
    { "対象": "内容", "正規表現": "export function", "単位": true }
  ],
  "分割": "一致",
  "識別子": { "元": "関数名" },
  "名前": { "元": "内容", "正規表現": "export function (\\\\w+)" },
  "属するファイル": ["src/api/*.ts"],
  "分類軸": [{ "名前": "メソッド", "取り方": "デコレータ" }],
  "例": ["src/api/order.ts"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 経路 | ルート定義 |
| 入力 | 引数の型 |
| 出力 | 戻り値の型 |
| 検証 | バリデーション関数 |
| 呼ぶ処理 | サービス層の呼び出し |
| 触る表 | ORMのクエリ |

### 4.3 表

| 項目 | 内容 |
|---|---|
| 単位の定義 | CREATE TABLE1つを1表とする |
| 走査の範囲 | db配下 |
| 目印 | CREATE TABLE文 |
| 分割の規則 | 1文1表 |
| 識別子の付け方 | テーブル名 |
| 名前の取り方 | テーブル名 |
| 説明の取り方 | 直前コメント |
| 属するファイル | schema.sql |
| 分類軸の取り方 | スキーマ名 |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "table",
  "単位の定義": "CREATE TABLE1つを1表とする",
  "走査": { "含む": ["db"], "除く": [], "拡張子": [".sql"] },
  "一致": [
    { "対象": "内容", "正規表現": "CREATE TABLE", "単位": true }
  ],
  "分割": "一致",
  "識別子": { "元": "テーブル名" },
  "名前": { "元": "内容", "正規表現": "CREATE TABLE (\\\\w+)" },
  "属するファイル": ["db/schema.sql"],
  "分類軸": [{ "名前": "種類", "取り方": "先頭コメント" }],
  "例": ["db/schema.sql"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 列 | CREATE TABLE内の列定義 |
| 型 | 列定義の型 |
| 制約 | NOT NULL等の制約句 |
| 関係 | FOREIGN KEY句 |

### 4.4 バッチ

| 項目 | 内容 |
|---|---|
| 単位の定義 | シェルスクリプト1つを1バッチとする |
| 走査の範囲 | batch配下 |
| 目印 | 拡張子.sh |
| 分割の規則 | 1ファイル1バッチ |
| 識別子の付け方 | ファイルパス |
| 名前の取り方 | ファイル名 |
| 説明の取り方 | 先頭コメント |
| 属するファイル | 同ファイル |
| 分類軸の取り方 | フォルダ名 |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "batch",
  "単位の定義": "シェルスクリプト1つを1バッチとする",
  "走査": { "含む": ["batch"], "除く": [], "拡張子": [".sh"] },
  "一致": [
    { "対象": "ファイル名", "正規表現": ".*\\\\.sh$" }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "ファイル名", "正規表現": "(.*)\\\\.sh" },
  "属するファイル": ["batch/*.sh"],
  "分類軸": [{ "名前": "種類", "取り方": "フォルダ名" }],
  "例": ["batch/nightly.sh"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 起動条件 | cron定義 |
| 入力 | 引数 |
| 出力 | ログファイル |
| 処理の流れ | スクリプト本文 |

### 4.5 帳票

| 項目 | 内容 |
|---|---|
| 単位の定義 | 帳票ファイル1つを1帳票とする |
| 走査の範囲 | report配下 |
| 目印 | ${mark_report} |
| 分割の規則 | 1ファイル1帳票 |
| 識別子の付け方 | ファイルパス |
| 名前の取り方 | ファイル名 |
| 説明の取り方 | 先頭行 |
| 属するファイル | 同ファイル |
| 分類軸の取り方 | フォルダ名 |
| 動的な定義の扱い | なし |

${report_block}

${extract_report:+| 事実の項目 | どの構文・記述から取るか |
|---|---|
${extract_report}
}
### 4.6 外部連携

| 項目 | 内容 |
|---|---|
| 単位の定義 | 連携ファイル1つを1外部連携とする |
| 走査の範囲 | external配下 |
| 目印 | ファイル名がpartnerを含む |
| 分割の規則 | 1ファイル1連携 |
| 識別子の付け方 | ファイルパス |
| 名前の取り方 | ファイル名 |
| 説明の取り方 | 先頭コメント |
| 属するファイル | 同ファイル |
| 分類軸の取り方 | フォルダ名 |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "external",
  "単位の定義": "連携ファイル1つを1外部連携とする",
  "走査": { "含む": ["external"], "除く": [], "拡張子": [".ts"] },
  "一致": [
    { "対象": "ファイル名", "正規表現": ".*\\\\.ts$" }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "ファイル名", "正規表現": "(.*)\\\\.ts" },
  "属するファイル": ["external/*.ts"],
  "分類軸": [{ "名前": "種類", "取り方": "フォルダ名" }],
  "例": ["external/partner.ts"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 相手先 | 接続先URL定数 |
| 形式 | 通信のプロトコル |
| 項目 | 送受信データの型 |
| 応答 | レスポンスの型 |
| 再試行 | リトライ設定 |

### 4.7 機能

| 項目 | 内容 |
|---|---|
| 単位の定義 | 機能ファイル1つを1機能とする |
| 走査の範囲 | features配下 |
| 目印 | ファイル名 |
| 分割の規則 | 1ファイル1機能 |
| 識別子の付け方 | ファイルパス |
| 名前の取り方 | ファイル名 |
| 説明の取り方 | 先頭コメント |
| 属するファイル | 同ファイル |
| 分類軸の取り方 | フォルダ名 |
| 動的な定義の扱い | なし |

\`\`\`json 検出条件
{
  "種別": "feature",
  "単位の定義": "機能ファイル1つを1機能とする",
  "走査": { "含む": ["features"], "除く": [], "拡張子": [".ts"] },
  "一致": [
    { "対象": "ファイル名", "正規表現": ".*\\\\.ts$" }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "ファイル名", "正規表現": "(.*)\\\\.ts" },
  "属するファイル": ["features/*.ts"],
  "分類軸の取り方": "フォルダ名",
  "分類軸": [{ "名前": "種類", "取り方": "フォルダ名" }],
  "例": ["features/order.ts"]
}
\`\`\`

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 含む単位 | importされる画面・接続窓口 |

### 4.8 機能のまとめ方

画面と接続窓口を、同じ業務目的でまとめて1機能とする。

## 5. 動的な定義

| 定義の場所 | 種別 | 見つけ方 | 環境の制約 |
|---|---|---|---|

## 6. 候補数

| 種別 | 領域 | 概数 | 数え方 |
|---|---|---|---|
| 画面 | 画面領域 | 1 | ファイル数 |
| 接続窓口 | 接続窓口領域 | 1 | 関数数 |
| 表 | データ領域 | 1 | CREATE TABLE数 |
| バッチ | バッチ領域 | 1 | ファイル数 |
| 帳票 | 帳票領域 | 1 | ファイル数 |
| 外部連携 | 外部連携領域 | 1 | ファイル数 |
| 機能 | 機能領域 | 1 | ファイル数 |

## 7. 共通方式の場所

| 方式 | 実装の場所 |
|---|---|
| 認証 | lib/auth.ts |
| 権限 | lib/auth.ts |
| エラー | なし |
| ログ | なし |
| データアクセス | db/schema.sql |
| 設定 | package.json |
| 入力検証 | なし |
| メッセージ | なし |
| トランザクション | なし |
| 排他 | なし |

## 8. 用語の候補

| コードの名前 | 業務の言葉 | 出典 |
|---|---|---|
| order | 注文 | src/api/order.ts |

## 9. 到達範囲

| 種別 | 一覧化 | 事実の取り出し | 基本設計 | 詳細設計 | 理由 |
|---|---|---|---|---|---|
| 画面 | 機械 | 機械 | 機械 | AI の読み取り | 詳細設計は文言が多く機械化していない |
| 接続窓口 | 機械 | 機械 | 機械 | 機械 | すべて検出条件で表現できる |
| 表 | 機械 | 機械 | 機械 | 機械 | すべて検出条件で表現できる |
| バッチ | 機械 | 機械 | 機械 | 機械 | すべて検出条件で表現できる |
| 帳票 | AI の読み取り | AI の読み取り | AI の読み取り | 対象外 | レイアウトは目視でしか判断できない |
| 外部連携 | 機械 | 機械 | 機械 | 機械 | すべて検出条件で表現できる |
| 機能 | 機械 | AI の読み取り | AI の読み取り | 対象外 | まとめ方が業務判断のため |

## 10. 読みの記録

| 領域 | フォルダ | ファイル数 | 読み方 | 根拠 |
|---|---|---|---|---|
| 画面領域 | src/screens | 1 | 全文 | ファイル数が少ないため |
| 接続窓口領域 | src/api | 1 | 全文 | ファイル数が少ないため |
| データ領域 | db | 1 | 全文 | ファイル数が少ないため |
| バッチ領域 | batch | 1 | 全文 | ファイル数が少ないため |
| 帳票領域 | report | 1 | 全文 | ファイル数が少ないため |
| 外部連携領域 | external | 1 | 全文 | ファイル数が少ないため |
| 機能領域 | features | 1 | 全文 | ファイル数が少ないため |
MAPEOF2
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
  local map_ok="${tmp}/map-ok.md"
  build_map "$map_ok" "1"
  assert_exit "合格-完成形" 0 bash "$0" "$map_ok" --target "$target"

  # 合格-AI の読み取り
  local map_ai="${tmp}/map-ai.md"
  build_map "$map_ai" "0"
  assert_exit "合格-AI の読み取り" 0 bash "$0" "$map_ai" --target "$target"

  # 不合格-様式のまま
  local tmpl="${tmp}/../../../templates/道標.md"
  local self_dir
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  local template_file="${self_dir}/../templates/道標.md"
  assert_exit "不合格-様式のまま" 1 bash "$0" "$template_file"
  assert_contains "不合格-様式のまま: 対象-欠落が出る" "対象-欠落"
  assert_contains "不合格-様式のまま: 調査-欠落が出る" "調査-欠落"

  # 不合格-節の欠落
  local map_missing_section="${tmp}/map-missing-section.md"
  build_map "$map_missing_section" "1"
  awk '/^## 10\. 読みの記録$/{skip=1} !skip{print}' "$map_missing_section" > "${map_missing_section}.tmp"
  mv "${map_missing_section}.tmp" "$map_missing_section"
  assert_exit "不合格-節の欠落" 1 bash "$0" "$map_missing_section" --target "$target"
  assert_contains "不合格-節の欠落: 節-構成が出る" "節-構成"

  # 不合格-検出条件の形式
  local map_bad_json="${tmp}/map-bad-json.md"
  build_map "$map_bad_json" "1"
  sed -i.bak 's/"分割": "ファイル",/"分割": "そのた",/' "$map_bad_json"
  assert_exit "不合格-検出条件の形式" 1 bash "$0" "$map_bad_json" --target "$target"
  assert_contains "不合格-検出条件の形式: 検出条件-形式が出る" "検出条件-形式"

  # 不合格-例の不在
  local map_bad_example="${tmp}/map-bad-example.md"
  build_map "$map_bad_example" "1"
  sed -i.bak 's#"例": \["src/screens/order-list.tsx"\]#"例": ["src/screens/does-not-exist.tsx"]#' "$map_bad_example"
  assert_exit "不合格-例の不在" 1 bash "$0" "$map_bad_example" --target "$target"
  assert_contains "不合格-例の不在: 検出条件-例不在が出る" "検出条件-例不在"

  # 不合格-到達範囲の値
  local map_bad_reach="${tmp}/map-bad-reach.md"
  build_map "$map_bad_reach" "1"
  sed -i.bak 's/| 画面 | 機械 | 機械 | 機械 | AI の読み取り | 詳細設計は文言が多く機械化していない |/| 画面 | 機械 | 機械 | 機械 | 未定 | 詳細設計は文言が多く機械化していない |/' "$map_bad_reach"
  assert_exit "不合格-到達範囲の値" 1 bash "$0" "$map_bad_reach" --target "$target"
  assert_contains "不合格-到達範囲の値: 到達範囲-欠落が出る" "到達範囲-欠落"

  # 合格-複数パス
  local map_multi="${tmp}/map-multi-path.md"
  build_map "$map_multi" "1"
  sed -i.bak 's#| 認証 | lib/auth.ts |#| 認証 | lib/auth.ts;README.md |#' "$map_multi"
  assert_exit "合格-複数パス" 0 bash "$0" "$map_multi" --target "$target"

  # 合格-補完と除外の一致
  local map_supplement="${tmp}/map-supplement.md"
  awk '{print} /"種別": "screen",/{print "  \"補完\": false,"; print "  \"除外の一致\": [{ \"対象\": \"内容\", \"正規表現\": \"DROP TABLE ([a-z_]+)\", \"捕捉\": 1 }],"}' "$map_ok" > "$map_supplement"
  assert_exit "合格-補完と除外の一致" 0 bash "$0" "$map_supplement" --target "$target"

  # 不合格-除外の一致の形式
  local map_bad_exclude="${tmp}/map-bad-exclude.md"
  awk '{print} /"種別": "screen",/{print "  \"除外の一致\": [{ \"対象\": \"内容\", \"捕捉\": \"abc\" }],"}' "$map_ok" > "$map_bad_exclude"
  assert_exit "不合格-除外の一致の形式" 1 bash "$0" "$map_bad_exclude" --target "$target"
  assert_contains "不合格-除外の一致の形式: 検出条件-形式が出る" "検出条件-形式"

  # 合格-文字コード種別
  local map_sjis="${tmp}/map-sjis.md"
  build_map "$map_sjis" "1"
  sed -i.bak 's/| 文字コード | UTF-8 |/| 文字コード | Shift_JIS |/' "$map_sjis"
  assert_exit "合格-文字コード種別" 0 bash "$0" "$map_sjis" --target "$target"

  # 不合格-文字コード種別
  local map_bad_charset="${tmp}/map-bad-charset.md"
  build_map "$map_bad_charset" "1"
  sed -i.bak 's/| 文字コード | UTF-8 |/| 文字コード | 謎の文字コード |/' "$map_bad_charset"
  assert_exit "不合格-文字コード種別" 1 bash "$0" "$map_bad_charset" --target "$target"
  assert_contains "不合格-文字コード種別: 文字コード-形式が出る" "文字コード-形式"

  # 使い方-ファイル不在
  assert_exit "使い方-ファイル不在" 2 bash "$0" "${tmp}/no-such-file.md"

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

FILE=""
TARGET=""
MAXLINES=200

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --max-lines)
      MAXLINES="${2:-200}"
      shift 2
      ;;
    -*)
      echo "使い方: check-map.sh <道標.md> [--target <対象リポジトリのルート>] [--max-lines <N>]" >&2
      exit 2
      ;;
    *)
      if [ -z "$FILE" ]; then
        FILE="$1"
      else
        echo "余分な引数です: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$FILE" ]; then
  echo "使い方: check-map.sh <道標.md> [--target <対象リポジトリのルート>] [--max-lines <N>]" >&2
  exit 2
fi

if [ ! -f "$FILE" ]; then
  echo "ファイルが見つかりません: $FILE" >&2
  exit 2
fi

check_map "$FILE" "$TARGET"

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
