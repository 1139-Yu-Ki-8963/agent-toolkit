#!/usr/bin/env bash
set -euo pipefail

# prefill-design-from-facts.sh — 封印済みfacts.ymlから画面詳細設計書テンプレートへの機械転記（任意工程）
#
# 使い方:
#   prefill-design-from-facts.sh <封印済みfacts.yml> <画面詳細設計書.md>
#   prefill-design-from-facts.sh --self-test
#
# generating-reverse-detailed-design の Phase 4（設計書転記）を補助する任意工程。scaffold直後の
# 画面詳細設計書テンプレートに対し、facts.yml（shared/references/facts-schema.md 準拠の9分類構造）
# の各アイテムを対応する章表へ機械転記する。転記できない列（業務的意味・分類判断等）には
# 【著述・未確認:<章番号>-<種別>】マーカーを置く。
#
# 転記マップ:
#   import      → §15.3 依存（import）一覧
#   export_type → §15.1 ファイル分割（export-* キー）／§15.2 型定義（type-* キー）
#   const       → §10.1 文字列定数（値・evidenceは転記。用途＝業務的意味はマーカー）
#   state       → §5.3 メイン画面の状態変数
#   handler     → §8.1 メイン画面イベント
#   jsx         → §3.2 DOM 配置順序（要素名 — 目的のリスト）
#   style       → §3.6 スタイル適用パターン（数値はDESIGN.md参照キーに実測値を併記）
#   api         → §7.1 API 一覧
#   measurement_pending → §16 要確認事項一覧（固定書式「実測委譲（画面単位検証で確定）」のみ）
#   §6.4 データ更新トリガーの分類／§12.1 遷移先一覧 → handler由来のevidenceのみ補助転記
#     （facts全キー突合のカウント対象外。あくまで補助情報）
#
# 2パス構成:
#   Pass1: facts.yml の各アイテムを1アイテム=1行として対応表へ挿入する（既存プレースホルダ行を
#          置換する。アイテムが0件のセクションは何もせずプレースホルダを残し、Pass2に委ねる）。
#   Pass2: Pass1後もなお残る全てのテンプレート原文プレースホルダ（バッククォート囲み `<...>`）を、
#          章番号付きマーカーへ一括置換する（frontmatter・フェンスコードブロック・HTMLコメント
#          単独行は対象外）。frontmatterは scaffold-screen.sh・Phase4のmeta転記が別途担当する値
#          であり、章番号（§N）という概念が存在しないため本スクリプトのスコープ外とする。
#
# facts.yml の value はプロファイル抽出規約上、自然文（プローズ）で複数情報を1フィールドに
# まとめて記録される（例: 状態変数の型・初期値が1つのvalueに混在）。本スクリプトは value を
# 精密なNLPで分割・再構成することはせず、facts.ymlのキー命名規約（<分類>-<名前>-<補足> の
# 第2セグメントが名前）から名前列を復元し、valueは最も適合する単一カラムへそのまま転記、
# その他のカラム（業務的意味・分類判断等、facts.ymlに存在しない情報）はマーカーとする設計とする。
#
# 依存: yq（あれば使う）→ 無ければ python3+pyyaml（あれば使う）→ いずれも無ければ内蔵awkパーサ。
# facts-schema.md がインデント2スペース固定を契約として明記しており（recount-facts.shと同じ
# 前提）、本スクリプトの実装は常にこの固定インデント前提のawkパーサを使う。yq/pyyamlの検出
# 関数は依存を明示するために用意するが、現行環境ではいずれも未導入（yq未インストール・
# python3にpyyaml未導入）であり実装しても検証できないため、出力契約を変えない高速化の
# 拡張余地としてのみ残す（実処理はawkパーサ経路のみ）。
#
# 保守責任者: 人手（ユーザー）。facts.ymlのスキーマ・画面詳細設計書テンプレートの章構成を
# 変更した時に本スクリプトの転記マップ・アンカー正規表現を追従させる。
# macOS bash 3.2 互換（連想配列・mapfile 不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALL_SECTIONS="import export_type const state handler jsx style api measurement_pending"

have_yq() { command -v yq >/dev/null 2>&1; }
have_pyyaml() { command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; }

# ---- マーカー生成・補助関数 ----

mk_marker() { # $1=章番号 $2=種別ラベル
  printf '【著述・未確認:%s-%s】' "$1" "$2"
}

