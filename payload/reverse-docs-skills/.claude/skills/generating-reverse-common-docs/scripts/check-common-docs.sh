#!/usr/bin/env bash
set -euo pipefail

# check-common-docs.sh — 共通6文書と横断根拠台帳の機械ゲート
#
# 使い方:
#   check-common-docs.sh <common_docs_dir> <target_repo_path>
#   check-common-docs.sh --self-test
#
# <common_docs_dir> は `<output_dir>` を指す（output-layout.json の commonRoot 配下に共通6文書を持つ親ディレクトリ）。
# 共通文書本文の対象コードの位置は、crossCuttingDesignRoot 配下の横断根拠台帳へ分離する。
# 規約4文書（コーディング規約・命名規約・ディレクトリ構成規約・コンポーネント設計規約）は
# コードからの採録をやめ空雛形へ変更済みのため、本ゲートの走査対象から除外する。サンプル記録も対象外。
#
# 検査（検査2・5は規約4文書の非採録化に伴い撤去。番号は繰り上げない＝欠番）:
#   1. 実在検査: 定義ファイルで依存する種別が除外されていない共通文書がすべて実在する。
#      依存種別が除外されている文書は「対象なし」として根拠とともに出力する。
#   3. パス実在検査: 共通設計書.md＋メッセージ定義書.md＋DESIGN.md内の
#      backtick囲み相対パス全件が target_repo_path 配下に test -e で実在する。
#      除外規則: URL・glob・プレースホルダ・絶対パス・空白/正規表現記号を含む
#      トークンは対象外。
#   4. テンプレ残存ゼロ: 開き括弧付きの形（<実測|<FILL|<TBD|<TODO）、または行/セル全体が
#      ちょうどTBD/TODOだけであるプレースホルダそのものの形が永続6文書すべてで0件。
#      TBD/TODOという語自体を地の文で言及すること（裸の語）は検出しない（1-153）。
#   6. メッセージ定義書規模突合: メッセージ定義書.md内の規模宣言行
#      （「総件数: <N>件」形式）と、同ファイル内のbacktickメッセージ文字列を
#      含むテーブル行の実測件数が一致する。宣言行が無い場合もFAILとする
#      （カタログ規模の推測表現を禁止するための機械検証）。
#
#   7. 必須節検査: 定義ファイルで必須節を持つ文書に、Markdown見出しとして
#      必須節がすべて無ければFAIL。
#   8. 根拠分離検査: 共通6文書に根拠列・抽出元列・file:line 注記が無い。
#   9. 横断根拠台帳検査: 台帳に対象文書・節/項目・対象コード・行の対応があり、
#      対象コードの実在と行番号の範囲を確認できる。
#  10. 宣言整合検査: output-layout と deliverable-inventory が同じ横断根拠台帳を宣言する。
#   いずれか1件でも違反があれば exit 1（fail-closed）。全件PASSでexit 0。
#   --self-test は合成フィクスチャで陽性exit 0・陰性(検査ごと)exit 1を自己検証する。
#
# 設計判断（ADR）の正本は本スキルの SKILL.md「## 設計判断」に記載する。
# 保守責任者: 人手（ユーザー）。検査基準・除外規則を変更した時に更新する。
# macOS bash 3.2 互換（mapfile 不使用）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# shellcheck source=../../../../generation-engine/scripts/output-layout.sh
. "$REPO_ROOT/generation-engine/scripts/output-layout.sh"

if [ "${1:-}" = "--self-test" ]; then
  LAYOUT_JSON="$(resolve_output_layout "")" || exit 1
else
  LAYOUT_JSON="$(resolve_output_layout "${1:-}")" || exit 1
fi

DOCUMENT_DEFINITIONS_FILE="$SCRIPT_DIR/../references/common-document-definitions.json"
[ -f "$DOCUMENT_DEFINITIONS_FILE" ] || { echo "エラー: 共通文書定義が見つかりません: $DOCUMENT_DEFINITIONS_FILE" >&2; exit 1; }
jq -e '.documents | type == "array" and length == 6' "$DOCUMENT_DEFINITIONS_FILE" >/dev/null \
  || { echo "エラー: 共通文書定義が不正です: $DOCUMENT_DEFINITIONS_FILE" >&2; exit 1; }
jq -e '.commonEvidenceLedger | type == "object" and (.layoutKey | type == "string") and (.inventoryKind | type == "string") and (.requiredColumns == ["対象文書", "節・項目", "対象コード", "行"])' "$DOCUMENT_DEFINITIONS_FILE" >/dev/null \
  || { echo "エラー: 横断根拠台帳の定義が不正です: $DOCUMENT_DEFINITIONS_FILE" >&2; exit 1; }
# 検査3（パス実在検査）の対象は共通設計書・メッセージ定義書・DESIGN.mdの3文書
PATH_CHECK_FILES="$(output_layout_get "$LAYOUT_JSON" commonDesignDoc) $(output_layout_get "$LAYOUT_JSON" messageDoc) $(output_layout_get "$LAYOUT_JSON" designDoc)"
MESSAGE_DOC_FILE="$(output_layout_get "$LAYOUT_JSON" messageDoc)"
COMMON_EVIDENCE_LEDGER_LAYOUT_KEY="$(jq -r '.commonEvidenceLedger.layoutKey' "$DOCUMENT_DEFINITIONS_FILE")"
COMMON_EVIDENCE_LEDGER_INVENTORY_KIND="$(jq -r '.commonEvidenceLedger.inventoryKind' "$DOCUMENT_DEFINITIONS_FILE")"
COMMON_EVIDENCE_LEDGER_FILE="$(output_layout_get "$LAYOUT_JSON" "$COMMON_EVIDENCE_LEDGER_LAYOUT_KEY")"
DELIVERABLE_INVENTORY_FILE="$REPO_ROOT/delivery-payload/references/deliverable-inventory.json"
PLACEHOLDER_RE='<実測|<FILL|TBD|TODO'
MESSAGE_SCALE_RE='総件数[:：] *[0-9]+件'

document_records() {
  jq -c '.documents[]' "$DOCUMENT_DEFINITIONS_FILE"
}

