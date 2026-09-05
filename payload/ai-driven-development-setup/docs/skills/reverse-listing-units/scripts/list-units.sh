#!/usr/bin/env bash
set -u

# list-units.sh — 調査と検出条件の定義書（reverse-writing-survey-definition の成果物）の検出条件を実行し、
# 対象リポジトリを走査して種別ごとの単位の一覧と元データを作る。
#
# 目的:
#   調査と検出条件の定義書の節「単位の見つけ方」にある検出条件（```json 検出条件``` の囲み）を
#   1つずつ実行し、種別（screen/api/table/batch/report/external/feature）ごとに
#   単位を数える。言語やフレームワークごとの分岐は持たない。見つけ方は調査と検出条件の定義書が
#   持つ検出条件がすべてを決める。
#
# 使い方:
#   list-units.sh <対象リポジトリのルート> [--design-root <設計書の置き場>] [--map <調査と検出条件の定義書のパス>] [--out <出力先フォルダ>] [--tolerance <0〜1の小数>]
#   list-units.sh --self-test
#
# --design-root の既定は <対象リポジトリのルート>。--map・--out の既定はこの値の配下。
# --map の既定は <対象>/docs/design/common/調査と検出条件の定義書.md。
# --out の既定は <対象>/docs/design/lists。
# --tolerance の既定は 0.2。
#
# 調査と検出条件の定義書の節0「文字コード」がUTF-8でない場合、走査対象ファイルはiconvでUTF-8に
# 変換してから照合する。変換に失敗したファイルは警告として記録し照合から外す。
#
# 調査と検出条件の定義書の節9「到達範囲」を読み、`json 検出条件` の囲みを持たない種別（一覧化が
# 「対象外」または「AI の読み取り」の種別）も集計へ書く。対象外は判定と対象外の理由を、AI の読み取り
# は読みの一致（値は空。手で埋める）を持たせる。集計を書き出す前に既存の一覧の集計.jsonを読み、
# 囲みを持たない種別（到達範囲の対象外・AI の読み取り）に限り、実行器が作らない鍵（読みの一致の値等）
# を引き継ぐ。これにより同じ入力で何度実行しても到達範囲の記録が消えない（冪等）。
# 囲みを持つ種別（`json 検出条件` の対象、$all_species に含まれる種別）は、種別が対象外・AI の
# 読み取りから機械へ切り替わったとき旧い到達範囲・対象外の理由の鍵を残さないよう、今回の実測を
# 丸ごと採用し既存の値と合成しない。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   検出条件-形式    ```json 検出条件``` の囲みがJSONとして読めない、または
#                    種別が不正、または分割が「一致」なのに単位:trueの一致が無い
#   走査-不在        走査.含む のフォルダが対象配下に実在しない
#   例-不在          例に挙げた相対パスが、出力した単位の場所にすべて現れない
#   候補数-差        |実測−候補数| / max(候補数,1) が --tolerance を超える
#   識別子-捕捉不能  識別子の正規表現が単位の行に一致しなかった（警告。不合格にはしない）
#   文字コード-変換失敗  走査対象ファイルの文字コード変換に失敗した（警告。不合格にはしない）
#
# 判定:
#   種別ごとに、上記のうち 検出条件-形式・走査-不在・例-不在 のいずれかがあれば
#   不合格。無く、候補数が調査と検出条件の定義書に無ければ 候補数無し。無く、候補数があれば
#   候補数-差 が無いときに限り合格、あるときは不合格。
#
# 終了コード:
#   0 = 全種別が合格または候補数無し
#   1 = 1種別以上が不合格
#   2 = 使い方の誤り・調査と検出条件の定義書不在・出力先を作れない・囲みが1つも無い（判定不能）
#
# 保守責任者: 人手（ユーザー）。検出条件の形（項目・書き方）を変えるときは、
#   調査と検出条件の定義書の様式（reverse-writing-survey-definition）と本スクリプトと自己テストを同時に直す。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage_error() {
  echo "使い方: list-units.sh <対象リポジトリのルート> [--design-root <設計書の置き場>] [--map <調査と検出条件の定義書のパス>] [--out <出力先フォルダ>] [--tolerance <0〜1の小数>]" >&2
  echo "        list-units.sh --self-test" >&2
  exit 2
}

# --- 日本語種別名の対応 ---
species_ja() {
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

is_valid_species() {
  case "$1" in
    screen|api|table|batch|report|external|feature) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 日本語種別名からの逆引き ---
species_from_ja() {
  case "$1" in
    画面) echo "screen" ;;
    接続窓口) echo "api" ;;
    表) echo "table" ;;
    バッチ) echo "batch" ;;
    帳票) echo "report" ;;
    外部連携) echo "external" ;;
    機能) echo "feature" ;;
    *) echo "" ;;
  esac
}

# --- 種別が all_species（既に囲みで処理済みの種別一覧、空白区切り）に含まれるかを判定する ---
species_already_covered() {
  local target="$1" list="$2" s
  for s in $list; do
    [ "$s" = "$target" ] && return 0
  done
  return 1
}

# --- 調査と検出条件の定義書の節9「到達範囲」の表を読み、
#     "種別の英字<TAB>一覧化の値<TAB>理由" の行を返す（種別の日本語が
#     species_from_ja で解決できない行は捨てる） ---
read_reach_rows() {
  local map="$1" line in_section=0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      '## '*)
        case "$line" in
          *到達範囲*) in_section=1 ;;
          *) in_section=0 ;;
        esac
        continue
        ;;
    esac
    [ "$in_section" -eq 1 ] || continue
    case "$line" in
      '|'*) : ;;
      *) continue ;;
    esac
    case "$line" in
      *---*) continue ;;
    esac
    local ja reach reason species
    ja="$(printf '%s' "$line" | awk -F'|' '{print $2}')"
    reach="$(printf '%s' "$line" | awk -F'|' '{print $3}')"
    reason="$(printf '%s' "$line" | awk -F'|' '{print $7}')"
    ja="$(trim "$ja")"
    reach="$(trim "$reach")"
    reason="$(trim "$reason")"
    [ "$ja" = "種別" ] && continue
    species="$(species_from_ja "$ja")"
    [ -n "$species" ] || continue
    printf '%s\t%s\t%s\n' "$species" "$reach" "$reason"
  done < "$map"
}

# --- グロブをPOSIX拡張正規表現へ変換（**は任意階層、*は/を含まない任意文字列） ---
glob_to_regex() {
  local g="$1" esc
  esc="$g"
  esc="${esc//./\\.}"
  esc="${esc//\*\*/@@DOUBLESTAR@@}"
  esc="${esc//\*/[^/]*}"
  esc="${esc//@@DOUBLESTAR@@/.*}"
  printf '^%s$' "$esc"
}

# --- 走査対象ファイル一覧を作る（対象配下の相対パスの配列を返す） ---
# 使い方: collect_files <target> <block-json> <out-var用の一時ファイル>
collect_files() {
  local target="$1" blockfile="$2" outfile="$3"
  : > "$outfile"
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -d "$target/$d" ]; then
      find "$target/$d" -type f 2>/dev/null >> "$outfile"
    fi
  done < <(jq -r '.["走査"]["含む"][]? // empty' "$blockfile" 2>/dev/null)
}