# キー命名規約（<分類>-<名前>-<補足>）の第nセグメント（1始まり）を取り出す
key_token() { # $1=key $2=セグメント番号(1始まり)
  printf '%s' "$1" | awk -F'-' -v i="$2" '{ if (i<=NF && $i!="") print $i; else print "" }'
}

esc_cell() { # Markdownテーブルセル用にパイプ文字をエスケープする
  printf '%s' "$1" | sed 's/|/\\|/g'
}

# ---- facts.yml パース（awk固定インデント方式。facts-schema.md準拠） ----

extract_items() { # $1=facts.yml $2=対象セクション名 -> key\x01value\x01evidence を1行ずつ出力
  awk -v target="$2" '
    function flush() {
      printf "%s\x01%s\x01%s\n", key, value, evidence
      havekey = 0
    }
    /^sections:/ { insec = 1; next }
    insec && /^  [A-Za-z_]+:[\t ]*$/ {
      if (havekey && cursec == target) flush()
      newsec = $0
      sub(/^  /, "", newsec); sub(/:[\t ]*$/, "", newsec)
      cursec = newsec
      havekey = 0
      next
    }
    cursec != target { next }
    /^      - key:/ {
      if (havekey) flush()
      k = $0; sub(/^      - key:[\t ]*/, "", k); gsub(/^"|"$/, "", k)
      key = k; value = ""; evidence = ""; havekey = 1
      next
    }
    /^        value:/ {
      v = $0; sub(/^        value:[\t ]*/, "", v); gsub(/^"|"$/, "", v)
      value = v
      next
    }
    /^        evidence:/ {
      e = $0; sub(/^        evidence:[\t ]*/, "", e); gsub(/^"|"$/, "", e)
      evidence = e
      next
    }
    END { if (havekey && cursec == target) flush() }
  ' "$1"
}

# 全9分類のアイテム総数（facts全キー突合の基準値）
total_fact_items() { # $1=facts.yml
  local total=0 sec n
  for sec in $ALL_SECTIONS; do
    n="$(extract_items "$1" "$sec" | grep -c . || true)"
    [ -z "$n" ] && n=0
    total=$((total + n))
  done
  printf '%s' "$total"
}

# ---- テーブル行/リスト行の挿入 ----

# アンカー見出し直後の最初のMarkdownテーブル区切り線の次の行（プレースホルダ行）を
# rows_fileの内容（0行なら何もせずプレースホルダのまま残しPass2に委ねる）で置換する。
insert_table_rows() { # $1=infile $2=anchor(ERE) $3=rows_file $4=outfile
  local infile="$1" anchor="$2" rowsfile="$3" outfile="$4"
  awk -v anchor="$anchor" -v rowsfile="$rowsfile" '
    BEGIN {
      state = 0
      nrows = 0
      while ((getline line < rowsfile) > 0) { nrows++; rows[nrows] = line }
      close(rowsfile)
    }
    {
      if (state == 0) {
        print
        if ($0 ~ anchor) state = 1
        next
      }
      if (state == 1) {
        print
        if ($0 ~ /^\|[ \t:|-]+\|[ \t]*$/) state = 2
        next
      }
      if (state == 2) {
        if (nrows > 0) { for (i = 1; i <= nrows; i++) print rows[i] }
        else print
        state = 3
        next
      }
      print
    }
    END {
      if (state == 0) { print "ANCHOR_NOT_FOUND: " anchor > "/dev/stderr"; exit 2 }
      if (state == 1) { print "SEPARATOR_NOT_FOUND_AFTER_ANCHOR: " anchor > "/dev/stderr"; exit 3 }
    }
  ' "$infile" > "$outfile"
}