excluded_kind_reason() {
  local excluded_json="$1" kind="$2"
  [ -f "$excluded_json" ] || return 1
  jq -r --arg kind "$kind" '
    .excludedKinds[]? |
    if type == "string" then
      select(. == $kind) | "種別の除外宣言"
    else
      select((.kind // "") == $kind) | (.reason // "種別の除外宣言")
    end
  ' "$excluded_json" 2>/dev/null | head -n1
}

# $1=出力先 $2=定義レコード。対象なしなら根拠を標準出力して1、対象なら0。
document_is_applicable() {
  local dir="$1" record="$2" excluded_json kind reason
  excluded_json="$dir/$(output_layout_get "$LAYOUT_JSON" excludedKinds)"
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    reason="$(excluded_kind_reason "$excluded_json" "$kind" || true)"
    if [ -n "$reason" ]; then
      printf '%s\n' "$kind: $reason"
      return 1
    fi
  done <<EOF
$(printf '%s' "$record" | jq -r '.dependsOnKinds[]?')
EOF
  return 0
}

document_path() {
  local record="$1" key
  key="$(printf '%s' "$record" | jq -r '.layoutKey')"
  output_layout_get "$LAYOUT_JSON" "$key"
}

# backtick囲みトークンのうち「相対パス」とみなせるもの以外を除外する判定。
# 除外: 「/」を含まない / URL / glob / プレースホルダ / 絶対パス / 空白・正規表現記号を含む
is_path_candidate() {
  tok="$1"
  case "$tok" in
    */*) : ;;
    *) return 1 ;;
  esac
  case "$tok" in
    *'://'*|*'*'*|*'?'*|*'<'*|*'>'*|/*|*' '*|*'\'*|*'"'*|*"'"*|*'('*|*')'*|*'|'*|*'['*|*']'*|*'^'*|*'$'*|*'+'*|*'{'*|*'}'*)
      return 1 ;;
  esac
  return 0
}

extract_backtick_tokens() {
  grep -oE '`[^`]+`' "$1" 2>/dev/null | sed -E 's/^`//; s/`$//' || true
}

# 表の区切り行（|---|---|等）かどうかを判定する
is_separator_row() {
  line="$1"
  stripped="$(printf '%s' "$line" | tr -d '|:\- ')"
  [ -z "$stripped" ]
}

# 検査1: 実在検査（定義上の対象文書）
check_files_exist() {
  local dir="$1" missing=0 record f label exclusion
  while IFS= read -r record; do
    f="$(document_path "$record")"
    label="$(printf '%s' "$record" | jq -r '.label')"
    if ! exclusion="$(document_is_applicable "$dir" "$record")"; then
      echo "  対象なし: ${f}（${exclusion}）"
      continue
    fi
    if [ ! -f "$dir/$f" ]; then
      echo "  未実在: $f" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$(document_records)
EOF
  if [ "$missing" -gt 0 ]; then
    echo "検査1失敗: 定義上の共通文書中 $missing 件が未実在です" >&2
    return 1
  fi
  echo "検査1通過: 定義上の共通文書すべて実在"
  return 0
}

# 検査3: パス実在検査（共通設計書＋メッセージ定義書＋DESIGN.md）
check_paths_exist() {
  dir="$1"
  repo="$2"
  missing=0
  total=0
  for f in $PATH_CHECK_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || continue
    tokens="$(extract_backtick_tokens "$path")"
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      if ! is_path_candidate "$tok"; then
        continue
      fi
      total=$((total + 1))
      checkpath="$tok"
      case "$checkpath" in
        ./*) checkpath="${checkpath#./}" ;;
      esac
      if [ ! -e "$repo/$checkpath" ]; then
        echo "  未実在: $f: $tok" >&2
        missing=$((missing + 1))
      fi
    done <<EOF
$tokens
EOF
  done
  if [ "$missing" -gt 0 ]; then
    echo "検査3失敗: 記載パス $total 件中 $missing 件が target_repo_path 配下に実在しません" >&2
    return 1
  fi
  echo "検査3通過: 記載パス $total 件すべて実在（対象0件を含む）"
  return 0
}

# 未置換のプレースホルダと、規約として正当に言及した語を区別する（1-153）。
# <実測/<FILL と同様、TBD/TODOも裸の語（文中に埋め込まれた語）では検出せず、次の2形式に限定する。
#   (a) 雛形記法と同じ開き括弧付きの形: <実測 / <FILL / <TBD / <TODO
#   (b) 行全体、またはMarkdown表のセル全体がプレースホルダそのものである形
#         （例: セル内容がちょうど "TBD" だけ／"TODO" だけ）
# 正当な言及を通す記法（規約・調査書の本文でTODO/TBDという語自体を説明する場合）は、
# バッククォートで囲んだ開き括弧付き形（`<TBD ...>`）にせず、地の文にそのまま書く。
placeholder_residue_hits() { # $1=file -> "行番号:該当行" を1件1行で列挙（0件なら出力なし）
  local file="$1" line lineno=0 cell trimmed hit
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    hit=0
    if printf '%s' "$line" | grep -qE -- '<実測|<FILL|<TBD|<TODO'; then
      hit=1
    elif printf '%s' "$line" | grep -q '|'; then
      local cells=()
      IFS='|' read -r -a cells <<<"$line"
      for cell in "${cells[@]}"; do
        trimmed="$(printf '%s' "$cell" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
        if [ "$trimmed" = "TBD" ] || [ "$trimmed" = "TODO" ]; then
          hit=1
          break
        fi
      done
    else
      trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/`//g')"
      if [ "$trimmed" = "TBD" ] || [ "$trimmed" = "TODO" ]; then
        hit=1
      fi
    fi
    [ "$hit" -eq 1 ] && printf '%d:%s\n' "$lineno" "$line"
  done < "$file"
}

# 検査4: テンプレ残存ゼロ（永続6ファイル）
check_no_placeholder() {
  local dir="$1" hit_total=0 record f exclusion
  while IFS= read -r record; do
    f="$(document_path "$record")"
    document_is_applicable "$dir" "$record" >/dev/null || continue
    path="$dir/$f"
    [ -f "$path" ] || continue
    hits="$(placeholder_residue_hits "$path" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      echo "  テンプレ残存: $f" >&2
      echo "$hits" >&2
      hit_total=$((hit_total + 1))
    fi
  done <<EOF
$(document_records)
EOF
  if [ "$hit_total" -gt 0 ]; then
    echo "検査4失敗: $hit_total ファイルにテンプレ残存トークンを検出" >&2
    return 1
  fi
  echo "検査4通過: 定義上の共通文書すべてテンプレ残存0件"
  return 0
}

# コードフェンス外にあるATX見出し（#〜######）だけを列挙する。
markdown_heading_lines() {
  awk '
    function strip_optional_indent(value) {
      if (value ~ /^   /) sub(/^   /, "", value)
      else if (value ~ /^  /) sub(/^  /, "", value)
      else sub(/^ /, "", value)
      return value
    }
    function marker_prefix_length(value, marker, count) {
      count = 0
      while (substr(value, count + 1, 1) == marker) count++
      return count
    }
    {
      line = strip_optional_indent($0)
      if (fence != "") {
        marker_count = marker_prefix_length(line, fence)
        if (marker_count >= fence_length && substr(line, marker_count + 1) ~ /^[ \t]*$/) {
          fence = ""
          fence_length = 0
        }
        next
      }
      marker = substr(line, 1, 1)
      if (marker == "`" || marker == "~") {
        marker_count = marker_prefix_length(line, marker)
        if (marker_count >= 3) {
          fence = marker
          fence_length = marker_count
          next
        }
      }
      marker_count = marker_prefix_length(line, "#")
      separator = substr(line, marker_count + 1, 1)
      if (marker_count >= 1 && marker_count <= 6 && separator ~ /[ \t]/) print line
    }
  ' "$1"
}

markdown_heading_contains() {
  local file="$1" required="$2" heading
  while IFS= read -r heading; do
    case "$heading" in
      *"$required"*) return 0 ;;
    esac
  done <<EOF
$(markdown_heading_lines "$file")
EOF
  return 1
}

# 検査7: 画面前提文書の主題逸脱検知。Markdown見出しの必須節が欠ける文書は別主題とみなす。
check_required_sections() {
  local dir="$1" failed=0 record f label section_count required_count section exclusion
  while IFS= read -r record; do
    required_count="$(printf '%s' "$record" | jq '.requiredSections | length')"
    [ "$required_count" -gt 0 ] || continue
    document_is_applicable "$dir" "$record" >/dev/null || continue
    f="$(document_path "$record")"
    [ -f "$dir/$f" ] || continue
    section_count=0
    while IFS= read -r section; do
      markdown_heading_contains "$dir/$f" "$section" && section_count=$((section_count + 1))
    done <<EOF
$(printf '%s' "$record" | jq -r '.requiredSections[]')
EOF
    if [ "$section_count" -ne "$required_count" ]; then
      label="$(printf '%s' "$record" | jq -r '.label')"
      echo "  必須節不足: ${f}（${label} の必須節 ${required_count} 件中${section_count}件）" >&2
      failed=$((failed + 1))
    fi
  done <<EOF
$(document_records)
EOF
  if [ "$failed" -gt 0 ]; then
    echo "検査7失敗: $failed 文書にテンプレート必須節の不足があります" >&2
    return 1
  fi
  echo "検査7通過: 必須節を持つ対象文書はすべての必須節をMarkdown見出しとして含む"
  return 0
}

# 検査8: 共通文書本文の根拠列・抽出元列・file:line注記を禁止する。
file_line_annotation_hits() {
  awk '
    BEGIN { FS = "[[:space:]|]+" }
    {
      for (i = 1; i <= NF; i++) {
        token = $i
        if (index(token, "://") == 0 && token ~ /\/.*:[1-9][0-9]*([^0-9]|$)/) {
          print NR ":" $0
          next
        }
      }
    }
  ' "$1"
}

check_common_doc_evidence_separation() {
  local dir="$1" record f path column_hits annotation_hits failed=0
  while IFS= read -r record; do
    f="$(document_path "$record")"
    document_is_applicable "$dir" "$record" >/dev/null || continue
    path="$dir/$f"
    [ -f "$path" ] || continue
    column_hits="$(grep -nE '^\|.*(根拠|抽出元).*\|[[:space:]]*$' "$path" 2>/dev/null || true)"
    annotation_hits="$(file_line_annotation_hits "$path" 2>/dev/null || true)"
    if [ -n "$column_hits$annotation_hits" ]; then
      echo "  本文へ残った根拠: $f" >&2
      [ -z "$column_hits" ] || echo "$column_hits" >&2
      [ -z "$annotation_hits" ] || echo "$annotation_hits" >&2
      failed=$((failed + 1))
    fi
  done <<EOF
$(document_records)
EOF
  if [ "$failed" -gt 0 ]; then
    echo "検査8失敗: $failed 文書に根拠列・抽出元列またはfile:line注記が残っています" >&2
    return 1
  fi
  echo "検査8通過: 共通6文書の本文に根拠列・抽出元列・file:line注記がない"
  return 0
}

trim_cell() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^`//; s/`$//'
}

# Markdown表の1行を、エスケープされていない縦棒だけで分割する。
# 出力は「列数 RS 列1 RS ...」。\| はセル内の文字として復元する。
parse_markdown_table_row() {
  awk '
    BEGIN { separator = sprintf("%c", 28) }
    {
      if (substr($0, 1, 1) != "|" || substr($0, length($0), 1) != "|") exit 2
      count = 0
      cell = ""
      escaped = 0
      for (i = 2; i <= length($0); i++) {
        char = substr($0, i, 1)
        if (escaped) {
          if (char == "|") cell = cell char
          else cell = cell "\\" char
          escaped = 0
        } else if (char == "\\") {
          escaped = 1
        } else if (char == "|") {
          values[++count] = cell
          cell = ""
        } else {
          cell = cell char
        }
      }
      if (escaped) exit 2
      printf "%d", count
      for (i = 1; i <= count; i++) printf "%s%s", separator, values[i]
      printf "\n"
    }
  '
}

# 検査9: 台帳の各行が本文の節・項目と実在する対象コードの行を対応づける。
check_common_evidence_ledger() {
  local dir="$1" repo="$2" path line parsed column_count doc section source lineno extra
  local source_path max_line rows=0 failed=0 header_seen=0 common_root record defined_record document_applicable document_file seen_docs="" separator
  path="$dir/$COMMON_EVIDENCE_LEDGER_FILE"
  common_root="$(output_layout_get "$LAYOUT_JSON" commonRoot)"
  separator="$(printf '\034')"
  if [ ! -f "$path" ]; then
    echo "  未実在: $COMMON_EVIDENCE_LEDGER_FILE" >&2
    echo "検査9失敗: 横断根拠台帳がありません" >&2
    return 1
  fi
  while IFS= read -r line; do
    case "$line" in
      '|'*) : ;;
      *) continue ;;
    esac
    if ! parsed="$(printf '%s\n' "$line" | parse_markdown_table_row)"; then
      echo "  解析不能な表行: $line" >&2
      failed=$((failed + 1))
      continue
    fi
    IFS="$separator" read -r column_count doc section source lineno extra <<EOF
$parsed
EOF
    doc="$(trim_cell "$doc")"
    section="$(trim_cell "$section")"
    source="$(trim_cell "$source")"
    lineno="$(trim_cell "$lineno")"
    if [ "$doc" = "対象文書" ] || [ "$section" = "節・項目" ]; then
      if [ "$column_count" -ne 4 ] || [ "$doc" != "対象文書" ] || [ "$section" != "節・項目" ] \
        || [ "$source" != "対象コード" ] || [ "$lineno" != "行" ]; then
        echo "  必須列不正: $line" >&2
        failed=$((failed + 1))
      else
        header_seen=1
      fi
      continue
    fi
    is_separator_row "$line" && continue
    [ "$header_seen" -eq 1 ] || continue
    rows=$((rows + 1))
    if [ "$column_count" -ne 4 ] || [ -n "${extra:-}" ] || [ -z "$doc" ] || [ -z "$section" ] \
      || [ -z "$source" ] || ! printf '%s' "$lineno" | grep -qE '^[1-9][0-9]*$'; then
      echo "  不正な対応行: $line" >&2
      failed=$((failed + 1))
      continue
    fi
    defined_record=""
    document_applicable=0
    while IFS= read -r record; do
      document_file="$(document_path "$record")"
      if [ "${document_file##*/}" = "$doc" ]; then
        defined_record="$record"
        if document_is_applicable "$dir" "$record" >/dev/null; then
          document_applicable=1
        fi
        break
      fi
    done <<EOF
$(document_records)
EOF
    if [ -z "$defined_record" ]; then
      echo "  対象文書が定義外: $doc" >&2
      failed=$((failed + 1))
      continue
    fi
    if [ "$document_applicable" -eq 1 ]; then
      document_file="$dir/$common_root/$doc"
      if [ ! -f "$document_file" ]; then
        echo "  対象文書が未実在: $common_root/$doc" >&2
        failed=$((failed + 1))
        continue
      fi
      if ! grep -Fq -- "$section" "$document_file"; then
        echo "  節・項目が対象文書に未実在: $doc: $section" >&2
        failed=$((failed + 1))
        continue
      fi
      seen_docs="${seen_docs}${doc}
"
    fi
    case "$source" in /*|../*|*'/../'*) echo "  対象コードの相対パスが不正: $source" >&2; failed=$((failed + 1)); continue ;; esac
    source_path="$repo/$source"
    if [ ! -f "$source_path" ]; then
      echo "  対象コードが未実在: $source" >&2
      failed=$((failed + 1))
      continue
    fi
    max_line="$(wc -l < "$source_path" | tr -d ' ')"
    if [ "$lineno" -gt "$max_line" ]; then
      echo "  行番号が範囲外: $source:$lineno（最終行 $max_line）" >&2
      failed=$((failed + 1))
    fi
  done < "$path"
  if [ "$header_seen" -ne 1 ]; then
    echo "  必須列不足: $COMMON_EVIDENCE_LEDGER_FILE" >&2
    failed=$((failed + 1))
  fi
  while IFS= read -r record; do
    document_is_applicable "$dir" "$record" >/dev/null || continue
    document_file="$(document_path "$record")"
    doc="${document_file##*/}"
    if ! printf '%s' "$seen_docs" | grep -Fxq -- "$doc"; then
      echo "  台帳に対象文書の対応行がない: $doc" >&2
      failed=$((failed + 1))
    fi
  done <<EOF
$(document_records)
EOF
  if [ "$rows" -eq 0 ] || [ "$failed" -gt 0 ]; then
    echo "検査9失敗: 横断根拠台帳の対応行 ${rows} 件中 不正 ${failed} 件" >&2
    return 1
  fi
  echo "検査9通過: 横断根拠台帳の対応行 ${rows} 件は対象文書・節/項目・対象コード・行を対応づける"
  return 0
}