# --- 走査.含む の不在フォルダを検出する。1件でもあれば標準出力へフォルダ名を出す ---
missing_scan_dirs() {
  local target="$1" blockfile="$2" d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$target/$d" ] || echo "$d"
  done < <(jq -r '.["走査"]["含む"][]? // empty' "$blockfile" 2>/dev/null)
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# --- 調査と検出条件の定義書の節0にある「文字コード」の値を読む。無ければUTF-8とみなす。
# 注意: このマシンのawk（bwk awk）は非ASCII文字列同士の==比較が常にtrueを
# 返す既知の不具合があるため、行の特定はgrep -E（バイト一致・空白の揺れを許容）で行う。
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

# --- 文字コードがUTF-8でない場合、ファイルをUTF-8化した一時ファイルのパスを
# 返す（キャッシュ済みなら再利用する）。変換に失敗すれば空文字を返し終了コード
# 1を返す（呼び出し側で「文字コード-変換失敗」を記録し、そのファイルを照合か
# ら外す） ---
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

# --- 候補数の表（candidate_rows.txt: "日本語種別名<TAB>概数"）から、指定した
# 日本語種別名の概数を合計して返す。無ければ空文字を返す。
# 注意: このマシンのawk（bwk awk）は非ASCII文字列同士の==比較が常にtrueを
# 返す既知の不具合があるため、種別名の一致判定はbashの文字列比較で行う。
lookup_candidate() {
  local file="$1" ja="$2" sum=0 found=0 f1 f2
  [ -f "$file" ] || { printf ''; return; }
  while IFS=$'\t' read -r f1 f2; do
    [ -n "$f1" ] || continue
    if [ "$f1" = "$ja" ]; then
      found=1
      sum=$((sum + f2))
    fi
  done < "$file"
  if [ "$found" -eq 1 ]; then
    printf '%s' "$sum"
  else
    printf ''
  fi
}

# --- 内容/ファイル名に対する正規表現から、1番目の捕捉を取り出す ---
# 見つからなければ空を返す（呼び出し側で捕捉不能を判定する）
capture_group1() {
  local content="$1" regex="$2" matched cap
  matched="$(printf '%s' "$content" | grep -oE "$regex" | head -n1)"
  [ -n "$matched" ] || { printf ''; return; }
  cap="$(printf '%s' "$matched" | sed -E "s/^${regex}\$/\\1/")"
  if [ "$cap" = "$matched" ]; then
    printf ''
  else
    printf '%s' "$cap"
  fi
}

# --- 除外の一致（表の削除を辿る等）を対象ファイル群に当て、捕捉した識別子の
#     一覧を返す（改行区切り、重複あり得る）。捕捉の既定は1 ---
excluded_identifiers_for_block() {
  local blockfile="$1" fileslist="$2" charset="$3" cache_dir="$4"
  local count
  count="$(jq '(.["除外の一致"] // []) | length' "$blockfile")"
  [ "${count:-0}" -gt 0 ] 2>/dev/null || return 0
  local i
  for i in $(seq 0 $((count - 1))); do
    local target_field regex capture
    target_field="$(jq -r ".[\"除外の一致\"][$i][\"対象\"] // \"内容\"" "$blockfile")"
    regex="$(jq -r ".[\"除外の一致\"][$i][\"正規表現\"] // empty" "$blockfile")"
    capture="$(jq -r ".[\"除外の一致\"][$i][\"捕捉\"] // 1" "$blockfile")"
    [ -n "$regex" ] || continue
    local f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$target_field" = "ファイル名" ]; then
        printf '%s\n' "$(basename "$f")" | grep -oE "$regex" | sed -E "s/^${regex}\$/\\${capture}/"
      else
        local cf
        if cf="$(utf8_path_for "$f" "$charset" "$cache_dir")" && [ -n "$cf" ]; then
          grep -oE "$regex" "$cf" 2>/dev/null | sed -E "s/^${regex}\$/\\${capture}/"
        fi
      fi
    done < "$fileslist"
  done
}

# --- 1単位をJSON行としてoutfileへ追記する（キーは日本語だがjqの識別子構文に
#     使えないため、jqフィルタ内はすべて.["key"]形式で参照する）。v_supplementが
#     "true"のとき、元データに"補完":trueを写す（候補数の突き合わせには含めない） ---
emit_unit() {
  local v_type="$1" v_id="$2" v_name="$3" v_place="$4" v_basis="$5"
  local v_def="$6" v_belongs="$7" v_axis="$8" v_supplement="$9" outfile="${10}"
  if [ "$v_supplement" = "true" ]; then
    jq -nc --arg v_type "$v_type" --arg v_id "$v_id" --arg v_name "$v_name" \
      --arg v_place "$v_place" --arg v_basis "$v_basis" \
      --argjson v_def "$v_def" --argjson v_belongs "$v_belongs" --argjson v_axis "$v_axis" \
      '{"種別": $v_type, "識別子": $v_id, "名前": $v_name, "場所": $v_place, "根拠": $v_basis, "単位の定義": $v_def, "属するファイル": $v_belongs, "分類軸": $v_axis, "補完": true}' \
      >> "$outfile"
  else
    jq -nc --arg v_type "$v_type" --arg v_id "$v_id" --arg v_name "$v_name" \
      --arg v_place "$v_place" --arg v_basis "$v_basis" \
      --argjson v_def "$v_def" --argjson v_belongs "$v_belongs" --argjson v_axis "$v_axis" \
      '{"種別": $v_type, "識別子": $v_id, "名前": $v_name, "場所": $v_place, "根拠": $v_basis, "単位の定義": $v_def, "属するファイル": $v_belongs, "分類軸": $v_axis}' \
      >> "$outfile"
  fi
}

# ============================================================
# 本処理
# ============================================================

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local design_root="$target"
  local scan_args=("$@") scan_i=0
  while [ $scan_i -lt ${#scan_args[@]} ]; do
    if [ "${scan_args[$scan_i]}" = "--design-root" ]; then
      design_root="${scan_args[$((scan_i+1))]}"
    fi
    scan_i=$((scan_i+1))
  done

  local map="${design_root%/}/docs/design/common/調査と検出条件の定義書.md"
  local out="${design_root%/}/docs/design/lists"
  local tolerance="0.2"

  while [ $# -gt 0 ]; do
    case "$1" in
      --map) map="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --tolerance) tolerance="$2"; shift 2 ;;
      --design-root) shift 2 ;;
      *) usage_error ;;
    esac
  done

  if [ ! -f "$map" ]; then
    echo "[FAIL] 調査と検出条件の定義書-不在: ${map} が存在しません" >&2
    exit 2
  fi

  mkdir -p "$out" 2>/dev/null
  if [ ! -d "$out" ]; then
    echo "[FAIL] 出力先-作成不能: ${out} を作れません" >&2
    exit 2
  fi

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/list-units.XXXXXX")" || { echo "[FAIL] 一時領域-作成不能" >&2; exit 2; }
  trap 'rm -rf "$work"' EXIT

  mkdir -p "$work/blocks"

  local charset
  charset="$(read_charset "$map")"
  local charset_cache="$work/charset-cache"
  mkdir -p "$charset_cache"

  # --- 検出条件の囲みを取り出す ---
  awk -v dir="$work/blocks" '
    /^```json[ \t]+検出条件[ \t]*$/ { infile=1; n++; fname=dir "/block-" n ".json"; next }
    infile && /^```[ \t]*$/ { infile=0; close(fname); next }
    infile { print >> fname }
  ' "$map"

  local n_blocks
  n_blocks="$(find "$work/blocks" -type f -name 'block-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n_blocks" -eq 0 ]; then
    echo "[FAIL] 検出条件-無し: ${map} に \`\`\`json 検出条件\`\`\` の囲みがありません" >&2
    exit 2
  fi

  # --- 候補数の表を読む ---
  # 注意: このマシンのawk（bwk awk 20200816）は非ASCII文字列同士の==比較が
  # 常にtrueを返す既知の不具合があるため、見出し行の検出はawkの==ではなく
  # grep -Fx（バイト一致）で行い、以降はNR（数値）比較だけをawkへ渡す。
  local header_line
  header_line="$(tr -d '\r' < "$map" | grep -n -F -x '| 種別 | 領域 | 概数 | 数え方 |' | head -n1 | cut -d: -f1)"
  : > "$work/candidate_rows.raw"
  if [ -n "$header_line" ]; then
    local candidate_start=$((header_line + 2))
    awk -v start="$candidate_start" '
      { line=$0; gsub(/\r$/, "", line) }
      NR < start { next }
      { if (line !~ /^\|/) { exit } print line }
    ' "$map" >> "$work/candidate_rows.raw"
  fi

  : > "$work/candidate_rows.txt"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local ja cnt
    ja="$(printf '%s' "$row" | awk -F'|' '{print $2}')"
    cnt="$(printf '%s' "$row" | awk -F'|' '{print $4}')"
    ja="$(trim "$ja")"
    cnt="$(trim "$cnt")"
    printf '%s\t%s\n' "$ja" "$cnt" >> "$work/candidate_rows.txt"
  done < "$work/candidate_rows.raw"

  # --- 検出条件ごとに処理する ---
  local blockfile species raw_species
  for blockfile in "$work"/blocks/block-*.json; do
    [ -f "$blockfile" ] || continue

    raw_species="$(grep -oE '"種別"[[:space:]]*:[[:space:]]*"[^"]*"' "$blockfile" | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"

    if ! jq -e . "$blockfile" >/dev/null 2>&1; then
      local key="${raw_species:-_不明}"
      echo "検出条件-形式" >> "$work/reasons-${key}.txt"
      continue
    fi

    species="$(jq -r '.["種別"] // empty' "$blockfile")"
    if ! is_valid_species "$species"; then
      local key="${raw_species:-_不明}"
      echo "検出条件-形式" >> "$work/reasons-${key}.txt"
      continue
    fi

    local supplement
    supplement="$(jq -r '.["補完"] // false' "$blockfile")"

    # 走査の不在チェック
    local missing
    missing="$(missing_scan_dirs "$target" "$blockfile")"
    if [ -n "$missing" ]; then
      echo "走査-不在" >> "$work/reasons-${species}.txt"
    fi

    # ファイル一覧の収集
    local files_txt="$work/files-${species}.txt"
    collect_files "$target" "$blockfile" "$files_txt"

    # 拡張子フィルタ
    local ext_list
    ext_list="$(jq -r '.["走査"]["拡張子"][]? // empty' "$blockfile")"
    if [ -n "$ext_list" ]; then
      local tmp_files="${files_txt}.ext"
      : > "$tmp_files"
      local f keep e
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        keep=0
        while IFS= read -r e; do
          [ -n "$e" ] || continue
          case "$f" in *"$e") keep=1 ;; esac
        done <<EXTS
