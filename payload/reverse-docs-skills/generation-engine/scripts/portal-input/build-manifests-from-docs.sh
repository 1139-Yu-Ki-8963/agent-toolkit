#!/usr/bin/env bash
# build-manifests-from-docs.sh — 設計文書のfrontmatterから種別別一覧マニフェストを組み立てる
#
# 目的(改善課題1-26の一部): 配布物の生成器だけではポータルを再現できず、実行側の独自スクリプトに
# 依存していた問題への対応。設計文書から入力データを組み立てる経路について、抽出元の形式を
# 宣言(delivery-payload/references/doc-extraction.json)で指定し、特定の文書構成に依存しない形で
# 一覧マニフェスト(<kind>-manifest.json)を組み立てる。
#
# Usage:
#   build-manifests-from-docs.sh <output_dir> <出力先ディレクトリ> [--unit-kind <種別>]
#   build-manifests-from-docs.sh --self-test
#
#   <output_dir>         設計文書が展開済みのプロジェクトルート
#                         (scaffold-design-unit.sh の展開先と同じ意味。output-layout.json の
#                         <kind>UnitRoot を <output_dir> からの相対で解決する)
#   <出力先ディレクトリ>  <kind>-manifest.json を書き出す先
#   --unit-kind           省略時は宣言にある全種別(api/table/batch/report/external/feature)を処理する
#
# 対象は非画面の6種別。画面はfrontmatterの体系(screenKey/route/entryFile)が他種別と異なるため
# 対象外(理由は doc-extraction.json の "excluded" 節を参照)。
#
# frontmatterから導けない項目(kind・confidence・detectionMethod・fileCount・API以外のidentifier)は
# 捏造せず、宣言の "unresolvable" 節が定める代替値で埋める。詳細は
# .claude/rules/scoped/portal/page-conventions/rule.md の
# 「## 設計判断」内「### build-manifests-from-docs.sh」を参照する。
#
# 保守責任者: 人手(ユーザー)。種別を増減する場合は本ファイルと doc-extraction.json と
# rule.md と self-test を同時に更新する。
# macOS bash 3.2 互換(mapfile / declare -A 不使用)。

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_EXTRACTION_DEFAULT="$SCRIPT_DIR/../../../delivery-payload/references/doc-extraction.json"
VALIDATE_MANIFEST_SH="$SCRIPT_DIR/../unit-list/validate-manifest.sh"
# shellcheck source=../output-layout.sh
. "$SCRIPT_DIR/../output-layout.sh"
# shellcheck source=../extract/document-paths.sh
. "$SCRIPT_DIR/../extract/document-paths.sh"

# 宣言JSONを読み、妥当性を検査してから中身をstdoutへ返す。
doc_extraction_load() {
  local decl_file="${1:-$DOC_EXTRACTION_DEFAULT}"
  if [ ! -f "$decl_file" ]; then
    echo "ERROR: 宣言ファイルが見つかりません: $decl_file" >&2
    return 1
  fi
  if ! jq -e '.specVersion == 1' "$decl_file" >/dev/null 2>&1; then
    echo "ERROR: doc-extraction.json の specVersion が不正です" >&2
    return 1
  fi
  cat "$decl_file"
}

# 宣言JSONから種別一覧(改行区切り)を取り出す。
doc_extraction_kinds() {
  printf '%s' "$1" | jq -r '.kinds | keys[]'
}

# 宣言JSONから種別のフィールド(dot区切りパス)を取り出す。値が無ければ空文字を返す。
doc_extraction_field() {
  local json="$1" kind="$2" path="$3"
  printf '%s' "$json" | jq -r --arg k "$kind" ".kinds[\$k].$path // empty"
}

# 宣言JSONから種別のdocFileNameを取り出す。文字列・配列いずれの形も吸収し、
# 候補ファイル名の一覧を改行区切りで返す。
doc_extraction_file_names() {
  local json="$1" kind="$2"
  printf '%s' "$json" | jq -r --arg k "$kind" '
    (.kinds[$k].docFileName // empty) as $v
    | if ($v | type) == "array" then $v[]
      elif ($v | type) == "string" then $v
      else empty
      end
  '
}

# doc-extraction.json の documents 宣言に従い、設計単位フォルダ内で実在する資料だけを
# 一覧マニフェストのPathフィールドへ追加する。outputExtension宣言のある設計書はリンク値だけ
# 拡張子を変換するが、実在判定は変換元の実ファイルで行う。確認台帳JSONは実体を直接指す。
append_declared_document_paths() {
  local unit_obj="$1" decl_json="$2" layout_json="$3" kind="$4" unit_dir="$5" unit_list_dir_abs="$6"
  local document role file_name output_extension actual_file link_target link_value field
  local basic_dir detail_dir test_dir candidate
  local path_fields=()

  [ -d "$unit_dir" ] || { printf '%s' "$unit_obj"; return 0; }
  basic_dir="$(printf '%s' "$layout_json" | jq -r '.unitPhaseDirNames.basic // empty')"
  detail_dir="$(printf '%s' "$layout_json" | jq -r '.unitPhaseDirNames.detail // empty')"
  test_dir="$(output_layout_get "$layout_json" unitTestDesignDir)" || return 1
  while IFS= read -r document; do
    [ -n "$document" ] || continue
    role="$(printf '%s' "$document" | jq -r '.role // empty')"
    file_name="$(printf '%s' "$document" | jq -r '.fileName // empty')"
    output_extension="$(printf '%s' "$document" | jq -r '.outputExtension // empty')"
    [ -n "$file_name" ] || continue

    actual_file=""
    case "$role" in
      basic)
        for candidate in "$unit_dir/$basic_dir/$file_name" "$unit_dir/基本設計/$file_name"; do
          if [ -f "$candidate" ]; then actual_file="$candidate"; break; fi
        done
        ;;
      detail)
        for candidate in "$unit_dir/$detail_dir/$file_name" "$unit_dir/詳細設計/$file_name"; do
          if [ -f "$candidate" ]; then actual_file="$candidate"; break; fi
        done
        ;;
      externalBehavior|functionUnit)
        candidate="$unit_dir/$test_dir/$file_name"
        [ ! -f "$candidate" ] || actual_file="$candidate"
        ;;
      design|confirmation)
        candidate="$unit_dir/$file_name"
        [ ! -f "$candidate" ] || actual_file="$candidate"
        ;;
    esac
    [ -n "$actual_file" ] || continue
    link_target="$actual_file"
    if [ -n "$output_extension" ]; then
      link_target="${actual_file%.*}${output_extension}"
    fi
    link_value="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' \
      "$link_target" "$unit_list_dir_abs" 2>/dev/null)" || link_value=""

    path_fields=()
    while IFS= read -r field; do
      [ -n "$field" ] && path_fields+=("$field")
    done < <(printf '%s' "$document" | jq -r '.pathFields[]?')
    unit_obj="$(document_paths_add_existing "$unit_obj" "$actual_file" "$link_value" "${path_fields[@]}")" || return 1
  done < <(printf '%s' "$decl_json" | jq -c --arg k "$kind" '.kinds[$k].documents[]?')
  printf '%s' "$unit_obj"
}

document_path_safe_unit_segment() {
  local value="$1"
  [ -n "$value" ] && [ "$value" != "." ] && [ "$value" != ".." ] || return 1
  printf '%s' "$value" | jq -Rse '
    (contains("/") or contains("\\") or test("\\s")
      or (explode | any(. < 32 or . == 127))) | not
  ' >/dev/null 2>&1
}

# scaffold-design-unit.sh が作る <kind>-<unit_id> 形式の、root直下の単位ディレクトリだけを許可する。
document_path_canonical_unit_dir() {
  local kind="$1" unit_dir="$2" base
  base="$(basename "$unit_dir")"
  document_path_safe_unit_segment "$base" || return 1
  case "$base" in
    "$kind"-?*) return 0 ;;
    *) return 1 ;;
  esac
}

