#!/usr/bin/env bash
set -u

# extract-facts.sh — 道標の取り出しの規則を実行し、単位ごとの事実を作る
#
# 目的:
#   道標の節4の当該種別にある「事実の項目 | どの構文・記述から取るか」の表
#   （取り出しの規則）を解釈し、一覧の元データが持つ単位ごとに、コードから
#   事実（入力項目・表示項目 等、種別ごとに定めた項目）を機械で取り出して
#   固定する。取り出しの規則が「AIの読み取り」の項目は機械では取り出さず、
#   値を空のまま「未」へ載せ、AIが後で埋める対象として残す。
#
# 使い方:
#   extract-facts.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書の置き場>]
#     [--map <道標のパス>] [--lists <一覧の元データの場所>]
#     [--out <facts の親>] [--verify]
#   extract-facts.sh --self-test
#
# --design-root の既定は <対象リポジトリのルート>。--map・--lists の既定はこの値の配下。
# --map の既定は <対象>/docs/design/common/道標.md。
# --lists の既定は <対象>/docs/design/lists。
# --out の既定は <実行フォルダ>/facts。
# --verify を付けると、既存の <out>/<種別>/ ともう一度取り出した結果を
#   compare-facts.sh で比べる。差分が0件なら「検証: 一致」に続けて
#   「未の項目: N」（Nは未の項目の総数）を出し終了コード0で返す。未の項目が
#   あっても差分が0件なら合格として扱う。差分が1件以上あれば終了コード1で
#   返す（このとき --out は上書きしない）。
#
# 取り出しの規則の書式（道標の節4「検出条件の形の制約」に定める）:
#   正規表現: <ERE> ／ 捕捉: <N> ／ 範囲: <場所|属するファイル|両方|単位>
#   （区切りは全角スラッシュ「 ／ 」。捕捉の既定1、範囲の既定 両方。
#    セル内の \| は | に戻す。範囲の値は前方一致で読む。例えば
#    「場所（画面ファイル）」は「場所」として扱う）
#   または
#   AI の読み取り: <説明>
#
# 範囲の意味:
#   場所・単位: 一覧の根拠（<場所>:<行>）が指す単位の区間だけを走査する。
#     区間は根拠の行から、同じ場所（ファイル）内で次に大きい行を持つ別の
#     単位の直前の行まで（同じ場所を持つ他の単位が無ければファイル末尾）。
#     1ファイルに1単位しか無い場合は区間がファイル全体に一致する。
#     「単位」は「属するファイルを読まない」ことを強調した場所の別名。
#   属するファイル: 一覧の属するファイルの各要素をglobとして対象ルートから
#     展開し、実在するファイルだけを走査する。属するファイルは検出条件の
#     規則の文字列であり、単位ごとに実在するとは限らない。展開結果が0件の
#     要素は警告に留め、不合格にはしない。
#   両方: 場所（単位の区間）と属するファイル（展開結果）の両方を走査する。
#
# 事実ファイルの形（<out>/<種別>/<単位のフォルダ名>.json）:
#   {"種別","識別子","名前","場所","属するファイル":[...],
#    "事実":{"<項目>":{"値":[...],"出所":"機械"|"AI","根拠":[...]}},
#    "未":[...],"取り出した実行":"<実行の識別子>"}
#   値は常に配列。機械で0件だった項目・AIの読み取りの項目は値[]で「未」に
#   載る。捕捉した文字列が空文字列であっても、一致自体があれば正当な値
#   （空文字列）として値に載せ、未には載せない。
#
# 終了コード:
#   0 = 全単位に事実がある（--verifyでは既存と再取り出しの差分が0件）
#   1 = 一覧の場所（単位そのものの所在）が対象に実在しない、または取り出しの規則の
#       2列目が規定の形（正規表現|AIの読み取り）のどちらでもなく解釈できない項目がある
#       （--verifyでは差分が1件以上）（差し戻し: 検出条件-見直し）
#       （解釈できない項目は集計.jsonの「規則の無い項目」へ列挙し警告を出す）
#   2 = 使い方の誤り・道標や一覧の不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。取り出しの規則の書式を変えるときは、道標の
#   様式（reverse-drawing-map）と本スクリプトと自己テストを同時に直す。
#
# 廃棄条件: 取り出しの規則の形を別の仕組み（構文解析器など）に置き換えた時。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPTS="$(cd "${SCRIPT_DIR}/../../reverse-shared/scripts" && pwd)"

usage_error() {
  echo "使い方: extract-facts.sh <対象リポジトリのルート> --run <実行フォルダ> --kind <種別> [--design-root <設計書の置き場>] [--map <道標のパス>] [--lists <一覧の元データの場所>] [--out <facts の親>] [--verify]" >&2
  echo "        extract-facts.sh --self-test" >&2
  exit 2
}

is_valid_kind() {
  case "$1" in
    screen|api|table|batch|report|external|feature) return 0 ;;
    *) return 1 ;;
  esac
}

kind_ja() {
  case "$1" in
    screen) echo "画面" ;;
    api) echo "接続窓口" ;;
    table) echo "表" ;;
    batch) echo "バッチ" ;;
    report) echo "帳票" ;;
    external) echo "外部連携" ;;
    feature) echo "機能" ;;
    *) echo "" ;;
  esac
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# --- 道標の節0にある「文字コード」の値を読む。無ければUTF-8とみなす
#     （list-units.shと同じ方式。reverse-sharedへは寄せず本ファイルへ
#     複製している。scripts/ は機能ごとに独立して持つという既存の切り方
#     に合わせ、依存を増やさないための複製） ---
read_charset() {
  local map="$1" row cs
  row="$(grep -E '^\|[[:space:]]*文字コード[[:space:]]*\|' "$map" | head -n1)"
  if [ -z "$row" ]; then
    printf 'UTF-8'
    return 0
  fi
  cs="$(printf '%s' "$row" | awk -F'|' '{print $3}')"
  cs="$(trim "$cs")"
  if [ -z "$cs" ]; then
    cs="UTF-8"
  fi
  printf '%s' "$cs"
}

