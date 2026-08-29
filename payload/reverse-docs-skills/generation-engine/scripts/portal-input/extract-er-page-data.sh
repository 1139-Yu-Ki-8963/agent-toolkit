#!/usr/bin/env bash
# extract-er-page-data.sh — テーブル定義書.md §5.3 外部キーから er 用の
# page-data.json（entities[]/relations[]）を機械的に組み立てる
#
# 背景(改善課題1-26 段階2。docs/tasks/関連図の内製化の指示書.md 5節 段階2):
# ER図の生成(build-detail-page.sh --page er)はpage-data.jsonを要求するが、
# これまでこの入力データを組み立てる決定的な経路が存在せず、
# generating-er-diagram-for-reverse-docsスキルの対話的な抽出(Claude自身のRead/Write)にのみ
# 依存していた。テーブル定義書.md §5.3外部キーには元々「出典参照」「関連の種別」の列が無く、
# 文書だけからは復元できなかったため、段階2では2列をテンプレートへ追加したうえで、
# 本スクリプトがその列を機械的に読み、page-data.jsonを組み立てる決定的な処理を提供する。
#
# Usage:
#   extract-er-page-data.sh <output_dir> <出力page-data.jsonのパス>
#   extract-er-page-data.sh --self-test
#
#   <output_dir>                テーブル定義書.md が展開済みのプロジェクトルート
#                                (output-layout.json の tableUnitRoot を <output_dir> からの
#                                相対で解決する)
#   <出力page-data.jsonのパス>   組み立てた page-data.json を書き出すファイルパス
#
# テーブル定義書.md が0件、または §6.3 外部キーのデータ行が0件(雛形のプレースホルダ行のみを
# 含む状態)の場合は、entities/relationsが可能な範囲で空(または部分的)のpage-data.jsonを書き出し、
# WARNをstderrへ出してexit 0で終える(build-manifests-from-docs.shの0件時フェイルセーフと同じ設計。
# 関連を捏造しない)。
#
# from(参照元テーブル)は現在のテーブル定義書自身のtable_key。
# to(参照先テーブル)は §6.3「参照先のテーブル」セルの値を、収集済み全テーブルの
# table_key/table_nameのいずれかと突き合わせて解決する(段階2着手時点でこの列に
# table_key(物理名寄りのslug)とtable_name(日本語表示名)のどちらが書かれるかの慣行が
# このリポジトリ内に確立していなかったため、両方を解決対象にする設計とした)。
# 解決できない場合はrelations[]へ加えず、unresolved[]へ理由付きで記録する
# (validate-page-data.shの孤児参照検査はrelations[]内の未解決参照を許さないため)。
#
# 設計判断の正本: docs/design/generation-engine/portal-input/詳細設計書.md
# 「## extract-er-page-data.sh」節。
# 保守責任者: 人手(ユーザー)。テーブル定義書.md §5.3 の列構成を変える場合は本ファイルと
# self-test を同時に更新する。
# macOS bash 3.2 互換(mapfile / declare -A 不使用)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"

# frontmatter(YAML先頭の --- 区切りブロック)から指定キーの値を1行取り出す。
# 見つからなければ空文字を返す。値の前後の空白は取り除く。
# (build-manifests-from-docs.sh の同名関数と同じ実装。命名慣行を揃え新しい形を発明しない)
extract_frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { delim = 0; infm = 0 }
    /^---[ \t]*$/ {
      delim++
      if (delim == 1) { infm = 1; next }
      if (delim == 2) { infm = 0; exit }
    }
    infm == 1 {
      if ($0 ~ "^"key"[ \t]*:") {
        line = $0
        sub("^"key"[ \t]*:[ \t]*", "", line)
        sub("[ \t]+$", "", line)
        print line
        exit
      }
    }
  ' "$file"
}