# 改善課題1-254: root直下の単位ディレクトリの数を数える。「正規の命名(document_path_
# canonical_unit_dirが受理するもの)の数」と「root直下の全ディレクトリ数」の2つを
# "<正規の数> <全体の数>" の形で1行返す。組み立てられた件数(unit_count)と正規の数を
# 突き合わせれば、正規の命名を持つ設計書が実在するのに反映されない食い違いを検知できる。
# 正規の数が0でも全体の数が1以上なら、単位フォルダの命名そのものが正規の形と一致して
# いない可能性がある(root自体が無い・単位フォルダを1つも持たない種別と区別するために
# 全体の数も返す)。root_dirが無ければ "0 0" を返す。
count_canonical_unit_dirs() {
  local root_dir="$1" kind="$2"
  local canonical=0 total=0 unit_dir
  [ -d "$root_dir" ] || { printf '%s %s\n' 0 0; return 0; }
  while IFS= read -r unit_dir; do
    [ -n "$unit_dir" ] || continue
    total=$((total + 1))
    document_path_canonical_unit_dir "$kind" "$unit_dir" || continue
    canonical=$((canonical + 1))
  done < <(find "$root_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
  printf '%s %s\n' "$canonical" "$total"
}

# frontmatter抽出元は、種別root直下の正規単位ディレクトリにある所定roleの文書だけに限る。
# 再帰findにするとarchive等の退避領域にある同名文書まで別単位として抽出してしまう。
individual_document_files() {
  local root_dir="$1" kind="$2" doc_file_names="$3" layout_json="$4"
  local detail_dir unit_dir fname candidate
  detail_dir="$(printf '%s' "$layout_json" | jq -r '.unitPhaseDirNames.detail // empty')"

  while IFS= read -r unit_dir; do
    [ -n "$unit_dir" ] || continue
    document_path_canonical_unit_dir "$kind" "$unit_dir" || continue
    while IFS= read -r fname; do
      [ -n "$fname" ] || continue
      if [ "$kind" = "feature" ]; then
        candidate="$unit_dir/$fname"
        [ ! -f "$candidate" ] || printf '%s\n' "$candidate"
      else
        for candidate in "$unit_dir/$detail_dir/$fname" "$unit_dir/詳細設計/$fname"; do
          if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            break
          fi
        done
      fi
    done <<< "$doc_file_names"
  done < <(find "$root_dir" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
}

# 集約文書から組み立てた行は単位文書そのものを走査していないため、unitIdまたは
# <kind>-<unitKey> と一致する実在フォルダがある場合だけ、その資料パスを補う。
append_aggregate_document_paths() {
  local units_json="$1" decl_json="$2" layout_json="$3" kind="$4" root_dir="$5" unit_list_dir_abs="$6"
  local enriched="[]" unit_obj unit_id unit_key unit_dir
  while IFS= read -r unit_obj; do
    [ -n "$unit_obj" ] || continue
    unit_id="$(printf '%s' "$unit_obj" | jq -r '.unitId // empty')"
    unit_key="$(printf '%s' "$unit_obj" | jq -r '.unitKey // empty')"
    unit_dir=""
    if document_path_safe_unit_segment "$unit_id"; then
      if [ -d "$root_dir/$unit_id" ] && document_path_canonical_unit_dir "$kind" "$root_dir/$unit_id"; then
        unit_dir="$root_dir/$unit_id"
      elif document_path_safe_unit_segment "$unit_key" && [ -d "$root_dir/$kind-$unit_key" ]; then
        unit_dir="$root_dir/$kind-$unit_key"
      fi
    elif [ -z "$unit_id" ] && document_path_safe_unit_segment "$unit_key" \
      && [ -d "$root_dir/$kind-$unit_key" ]; then
      unit_dir="$root_dir/$kind-$unit_key"
    fi
    unit_obj="$(append_declared_document_paths "$unit_obj" "$decl_json" "$layout_json" "$kind" "$unit_dir" "$unit_list_dir_abs")" || return 1
    # unit_objはfields/document Pathsとともに伸びるため、直接--argjsonを採らずjq -sを使う。
    # この値での失敗実測はないが、900列での失敗と単一引数131,071バイトの実測がある。
    # 引数長の上限は環境依存である。直接--argjsonへ戻してはならない。
    # checkerが2026-08-23に許可リスト外使用を報告し、この箇所では初回対策となる（1-249）。
    enriched="$(printf '%s\n%s\n' "$enriched" "$unit_obj" | jq -s '.[0] + [.[1]]')"
  done < <(printf '%s' "$units_json" | jq -c '.[]')
  printf '%s' "$enriched"
}

# frontmatter(YAML先頭の --- 区切りブロック)から指定キーの値を1行取り出す。
# 見つからなければ空文字を返す。値の前後の空白は取り除く。
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

# aggregateDocumentExtraction の宣言に従い、集約Markdownの該当節にある表の各行を
# JSON objectとして返す。列名と抽出フィールドの対応は宣言側だけが持つため、この処理は
# 特定の文書名・見出し・列名に依存しない。表は各対象節の最初のMarkdown表を読む。
extract_aggregate_unit_values() {
  local decl_json="$1" kind="$2" document="$3"
  local start_regex field_columns static_fields mapping
  start_regex="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].aggregateDocumentExtraction.sectionStartRegex')"
  field_columns="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].aggregateDocumentExtraction.fieldColumns | to_entries[] | "\(.key)=\(.value)"')"
  static_fields="$(printf '%s' "$decl_json" | jq -c --arg k "$kind" '.kinds[$k].aggregateDocumentExtraction.staticFields // {}')"
  mapping="$(printf '%s\n' "$field_columns" | tr '\n' '\034')"
  mapping="${mapping%$'\034'}"

  awk -v start_regex="$start_regex" -v mapping="$mapping" '
    function trim(value) { sub(/^[ \t]+/, "", value); sub(/[ \t]+$/, "", value); return value }
    function split_cells(line, cells,    count, item) {
      count = split(line, raw, "|")
      for (item = 2; item < count; item++) cells[item - 1] = trim(raw[item])
      return count - 2
    }
    BEGIN {
      map_count = split(mapping, map_entries, "\034")
      for (i = 1; i <= map_count; i++) {
        split(map_entries[i], pair, "=")
        map_key[i] = pair[1]
        map_column[i] = pair[2]
      }
    }
    $0 ~ start_regex { in_section = 1; have_header = 0; next }
    in_section && /^#/ { in_section = 0; have_header = 0 }
    in_section && /^\|/ {
      cell_count = split_cells($0, cells)
      if (!have_header) {
        for (i = 1; i <= cell_count; i++) header[cells[i]] = i
        have_header = 1
        next
      }
      if (cells[1] ~ /^[-: ]+$/) next
      output = ""
      for (i = 1; i <= map_count; i++) {
        value = ""
        if (map_column[i] in header) value = cells[header[map_column[i]]]
        output = output map_key[i] "\034" value "\034"
      }
      sub(/\034$/, "", output)
      print output
    }
  ' "$document" | jq -Rcn --arg static "$static_fields" '
    inputs | select(length > 0) | split("\u001c") as $items
      | reduce range(0; $items | length; 2) as $i
          (($static | fromjson); .[$items[$i]] = $items[$i + 1])
  '
}

# 集約文書の1行から既存マニフェストと同じ項目を組み立てる。kind判定は既存の
# kindMapping宣言を使うので、集約経路用に値域や種別をコードへ重ねて持たない。
build_aggregate_units() {
  local decl_json="$1" kind="$2" document="$3"
  local mapping_keys unresolved_kind unresolved_confidence unresolved_detection unresolved_identifier
  local unresolved_unit_key unresolved_source_file kind_mapping_value_from kind_mapping_allowed_values
  mapping_keys="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].mapping | keys[]')"
  unresolved_kind="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.kind')"
  unresolved_confidence="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.confidence')"
  unresolved_detection="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.detectionMethod')"
  unresolved_identifier="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.identifier')"
  unresolved_unit_key="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.unitKey')"
  unresolved_source_file="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.sourceFile')"
  kind_mapping_value_from="$(doc_extraction_field "$decl_json" "$kind" 'kindMapping.valueFrom')"
  kind_mapping_allowed_values="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].kindMapping.allowedValues[]? // empty')"

  local units_json="[]" raw field src_key value unit_obj unit_needs_unresolved_kind
  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    unit_obj="$(jq -n '{}')"
    for field in $mapping_keys; do
      src_key="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" --arg f "$field" '.kinds[$k].mapping[$f]')"
      value="$(printf '%s' "$raw" | jq -r --arg f "$src_key" '.[$f] // empty')"
      [ -z "$value" ] || unit_obj="$(printf '%s' "$unit_obj" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')"
    done
    unit_needs_unresolved_kind=0
    if ! printf '%s' "$unit_obj" | jq -e 'has("unitKey")' >/dev/null 2>&1; then
      unit_obj="$(printf '%s' "$unit_obj" | jq --arg v "$unresolved_unit_key" '.unitKey = $v')"
      unit_needs_unresolved_kind=1
    fi
    if ! printf '%s' "$unit_obj" | jq -e 'has("sourceFile")' >/dev/null 2>&1; then
      unit_obj="$(printf '%s' "$unit_obj" | jq --arg v "$unresolved_source_file" '.sourceFile = $v')"
      unit_needs_unresolved_kind=1
    fi
    local final_kind="$unresolved_kind" final_confidence="$unresolved_confidence" final_detection="$unresolved_detection"
    if [ "$unit_needs_unresolved_kind" -eq 0 ] && [ -n "$kind_mapping_value_from" ]; then
      value="$(printf '%s' "$raw" | jq -r --arg f "$kind_mapping_value_from" '.[$f] // empty')"
      local allowed=0 allowed_value
      while IFS= read -r allowed_value; do
        [ "$value" = "$allowed_value" ] && allowed=1
      done <<< "$kind_mapping_allowed_values"
      if [ "$allowed" -eq 1 ]; then
        final_kind="$value"
        final_confidence="high"
        final_detection="document-aggregate-table"
      fi
    fi
    unit_obj="$(printf '%s' "$unit_obj" | jq --arg idv "$unresolved_identifier" --arg kindv "$final_kind" --arg conf "$final_confidence" --arg dm "$final_detection" '.identifier = $idv | .kind = $kindv | .confidence = $conf | .detectionMethod = $dm | .fileCount = null')"
    units_json="$(printf '%s' "$units_json" | jq --argjson u "$unit_obj" '. + [$u]')"
  done < <(extract_aggregate_unit_values "$decl_json" "$kind" "$document")
  printf '%s' "$units_json"
}

# API詳細設計書 §7.1/§7.2 の先頭列から、CRUD対応表に渡す対象テーブルを導く。
# frontmatter の targetTables に依存せず、設計書本文に確定しているデータアクセスを
# 正本にする。雛形のプレースホルダ・空行は除外し、初出順で重複を取り除く。
extract_api_target_tables() {
  local file="$1"
  node - "$file" <<'NODE'
const fs = require("fs");
const lines = fs.readFileSync(process.argv[2], "utf8").split(/\r?\n/);
let inSection = false;
let dataRows = false;
const seen = new Set();
const tables = [];
for (const line of lines) {
  if (/^### 7\.[12] /.test(line)) {
    inSection = true;
    dataRows = false;
    continue;
  }
  if (/^#{2,3} /.test(line)) {
    inSection = false;
    dataRows = false;
    continue;
  }
  if (!inSection) continue;
  if (/^\|[ \t]*---/.test(line)) {
    dataRows = true;
    continue;
  }
  if (!dataRows || !/^\|/.test(line)) continue;
  const cells = line.replace(/^\|/, "").replace(/\|[ \t]*$/, "").split("|");
  const table = (cells[0] || "").trim().replace(/^`+|`+$/g, "");
  if (!table || /<実測:/.test(table) || seen.has(table)) continue;
  seen.add(table);
  tables.push(table);
}
process.stdout.write(JSON.stringify(tables));
NODE
}

# 種別1件分のマニフェストを組み立てて<dest_dir>/<kind>-manifest.jsonへ書き出し、
# validate-manifest.sh の検証まで実行する。
build_manifest_for_kind() {
  local decl_json="$1" layout_json="$2" output_dir="$3" dest_dir="$4" kind="$5"

  local unit_root_key doc_file_names unit_root_rel root_dir
  unit_root_key="$(doc_extraction_field "$decl_json" "$kind" unitRootKey)"
  doc_file_names="$(doc_extraction_file_names "$decl_json" "$kind")"
  if [ -z "$unit_root_key" ] || [ -z "$doc_file_names" ]; then
    echo "ERROR: 宣言に種別 $kind の unitRootKey/docFileName がありません" >&2
    return 1
  fi
  unit_root_rel="$(output_layout_get "$layout_json" "$unit_root_key")" || return 1
  root_dir="$output_dir/$unit_root_rel"

  # 1-36: 一覧の行から個別ページへ遷移できるよう、この時点で実在確認済みの設計書単位文書
  # （findで見つかった$file自体）から、一覧HTMLの置き場を基点にした相対パスを機械的に導き
  # designDocPathへ供給する。変換先(.html)はbuild-portal.sh側でcommon_rootsへ合流させた
  # 同じUnitRootのmd→html変換が担う(generation-engine/scripts/build-portal.sh参照)。文書が実在しない
  # ユニットには値を入れない(このループ自体が実在文書だけを対象に回るため自然に満たされる)。
  local kind_label unit_list_dir_rel unit_list_dir_abs
  kind_label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
  unit_list_dir_rel="$(output_layout_get "$layout_json" unitListDir "$kind_label")" || return 1
  unit_list_dir_abs="$output_dir/$unit_list_dir_rel"

  local mapping_keys
  mapping_keys="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].mapping | keys[]')"

  local identifier_mode identifier_field1 identifier_field2 identifier_sep
  identifier_mode="$(doc_extraction_field "$decl_json" "$kind" 'identifier.mode')"
  identifier_field1="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].identifier.fields[0] // empty')"
  identifier_field2="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].identifier.fields[1] // empty')"
  identifier_sep="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].identifier.separator // " "')"

  local unresolved_kind unresolved_confidence unresolved_detection unresolved_identifier
  unresolved_kind="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.kind')"
  unresolved_confidence="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.confidence')"
  unresolved_detection="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.detectionMethod')"
  unresolved_identifier="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.identifier')"
  # 1-67: マッピング(unitKey・sourceFile)がfrontmatterから導けなかった場合の代替値。
  local unresolved_unit_key unresolved_source_file
  unresolved_unit_key="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.unitKey')"
  unresolved_source_file="$(doc_extraction_field "$decl_json" "$kind" 'unresolvable.sourceFile')"

  # 1-66: 宣言(kindMapping)が定義済みの種別だけ、frontmatterの特定フィールドがすべて
  # 埋まっている場合にkindを解決する。宣言に無い種別は従来どおりunresolvedのまま
  # (判定材料がfrontmatterに無いため、捏造せず未着手のまま残す)。
  local kind_mapping_value kind_mapping_fields
  kind_mapping_value="$(doc_extraction_field "$decl_json" "$kind" 'kindMapping.value')"
  kind_mapping_fields="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].kindMapping.requiredFields[]? // empty')"
  local kind_mapping_value_from kind_mapping_allowed_values
  kind_mapping_value_from="$(doc_extraction_field "$decl_json" "$kind" 'kindMapping.valueFrom')"
  kind_mapping_allowed_values="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].kindMapping.allowedValues[]? // empty')"

  local units_json="[]" extraction_method="document-frontmatter"
  local aggregate_doc_rel aggregate_doc
  aggregate_doc_rel="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" '.kinds[$k].aggregateDocumentExtraction.documentPath // empty')"
  aggregate_doc="$output_dir/$aggregate_doc_rel"
  # 集約宣言の文書が実在する場合だけ集約経路を使う。無い場合は従来の単位別文書を
  # 探すので、既存プロジェクトの出力内容・探索規則は変わらない。
  if [ -n "$aggregate_doc_rel" ] && [ -f "$aggregate_doc" ]; then
    extraction_method="document-aggregate-table"
    units_json="$(build_aggregate_units "$decl_json" "$kind" "$aggregate_doc")"
    if command -v python3 >/dev/null 2>&1; then
      units_json="$(append_aggregate_document_paths "$units_json" "$decl_json" "$layout_json" "$kind" "$root_dir" "$unit_list_dir_abs")" || return 1
    fi
  elif [ -d "$root_dir" ]; then
    local file
    while IFS= read -r file; do
      [ -z "$file" ] && continue

      local file_rel unit_dir
      file_rel="${file#"$root_dir"/}"
      unit_dir="$root_dir/${file_rel%%/*}"
      # root直下のarchive等やprefix無しディレクトリを、設計単位として受理しない。
      document_path_canonical_unit_dir "$kind" "$unit_dir" || continue

      local unit_obj field
      unit_obj="$(jq -n '{}')"

      for field in $mapping_keys; do
        local src_key value
        src_key="$(printf '%s' "$decl_json" | jq -r --arg k "$kind" --arg f "$field" '.kinds[$k].mapping[$f]')"
        value="$(extract_frontmatter_value "$file" "$src_key")"
        if [ -n "$value" ]; then
          unit_obj="$(printf '%s' "$unit_obj" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')"
        fi
      done

      # 1-69: APIの対象テーブルはfrontmatterの未定義フィールドではなく、API詳細設計書
      # §7 データアクセスに記録された表から決定的に導く。表が空ならフィールドは付けず、
      # 「未確認」と「調査済みで0件」を混同しない。
      if [ "$kind" = "api" ]; then
        local target_tables_json
        target_tables_json="$(extract_api_target_tables "$file")" || return 1
        if [ "$(printf '%s' "$target_tables_json" | jq 'length')" -gt 0 ]; then
          # target_tables_jsonは設計書§7の表の行数に比例して伸びうる可変長の値
          # のため、コマンドライン引数ではなく一時ファイル経由(--slurpfile)で
          # jqへ渡す（改善課題1-52）。
          local target_tables_file
          if ! target_tables_file="$(mktemp "${TMPDIR:-/tmp}/build-manifests-target-tables.XXXXXX")" || [ -z "$target_tables_file" ]; then
            echo "ERROR: 一時ファイルの作成に失敗しました(mktemp)" >&2
            return 1
          fi
          printf '%s' "$target_tables_json" > "$target_tables_file"
          unit_obj="$(printf '%s' "$unit_obj" | jq --slurpfile tablesFile "$target_tables_file" '.targetTables = $tablesFile[0]')"
          rm -f -- "$target_tables_file"
        fi
      fi

      # 1-67: unitKey・sourceFileはvalidate-manifest.shが必須とするキーだが、上のループは
      # frontmatterの値が空なら書き込まずキー自体を欠落させる。検証器の必須フィールド検査は
      # キーの有無だけを見る(値の中身は見ない)ため、欠落したまま渡すと終了コード1で止まる。
      # frontmatterから導けなかった場合は宣言済みの代替値で埋め、キーの欠落を防ぐ(捏造ではなく
      # 「不明である」ことを表す固定値)。
      #
      # unit_needs_unresolved_kindは、この行が代替値で埋まったこと(=実体を確認できていない
      # こと)を記録するフラグ。値そのものはこの時点のkind決定には使わない(現状kindは常に
      # unresolved_kindになるため無条件で正しい)が、1-66でkindをfrontmatterから解決する
      # 分岐を足す際に必ず参照すること。代替値のsourceFile("未確認"等、実在しないパス文字列)
      # を持つ行のkindを非unresolvedにすると、validate-manifest.shのsourceFile-実在検査
      # (kind!=unresolvedの行だけを検査する)に必ずひっかかり終了コード1で止まる。
      local unit_needs_unresolved_kind=0
      if ! printf '%s' "$unit_obj" | jq -e 'has("unitKey")' >/dev/null 2>&1; then
        if [ -n "$unresolved_unit_key" ]; then
          unit_obj="$(printf '%s' "$unit_obj" | jq --arg v "$unresolved_unit_key" '.unitKey = $v')"
        fi
        unit_needs_unresolved_kind=1
      fi
      if ! printf '%s' "$unit_obj" | jq -e 'has("sourceFile")' >/dev/null 2>&1; then
        if [ -n "$unresolved_source_file" ]; then
          unit_obj="$(printf '%s' "$unit_obj" | jq --arg v "$unresolved_source_file" '.sourceFile = $v')"
        fi
        unit_needs_unresolved_kind=1
      fi

      if command -v python3 >/dev/null 2>&1; then
        unit_obj="$(append_declared_document_paths "$unit_obj" "$decl_json" "$layout_json" "$kind" "$unit_dir" "$unit_list_dir_abs")" || return 1
      fi

      local identifier_value
      if [ "$identifier_mode" = "concat" ]; then
        local v1 v2
        v1="$(extract_frontmatter_value "$file" "$identifier_field1")"
        v2="$(extract_frontmatter_value "$file" "$identifier_field2")"
        identifier_value="${v1}${identifier_sep}${v2}"
      else
        identifier_value="$unresolved_identifier"
      fi

      # 1-66: kindMapping宣言があり、かつ必須フィールドがすべてfrontmatterに存在する場合
      # だけkindを解決する。unit_needs_unresolved_kind(1-67)が立っている行は、unitKey・
      # sourceFileが代替値(実在しないパス文字列等)で埋まっており実体を確認できていない
      # ため、kindMappingの条件を満たしていてもunresolvedのまま固定する(この固定を外すと
      # validate-manifest.shのsourceFile-実在検査に必ず引っかかる。詳細は
      # docs/design/generation-engine/portal-input/詳細設計書.md「実装判断(改善課題1-67)」
      # を参照)。
      local final_kind="$unresolved_kind" final_confidence="$unresolved_confidence" \
        final_detection="$unresolved_detection"
      if [ -n "$kind_mapping_value" ] && [ "$unit_needs_unresolved_kind" -eq 0 ]; then
        local kind_fields_ok=1 kind_field_name kind_field_value
        if [ -n "$kind_mapping_fields" ]; then
          while IFS= read -r kind_field_name; do
            [ -z "$kind_field_name" ] && continue
            kind_field_value="$(extract_frontmatter_value "$file" "$kind_field_name")"
            [ -n "$kind_field_value" ] || kind_fields_ok=0
          done <<< "$kind_mapping_fields"
        fi
        if [ "$kind_fields_ok" -eq 1 ]; then
          final_kind="$kind_mapping_value"
          final_confidence="high"
          final_detection="document-frontmatter"
        fi
      elif [ -n "$kind_mapping_value_from" ] && [ "$unit_needs_unresolved_kind" -eq 0 ]; then
        # 種別の判定材料をテンプレートへ足す指示書: table/batch/report/externalは
        # kindMapping.valueのような固定値ではなく、frontmatterの欄
        # (kind_mapping_value_from)の実際の値を読んでkindとする。allowedValuesに
        # 無い値(未置換のプレースホルダ等)はunresolvedのまま残す(捏造しない。
        # この検査を省くとテンプレートのプレースホルダがそのままkindへ化け、
        # validate-manifest.shの値域検査で落ちる)。
        local kind_fields_ok=1 kind_field_name kind_field_value
        if [ -n "$kind_mapping_fields" ]; then
          while IFS= read -r kind_field_name; do
            [ -z "$kind_field_name" ] && continue
            kind_field_value="$(extract_frontmatter_value "$file" "$kind_field_name")"
            [ -n "$kind_field_value" ] || kind_fields_ok=0
          done <<< "$kind_mapping_fields"
        fi
        if [ "$kind_fields_ok" -eq 1 ]; then
          local resolved_value value_allowed=0 allowed_value
          resolved_value="$(extract_frontmatter_value "$file" "$kind_mapping_value_from")"
          if [ -n "$resolved_value" ] && [ -n "$kind_mapping_allowed_values" ]; then
            while IFS= read -r allowed_value; do
              [ -z "$allowed_value" ] && continue
              if [ "$resolved_value" = "$allowed_value" ]; then
                value_allowed=1
                break
              fi
            done <<< "$kind_mapping_allowed_values"
          fi
          if [ "$value_allowed" -eq 1 ]; then
            final_kind="$resolved_value"
            final_confidence="high"
            final_detection="document-frontmatter"
          fi
        fi
      fi

      # 導けない項目(kind・confidence・detectionMethod・fileCount・API以外のidentifier)は
      # 宣言の代替値で埋める(捏造しない)。kindMappingで解決できた場合はfinal_*を使う。
      unit_obj="$(printf '%s' "$unit_obj" | jq \
        --arg idv "$identifier_value" \
        --arg kindv "$final_kind" \
        --arg conf "$final_confidence" \
        --arg dm "$final_detection" \
        '.identifier = $idv | .kind = $kindv | .confidence = $conf | .detectionMethod = $dm | .fileCount = null')"

      units_json="$(printf '%s' "$units_json" | jq --argjson u "$unit_obj" '. + [$u]')"
    done < <(individual_document_files "$root_dir" "$kind" "$doc_file_names" "$layout_json")
  fi

  local unit_count unresolved_count
  unit_count="$(printf '%s' "$units_json" | jq 'length')"
  unresolved_count="$(printf '%s' "$units_json" | jq '[.[] | select(.kind == "unresolved")] | length')"

  # 改善課題1-254: 単位フォルダの数(folder_count。正規の命名を持つものだけ)と
  # 組み立てられた件数(unit_count)を突き合わせる。単位フォルダが1つ以上ある種別に限って
  # 食い違いを検知する。個別の設計書を持たない種別(単位フォルダ自体が0件)は、0件が正しい
  # 状態のため対象から外す。あわせて、root直下に何らかのディレクトリ(all_dir_count)は
  # あるのに正規の命名を持つものが1つも無い場合も検知する(単位フォルダの命名そのものが
  # 正規の形と一致していない可能性。この場合はfolder_countが0になり上の突き合わせでは
  # 検知できないため、別条件として持つ)。組み立ての処理自体は終了コード0のまま続ける
  # (0件・食い違いを理由に生成連鎖を止めない。既存の「0件時は警告のみで続行する」設計を
  # 踏襲する。詳細は .claude/rules/scoped/portal/page-conventions/rule.md「設計判断」内
  # 「build-manifests-from-docs.sh」を参照)。
  local folder_count all_dir_count
  read -r folder_count all_dir_count < <(count_canonical_unit_dirs "$root_dir" "$kind")
  local names_oneline root_dir_abs
  names_oneline="$(printf '%s' "$doc_file_names" | tr '\n' ',' | sed 's/,$//')"
  if [ -d "$root_dir" ]; then
    root_dir_abs="$(cd "$root_dir" && pwd)"
  else
    root_dir_abs="$root_dir"
  fi
  if [ "$folder_count" -ge 1 ] && [ "$folder_count" -ne "$unit_count" ]; then
    echo "WARN: 種別 $kind で単位フォルダの数(${folder_count})と一覧の元データへ組み立てられた件数(${unit_count})が一致しません(探索したファイル名: ${names_oneline} / 走査したディレクトリ: ${root_dir_abs})。設計書は実在するのに一覧の元データへ反映されていない可能性があります。" >&2
  elif [ "$folder_count" -eq 0 ] && [ "$all_dir_count" -ge 1 ]; then
    echo "WARN: 種別 $kind で単位フォルダの命名が正規の形(${kind}-<単位ID>)と一致しません(root直下のディレクトリ数: ${all_dir_count} / 正規の命名を持つもの: 0 / 走査したディレクトリ: ${root_dir_abs})。設計書が実在するのに一覧の元データへ反映されていない可能性があります。" >&2
  fi

  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local manifest
  manifest="$(jq -n \
    --arg generatedAt "$generated_at" \
    --arg sourceDir "$unit_root_rel" \
    --arg unitKind "$kind" \
    --arg extractionMethod "$extraction_method" \
    --argjson unitCount "$unit_count" \
    --argjson unresolvedCount "$unresolved_count" \
    --argjson units "$units_json" \
    '{
      generatedAt: $generatedAt,
      sourceDir: $sourceDir,
      unitKind: $unitKind,
      strategy: { extractionMethod: $extractionMethod, approvedByUser: true, unitIdRegex: null },
      detectionSummary: { unitCount: $unitCount, unresolvedCount: $unresolvedCount },
      units: $units
    }')"

  mkdir -p "$dest_dir"
  printf '%s\n' "$manifest" > "$dest_dir/${kind}-manifest.json"

  bash "$VALIDATE_MANIFEST_SH" "$dest_dir/${kind}-manifest.json" --unit-kind "$kind" >&2
  return $?
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-selftest.XXXXXX")"
  tmp="$(cd "$tmp" && pwd -P)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/docs/design/apis/api-get-users/詳細設計"
  cat > "$tmp/docs/design/apis/api-get-users/詳細設計/API詳細設計書.md" <<'EOF'