# --- 文字コードがUTF-8でない場合、UTF-8化した一時ファイルのパスを返す
#     （キャッシュ済みなら再利用する）。変換に失敗すれば空文字を返し
#     非0で返る（list-units.shと同じ方式） ---
utf8_path_for() {
  local f="$1" charset="$2" cache_dir="$3"
  if [ "$charset" = "UTF-8" ]; then
    printf '%s' "$f"
    return 0
  fi
  local key cached
  key="$(printf '%s' "$f" | shasum -a 256 | awk '{print $1}')"
  cached="${cache_dir}/${key}"
  if [ -f "$cached" ]; then
    printf '%s' "$cached"
    return 0
  fi
  if iconv -f "$charset" -t UTF-8 "$f" > "$cached" 2>/dev/null; then
    printf '%s' "$cached"
    return 0
  fi
  rm -f "$cached" 2>/dev/null
  return 1
}

# --- 道標の節4の当該種別の「目印」欄が「対象外」かどうかを判定する ---
kind_is_out_of_scope() {
  local map="$1" kind="$2" ja
  ja="$(kind_ja "$kind")"
  [ -n "$ja" ] || return 1

  local mark
  mark="$(awk -v ja="$ja" '
    BEGIN { infile = 0 }
    $0 ~ ("^### 4\\.[0-9]+ " ja "$") { infile = 1; next }
    infile && /^### / { exit }
    infile && /^## / { exit }
    infile && /^\| 目印 \|/ { print; exit }
  ' "$map")"
  case "$mark" in
    *"| 対象外 |"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 道標の節4の当該種別の「事実の項目 | どの構文・記述から取るか」の表を
#     生の行（"| 項目 | 規則 |"）のまま返す ---
read_extraction_rule_rows() {
  local map="$1" kind="$2" ja
  ja="$(kind_ja "$kind")"
  [ -n "$ja" ] || return 1

  local block
  block="$(awk -v ja="$ja" '
    BEGIN { infile = 0 }
    $0 ~ ("^### 4\\.[0-9]+ " ja "$") { infile = 1; next }
    infile && /^### / { exit }
    infile && /^## / { exit }
    infile { print }
  ' "$map")"
  [ -n "$block" ] || return 1

  local header_line
  header_line="$(printf '%s\n' "$block" | grep -n -F -x '| 事実の項目 | どの構文・記述から取るか |' | head -n1 | cut -d: -f1)"
  [ -n "$header_line" ] || return 1

  local start=$((header_line + 2))
  printf '%s\n' "$block" | awk -v start="$start" '
    NR < start { next }
    /^\|/ { print; next }
    { exit }
  '
}

# --- "| 項目 | 規則 |" の1行を "項目<TAB>規則" に変換する（\| は | に戻す） ---
parse_rule_row() {
  local row="$1" placeholder="@@ESCPIPE@@"
  local esc="${row//\\|/$placeholder}"
  local item rule
  item="$(printf '%s' "$esc" | awk -F'|' '{print $2}')"
  rule="$(printf '%s' "$esc" | awk -F'|' '{print $3}')"
  item="$(trim "$item")"
  rule="$(trim "$rule")"
  item="${item//$placeholder/|}"
  rule="${rule//$placeholder/|}"
  printf '%s\t%s' "$item" "$rule"
}

# --- 道標の節4の当該種別の取り出しの規則を "項目<TAB>規則" の行群で返す ---
read_extraction_rules() {
  local map="$1" kind="$2" rows row
  rows="$(read_extraction_rule_rows "$map" "$kind")" || return 1
  [ -n "$rows" ] || return 1
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    parse_rule_row "$row"
    printf '\n'
  done <<ROWLIST
$rows
ROWLIST
}

# --- 「範囲:」の値を前方一致で正規の値へ寄せる。道標が補足を括弧で付けて
#     も読める（例: 「場所（画面ファイル）」→「場所」）。前方一致で判定
#     できない値は既定の「両方」に寄せる ---
normalize_scope() {
  local raw="$1"
  case "$raw" in
    属するファイル*) printf '属するファイル' ;;
    両方*) printf '両方' ;;
    単位*) printf '単位' ;;
    場所*) printf '場所' ;;
    *) printf '両方' ;;
  esac
}

# --- 規則の文字列を解釈する。標準出力:
#     "MACHINE<TAB><regex><TAB><capture><TAB><scope>" または "AI<TAB><説明>"
#     解釈できなければ何も出さず非0で返る ---
parse_rule() {
  local rule="$1"
  case "$rule" in
    "AI の読み取り:"*)
      local desc="${rule#AI の読み取り:}"
      desc="$(trim "$desc")"
      printf 'AI\t%s' "$desc"
      return 0
      ;;
  esac

  local regex="" capture="1" scope="両方"
  local rest="$rule" part
  while [ -n "$rest" ]; do
    case "$rest" in
      *"／"*)
        part="${rest%%／*}"
        rest="${rest#*／}"
        ;;
      *)
        part="$rest"
        rest=""
        ;;
    esac
    part="$(trim "$part")"
    case "$part" in
      正規表現:*)
        regex="${part#正規表現:}"
        regex="$(trim "$regex")"
        ;;
      捕捉:*)
        capture="${part#捕捉:}"
        capture="$(trim "$capture")"
        ;;
      範囲:*)
        scope="${part#範囲:}"
        scope="$(trim "$scope")"
        ;;
    esac
  done

  [ -n "$regex" ] || return 1
  scope="$(normalize_scope "$scope")"
  printf 'MACHINE\t%s\t%s\t%s' "$regex" "$capture" "$scope"
  return 0
}

# --- 正規表現の捕捉数（エスケープされていない開き括弧の数）を数える ---
count_capture_groups() {
  local regex="$1" stripped cnt
  stripped="$(printf '%s' "$regex" | sed -E 's/\\\(//g; s/\\\)//g')"
  cnt="$(printf '%s' "$stripped" | tr -dc '(' | wc -c | tr -d ' ')"
  printf '%s' "$cnt"
}

# --- 内容の1行から、正規表現のN番目の捕捉を取り出す。標準出力に値を出し
#     0で返る（捕捉が空文字列でも0で返る）。一致が無い、または捕捉番号が
#     正規表現の括弧の数を超える場合は何も出さず非0で返る ---
capture_group_n() {
  local content="$1" regex="$2" n="$3" matched groups cap
  case "$n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  matched="$(printf '%s' "$content" | grep -oE "$regex" | head -n1)"
  [ -n "$matched" ] || return 1
  groups="$(count_capture_groups "$regex")"
  if [ "$n" -lt 1 ] || [ "$groups" -lt "$n" ]; then
    return 1
  fi
  cap="$(printf '%s' "$matched" | sed -E "s/^${regex}\$/@@CAPBEGIN@@\\${n}@@CAPEND@@/" 2>/dev/null)"
  case "$cap" in
    @@CAPBEGIN@@*@@CAPEND@@)
      cap="${cap#@@CAPBEGIN@@}"
      cap="${cap%@@CAPEND@@}"
      printf '%s' "$cap"
      return 0
      ;;
  esac
  return 1
}

