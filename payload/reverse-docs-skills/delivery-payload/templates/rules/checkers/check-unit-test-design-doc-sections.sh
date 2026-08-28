#!/usr/bin/env bash
# check-unit-test-design-doc-sections.sh — 単体テスト設計書の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 単体テスト設計書の決まり
#   - 単体テスト設計書は基本設計フェーズで作る
#   - 記載項目を省かない
#   - 規約が求めるテストを観点へ取り込む
#
# 判定:
#   （記載項目を省かない）
#   書き込み先のファイル名に「単体テスト設計書」が含まれる場合、本文が
#   テンプレートが定める13節の見出しを抽出し、名前・順序・件数が完全に一致するか
#   を走査する。1つでも欠ける、順序が違う、余分な節がある場合は違反とする。
#
#   （単体テスト設計書は基本設計フェーズで作る）
#   cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
#   本規則の宣言（基本設計フォルダの置き場を示す文章。/ を含む語を1つ持つ）を
#   探す。宣言があれば、その語を名前に含むディレクトリを cwd 配下から走査し、
#   直下に「単体テスト設計書」を名前に含むファイルを持たないディレクトリが
#   あれば違反とする。
#
#   （規約が求めるテストを観点へ取り込む）
#   書き込み先のファイル名に「単体テスト設計書」が含まれる場合、cwd 配下の
#   docs/rules/**/rule.md の「## 規則」表から、検査列に「テスト:」を含む
#   規則の名前を集め、そのいずれかが本文に現れているかを走査する。
#
#   （テスト設計書の節の役割）
#   ファイル名に「テスト設計書」が含まれる場合、§1を全観点、§5・§6を
#   それぞれ異常・境界の観点の詳細、§2を実行ケースの唯一の一覧として扱う。
#   §5・§6の第1列が「観点のキー」であること、§5・§6のキーが§1に含まれる
#   こと、§2の全行が§1の観点を参照すること、§1の全観点に§2のケースが1件
#   以上あること、§2のケースキーが重複しないことを走査する。

#
# 既知の限界:
#   - 見出しの名前・順序・件数と、§1・§2・§5・§6のキー集合を判定する。
#     各セルの説明文や期待結果の妥当性までは判定しない
#   - Markdown の `#` 見出し記法を前提とする。見出し記法を使わない文書形式では
#     検出できない
#   - 単体テスト設計書は基本設計フェーズで作る: 製造の着手前に作成されたかどうか
#     を判定する基準は定義されていないため、この部分は実装しない（規約が
#     判定不能と定める部分）。基本設計フォルダに単体テスト設計書が実在するかの
#     静的な走査のみを行う
#   - 単体テスト設計書は基本設計フェーズで作る: 基本設計フォルダの宣言（/ を
#     含む語）は自由な文章から最初の1語を取り出す方式であり、複数の型が
#     書かれている場合は最初の1つだけを見る
#   - 規約が求めるテストを観点へ取り込む: 規則名の文字列が本文に含まれるかの
#     機械的な一致しか見ない。各規則が求める確認が実際のテスト観点で確かめ
#     られているかどうかの妥当性まではレビュー（人手）に委ねる
#   - テスト設計書の節の役割: Markdown表のセル内にパイプ文字を含めない記法を
#     前提とする。未記入のテンプレート行（山括弧のプレースホルダ）は集合検査から
#     除外する
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外
#   - ファイル名に「単体テスト設計書」を含まない → 記載項目を省かない・規約が
#     求めるテストを観点へ取り込むの2規則は対象外
#   - 単体テスト設計書は基本設計フェーズで作る: cwd 配下の宣言が無い、または
#     宣言はあるが / を含む語が読み取れない、または宣言された基本設計フォルダが
#     見当たらない → 通知（block しない）
#   - 規約が求めるテストを観点へ取り込む: cwd が空・docs/rules が存在しない、
#     または検査列にテストを含む規則が見当たらない → 通知（block しない）
#
# 止めるか知らせるか:
#   単体テスト設計書は基本設計フェーズで作る: 止める（基本設計フォルダに単体テスト設計書を欠いたまま製造が進むと、後から不足に気付いても設計フェーズへ戻す機会を失うため）
#   記載項目を省かない: 止める（必須見出しを欠いた単体テスト設計書が確定すると、その観点の検証漏れが履歴に残り事後に補えなくなるため）
#   規約が求めるテストを観点へ取り込む: 止める（規約が求める確認をテスト観点に取り込まないまま設計書が確定すると、その規約違反を検出する機会を失うため）
#
# 逃げ道:
#   UNIT_TEST_DESIGN_DOC_SECTIONS_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-unit-test-design-doc-sections.sh --self-test
#   ファイル検査: check-unit-test-design-doc-sections.sh --check-file <単体テスト設計書.md>
set -uo pipefail

REQUIRED_SECTION_HEADINGS='本書が検証するもの
テスト対象
テストの粒度と自動化の方針
本書が扱わない範囲
§1 テスト観点
§2 テストケース一覧
§3 入力条件
§4 期待結果
§5 異常系
§6 境界値
§7 網羅基準
§8 前提条件と終了条件
§9 要確認事項一覧'