---
# API詳細設計書テンプレート(unit_kind=api・1エンドポイント1枚)
api_key: get-users
api_id: api-get-users
method: GET
path: /api/users
feature_key: user-management
source_ref: src/api/users.py
unit_kind: api
---

# ユーザー一覧 API詳細設計書

## §7 データアクセス

### 7.1 参照テーブル

| テーブル | 取得条件 | 根拠 |
|---|---|---|
| `users` | 一覧取得 | `src/api/users.py` |

### 7.2 更新テーブル

| テーブル | 操作 | 更新条件 | 根拠 |
|---|---|---|---|
| `audit_logs` | INSERT | 監査記録 | `src/api/users.py` |
EOF

  # 正規単位内の退避領域にある同名文書は、別単位として抽出しない。
  mkdir -p "$tmp/docs/design/apis/api-get-users/archive/詳細設計"
  cat > "$tmp/docs/design/apis/api-get-users/archive/詳細設計/API詳細設計書.md" <<'EOF'
---
api_key: nested-archive
api_id: api-nested-archive
method: DELETE
path: /api/archive
source_ref: src/api/archive.py
unit_kind: api
---

# 退避API詳細設計書
EOF

  # root直下の非正規archiveは、同名の詳細・基本資料を持っても設計単位ではない。
  mkdir -p "$tmp/docs/design/apis/archive/詳細設計" "$tmp/docs/design/apis/archive/基本設計"
  cat > "$tmp/docs/design/apis/archive/詳細設計/API詳細設計書.md" <<'EOF'