# --- 対象ルート内でglobパターンを展開し、対象ルートからの相対パスを返す ---
expand_glob_in_target() {
  local target="$1" pattern="$2"
  ( cd "$target" 2>/dev/null || exit 1
    compgen -G "$pattern" 2>/dev/null )
}

# --- 属するファイル（; 区切りの規則の文字列）をglobとして展開し、実在する
#     ファイルの相対パスを重複なく返す。展開結果が0件の要素は警告のみで
#     不合格にしない ---
resolve_belongs_files() {
  local target="$1" belongs="$2" kind="$3" id="$4"
  [ -n "$belongs" ] || return 0
  printf '%s\n' "$belongs" | tr ';' '\n' | while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    local matches
    matches="$(expand_glob_in_target "$target" "$pattern")"
    if [ -z "$matches" ]; then
      echo "[WARN] 属するファイル-一致なし: ${kind}/${id}: ${pattern}" >&2
    else
      printf '%s\n' "$matches"
    fi
  done | awk 'NF' | awk '!seen[$0]++'
}

# --- 一覧の元データ（<種別>.json）の識別子・場所・根拠から、単位ごとの
#     区間（開始行・終了行）を求める。標準出力: 識別子<TAB>場所<TAB>開始行
#     <TAB>終了行（0はファイル末尾までを表す）。
#     区間 = 根拠の行から、同じ場所で次に大きい行を持つ別の単位の直前の
#     行まで（無ければファイル末尾）。1ファイル1単位なら区間はファイル
#     全体に一致する ---
compute_unit_ranges() {
  local lists_file="$1"
  [ -f "$lists_file" ] || return 0
  local raw
  raw="$(jq -r '.[] | [.["識別子"], .["場所"], (.["根拠"] // "")] | @tsv' "$lists_file" 2>/dev/null)"
  [ -n "$raw" ] || return 0

  awk -F'\t' '
    function line_of(ev,    tail, n, arr) {
      n = split(ev, arr, ":")
      if (n < 1) return 1
      tail = arr[n]
      if (tail ~ /^[0-9]+$/) return tail + 0
      return 1
    }
    {
      id[NR] = $1
      place[NR] = $2
      line[NR] = line_of($3)
      n = NR
    }
    END {
      for (i = 1; i <= n; i++) {
        best = 0
        for (j = 1; j <= n; j++) {
          if (place[j] == place[i] && line[j] > line[i]) {
            if (best == 0 || line[j] < best) best = line[j]
          }
        }
        endline = (best == 0) ? 0 : best - 1
        print id[i] "\t" place[i] "\t" line[i] "\t" endline
      }
    }
  ' <<< "$raw"
}

# --- 内容ファイル（対象ファイルの全体、または単位の区間を切り出した一時
#     ファイル）にregexを掛け、捕捉値・根拠（rel）をvalues_file/
#     evidence_fileへ積む ---
scan_regex_source() {
  local rel="$1" content_file="$2" regex="$3" capture="$4" values_file="$5" evidence_file="$6"
  local had_match=0 matchline cap
  while IFS= read -r matchline; do
    [ -n "$matchline" ] || continue
    had_match=1
    if cap="$(capture_group_n "$matchline" "$regex" "$capture")"; then
      if ! grep -qFx -- "$cap" "$values_file" 2>/dev/null; then
        printf '%s\n' "$cap" >> "$values_file"
      fi
    fi
  done < <(grep -E "$regex" "$content_file" 2>/dev/null)
  if [ "$had_match" -eq 1 ] && ! grep -qFx -- "$rel" "$evidence_file" 2>/dev/null; then
    echo "$rel" >> "$evidence_file"
  fi
}

# ============================================================
# 本処理
# ============================================================

