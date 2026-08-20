#!/bin/bash
# 指示書形式規約（.claude/rules/always/tasks/instruction-format/rule.md）の検査スクリプト。
# docs/tasks/ 直下と docs/tasks/design/ 配下の指示書が「必須の8節」「冒頭の4行」
# 「状態・優先度の値」「完了の判定の番号付き条件」「対応の記録の状態語」
# 「決めていないことの既定」「判断待ちの見出し禁止」「置き場と状態の一致」
# 「元の指摘の形式」を満たすかを検査する。
#
# 使い方:
#   check-instruction-format.sh                対象一覧を出して全件検査する
#   check-instruction-format.sh <ファイル>      1件だけ検査する
#   check-instruction-format.sh --self-test    スクリプト自身の検査
#   check-instruction-format.sh --decisions    docs/tasks/ 全体の「判断の記録」を集めて表示する（合否は判定しない）
set -euo pipefail

REQUIRED_HEADINGS=(
  "この指示書は何か"
  "なぜ必要か"
  "やること"
  "完了の判定"
  "触らない範囲"
  "決めていないこと"
  "他の指示書との関係"
  "この指示書の位置づけ"
)

STATE_VALUES=("着手できる" "設計から始める")
PRIORITY_VALUES=("最高" "高" "中" "低")
RECORD_STATE_VALUES=("未着手" "対応中" "完了" "対象外" "未確認")

declare -a REASONS=()