# テーブル定義書.md から §6.3 外部キーのデータ行を
# TSV(column\ttarget\ttargetcol\tondelete\tcardinality\tsourceRef)として抽出する。
#
# 見出しの一致は「### 6.3 外部キー」で始まる行の前方一致とする。次の見出し(## または ###)で
# 節を抜ける。プレースホルダ行(いずれかの列に<実測: ...>を含む雛形の行)は除外する(捏造しない)。
# 既存文書が旧4列(カラム/参照先のテーブル/参照先のカラム/削除時の動作)のままの場合も
# 読めるよう、6列に満たない行はcardinality/sourceRefを空文字として扱う。
extract_fk_rows() {
  local doc_file="$1"
  awk '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function strip_backtick(s) {
      gsub(/^`+|`+$/, "", s)
      return s
    }
    BEGIN { in_section = 0; header_seen = 0 }
    /^#{2,3} / {
      if (in_section == 1) { exit }
      in_section = ($0 ~ /^### [0-9]+\.3 外部キー/) ? 1 : 0
      next
    }
    in_section == 0 { next }
    /^\|---/ { header_seen = 1; next }
    /^\|/ {
      if (header_seen == 0) { next }  # 列名行(ヘッダ)はスキップ。区切り行の後だけデータ行を採る
      line = $0
      sub(/^\|/, "", line)
      sub(/\|[ \t]*$/, "", line)
      n = split(line, cols, "|")
      if (n < 4) { next }
      column = strip_backtick(trim(cols[1]))
      target = strip_backtick(trim(cols[2]))
      targetcol = strip_backtick(trim(cols[3]))
      ondelete = strip_backtick(trim(cols[4]))
      cardinality = (n >= 5) ? strip_backtick(trim(cols[5])) : ""
      sourceref = (n >= 6) ? strip_backtick(trim(cols[6])) : ""
      if (column ~ /<実測/ || target ~ /<実測/ || targetcol ~ /<実測/ || ondelete ~ /<実測/ || cardinality ~ /<実測/ || sourceref ~ /<実測/) { next }
      if (column == "" || target == "") { next }
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", column, target, targetcol, ondelete, cardinality, sourceref
    }
  ' "$doc_file"
}