do_extract() {
  local target="$1" kind="$2" map="$3" lists="$4" out="$5" exec_id="$6" run_dir="$7"

  if kind_is_out_of_scope "$map" "$kind"; then
    echo "対象外: ${kind} は道標の目印が対象外のため取り出しを飛ばします"
    return 0
  fi

  local rules
  rules="$(read_extraction_rules "$map" "$kind")"
  if [ -z "$rules" ]; then
    echo "[FAIL] 規則-不在: 道標に ${kind} の取り出しの規則がありません" >&2
    return 2
  fi

  local units units_rc
  units="$("$SHARED_SCRIPTS/list-units-of.sh" "$target" "$kind" --lists "$lists" 2>&1)"
  units_rc=$?
  if [ "$units_rc" -ne 0 ]; then
    echo "$units" >&2
    return 2
  fi

  mkdir -p "${out}/${kind}"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/extract-facts-work.XXXXXX")" || { echo "[FAIL] 一時領域-作成不能" >&2; return 2; }
  local charset
  charset="$(read_charset "$map")"
  local charset_cache="${work}/charset-cache"
  mkdir -p "$charset_cache"

  local lists_file="${lists%/}/${kind}.json"
  local ranges_file="${work}/unit-ranges.tsv"
  compute_unit_ranges "$lists_file" > "$ranges_file"

  local unit_count=0 machine_filled=0 mi_total=0 missing_total=0 ai_items="" invalid_items=""

  local item rule_cell parsed rtype
  while IFS=$'\t' read -r item rule_cell; do
    [ -n "$item" ] || continue
    if parsed="$(parse_rule "$rule_cell")"; then
      rtype="${parsed%%$'\t'*}"
      if [ "$rtype" = "AI" ]; then
        ai_items="${ai_items}${item}
"
      fi
    else
      invalid_items="${invalid_items}${item}
"
    fi
  done <<RULESLIST
$rules
RULESLIST

  local id name place belongs
  while IFS=$'\t' read -r id name place belongs; do
    [ -n "$id" ] || continue
    unit_count=$((unit_count + 1))

    local dirname
    dirname="$(bash "$SHARED_SCRIPTS/unit-dir-name.sh" "$id")"

    local belongs_json
    if [ -n "$belongs" ]; then
      belongs_json="$(printf '%s' "$belongs" | tr ';' '\n' | jq -R -s -c 'split("\n") | map(select(length>0))')"
    else
      belongs_json="[]"
    fi

    local range_row start_line end_line
    range_row="$(awk -F'\t' -v id="$id" '$1==id{print; exit}' "$ranges_file")"
    if [ -n "$range_row" ]; then
      start_line="$(printf '%s' "$range_row" | awk -F'\t' '{print $3}')"
      end_line="$(printf '%s' "$range_row" | awk -F'\t' '{print $4}')"
    else
      start_line=1
      end_line=0
    fi

    local items_jsonl="${work}/${dirname}.items.jsonl"
    : > "$items_jsonl"
    local mi_list="${work}/${dirname}.mi.txt"
    : > "$mi_list"
    local item_idx=0

    while IFS=$'\t' read -r item2 rule_cell2; do
      [ -n "$item2" ] || continue
      item_idx=$((item_idx + 1))
      local parsed2 rtype2
      parsed2="$(parse_rule "$rule_cell2")" || continue
      rtype2="${parsed2%%$'\t'*}"

      if [ "$rtype2" = "AI" ]; then
        jq -n --arg item "$item2" '{"項目": $item, "値": [], "出所": "AI", "根拠": []}' >> "$items_jsonl"
        echo "$item2" >> "$mi_list"
        continue
      fi

      local regex capture scope
      regex="$(printf '%s' "$parsed2" | awk -F'\t' '{print $2}')"
      capture="$(printf '%s' "$parsed2" | awk -F'\t' '{print $3}')"
      scope="$(printf '%s' "$parsed2" | awk -F'\t' '{print $4}')"

      local values_file="${work}/${dirname}.item${item_idx}.values.txt"
      local evidence_file="${work}/${dirname}.item${item_idx}.evidence.txt"
      : > "$values_file"
      : > "$evidence_file"

      local place_abs="${target}/${place}"
      local place_ok=1
      case "$scope" in
        場所|単位|両方)
          if [ ! -f "$place_abs" ]; then
            echo "[FAIL] 属するファイル-不在: ${kind}/${id}: ${place}" >&2
            missing_total=$((missing_total + 1))
            place_ok=0
          fi
          ;;
      esac

      case "$scope" in
        場所|単位|両方)
          if [ "$place_ok" -eq 1 ]; then
            local cf
            if cf="$(utf8_path_for "$place_abs" "$charset" "$charset_cache")" && [ -n "$cf" ]; then
              local slice_file="${work}/${dirname}.item${item_idx}.slice.txt"
              if [ "$end_line" = "0" ]; then
                sed -n "${start_line},\$p" "$cf" > "$slice_file" 2>/dev/null
              else
                sed -n "${start_line},${end_line}p" "$cf" > "$slice_file" 2>/dev/null
              fi
              scan_regex_source "$place" "$slice_file" "$regex" "$capture" "$values_file" "$evidence_file"
            else
              echo "[WARN] 文字コード-変換失敗: ${kind}/${id}: ${place}" >&2
            fi
          fi
          ;;
      esac

      case "$scope" in
        属するファイル|両方)
          local belongs_files
          belongs_files="$(resolve_belongs_files "$target" "$belongs" "$kind" "$id")"
          local bf
          while IFS= read -r bf; do
            [ -n "$bf" ] || continue
            local babs="${target}/${bf}"
            [ -f "$babs" ] || continue
            local bcf
            if bcf="$(utf8_path_for "$babs" "$charset" "$charset_cache")" && [ -n "$bcf" ]; then
              scan_regex_source "$bf" "$bcf" "$regex" "$capture" "$values_file" "$evidence_file"
            else
              echo "[WARN] 文字コード-変換失敗: ${kind}/${id}: ${bf}" >&2
            fi
          done <<BELONGSFILES
$belongs_files
BELONGSFILES
          ;;
      esac

      local values_json evidence_json
      values_json="$(jq -R '.' "$values_file" | jq -s -c '.')"
      evidence_json="$(jq -R -s -c 'split("\n") | map(select(length>0))' "$evidence_file")"

      if [ "$values_json" = "[]" ]; then
        echo "$item2" >> "$mi_list"
      else
        machine_filled=$((machine_filled + 1))
      fi

      jq -n --arg item "$item2" --argjson v "$values_json" --argjson e "$evidence_json" \
        '{"項目": $item, "値": $v, "出所": "機械", "根拠": $e}' >> "$items_jsonl"
    done <<RULESLIST2
$rules
RULESLIST2

    local facts_json mi_json mi_count
    facts_json="$(jq -s 'map({(.["項目"]): {"値": .["値"], "出所": .["出所"], "根拠": .["根拠"]}}) | add // {}' "$items_jsonl")"
    mi_json="$(jq -R -s -c 'split("\n") | map(select(length>0)) | unique' "$mi_list")"
    mi_count="$(printf '%s' "$mi_json" | jq 'length')"
    mi_total=$((mi_total + mi_count))

    jq -n --arg v_kind "$kind" --arg v_id "$id" --arg v_name "$name" --arg v_place "$place" \
      --argjson v_belongs "$belongs_json" --argjson v_facts "$facts_json" \
      --argjson v_mi "$mi_json" --arg v_exec "$exec_id" \
      '{"種別": $v_kind, "識別子": $v_id, "名前": $v_name, "場所": $v_place,
        "属するファイル": $v_belongs, "事実": $v_facts, "未": $v_mi,
        "取り出した実行": $v_exec}' > "${out}/${kind}/${dirname}.json"

    if [ "$mi_count" -gt 0 ]; then
      "$SHARED_SCRIPTS/units-status.sh" "$run_dir" set "$kind" "$id" 事実 未 > /dev/null 2>&1
    else
      "$SHARED_SCRIPTS/units-status.sh" "$run_dir" set "$kind" "$id" 事実 済 > /dev/null 2>&1
    fi
  done <<UNITSLIST