$ext_list
EXTS
        [ "$keep" -eq 1 ] && echo "$f" >> "$tmp_files"
      done < "$files_txt"
      mv "$tmp_files" "$files_txt"
    fi

    # 除外グロブフィルタ
    local exclude_list
    exclude_list="$(jq -r '.["走査"]["除く"][]? // empty' "$blockfile")"
    if [ -n "$exclude_list" ]; then
      local tmp_files="${files_txt}.exc"
      : > "$tmp_files"
      local f rel excluded g rgx
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#$target/}"
        excluded=0
        while IFS= read -r g; do
          [ -n "$g" ] || continue
          rgx="$(glob_to_regex "$g")"
          if printf '%s' "$rel" | grep -qE "$rgx"; then excluded=1; break; fi
        done <<GLOBS
$exclude_list
GLOBS
        [ "$excluded" -eq 0 ] && echo "$f" >> "$tmp_files"
      done < "$files_txt"
      mv "$tmp_files" "$files_txt"
    fi

    # 除外の一致で使う走査対象ファイル全体（一致フィルタ前のスナップショット）
    local prematch_files="$work/prematch-${species}.txt"
    cp "$files_txt" "$prematch_files"

    # 一致フィルタ（すべて満たすファイルだけ残す。単位:trueの一致を控える）
    local match_count unit_target_type="" unit_regex=""
    match_count="$(jq -r '.["一致"] | length // 0' "$blockfile")"
    local i target_type regex is_unit
    i=0
    while [ "$i" -lt "$match_count" ]; do
      target_type="$(jq -r ".[\"一致\"][$i][\"対象\"]" "$blockfile")"
      regex="$(jq -r ".[\"一致\"][$i][\"正規表現\"]" "$blockfile")"
      is_unit="$(jq -r ".[\"一致\"][$i][\"単位\"] // false" "$blockfile")"

      local tmp_files="${files_txt}.match${i}"
      : > "$tmp_files"
      local f bn cf
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ "$target_type" = "ファイル名" ]; then
          bn="$(basename "$f")"
          if printf '%s' "$bn" | grep -qE "$regex"; then echo "$f" >> "$tmp_files"; fi
        else
          if cf="$(utf8_path_for "$f" "$charset" "$charset_cache")" && [ -n "$cf" ]; then
            if grep -qE "$regex" "$cf" 2>/dev/null; then echo "$f" >> "$tmp_files"; fi
          else
            echo "文字コード-変換失敗" >> "$work/reasons-${species}.warn"
          fi
        fi
      done < "$files_txt"
      mv "$tmp_files" "$files_txt"

      if [ "$is_unit" = "true" ]; then
        unit_target_type="$target_type"
        unit_regex="$regex"
      fi
      i=$((i + 1))
    done

    local split
    split="$(jq -r '.["分割"]' "$blockfile")"
    if [ "$split" = "一致" ] && [ -z "$unit_regex" ]; then
      echo "検出条件-形式" >> "$work/reasons-${species}.txt"
      continue
    fi

    # 識別子・名前の設定
    local id_source id_regex name_source name_regex
    id_source="$(jq -r '.["識別子"]["元"] // "ファイルパス"' "$blockfile")"
    id_regex="$(jq -r '.["識別子"]["正規表現"] // empty' "$blockfile")"
    name_source="$(jq -r '.["名前"]["元"] // "識別子"' "$blockfile")"
    name_regex="$(jq -r '.["名前"]["正規表現"] // empty' "$blockfile")"

    local unit_def belongs_json axis_json
    unit_def="$(jq -c '.["単位の定義"] // ""' "$blockfile")"
    belongs_json="$(jq -c '.["属するファイル"] // []' "$blockfile")"
    axis_json="$(jq -c '.["分類軸"] // []' "$blockfile")"

    # 単位を作る
    local f rel lineno content id name cap cf
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#$target/}"

      if [ "$split" = "ファイル" ]; then
        if cf="$(utf8_path_for "$f" "$charset" "$charset_cache")" && [ -n "$cf" ]; then
          content="$(cat "$cf" 2>/dev/null)"
        else
          echo "文字コード-変換失敗" >> "$work/reasons-${species}.warn"
          continue
        fi
        lineno=1

        if [ "$id_source" = "一致の捕捉" ]; then
          cap="$(capture_group1 "$content" "$id_regex")"
          if [ -n "$cap" ]; then id="$cap"; else id="${rel}:${lineno}"; echo "識別子-捕捉不能" >> "$work/reasons-${species}.warn"; fi
        else
          id="$rel"
        fi

        if [ "$name_source" = "ファイル名" ]; then
          local bn="$(basename "$f")"
          name="${bn%.*}"
        elif [ "$name_source" = "内容" ]; then
          cap="$(capture_group1 "$content" "$name_regex")"
          if [ -n "$cap" ]; then name="$cap"; else name="$id"; fi
        else
          name="$id"
        fi

        emit_unit "$species" "$id" "$name" "$rel" "${rel}:${lineno}" \
          "$unit_def" "$belongs_json" "$axis_json" "$supplement" "$work/units-${species}.jsonl"

      else
        # 分割が「一致」
        if [ "$unit_target_type" = "内容" ]; then
          if cf="$(utf8_path_for "$f" "$charset" "$charset_cache")" && [ -n "$cf" ]; then
          while IFS= read -r matchline; do
            [ -n "$matchline" ] || continue
            lineno="${matchline%%:*}"
            content="${matchline#*:}"

            if [ "$id_source" = "一致の捕捉" ]; then
              cap="$(capture_group1 "$content" "$id_regex")"
              if [ -n "$cap" ]; then id="$cap"; else id="${rel}:${lineno}"; echo "識別子-捕捉不能" >> "$work/reasons-${species}.warn"; fi
            else
              id="${rel}:${lineno}"
            fi

            if [ "$name_source" = "ファイル名" ]; then
              local bn2="$(basename "$f")"
              name="${bn2%.*}"
            elif [ "$name_source" = "内容" ]; then
              cap="$(capture_group1 "$content" "$name_regex")"
              if [ -n "$cap" ]; then name="$cap"; else name="$id"; fi
            else
              name="$id"
            fi

            emit_unit "$species" "$id" "$name" "$rel" "${rel}:${lineno}" \
              "$unit_def" "$belongs_json" "$axis_json" "$supplement" "$work/units-${species}.jsonl"
          done < <(grep -nE "$unit_regex" "$cf" 2>/dev/null)
          else
            echo "文字コード-変換失敗" >> "$work/reasons-${species}.warn"
          fi
        else
          # 対象がファイル名の一致を単位に使う稀なケース：1ファイル1単位（行1）扱い
          lineno=1
          content="$(basename "$f")"
          if [ "$id_source" = "一致の捕捉" ]; then
            cap="$(capture_group1 "$content" "$id_regex")"
            if [ -n "$cap" ]; then id="$cap"; else id="${rel}:${lineno}"; echo "識別子-捕捉不能" >> "$work/reasons-${species}.warn"; fi
          else
            id="${rel}:${lineno}"
          fi
          name="$id"
          emit_unit "$species" "$id" "$name" "$rel" "${rel}:${lineno}" \
            "$unit_def" "$belongs_json" "$axis_json" "$supplement" "$work/units-${species}.jsonl"
        fi
      fi
    done < "$files_txt"

    # 除外の一致の適用（表の削除を辿る等。捕捉した識別子と同じ単位を結果から除く）
    local excluded_ids
    excluded_ids="$(excluded_identifiers_for_block "$blockfile" "$prematch_files" "$charset" "$charset_cache" | sort -u)"
    if [ -n "$excluded_ids" ]; then
      local eid
      while IFS= read -r eid; do
        [ -n "$eid" ] || continue
        local tmp_units="${work}/units-${species}.jsonl.tmp"
        jq -c --arg id "$eid" 'select(.["識別子"] != $id)' "$work/units-${species}.jsonl" > "$tmp_units" 2>/dev/null
        mv "$tmp_units" "$work/units-${species}.jsonl"
      done <<< "$excluded_ids"
    fi

    # 例の確認
    local ex
    while IFS= read -r ex; do
      [ -n "$ex" ] || continue
      echo "$ex" >> "$work/examples-${species}.txt"
    done < <(jq -r '.["例"][]? // empty' "$blockfile")
  done

  # --- 種別ごとに出力を作る ---
  local all_species
  all_species="$( (find "$work" -maxdepth 1 -name 'units-*.jsonl' -o -maxdepth 1 -name 'reasons-*.txt' -o -maxdepth 1 -name 'examples-*.txt' 2>/dev/null) \
    | sed -E 's#.*/(units|reasons|examples)-##; s/\.(jsonl|txt)$//' | sort -u)"

  : > "$work/agg.jsonl"
  local fail_n=0 ok_n=0

  for species in $all_species; do
    local units_file="$work/units-${species}.jsonl"
    local actual=0
    if [ -f "$units_file" ]; then
      actual="$(jq -s '[.[] | select(.["補完"] != true)] | length' "$units_file")"
      jq -s 'sort_by(.["識別子"])' "$units_file" > "$out/${species}.json"
    else
      echo "[]" > "$out/${species}.json"
    fi

    local ja
    ja="$(species_ja "$species")"
    {
      echo "# ${ja}一覧"
      echo ""
      echo "| 識別子 | 名前 | 場所 | 根拠 |"
      echo "|---|---|---|---|"
      jq -r '.[] | "| " + .["識別子"] + " | " + .["名前"] + " | " + .["場所"] + " | " + .["根拠"] + " |"' "$out/${species}.json"
    } > "$out/${species}.md"

    # 例-不在チェック
    if [ -f "$work/examples-${species}.txt" ]; then
      local ex found
      while IFS= read -r ex; do
        [ -n "$ex" ] || continue
        found="$(jq --arg e "$ex" '[.[] | select(.["場所"] == $e)] | length' "$out/${species}.json")"
        if [ "$found" -eq 0 ]; then
          echo "例-不在" >> "$work/reasons-${species}.txt"
        fi
      done < "$work/examples-${species}.txt"
    fi

    local candidate
    candidate="$(lookup_candidate "$work/candidate_rows.txt" "$ja")"

    local reasons_json="[]"
    if [ -f "$work/reasons-${species}.txt" ]; then
      reasons_json="$(sort -u "$work/reasons-${species}.txt" | jq -R -s -c 'split("\n") | map(select(length>0))')"
    fi

    local id_capture_fail=0
    if [ -f "$work/reasons-${species}.warn" ]; then
      id_capture_fail="$(grep -c "識別子-捕捉不能" "$work/reasons-${species}.warn" || true)"
    fi
    if [ "${id_capture_fail:-0}" -gt 0 ] 2>/dev/null; then
      echo "警告: ${species} は識別子の捕捉に失敗した単位が ${id_capture_fail} 件あります" >&2
    fi

    local hard_fail=0
    case "$reasons_json" in
      *検出条件-形式*|*走査-不在*|*例-不在*) hard_fail=1 ;;
    esac

    local candidate_json ratio_json verdict
    if [ -z "$candidate" ]; then
      candidate_json="null"
      ratio_json="null"
      if [ "$hard_fail" -eq 1 ]; then
        verdict="不合格"
      else
        verdict="候補数無し"
      fi
    else
      candidate_json="$candidate"
      ratio_json="$(awk -v a="$actual" -v c="$candidate" 'BEGIN{d=a-c; if(d<0)d=-d; denom=(c>1?c:1); printf "%.4f", d/denom}')"
      local over
      over="$(awk -v r="$ratio_json" -v t="$tolerance" 'BEGIN{print (r>t)?1:0}')"
      if [ "$over" -eq 1 ]; then
        reasons_json="$(printf '%s\n候補数-差' "$(printf '%s' "$reasons_json" | jq -r '.[]')" | sort -u | jq -R -s -c 'split("\n") | map(select(length>0))')"
        verdict="不合格"
      elif [ "$hard_fail" -eq 1 ]; then
        verdict="不合格"
      else
        verdict="合格"
      fi
    fi

    if [ "$verdict" = "不合格" ]; then
      fail_n=$((fail_n + 1))
    else
      ok_n=$((ok_n + 1))
    fi

    echo "${species}: 実測=${actual} 候補数=${candidate:-無し} 判定=${verdict}"

    local entry wrapped
    entry="$(jq -n --argjson v_actual "$actual" --argjson v_candidate "$candidate_json" --argjson v_ratio "$ratio_json" \
      --arg v_verdict "$verdict" --argjson v_reasons "$reasons_json" \
      --argjson v_id_capture_fail "${id_capture_fail:-0}" \
      '{"実測": $v_actual, "候補数": $v_candidate, "差の割合": $v_ratio, "判定": $v_verdict, "不合格の理由": $v_reasons, "識別子捕捉不能件数": $v_id_capture_fail}')"
    wrapped="$(jq -n --arg k "$species" --argjson v "$entry" '{($k): $v}')"
    echo "$wrapped" >> "$work/agg.jsonl"
  done

  # --- 到達範囲の表を読み、囲みを持たない種別（対象外・AI の読み取り）も集計へ書く ---
  local oos_n=0 ai_n=0
  local reach_species reach_status reach_reason
  while IFS=$'\t' read -r reach_species reach_status reach_reason; do
    [ -n "$reach_species" ] || continue
    species_already_covered "$reach_species" "$all_species" && continue

    case "$reach_status" in
      対象外*)
        local entry_oos wrapped_oos
        entry_oos="$(jq -n --arg reason "$reach_reason" \
          '{"実測":0,"候補数":0,"差の割合":0.0000,"判定":"対象外","不合格の理由":[],"識別子捕捉不能件数":0,"到達範囲":"対象外","対象外の理由":$reason}')"
        wrapped_oos="$(jq -n --arg k "$reach_species" --argjson v "$entry_oos" '{($k): $v}')"
        echo "$wrapped_oos" >> "$work/agg.jsonl"
        oos_n=$((oos_n + 1))
        ;;
      AI*)
        local candidate_ai candidate_ai_json entry_ai wrapped_ai
        candidate_ai="$(lookup_candidate "$work/candidate_rows.txt" "$(species_ja "$reach_species")")"
        if [ -z "$candidate_ai" ]; then candidate_ai_json="null"; else candidate_ai_json="$candidate_ai"; fi
        entry_ai="$(jq -n --argjson cand "$candidate_ai_json" \
          '{"実測":0,"候補数":$cand,"差の割合":null,"判定":"AI の読み取り","不合格の理由":[],"識別子捕捉不能件数":0,"到達範囲":"AI の読み取り","読みの一致":""}')"
        wrapped_ai="$(jq -n --arg k "$reach_species" --argjson v "$entry_ai" '{($k): $v}')"
        echo "$wrapped_ai" >> "$work/agg.jsonl"
        ai_n=$((ai_n + 1))
        ;;
      *)
        : # 機械なのに囲みが無い種別は、従来どおり集計へ載せない
        ;;
    esac
  done < <(read_reach_rows "$map")

  # --- 既存の一覧の集計.jsonを読み、実行器が作らない鍵（読みの一致の値等）を引き継いで書き出す ---
  # `json 検出条件`の囲みを持つ種別（$all_speciesに含まれる種別）は、今回の
  # 実測を丸ごと採用する（旧い到達範囲・対象外の理由の鍵を残さない）。
  # 囲みを持たない種別（到達範囲の対象外・AIの読み取り）だけ、既存の値を
  # 引き継ぐ合成を行う。
  local new_agg covered_json
  new_agg="$(jq -s 'add // {}' "$work/agg.jsonl")"
  covered_json="$(printf '%s\n' "$all_species" | jq -R -s -c 'split("\n") | map(select(length>0))')"
  if [ -f "$out/一覧の集計.json" ] && jq -e . "$out/一覧の集計.json" > /dev/null 2>&1; then
    jq -n --argjson old "$(cat "$out/一覧の集計.json")" --argjson new "$new_agg" --argjson covered "$covered_json" '
      $new | with_entries(
        .key as $k
        | ($old[$k] // {}) as $o
        | .value as $n_full
        | (.value | with_entries(select(.key != "読みの一致" or .value != ""))) as $n
        | if ($covered | index($k)) then
            .value = $n_full
          else
            (.value = ($o + $n))
            | if (($new[$k] | has("読みの一致")) and ((.value | has("読みの一致")) | not)) then .value["読みの一致"] = "" else . end
          end
      )' > "$out/一覧の集計.json"
  else
    printf '%s\n' "$new_agg" > "$out/一覧の集計.json"
  fi

  echo "合格 ${ok_n} 種別 / 不合格 ${fail_n} 種別"
  if [ $((oos_n + ai_n)) -gt 0 ]; then
    echo "到達範囲の対象外 ${oos_n} 種別 / AI の読み取り ${ai_n} 種別"
  fi

  if [ "$fail_n" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/list-units-self-test.XXXXXX")" || { echo "[FAIL] 自己テスト用一時領域を作れません"; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

  make_fixture() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d/src/pages/__tests__" "$d/src/api" "$d/db/migrations" "$d/docs/design/common"

    cat > "$d/src/pages/OrderList.tsx" <<'EOF'
export default function OrderList() {
  return null;
}
EOF
    cat > "$d/src/pages/OrderDetail.tsx" <<'EOF'
export default function OrderDetail() {
  return null;
}
EOF
    cat > "$d/src/pages/__tests__/OrderList.test.tsx" <<'EOF'
export default function OrderListTest() {
  return null;
}
EOF
    cat > "$d/src/api/orders.ts" <<'EOF'
router.get('/orders', listOrders);
router.post('/orders', createOrder);
router.get('/orders/:id', getOrder);
EOF
    cat > "$d/db/migrations/001_orders.sql" <<'EOF'
CREATE TABLE orders (id integer, name text);
EOF
    cat > "$d/README.md" <<'EOF'
# サンプル
EOF

    cat > "$d/docs/design/common/調査と検出条件の定義書.md" <<'EOF'
# 調査と検出条件の定義書

## 単位の見つけ方

```json 検出条件
{
  "種別": "screen",
  "単位の定義": "1 つの経路に対応する画面の部品を 1 つと数える",
  "走査": { "含む": ["src/pages"], "除く": ["**/__tests__/**"], "拡張子": [".tsx"] },
  "一致": [
    { "対象": "内容", "正規表現": "export default function", "単位": true }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["src/pages/OrderList.tsx"]
}
```

```json 検出条件
{
  "種別": "api",
  "単位の定義": "1 つの経路を 1 つと数える",
  "走査": { "含む": ["src/api"], "除く": [], "拡張子": [".ts"] },
  "一致": [
    { "対象": "内容", "正規表現": "router\\.(get|post)\\('([^']+)'", "単位": true }
  ],
  "分割": "一致",
  "識別子": { "元": "一致の捕捉", "正規表現": "'([^']+)'" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["src/api/orders.ts"]
}
```

```json 検出条件
{
  "種別": "table",
  "単位の定義": "1 つのテーブル定義を 1 つと数える",
  "走査": { "含む": ["db/migrations"], "除く": [], "拡張子": [".sql"] },
  "一致": [
    { "対象": "内容", "正規表現": "CREATE TABLE ([a-z_]+)", "単位": true }
  ],
  "分割": "一致",
  "識別子": { "元": "一致の捕捉", "正規表現": "CREATE TABLE ([a-z_]+)" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["db/migrations/001_orders.sql"]
}
```

### 候補数

| 種別 | 領域 | 概数 | 数え方 |
|---|---|---|---|
| 画面 | 受注 | 2 | 経路単位 |
| 接続窓口 | 受注 | 3 | 経路単位 |
| 表 | 受注 | 1 | テーブル単位 |
EOF
  }

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

  # --- 合格-見本 ---
  local d1="$base/case1"
  make_fixture "$d1"
  bash "$SCRIPT_DIR/list-units.sh" "$d1" --out "$d1/docs/design/lists" > "$base/case1.out" 2>"$base/case1.err"
  local rc1=$?
  local screen_n api_n table_n
  screen_n="$(jq 'length' "$d1/docs/design/lists/screen.json" 2>/dev/null || echo -1)"
  api_n="$(jq 'length' "$d1/docs/design/lists/api.json" 2>/dev/null || echo -1)"
  table_n="$(jq 'length' "$d1/docs/design/lists/table.json" 2>/dev/null || echo -1)"
  check "合格-見本: 終了コード0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
  check "合格-見本: screen 2件" "$([ "$screen_n" -eq 2 ] && echo 0 || echo 1)"
  check "合格-見本: api 3件" "$([ "$api_n" -eq 3 ] && echo 0 || echo 1)"
  check "合格-見本: table 1件" "$([ "$table_n" -eq 1 ] && echo 0 || echo 1)"

  # --- 不合格-候補数の差 ---
  local d2="$base/case2"
  make_fixture "$d2"
  sed -i.bak 's/| 画面 | 受注 | 2 | 経路単位 |/| 画面 | 受注 | 10 | 経路単位 |/' "$d2/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d2" --out "$d2/docs/design/lists" > "$base/case2.out" 2>"$base/case2.err"
  local rc2=$?
  local screen_verdict
  screen_verdict="$(jq -r '.screen["判定"]' "$d2/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "不合格-候補数の差: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"
  check "不合格-候補数の差: screen判定が不合格" "$([ "$screen_verdict" = "不合格" ] && echo 0 || echo 1)"

  # --- 不合格-例の不在 ---
  local d3="$base/case3"
  make_fixture "$d3"
  sed -i.bak 's#"例": \["src/pages/OrderList.tsx"\]#"例": ["src/pages/Missing.tsx"]#' "$d3/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d3" --out "$d3/docs/design/lists" > "$base/case3.out" 2>"$base/case3.err"
  local rc3=$?
  local screen_reasons3
  screen_reasons3="$(jq -c '.screen["不合格の理由"]' "$d3/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "不合格-例の不在: 終了コード1" "$([ "$rc3" -eq 1 ] && echo 0 || echo 1)"
  case "$screen_reasons3" in
    *例-不在*) check "不合格-例の不在: 理由に例-不在" 0 ;;
    *) check "不合格-例の不在: 理由に例-不在" 1 ;;
  esac

  # --- 不合格-形式 ---
  local d4="$base/case4"
  make_fixture "$d4"
  sed -i.bak 's/"種別": "table",/"種別": "table"/' "$d4/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d4" --out "$d4/docs/design/lists" > "$base/case4.out" 2>"$base/case4.err"
  local rc4=$?
  local table_reasons4
  table_reasons4="$(jq -c '.table["不合格の理由"]' "$d4/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "不合格-形式: 終了コード1" "$([ "$rc4" -eq 1 ] && echo 0 || echo 1)"
  case "$table_reasons4" in
    *検出条件-形式*) check "不合格-形式: 理由に検出条件-形式" 0 ;;
    *) check "不合格-形式: 理由に検出条件-形式" 1 ;;
  esac

  # --- 候補数無し ---
  local d5="$base/case5"
  make_fixture "$d5"
  awk '
    /^### 候補数$/ { skip=1; next }
    skip && (/^$/ || /^\|/) { next }
    { skip=0; print }
  ' "$d5/docs/design/common/調査と検出条件の定義書.md" > "$d5/docs/design/common/調査と検出条件の定義書.md.new"
  mv "$d5/docs/design/common/調査と検出条件の定義書.md.new" "$d5/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d5" --out "$d5/docs/design/lists" > "$base/case5.out" 2>"$base/case5.err"
  local rc5=$?
  local screen_verdict5 api_verdict5 table_verdict5
  screen_verdict5="$(jq -r '.screen["判定"]' "$d5/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  api_verdict5="$(jq -r '.api["判定"]' "$d5/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  table_verdict5="$(jq -r '.table["判定"]' "$d5/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "候補数無し: 終了コード0" "$([ "$rc5" -eq 0 ] && echo 0 || echo 1)"
  check "候補数無し: 3種別とも候補数無し" "$([ "$screen_verdict5" = "候補数無し" ] && [ "$api_verdict5" = "候補数無し" ] && [ "$table_verdict5" = "候補数無し" ] && echo 0 || echo 1)"

  # --- 使い方-調査と検出条件の定義書不在 ---
  local d6="$base/case6"
  make_fixture "$d6"
  bash "$SCRIPT_DIR/list-units.sh" "$d6" --map "$d6/docs/design/common/存在しない.md" --out "$d6/docs/design/lists" > "$base/case6.out" 2>"$base/case6.err"
  local rc6=$?
  check "使い方-調査と検出条件の定義書不在: 終了コード2" "$([ "$rc6" -eq 2 ] && echo 0 || echo 1)"

  # --- 名前の捕捉 ---
  local d7="$base/case7"
  make_fixture "$d7"
  sed -i.bak 's/  "名前": { "元": "識別子" },\n/&/' "$d7/docs/design/common/調査と検出条件の定義書.md" 2>/dev/null
  perl -0pi -e 's/("種別": "screen",.*?)"名前": \{ "元": "識別子" \},/$1"名前": { "元": "内容", "正規表現": "title=\\"([^\\"]+)\\"" },/s' "$d7/docs/design/common/調査と検出条件の定義書.md" 2>/dev/null
  cat >> "$d7/src/pages/OrderList.tsx" <<'EOF'