run() {
  local output_dir="$1" dest_file="$2"
  local layout_json table_unit_rel root_dir
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/extract-er-page-data.XXXXXX")" || return 1
  trap 'rm -rf "$work"' RETURN
  layout_json="$(resolve_output_layout "$output_dir")" || return 1
  table_unit_rel="$(output_layout_get "$layout_json" tableUnitRoot)" || return 1
  root_dir="$output_dir/$table_unit_rel"

  local table_files=""
  if [ -d "$root_dir" ]; then
    table_files="$(find "$root_dir" -type f -name "テーブル定義書.md" | sort)"
  fi

  if [ -z "$table_files" ]; then
    echo "WARN: テーブル定義書.md が見つかりません: $root_dir" >&2
  fi

  # entities_json: [{key,label}] を発見順(sort済みファイル順)で組み立てる
  # relation_rows_tsv: from\tcolumn\ttarget\ttargetcol\tondelete\tcardinality\tsourceRef
  local entities_json="[]" relation_rows_tsv=""
  local file table_key table_name
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    table_key="$(extract_frontmatter_value "$file" "table_key")"
    table_name="$(extract_frontmatter_value "$file" "table_name")"
    if [ -z "$table_name" ]; then table_name="$table_key"; fi
    if [ -z "$table_key" ]; then
      echo "WARN: table_key が空のためスキップします: $file" >&2
      continue
    fi
    entities_json="$(printf '%s' "$entities_json" | jq --arg key "$table_key" --arg label "$table_name" '. + [{key: $key, label: $label}]')" || return 1

    local rows_tsv fk_source
    # 改善課題1-288: 外部キーの表はテーブル実装記録.md（§2.3）へ移った。実装記録があればそちらを読み、無ければ定義書を読む。
    fk_source="$(dirname "$file")/テーブル実装記録.md"
    [ -f "$fk_source" ] || fk_source="$file"
    rows_tsv="$(extract_fk_rows "$fk_source")"
    if [ -n "$rows_tsv" ]; then
      while IFS=$'\t' read -r column target targetcol ondelete cardinality sourceref; do
        [ -z "$column" ] && continue
        relation_rows_tsv="${relation_rows_tsv}${table_key}	${column}	${target}	${targetcol}	${ondelete}	${cardinality}	${sourceref}
"
      done < <(printf '%s\n' "$rows_tsv")
    fi
  done < <(printf '%s\n' "$table_files")

  if [ -z "$relation_rows_tsv" ]; then
    echo "WARN: §6.3 外部キーのデータ行が0件でした(捏造せず空のrelationsを書き出す): $root_dir" >&2
  fi

  # relation_rows_json: [{from,column,target,targetCol,onDelete,cardinality,sourceRef}]
  local relation_rows_json
  relation_rows_json="$(printf '%s' "$relation_rows_tsv" | jq -R -s '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({from: .[0], column: .[1], target: .[2], targetCol: .[3], onDelete: .[4], cardinality: (.[5] // ""), sourceRef: (.[6] // "")})
  ')" || return 1

  # target(参照先のテーブルセルの値)を、収集済みentitiesのkey/nameいずれかと突き合わせて
  # table_keyへ解決する。解決できない行はrelationsへ加えずunresolvedへ回す。
  # entities/rowsはテーブル・外部キーの件数に比例して増えうる可変長の値であり、
  # --argjsonへ直接展開するとjqの引数長上限を超えうる。一時ファイル経由の
  # --slurpfileで渡す(extract-table-metadata.shのmainColumns対策と同じ設計)。
  local entities_file="$work/entities.json" relation_rows_file="$work/rows.json"
  printf '%s' "$entities_json" > "$entities_file"
  printf '%s' "$relation_rows_json" > "$relation_rows_file"
  local result_json
  result_json="$(jq -n --slurpfile entities "$entities_file" --slurpfile rows "$relation_rows_file" '
    ($entities[0] | map({(.key): .key}) | add // {}) as $byKey
    | ($entities[0] | map({(.label): .key}) | add // {}) as $byLabel
    | ($byKey * $byLabel) as $resolve
    | reduce $rows[0][] as $r (
        {relations: [], unresolved: []};
        ($resolve[$r.target] // null) as $to
        | if $to != null then
            .relations += [{from: $r.from, to: $to, cardinality: $r.cardinality, sourceRef: $r.sourceRef}]
          else
            .unresolved += [{
              label: ($r.from + "." + $r.column + " → " + $r.target),
              reason: "参照先テーブルが見つかりません(テーブル定義書未検出または未一致)",
              sourceRef: $r.sourceRef
            }]
          end
      )
  ')" || return 1

  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local result_file="$work/result.json"
  printf '%s' "$result_json" > "$result_file"
  local page_data
  page_data="$(jq -n \
    --slurpfile entities "$entities_file" \
    --slurpfile result "$result_file" \
    --arg generatedAt "$generated_at" \
    '{
      pageKind: "er",
      generatedAt: $generatedAt,
      title: "ER図",
      description: "テーブル定義書.md §5.3 外部キーに記載された参照関係を可視化する。",
      legend: [],
      entities: $entities[0],
      relations: $result[0].relations,
      unresolved: $result[0].unresolved
    }')" || return 1

  mkdir -p "$(dirname "$dest_file")"
  printf '%s\n' "$page_data" > "$dest_file"
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/er-page-data.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/docs/design/tables/table-users/詳細設計"
  cat > "$tmp/docs/design/tables/table-users/詳細設計/テーブル定義書.md" <<'EOF'
---
table_key: users
table_id: table-users
table_name: ユーザー
source_ref: src/models/users.py
unit_kind: table
status: draft
---

# ユーザー テーブル定義書

## §6 データ定義

### 6.3 外部キー

| カラム | 参照先のテーブル | 参照先のカラム | 削除時の動作 | 関連の種別 | 出典参照 |
|---|---|---|---|---|---|
EOF

  mkdir -p "$tmp/docs/design/tables/table-orders/詳細設計"
  cat > "$tmp/docs/design/tables/table-orders/詳細設計/テーブル定義書.md" <<'EOF'
---
table_key: orders
table_id: table-orders
table_name: 注文
source_ref: src/models/orders.py
unit_kind: table
status: draft
---

# 注文 テーブル定義書

## §6 データ定義

### 6.3 外部キー

| カラム | 参照先のテーブル | 参照先のカラム | 削除時の動作 | 関連の種別 | 出典参照 |
|---|---|---|---|---|---|
| `user_id` | `users` | `id` | `CASCADE` | `一対多` | `src/models/orders.py#L12` |
| `billing_user_id` | `ユーザー` | `id` | `RESTRICT` | `一対多` | `src/models/orders.py#L20` |
| `coupon_id` | `クーポン` | `id` | `SET NULL` | `一対多` | `src/models/orders.py#L30` |
| `<実測: 外部キーカラム名>` | `<実測: 参照先テーブル名>` | `<実測: 参照先カラム名>` | `<実測: CASCADE/RESTRICT/SET NULL等>` | `<実測: 一対一 または 一対多 または 多対多>` | `<実測: 根拠パス>` |

### 6.4 整合性のチェック点

| 対象 | チェックの内容 | 実施の箇所 |
|---|---|---|
EOF

  local self_path
  self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local out="$tmp/out/page-data.json"
  if bash "$self_path" "$tmp" "$out" >/dev/null 2>"$tmp/stderr1.log"; then
    echo "  [PASS] 正常系: 2テーブル・3有効行(+プレースホルダ1行)でexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 正常系: exit 0で終わらなかった" >&2
    fail=$((fail + 1))
  fi

  # 検査1: entitiesがファイル発見順(table-orders → table-users)でkey/labelを持つこと
  local ok1=1
  local entity_keys
  entity_keys="$(jq -r '[.entities[].key] | join(",")' "$out" 2>/dev/null)"
  [ "$entity_keys" = "orders,users" ] || ok1=0
  [ "$(jq -r '.entities[] | select(.key=="users") | .label' "$out" 2>/dev/null)" = "ユーザー" ] || ok1=0
  if [ "$ok1" -eq 1 ]; then
    echo "  [PASS] 検査1: entitiesがtable_key/table_nameで正しく組み立つ" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1: entitiesの組み立てに不一致がある(実際: $entity_keys)" >&2
    fail=$((fail + 1))
  fi

  # 検査2: table_key一致(users)・table_name一致(ユーザー)の両方がrelations[]へ解決され、
  # プレースホルダ行は除外されること
  local ok2=1
  [ "$(jq -r '.relations | length' "$out" 2>/dev/null)" = "2" ] || ok2=0
  [ "$(jq -r '[.relations[].to] | unique | join(",")' "$out" 2>/dev/null)" = "users" ] || ok2=0
  [ "$(jq -r '.relations[0].from' "$out" 2>/dev/null)" = "orders" ] || ok2=0
  [ "$(jq -r '.relations[0].cardinality' "$out" 2>/dev/null)" = "一対多" ] || ok2=0
  [ "$(jq -r '.relations[0].sourceRef' "$out" 2>/dev/null)" = "src/models/orders.py#L12" ] || ok2=0
  if [ "$ok2" -eq 1 ]; then
    echo "  [PASS] 検査2: table_key一致・table_name一致の両方がrelations[]へ解決される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査2: relations[]の組み立てに不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査3: 解決できない参照先(クーポン)はrelations[]に混入せずunresolved[]へ回ること
  local ok3=1
  [ "$(jq -r '.unresolved | length' "$out" 2>/dev/null)" = "1" ] || ok3=0
  printf '%s' "$(jq -r '.unresolved[0].label' "$out" 2>/dev/null)" | grep -q "クーポン" || ok3=0
  [ "$(jq -r '[.relations[].to] | index("クーポン")' "$out" 2>/dev/null)" = "null" ] || ok3=0
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] 検査3: 未解決の参照先はrelations[]を汚さずunresolved[]へ回る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査3: 未解決参照の扱いが不正" >&2
    fail=$((fail + 1))
  fi

  # 検査4: build-detail-page.sh --page er に通し、実際にHTMLが生成されること
  # (validate-page-data.shの孤児参照検査を通過することも同時に確かめる)
  local ok4=1
  local build_detail_page_sh="$SCRIPT_DIR/../detail-pages/build-detail-page.sh"
  local html_out_dir="$tmp/html-out"
  mkdir -p "$html_out_dir"
  if bash "$build_detail_page_sh" "$out" "$html_out_dir" --page er >/dev/null 2>"$tmp/stderr4.log"; then
    [ -f "$html_out_dir/ER図.html" ] || ok4=0
  else
    ok4=0
  fi
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] 検査4: build-detail-page.sh --page er でER図.htmlが生成される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査4: ER図.htmlの生成に失敗した" >&2
    sed 's/^/    /' "$tmp/stderr4.log" >&2
    fail=$((fail + 1))
  fi

  # 検査5: テーブル定義書.mdが1件も無い場合、0件のentities/relationsとWARNでexit 0であること
  local t5_root t5_dest t5_output t5_rc ok5=1
  t5_root="$(mktemp -d "${TMPDIR:-/tmp}/er-page-data-t5.XXXXXX")"
  local t5_dest_dir="$t5_root/out"
  mkdir -p "$t5_dest_dir"
  t5_dest="$t5_dest_dir/page-data.json"
  t5_output="$(bash "$self_path" "$t5_root" "$t5_dest" 2>&1)"
  t5_rc=$?
  [ "$t5_rc" -eq 0 ] || ok5=0
  printf '%s' "$t5_output" | grep -q "WARN" || ok5=0
  [ "$(jq -r '.entities | length' "$t5_dest" 2>/dev/null)" = "0" ] || ok5=0
  [ "$(jq -r '.relations | length' "$t5_dest" 2>/dev/null)" = "0" ] || ok5=0
  [ "$(jq -r '.pageKind' "$t5_dest" 2>/dev/null)" = "er" ] || ok5=0
  rm -rf "$t5_root"
  if [ "$ok5" -eq 1 ]; then
    echo "  [PASS] 検査5: テーブル定義書.md不在時は0件のentities/relationsとWARNでexit 0" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査5: テーブル定義書.md不在時の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  if self_test; then exit 0; else exit 1; fi
fi

output_dir="${1:?引数1 output_dir が必要です}"
dest_file="${2:?引数2 出力page-data.jsonのパス が必要です}"

if [ ! -d "$output_dir" ]; then
  echo "ERROR: output_dir が存在しません: $output_dir" >&2
  exit 1
fi

run "$output_dir" "$dest_file"