---
api_key: archived
api_id: api-archived
method: GET
path: /api/archived
source_ref: src/api/archived.py
unit_kind: api
---

# archive API詳細設計書
EOF
  : > "$tmp/docs/design/apis/archive/基本設計/API基本設計書.md"

  mkdir -p "$tmp/docs/design/tables/table-users/詳細設計"
  cat > "$tmp/docs/design/tables/table-users/詳細設計/テーブル定義書.md" <<'EOF'
---
# テーブル定義書テンプレート(unit_kind=table・1テーブル1枚)
table_key: users
table_id: table-users
table_name: ユーザー
source_ref: src/models/users.py
table_subkind: table
unit_kind: table
status: draft
---

# ユーザー テーブル定義書
EOF

  mkdir -p "$tmp/docs/design/batches/batch-cleanup/詳細設計"
  cat > "$tmp/docs/design/batches/batch-cleanup/詳細設計/バッチ詳細設計書.md" <<'EOF'
---
batch_key: cleanup
batch_id: batch-cleanup
batch_name: 古いセッションの削除
source_ref: src/batches/cleanup.py
batch_trigger_type: scheduled
unit_kind: batch
status: draft
---

# 古いセッションの削除 バッチ詳細設計書
EOF

  mkdir -p "$tmp/docs/design/reports/report-sales/詳細設計"
  cat > "$tmp/docs/design/reports/report-sales/詳細設計/帳票詳細設計書.md" <<'EOF'