# アンカー見出し直後の連番リスト（"N. ..." 形式）ブロックをrows_fileの内容で置換する
# （§3.2 DOM配置順序など、テーブルではなくリスト形式のセクション向け）。
insert_list_rows() { # $1=infile $2=anchor(ERE) $3=rows_file(番号なしの本文。連番は本関数が付与) $4=outfile
  local infile="$1" anchor="$2" rowsfile="$3" outfile="$4"
  awk -v anchor="$anchor" -v rowsfile="$rowsfile" '
    BEGIN {
      state = 0
      nrows = 0
      while ((getline line < rowsfile) > 0) { nrows++; rows[nrows] = line }
      close(rowsfile)
    }
    {
      if (state == 0) {
        print
        if ($0 ~ anchor) state = 1
        next
      }
      if (state == 1) {
        if ($0 ~ /^[0-9]+\.[ \t]/) {
          if (nrows > 0) {
            for (i = 1; i <= nrows; i++) printf "%d. %s\n", i, rows[i]
            state = 2
          } else {
            print
            state = 4
          }
          next
        }
        print
        next
      }
      if (state == 2) {
        if ($0 ~ /^[0-9]+\.[ \t]/) next
        state = 3
        print
        next
      }
      if (state == 4) { print; next }
      print
    }
    END {
      if (state == 0) { print "ANCHOR_NOT_FOUND: " anchor > "/dev/stderr"; exit 2 }
    }
  ' "$infile" > "$outfile"
}

# ---- セクション別の行生成 ----

build_rows_import() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name content kind
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$(mk_marker 15 モジュール)"
    content="$value"; [ -z "$content" ] && content="$(mk_marker 15 import内容)"
    kind="$(mk_marker 15 種別)"
    printf '| `%s` | %s | %s |\n' "$(esc_cell "$name")" "$(esc_cell "$content")" "$kind"
  done < <(extract_items "$1" import)
}

build_rows_export_file() { # §15.1（export-* キー。type-* 以外すべて）
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    case "$key" in
      type-*) continue ;;
    esac
    local filepath ename kind shape dir
    filepath="${evidence%%:*}"; [ -z "$filepath" ] && filepath="$(mk_marker 15 ファイルパス)"
    ename="$(key_token "$key" 2)"; [ -z "$ename" ] && ename="$key"
    kind="$(mk_marker 15 種別)"
    shape="$(mk_marker 15 実体形状)"
    dir="$(mk_marker 15 配置ディレクトリ)"
    printf '| `%s` | `%s` | %s | %s | %s |\n' "$(esc_cell "$filepath")" "$(esc_cell "$ename")" "$kind" "$shape" "$dir"
  done < <(extract_items "$1" export_type)
}

build_rows_export_type() { # §15.2（type-* キーのみ）
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    case "$key" in
      type-*) ;;
      *) continue ;;
    esac
    local tname fname ftype req
    tname="$(key_token "$key" 2)"; [ -z "$tname" ] && tname="$(mk_marker 15 型名)"
    fname="$(key_token "$key" 3)"; [ -z "$fname" ] && fname="$(mk_marker 15 フィールド名)"
    ftype="$value"; [ -z "$ftype" ] && ftype="$(mk_marker 15 型)"
    req="$(mk_marker 15 必須任意)"
    printf '| `%s` | `%s` | %s | %s |\n' "$(esc_cell "$tname")" "$(esc_cell "$fname")" "$(esc_cell "$ftype")" "$req"
  done < <(extract_items "$1" export_type)
}

build_rows_const() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name val usage
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$key"
    val="$value"; [ -z "$val" ] && val="$(mk_marker 10 値)"
    [ -n "$evidence" ] && val="${val}（${evidence}）"
    usage="$(mk_marker 10 用途)"
    printf '| `%s` | %s | %s |\n' "$(esc_cell "$name")" "$(esc_cell "$val")" "$usage"
  done < <(extract_items "$1" const)
}

build_rows_state() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name type_col init role
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$key"
    type_col="$(mk_marker 5 型)"
    init="$value"; [ -z "$init" ] && init="$(mk_marker 5 初期値)"
    role="$(mk_marker 5 役割)"
    printf '| `%s` | %s | %s | %s |\n' "$(esc_cell "$name")" "$type_col" "$(esc_cell "$init")" "$role"
  done < <(extract_items "$1" state)
}

build_rows_handler() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name trigger summary
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$key"
    trigger="$(mk_marker 8 発火要素)"
    summary="$value"; [ -z "$summary" ] && summary="$(mk_marker 8 処理概要)"
    printf '| `%s` | %s | %s |\n' "$(esc_cell "$name")" "$trigger" "$(esc_cell "$summary")"
  done < <(extract_items "$1" handler)
}

build_rows_jsx() { # §3.2 DOM配置順序（リスト本文のみ。連番はinsert_list_rowsが付与）
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local purpose
    purpose="$value"; [ -z "$purpose" ] && purpose="$(mk_marker 3 目的)"
    printf '`%s` — %s\n' "$(esc_cell "$key")" "$(esc_cell "$purpose")"
  done < <(extract_items "$1" jsx)
}