# 検査10: 配置宣言と納品物一覧の台帳kindを1つの定義に結びつける。
check_common_evidence_declarations() {
  if [ ! -f "$DELIVERABLE_INVENTORY_FILE" ]; then
    echo "検査10失敗: 納品物一覧定義がありません: $DELIVERABLE_INVENTORY_FILE" >&2
    return 1
  fi
  if ! jq -e --arg layout_key "$COMMON_EVIDENCE_LEDGER_LAYOUT_KEY" --arg inventory_kind "$COMMON_EVIDENCE_LEDGER_INVENTORY_KIND" '
    .items | any(.kind == $inventory_kind and .layoutKey == $layout_key and .evidenceSource == "none")
  ' "$DELIVERABLE_INVENTORY_FILE" >/dev/null; then
    echo "検査10失敗: output-layout の $COMMON_EVIDENCE_LEDGER_LAYOUT_KEY と納品物一覧の $COMMON_EVIDENCE_LEDGER_INVENTORY_KIND が一致しません" >&2
    return 1
  fi
  echo "検査10通過: output-layout と納品物一覧が横断根拠台帳を同じキーで宣言"
  return 0
}

# 検査6: メッセージ定義書規模突合
check_message_scale() {
  dir="$1"
  path="$dir/$MESSAGE_DOC_FILE"
  if [ ! -f "$path" ]; then
    echo "  未実在: $MESSAGE_DOC_FILE" >&2
    echo "検査6失敗: $MESSAGE_DOC_FILE が存在しません" >&2
    return 1
  fi
  declared="$(grep -oE -- "$MESSAGE_SCALE_RE" "$path" | head -n1 | grep -oE '[0-9]+' || true)"
  if [ -z "$declared" ]; then
    echo "  規模宣言欠落: $MESSAGE_DOC_FILE に「総件数: <N>件」形式の宣言行が見つかりません" >&2
    echo "検査6失敗: メッセージ定義書に規模宣言がありません" >&2
    return 1
  fi
  actual=0
  while IFS= read -r line; do
    case "$line" in
      '|'*) : ;;
      *) continue ;;
    esac
    is_separator_row "$line" && continue
    if printf '%s' "$line" | grep -qE '`[^`]+`'; then
      actual=$((actual + 1))
    fi
  done < "$path"
  if [ "$actual" -ne "$declared" ]; then
    echo "  規模不一致: $MESSAGE_DOC_FILE の宣言(${declared}件)と実測テーブル行数(${actual}件)が不一致です" >&2
    echo "検査6失敗: メッセージ定義書の宣言件数と実測件数が不一致です" >&2
    return 1
  fi
  echo "検査6通過: メッセージ定義書の宣言件数(${declared})と実測件数(${actual})が一致"
  return 0
}