---
report_key: sales
report_id: report-sales
report_name: 売上帳票
source_ref: src/reports/sales.py
report_engine: template
unit_kind: report
status: draft
---

# 売上帳票 帳票詳細設計書
EOF

  mkdir -p "$tmp/docs/design/externals/external-payment/詳細設計"
  cat > "$tmp/docs/design/externals/external-payment/詳細設計/外部連携詳細設計書.md" <<'EOF'
---
external_key: payment
external_id: external-payment
external_name: 決済API連携
source_ref: src/externals/payment.py
external_direction: client
unit_kind: external
status: draft
---

# 決済API連携 外部連携詳細設計書
EOF

  mkdir -p "$tmp/docs/design/features/feature-user-management"
  cat > "$tmp/docs/design/features/feature-user-management/機能設計書.md" <<'EOF'
---
feature_key: user-management
feature_id: feature-user-management
category: 会員管理
source_ref: src/features/user_management.py
unit_kind: feature
---

# 会員管理 機能設計書
EOF

  # 改善課題1-249: 全6種別に、宣言された資料を実在させる。見本は変更せず一時領域だけを使う。
  mkdir -p \
    "$tmp/docs/design/apis/api-get-users/基本設計" "$tmp/docs/design/apis/api-get-users/テスト設計" \
    "$tmp/docs/design/tables/table-users/基本設計" "$tmp/docs/design/tables/table-users/テスト設計" \
    "$tmp/docs/design/batches/batch-cleanup/基本設計" "$tmp/docs/design/batches/batch-cleanup/テスト設計" \
    "$tmp/docs/design/reports/report-sales/基本設計" "$tmp/docs/design/reports/report-sales/テスト設計" \
    "$tmp/docs/design/externals/external-payment/基本設計" "$tmp/docs/design/externals/external-payment/テスト設計" \
    "$tmp/docs/design/features/feature-user-management/テスト設計"
  : > "$tmp/docs/design/apis/api-get-users/基本設計/API基本設計書.md"
  : > "$tmp/docs/design/apis/api-get-users/テスト設計/APIテスト設計書.md"
  : > "$tmp/docs/design/apis/api-get-users/テスト設計/API単体テスト設計書.md"
  : > "$tmp/docs/design/apis/api-get-users/要確認事項台帳.json"
  : > "$tmp/docs/design/tables/table-users/基本設計/論理データモデル.md"
  : > "$tmp/docs/design/tables/table-users/テスト設計/テーブルテスト設計書.md"
  : > "$tmp/docs/design/tables/table-users/テスト設計/テーブル単体テスト設計書.md"
  : > "$tmp/docs/design/tables/table-users/要確認事項台帳.json"
  : > "$tmp/docs/design/batches/batch-cleanup/基本設計/バッチ基本設計書.md"
  : > "$tmp/docs/design/batches/batch-cleanup/テスト設計/バッチテスト設計書.md"
  : > "$tmp/docs/design/batches/batch-cleanup/テスト設計/バッチ単体テスト設計書.md"
  : > "$tmp/docs/design/batches/batch-cleanup/要確認事項台帳.json"
  : > "$tmp/docs/design/reports/report-sales/基本設計/帳票基本設計書.md"
  : > "$tmp/docs/design/reports/report-sales/テスト設計/帳票テスト設計書.md"
  : > "$tmp/docs/design/reports/report-sales/テスト設計/帳票単体テスト設計書.md"
  : > "$tmp/docs/design/reports/report-sales/要確認事項台帳.json"
  : > "$tmp/docs/design/externals/external-payment/基本設計/外部連携基本設計書.md"
  : > "$tmp/docs/design/externals/external-payment/テスト設計/外部連携テスト設計書.md"
  : > "$tmp/docs/design/externals/external-payment/テスト設計/外部連携単体テスト設計書.md"
  : > "$tmp/docs/design/externals/external-payment/要確認事項台帳.json"
  : > "$tmp/docs/design/features/feature-user-management/テスト設計/機能テスト設計書.md"
  : > "$tmp/docs/design/features/feature-user-management/テスト設計/機能単体テスト設計書.md"
  : > "$tmp/docs/design/features/feature-user-management/要確認事項台帳.json"

  local out="$tmp/out"
  mkdir -p "$out"

  # 1-66: apiのkindがkindMappingで"endpoint"(非unresolved)へ解決されるため、
  # validate-manifest.shのsourceFile-実在検査(kind!=unresolvedの行のみ検査)が
  # source_refの実在を要求するようになる。sourceDirはこの検証器の実装上、
  # manifestの所在ディレクトリ(この自己検査では$out。.git祖先が無いためフォール
  # バックされる)を基準に解決されるため、$out配下の同じ相対位置にダミーの実体を
  # 用意する(既存のvalidate-manifest.shの解決仕様に合わせるだけで、本体の
  # 挙動は変えない)。
  mkdir -p "$out/docs/design/apis/src/api"
  : > "$out/docs/design/apis/src/api/users.py"

  # 種別の判定材料をテンプレートへ足す指示書: table/batch/report/externalのkindMapping
  # (table_subkind等)がfrontmatterの欄から解決されるようになったため、apiと同様に
  # sourceFile-実在検査(kind!=unresolvedの行のみを検査するvalidate-manifest.shの
  # 検査4)がsource_refの実在を要求するようになる。$out配下の同じ相対位置にダミーの
  # 実体を用意する(本体の挙動は変えない。上のapi向け実装と同じ形。ab86f030の先例に倣う)。
  mkdir -p "$out/docs/design/tables/src/models"
  : > "$out/docs/design/tables/src/models/users.py"
  mkdir -p "$out/docs/design/batches/src/batches"
  : > "$out/docs/design/batches/src/batches/cleanup.py"
  mkdir -p "$out/docs/design/reports/src/reports"
  : > "$out/docs/design/reports/src/reports/sales.py"
  mkdir -p "$out/docs/design/externals/src/externals"
  : > "$out/docs/design/externals/src/externals/payment.py"

  local self_path
  self_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local run_output run_rc
  run_output="$(bash "$self_path" "$tmp" "$out" 2>&1)"
  run_rc=$?

  if [ "$run_rc" -eq 0 ]; then
    echo "  [PASS] 6種別の抽出とvalidate-manifest.sh検証がすべて成功" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 抽出またはvalidate-manifest.sh検証が失敗" >&2
    echo "$run_output" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # 検査1: frontmatterから導ける項目(unitKey・unitId・sourceFile・API識別子・feature category)
  #        が正しく入ること
  local ok1=1
  [ "$(jq -r '.units[0].unitKey' "$out/api-manifest.json" 2>/dev/null)" = "get-users" ] || ok1=0
  [ "$(jq -r '.units[0].unitId' "$out/api-manifest.json" 2>/dev/null)" = "api-get-users" ] || ok1=0
  [ "$(jq -r '.units[0].sourceFile' "$out/api-manifest.json" 2>/dev/null)" = "src/api/users.py" ] || ok1=0
  [ "$(jq -r '.units[0].identifier' "$out/api-manifest.json" 2>/dev/null)" = "GET /api/users" ] || ok1=0
  [ "$(jq -r '.detectionSummary.unitCount' "$out/api-manifest.json" 2>/dev/null)" = "1" ] || ok1=0
  jq -e '[.units[] | select(.unitKey == "archived")] | length == 0' \
    "$out/api-manifest.json" >/dev/null 2>&1 || ok1=0
  [ "$(jq -c '.units[0].targetTables' "$out/api-manifest.json" 2>/dev/null)" = '["users","audit_logs"]' ] || ok1=0
  [ "$(jq -r '.units[0].unitKey' "$out/table-manifest.json" 2>/dev/null)" = "users" ] || ok1=0
  [ "$(jq -r '.units[0].sourceFile' "$out/table-manifest.json" 2>/dev/null)" = "src/models/users.py" ] || ok1=0
  [ "$(jq -r '.units[0].unitKey' "$out/feature-manifest.json" 2>/dev/null)" = "user-management" ] || ok1=0
  [ "$(jq -r '.units[0].category' "$out/feature-manifest.json" 2>/dev/null)" = "会員管理" ] || ok1=0
  if [ "$ok1" -eq 1 ]; then
    echo "  [PASS] 検査1: frontmatterとAPI詳細設計書から導ける項目が正しく入る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1: frontmatterまたはAPI詳細設計書から導ける項目に不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査1b(改善課題1-249): 6種別すべてで、実在する宣言資料だけがPathフィールドへ入ること。
  local ok1b=1
  for k in api table batch report external; do
    jq -e '.units[0]
      | [.designDocPath, .detailDocPath, .integrationTestViewpointPath,
         .integrationTestCasePath, .testCasePath, .unitTestViewpointPath, .confirmationPath]
      | all(type == "string" and length > 0)' "$out/${k}-manifest.json" >/dev/null 2>&1 || ok1b=0
  done
  jq -e '.units[0]
    | ([.designDocPath, .integrationTestViewpointPath, .integrationTestCasePath,
        .testCasePath, .unitTestViewpointPath, .confirmationPath]
       | all(type == "string" and length > 0))
      and (.confirmationPath | endswith("要確認事項台帳.json"))
      and (has("detailDocPath") | not)' "$out/feature-manifest.json" >/dev/null 2>&1 || ok1b=0
  for k in api table batch report external; do
    jq -e '.units[0].confirmationPath | endswith("要確認事項台帳.json")' \
      "$out/${k}-manifest.json" >/dev/null 2>&1 || ok1b=0
  done
  if [ "$ok1b" -eq 1 ]; then
    echo "  [PASS] 検査1b(1-249): 6種別で実在する宣言資料のPathフィールドを付与" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1b(1-249): 宣言資料のPathフィールドに不足または非実在資料の値がある" >&2
    fail=$((fail + 1))
  fi

  # 検査1c(改善課題1-249): 資料を削除して再生成すると、対応するPathだけが消えること。
  # archiveに同名資料があっても、所定phase外なので代わりに拾わない。
  local ok1c=1
  rm -f "$tmp/docs/design/apis/api-get-users/テスト設計/API単体テスト設計書.md"
  rm -f "$tmp/docs/design/apis/api-get-users/基本設計/API基本設計書.md"
  mkdir -p "$tmp/docs/design/apis/api-get-users/archive"
  : > "$tmp/docs/design/apis/api-get-users/archive/API基本設計書.md"
  if ! bash "$self_path" "$tmp" "$out" --unit-kind api >/dev/null 2>&1; then
    ok1c=0
  fi
  jq -e '.units[0]
    | (has("testCasePath") | not)
      and (has("unitTestViewpointPath") | not)
      and (has("designDocPath") | not)
      and (.detailDocPath | type == "string")' "$out/api-manifest.json" >/dev/null 2>&1 || ok1c=0
  if [ "$ok1c" -eq 1 ]; then
    echo "  [PASS] 検査1c(1-249): 資料削除後にPathが消え、archiveの同名資料を拾わない" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1c(1-249): 削除した資料のPathが残るか再生成に失敗" >&2
    fail=$((fail + 1))
  fi

  # 検査1d(改善課題1-249): scaffoldが許可する日本語・underscoreを含む識別子を
  # builder独自の文字種制約で除外しない。root直下のprefix無しarchive除外も維持する。
  local jp_root="$tmp/scaffold-japanese-id" jp_out="$tmp/scaffold-japanese-id-out" ok1d=1
  mkdir -p "$jp_root" "$jp_out"
  if ! bash "$SCRIPT_DIR/../scaffold-design-unit.sh" api detail "$jp_root" \
    "日本語_ID" "日本語 API" >/dev/null 2>&1; then
    ok1d=0
  fi
  mkdir -p "$jp_root/docs/design/apis/archive/詳細設計"
  cp "$jp_root/docs/design/apis/api-日本語_ID/詳細設計/API詳細設計書.md" \
    "$jp_root/docs/design/apis/archive/詳細設計/API詳細設計書.md" 2>/dev/null || ok1d=0
  mkdir -p "$jp_out/docs/design/apis"
  : > "$jp_out/docs/design/apis/SOURCEREF"
  if ! bash "$self_path" "$jp_root" "$jp_out" --unit-kind api >/dev/null 2>&1; then
    ok1d=0
  fi
  jq -e '.detectionSummary.unitCount == 1
    and (.units | length == 1)
    and (.units[0].detailDocPath | type == "string" and length > 0)' \
    "$jp_out/api-manifest.json" >/dev/null 2>&1 || ok1d=0
  if [ "$ok1d" -eq 1 ]; then
    echo "  [PASS] 検査1d(1-249): scaffold合法の日本語_IDをPath付きで抽出し、archiveは除外" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査1d(1-249): scaffold合法IDの抽出またはarchive除外が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査2: 導けない項目が宣言の代替値で埋まること(featureで確認。tableは検査8でkindMapping解決を確認)
  local ok2=1
  [ "$(jq -r '.units[0].kind' "$out/feature-manifest.json" 2>/dev/null)" = "unresolved" ] || ok2=0
  [ "$(jq -r '.units[0].confidence' "$out/feature-manifest.json" 2>/dev/null)" = "low" ] || ok2=0
  [ "$(jq -r '.units[0].identifier' "$out/feature-manifest.json" 2>/dev/null)" = "未確認" ] || ok2=0
  [ "$(jq -r '.units[0].detectionMethod' "$out/feature-manifest.json" 2>/dev/null)" = "未確認" ] || ok2=0
  [ "$(jq -r '.units[0].fileCount' "$out/feature-manifest.json" 2>/dev/null)" = "null" ] || ok2=0
  if [ "$ok2" -eq 1 ]; then
    echo "  [PASS] 検査2: 導けない項目が宣言の代替値で埋まる" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査2: 導けない項目の代替値に不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査2b(改善課題1-66): kindMapping宣言のあるapiは、必須フィールド(method・path)が
  #         frontmatterに揃っている場合にkindがunresolvedから解決されること。table等
  #         宣言の無い種別は従来どおりunresolvedのままであること(検査2で確認済み)。
  local ok2b=1
  [ "$(jq -r '.units[0].kind' "$out/api-manifest.json" 2>/dev/null)" = "endpoint" ] || ok2b=0
  [ "$(jq -r '.units[0].confidence' "$out/api-manifest.json" 2>/dev/null)" = "high" ] || ok2b=0
  [ "$(jq -r '.units[0].detectionMethod' "$out/api-manifest.json" 2>/dev/null)" = "document-frontmatter" ] || ok2b=0
  if [ "$ok2b" -eq 1 ]; then
    echo "  [PASS] 検査2b: kindMappingの必須フィールドが揃ったapiのkindが解決される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査2b: kindMappingによるapiのkind解決が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査3: 出力がvalidate-manifest.shの検証を通ること(6種別すべてを直接再検証)
  local ok3=1 k
  for k in api table batch report external feature; do
    if ! bash "$VALIDATE_MANIFEST_SH" "$out/${k}-manifest.json" --unit-kind "$k" >/dev/null 2>&1; then
      ok3=0
    fi
  done
  if [ "$ok3" -eq 1 ]; then
    echo "  [PASS] 検査3: 6種別すべての出力がvalidate-manifest.shを通る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査3: validate-manifest.shを通らない出力がある" >&2
    fail=$((fail + 1))
  fi

  # 検査4: 設計文書が1件も無い(unitRootが存在しない)場合、0件のマニフェストを組み立て、
  #        それでもvalidate-manifest.shを通ること
  local empty_root empty_out ok4=1
  empty_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-empty.XXXXXX")"
  empty_out="$empty_root/out"
  mkdir -p "$empty_out"
  if ! bash "$self_path" "$empty_root" "$empty_out" --unit-kind api >/dev/null 2>&1; then
    ok4=0
  fi
  [ "$(jq -r '.detectionSummary.unitCount' "$empty_out/api-manifest.json" 2>/dev/null)" = "0" ] || ok4=0
  [ "$(jq -r '.detectionSummary.unresolvedCount' "$empty_out/api-manifest.json" 2>/dev/null)" = "0" ] || ok4=0
  [ "$(jq -r '.units | length' "$empty_out/api-manifest.json" 2>/dev/null)" = "0" ] || ok4=0
  rm -rf "$empty_root"
  if [ "$ok4" -eq 1 ]; then
    echo "  [PASS] 検査4: 設計文書が0件でも0件マニフェストを組み立てvalidateを通る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査4: 0件時の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査5: ファイル名が抽出定義と一致しない合成データで実行すると、警告が標準エラーへ出て
  #        終了コードは0のままであること
  local t5_root t5_out t5_output t5_rc ok5=1
  t5_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t5.XXXXXX")"
  mkdir -p "$t5_root/docs/design/apis/api-mismatch/詳細設計"
  cat > "$t5_root/docs/design/apis/api-mismatch/詳細設計/APIdetail-mismatch.md" <<'EOF'