// title="受注一覧"
EOF
  bash "$SCRIPT_DIR/list-units.sh" "$d7" --out "$d7/docs/design/lists" > "$base/case7.out" 2>"$base/case7.err"
  local rc7=$?
  local name7
  name7="$(jq -r '.[] | select(.["場所"]=="src/pages/OrderList.tsx") | .["名前"]' "$d7/docs/design/lists/screen.json" 2>/dev/null)"
  check "名前の捕捉: 終了コード0" "$([ "$rc7" -eq 0 ] && echo 0 || echo 1)"
  check "名前の捕捉: OrderListの名前が受注一覧" "$([ "$name7" = "受注一覧" ] && echo 0 || echo 1)"

  # --- 除外の一致-削除された表 ---
  local d8="$base/case8"
  make_fixture "$d8"
  cat > "$d8/db/migrations/002_more.sql" <<'EOF2'
CREATE TABLE customers (id integer, name text);
CREATE TABLE products (id integer, name text);
EOF2
  cat > "$d8/db/migrations/003_drop.sql" <<'EOF2'
DROP TABLE customers;
EOF2
  perl -0pi -e 's/("種別": "table",.*?)"例": \["db\/migrations\/001_orders.sql"\]/$1"除外の一致": [{ "対象": "内容", "正規表現": "DROP TABLE[[:space:]]+(IF EXISTS[[:space:]]+)?([a-z_]+)", "捕捉": 2 }],\n  "例": ["db\/migrations\/001_orders.sql"]/s' "$d8/docs/design/common/調査と検出条件の定義書.md"
  sed -i.bak 's/| 表 | 受注 | 1 | テーブル単位 |/| 表 | 受注 | 2 | テーブル単位 |/' "$d8/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d8" --out "$d8/docs/design/lists" > "$base/case8.out" 2>"$base/case8.err"
  local rc8=$?
  local table_n8
  table_n8="$(jq 'length' "$d8/docs/design/lists/table.json" 2>/dev/null || echo -1)"
  check "除外の一致-削除された表: 終了コード0" "$([ "$rc8" -eq 0 ] && echo 0 || echo 1)"
  check "除外の一致-削除された表: table 2件" "$([ "$table_n8" -eq 2 ] && echo 0 || echo 1)"

  # --- 補完-合算しない ---
  local d9="$base/case9"
  make_fixture "$d9"
  mkdir -p "$d9/src/legacy"
  cat > "$d9/src/legacy/OldScreen.tsx" <<'EOF2'