# Markdownのフェンス内にある見出し例を本文の節と誤認しないよう、フェンス外の
# H2見出しだけを順番どおりに返す。
extract_h2_headings() {
  LC_ALL=C awk '
    function fence_run(line,    stripped, char, count, indent) {
      indent = 0
      while (substr(line, indent + 1, 1) == " ") indent++
      if (indent > 3) return ""
      stripped = substr(line, indent + 1)
      char = substr(stripped, 1, 1)
      if (char != "`" && char != "~") return ""
      count = 0
      while (substr(stripped, count + 1, 1) == char) count++
      if (count < 3) return ""
      return substr(stripped, 1, count)
    }
    {
      marker = fence_run($0)
      if (fence == "" && marker != "") {
        fence = marker
        next
      }
      if (fence != "") {
        if (marker != "" && substr(marker, 1, 1) == substr(fence, 1, 1) && length(marker) >= length(fence)) {
          remainder = $0
          sub(/^[[:space:]]*/, "", remainder)
          remainder = substr(remainder, length(marker) + 1)
          if (remainder ~ /^[[:space:]]*$/) fence = ""
        }
        next
      }
      if (/^## /) {
        sub(/^## /, "")
        print
      }
    }
  '
}

# cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
# 規則名（第1列）が完全一致する行の内容列（第2列）を1件返す。無ければ空文字。
lookup_project_override_content() {
  # $1: cwd, $2: rule name
  local cwd="$1" name="$2" file
  [ -d "$cwd/docs/rules" ] || return 0
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    LC_ALL=C awk -v name="$name" '
      BEGIN { insec = 0 }
      /^## このプロジェクトの規則/ { insec = 1; next }
      /^## / && insec == 1 { insec = 0 }
      insec == 1 && /^\|/ {
        line = $0
        if (line ~ /^\| *規則 *\|/) next
        if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
        n = split(line, cols, "|")
        rule = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", rule)
        if (rule == name) {
          content = cols[3]; gsub(/^[ \t]+|[ \t]+$/, "", content)
          print content
          exit
        }
      }
    ' "$file"
  done < <(find "$cwd/docs/rules" -name 'rule.md' 2>/dev/null) | head -1
}

# 指定した rule.md 本文の「## 規則」表のデータ行から、検査列（4列目）に
# 「テスト:」を含む行の規則名（第1列）を1行1件、標準出力へ列挙する。
collect_test_rule_names() {
  local file="$1"
  LC_ALL=C awk '
    BEGIN { in_section = 0 }
    /^## 規則/ { in_section = 1; next }
    /^## / && in_section == 1 { in_section = 0 }
    in_section == 1 && /^\|/ {
      line = $0
      if (line ~ /^\| *規則 *\|/) next
      if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
      n = split(line, cols, "|")
      name = cols[2]; gsub(/^[ \t]+|[ \t]+$/, "", name)
      check = cols[n-1]; gsub(/^[ \t]+|[ \t]+$/, "", check)
      if (check ~ /テスト:/) print name
    }
  ' "$file"
}

# 「記載項目を省かない」規則の判定
judge_required_sections() {
  # $1: file_path, $2: content
  local file_path="$1" content="$2"
  local base
  base="$(basename "$file_path")"

  if ! printf '%s' "$base" | grep -qF '単体テスト設計書'; then
    echo "対象外[記載項目を省かない]: 単体テスト設計書ではありません（${base}）"
    return 0
  fi

  local actual_headings expected_inline actual_inline
  actual_headings="$(printf '%s\n' "$content" | extract_h2_headings)"
  if [ "$actual_headings" != "$REQUIRED_SECTION_HEADINGS" ]; then
    expected_inline="$(printf '%s\n' "$REQUIRED_SECTION_HEADINGS" | awk 'BEGIN { ORS="" } NR > 1 { printf " → " } { printf "%s", $0 } END { print "" }')"
    actual_inline="$(printf '%s\n' "$actual_headings" | awk 'BEGIN { ORS="" } NR > 1 { printf " → " } { printf "%s", $0 } END { print "" }')"
    [ -n "$actual_inline" ] || actual_inline="（見出しなし）"
    echo "拒否[記載項目を省かない]: 13節の名前・順序・件数がテンプレートと一致しません（期待: ${expected_inline}／実際: ${actual_inline}）"
    return 2
  fi

  echo "許可[記載項目を省かない]: 13節の名前・順序・件数がテンプレートと一致します"
  return 0
}

# 「テスト設計書の節の役割」の判定
judge_test_section_roles() {
  # $1: file_path, $2: content
  local file_path="$1" content="$2"
  local base
  base="$(basename "$file_path")"

  if ! printf '%s' "$base" | grep -qF 'テスト設計書'; then
    echo "対象外[テスト設計書の節の役割]: テスト設計書ではありません（${base}）"
    return 0
  fi

  # 見出し・列名の完全一致比較は LC_ALL=C で行う。macOS 標準 awk は UTF-8 ロケールで多バイト文字列の == を誤り、
  # 第1列「キー」を「観点のキー」と等しいと判定した(実測 2026-08-28)。手元で動いても戻さない。
  printf '%s\n' "$content" | LC_ALL=C awk '
    function trim(value) {
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      return value
    }
    function is_separator(value) {
      value = trim(value)
      return value ~ /^:?-+:?$/
    }
    function is_placeholder(value) {
      value = trim(value)
      return value == "" || value == "該当なし" || value ~ /[<>]/
    }
    function add_error(message) {
      errors[++error_count] = message
    }
    function fence_run(line,    stripped, char, count, indent) {
      indent = 0
      while (substr(line, indent + 1, 1) == " ") indent++
      if (indent > 3) return ""
      stripped = substr(line, indent + 1)
      char = substr(stripped, 1, 1)
      if (char != "`" && char != "~") return ""
      count = 0
      while (substr(stripped, count + 1, 1) == char) count++
      if (count < 3) return ""
      return substr(stripped, 1, count)
    }
    {
      marker = fence_run($0)
      if (fence == "" && marker != "") {
        fence = marker
        next
      }
      if (fence != "") {
        if (marker != "" && substr(marker, 1, 1) == substr(fence, 1, 1) && length(marker) >= length(fence)) {
          remainder = $0
          sub(/^[[:space:]]*/, "", remainder)
          remainder = substr(remainder, length(marker) + 1)
          if (remainder ~ /^[[:space:]]*$/) fence = ""
        }
        next
      }
    }
    /^## §1 テスト観点/ { section = 1; in_table = 0; active_table = 0; next }
    /^## §2 テストケース一覧/ { section = 2; in_table = 0; active_table = 0; next }
    /^## §5 異常系/ { section = 5; in_table = 0; active_table = 0; next }
    /^## §6 境界値/ { section = 6; in_table = 0; active_table = 0; next }
    /^## / { section = 0; in_table = 0; active_table = 0; next }
    section > 0 && !/^\|/ {
      in_table = 0
      active_table = 0
      next
    }
    section > 0 && /^\|/ {
      count = split($0, raw, "|")
      for (i = 2; i < count; i++) cols[i - 1] = trim(raw[i])
      width = count - 2

      if (!in_table) {
        in_table = 1
        active_table = 0
        signature = ""
        for (i = 1; i <= width; i++) signature = signature (i > 1 ? "|" : "") cols[i]
        if (section == 1 && cols[1] == "キー") {
          if (!table_selected[section]) {
            active_table = 1
            table_selected[section] = 1
            role_header[section] = signature
          } else if (signature == role_header[section]) {
            active_table = 1
          }
        }
        if (section == 2) {
          viewpoint_column = 0
          for (i = 1; i <= width; i++) {
            normalized = cols[i]
            gsub(/[ \t]/, "", normalized)
            if (normalized ~ /^対応(する)?観点(の)?キー$/) viewpoint_column = i
          }
          if (cols[1] == "キー" && viewpoint_column > 0) {
            if (!table_selected[section]) {
              active_table = 1
              table_selected[section] = 1
              role_header[section] = signature
            } else if (signature == role_header[section]) {
              active_table = 1
            } else {
              case_table_shape_mismatch = 1
            }
            if (active_table) case_table_seen = 1
            if (active_table && cols[2] != "番号") add_error("§2のケース表の2列目を「番号」にしてください（改善課題1-297）")
          }
        }
        if (section == 5 || section == 6) {
          if (!table_selected[section]) {
            active_table = 1
            table_selected[section] = 1
            first_header[section] = cols[1]
            role_header[section] = signature
          } else if (signature == role_header[section]) {
            active_table = 1
          }
        }
        if (active_table) header_seen[section] = 1
        delete cols
        next
      }

      if (!active_table) {
        delete cols
        next
      }

      if (is_separator(cols[1])) {
        delete cols
        next
      }

      key = cols[1]
      if (key == "キー" || key == "観点のキー" || is_placeholder(key)) {
        delete cols
        next
      }

      if (section == 1) {
        viewpoint_counts[key]++
        viewpoints[key] = 1
      }
      if (section == 5) {
        abnormal_viewpoint_counts[key]++
        abnormal_viewpoints[key] = 1
      }
      if (section == 6) {
        boundary_viewpoint_counts[key]++
        boundary_viewpoints[key] = 1
      }
      if (section == 2) {
        case_count++
        case_keys[key]++
        if (viewpoint_column > 0) {
          viewpoint_key = cols[viewpoint_column]
          if (is_placeholder(viewpoint_key)) {
            add_error("§2のケース「" key "」に対応する観点のキーがありません")
          } else {
            case_viewpoints[viewpoint_key] = 1
          }
        }
      }
      delete cols
    }
    END {
      if (!header_seen[1] || !header_seen[2] || !header_seen[5] || !header_seen[6]) {
        add_error("§1・§2・§5・§6の表をすべて記載してください")
      }
      if (first_header[5] != "観点のキー") add_error("§5の第1列を「観点のキー」にしてください")
      if (first_header[6] != "観点のキー") add_error("§6の第1列を「観点のキー」にしてください")
      if (!case_table_seen) add_error("§2に対応する観点のキー列がありません")
      if (case_table_shape_mismatch) add_error("§2のケース表の列構成が統一されていません")

      for (key in abnormal_viewpoints) {
        if (!(key in viewpoints)) add_error("§5の観点「" key "」が§1にありません")
      }
      for (key in boundary_viewpoints) {
        if (!(key in viewpoints)) add_error("§6の観点「" key "」が§1にありません")
      }
      for (key in case_viewpoints) {
        if (!(key in viewpoints)) add_error("§2が参照する観点「" key "」が§1にありません")
      }
      for (key in viewpoints) {
        if (!(key in case_viewpoints)) add_error("§1の観点「" key "」に対応するケースが§2にありません")
      }
      for (key in case_keys) {
        if (case_keys[key] > 1) add_error("§2のケースキー「" key "」が重複しています")
      }
      for (key in viewpoint_counts) {
        if (viewpoint_counts[key] > 1) add_error("§1の観点キー「" key "」が重複しています")
      }
      for (key in abnormal_viewpoint_counts) {
        if (abnormal_viewpoint_counts[key] > 1) add_error("§5の観点キー「" key "」が重複しています")
      }
      for (key in boundary_viewpoint_counts) {
        if (boundary_viewpoint_counts[key] > 1) add_error("§6の観点キー「" key "」が重複しています")
      }

      if (error_count > 0) {
        printf "拒否[テスト設計書の節の役割]: "
        for (i = 1; i <= error_count; i++) printf "%s%s", (i > 1 ? "／" : ""), errors[i]
        printf "\n"
        exit 2
      }

      printf "許可[テスト設計書の節の役割]: §1が全観点、§5・§6がその部分集合で、実行するテストは§2の%dケースです\n", case_count
    }
  '
}

run_file_check() {
  local file_path="${1:-}"
  if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
    echo "検査対象の単体テスト設計書が見つかりません: ${file_path:-（未指定）}" >&2
    return 1
  fi
  local content rc=0 msg code
  content="$(cat "$file_path")"
  if msg="$(judge_required_sections "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2
  if msg="$(judge_test_section_roles "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2
  return "$rc"
}

# 「単体テスト設計書は基本設計フェーズで作る」規則の判定
judge_unit_test_doc_exists() {
  # $1: cwd
  local cwd="$1"

  local override
  override="$(lookup_project_override_content "$cwd" "単体テスト設計書は基本設計フェーズで作る")"
  if [ -z "$override" ]; then
    echo "通知[単体テスト設計書は基本設計フェーズで作る]: このプロジェクトの規則に基本設計フォルダの宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local needle
  needle="$(printf '%s' "$override" | tr ' ' '\n' | grep -F '/' | head -1)"
  if [ -z "$needle" ]; then
    echo "通知[単体テスト設計書は基本設計フェーズで作る]: このプロジェクトの規則に宣言はありますが、基本設計フォルダを読み取れません"
    return 0
  fi

  local dirs
  dirs="$(find "$cwd" -type d -not -path '*/.git/*' -path "*${needle}*" 2>/dev/null)"
  if [ -z "$dirs" ]; then
    echo "通知[単体テスト設計書は基本設計フェーズで作る]: 宣言された基本設計フォルダが見当たらないため判定していません"
    return 0
  fi

  local dir rel missing_dirs=""
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    if ! find "$dir" -maxdepth 1 -type f -name '*単体テスト設計書*' 2>/dev/null | grep -q .; then
      rel="${dir#"$cwd"/}"
      missing_dirs="${missing_dirs}${missing_dirs:+、}${rel}"
    fi
  done <<< "$dirs"

  if [ -n "$missing_dirs" ]; then
    echo "拒否[単体テスト設計書は基本設計フェーズで作る]: 基本設計フォルダ（${missing_dirs}）に単体テスト設計書がありません"
    return 2
  fi

  echo "許可[単体テスト設計書は基本設計フェーズで作る]: 基本設計フォルダのすべてに単体テスト設計書があります"
  return 0
}

# 「規約が求めるテストを観点へ取り込む」規則の判定
judge_test_viewpoint_coverage() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"
  local base
  base="$(basename "$file_path")"

  if ! printf '%s' "$base" | grep -qF '単体テスト設計書'; then
    echo "対象外[規約が求めるテストを観点へ取り込む]: 単体テスト設計書ではありません（${base}）"
    return 0
  fi

  if [ -z "$cwd" ] || [ ! -d "$cwd/docs/rules" ]; then
    echo "通知[規約が求めるテストを観点へ取り込む]: docs/rules が見当たらないため、適用される規約の規則名を集められません"
    return 0
  fi

  local names="" file n
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    while IFS= read -r n; do
      [ -z "$n" ] && continue
      names="${names}${n}"$'\n'
    done < <(collect_test_rule_names "$file")
  done < <(find "$cwd/docs/rules" -name 'rule.md' 2>/dev/null)

  names="$(printf '%s' "$names" | grep -v '^$' | LC_ALL=C sort -u)"

  if [ -z "$names" ]; then
    echo "通知[規約が求めるテストを観点へ取り込む]: 検査の手段にテストを含む規則が見当たらないため判定していません"
    return 0
  fi

  local n_count
  n_count="$(printf '%s\n' "$names" | grep -c .)"

  local hit="" name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if printf '%s' "$content" | grep -qF "$name"; then
      hit="$name"
      break
    fi
  done <<< "$names"

  if [ -z "$hit" ]; then
    echo "拒否[規約が求めるテストを観点へ取り込む]: 検査の手段にテストを含む規則（${n_count}件）のいずれもテスト観点に現れていません"
    return 2
  fi

  echo "許可[規約が求めるテストを観点へ取り込む]: 検査の手段にテストを含む規則がテスト観点に現れています（${hit}）"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可）
  local file_path="$1" content="$2" cwd="${3:-}"
  local rc=0 msg code

  if msg="$(judge_required_sections "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  if msg="$(judge_unit_test_doc_exists "$cwd")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  if msg="$(judge_test_viewpoint_coverage "$cwd" "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  if msg="$(judge_test_section_roles "$file_path" "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  [ "$code" -eq 2 ] && rc=2

  return "$rc"
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${UNIT_TEST_DESIGN_DOC_SECTIONS_SKIP_REASON:-}" ]; then
    echo "[UNIT-TEST-DESIGN-DOC-SECTIONS-SKIP] 理由: ${UNIT_TEST_DESIGN_DOC_SECTIONS_SKIP_REASON}"
    return 0
  fi
  return 1
}

run_hook() {
  local skip_msg
  if skip_msg="$(should_skip_with_reason)"; then
    printf '%s\n' "$skip_msg" >&2
    exit 0
  fi

  local input
  input="$(cat)"
  [ -z "$input" ] && exit 0

  local tool
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" != "Write" ] && exit 0

  local file_path content cwd
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$file_path" ] && exit 0
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[UNIT-TEST-DESIGN-DOC-SECTIONS-BLOCK] ${msg}"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  local full='## 本書が検証するもの

| 段 | 検証する状態 | 対応する設計書 | 文書 |
|---|---|---|---|
| 単体 | 関数 | 詳細設計書 | 本書 |

## テスト対象
対象API
## テストの粒度と自動化の方針
API単位で自動化する
## 本書が扱わない範囲
他のAPI
## §1 テスト観点
| キー | 観点 |
|---|---|
| `<観点キー>` | `<観点>` |
## §2 テストケース一覧
| キー | 番号 | 対応する観点のキー | 入力 | 期待結果 |
|---|---|---|---|---|
| `<ケースキー>` | 1 | `<観点キー>` | `<入力>` | `<期待結果>` |
## §3 入力条件
...
## §4 期待結果
...
## §5 異常系
| 観点のキー | 条件 | 期待結果 |
|---|---|---|
| `<観点キー>` | `<条件>` | `<期待結果>` |
## §6 境界値
| 観点のキー | 境界 | 期待結果 |
|---|---|---|
| `<観点キー>` | `<境界>` | `<期待結果>` |
## §7 網羅基準
...
## §8 前提条件と終了条件
...
## §9 要確認事項一覧
...'

  # 系1: 対象外拡張子(ファイル名不一致) → 許可
  if msg="$(judge "docs/design/screens/画面A/README.md" "本文なし")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系1: 単体テスト設計書でないファイルは許可される（${msg}）"
  else
    echo "  [FAIL] 系1: 対象外ファイルなのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 単体テスト設計書だが見出しが1つも無い → 拒否
  if msg="$(judge "docs/design/screens/画面A/単体テスト設計書.md" "本文のみで見出しなし")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: 見出しが無い単体テスト設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 見出しが無いのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3: 合成フィクスチャ3件をファイルとして書き出し、13節を正順で持つ → すべて許可
  local fixture fixture_path fixture_ok=1 tmp3
  if ! tmp3="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp3" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  for fixture in api-login api-list api-update; do
    fixture_path="$tmp3/${fixture}-API単体テスト設計書.md"
    printf '%s\n' "$full" > "$fixture_path"
    if ! run_file_check "$fixture_path" >/dev/null; then
      fixture_ok=0
    fi
  done
  rm -rf "$tmp3"
  if [ "$fixture_ok" -eq 1 ]; then
    echo "  [PASS] 系3: 書き出した合成フィクスチャ3件の13節が名前・順序とも一致する"
  else
    echo "  [FAIL] 系3: 合成フィクスチャ3件のいずれかが拒否された" >&2
    rc=1
  fi

  # 系4: 1つだけ欠けている（§6 境界値が無い）→ 拒否
  local partial
  partial="$(printf '%s\n' "$full" | grep -v '^## §6 境界値$')"
  if msg="$(judge "docs/design/screens/画面A/単体テスト設計書.md" "$partial")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4: 1つ欠けていても拒否される（${msg}）"
  else
    echo "  [FAIL] 系4: 見出し欠落があるのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系4c: 欠落した節と同名の見出しがコードフェンス内にあっても拒否
  local fenced_missing
  fenced_missing="$(printf '%s\n' "$partial")
~~~md
## §6 境界値
~~~"
  if msg="$(judge "docs/design/apis/api-fenced/基本設計/API単体テスト設計書.md" "$fenced_missing")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4c: コードフェンス内の見出しでは欠落を補えない（${msg}）"
  else
    echo "  [FAIL] 系4c: コードフェンス内の見出しで欠落を偽装できた（exit=${code}）" >&2
    rc=1
  fi

  # 系4d: 4バッククォートの内側に3バッククォートがあってもフェンスは閉じない → 拒否
  local long_fenced_missing
  long_fenced_missing="$(printf '%s\n' "$partial")
\`\`\`\`md
\`\`\`
## §6 境界値
\`\`\`
\`\`\`\`"
  if msg="$(judge "docs/design/apis/api-long-fenced/基本設計/API単体テスト設計書.md" "$long_fenced_missing")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4d: 長いコードフェンス内の見出しでも欠落を補えない（${msg}）"
  else
    echo "  [FAIL] 系4d: 長いコードフェンス内の見出しで欠落を偽装できた（exit=${code}）" >&2
    rc=1
  fi

  # 系4e: 4スペース字下げされたバッククォート行はフェンスではない → 許可
  local indented_code_before_full
  indented_code_before_full="    \`\`\`\`
${full}"
  if msg="$(judge "docs/design/apis/api-indented-code/基本設計/API単体テスト設計書.md" "$indented_code_before_full")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4e: 4スペース字下げのコード行は後続の13節を隠さない（${msg}）"
  else
    echo "  [FAIL] 系4e: 4スペース字下げのコード行をフェンスと誤認した（exit=${code}）" >&2
    rc=1
  fi

  # 系4b: 13節が揃っていても順序が違う → 拒否
  local reordered
  reordered="$(printf '%s\n' "$full" | awk '
    /^## テストの粒度と自動化の方針$/ { second=$0; getline second_body; next }
    /^## 本書が扱わない範囲$/ { print; getline; print; print second; print second_body; next }
    { print }
  ')"
  if msg="$(judge "docs/design/apis/api-order/基本設計/API単体テスト設計書.md" "$reordered")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4b: 13節の順序が違えば拒否される（${msg}）"
  else
    echo "  [FAIL] 系4b: 13節の順序が違うのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 単体テスト設計書は基本設計フェーズで作る - 宣言が無い → 通知
  local tmp5
  if ! tmp5="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp5" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_unit_test_doc_exists "$tmp5")"; then code=0; else code=$?; fi
  rm -rf "$tmp5"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[単体テスト設計書は基本設計フェーズで作る]'; then
    echo "  [PASS] 系5: 基本設計フォルダの宣言が無ければ通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系5: 宣言が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系6: 単体テスト設計書は基本設計フェーズで作る - 宣言はあるが / を含む語が無い → 通知
  local tmp6
  if ! tmp6="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp6" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp6/docs/rules/example"
  cat > "$tmp6/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計フォルダに置く | 静的解析 |
EOF
  if msg="$(judge_unit_test_doc_exists "$tmp6")"; then code=0; else code=$?; fi
  rm -rf "$tmp6"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[単体テスト設計書は基本設計フェーズで作る]'; then
    echo "  [PASS] 系6: 基本設計フォルダを読み取れなければ通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系6: 読み取れないのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 単体テスト設計書は基本設計フェーズで作る - 基本設計フォルダに単体テスト設計書が無い → 拒否
  local tmp7
  if ! tmp7="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp7" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp7/docs/rules/example"
  cat > "$tmp7/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計は docs/design/画面A/基本設計 に置く | 静的解析 |
EOF
  mkdir -p "$tmp7/docs/design/画面A/基本設計"
  printf '# 画面A基本設計書\n' > "$tmp7/docs/design/画面A/基本設計/画面A基本設計書.md"
  if msg="$(judge_unit_test_doc_exists "$tmp7")"; then code=0; else code=$?; fi
  rm -rf "$tmp7"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[単体テスト設計書は基本設計フェーズで作る]'; then
    echo "  [PASS] 系7: 基本設計フォルダに単体テスト設計書が無ければ拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 単体テスト設計書が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 単体テスト設計書は基本設計フェーズで作る - 基本設計フォルダのすべてに単体テスト設計書がある → 許可
  local tmp8
  if ! tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp8" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp8/docs/rules/example"
  cat > "$tmp8/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計は docs/design/画面A/基本設計 に置く | 静的解析 |
EOF
  mkdir -p "$tmp8/docs/design/画面A/基本設計"
  printf '# 画面A基本設計書\n' > "$tmp8/docs/design/画面A/基本設計/画面A基本設計書.md"
  printf '# 画面A単体テスト設計書\n' > "$tmp8/docs/design/画面A/基本設計/画面A単体テスト設計書.md"
  if msg="$(judge_unit_test_doc_exists "$tmp8")"; then code=0; else code=$?; fi
  rm -rf "$tmp8"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[単体テスト設計書は基本設計フェーズで作る]'; then
    echo "  [PASS] 系8: 基本設計フォルダのすべてに単体テスト設計書があれば許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 単体テスト設計書があるのに拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: 規約が求めるテストを観点へ取り込む - 単体テスト設計書ではない → 対象外
  if msg="$(judge_test_viewpoint_coverage "" "docs/design/screens/画面A/README.md" "本文")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[規約が求めるテストを観点へ取り込む]'; then
    echo "  [PASS] 系9: 単体テスト設計書でなければ対象外になる（${msg}）"
  else
    echo "  [FAIL] 系9: 対象外のはずが判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 規約が求めるテストを観点へ取り込む - docs/rules が無い → 通知
  local tmp10
  if ! tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp10" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  if msg="$(judge_test_viewpoint_coverage "$tmp10" "docs/design/screens/画面A/単体テスト設計書.md" "$full")"; then code=0; else code=$?; fi
  rm -rf "$tmp10"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[規約が求めるテストを観点へ取り込む]'; then
    echo "  [PASS] 系10: docs/rules が無ければ通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系10: docs/rules が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: 規約が求めるテストを観点へ取り込む - 規則名がテスト観点に現れない → 拒否
  local tmp11
  if ! tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp11" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp11/docs/rules/example"
  cat > "$tmp11/docs/rules/example/rule.md" <<'EOF'
# 例

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 金額を小数で扱わない | 内容 | 静的解析: 何か ／ テスト: 境界値を確かめる |
EOF
  if msg="$(judge_test_viewpoint_coverage "$tmp11" "docs/design/screens/画面A/単体テスト設計書.md" "$full")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[規約が求めるテストを観点へ取り込む]'; then
    echo "  [PASS] 系11: 規則名がテスト観点に現れなければ拒否される（${msg}）"
  else
    echo "  [FAIL] 系11: 現れないのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 規約が求めるテストを観点へ取り込む - 規則名がテスト観点に現れる → 許可
  local tmp12
  if ! tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp12" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  mkdir -p "$tmp12/docs/rules/example"
  cat > "$tmp12/docs/rules/example/rule.md" <<'EOF'
# 例

## 規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 金額を小数で扱わない | 内容 | 静的解析: 何か ／ テスト: 境界値を確かめる |
EOF
  local full_with_rule="${full}
金額を小数で扱わない"
  if msg="$(judge_test_viewpoint_coverage "$tmp12" "docs/design/screens/画面A/単体テスト設計書.md" "$full_with_rule")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[規約が求めるテストを観点へ取り込む]'; then
    echo "  [PASS] 系12: 規則名がテスト観点に現れれば許可される（${msg}）"
  else
    echo "  [FAIL] 系12: 現れるのに拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(UNIT_TEST_DESIGN_DOC_SECTIONS_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'UNIT-TEST-DESIGN-DOC-SECTIONS-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系13: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系13: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系14: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if UNIT_TEST_DESIGN_DOC_SECTIONS_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系14: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系14: 空文字なのに skip した（exit=${skip_code2}）" >&2
    rc=1
  fi

  local role_valid='## §1 テスト観点
| キー | 観点 |
|---|---|
| api-失敗 | API失敗 |
| 金額-境界 | 金額の境界 |
## §2 テストケース一覧
| キー | 番号 | 対応する観点のキー | 入力 | 期待結果 |
|---|---|---|---|---|
| api失敗-タイムアウト | 1 | api-失敗 | timeout | error |
| 金額境界-直前 | 2 | 金額-境界 | 0 | reject |
| 金額境界-一致 | 3 | 金額-境界 | 1 | accept |
## §5 異常系
| 観点のキー | 発生させる条件 | 期待する例外・エラー |
|---|---|---|
| api-失敗 | timeout | error |
## §6 境界値
| 観点のキー | 境界の値 | 境界の直前と直後の扱い |
|---|---|---|
| 金額-境界 | 1 | 0は拒否、1は許可 |'

  # 系15: 観点の部分集合と全ケースが整合する → §2の行数を実行件数として許可
  local tmp15 role_file
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）"
    exit 2
  fi
  role_file="$tmp15/API結合テスト設計書.md"
  printf '%s\n' "$role_valid" > "$role_file"
  if msg="$(run_file_check "$role_file")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '§2の3ケース'; then
    echo "  [PASS] 系15: §1・§2・§5・§6の集合関係が整合し、実行件数を§2の3ケースと数えられる（${msg}）"
  else
    echo "  [FAIL] 系15: 整合する節構造が拒否された、または§2の件数が得られない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系16: §5・§6の第1列が「キー」のまま → 拒否
  local wrong_headers
  wrong_headers="$(printf '%s\n' "$role_valid" | sed 's/^| 観点のキー |/| キー |/')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$wrong_headers")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '第1列'; then
    echo "  [PASS] 系16: §5・§6の旧見出し「キー」を拒否する（${msg}）"
  else
    echo "  [FAIL] 系16: §5・§6の旧見出しを許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系17: §5の観点が§1に無い → 拒否
  local orphan_abnormal
  orphan_abnormal="$(printf '%s\n' "$role_valid" | sed 's/^| api-失敗 | timeout | error |$/| 未登録-異常 | timeout | error |/')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$orphan_abnormal")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '§5の観点'; then
    echo "  [PASS] 系17: §1に無い§5の観点を拒否する（${msg}）"
  else
    echo "  [FAIL] 系17: §1に無い§5の観点を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系18: §1の観点に対応するケースが§2に無い → 拒否
  local missing_case
  missing_case="$(printf '%s\n' "$role_valid" | grep -v '^| 金額境界-')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$missing_case")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '対応するケースが§2にありません'; then
    echo "  [PASS] 系18: §2が網羅しない観点を拒否する（${msg}）"
  else
    echo "  [FAIL] 系18: §2が網羅しない観点を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系19: §2のケース表の後に補助データ表がある → 補助表をケースとして数えない
  local role_with_auxiliary_table
  role_with_auxiliary_table="$(printf '%s\n' "$role_valid" | awk '
    /^## §5 異常系/ {
      print "### テストデータ"
      print "| キー | データ | 用途 |"
      print "|---|---|---|"
      print "| 正常入力 | sample.json | ケース入力 |"
    }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$role_with_auxiliary_table")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '§2の3ケース'; then
    echo "  [PASS] 系19: §2の補助データ表をケース件数から除外する（${msg}）"
  else
    echo "  [FAIL] 系19: §2の補助データ表をケースとして数えた（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系20: §2の実ケースが観点を参照しない → 拒否
  local missing_viewpoint_reference
  missing_viewpoint_reference="$(printf '%s\n' "$role_valid" | sed 's/^| 金額境界-直前 | 2 | 金額-境界 |/| 金額境界-直前 | 2 |  |/')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$missing_viewpoint_reference")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '対応する観点のキーがありません'; then
    echo "  [PASS] 系20: 観点を参照しない§2の実ケースを拒否する（${msg}）"
  else
    echo "  [FAIL] 系20: 観点を参照しない§2の実ケースを許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系21: コードフェンス内の偽の§5表 → 実際の§5として扱わない
  local fenced_role_example
  fenced_role_example="$(printf '%s\n' "$role_valid" | awk '
    /^## §5 異常系/ {
      print "~~~md"
      print "## §5 異常系"
      print "| キー | 条件 | 期待結果 |"
      print "|---|---|---|"
      print "| 偽の観点 | timeout | error |"
      print "~~~"
    }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$fenced_role_example")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '§2の3ケース'; then
    echo "  [PASS] 系21: コードフェンス内の偽の節と表を無視する（${msg}）"
  else
    echo "  [FAIL] 系21: コードフェンス内の偽の節または表を実データとして扱った（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系22: §2にケース表が複数ある → 全てのケースを数える
  local multiple_case_tables
  multiple_case_tables="$(printf '%s\n' "$role_valid" | awk '
    /^## §5 異常系/ {
      print "### 追加ケース"
      print "| キー | 番号 | 対応する観点のキー | 入力 | 期待結果 |"
      print "|---|---|---|---|---|"
      print "| api失敗-再試行 | 4 | api-失敗 | retry | success |"
    }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$multiple_case_tables")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '§2の4ケース'; then
    echo "  [PASS] 系22: §2に分かれた複数のケース表を全て数える（${msg}）"
  else
    echo "  [FAIL] 系22: §2の2表目にあるケースを数えなかった（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系23: §2の2つ目のケース表が未登録観点を参照する → 拒否
  local orphan_in_second_case_table
  orphan_in_second_case_table="$(printf '%s\n' "$multiple_case_tables" | sed 's/| api失敗-再試行 | 4 | api-失敗 |/| api失敗-再試行 | 4 | 未登録-観点 |/')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$orphan_in_second_case_table")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '§2が参照する観点'; then
    echo "  [PASS] 系23: §2の2表目が参照する未登録観点を拒否する（${msg}）"
  else
    echo "  [FAIL] 系23: §2の2表目が参照する未登録観点を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系24: §1の2つ目の同型表に未被覆の観点がある → 拒否
  local uncovered_in_second_viewpoint_table
  uncovered_in_second_viewpoint_table="$(printf '%s\n' "$role_valid" | awk '
    /^## §2 テストケース一覧/ {
      print "### 追加観点"
      print "| キー | 観点 |"
      print "|---|---|"
      print "| 認証-期限切れ | 認証期限切れ |"
    }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$uncovered_in_second_viewpoint_table")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '認証-期限切れ'; then
    echo "  [PASS] 系24: §1の2表目にある未被覆の観点を拒否する（${msg}）"
  else
    echo "  [FAIL] 系24: §1の2表目にある未被覆の観点を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系25: §2に似た列を持つ別構成の表 → ケース表の列不一致として拒否
  local case_like_auxiliary_table
  case_like_auxiliary_table="$(printf '%s\n' "$role_valid" | awk '
    /^## §5 異常系/ {
      print "### 補助対応表"
      print "| キー | 対応する観点のキー | 備考 |"
      print "|---|---|---|"
      print "| 補助-対応 | api-失敗 | 説明用 |"
    }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$case_like_auxiliary_table")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '§2のケース表の列構成が統一されていません'; then
    echo "  [PASS] 系25: §2で観点参照列を持つ別構成の表を拒否する（${msg}）"
  else
    echo "  [FAIL] 系25: §2で観点参照列を持つ別構成の表を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系26: §1と§5の観点キーが重複する → 拒否
  local duplicate_viewpoint_keys
  duplicate_viewpoint_keys="$(printf '%s\n' "$role_valid" | awk '
    /^## §2 テストケース一覧/ { print "| api-失敗 | API失敗の重複 |" }
    /^## §6 境界値/ { print "| api-失敗 | timeout | error |" }
    { print }
  ')"
  if msg="$(judge_test_section_roles "API結合テスト設計書.md" "$duplicate_viewpoint_keys")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '§1の観点キー' && printf '%s' "$msg" | grep -qF '§5の観点キー'; then
    echo "  [PASS] 系26: §1と§5の観点キー重複を拒否する（${msg}）"
  else
    echo "  [FAIL] 系26: §1または§5の観点キー重複を許可した（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  --check-file) run_file_check "${2:-}"; exit $? ;;
  *) run_hook ;;
esac