---
api_key: mismatch
api_id: api-mismatch
method: GET
path: /api/mismatch
source_ref: src/api/mismatch.py
unit_kind: api
---

# 不一致確認用API詳細設計書
EOF
  t5_out="$t5_root/out"
  mkdir -p "$t5_out"
  t5_output="$(bash "$self_path" "$t5_root" "$t5_out" --unit-kind api 2>&1)"
  t5_rc=$?
  [ "$t5_rc" -eq 0 ] || ok5=0
  printf '%s' "$t5_output" | grep -q "WARN" || ok5=0
  [ "$(jq -r '.detectionSummary.unitCount' "$t5_out/api-manifest.json" 2>/dev/null)" = "0" ] || ok5=0
  rm -rf "$t5_root"
  if [ "$ok5" -eq 1 ]; then
    echo "  [PASS] 検査5: ファイル名不一致の合成データで警告が出て終了コードは0のまま" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査5: ファイル名不一致時の挙動が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査6: docFileNameをjqでインメモリ配列化してbuild_manifest_for_kindを直接呼び、
  #        両方の候補に一致するファイルが抽出されること
  local t6_root t6_out t6_decl t6_layout ok6=1
  t6_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t6.XXXXXX")"
  mkdir -p "$t6_root/docs/design/apis/api-get-users/詳細設計"
  cat > "$t6_root/docs/design/apis/api-get-users/詳細設計/API詳細設計書.md" <<'EOF'
---
api_key: get-users
api_id: api-get-users
method: GET
path: /api/users
source_ref: src/api/users.py
unit_kind: api
---

# ユーザー一覧 API詳細設計書
EOF
  mkdir -p "$t6_root/docs/design/apis/api-create-order/詳細設計"
  cat > "$t6_root/docs/design/apis/api-create-order/詳細設計/APIdetail-alt.md" <<'EOF'
---
api_key: create-order
api_id: api-create-order
method: POST
path: /api/orders
source_ref: src/api/orders.py
unit_kind: api
---