# コード柵（``` または ~~~ で始まる行）に挟まれた範囲を空行へ置き換えて標準出力へ出す。
# 行番号がずれないよう、行は消さず空文字へ置き換える。
# 柵が閉じないままファイルが終わった場合は、開いた位置から末尾までを柵の中として扱う。
# LC_ALL=C: 他の awk 呼び出しと同じく、多バイト文字列比較の不具合を避けるため。
strip_fences() {
  local file="$1"
  LC_ALL=C awk '
    BEGIN { infence = 0 }
    /^[ ]{0,3}(```|~~~)/ {
      if (infence == 0) { infence = 1 } else { infence = 0 }
      print ""
      next
    }
    {
      if (infence == 1) { print "" } else { print }
    }
  ' "$file"
}

# 見出し・完了の判定・対応の記録の検査（検査1・検査5・検査6）が読む、柵を落とした
# 一時ファイルを用意する。呼び出しのたびに mktemp で新規作成せず同じパスを使い回し、
# スクリプト終了時に trap で一度だけ消す。
STRIPPED_TMP=""
# mktemp が失敗した場合（サンドボックス等で一時領域へ書けない場合）に立てるフラグ。
# このフラグが立つと run_main は各ファイルの合否を判定せず、判定不能として終了する。
MKTEMP_FAILED=0
ensure_stripped_tmp() {
  if [ -z "$STRIPPED_TMP" ]; then
    if ! STRIPPED_TMP="$(mktemp 2>/dev/null)" || [ -z "$STRIPPED_TMP" ]; then
      MKTEMP_FAILED=1
      STRIPPED_TMP=""
      return 1
    fi
    trap 'rm -f "$STRIPPED_TMP"' EXIT
  fi
  return 0
}

contains() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    if [ "$x" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

join_by() {
  local d="$1"
  shift
  local first=1
  local r=""
  local x
  for x in "$@"; do
    if [ "$first" -eq 1 ]; then
      r="$x"
      first=0
    else
      r="${r}${d}${x}"
    fi
  done
  printf '%s' "$r"
}

# ファイル内の "## " 見出し一覧を "行番号<TAB>見出しテキスト" で返す。
# 番号プレフィックス（"3. " 等）は除去する。"### " 以下の下位見出しは対象外。
list_headings() {
  local file="$1"
  grep -n '^## ' "$file" 2>/dev/null | sed -E 's/^([0-9]+):## +([0-9]+\. )?/\1\t/; s/[[:space:]]+$//'
}

# $1=file $2=見出しテキスト（完全一致） -> 一致する見出しの行番号（最初の1件）
# LC_ALL=C: macOS標準awkは多バイト文字列の "==" 比較を数値コンテキストへ引き込み、
# 非数値文字列同士を 0==0 として常に真にしてしまう不具合を持つ。Cロケールで回避する。
heading_line() {
  local file="$1" target="$2"
  list_headings "$file" | LC_ALL=C awk -F'\t' -v t="$target" '$2==t {print $1; exit}'
}

# $1=file $2=開始行番号 -> 次の "## " 見出しの直前の行番号（無ければファイル末尾行）
section_range() {
  local file="$1" start="$2"
  local total
  total=$(wc -l < "$file" | tr -d '[:space:]')
  local end
  end=$(list_headings "$file" | LC_ALL=C awk -F'\t' -v s="$start" '$1>s {print $1; exit}')
  if [ -z "${end:-}" ]; then
    echo "$total"
  else
    echo $((end - 1))
  fi
}

# $1=file $2=見出しテキスト -> 見出し直後から次の見出し直前までの本文を出力する。
# 見出しが見つからない場合は戻り値1。
section_body() {
  local file="$1" heading="$2"
  local start
  start=$(heading_line "$file" "$heading")
  if [ -z "$start" ]; then
    return 1
  fi
  local end
  end=$(section_range "$file" "$start")
  sed -n "$((start + 1)),${end}p" "$file"
}

# 標準入力の表（Markdownテーブル）を走査し、"状態" 列を持つ表の各データ行から
# 状態の値を1行ずつ出力する。空行・見出し行で表の追跡をリセットする。
# LC_ALL=C: heading_line と同じ多バイト文字列 "==" 比較の不具合を回避する。
#
# 実装判断: セル内の `\|`（Markdownでリテラルのパイプ文字を書く標準表記。
# 「確かめる手段」の欄にシェルのパイプ演算子を含むコマンドを書く際に使われる）
# は表の区切りではないため、split前に一時退避してから "|" だけで split する。
# 退避しないと、そのセルを含む行だけ列数が1つ増え、以降の列（状態・コミット・
# 確かめた内容）が右にずれる。状態の列位置は見出し行から動的に求めており
# （state_col）これ自体は元から正しいが、データ行側の列数がずれると同じ
# state_col を指しても違う値を指してしまう。
# 実測: 「片付き判定に実測の段階を足す指示書.md」の判定7・8行で発生を確認
# （2026-08-18、check-instruction-format.sh --self-test への追加ケースで再現）。
# 環境依存: 無し。retry不要。
parse_record_states() {
  LC_ALL=C awk '
    BEGIN { state_col = -1 }
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    {
      line = $0
      if (line ~ /^[ \t]*$/ || line ~ /^#/) { state_col = -1; next }
      if (line !~ /^\|/) { next }
      protected_line = line
      gsub(/\\[|]/, "@@ESCPIPE@@", protected_line)
      n = split(protected_line, cols, "|")
      for (i = 1; i <= n; i++) {
        cols[i] = trim(cols[i])
        gsub(/@@ESCPIPE@@/, "\\|", cols[i])
      }
      is_sep = 1
      for (i = 2; i < n; i++) { if (cols[i] !~ /^-+$/) { is_sep = 0; break } }
      if (is_sep) next
      if (state_col < 0) {
        for (i = 2; i < n; i++) { if (cols[i] == "状態") { state_col = i; break } }
        next
      }
      print cols[state_col]
    }
  '
}

# 標準入力の表（Markdownテーブル）を走査し、「確かめる手段」列と「確かめた内容」列を持つ表の
# 各データ行から「手段<TAB>理由」を1行ずつ出力する。空行・見出し行で表の追跡をリセットする。
# セル内の `\|` の扱い・LC_ALL=C の理由は parse_record_states と同じ。
parse_record_method_reason() {
  LC_ALL=C awk '
    BEGIN { method_col = -1; reason_col = -1 }
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    {
      line = $0
      if (line ~ /^[ \t]*$/ || line ~ /^#/) { method_col = -1; reason_col = -1; next }
      if (line !~ /^\|/) { next }
      protected_line = line
      gsub(/\\[|]/, "@@ESCPIPE@@", protected_line)
      n = split(protected_line, cols, "|")
      for (i = 1; i <= n; i++) {
        cols[i] = trim(cols[i])
        gsub(/@@ESCPIPE@@/, "\\|", cols[i])
      }
      is_sep = 1
      for (i = 2; i < n; i++) { if (cols[i] !~ /^-+$/) { is_sep = 0; break } }
      if (is_sep) next
      if (method_col < 0 && reason_col < 0) {
        for (i = 2; i < n; i++) {
          if (cols[i] == "確かめる手段") { method_col = i }
          if (cols[i] == "確かめた内容") { reason_col = i }
        }
        next
      }
      if (method_col > 0 && reason_col > 0) {
        print cols[method_col] "\t" cols[reason_col]
      }
    }
  '
}

# $1=「対応の記録」節の本文 -> 「確かめる手段」が目視の行に「確かめた内容」の
# 理由が書かれているかを判定する。理由なし=1、理由あり（または目視の行が無い）=0。
# validate_file（検査11）と validate_mihari_only（docs/tasks/done/ 専用。
# rule.md 項目10）の両方から呼ばれる、判定の中身を持つ唯一の実装。
check_mihari_reason_in_record_body() {
  local record_body="$1"
  local mr_lines
  mr_lines="$(printf '%s\n' "$record_body" | parse_record_method_reason)"
  local mihari_bad=0
  local method reason method_clean reason_trim
  while IFS=$'\t' read -r method reason; do
    [ -z "$method" ] && continue
    method_clean="$(printf '%s' "$method" | sed -E 's/^`//; s/`$//')"
    if [ "$method_clean" = "目視" ]; then
      reason_trim="$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      case "$reason_trim" in
        ""|"—"|"ー"|"-")
          mihari_bad=1 ;;
      esac
    fi
  done <<< "$mr_lines"
  if [ "$mihari_bad" -eq 1 ]; then
    return 1
  fi
  return 0
}

# $1=file を検査し、「対応の記録」節の目視理由（検査11相当）だけを判定する。
# 他の検査（必須の8節・冒頭3行・状態語等）は行わない。
# docs/tasks/done/ 配下（片付いた指示書。他の検査の対象外）に使う専用の入口。
# rule.md 項目10「目視の理由の検査だけは docs/tasks/done/ も走査する」に対応する。
# 戻り値: 合格なら0、不合格なら1。不合格理由はグローバル配列 REASONS に積む。
validate_mihari_only() {
  local file="$1"
  REASONS=()

  ensure_stripped_tmp
  strip_fences "$file" > "$STRIPPED_TMP"
  local stripped="$STRIPPED_TMP"

  local record_body
  if record_body="$(section_body "$stripped" "対応の記録")"; then
    if ! check_mihari_reason_in_record_body "$record_body"; then
      REASONS+=("検査11 目視の理由（$(basename "$file")）: 確かめる手段が目視の行に、確かめた内容の理由が書かれていない")
    fi
  fi

  if [ "${#REASONS[@]}" -gt 0 ]; then
    return 1
  fi
  return 0
}