# 検査1・3・4・6・7・8・9・10を実行し集約結果を返す（検査2・5は撤去済み）。
# rcはlocal必須: self_test()も同名のrcを集計に使っており、非localだと
# run_all_checksの呼び出しごとにself_test側のrc（既に検出した失敗の記録）を
# 0へ巻き戻してしまい、後続の成功呼び出しが先行失敗を握り潰す（空振りの温床）。
run_all_checks() {
  dir="$1"
  repo="$2"
  local rc=0
  check_files_exist "$dir" || rc=1
  check_paths_exist "$dir" "$repo" || rc=1
  check_no_placeholder "$dir" || rc=1
  check_message_scale "$dir" || rc=1
  check_required_sections "$dir" || rc=1
  check_common_doc_evidence_separation "$dir" || rc=1
  check_common_evidence_ledger "$dir" "$repo" || rc=1
  check_common_evidence_declarations || rc=1
  return "$rc"
}

# 合成フィクスチャによる自己テスト（陽性と検査ごとの陰性を含む）。
self_test() {
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/compiling-common-docs-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] self-test用一時ディレクトリを作成できないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  repo="$tmp/repo"
  mkdir -p "$repo/src/components" "$repo/src/utils" "$repo/src/hooks" "$repo/src/legacy"
  printf '%s\n' 'export function Button() {}' > "$repo/src/components/Button.tsx"
  : > "$repo/src/utils/format.ts"
  : > "$repo/src/hooks/useAuth.ts"
  : > "$repo/src/legacy/OldForm.tsx"

  # フィクスチャの書き込み先は宣言（output-layout.json）から解決する。
  # 旧配置（プロジェクト共通/）を直書きすると、宣言経由で別の場所を読む
  # 本番の検査処理と食い違い、検査が常に0件のまま空振りする（改善課題1-XXX相当の再発防止）。
  common_design_doc="$(output_layout_get "$LAYOUT_JSON" commonDesignDoc)"
  message_doc="$(output_layout_get "$LAYOUT_JSON" messageDoc)"
  design_doc="$(output_layout_get "$LAYOUT_JSON" designDoc)"
  foundation_doc="$(output_layout_get "$LAYOUT_JSON" foundationDoc)"
  ui_common_doc="$(output_layout_get "$LAYOUT_JSON" uiCommonDoc)"
  data_design_doc="$(output_layout_get "$LAYOUT_JSON" dataDesignDoc)"
  common_evidence_ledger="$(output_layout_get "$LAYOUT_JSON" "$COMMON_EVIDENCE_LEDGER_LAYOUT_KEY")"
  excluded_kinds_file="$(output_layout_get "$LAYOUT_JSON" excludedKinds)"
  common_root="$(output_layout_get "$LAYOUT_JSON" commonRoot)"
  sample_record_doc="$common_root/サンプル記録.md"

  build_docs() {
    target="$1"
    mkdir -p "$(dirname "$target/$common_design_doc")"
    mkdir -p "$(dirname "$target/$common_evidence_ledger")"
    mkdir -p "$(dirname "$target/$excluded_kinds_file")"
    cat > "$target/$excluded_kinds_file" <<'JSON'
{"presentKinds":["screen"],"excludedKinds":[]}
JSON
    cat > "$target/$common_design_doc" <<'MD'
# 共通設計書（リバース版）

## 本書に書かないもの

## §1 共通画面状態の規則（実測）
loading状態はスケルトン表示。

## §2 共通操作規則（実測）

保存操作を共通化する。

## §3 共通レイアウト原則（実測）

共通の余白を適用する。

## §4 要確認事項一覧

なし。
MD
    cat > "$target/$message_doc" <<'MD'
# 共通メッセージ定義書（リバース版）

総件数: 2件

## メッセージ一覧

| メッセージ | 用途 |
|---|---|
| `保存に成功しました` | 保存成功トースト |
| `保存に失敗しました` | 保存失敗トースト |
MD
    cat > "$target/$design_doc" <<'MD'
# 共通デザインシステム | リバース版

primary色は#1a73e8。
MD
    cat > "$target/$foundation_doc" <<'MD'
# 基盤設計書（リバース版）

## §1 フレームワーク構成（実測）
Reactを採用。
MD
    cat > "$target/$ui_common_doc" <<'MD'
# UI共通設計書（リバース版）

## 本書に書かないもの

## §1 デザインシステム（実測）
独自コンポーネントライブラリを使用。

## §2 共通コンポーネント一覧（実測）

Buttonを共通利用する。

## §3 レイアウト方針（実測）

レスポンシブに配置する。

## §4 テーマ・スタイル管理（実測）

CSS Modulesを使用する。

## §5 アクセシビリティ方針（実測）

aria属性を使用する。

## §6 画面横断 UI 状態（実測）

通知状態を共有する。

## traced の条件

根拠を記録する。
MD
    cat > "$target/$data_design_doc" <<'MD'
# データ設計書（リバース版）

## §1 データモデル概要（実測）
ユーザーエンティティを保有。
MD
    cat > "$target/$common_evidence_ledger" <<'MD'
# 共通文書根拠台帳

|対象文書| 節・項目|対象コード |行|
|---|---|---|---|
| 共通設計書.md | §1 共通画面状態の規則 | src/components/Button.tsx | 1 |
| メッセージ定義書.md | メッセージ一覧 | src/components/Button.tsx | 1 |
| DESIGN.md | 共通デザインシステム \| リバース版 | src/components/Button.tsx | 1 |
| 基盤設計.md | §1 フレームワーク構成 | src/components/Button.tsx | 1 |
| UI共通設計.md | §1 デザインシステム | src/components/Button.tsx | 1 |
| データ設計.md | §1 データモデル概要 | src/components/Button.tsx | 1 |
MD
    cat > "$target/$sample_record_doc" <<'MD'
# サンプル記録

## 選定コマンド
`find src/components -type f | sort | head -n 5`
MD
  }

  rc=0

  # 陽性フィクスチャ: 検査1・3・4・6すべてPASSする想定
  pass_dir="$tmp/pass"
  build_docs "$pass_dir"
  if run_all_checks "$pass_dir" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 陽性フィクスチャがexit 0"
  else
    echo "  [FAIL] 陽性フィクスチャがexit 0にならない" >&2
    rc=1
  fi
  if check_required_sections "$pass_dir" >/dev/null 2>&1; then
    echo "  [PASS] 検査7: 必須節をMarkdown見出しとして持つ文書でexit 0"
  else
    echo "  [FAIL] 検査7: 必須節をMarkdown見出しとして持つ文書がexit 0にならない" >&2
    rc=1
  fi

  # 陽性(Phase A): 規約4文書とサンプル記録が無くても永続6文書のゲートは通る
  persistent_only_dir="$tmp/persistent-only"
  build_docs "$persistent_only_dir"
  rm -rf "$persistent_only_dir/規約"
  rm -f "$persistent_only_dir/$sample_record_doc"
  if run_all_checks "$persistent_only_dir" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] Phase A: 規約4文書・サンプル記録なしで永続6文書がexit 0"
  else
    echo "  [FAIL] Phase A: 非永続文書の欠落を必須違反にした" >&2
    rc=1
  fi

  # 陰性1: 検査1のみ違反（DESIGN.mdを欠落）
  fail1_dir="$tmp/fail1"
  build_docs "$fail1_dir"
  rm -f "$fail1_dir/$design_doc"
  if check_files_exist "$fail1_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査1: ファイル欠落があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査1: ファイル欠落でexit 1"
  fi

  # 陰性3: 検査3のみ違反（存在しないパスを記載）
  fail3_dir="$tmp/fail3"
  build_docs "$fail3_dir"
  cat >> "$fail3_dir/$design_doc" <<'MD'