export default function OldScreen() {
  return null;
}
EOF2
  cat >> "$d9/docs/design/common/調査と検出条件の定義書.md" <<'EOF2'

```json 検出条件
{
  "種別": "screen",
  "補完": true,
  "単位の定義": "AI が読んで補う画面を 1 つと数える",
  "走査": { "含む": ["src/legacy"], "除く": [], "拡張子": [".tsx"] },
  "一致": [
    { "対象": "内容", "正規表現": "export default function", "単位": true }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["src/legacy/OldScreen.tsx"]
}
```
EOF2
  bash "$SCRIPT_DIR/list-units.sh" "$d9" --out "$d9/docs/design/lists" > "$base/case9.out" 2>"$base/case9.err"
  local rc9=$?
  local screen_n9 screen_actual9
  screen_n9="$(jq 'length' "$d9/docs/design/lists/screen.json" 2>/dev/null || echo -1)"
  screen_actual9="$(jq -r '.screen["実測"]' "$d9/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "補完-合算しない: 終了コード0" "$([ "$rc9" -eq 0 ] && echo 0 || echo 1)"
  check "補完-合算しない: screen一覧は3件" "$([ "$screen_n9" -eq 3 ] && echo 0 || echo 1)"
  check "補完-合算しない: 実測は2件" "$([ "$screen_actual9" -eq 2 ] && echo 0 || echo 1)"

  # --- 文字コード-EUC-JP ---
  local d10="$base/case10"
  make_fixture "$d10"
  mkdir -p "$d10/src/legacy-jp"
  printf 'export default function OrderJP() {\n  // 受注一覧\n  return null;\n}\n' \
    | iconv -f UTF-8 -t EUC-JP > "$d10/src/legacy-jp/OrderJP.tsx"
  cat >> "$d10/docs/design/common/調査と検出条件の定義書.md" <<'EOF2'