build_rows_style() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local area pattern ref
    area="$(key_token "$key" 2)"; [ -z "$area" ] && area="$key"
    pattern="$(mk_marker 3 適用パターン)"
    ref="DESIGN.md > ${key}"
    [ -n "$value" ] && ref="${ref}（実測値: ${value}）"
    printf '| `%s` | %s | %s |\n' "$(esc_cell "$area")" "$pattern" "$(esc_cell "$ref")"
  done < <(extract_items "$1" style)
}

build_rows_api() {
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name no_col method endpoint trigger
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$key"
    no_col="$(mk_marker 7 No)"
    method="$(mk_marker 7 メソッド)"
    endpoint="$(mk_marker 7 エンドポイント)"
    trigger="$value"; [ -z "$trigger" ] && trigger="$(mk_marker 7 呼び出し契機)"
    printf '| %s | `%s` | %s | %s | %s |\n' "$no_col" "$(esc_cell "$name")" "$method" "$endpoint" "$(esc_cell "$trigger")"
  done < <(extract_items "$1" api)
}

build_rows_measurement_pending() { # §16
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local kcol filed content pending_ch resolve
    kcol="mp-${key}"
    filed="$(mk_marker 16 起票日)"
    content="実測委譲（画面単位検証で確定）"
    pending_ch="$(mk_marker 16 暫定扱いにしている§)"
    resolve="$(mk_marker 16 解消条件)"
    printf '| `%s` | %s | %s | %s | %s | 未解消 |\n' "$(esc_cell "$kcol")" "$filed" "$content" "$pending_ch" "$resolve"
  done < <(extract_items "$1" measurement_pending)
}

# 補助転記（facts全キー突合のカウント対象外）: handler由来のevidenceのみ§6.4/§12.1へ転記する
build_rows_dataflow_trigger() { # §6.4
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local name kind summary
    name="$(key_token "$key" 2)"; [ -z "$name" ] && name="$key"
    kind="$(mk_marker 6 種別)"
    summary="$(mk_marker 6 処理概要)"
    [ -n "$evidence" ] && summary="${summary}（evidence: ${evidence}）"
    printf '| `%s` | %s | %s |\n' "$(esc_cell "$name")" "$kind" "$(esc_cell "$summary")"
  done < <(extract_items "$1" handler)
}

build_rows_transition_list() { # §12.1
  while IFS=$'\x01' read -r key value evidence; do
    [ -z "$key" ] && continue
    local dest method cond param
    dest="$(mk_marker 12 遷移先画面)"
    method="$(mk_marker 12 遷移方式)"
    cond="$(mk_marker 12 条件)"
    param="$(mk_marker 12 パラメータ)"
    [ -n "$evidence" ] && param="${param}（evidence: ${evidence}）"
    printf '| %s | %s | %s | %s |\n' "$dest" "$method" "$(esc_cell "$cond")" "$(esc_cell "$param")"
  done < <(extract_items "$1" handler)
}

# ---- Pass1: 転記 ----

pass1_insert() { # $1=facts.yml $2=in_md $3=out_md $4=workdir
  local facts="$1" in_md="$2" out_md="$3" workdir="$4"
  local cur="$in_md" nxt

  build_rows_import "$facts" > "$workdir/rows_import.txt"
  build_rows_export_file "$facts" > "$workdir/rows_export_file.txt"
  build_rows_export_type "$facts" > "$workdir/rows_export_type.txt"
  build_rows_const "$facts" > "$workdir/rows_const.txt"
  build_rows_state "$facts" > "$workdir/rows_state.txt"
  build_rows_handler "$facts" > "$workdir/rows_handler.txt"
  build_rows_jsx "$facts" > "$workdir/rows_jsx.txt"
  build_rows_style "$facts" > "$workdir/rows_style.txt"
  build_rows_api "$facts" > "$workdir/rows_api.txt"
  build_rows_measurement_pending "$facts" > "$workdir/rows_mp.txt"
  build_rows_dataflow_trigger "$facts" > "$workdir/rows_dataflow.txt"
  build_rows_transition_list "$facts" > "$workdir/rows_transition.txt"

  nxt="$workdir/step01.md"; insert_table_rows "$cur" '^### 15\.3 依存' "$workdir/rows_import.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step02.md"; insert_table_rows "$cur" '^### 15\.1 ファイル分割' "$workdir/rows_export_file.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step03.md"; insert_table_rows "$cur" '^### 15\.2 型定義' "$workdir/rows_export_type.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step04.md"; insert_table_rows "$cur" '^### 10\.1 文字列定数' "$workdir/rows_const.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step05.md"; insert_table_rows "$cur" '^### 5\.3 メイン画面の状態変数' "$workdir/rows_state.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step06.md"; insert_table_rows "$cur" '^### 8\.1 メイン画面イベント' "$workdir/rows_handler.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step07.md"; insert_list_rows  "$cur" '^### 3\.2 DOM' "$workdir/rows_jsx.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step08.md"; insert_table_rows "$cur" '^### 3\.6 スタイル適用パターン' "$workdir/rows_style.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step09.md"; insert_table_rows "$cur" '^### 7\.1 API' "$workdir/rows_api.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step10.md"; insert_table_rows "$cur" '^## §16' "$workdir/rows_mp.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step11.md"; insert_table_rows "$cur" '^### 6\.4 データ更新トリガーの分類' "$workdir/rows_dataflow.txt" "$nxt"; cur="$nxt"
  nxt="$workdir/step12.md"; insert_table_rows "$cur" '^### 12\.1 遷移先一覧' "$workdir/rows_transition.txt" "$nxt"; cur="$nxt"

  cp "$cur" "$out_md"
}