参照コンポーネントは `src/components/Missing.tsx`。
MD
  if check_paths_exist "$fail3_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査3: 未実在パスがあるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査3: 未実在パスでexit 1"
  fi
  if run_all_checks "$fail3_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 集約入口: 検査3違反を見逃した" >&2
    rc=1
  else
    echo "  [PASS] 集約入口: 検査3違反でexit 1"
  fi

  # 陰性4: 検査4のみ違反（テンプレ残存）
  fail4_dir="$tmp/fail4"
  build_docs "$fail4_dir"
  cat >> "$fail4_dir/$design_doc" <<'MD'

surface色は<TBD: 実測値未確定>。
MD
  if check_no_placeholder "$fail4_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査4: テンプレ残存があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査4: テンプレ残存でexit 1"
  fi

  # 陽性(1-153): TODO/TBDという語自体を地の文で正当に言及した場合は検出しないこと
  mention4_dir="$tmp/mention4"
  build_docs "$mention4_dir"
  cat >> "$mention4_dir/$design_doc" <<'MD'

未確定値の書き方はTBD、作業メモ用コメントはTODOで統一する運用である。
MD
  if check_no_placeholder "$mention4_dir" >/dev/null 2>&1; then
    echo "  [PASS] 検査4(1-153): TODO/TBDの地の文言及は誤検出しない"
  else
    echo "  [FAIL] 検査4(1-153): 正当な言及なのにテンプレ残存として誤検出した" >&2
    rc=1
  fi

  # 陽性(Phase A): sample記録は存在してもゲート対象外
  ignored_sample_dir="$tmp/ignored-sample"
  build_docs "$ignored_sample_dir"
  cat >> "$ignored_sample_dir/$sample_record_doc" <<'MD'