$units
UNITSLIST

  local ai_items_json invalid_items_json rule_free_json invalid_count
  ai_items_json="$(printf '%s' "$ai_items" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  invalid_items_json="$(printf '%s' "$invalid_items" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  rule_free_json="$(jq -n -c --argjson a "$ai_items_json" --argjson b "$invalid_items_json" '($a + $b) | unique')"
  invalid_count="$(printf '%s' "$invalid_items_json" | jq 'length')"

  jq -n --argjson u "$unit_count" --argjson m "$machine_filled" --argjson n "$mi_total" --argjson r "$rule_free_json" \
    '{"単位数": $u, "機械で埋まった項目数": $m, "未の項目数": $n, "規則の無い項目": $r}' \
    > "${out}/${kind}/集計.json"

  rm -rf "$work"

  echo "単位数=${unit_count} 機械で埋まった項目数=${machine_filled} 未の項目数=${mi_total} 属するファイル不在=${missing_total}"

  if [ "$invalid_count" -gt 0 ]; then
    echo "[WARN] 規則-解釈不能: ${invalid_count} 件の項目の取り出しの規則を解釈できませんでした（集計の規則の無い項目を確認してください）" >&2
  fi

  if [ "$missing_total" -gt 0 ] || [ "$invalid_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" kind="" map="" lists="" out="" verify=0 design_root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --map) map="$2"; shift 2 ;;
      --lists) lists="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      --verify) verify=1; shift ;;
      *) usage_error ;;
    esac
  done

  [ -n "$run_dir" ] || usage_error
  [ -n "$kind" ] || usage_error
  is_valid_kind "$kind" || usage_error

  [ -n "$design_root" ] || design_root="$target"

  [ -n "$map" ] || map="${design_root%/}/docs/design/common/道標.md"
  [ -n "$lists" ] || lists="${design_root%/}/docs/design/lists"
  [ -n "$out" ] || out="${run_dir%/}/facts"

  if [ ! -f "$map" ]; then
    echo "[FAIL] 道標-不在: ${map} が存在しません" >&2
    exit 2
  fi

  local exec_id
  if ! exec_id="$("$SHARED_SCRIPTS/read-run.sh" "$run_dir" 実行の識別子 2>&1)"; then
    echo "$exec_id" >&2
    exit 2
  fi

  mkdir -p "$out"

  if [ "$verify" -eq 1 ]; then
    if [ ! -d "${out}/${kind}" ]; then
      echo "[FAIL] 検証-既存無し: ${out}/${kind} がありません" >&2
      exit 2
    fi
    local verify_work
    verify_work="$(mktemp -d "${TMPDIR:-/tmp}/extract-facts-verify.XXXXXX")" || { echo "[FAIL] 一時領域-作成不能" >&2; exit 2; }
    do_extract "$target" "$kind" "$map" "$lists" "$verify_work" "$exec_id" "$run_dir"
    local extract_rc=$?
    if [ "$extract_rc" -eq 2 ]; then
      rm -rf "$verify_work"
      exit 2
    fi
    bash "$SCRIPT_DIR/compare-facts.sh" "$out" "$verify_work" --kind "$kind" > "${verify_work}.cmp.log" 2>&1
    local cmp_rc=$?
    cat "${verify_work}.cmp.log"
    local verify_mi
    verify_mi="$(jq -r '.["未の項目数"] // 0' "${verify_work}/${kind}/集計.json" 2>/dev/null)"
    [ -n "$verify_mi" ] || verify_mi=0
    rm -rf "$verify_work" "${verify_work}.cmp.log"
    if [ "$cmp_rc" -ne 0 ]; then
      echo "[FAIL] 検証-不一致: 既存の事実と再取り出しの事実が一致しません" >&2
      exit 1
    fi
    echo "検証: 一致"
    echo "未の項目: ${verify_mi}"
    exit 0
  fi

  do_extract "$target" "$kind" "$map" "$lists" "$out" "$exec_id" "$run_dir"
  exit $?
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/extract-facts-self-test.XXXXXX")" || { echo "[FAIL] 自己テスト用一時領域を作れません"; return 2; }
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

  make_fixture() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d/src/pages" "$d/docs/design/common" "$d/docs/design/lists"

    cat > "$d/src/pages/OrderList.tsx" <<'FIXEOF'
<input name="orderId" />
onClickHandler: handleSubmit
FIXEOF

    cat > "$d/src/pages/OrderDetail.tsx" <<'FIXEOF'
export default function OrderDetail() {
  return null;
}
FIXEOF

    cat > "$d/docs/design/common/道標.md" <<'FIXEOF'
# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 操作 | 正規表現: handle(Submit\|Cancel) ／ 捕捉: 1 ／ 範囲: 場所 |
| 呼ぶ接続窓口 | AI の読み取り: 呼び出し箇所を読んで判断する |