# ---- Pass2: 残存プレースホルダの一括マーカー化 ----

pass2_sweep() { # $1=infile $2=outfile
  awk '
    BEGIN { fmseen = 0; fmdone = 0; infence = 0; chapter = "0" }
    {
      line = $0
      if (!fmdone) {
        if (line == "---") {
          fmseen++
          if (fmseen == 2) fmdone = 1
          print line
          next
        }
        print line
        next
      }
      if (line ~ /^```/) { infence = !infence; print line; next }
      if (infence) { print line; next }
      if (line ~ /^[ \t]*<!--.*-->[ \t]*$/) { print line; next }

      if (match(line, /^## §([0-9]+)/)) {
        tmp = line
        sub(/^## §/, "", tmp)
        sub(/[^0-9].*/, "", tmp)
        chapter = tmp
      }

      out = ""
      rest = line
      while (match(rest, /`<[^`>]+>`/)) {
        pre = substr(rest, 1, RSTART - 1)
        matched = substr(rest, RSTART, RLENGTH)
        inner = matched
        sub(/^`</, "", inner)
        sub(/>`$/, "", inner)
        marker = "【著述・未確認:" chapter "-" inner "】"
        out = out pre marker
        rest = substr(rest, RSTART + RLENGTH)
      }
      out = out rest
      print out
    }
  ' "$1" > "$2"
}