<TBD: verification外部化までの一時記録>
MD
  if run_all_checks "$ignored_sample_dir" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] Phase A: sample記録の内容をゲート対象外として扱う"
  else
    echo "  [FAIL] Phase A: sample記録をゲート対象として評価した" >&2
    rc=1
  fi

  # 陰性6: 検査6のみ違反（メッセージ定義書の宣言件数と実測件数が不一致）
  fail6_dir="$tmp/fail6"
  build_docs "$fail6_dir"
  cat > "$fail6_dir/$message_doc" <<'MD'
# 共通メッセージ定義書（リバース版）

総件数: 3件

## メッセージ一覧

| メッセージ | 用途 |
|---|---|
| `保存に成功しました` | 保存成功トースト |
| `保存に失敗しました` | 保存失敗トースト |
MD
  if check_message_scale "$fail6_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査6: 宣言件数と実測件数の不一致があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査6: 宣言件数と実測件数の不一致でexit 1"
  fi

  # 検収1: 共通文書本文の根拠列・file:line注記が無い状態を通す。
  if check_common_doc_evidence_separation "$pass_dir" >/dev/null 2>&1; then
    echo "  [PASS] 検査8: 共通文書本文に根拠列・file:line注記が無い状態でexit 0"
  else
    echo "  [FAIL] 検査8: 根拠を分離済みの共通文書を不合格にした" >&2
    rc=1
  fi

  # 検収1の陰性: 根拠列またはfile:line注記が本文へ戻れば検出する。
  fail8_dir="$tmp/fail8"
  build_docs "$fail8_dir"
  cat >> "$fail8_dir/$data_design_doc" <<'MD'