```json 検出条件
{
  "種別": "feature",
  "単位の定義": "日本語コメントを含むファイルを1つと数える",
  "走査": { "含む": ["src/legacy-jp"], "除く": [], "拡張子": [".tsx"] },
  "一致": [
    { "対象": "内容", "正規表現": "受注一覧", "単位": true }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["src/legacy-jp/OrderJP.tsx"]
}
```
EOF2
  {
    echo '| 文字コード | EUC-JP |'
    cat "$d10/docs/design/common/調査と検出条件の定義書.md"
  } > "${d10}/docs/design/common/調査と検出条件の定義書.md.new"
  mv "${d10}/docs/design/common/調査と検出条件の定義書.md.new" "$d10/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d10" --out "$d10/docs/design/lists" > "$base/case10.out" 2>"$base/case10.err"
  local rc10=$?
  local feature_n10
  feature_n10="$(jq 'length' "$d10/docs/design/lists/feature.json" 2>/dev/null || echo -1)"
  check "文字コード-EUC-JP: 終了コード0" "$([ "$rc10" -eq 0 ] && echo 0 || echo 1)"
  check "文字コード-EUC-JP: featureが1件（EUC-JPを変換して日本語一致）" "$([ "$feature_n10" -eq 1 ] && echo 0 || echo 1)"

  # --- 文字コード行-空白揺れ（パイプ直後に空白が無い記法も読める） ---
  local d11="$base/case11"
  make_fixture "$d11"
  mkdir -p "$d11/src/legacy-jp"
  printf 'export default function OrderJP() {\n  // 受注一覧\n  return null;\n}\n' \
    | iconv -f UTF-8 -t EUC-JP > "$d11/src/legacy-jp/OrderJP.tsx"
  cat >> "$d11/docs/design/common/調査と検出条件の定義書.md" <<'EOF2'