## 5. 動的な定義
FIXEOF

    cat > "$d/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/OrderList.tsx","名前":"OrderList","場所":"src/pages/OrderList.tsx","根拠":"src/pages/OrderList.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"src/pages/OrderDetail.tsx","名前":"OrderDetail","場所":"src/pages/OrderDetail.tsx","根拠":"src/pages/OrderDetail.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  }

  make_run() {
    local r="$1"
    rm -rf "$r"
    mkdir -p "$r"
    cat > "$r/run.json" <<'FIXEOF'
{"対象リポジトリ":"/path/to/target","先方の名前":"サンプル先方","出力の置き場":"/path/to/ai-output","実行の識別子":"2026-09-03-abc1234","対象のコミット":"abc1234def"}
FIXEOF
  }

  # --- 合格-見本 ---
  local d1="$base/case1" r1="$base/run1"
  make_fixture "$d1"
  make_run "$r1"
  bash "$SCRIPT_DIR/extract-facts.sh" "$d1" --run "$r1" --kind screen --out "$r1/facts" > "$base/case1.out" 2>"$base/case1.err"
  local rc1=$?
  check "合格-見本: 終了コード0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"

  local orderlist_json="$r1/facts/screen/src_pages_OrderList.tsx.json"
  local orderdetail_json="$r1/facts/screen/src_pages_OrderDetail.tsx.json"
  check "OrderListの事実ファイルがある" "$([ -f "$orderlist_json" ] && echo 0 || echo 1)"

  local input_values
  input_values="$(jq -c '.["事実"]["入力項目"]["値"]' "$orderlist_json" 2>/dev/null)"
  check "入力項目の値がorderId" "$([ "$input_values" = '["orderId"]' ] && echo 0 || echo 1)"

  local action_values
  action_values="$(jq -c '.["事実"]["操作"]["値"]' "$orderlist_json" 2>/dev/null)"
  check "エスケープしたパイプを含む正規表現でSubmitを捕捉" "$([ "$action_values" = '["Submit"]' ] && echo 0 || echo 1)"

  local ai_source
  ai_source="$(jq -r '.["事実"]["呼ぶ接続窓口"]["出所"]' "$orderlist_json" 2>/dev/null)"
  check "AIの読み取りの項目は出所がAI" "$([ "$ai_source" = "AI" ] && echo 0 || echo 1)"

  local ai_mi
  ai_mi="$(jq -c '.["未"]' "$orderlist_json" 2>/dev/null)"
  case "$ai_mi" in
    *"呼ぶ接続窓口"*) check "呼ぶ接続窓口は未に載る" 0 ;;
    *) check "呼ぶ接続窓口は未に載る" 1 ;;
  esac

  local detail_input_values
  detail_input_values="$(jq -c '.["事実"]["入力項目"]["値"]' "$orderdetail_json" 2>/dev/null)"
  check "0件だった項目は値が空配列" "$([ "$detail_input_values" = '[]' ] && echo 0 || echo 1)"

  local detail_mi
  detail_mi="$(jq -c '.["未"]' "$orderdetail_json" 2>/dev/null)"
  case "$detail_mi" in
    *"入力項目"*) check "0件だった項目は未に載る" 0 ;;
    *) check "0件だった項目は未に載る" 1 ;;
  esac

  local exec_recorded
  exec_recorded="$(jq -r '.["取り出した実行"]' "$orderlist_json" 2>/dev/null)"
  check "取り出した実行にrun.jsonの値が入る" "$([ "$exec_recorded" = "2026-09-03-abc1234" ] && echo 0 || echo 1)"

  local status_ok status_mi
  status_ok="$(bash "${SHARED_SCRIPTS}/units-status.sh" "$r1" get screen "src/pages/OrderList.tsx" 事実)"
  status_mi="$(bash "${SHARED_SCRIPTS}/units-status.sh" "$r1" get screen "src/pages/OrderDetail.tsx" 事実)"
  check "未が有る単位は事実=未" "$([ "$status_mi" = "未" ] && echo 0 || echo 1)"
  check "未が有る単位は事実=未（OrderListも呼ぶ接続窓口がAI項目のため未）" "$([ "$status_ok" = "未" ] && echo 0 || echo 1)"

  local agg_json="$r1/facts/screen/集計.json"
  local agg_units agg_rule_free
  agg_units="$(jq -r '.["単位数"]' "$agg_json" 2>/dev/null)"
  agg_rule_free="$(jq -c '.["規則の無い項目"]' "$agg_json" 2>/dev/null)"
  check "集計の単位数が2" "$([ "$agg_units" = "2" ] && echo 0 || echo 1)"
  check "集計の規則の無い項目に呼ぶ接続窓口を含む" "$(case "$agg_rule_free" in *呼ぶ接続窓口*) echo 0 ;; *) echo 1 ;; esac)"

  # --- 不合格-属するファイル不在（場所そのものが実在しない） ---
  local d2="$base/case2" r2="$base/run2"
  make_fixture "$d2"
  make_run "$r2"
  cat > "$d2/docs/design/lists/screen.json" <<'FIXEOF'
[
  {"種別":"screen","識別子":"src/pages/Missing.tsx","名前":"Missing","場所":"src/pages/Missing.tsx","根拠":"src/pages/Missing.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF
  bash "$SCRIPT_DIR/extract-facts.sh" "$d2" --run "$r2" --kind screen --out "$r2/facts" > "$base/case2.out" 2>"$base/case2.err"
  local rc2=$?
  check "不合格-属するファイル不在: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"

  # --- 検証: 一致 ---
  local rc_verify_ok
  bash "$SCRIPT_DIR/extract-facts.sh" "$d1" --run "$r1" --kind screen --out "$r1/facts" --verify > "$base/verify_ok.out" 2>"$base/verify_ok.err"
  rc_verify_ok=$?
  check "検証-一致: 終了コード0" "$([ "$rc_verify_ok" -eq 0 ] && echo 0 || echo 1)"

  local expected_mi
  expected_mi="$(jq -r '.["未の項目数"]' "$r1/facts/screen/集計.json" 2>/dev/null)"
  case "$(cat "$base/verify_ok.out")" in
    *"未の項目: ${expected_mi}"*) check "検証-一致: 未の項目数を別行で出す（未が有っても合格）" 0 ;;
    *) check "検証-一致: 未の項目数を別行で出す（未が有っても合格）" 1 ;;
  esac

  # --- 検証: 不一致 ---
  local tampered="$r1/facts/screen/src_pages_OrderList.tsx.json"
  cp "$tampered" "${tampered}.bak"
  jq '.["事実"]["入力項目"]["値"] = ["改ざん"]' "$tampered" > "${tampered}.new" && mv "${tampered}.new" "$tampered"
  local rc_verify_ng
  bash "$SCRIPT_DIR/extract-facts.sh" "$d1" --run "$r1" --kind screen --out "$r1/facts" --verify > "$base/verify_ng.out" 2>"$base/verify_ng.err"
  rc_verify_ng=$?
  check "検証-不一致: 終了コード1" "$([ "$rc_verify_ng" -eq 1 ] && echo 0 || echo 1)"
  mv "${tampered}.bak" "$tampered"

  # --- 使い方誤り ---
  local d3="$base/case3" r3="$base/run3"
  make_fixture "$d3"
  make_run "$r3"

  bash "$SCRIPT_DIR/extract-facts.sh" "$d3" --kind screen > /dev/null 2>"$base/case3a.err"
  check "使い方誤り-run無し: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-facts.sh" "$d3" --run "$r3" > /dev/null 2>"$base/case3b.err"
  check "使い方誤り-kind無し: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-facts.sh" "$d3" --run "$r3" --kind unknown > /dev/null 2>"$base/case3c.err"
  check "使い方誤り-種別不正: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-facts.sh" "$d3" --run "$r3" --kind screen --map "$d3/docs/design/common/存在しない.md" > /dev/null 2>"$base/case3d.err"
  check "使い方誤り-道標不在: 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/extract-facts.sh" "$d3" --run "$r3" --kind api > /dev/null 2>"$base/case3e.err"
  check "使い方誤り-規則不在(api用の表が無い): 終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d3f="$base/case3f" r3f="$base/run3f"
  make_fixture "$d3f"
  make_run "$r3f"
  cat >> "$d3f/docs/design/common/道標.md" <<'FIXEOF2'