| 項目 | 根拠 |
|---|---|
| 状態管理 | src/components/Button.tsx:1 |
MD
  if check_common_doc_evidence_separation "$fail8_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査8: 本文に根拠列・file:line注記があるのにexit 0になった" >&2
    rc=1
  else
    echo "  [PASS] 検査8: 本文の根拠列・file:line注記でexit 1"
  fi

  # 検査8: 拡張子に依存せず、非ASCIIパスを含むfile:line注記を検出する。
  language8_dir="$tmp/language8"
  build_docs "$language8_dir"
  cat >> "$language8_dir/$data_design_doc" <<'MD'

実装位置は src/views/App.vue:2 と 日本語/処理.sql:1。
MD
  language8_hits="$(file_line_annotation_hits "$language8_dir/$data_design_doc")"
  if check_common_doc_evidence_separation "$language8_dir" >/dev/null 2>&1 \
    || ! printf '%s' "$language8_hits" | grep -Fq 'src/views/App.vue:2' \
    || ! printf '%s' "$language8_hits" | grep -Fq '日本語/処理.sql:1'; then
    echo "  [FAIL] 検査8: 言語非依存・日本語パスのfile:line注記を検出できない" >&2
    rc=1
  else
    echo "  [PASS] 検査8: .vueと日本語パス.sqlのfile:line注記でexit 1"
  fi

  # 検査8: URL中のコロン付き数値はfile:line注記として扱わない。
  url8_dir="$tmp/url8"
  build_docs "$url8_dir"
  printf '%s\n' '参照URLは https://example.com/docs/file.vue:1。' >> "$url8_dir/$data_design_doc"
  if check_common_doc_evidence_separation "$url8_dir" >/dev/null 2>&1; then
    echo "  [PASS] 検査8: URLはfile:line注記から除外"
  else
    echo "  [FAIL] 検査8: URLをfile:line注記として誤検出した" >&2
    rc=1
  fi

  # 検収2: 台帳が文書・節/項目・対象コード・行を対応づける。
  if check_common_evidence_ledger "$pass_dir" "$repo" >/dev/null 2>&1; then
    echo "  [PASS] 検査9: 横断根拠台帳が文書・節/項目・対象コード・行を対応づける"
  else
    echo "  [FAIL] 検査9: 正しい横断根拠台帳を不合格にした" >&2
    rc=1
  fi
  fail9_dir="$tmp/fail9"
  build_docs "$fail9_dir"
  sed -i.bak 's#src/components/Button.tsx | 1#src/components/Missing.tsx | 99#' "$fail9_dir/$common_evidence_ledger"
  rm -f "$fail9_dir/$common_evidence_ledger.bak"
  if check_common_evidence_ledger "$fail9_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査9: 未実在の対象コード・範囲外の行を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査9: 未実在の対象コード・範囲外の行でexit 1"
  fi

  unknown_doc9_dir="$tmp/unknown-doc9"
  build_docs "$unknown_doc9_dir"
  sed -i.bak 's/共通設計書.md | §1 共通画面状態の規則/不存在.md | §1 共通画面状態の規則/' "$unknown_doc9_dir/$common_evidence_ledger"
  rm -f "$unknown_doc9_dir/$common_evidence_ledger.bak"
  if check_common_evidence_ledger "$unknown_doc9_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査9: 定義外の対象文書を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査9: 定義外・未実在の対象文書でexit 1"
  fi

  unknown_section9_dir="$tmp/unknown-section9"
  build_docs "$unknown_section9_dir"
  sed -i.bak 's/§1 共通画面状態の規則/本文に存在しない節/' "$unknown_section9_dir/$common_evidence_ledger"
  rm -f "$unknown_section9_dir/$common_evidence_ledger.bak"
  if check_common_evidence_ledger "$unknown_section9_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査9: 対象文書に存在しない節・項目を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査9: 対象文書に存在しない節・項目でexit 1"
  fi

  missing_doc9_dir="$tmp/missing-doc9"
  build_docs "$missing_doc9_dir"
  sed -i.bak '/| メッセージ定義書.md |/d' "$missing_doc9_dir/$common_evidence_ledger"
  rm -f "$missing_doc9_dir/$common_evidence_ledger.bak"
  if check_common_evidence_ledger "$missing_doc9_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査9: 適用対象1文書の台帳行欠落を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査9: 適用対象1文書の台帳行欠落でexit 1"
  fi

  extra_column9_dir="$tmp/extra-column9"
  build_docs "$extra_column9_dir"
  cat >> "$extra_column9_dir/$common_evidence_ledger" <<'MD'