```json 検出条件
{
  "種別": "feature",
  "単位の定義": "日本語コメントを含むファイルを1つと数える",
  "走査": { "含む": ["src/legacy-jp"], "除く": [], "拡張子": [".tsx"] },
  "一致": [
    { "対象": "内容", "正規表現": "受注一覧", "単位": true }
  ],
  "分割": "ファイル",
  "識別子": { "元": "ファイルパス" },
  "名前": { "元": "識別子" },
  "属するファイル": [],
  "分類軸": [],
  "例": ["src/legacy-jp/OrderJP.tsx"]
}
```
EOF2
  {
    echo '|文字コード|EUC-JP|'
    cat "$d11/docs/design/common/調査と検出条件の定義書.md"
  } > "${d11}/docs/design/common/調査と検出条件の定義書.md.new"
  mv "${d11}/docs/design/common/調査と検出条件の定義書.md.new" "$d11/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d11" --out "$d11/docs/design/lists" > "$base/case11.out" 2>"$base/case11.err"
  local rc11=$?
  local feature_n11
  feature_n11="$(jq 'length' "$d11/docs/design/lists/feature.json" 2>/dev/null || echo -1)"
  check "文字コード行-空白揺れ: 終了コード0" "$([ "$rc11" -eq 0 ] && echo 0 || echo 1)"
  check "文字コード行-空白揺れ: featureが1件（パイプ直後空白無しでも変換される）" "$([ "$feature_n11" -eq 1 ] && echo 0 || echo 1)"



  # --- 識別子-捕捉不能の警告 ---
  local d12="$base/case12"
  make_fixture "$d12"
  sed -i.bak 's/"識別子": { "元": "一致の捕捉", "正規表現": "CREATE TABLE (\[a-z_\]+)" },/"識別子": { "元": "一致の捕捉", "正規表現": "CREATE TABLE_X (\[a-z_\]+)" },/' "$d12/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d12" --out "$d12/docs/design/lists" > "$base/case12.out" 2>"$base/case12.err"
  local rc12=$?
  local table_capture_fail12
  table_capture_fail12="$(jq -r '.table["識別子捕捉不能件数"]' "$d12/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "識別子-捕捉不能: 標準出力に警告が出る" "$(grep -q "識別子の捕捉に失敗" "$base/case12.err" && echo 0 || echo 1)"
  check "識別子-捕捉不能: 一覧の集計.jsonに件数が載る" "$([ "${table_capture_fail12:-0}" -gt 0 ] 2>/dev/null && echo 0 || echo 1)"

  # --- 到達範囲-対象外とAIの読み取りが集計から消えない ---
  local d13="$base/case13"
  make_fixture "$d13"
  cat >> "$d13/docs/design/common/調査と検出条件の定義書.md" <<'EOF2'

## 9. 到達範囲