# 注文作成 API詳細設計書(別名ファイル)
EOF
  t6_out="$t6_root/out"
  mkdir -p "$t6_out"
  # 1-66: 検査7と同じ理由(kindMappingでapiのkindがendpointへ解決されるため、
  # sourceFile-実在検査がsource_refの実在を要求する)でダミーの実体を用意する。
  mkdir -p "$t6_out/docs/design/apis/src/api"
  : > "$t6_out/docs/design/apis/src/api/users.py"
  : > "$t6_out/docs/design/apis/src/api/orders.py"
  t6_decl="$(doc_extraction_load | jq '.kinds.api.docFileName = ["API詳細設計書.md", "APIdetail-alt.md"]')"
  t6_layout="$(resolve_output_layout "$t6_root")"
  if build_manifest_for_kind "$t6_decl" "$t6_layout" "$t6_root" "$t6_out" api >/dev/null 2>&1; then
    [ "$(jq -r '.detectionSummary.unitCount' "$t6_out/api-manifest.json" 2>/dev/null)" = "2" ] || ok6=0
    [ "$(jq -r '[.units[].unitKey] | sort | join(",")' "$t6_out/api-manifest.json" 2>/dev/null)" = "create-order,get-users" ] || ok6=0
  else
    ok6=0
  fi
  rm -rf "$t6_root"
  if [ "$ok6" -eq 1 ]; then
    echo "  [PASS] 検査6: docFileNameの配列化で両方の候補ファイルが抽出される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査6: 配列化した候補の抽出に不一致がある" >&2
    fail=$((fail + 1))
  fi

  # 検査7(改善課題1-67・1-66の不変条件も兼ねる): unitKey・sourceFileのマッピング元
  #        frontmatterキーが空・不在の合成データで実行しても、validate-manifest.shの
  #        必須フィールド検査を通ること(代替値で埋まること)。あわせて、代替値で埋まった
  #        行のkindがunresolvedのままであること(sourceFile-実在検査に引っかからないための
  #        不変条件)。このフィクスチャはmethod・pathを持つため改善課題1-66のkindMapping
  #        条件(必須フィールドが揃っている)を満たすが、unitKey・sourceFileの元となる
  #        api_key・source_refを欠く。kindMappingの条件を満たしていてもkindが解決されず
  #        unresolvedのままであることを、この1本で両課題にまたがって検証する。
  local t7_root t7_out ok7=1
  t7_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t7.XXXXXX")"
  mkdir -p "$t7_root/docs/design/apis/api-noident/詳細設計"
  cat > "$t7_root/docs/design/apis/api-noident/詳細設計/API詳細設計書.md" <<'EOF'
---
method: GET
path: /api/noident
unit_kind: api
---

# 識別子未記入 API詳細設計書
EOF
  t7_out="$t7_root/out"
  mkdir -p "$t7_out"
  if ! bash "$self_path" "$t7_root" "$t7_out" --unit-kind api >/dev/null 2>&1; then
    ok7=0
  fi
  [ "$(jq -r '.units[0].unitKey' "$t7_out/api-manifest.json" 2>/dev/null)" = "未確認" ] || ok7=0
  [ "$(jq -r '.units[0].sourceFile' "$t7_out/api-manifest.json" 2>/dev/null)" = "未確認" ] || ok7=0
  [ "$(jq -r '.units[0].kind' "$t7_out/api-manifest.json" 2>/dev/null)" = "unresolved" ] || ok7=0
  if ! bash "$VALIDATE_MANIFEST_SH" "$t7_out/api-manifest.json" --unit-kind api >/dev/null 2>&1; then
    ok7=0
  fi
  rm -rf "$t7_root"
  if [ "$ok7" -eq 1 ]; then
    echo "  [PASS] 検査7: unitKey/sourceFile不在の合成データでも代替値で埋まりkind=unresolvedのままvalidateを通る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査7: unitKey/sourceFile不在時の代替値埋めが不正" >&2
    fail=$((fail + 1))
  fi

  # 検査8(指示書「種別の判定材料をテンプレートへ足す」): kindMapping.valueFrom宣言のある
  #        table/batch/report/externalは、判定材料の欄(table_subkind等)がfrontmatterに
  #        存在しallowedValuesに含まれる場合、その値がkindとして解決されること
  local ok8=1
  [ "$(jq -r '.units[0].kind' "$out/table-manifest.json" 2>/dev/null)" = "table" ] || ok8=0
  [ "$(jq -r '.units[0].kind' "$out/batch-manifest.json" 2>/dev/null)" = "scheduled" ] || ok8=0
  [ "$(jq -r '.units[0].kind' "$out/report-manifest.json" 2>/dev/null)" = "template" ] || ok8=0
  [ "$(jq -r '.units[0].kind' "$out/external-manifest.json" 2>/dev/null)" = "client" ] || ok8=0
  [ "$(jq -r '.units[0].confidence' "$out/table-manifest.json" 2>/dev/null)" = "high" ] || ok8=0
  [ "$(jq -r '.units[0].detectionMethod' "$out/table-manifest.json" 2>/dev/null)" = "document-frontmatter" ] || ok8=0
  [ "$(jq -r '.strategy.extractionMethod' "$out/table-manifest.json" 2>/dev/null)" = "document-frontmatter" ] || ok8=0
  if [ "$ok8" -eq 1 ]; then
    echo "  [PASS] 検査8: 種別の判定材料の欄を埋めた場合にkindが解決される" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査8: 種別の判定材料の欄を埋めた場合のkind解決が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査9(指示書「種別の判定材料をテンプレートへ足す」): 判定材料の欄がfrontmatterに
  #        存在しない場合、kindMapping.valueFromが宣言されていてもkindはunresolvedの
  #        まま解決されない(捏造しない)こと
  local t9_root t9_out ok9=1
  t9_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t9.XXXXXX")"
  mkdir -p "$t9_root/docs/design/tables/table-orders/詳細設計"
  cat > "$t9_root/docs/design/tables/table-orders/詳細設計/テーブル定義書.md" <<'EOF'
---
table_key: orders
table_id: table-orders
table_name: 注文
source_ref: src/models/orders.py
unit_kind: table
status: draft
---

# 注文 テーブル定義書
EOF
  t9_out="$t9_root/out"
  mkdir -p "$t9_out"
  if ! bash "$self_path" "$t9_root" "$t9_out" --unit-kind table >/dev/null 2>&1; then
    ok9=0
  fi
  [ "$(jq -r '.units[0].kind' "$t9_out/table-manifest.json" 2>/dev/null)" = "unresolved" ] || ok9=0
  if ! bash "$VALIDATE_MANIFEST_SH" "$t9_out/table-manifest.json" --unit-kind table >/dev/null 2>&1; then
    ok9=0
  fi
  rm -rf "$t9_root"
  if [ "$ok9" -eq 1 ]; then
    echo "  [PASS] 検査9: 種別の判定材料の欄を埋めない場合はkindがunresolvedのまま" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査9: 欄を埋めない場合のkind解決が不正(unresolvedになっていない)" >&2
    fail=$((fail + 1))
  fi

  # 検査10(改善課題1-68): table/batch/externalは、各種別のaggregateDocumentExtraction
  # 宣言で指定された単一文書の節・表から3件ずつ抽出できること。個別文書は置かず、
  # 集約経路だけを通す。先に実行した検査1/8は従来の個別文書経路の件数・内容を確認する。
  local t10_root t10_out ok10=1
  t10_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t10.XXXXXX")"
  mkdir -p "$t10_root/docs/design/tables" "$t10_root/docs/design/batches" "$t10_root/docs/design/externals"
  cat > "$t10_root/docs/design/tables/テーブル一覧.md" <<'EOF'
# データ設計
## テーブル: users
| キー | ID | ソース参照 | 種別 |
| --- | --- | --- | --- |
| users | table-users | src/models/users.py | table |
## テーブル: orders
| キー | ID | ソース参照 | 種別 |
| --- | --- | --- | --- |
| orders | table-orders | src/models/orders.py | table |
## テーブル: audit_logs
| キー | ID | ソース参照 | 種別 |
| --- | --- | --- | --- |
| audit-logs | table-audit-logs | src/models/audit_logs.py | migration |
EOF
  cat > "$t10_root/docs/design/batches/バッチ一覧.md" <<'EOF'
# バッチ設計
## バッチ: cleanup
| キー | ID | ソース参照 | 起動種別 |
| --- | --- | --- | --- |
| cleanup | batch-cleanup | src/batches/cleanup.py | scheduled |
## バッチ: import
| キー | ID | ソース参照 | 起動種別 |
| --- | --- | --- | --- |
| import | batch-import | src/batches/import.py | triggered |
## バッチ: archive
| キー | ID | ソース参照 | 起動種別 |
| --- | --- | --- | --- |
| archive | batch-archive | src/batches/archive.py | scheduled |
EOF
  cat > "$t10_root/docs/design/externals/外部連携一覧.md" <<'EOF'