| 共通設計書.md | §1 共通画面状態の規則 | src/components/Button.tsx | 1 | 余分 |
MD
  if check_common_evidence_ledger "$extra_column9_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 検査9: canonical 4列以外の台帳行を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査9: canonical 4列以外の台帳行でexit 1"
  fi

  # 検収3: output-layout と納品物一覧が同じ台帳キーを宣言する。
  if check_common_evidence_declarations >/dev/null 2>&1; then
    echo "  [PASS] 検査10: output-layout と納品物一覧の台帳宣言が一致"
  else
    echo "  [FAIL] 検査10: output-layout と納品物一覧の台帳宣言が一致しない" >&2
    rc=1
  fi

  # 検収1・2: screen除外時、画面依存の2文書は未実在でも対象なしとして通過し根拠を出力する。
  excluded_screen_dir="$tmp/excluded-screen"
  build_docs "$excluded_screen_dir"
  jq '.excludedKinds = [{"kind":"screen","reason":"画面を持たない外部連携のみの対象"}]' \
    "$excluded_screen_dir/$excluded_kinds_file" > "$excluded_screen_dir/$excluded_kinds_file.next"
  mv "$excluded_screen_dir/$excluded_kinds_file.next" "$excluded_screen_dir/$excluded_kinds_file"
  rm -f "$excluded_screen_dir/$common_design_doc" "$excluded_screen_dir/$ui_common_doc"
  excluded_rc=0
  excluded_output="$(check_files_exist "$excluded_screen_dir" 2>&1)" || excluded_rc=1
  if [ "$excluded_rc" -eq 0 ] && [ "$(printf '%s\n' "$excluded_output" | grep -c '^  対象なし: ' || true)" -eq 2 ] \
    && printf '%s' "$excluded_output" | grep -Fq 'screen: 画面を持たない外部連携のみの対象'; then
    echo "  [PASS] screen除外: 画面依存2文書を対象なしとして出力しexit 0"
  else
    echo "  [FAIL] screen除外: 画面依存2文書の対象なし判定または出力が不正" >&2
    rc=1
  fi

  # 検収3: 除外宣言が無い場合は同じ2文書の未実在をFAILにする。
  required_screen_dir="$tmp/required-screen"
  build_docs "$required_screen_dir"
  rm -f "$required_screen_dir/$common_design_doc" "$required_screen_dir/$ui_common_doc"
  if run_all_checks "$required_screen_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] screen未除外: 画面依存2文書の未実在を通過した" >&2
    rc=1
  else
    echo "  [PASS] screen未除外: 画面依存2文書の未実在でexit 1"
  fi

  # 検収4: 定義ファイルだけを変え、検査スクリプトを変えずに依存判定を変えられる。
  definition_driven_dir="$tmp/definition-driven"
  build_docs "$definition_driven_dir"
  jq '.excludedKinds = [{"kind":"screen","reason":"定義駆動の確認"}]' \
    "$definition_driven_dir/$excluded_kinds_file" > "$definition_driven_dir/$excluded_kinds_file.next"
  mv "$definition_driven_dir/$excluded_kinds_file.next" "$definition_driven_dir/$excluded_kinds_file"
  rm -f "$definition_driven_dir/$foundation_doc"
  if run_all_checks "$definition_driven_dir" "$repo" >/dev/null 2>&1; then
    echo "  [FAIL] 定義駆動: 依存未定義の基盤設計書欠落を通過した" >&2
    rc=1
  else
    cp "$DOCUMENT_DEFINITIONS_FILE" "$tmp/definition-driven.json"
    DOCUMENT_DEFINITIONS_FILE="$tmp/definition-driven.json"
    jq '(.documents[] | select(.layoutKey == "foundationDoc").dependsOnKinds) = ["screen"]' \
      "$DOCUMENT_DEFINITIONS_FILE" > "$DOCUMENT_DEFINITIONS_FILE.next"
    mv "$DOCUMENT_DEFINITIONS_FILE.next" "$DOCUMENT_DEFINITIONS_FILE"
    if run_all_checks "$definition_driven_dir" "$repo" >/dev/null 2>&1; then
      echo "  [PASS] 定義駆動: 定義だけの変更で基盤設計書を対象なしに変更"
    else
      echo "  [FAIL] 定義駆動: 定義変更後も判定が変わらない" >&2
      rc=1
    fi
    DOCUMENT_DEFINITIONS_FILE="$SCRIPT_DIR/../references/common-document-definitions.json"
  fi

  # 検収5: 画面前提文書にテンプレート必須節が1つも無ければFAILにする。
  fail7_dir="$tmp/fail7"
  build_docs "$fail7_dir"
  printf '%s\n' '# エンドポイントの共通処理' > "$fail7_dir/$common_design_doc"
  if check_required_sections "$fail7_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査7: 必須節を1つも持たない文書を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査7: 必須節を1つも持たない文書でexit 1"
  fi

  # 陰性7: 必須語が本文にだけ並び、Markdown見出しとして存在しなければFAILにする。
  body_only7_dir="$tmp/body-only7"
  build_docs "$body_only7_dir"
  cat > "$body_only7_dir/$common_design_doc" <<'MD'
# 共通設計書（リバース版）

本書に書かないもの 共通画面状態の規則 共通操作規則 共通レイアウト原則 要確認事項一覧
MD
  if check_required_sections "$body_only7_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査7: 必須語が本文にだけある文書を通過した" >&2
    rc=1
  else
    echo "  [PASS] 検査7: 必須語が本文にだけある文書でexit 1"
  fi

  # 陰性7: コードフェンス内のATX見出し風の行は必須節として数えない。
  fenced7_dir="$tmp/fenced7"
  build_docs "$fenced7_dir"
  cat > "$fenced7_dir/$common_design_doc" <<'MD'
# 共通設計書（リバース版）

````markdown
## 本書に書かないもの
```
## 共通画面状態の規則
## 共通操作規則
## 共通レイアウト原則
## 要確認事項一覧
````
MD
  if check_required_sections "$fenced7_dir" >/dev/null 2>&1; then
    echo "  [FAIL] 検査7: コードフェンス内のATX見出し風の行を必須節として数えた" >&2
    rc=1
  else
    echo "  [PASS] 検査7: コードフェンス内のATX見出し風の行でexit 1"
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

docs_dir="${1:?使い方: check-common-docs.sh <common_docs_dir> <target_repo_path>}"
repo="${2:?使い方: check-common-docs.sh <common_docs_dir> <target_repo_path>}"

if [ ! -d "$docs_dir" ]; then
  echo "エラー: common_docs_dir が見つかりません: $docs_dir" >&2
  exit 2
fi
if [ ! -d "$repo" ]; then
  echo "エラー: target_repo_path が見つかりません: $repo" >&2
  exit 2
fi

if run_all_checks "$docs_dir" "$repo"; then
  echo "プロジェクト共通文書ゲート: 検査1・3・4・6・7すべてPASS"
  exit 0
else
  echo "プロジェクト共通文書ゲート: FAIL" >&2
  exit 1
fi