# $1=行（表の1行）-> 既定の語を含む列の1始まりの列番号を出力する。見つからなければ何も出力しない。
kimeteinai_default_col() {
  local header="$1"
  printf '%s' "$header" | LC_ALL=C awk -F'|' '{
    for (i = 1; i <= NF; i++) {
      v = $i
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v ~ /既定/) { print i; exit }
    }
  }'
}

# $1=行（表の1行） $2=列番号(1始まり) -> その列の値（前後の空白を除く）を出力する。
kimeteinai_col_value() {
  local row="$1" col="$2"
  printf '%s' "$row" | LC_ALL=C awk -F'|' -v c="$col" '{
    v = $c
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    print v
  }'
}

# $1=既定の欄の値 -> 0=ユーザーの判断への委譲・空欄相当、1=そうでない
#
# 群A（部分一致）: ユーザーの返事を待つことそのものを指す語。中身に関わらず不可。
# 群B（完全一致）: 前後の空白と末尾の句点「。」「.」を取り除いた結果が欄の値の全体と
#                   一致する場合だけ不可。「決めない。かわりに…」のように具体が続く既定は
#                   完全一致しないため可とする。群Aを先に判定し、当たれば群Bを見ない。
kimeteinai_default_is_delegated() {
  local v="$1"
  case "$v" in
    *ユーザーの判断*|*ユーザー判断*|*判断を仰ぐ*|*ユーザーに確認*|*ユーザーへ確認*|*ユーザーに尋ね*|*ユーザーへ尋ね*|*指示待ち*)
      return 0 ;;
  esac
  local trimmed
  trimmed="$(printf '%s' "$v" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[。.]+$//')"
  case "$trimmed" in
    ""|"—"|"ー"|"-"|"決めない"|"決めていない"|"未定"|"保留"|"要相談")
      return 0 ;;
  esac
  return 1
}

# $1=body（「決めていないこと」節の中身）
# -> 0=既定つき表（データ行が委譲・空欄でない）または「なし」の1行
#    1=既定つき表も「なし」の1行も見つからない
#    2=既定つき表はあるが、既定の欄がユーザーの判断への委譲・空欄相当になっている
# 形A: 表の見出し行（直後の行が |--- 形の区切り行）に「既定」の語を含む
# 形B: 中身が実質1行で、前後の空白・句点を除くと「なし」だけになる
kimeteinai_ok() {
  local body="$1"
  local -a all_lines=()
  local line
  while IFS= read -r line; do
    all_lines+=("$line")
  done <<< "$body"

  # 形B: 実質1行で「なし」だけ
  local -a nonblank=()
  for line in "${all_lines[@]}"; do
    if [[ "$line" =~ [^[:space:]] ]]; then
      nonblank+=("$line")
    fi
  done
  if [ "${#nonblank[@]}" -eq 1 ]; then
    local only
    only="$(printf '%s' "${nonblank[0]}" | sed -E 's/^[[:space:]。、.]+//; s/[[:space:]。、.]+$//')"
    if [ "$only" = "なし" ]; then
      return 0
    fi
  fi

  # 形A: 既定の語を含む見出し行を持つ表
  local total="${#all_lines[@]}"
  local i
  local header_idx=-1
  for ((i = 0; i < total - 1; i++)); do
    local cur="${all_lines[$i]}"
    local nxt="${all_lines[$((i + 1))]}"
    if [[ "$cur" == *"|"* ]] && [[ "$nxt" =~ ^[[:space:]\|:-]+$ ]] && [[ "$nxt" == *-* ]]; then
      if [[ "$cur" == *"既定"* ]]; then
        header_idx=$i
        break
      fi
    fi
  done

  if [ "$header_idx" -lt 0 ]; then
    return 1
  fi

  # 既定の列を特定し、データ行を走査する
  local default_col
  default_col="$(kimeteinai_default_col "${all_lines[$header_idx]}")"
  if [ -z "$default_col" ]; then
    return 0
  fi

  local sep_idx=$((header_idx + 1))
  local data_idx
  for ((data_idx = sep_idx + 1; data_idx < total; data_idx++)); do
    local row="${all_lines[$data_idx]}"
    if [[ ! "$row" =~ ^[[:space:]]*\| ]]; then
      break
    fi
    local val
    val="$(kimeteinai_col_value "$row" "$default_col")"
    if kimeteinai_default_is_delegated "$val"; then
      return 2
    fi
  done

  return 0
}

# 標準入力の表（Markdownテーブル）から、見出し行と区切り行を除いたデータ行を出力する。
# 「判断の記録」節から --decisions が使う。
parse_decision_rows() {
  LC_ALL=C awk '
    BEGIN { header_seen = 0; sep_seen = 0 }
    /^[ \t]*$/ { next }
    !/^\|/ { next }
    {
      if (!header_seen) { header_seen = 1; next }
      if (!sep_seen) {
        sep_seen = 1
        line = $0
        n = split(line, cols, "|")
        is_sep = 1
        for (i = 2; i < n; i++) {
          c = cols[i]
          gsub(/^[ \t]+|[ \t]+$/, "", c)
          if (c !~ /^:?-+:?$/) { is_sep = 0; break }
        }
        if (is_sep) next
      }
      print
    }
  '
}