count_remaining_placeholders() { # $1=md file （frontmatter・フェンス・HTMLコメントは対象外で数える）
  awk '
    BEGIN { fmseen = 0; fmdone = 0; infence = 0; cnt = 0 }
    {
      line = $0
      if (!fmdone) {
        if (line == "---") { fmseen++; if (fmseen == 2) fmdone = 1; next }
        next
      }
      if (line ~ /^```/) { infence = !infence; next }
      if (infence) next
      if (line ~ /^[ \t]*<!--.*-->[ \t]*$/) next
      rest = line
      while (match(rest, /`<[^`>]+>`/)) {
        cnt++
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    END { print cnt + 0 }
  ' "$1"
}

# ---- 転記サマリ（JSON） ----

print_summary() { # $1=workdir
  local workdir="$1"
  cat "$workdir/rows_export_file.txt" "$workdir/rows_export_type.txt" > "$workdir/rows_export_type_combined.txt"
  local first=1 sec fname n m
  printf '{\n'
  for pair in \
    "import:rows_import" \
    "export_type:rows_export_type_combined" \
    "const:rows_const" \
    "state:rows_state" \
    "handler:rows_handler" \
    "jsx:rows_jsx" \
    "style:rows_style" \
    "api:rows_api" \
    "measurement_pending:rows_mp"
  do
    sec="${pair%%:*}"
    fname="${pair##*:}"
    n="$(grep -c . "$workdir/${fname}.txt" 2>/dev/null || true)"; [ -z "$n" ] && n=0
    m="$(grep -o '【著述・未確認' "$workdir/${fname}.txt" 2>/dev/null | wc -l | tr -d ' ' || true)"; [ -z "$m" ] && m=0
    [ "$first" -eq 1 ] || printf ',\n'
    printf '  "%s": {"rows": %s, "markers": %s}' "$sec" "$n" "$m"
    first=0
  done
  printf '\n}\n'
}

# ---- メイン ----

main() {
  local facts="$1" design_md="$2"
  [ -f "$facts" ] || { echo "エラー: facts.ymlが見つかりません: $facts" >&2; exit 2; }
  [ -f "$design_md" ] || { echo "エラー: 設計書が見つかりません: $design_md" >&2; exit 2; }

  local workdir
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/prefill-design.XXXXXX")"
  trap 'rm -rf "$workdir"' RETURN

  pass1_insert "$facts" "$design_md" "$workdir/pass1.md" "$workdir"
  pass2_sweep "$workdir/pass1.md" "$workdir/pass2.md"

  # 終端self-verify（1: プレースホルダ残存なし　2: facts全キーの転記行数突合）
  local total_facts rows_total remaining n
  total_facts="$(total_fact_items "$facts")"
  rows_total=0
  for f in rows_import rows_const rows_state rows_handler rows_jsx rows_style rows_api rows_mp; do
    n="$(grep -c . "$workdir/${f}.txt" 2>/dev/null || true)"; [ -z "$n" ] && n=0
    rows_total=$((rows_total + n))
  done
  n="$(grep -c . "$workdir/rows_export_file.txt" 2>/dev/null || true)"; [ -z "$n" ] && n=0
  rows_total=$((rows_total + n))
  n="$(grep -c . "$workdir/rows_export_type.txt" 2>/dev/null || true)"; [ -z "$n" ] && n=0
  rows_total=$((rows_total + n))

  remaining="$(count_remaining_placeholders "$workdir/pass2.md")"

  local ok=1
  if [ "$remaining" -ne 0 ]; then
    echo "self-verify失敗: テンプレート原文プレースホルダが${remaining}件残存しています" >&2
    ok=0
  fi
  if [ "$rows_total" -ne "$total_facts" ]; then
    echo "self-verify失敗: facts全キー突合不一致（facts総数=${total_facts} 転記行数=${rows_total}）" >&2
    ok=0
  fi
  if [ "$ok" -ne 1 ]; then
    exit 1
  fi

  cp "$workdir/pass2.md" "$design_md"
  print_summary "$workdir"
}

# ---- 自己テスト ----

self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/prefill-design-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  local rc=0

  local template="$SCRIPT_DIR/../templates/リバース検証/画面/詳細設計/画面詳細設計書.md"
  if [ ! -f "$template" ]; then
    echo "エラー: テンプレートが見つかりません: $template" >&2
    return 2
  fi

  local design_md="$tmp/画面詳細設計書.md"
  cp "$template" "$design_md"

  local facts="$tmp/facts.yml"
  cat > "$facts" <<'YML'
run_id: extract-1
profile: screen
target_repo_path: /abs/path/to/repo
target_file_paths:
  - src/screens/Foo/Foo.tsx
meta:
  source_repo: /abs/path/to/repo
  source_ref: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
  route:
    value: "/foo/:id"
    evidence: "src/router/routes.tsx:42"
sections:
  import:
    reason: ""
    items:
      - key: import-react-useState
        value: "react から useState"
        evidence: "src/screens/Foo/Foo.tsx:1"
  export_type:
    reason: "該当なし（自己テスト用フィクスチャのため省略）"
    items: []
  const:
    reason: ""
    items:
      - key: const-MAX_ROWS-100
        value: "100"
        evidence: "src/screens/Foo/Foo.tsx:4"
  state:
    reason: ""
    items:
      - key: state-rows-empty
        value: "初期値は空配列"
        evidence: "src/screens/Foo/Foo.tsx:8"
  handler:
    reason: ""
    items:
      - key: handler-onRowClick-遷移
        value: "行クリックで詳細画面へ遷移する"
        evidence: "src/screens/Foo/Foo.tsx:12"
  jsx:
    reason: "該当なし（自己テスト用フィクスチャのため省略）"
    items: []
  style:
    reason: "該当なし（自己テスト用フィクスチャのため省略）"
    items: []
  api:
    reason: ""
    items:
      - key: api-fetchReport-req
        value: "初期表示時にレポート一覧を取得する"
        evidence: "src/screens/Foo/Foo.tsx:20"
  measurement_pending:
    reason: ""
    items:
      - key: 初期表示-件数
        evidence: "src/screens/Foo/Foo.tsx:24"
YML

  if bash "$SCRIPT_DIR/prefill-design-from-facts.sh" "$facts" "$design_md" > "$tmp/summary.json" 2> "$tmp/stderr.log"; then
    echo "  [PASS] 実行成功（終端self-verify通過）"
  else
    echo "  [FAIL] 実行失敗（終端self-verifyまたは処理エラー）" >&2
    sed 's/^/    /' "$tmp/stderr.log" >&2
    rc=1
  fi

  extract_section() { # $1=file $2=start anchor(ERE)
    awk -v start="$2" '
      state==0 { if ($0 ~ start) state=1; next }
      state==1 { if ($0 ~ /^#/ || $0 == "---") exit; print }
    ' "$1"
  }

  # 陽性: 各分類が対応章の表へ転記されること
  if extract_section "$design_md" '^### 5\.3' | grep -q '初期値は空配列'; then
    echo "  [PASS] 陽性: state が §5.3 の表へ転記された"
  else
    echo "  [FAIL] 陽性: state が §5.3 の表へ転記されていない" >&2
    rc=1
  fi

  if extract_section "$design_md" '^### 8\.1' | grep -q '行クリックで詳細画面へ遷移する'; then
    echo "  [PASS] 陽性: handler が §8.1 の表へ転記された"
  else
    echo "  [FAIL] 陽性: handler が §8.1 の表へ転記されていない" >&2
    rc=1
  fi

  if extract_section "$design_md" '^### 7\.1' | grep -q '初期表示時にレポート一覧を取得する'; then
    echo "  [PASS] 陽性: api が §7.1 の表へ転記された"
  else
    echo "  [FAIL] 陽性: api が §7.1 の表へ転記されていない" >&2
    rc=1
  fi

  if extract_section "$design_md" '^### 10\.1' | grep -q 'MAX_ROWS' && extract_section "$design_md" '^### 10\.1' | grep -q '100'; then
    echo "  [PASS] 陽性: const が §10.1 の表へ転記された（強化ケース）"
  else
    echo "  [FAIL] 陽性: const が §10.1 の表へ転記されていない" >&2
    rc=1
  fi

  if extract_section "$design_md" '^### 15\.3' | grep -q 'react'; then
    echo "  [PASS] 陽性: import が §15.3 の表へ転記された（強化ケース）"
  else
    echo "  [FAIL] 陽性: import が §15.3 の表へ転記されていない" >&2
    rc=1
  fi

  if extract_section "$design_md" '^## §16' | grep -q 'mp-初期表示-件数' \
    && extract_section "$design_md" '^## §16' | grep -q '実測委譲（画面単位検証で確定）' \
    && extract_section "$design_md" '^## §16' | grep -q '未解消'; then
    echo "  [PASS] 陽性: measurement_pending が §16 へ固定書式で計上された"
  else
    echo "  [FAIL] 陽性: measurement_pending が §16 へ正しく計上されていない" >&2
    rc=1
  fi

  # 陰性: 出力に裸の「-」セル・テンプレート原文プレースホルダが残っていないこと
  if grep -qE '\| *- *\|' "$design_md"; then
    echo "  [FAIL] 陰性: 裸の「-」セルが残存している" >&2
    rc=1
  else
    echo "  [PASS] 陰性: 裸の「-」セルは0件"
  fi

  if grep -qE '`<[^`>]+>`' "$design_md"; then
    echo "  [FAIL] 陰性: テンプレート原文プレースホルダが残存している" >&2
    grep -nE '`<[^`>]+>`' "$design_md" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 陰性: テンプレート原文プレースホルダは0件"
  fi

  # マーカー形式の確認（少なくとも1件は生成されているはず）
  if grep -q '【著述・未確認:' "$design_md"; then
    echo "  [PASS] マーカーが規定書式で挿入されている"
  else
    echo "  [FAIL] マーカーが1件も挿入されていない" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

facts="${1:?使い方: prefill-design-from-facts.sh <封印済みfacts.yml> <画面詳細設計書.md> ／ prefill-design-from-facts.sh --self-test}"
design_md="${2:?使い方: prefill-design-from-facts.sh <封印済みfacts.yml> <画面詳細設計書.md> ／ prefill-design-from-facts.sh --self-test}"
main "$facts" "$design_md"