| 種別 | 一覧化 | 読み取り結果の取り出し | 基本設計 | 詳細設計 | 理由 |
|---|---|---|---|---|---|
| 画面 | 機械 | 機械 | 機械 | 機械 | 画面の部品がある |
| 接続窓口 | 機械 | 機械 | 機械 | 機械 | 経路の定義がある |
| 表 | 機械 | 機械 | 機械 | 機械 | 移行の定義がある |
| バッチ | 対象外 | 対象外 | 対象外 | 対象外 | 定期実行の処理が無い |
| 帳票 | 対象外 | 対象外 | 対象外 | 対象外 | 帳票を出す記述が無い |
| 外部連携 | AI の読み取り | AI の読み取り | AI の読み取り | AI の読み取り | 通信の呼び出しを読んで判断する |
| 機能 | AI の読み取り | AI の読み取り | AI の読み取り | AI の読み取り | 設定表を読んで判断する |
EOF2
  bash "$SCRIPT_DIR/list-units.sh" "$d13" --out "$d13/docs/design/lists" > "$base/case13-1.out" 2>"$base/case13-1.err"
  local rc13_1=$?
  local batch_verdict13 batch_reason13 external_reach13 external_yomi13
  batch_verdict13="$(jq -r '.batch["判定"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  batch_reason13="$(jq -r '.batch["対象外の理由"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  external_reach13="$(jq -r '.external["到達範囲"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  external_yomi13="$(jq -r '.external["読みの一致"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "到達範囲-対象外とAIの読み取り: 終了コード0" "$([ "$rc13_1" -eq 0 ] && echo 0 || echo 1)"
  check "到達範囲-対象外とAIの読み取り: 標準出力に集計行が出る" "$(grep -q "到達範囲の対象外 2 種別 / AI の読み取り 2 種別" "$base/case13-1.out" && echo 0 || echo 1)"
  check "到達範囲-対象外とAIの読み取り: batchが対象外でbatchの理由が一致" "$([ "$batch_verdict13" = "対象外" ] && [ "$batch_reason13" = "定期実行の処理が無い" ] && echo 0 || echo 1)"
  check "到達範囲-対象外とAIの読み取り: externalがAIの読み取りで読みの一致が空" "$([ "$external_reach13" = "AI の読み取り" ] && [ "$external_yomi13" = "" ] && echo 0 || echo 1)"

  cp "$d13/docs/design/lists/一覧の集計.json" "$base/case13-agg-1.json"
  bash "$SCRIPT_DIR/list-units.sh" "$d13" --out "$d13/docs/design/lists" > "$base/case13-2.out" 2>"$base/case13-2.err"
  local rc13_2=$?
  check "到達範囲-2回実行で集計が同一: 終了コード0" "$([ "$rc13_2" -eq 0 ] && echo 0 || echo 1)"
  check "到達範囲-2回実行で集計が同一: diffが0行" "$(diff "$base/case13-agg-1.json" "$d13/docs/design/lists/一覧の集計.json" > /dev/null 2>&1 && echo 0 || echo 1)"

  local tmp_agg13="$d13/docs/design/lists/一覧の集計.json.tmp"
  jq '.external["読みの一致"] = "2 回の読みが一致"' "$d13/docs/design/lists/一覧の集計.json" > "$tmp_agg13"
  mv "$tmp_agg13" "$d13/docs/design/lists/一覧の集計.json"
  bash "$SCRIPT_DIR/list-units.sh" "$d13" --out "$d13/docs/design/lists" > "$base/case13-3.out" 2>"$base/case13-3.err"
  local rc13_3=$?
  local external_yomi13_3 batch_reason13_3
  external_yomi13_3="$(jq -r '.external["読みの一致"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  batch_reason13_3="$(jq -r '.batch["対象外の理由"]' "$d13/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "到達範囲-読みの一致が再実行で残る: 終了コード0" "$([ "$rc13_3" -eq 0 ] && echo 0 || echo 1)"
  check "到達範囲-読みの一致が再実行で残る: 値が保持される" "$([ "$external_yomi13_3" = "2 回の読みが一致" ] && echo 0 || echo 1)"
  check "到達範囲-読みの一致が再実行で残る: batchの理由も残る" "$([ "$batch_reason13_3" = "定期実行の処理が無い" ] && echo 0 || echo 1)"

  # --- 遷移-対象外から機械へ切り替わった種別に旧い鍵が残らない ---
  local d14="$base/case14"
  make_fixture "$d14"
  # 表のjson検出条件の囲みを外し、節9で表を対象外にする
  perl -0pi -e 's/```json 検出条件\n\{\n  "種別": "table".*?\n```\n\n//s' "$d14/docs/design/common/調査と検出条件の定義書.md"
  cat >> "$d14/docs/design/common/調査と検出条件の定義書.md" <<'EOF4'

## 9. 到達範囲

| 種別 | 一覧化 | 読み取り結果の取り出し | 基本設計 | 詳細設計 | 理由 |
|---|---|---|---|---|---|
| 画面 | 機械 | 機械 | 機械 | 機械 | 画面の部品がある |
| 接続窓口 | 機械 | 機械 | 機械 | 機械 | 経路の定義がある |
| 表 | 対象外 | 対象外 | 対象外 | 対象外 | 検証用 |
EOF4
  bash "$SCRIPT_DIR/list-units.sh" "$d14" --out "$d14/docs/design/lists" > "$base/case14-1.out" 2>"$base/case14-1.err"
  local rc14_1=$?
  local table_reach14_1
  table_reach14_1="$(jq -r '.table["到達範囲"]' "$d14/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "遷移-対象外から機械へ: 1回目は対象外として集計に載る" "$([ "$rc14_1" -eq 0 ] && [ "$table_reach14_1" = "対象外" ] && echo 0 || echo 1)"

  # 表のjson検出条件の囲みを戻し、節9も機械にする
  perl -0pi -e 's/\n### 候補数/\n```json 検出条件\n{\n  "種別": "table",\n  "単位の定義": "1 つのテーブル定義を 1 つと数える",\n  "走査": { "含む": ["db\/migrations"], "除く": [], "拡張子": [".sql"] },\n  "一致": [\n    { "対象": "内容", "正規表現": "CREATE TABLE ([a-z_]+)", "単位": true }\n  ],\n  "分割": "一致",\n  "識別子": { "元": "一致の捕捉", "正規表現": "CREATE TABLE ([a-z_]+)" },\n  "名前": { "元": "識別子" },\n  "属するファイル": [],\n  "分類軸": [],\n  "例": ["db\/migrations\/001_orders.sql"]\n}\n```\n\n### 候補数/s' "$d14/docs/design/common/調査と検出条件の定義書.md"
  sed -i.bak 's/| 表 | 対象外 | 対象外 | 対象外 | 対象外 | 検証用 |/| 表 | 機械 | 機械 | 機械 | 機械 | 検証用 |/' "$d14/docs/design/common/調査と検出条件の定義書.md"
  bash "$SCRIPT_DIR/list-units.sh" "$d14" --out "$d14/docs/design/lists" > "$base/case14-2.out" 2>"$base/case14-2.err"
  local rc14_2=$?
  local table_has_reach14_2 table_has_oosreason14_2
  table_has_reach14_2="$(jq -r '.table | has("到達範囲")' "$d14/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  table_has_oosreason14_2="$(jq -r '.table | has("対象外の理由")' "$d14/docs/design/lists/一覧の集計.json" 2>/dev/null)"
  check "遷移-対象外から機械へ: 2回目は終了コード0" "$([ "$rc14_2" -eq 0 ] && echo 0 || echo 1)"
  check "遷移-対象外から機械へ: 2回目は到達範囲・対象外の理由の鍵が残らない" "$([ "$table_has_reach14_2" = "false" ] && [ "$table_has_oosreason14_2" = "false" ] && echo 0 || echo 1)"

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