# 外部連携設計
## 外部連携: payment
| キー | ID | ソース参照 | 方向 |
| --- | --- | --- | --- |
| payment | external-payment | src/externals/payment.py | client |
## 外部連携: notify
| キー | ID | ソース参照 | 方向 |
| --- | --- | --- | --- |
| notify | external-notify | src/externals/notify.py | webhook |
## 外部連携: identity
| キー | ID | ソース参照 | 方向 |
| --- | --- | --- | --- |
| identity | external-identity | src/externals/identity.py | client |
EOF
  t10_out="$t10_root/out"
  mkdir -p "$t10_out/docs/design/tables/src/models" "$t10_out/docs/design/batches/src/batches" "$t10_out/docs/design/externals/src/externals"
  : > "$t10_out/docs/design/tables/src/models/users.py"
  : > "$t10_out/docs/design/tables/src/models/orders.py"
  : > "$t10_out/docs/design/tables/src/models/audit_logs.py"
  : > "$t10_out/docs/design/batches/src/batches/cleanup.py"
  : > "$t10_out/docs/design/batches/src/batches/import.py"
  : > "$t10_out/docs/design/batches/src/batches/archive.py"
  : > "$t10_out/docs/design/externals/src/externals/payment.py"
  : > "$t10_out/docs/design/externals/src/externals/notify.py"
  : > "$t10_out/docs/design/externals/src/externals/identity.py"
  for k in table batch external; do
    if ! bash "$self_path" "$t10_root" "$t10_out" --unit-kind "$k" >/dev/null 2>&1; then
      ok10=0
    fi
    [ "$(jq -r '.detectionSummary.unitCount' "$t10_out/${k}-manifest.json" 2>/dev/null)" = "3" ] || ok10=0
    [ "$(jq -r '.strategy.extractionMethod' "$t10_out/${k}-manifest.json" 2>/dev/null)" = "document-aggregate-table" ] || ok10=0
  done
  [ "$(jq -r '[.units[].unitKey] | sort | join(",")' "$t10_out/table-manifest.json" 2>/dev/null)" = "audit-logs,orders,users" ] || ok10=0
  # 集約一覧は単位資料ではない。単位フォルダを置かないこのケースでは、実在しない
  # 単位資料へのPathを作らないことを確認する。
  jq -e '[.units[] | to_entries[] | select(.key | test("Path$"))] | length == 0' \
    "$t10_out/table-manifest.json" >/dev/null 2>&1 || ok10=0
  # 安全なunitIdが所定の単位フォルダに一致する正常系では資料Pathを補う。
  mkdir -p "$t10_root/docs/design/tables/table-users/基本設計" "$t10_root/list"
  : > "$t10_root/docs/design/tables/table-users/基本設計/論理データモデル.md"
  local t10_layout valid_units valid_enriched
  t10_layout="$(resolve_output_layout "$t10_root")"
  valid_units='[{"unitId":"table-users","unitKey":"users"}]'
  valid_enriched="$(append_aggregate_document_paths "$valid_units" "$(doc_extraction_load)" \
    "$t10_layout" table "$t10_root/docs/design/tables" "$t10_root/list")" || ok10=0
  jq -e '.[0].designDocPath | type == "string" and length > 0' \
    <<<"$valid_enriched" >/dev/null 2>&1 || ok10=0
  # 不正なunitIdがroot外の同名資料を指し、unitKey fallback先にも別単位の同名資料が
  # ある場合でも、どちらも参照しない。
  mkdir -p "$t10_root/docs/design/escape/基本設計" \
    "$t10_root/docs/design/tables/table-escape/基本設計" "$t10_root/list"
  : > "$t10_root/docs/design/escape/基本設計/論理データモデル.md"
  : > "$t10_root/docs/design/tables/table-escape/基本設計/論理データモデル.md"
  local malicious_units malicious_enriched
  malicious_units='[{"unitId":"../escape","unitKey":"escape"}]'
  malicious_enriched="$(append_aggregate_document_paths "$malicious_units" "$(doc_extraction_load)" \
    "$t10_layout" table "$t10_root/docs/design/tables" "$t10_root/list")" || ok10=0
  jq -e '[.[] | to_entries[] | select(.key | test("Path$"))] | length == 0' \
    <<<"$malicious_enriched" >/dev/null 2>&1 || ok10=0
  rm -rf "$t10_root"
  if [ "$ok10" -eq 1 ]; then
    echo "  [PASS] 検査10(1-68/1-249): 集約3種別を抽出し、不正unitIdのroot外・別単位資料Pathは付与しない" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査10(1-68/1-249): 集約文書からの抽出件数・抽出方式または単位資料Pathが不正" >&2
    fail=$((fail + 1))
  fi

  # 検査11(改善課題1-254): 単位フォルダを2つ用意し、片方だけ設計文書が実在する場合、
  #        単位フォルダの数(2)と組み立てられた件数(1)の食い違いがWARNとして出て、
  #        終了コードは0のまま続くこと。
  local t11_root t11_out t11_output t11_rc ok11=1
  t11_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t11.XXXXXX")"
  mkdir -p "$t11_root/docs/design/features/feature-with-doc" \
    "$t11_root/docs/design/features/feature-without-doc"
  cat > "$t11_root/docs/design/features/feature-with-doc/機能設計書.md" <<'EOF'
---
feature_key: with-doc
feature_id: feature-with-doc
category: 会員管理
source_ref: src/features/with_doc.py
unit_kind: feature
---

# 設計書ありの機能設計書
EOF
  t11_out="$t11_root/out"
  mkdir -p "$t11_out"
  t11_output="$(bash "$self_path" "$t11_root" "$t11_out" --unit-kind feature 2>&1)"
  t11_rc=$?
  [ "$t11_rc" -eq 0 ] || ok11=0
  printf '%s' "$t11_output" | grep -q "WARN" || ok11=0
  printf '%s' "$t11_output" | grep -q "単位フォルダの数(2)と一覧の元データへ組み立てられた件数(1)" || ok11=0
  [ "$(jq -r '.detectionSummary.unitCount' "$t11_out/feature-manifest.json" 2>/dev/null)" = "1" ] || ok11=0
  rm -rf "$t11_root"
  if [ "$ok11" -eq 1 ]; then
    echo "  [PASS] 検査11(1-254): 単位フォルダの数と組み立て件数の食い違いがWARNとして出て終了コードは0のまま" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査11(1-254): 単位フォルダ数と組み立て件数の食い違い検知が不正" >&2
    fail=$((fail + 1))
  fi

  # 検査12(改善課題1-254): 単位フォルダを1つも持たない種別(0件が正しい種別)では、
  #        食い違いのWARNが出ないこと。検査4と同じ空rootを使うが、WARN文言の有無まで見る。
  local t12_root t12_out t12_output ok12=1
  t12_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t12.XXXXXX")"
  t12_out="$t12_root/out"
  mkdir -p "$t12_out"
  t12_output="$(bash "$self_path" "$t12_root" "$t12_out" --unit-kind feature 2>&1)"
  [ $? -eq 0 ] || ok12=0
  printf '%s' "$t12_output" | grep -q "WARN" && ok12=0
  rm -rf "$t12_root"
  if [ "$ok12" -eq 1 ]; then
    echo "  [PASS] 検査12(1-254): 単位フォルダが0件の種別では食い違いのWARNが出ない" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査12(1-254): 単位フォルダ0件時にWARNが誤って出た" >&2
    fail=$((fail + 1))
  fi

  # 検査13(改善課題1-254): 設計書を持つ単位フォルダが実在するが、正規の命名
  #        (<kind>-<単位ID>)と一致しない場合、単位フォルダの数(folder_count)が0のまま
  #        検査11の食い違い検知(folder_count>=1が前提)をすり抜ける。この場合でも、
  #        命名不一致のWARNが出て終了コードは0のまま続くこと。
  local t13_root t13_out t13_output t13_rc ok13=1
  t13_root="$(mktemp -d "${TMPDIR:-/tmp}/build-manifests-from-docs-t13.XXXXXX")"
  mkdir -p "$t13_root/docs/design/features/user-management"
  cat > "$t13_root/docs/design/features/user-management/機能設計書.md" <<'EOF'
---
feature_key: user-management
feature_id: feature-user-management
category: 会員管理
source_ref: src/features/user_management.py
unit_kind: feature
---

# 会員管理 機能設計書
EOF
  t13_out="$t13_root/out"
  mkdir -p "$t13_out"
  t13_output="$(bash "$self_path" "$t13_root" "$t13_out" --unit-kind feature 2>&1)"
  t13_rc=$?
  [ "$t13_rc" -eq 0 ] || ok13=0
  printf '%s' "$t13_output" | grep -q "WARN" || ok13=0
  printf '%s' "$t13_output" | grep -q "単位フォルダの命名が正規の形" || ok13=0
  [ "$(jq -r '.detectionSummary.unitCount' "$t13_out/feature-manifest.json" 2>/dev/null)" = "0" ] || ok13=0
  rm -rf "$t13_root"
  if [ "$ok13" -eq 1 ]; then
    echo "  [PASS] 検査13(1-254): 正規の命名でない単位フォルダはfolder_count=0でも命名不一致のWARNが出る" >&2
    pass=$((pass + 1))
  else
    echo "  [FAIL] 検査13(1-254): 命名不一致時のWARN検知が不正" >&2
    fail=$((fail + 1))
  fi

  echo "self-test: ${pass} PASS, ${fail} FAIL" >&2
  [ "$fail" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  if self_test; then exit 0; else exit 1; fi
fi

output_dir="${1:?引数1 output_dir が必要です}"
dest_dir="${2:?引数2 出力先ディレクトリ が必要です}"
shift 2

unit_kind_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unit-kind)
      unit_kind_arg="${2:?--unit-kind には種別が必要です}"
      shift 2
      ;;
    *)
      echo "Usage: build-manifests-from-docs.sh <output_dir> <出力先ディレクトリ> [--unit-kind <種別>]" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$output_dir" ]; then
  echo "ERROR: output_dir が存在しません: $output_dir" >&2
  exit 1
fi

decl_json="$(doc_extraction_load)" || exit 1
layout_json="$(resolve_output_layout "$output_dir")" || exit 1

kinds_to_process=""
if [ -n "$unit_kind_arg" ]; then
  if ! printf '%s' "$decl_json" | jq -e --arg k "$unit_kind_arg" '.kinds | has($k)' >/dev/null 2>&1; then
    echo "ERROR: 宣言に存在しない種別です: $unit_kind_arg" >&2
    exit 1
  fi
  kinds_to_process="$unit_kind_arg"
else
  kinds_to_process="$(doc_extraction_kinds "$decl_json")"
fi

overall_rc=0
for kind in $kinds_to_process; do
  echo "=== 種別 $kind の抽出 ===" >&2
  if ! build_manifest_for_kind "$decl_json" "$layout_json" "$output_dir" "$dest_dir" "$kind"; then
    echo "ERROR: 種別 $kind のマニフェスト検証に失敗しました" >&2
    overall_rc=1
  fi
done

exit $overall_rc