# $1=file を検査し、不合格理由をグローバル配列 REASONS に積む。
# 戻り値: 合格なら0、不合格なら1。
validate_file() {
  local file="$1"
  REASONS=()

  # 検査1・検査5・検査6が読む、コード柵を落とした本文。
  ensure_stripped_tmp
  strip_fences "$file" > "$STRIPPED_TMP"
  local stripped="$STRIPPED_TMP"

  # 検査1: 必須の8節
  local headings_text
  headings_text="$(list_headings "$stripped" | cut -f2)"
  local missing=()
  local h
  for h in "${REQUIRED_HEADINGS[@]}"; do
    if ! grep -qxF "$h" <<< "$headings_text"; then
      missing+=("$h")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    REASONS+=("検査1 必須の節: 欠落 ${#missing[@]} 件（$(join_by ' / ' "${missing[@]}")）")
  fi

  # 検査2: 冒頭4行（状態・優先度・前提・元の指摘）
  local head20
  head20="$(head -20 "$file")"
  local missing_prefix=()
  grep -qF '**状態**:' <<< "$head20" || missing_prefix+=("状態")
  grep -qF '**優先度**:' <<< "$head20" || missing_prefix+=("優先度")
  grep -qF '**前提**:' <<< "$head20" || missing_prefix+=("前提")
  grep -qF '**元の指摘**:' <<< "$head20" || missing_prefix+=("元の指摘")
  if [ "${#missing_prefix[@]}" -gt 0 ]; then
    REASONS+=("検査2 冒頭4行: 欠落 ${#missing_prefix[@]} 件（$(join_by ' / ' "${missing_prefix[@]}")）")
  fi

  # 検査12: 元の指摘の値の形式
  # 「なし」、または「1-NN」をカンマ区切りで並べたもの（件数に上限は無い）のいずれか。
  local claim_val
  claim_val="$(grep -m1 -F '**元の指摘**:' "$file" | sed -E 's/^\*\*元の指摘\*\*:[[:space:]]*//; s/[[:space:]]+$//' || true)"
  if [ -n "$claim_val" ] && [ "$claim_val" != "なし" ]; then
    if ! [[ "$claim_val" =~ ^1-[0-9]+([[:space:]]*,[[:space:]]*1-[0-9]+)*$ ]]; then
      REASONS+=("検査12 元の指摘の値: 「${claim_val}」は「なし」または「1-NN」のカンマ区切りに限る")
    fi
  fi

  # 検査3: 状態の値
  local state_val
  state_val="$(grep -m1 -F '**状態**:' "$file" | sed -E 's/^\*\*状態\*\*:[[:space:]]*//; s/[[:space:]]+$//' || true)"
  if [ -n "$state_val" ]; then
    if [ "$state_val" = "決定を待つ" ]; then
      REASONS+=("検査3 状態の値: 「決定を待つ」は廃止された。判断が要る事項は「決めていないこと」へ既定つきで書く")
    elif ! contains "$state_val" "${STATE_VALUES[@]}"; then
      REASONS+=("検査3 状態の値: 「${state_val}」は定めた 3 つに無い")
    fi
  fi

  # 検査4: 優先度の値
  local priority_val
  priority_val="$(grep -m1 -F '**優先度**:' "$file" | sed -E 's/^\*\*優先度\*\*:[[:space:]]*//; s/[[:space:]]+$//' || true)"
  if [ -n "$priority_val" ] && ! contains "$priority_val" "${PRIORITY_VALUES[@]}"; then
    REASONS+=("検査4 優先度の値: 「${priority_val}」は定めた 4 つに無い")
  fi

  # 検査5: 完了の判定に番号付きの条件があるか
  local kanryo_body
  if kanryo_body="$(section_body "$stripped" "完了の判定")"; then
    if ! grep -qE '^1\. |^\| *1\. ' <<< "$kanryo_body"; then
      REASONS+=("検査5 完了の判定: 番号付きの条件が無い")
    fi
  fi

  # 検査6: 対応の記録の状態語
  local record_body
  if record_body="$(section_body "$stripped" "対応の記録")"; then
    local states
    states="$(printf '%s\n' "$record_body" | parse_record_states)"
    local bad=()
    local s
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      if ! contains "$s" "${RECORD_STATE_VALUES[@]}"; then
        bad+=("$s")
      fi
    done <<< "$states"
    if [ "${#bad[@]}" -gt 0 ]; then
      local uniq_bad
      uniq_bad="$(printf '%s\n' "${bad[@]}" | LC_ALL=C sort -u)"
      local bad_arr=()
      local x
      while IFS= read -r x; do
        [ -z "$x" ] && continue
        bad_arr+=("$x")
      done <<< "$uniq_bad"
      REASONS+=("検査6 記録の状態語: 「$(join_by ' / ' "${bad_arr[@]}")」は定めた 5 つに無い")
    fi
  fi

  # 検査11: 目視の理由
  # 「確かめる手段」が目視の行は、「確かめた内容」に理由が無ければ不合格とする。
  # 5列の表（確かめる手段・確かめた内容の両列を持つ表）にだけ適用する。
  # 判定の中身は check_mihari_reason_in_record_body に集約し、
  # docs/tasks/done/ 専用の validate_mihari_only（規約 rule.md 項目10）と共有する。
  if [ -n "${record_body:-}" ]; then
    if ! check_mihari_reason_in_record_body "$record_body"; then
      REASONS+=("検査11 目視の理由: 確かめる手段が目視の行に、確かめた内容の理由が書かれていない")
    fi
  fi

  # 検査7: 決めていないこと の既定
  # 節が無ければ検査1が既に拾うため、ここでは報告しない。
  local kimeteinai_body
  if kimeteinai_body="$(section_body "$stripped" "決めていないこと")"; then
    local kimeteinai_rc=0
    kimeteinai_ok "$kimeteinai_body" || kimeteinai_rc=$?
    if [ "$kimeteinai_rc" -eq 1 ]; then
      REASONS+=("検査7 決めていないこと: 既定の列を持つ表、または「なし」の 1 行が要る")
    elif [ "$kimeteinai_rc" -eq 2 ]; then
      REASONS+=("検査7 決めていないこと: 既定の欄がユーザーの判断への委譲になっている。既定は担当者がそのまま選べる具体で書く（規約: 既定が無いと担当者が止まる）")
    fi
  fi

  # 検査8: 判断待ち（止まる前提の節を置いてはならない）
  if grep -qE '^(## |### )判断待ち[[:space:]]*$' "$stripped"; then
    REASONS+=("検査8 判断待ち: 止まる前提の節を置いてはならない。「判断の記録」へ書き換える")
  fi

  # 検査10: 置き場と状態の一致
  # docs/tasks/ 直下（design/ 以外）は「着手できる」、docs/tasks/design/ は「設計から始める」でなければならない。
  # 置き場の判定は親ディレクトリ名が "design" かどうかで行う（self-test の使い捨てディレクトリでも
  # 同じ規則で検査できるようにするため。ファイルパスに "docs/tasks" という固定文字列を要求しない）。
  if [ -n "$state_val" ]; then
    local parent_name
    parent_name="$(basename "$(dirname "$file")")"
    if [ "$parent_name" = "design" ]; then
      if [ "$state_val" != "設計から始める" ]; then
        REASONS+=("検査10 置き場と状態: 直下は「着手できる」、design/ は「設計から始める」でなければならない")
      fi
    else
      if [ "$state_val" != "着手できる" ]; then
        REASONS+=("検査10 置き場と状態: 直下は「着手できる」、design/ は「設計から始める」でなければならない")
      fi
    fi
  fi

  if [ "${#REASONS[@]}" -gt 0 ]; then
    return 1
  fi
  return 0
}