### 4.2 接続窓口

| 目印 | 対象外 |
|---|---|
FIXEOF2
  bash "$SCRIPT_DIR/extract-facts.sh" "$d3f" --run "$r3f" --kind api > "$base/case3f.out" 2>"$base/case3f.err"
  rc3f=$?
  check "対象外-種別は飛ばす: 終了コード0" "$([ "$rc3f" -eq 0 ] && echo 0 || echo 1)"
  check "対象外-種別は飛ばす: 対象外の表示が出る" "$(grep -q "対象外" "$base/case3f.out" && echo 0 || echo 1)"

  # --- 文字コード-EUC-JP ---
  local d4="$base/case4" r4="$base/run4"
  rm -rf "$d4" "$r4"
  mkdir -p "$d4/src/pages" "$d4/docs/design/common" "$d4/docs/design/lists"
  make_run "$r4"

  printf 'export default function OrderJP() {\n  displayLabel: 受注一覧\n  return null;\n}\n' \
    | iconv -f UTF-8 -t EUC-JP > "$d4/src/pages/OrderJP.tsx"

  cat > "$d4/docs/design/common/道標.md" <<'FIXEOF4'
| 文字コード | EUC-JP |

# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 表示項目 | 正規表現: displayLabel: (受注一覧) ／ 捕捉: 1 ／ 範囲: 場所 |

## 5. 動的な定義
FIXEOF4

  cat > "$d4/docs/design/lists/screen.json" <<'FIXEOF4'