run_main() {
  local target="${1:-}"
  local root
  if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    exit 0
  fi

  local files=()
  local done_files=()
  if [ -n "$target" ]; then
    files=("$target")
  else
    if [ -d "$root/docs/tasks" ]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$root/docs/tasks" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
    fi
    if [ -d "$root/docs/tasks/design" ]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$root/docs/tasks/design" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
    fi
    # rule.md 項目10: 目視の理由の検査だけは docs/tasks/done/ も走査する。
    # 検査9（全項目の走査範囲）はここでは変えない。done/ のファイルは
    # validate_file（全項目）ではなく validate_mihari_only（目視理由のみ）で見る。
    if [ -d "$root/docs/tasks/done" ]; then
      while IFS= read -r f; do
        done_files+=("$f")
      done < <(find "$root/docs/tasks/done" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
    fi
  fi

  echo "=== 指示書の形の検査 ==="
  echo "対象: $(( ${#files[@]} + ${#done_files[@]} )) 件（うち done/ は目視理由検査のみ ${#done_files[@]} 件）"
  echo ""

  # 一時ファイル基盤が使えるかを事前に確認する。mktempが失敗する環境
  # （サンドボックスで一時領域への書き込みが拒否される場合等）では、
  # 各ファイルの中身に関わらず全項目が「欠落」と誤判定されるため、
  # ここで検出し「不合格」と区別できる「判定不能」として終了する。
  if ! ensure_stripped_tmp; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi

  local pass=0 fail=0
  local f
  for f in "${files[@]}"; do
    local name
    name="$(basename "$f")"
    if validate_file "$f"; then
      echo "[OK]   ${name}"
      pass=$((pass + 1))
    else
      echo "[FAIL] ${name}"
      local r
      for r in "${REASONS[@]}"; do
        echo "       ${r}"
      done
      fail=$((fail + 1))
    fi
  done

  if [ "${#done_files[@]}" -gt 0 ]; then
    echo ""
    echo "--- done/ の目視理由検査（rule.md 項目10） ---"
    for f in "${done_files[@]}"; do
      local done_name
      done_name="$(basename "$f")"
      if validate_mihari_only "$f"; then
        echo "[OK]   ${done_name}"
        pass=$((pass + 1))
      else
        echo "[FAIL] ${done_name}"
        local dr
        for dr in "${REASONS[@]}"; do
          echo "       ${dr}"
        done
        fail=$((fail + 1))
      fi
    done
  fi

  echo ""
  echo "合格 ${pass} 件 / 不合格 ${fail} 件"

  if [ "$fail" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# docs/tasks/ 全体から「判断の記録」節の表を集めて表示する。合否は判定しない
# （常に exit 0）。
run_decisions() {
  local root
  if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    exit 0
  fi

  local files=()
  if [ -d "$root/docs/tasks" ]; then
    while IFS= read -r f; do
      files+=("$f")
    done < <(find "$root/docs/tasks" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
  fi

  echo "=== 判断の記録の一覧 ==="
  echo ""

  local total=0
  local f
  for f in "${files[@]}"; do
    ensure_stripped_tmp
    strip_fences "$f" > "$STRIPPED_TMP"
    local body
    if ! body="$(section_body "$STRIPPED_TMP" "判断の記録")"; then
      continue
    fi
    echo "--- $(basename "$f") ---"
    local rows
    rows="$(printf '%s\n' "$body" | parse_decision_rows)"
    if [ -z "$rows" ]; then
      echo "（記録なし）"
    else
      printf '%s\n' "$rows"
      local n
      n="$(printf '%s\n' "$rows" | grep -c .)"
      total=$((total + n))
    fi
    echo ""
  done

  echo "合計 ${total} 件"
  exit 0
}

# --- self-test 用の疑似指示書生成 ---

# 5列の「判定の充足状況」表を持ち、「確かめる手段」の欄に、Markdownで
# リテラルのパイプ文字を表す標準表記 `\|`（シェルのパイプ演算子を含む
# コマンド）を書いた行を持つ疑似指示書。$1=状態欄の値
# （STATE_PLACEHOLDERをsedで置き換える）。
good_doc_5col_with_escaped_pipe() {
  cat <<'EOF'
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

1. 何かが0件になる

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 何かが0件になる | `cmd1 2>&1 \| grep -qF ok` | STATE_PLACEHOLDER | — | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
EOF
}

good_doc() {
  cat <<'EOF'
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

1. 何かが0件になる

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|
| 1. 何かが0件になる | 未着手 | — | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
EOF
}

# $1=heading を検査し、その本文（heading直後〜次の"## "見出し直前）を $2 で
# まるごと置き換えて標準出力へ出す。標準入力に元の文書全文を渡す。
# $2 は環境変数（REPLACE_HEADING_NB）経由で渡す。awk -v は値に改行を含むと
# 「newline in string」でエラーになるため（macOS標準awkで実測確認）、
# 改行を含みうる本文だけは ENVIRON 経由にする。
replace_heading_body() {
  local heading="$1" newbody="$2"
  REPLACE_HEADING_NB="$newbody" LC_ALL=C awk -v h="$heading" '
    BEGIN { skip = 0; nb = ENVIRON["REPLACE_HEADING_NB"] }
    /^## / {
      title = $0
      sub(/^## +([0-9]+\. )?/, "", title)
      gsub(/[ \t]+$/, "", title)
      if (title == h) {
        print $0
        print ""
        print nb
        skip = 1
        next
      } else {
        skip = 0
      }
    }
    skip == 0 { print }
  '
}

remove_heading_section() {
  local heading="$1"
  LC_ALL=C awk -v h="$heading" '
    BEGIN { skip = 0 }
    /^## / {
      title = $0
      sub(/^## +([0-9]+\. )?/, "", title)
      gsub(/[ \t]+$/, "", title)
      if (title == h) { skip = 1; next }
      else { skip = 0 }
    }
    skip == 0 { print }
  '
}

number_headings() {
  awk '
    /^## / { n++; sub(/^## /, "## " n ". ") }
    { print }
  '
}

wrong_named_doc() {
  cat <<'EOF'
# サンプル指示書（見出し名が違う版）

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## 背景

説明。

## project-setup

説明。

## 命名の判断

説明。

## 実測で判明した事実

説明。

## 着手前に必要な調査

説明。

## 移設の方法を先に決める必要がある

説明。

## 実施の順序

説明。

## 見送った判断

説明。
EOF
}

run_self_test() {
  # tmpdirはグローバル変数にする。trap RETURNはbashでは関数スコープに閉じず
  # このシェルで以後に返るすべての関数呼び出し（run_case等）で再発火するため、
  # ローカル変数だと最初のネスト関数の return 時点で削除されてしまう。
  # trap EXIT + グローバル変数の組み合わせで、スクリプト終了時にのみ1回だけ掃除する。
  if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため自己テストを判定できません（mktemp -d が一時領域へ書き込めませんでした）"
    exit 2
  fi
  trap 'rm -rf "$tmpdir"' EXIT

  local pass=0 fail=0

  run_case() {
    local name="$1" file="$2" expect="$3"
    local got="fail"
    if validate_file "$file"; then
      got="pass"
    fi
    if [ "$got" = "$expect" ]; then
      echo "[PASS] ${name}"
      pass=$((pass + 1))
    else
      echo "[FAIL] ${name}"
      fail=$((fail + 1))
    fi
  }

  echo "実行 35 件"

  # 1. 8節と3行が揃う -> 合格
  local f1="$tmpdir/case1.md"
  good_doc > "$f1"
  run_case "8節と3行が揃う" "$f1" "pass"

  # 2. 節が1つ欠ける -> 不合格
  local f2="$tmpdir/case2.md"
  good_doc | remove_heading_section "触らない範囲" > "$f2"
  run_case "節が1つ欠ける" "$f2" "fail"

  # 3. 節が番号付き（## 3. やること 等） -> 合格
  local f3="$tmpdir/case3.md"
  good_doc | number_headings > "$f3"
  run_case "節が番号付き" "$f3" "pass"

  # 4. 冒頭3行のうち1つが無い -> 不合格
  local f4="$tmpdir/case4.md"
  good_doc | grep -vF '**前提**:' > "$f4"
  run_case "冒頭3行のうち1つが無い" "$f4" "fail"

  # 5. 状態が定めた3つに無い値 -> 不合格
  local f5="$tmpdir/case5.md"
  good_doc | sed 's/\*\*状態\*\*: 着手できる/**状態**: 作業中/' > "$f5"
  run_case "状態が定めた3つに無い値" "$f5" "fail"

  # 6. 優先度が定めた4つに無い値 -> 不合格
  local f6="$tmpdir/case6.md"
  good_doc | sed 's/\*\*優先度\*\*: 中/**優先度**: 超高/' > "$f6"
  run_case "優先度が定めた4つに無い値" "$f6" "fail"

  # 7. 完了の判定に番号付きの条件が無い -> 不合格
  local f7="$tmpdir/case7.md"
  good_doc | sed 's/^1\. 何かが0件になる$/何かを完了させる。/' > "$f7"
  run_case "完了の判定に番号付きの条件が無い" "$f7" "fail"

  # 8. 記録の状態に「保留」がある -> 不合格
  local f8="$tmpdir/case8.md"
  good_doc | sed 's/| 未着手 |/| 保留 |/' > "$f8"
  run_case "記録の状態に保留がある" "$f8" "fail"

  # 9. 節が8個あるが名前が必須の8つと1つも一致しない -> 不合格
  local f9="$tmpdir/case9.md"
  wrong_named_doc > "$f9"
  run_case "節が8個あるが名前が違う" "$f9" "fail"

  # 10. 必須の節のうち3つが柵の中にだけある（本物の見出しとしては無い） -> 不合格
  local f10="$tmpdir/case10.md"
  cat <<'EOF' > "$f10"
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

1. 何かが0件になる

節の名前は下記の例を参照する。

```
## 触らない範囲
## 決めていないこと
## 他の指示書との関係
```

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|
| 1. 何かが0件になる | 未着手 | — | — |

### 判断待ち

| 何を決めるか | なぜ決められないか | 選択肢 |
|---|---|---|
EOF
  run_case "節の名前が柵の中だけにある" "$f10" "fail"

  # 11. 完了の判定の番号付き条件が柵の中だけにある -> 不合格
  local f11="$tmpdir/case11.md"
  cat <<'EOF' > "$f11"
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

条件の書き方は次の例を参照する。

```
1. 何かが0件になる
```

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|
| 1. 何かが0件になる | 未着手 | — | — |

### 判断待ち

| 何を決めるか | なぜ決められないか | 選択肢 |
|---|---|---|
EOF
  run_case "完了の判定の条件が柵の中だけにある" "$f11" "fail"

  # 12. 柵が閉じないままファイルが終わり、必須の節が柵の後ろに残る -> 不合格
  local f12="$tmpdir/case12.md"
  cat <<'EOF' > "$f12"
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

```
コードの例がここから始まり、閉じずに終わる。

## 完了の判定

1. 何かが0件になる

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|
| 1. 何かが0件になる | 未着手 | — | — |

### 判断待ち

| 何を決めるか | なぜ決められないか | 選択肢 |
|---|---|---|
EOF
  run_case "柵が閉じない" "$f12" "fail"

  # 13. 状態が「決定を待つ」 -> 不合格
  local f13="$tmpdir/case13.md"
  good_doc | sed 's/\*\*状態\*\*: 着手できる/**状態**: 決定を待つ/' > "$f13"
  run_case "状態が決定を待つ" "$f13" "fail"

  # 14. 決めていないことが既定の列を持つ表 -> 合格
  local f14="$tmpdir/case14.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めないか | 既定 |\n|---|---|\n| 対象範囲 | 全部 |')" > "$f14"
  run_case "決めていないことが既定の列を持つ表" "$f14" "pass"

  # 15. 決めていないことが「なし」の1行 -> 合格
  local f15="$tmpdir/case15.md"
  good_doc | replace_heading_body "決めていないこと" "なし。" > "$f15"
  run_case "決めていないことがなしの1行" "$f15" "pass"

  # 16. 決めていないことが既定の列を持たない表 -> 不合格
  local f16="$tmpdir/case16.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めないか | 理由 |\n|---|---|\n| 対象範囲 | 未定 |')" > "$f16"
  run_case "決めていないことが既定の列を持たない" "$f16" "fail"

  # 17. 判断待ちの見出しがある -> 不合格
  local f17="$tmpdir/case17.md"
  good_doc | sed 's/### 判断の記録/### 判断待ち/' > "$f17"
  run_case "判断待ちの見出しがある" "$f17" "fail"

  # 置き場と状態の一致（検査10）用のディレクトリを用意する。
  mkdir -p "$tmpdir/tasks/design"

  # 18. 直下に「着手できる」 -> 合格
  local f18="$tmpdir/tasks/case18.md"
  good_doc > "$f18"
  run_case "直下に「着手できる」" "$f18" "pass"

  # 19. 直下に「設計から始める」 -> 不合格
  local f19="$tmpdir/tasks/case19.md"
  good_doc | sed 's/\*\*状態\*\*: 着手できる/**状態**: 設計から始める/' > "$f19"
  run_case "直下に「設計から始める」" "$f19" "fail"

  # 20. design/ に「設計から始める」 -> 合格
  local f20="$tmpdir/tasks/design/case20.md"
  good_doc | sed 's/\*\*状態\*\*: 着手できる/**状態**: 設計から始める/' > "$f20"
  run_case "design/に「設計から始める」" "$f20" "pass"

  # 21. 5列の表で、確かめる手段に \| を含むコマンドがあり状態が「完了」 -> 合格
  # （回帰ケース: セル内の \| を区切りとして split すると、その行だけ列数が
  #   1つ増え、状態欄の位置がずれて誤った値を読む。修正前はこのケースが不合格になる）
  local f21="$tmpdir/case21.md"
  good_doc_5col_with_escaped_pipe | sed 's/STATE_PLACEHOLDER/完了/' > "$f21"
  run_case "5列で確かめる手段に\\|を含み状態が完了" "$f21" "pass"

  # 22. 5列の表で、確かめる手段に \| を含むコマンドがあり状態が定めた4つに無い語 -> 不合格
  local f22="$tmpdir/case22.md"
  good_doc_5col_with_escaped_pipe | sed 's/STATE_PLACEHOLDER/保留/' > "$f22"
  run_case "5列で確かめる手段に\\|を含み状態が定めた4つに無い語" "$f22" "fail"

  # 23. 決めていないことが既定の欄でユーザー判断への委譲 -> 不合格
  local f23="$tmpdir/case23.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めるか | 既定 |\n|---|---|\n| 対象範囲 | 決めない。ユーザーの判断を仰ぐ |')" > "$f23"
  run_case "決めていないことの既定がユーザー判断への委譲" "$f23" "fail"

  # 24. 決めていないことが既定の欄で空欄相当（—） -> 不合格
  local f24="$tmpdir/case24.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めるか | 既定 |\n|---|---|\n| 対象範囲 | — |')" > "$f24"
  run_case "決めていないことの既定が空欄相当" "$f24" "fail"

  # 25. 決めていないことの既定が「決めない」で始まるが具体が続く -> 合格
  local f25="$tmpdir/case25.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めるか | 既定 |\n|---|---|\n| 対象範囲 | この一覧では決めない。1件で形を確立し対応中のまま残す |')" > "$f25"
  run_case "決めていないことの既定が決めないで始まるが具体が続く" "$f25" "pass"

  # 26. 決めていないことの既定に具体があってもユーザー判断への委譲を含む -> 不合格
  local f26="$tmpdir/case26.md"
  good_doc | replace_heading_body "決めていないこと" "$(printf '| 何を決めるか | 既定 |\n|---|---|\n| 対象範囲 | まず1件で試す。その後ユーザーの判断を仰ぐ |')" > "$f26"
  run_case "決めていないことの既定に具体があってもユーザー判断への委譲を含む" "$f26" "fail"

  # 27. 記録の状態語に「未確認」を使える -> 合格
  local f27="$tmpdir/case27.md"
  good_doc | sed 's/| 未着手 |/| 未確認 |/' > "$f27"
  run_case "記録の状態語に未確認を使える" "$f27" "pass"

  # 28. 記録の状態語に定めていない語（保留）は使えない -> 不合格
  # （「未確認」を足したことで他の語まで通るようになっていないことを確かめる）
  local f28="$tmpdir/case28.md"
  good_doc | sed 's/| 未着手 |/| 保留 |/' > "$f28"
  run_case "記録の状態語に定めていない語は使えない" "$f28" "fail"

  # 29. 目視の行に理由があれば合格
  local f29="$tmpdir/case29.md"
  cat <<'EOF' > "$f29"
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

1. 何かが0件になる

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 何かが0件になる | 目視 | 完了 | — | 文面の評価を要するため |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
EOF
  run_case "目視の行に理由があれば合格" "$f29" "pass"

  # 30. 目視の行に理由が無ければ不合格
  local f30="$tmpdir/case30.md"
  cat <<'EOF' > "$f30"
# サンプル指示書

**状態**: 着手できる
**優先度**: 中
**前提**: なし
**元の指摘**: なし

## この指示書は何か

説明。

## なぜ必要か

理由。

## やること

作業内容。

## 完了の判定

1. 何かが0件になる

## 触らない範囲

なし。

## 決めていないこと

なし。

## 他の指示書との関係

なし。

## この指示書の位置づけ

説明。

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 何かが0件になる | 目視 | 完了 | — | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
EOF
  run_case "目視の行に理由が無ければ不合格" "$f30" "fail"

  # 31. done配下の理由なし目視を検知する（rule.md 項目10: 目視の理由の検査だけを
  # docs/tasks/done/ へ広げる）。validate_file ではなく validate_mihari_only を使う。
  # 「対応の記録」より前の必須節・冒頭3行は無く、他の検査には通らない疑似ファイルでも、
  # 目視理由の検査だけが働き不合格になることを確かめる。
  mkdir -p "$tmpdir/tasks/done"
  local f31="$tmpdir/tasks/done/case31.md"
  cat <<'EOF' > "$f31"
# サンプル指示書（done配下・片付いた指示書）

## 対応の記録

### 判定の充足状況

| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |
|---|---|---|---|---|
| 1. 何かが0件になる | 目視 | 完了 | — | — |

### 判断の記録

| 何を決めたか | 選んだもの | 選んだ理由 | 覆すと何が変わるか |
|---|---|---|---|
EOF
  local got31="fail"
  if validate_mihari_only "$f31"; then
    got31="pass"
  fi
  if [ "$got31" = "fail" ]; then
    echo "[PASS] done配下の理由なし目視を検知する"
    pass=$((pass + 1))
  else
    echo "[FAIL] done配下の理由なし目視を検知する"
    fail=$((fail + 1))
  fi

  # 32. 元の指摘が正しい形（1件） -> 合格
  local f32="$tmpdir/case32.md"
  good_doc | sed 's/\*\*元の指摘\*\*: なし/**元の指摘**: 1-62/' > "$f32"
  run_case "元の指摘が1件の正しい形" "$f32" "pass"

  # 33. 元の指摘が正しい形（複数件・カンマ区切り） -> 合格
  local f33="$tmpdir/case33.md"
  good_doc | sed 's/\*\*元の指摘\*\*: なし/**元の指摘**: 1-62, 1-65, 1-81/' > "$f33"
  run_case "元の指摘が複数件のカンマ区切り" "$f33" "pass"

  # 34. 冒頭4行のうち元の指摘だけが無い -> 不合格
  local f34="$tmpdir/case34.md"
  good_doc | grep -vF '**元の指摘**:' > "$f34"
  run_case "元の指摘の行が無い" "$f34" "fail"

  # 35. 元の指摘の値が形式に合わない（1-NN でもなしでもない） -> 不合格
  local f35="$tmpdir/case35.md"
  good_doc | sed 's/\*\*元の指摘\*\*: なし/**元の指摘**: 1-62.5/' > "$f35"
  run_case "元の指摘の値が形式に合わない" "$f35" "fail"

  echo "合格 ${pass} 件 / 不合格 ${fail} 件"

  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

main() {
  local mode="${1:-}"
  if [ "$mode" = "--self-test" ]; then
    run_self_test
    exit $?
  fi
  if [ "$mode" = "--decisions" ]; then
    run_decisions
    exit 0
  fi
  run_main "$mode"
}

main "$@"