[
  {"種別":"screen","識別子":"src/pages/OrderJP.tsx","名前":"OrderJP","場所":"src/pages/OrderJP.tsx","根拠":"src/pages/OrderJP.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF4

  bash "$SCRIPT_DIR/extract-facts.sh" "$d4" --run "$r4" --kind screen --out "$r4/facts" > "$base/case4.out" 2>"$base/case4.err"
  local rc4=$?
  check "文字コード-EUC-JP: 終了コード0" "$([ "$rc4" -eq 0 ] && echo 0 || echo 1)"

  local jp_values
  jp_values="$(jq -c '.["事実"]["表示項目"]["値"]' "$r4/facts/screen/src_pages_OrderJP.tsx.json" 2>/dev/null)"
  check "文字コード-EUC-JP: EUC-JPを変換して受注一覧を捕捉" "$([ "$jp_values" = '["受注一覧"]' ] && echo 0 || echo 1)"

  # --- 単位の区間: 同一ファイルに2単位があっても値が混ざらない
  #     （範囲の前方一致「場所（画面ファイル）」も同時に確かめる） ---
  local d5="$base/case5" r5="$base/run5"
  rm -rf "$d5" "$r5"
  mkdir -p "$d5/src/pages" "$d5/docs/design/common" "$d5/docs/design/lists"
  make_run "$r5"

  cat > "$d5/src/pages/Combo.tsx" <<'FIXEOF5'
<input name="fieldA" />
sep
sep
<input name="fieldB" />
end
FIXEOF5

  cat > "$d5/docs/design/common/道標.md" <<'FIXEOF5'
# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所（画面ファイル） |

## 5. 動的な定義
FIXEOF5

  cat > "$d5/docs/design/lists/screen.json" <<'FIXEOF5'
[
  {"種別":"screen","識別子":"combo-1","名前":"Combo1","場所":"src/pages/Combo.tsx","根拠":"src/pages/Combo.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]},
  {"種別":"screen","識別子":"combo-2","名前":"Combo2","場所":"src/pages/Combo.tsx","根拠":"src/pages/Combo.tsx:4","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF5

  bash "$SCRIPT_DIR/extract-facts.sh" "$d5" --run "$r5" --kind screen --out "$r5/facts" > "$base/case5.out" 2>"$base/case5.err"
  local rc5=$?
  check "単位の区間: 終了コード0" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"

  local combo1_json="$r5/facts/screen/combo-1.json" combo2_json="$r5/facts/screen/combo-2.json"
  local combo1_values combo2_values
  combo1_values="$(jq -c '.["事実"]["入力項目"]["値"]' "$combo1_json" 2>/dev/null)"
  combo2_values="$(jq -c '.["事実"]["入力項目"]["値"]' "$combo2_json" 2>/dev/null)"
  check "単位の区間: combo-1はfieldAだけ（fieldBと混ざらない）" "$([ "$combo1_values" = '["fieldA"]' ] && echo 0 || echo 1)"
  check "単位の区間: combo-2はfieldBだけ（fieldAと混ざらない）" "$([ "$combo2_values" = '["fieldB"]' ] && echo 0 || echo 1)"

  # --- 属するファイルはglobとして展開する。0件は警告のみで不合格にしない ---
  local d6="$base/case6" r6="$base/run6"
  rm -rf "$d6" "$r6"
  mkdir -p "$d6/src/pages" "$d6/src/api" "$d6/docs/design/common" "$d6/docs/design/lists"
  make_run "$r6"

  cat > "$d6/src/pages/List.tsx" <<'FIXEOF6'
export default function List() {
  return null;
}
FIXEOF6
  cat > "$d6/src/api/orders.ts" <<'FIXEOF6'
export const path = "/orders";
FIXEOF6
  cat > "$d6/src/api/users.ts" <<'FIXEOF6'
export const path = "/users";
FIXEOF6

  cat > "$d6/docs/design/common/道標.md" <<'FIXEOF6'
# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 呼ぶ接続窓口 | 正規表現: path = "([a-zA-Z0-9_/]+)" ／ 捕捉: 1 ／ 範囲: 属するファイル |

## 5. 動的な定義
FIXEOF6

  cat > "$d6/docs/design/lists/screen.json" <<'FIXEOF6'
[
  {"種別":"screen","識別子":"src/pages/List.tsx","名前":"List","場所":"src/pages/List.tsx","根拠":"src/pages/List.tsx:1","単位の定義":"","属するファイル":["src/api/*.ts","src/api/none-*.ts"],"分類軸":[]}
]
FIXEOF6

  bash "$SCRIPT_DIR/extract-facts.sh" "$d6" --run "$r6" --kind screen --out "$r6/facts" > "$base/case6.out" 2>"$base/case6.err"
  local rc6=$?
  check "属するファイルglob: 終了コード0（0件一致は警告のみ）" "$([ "$rc6" -eq 0 ] && echo 0 || echo 1)"

  local list_json="$r6/facts/screen/src_pages_List.tsx.json"
  local list_values
  list_values="$(jq -c '.["事実"]["呼ぶ接続窓口"]["値"] | sort' "$list_json" 2>/dev/null)"
  check "属するファイルglob: 複数ファイルへの展開結果を両方捕捉" "$([ "$list_values" = '["/orders","/users"]' ] && echo 0 || echo 1)"

  case "$(cat "$base/case6.err")" in
    *"属するファイル-一致なし"*) check "属するファイルglob: 0件一致は警告メッセージを出す" 0 ;;
    *) check "属するファイルglob: 0件一致は警告メッセージを出す" 1 ;;
  esac

  # --- 捕捉: 一致全体と同じ捕捉・空文字列の捕捉を正しく値として採る ---
  local d7="$base/case7" r7="$base/run7"
  rm -rf "$d7" "$r7"
  mkdir -p "$d7/src/pages" "$d7/docs/design/common" "$d7/docs/design/lists"
  make_run "$r7"

  cat > "$d7/src/pages/Order.tsx" <<'FIXEOF7'
route path=""
route path="/orders"
standalone
onlyempty=""
FIXEOF7

  cat > "$d7/docs/design/common/道標.md" <<'FIXEOF7'
# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 経路 | 正規表現: route path="([^"]*)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 名前一致 | 正規表現: (standalone) ／ 捕捉: 1 ／ 範囲: 場所 |
| 空値項目 | 正規表現: onlyempty="([^"]*)" ／ 捕捉: 1 ／ 範囲: 場所 |

## 5. 動的な定義
FIXEOF7

  cat > "$d7/docs/design/lists/screen.json" <<'FIXEOF7'
[
  {"種別":"screen","識別子":"src/pages/Order.tsx","名前":"Order","場所":"src/pages/Order.tsx","根拠":"src/pages/Order.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF7

  bash "$SCRIPT_DIR/extract-facts.sh" "$d7" --run "$r7" --kind screen --out "$r7/facts" > "$base/case7.out" 2>"$base/case7.err"
  local rc7=$?
  check "捕捉の取りこぼし: 終了コード0" "$([ "$rc7" -eq 0 ] && echo 0 || echo 1)"

  local order_json="$r7/facts/screen/src_pages_Order.tsx.json"
  local route_values name_values empty_values order_mi
  route_values="$(jq -c '.["事実"]["経路"]["値"] | sort' "$order_json" 2>/dev/null)"
  name_values="$(jq -c '.["事実"]["名前一致"]["値"]' "$order_json" 2>/dev/null)"
  empty_values="$(jq -c '.["事実"]["空値項目"]["値"]' "$order_json" 2>/dev/null)"
  order_mi="$(jq -c '.["未"]' "$order_json" 2>/dev/null)"

  check "捕捉: 空文字列の捕捉を値として含める" "$([ "$route_values" = '["","/orders"]' ] && echo 0 || echo 1)"
  check "捕捉: 一致全体と同じ捕捉でも値を採る（standaloneが空にならない）" "$([ "$name_values" = '["standalone"]' ] && echo 0 || echo 1)"
  check "捕捉: 常に空文字列しか捕捉しない項目も値[\"\"]になる" "$([ "$empty_values" = '[""]' ] && echo 0 || echo 1)"
  case "$order_mi" in
    *"空値項目"*) check "捕捉: 空文字列の値がある項目は未に載らない" 1 ;;
    *) check "捕捉: 空文字列の値がある項目は未に載らない" 0 ;;
  esac

  # --- 規則-解釈不能: 取り出しの規則の2列目が規定のどちらの形でもない項目 ---
  local d8="$base/case8" r8="$base/run8"
  rm -rf "$d8" "$r8"
  mkdir -p "$d8/src/pages" "$d8/docs/design/common" "$d8/docs/design/lists"
  make_run "$r8"

  cat > "$d8/src/pages/Broken.tsx" <<'FIXEOF8'
<input name="orderId" />
FIXEOF8

  cat > "$d8/docs/design/common/道標.md" <<'FIXEOF8'
# 道標

## 4. 単位の見つけ方

### 4.1 画面

| 事実の項目 | どの構文・記述から取るか |
|---|---|
| 入力項目 | 正規表現: <input[[:space:]]+name="([a-zA-Z0-9_]+)" ／ 捕捉: 1 ／ 範囲: 場所 |
| 壊れた項目 | ここには地の文が書かれていて規定の形ではない |

## 5. 動的な定義
FIXEOF8

  cat > "$d8/docs/design/lists/screen.json" <<'FIXEOF8'
[
  {"種別":"screen","識別子":"src/pages/Broken.tsx","名前":"Broken","場所":"src/pages/Broken.tsx","根拠":"src/pages/Broken.tsx:1","単位の定義":"","属するファイル":[],"分類軸":[]}
]
FIXEOF8

  bash "$SCRIPT_DIR/extract-facts.sh" "$d8" --run "$r8" --kind screen --out "$r8/facts" > "$base/case8.out" 2>"$base/case8.err"
  local rc8=$?
  check "規則-解釈不能: 終了コードが0以外" "$([ "$rc8" -ne 0 ] && echo 0 || echo 1)"

  local agg8_json="$r8/facts/screen/集計.json"
  local agg8_rule_free
  agg8_rule_free="$(jq -c '.["規則の無い項目"]' "$agg8_json" 2>/dev/null)"
  case "$agg8_rule_free" in
    *壊れた項目*) check "規則-解釈不能: 集計の規則の無い項目に列挙される" 0 ;;
    *) check "規則-解釈不能: 集計の規則の無い項目に列挙される" 1 ;;
  esac

  case "$(cat "$base/case8.err")" in
    *"規則-解釈不能"*) check "規則-解釈不能: 標準出力（実行した側が読む位置）に警告が出る" 0 ;;
    *) check "規則-解釈不能: 標準出力（実行した側が読む位置）に警告が出る" 1 ;;
  esac

  local broken_json="$r8/facts/screen/src_pages_Broken.tsx.json"
  local broken_input_values
  broken_input_values="$(jq -c '.["事実"]["入力項目"]["値"]' "$broken_json" 2>/dev/null)"
  check "規則-解釈不能: 規定の形の項目は従来どおり値が埋まる" "$([ "$broken_input_values" = '["orderId"]' ] && echo 0 || echo 1)"

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
