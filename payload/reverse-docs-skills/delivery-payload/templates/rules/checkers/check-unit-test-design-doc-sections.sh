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
#   テンプレートが定める12節の見出しを抽出し、名前・順序・件数が完全に一致するか
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
# 既知の限界:
#   - 見出しの名前・順序・件数を見る。各見出し配下の記述内容の充実度までは判定しない
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

REQUIRED_SECTION_HEADINGS='テスト対象
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
  awk '
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
    awk -v name="$name" '
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
  awk '
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
    echo "拒否[記載項目を省かない]: 12節の名前・順序・件数がテンプレートと一致しません（期待: ${expected_inline}／実際: ${actual_inline}）"
    return 2
  fi

  echo "許可[記載項目を省かない]: 12節の名前・順序・件数がテンプレートと一致します"
  return 0
}

run_file_check() {
  local file_path="${1:-}"
  if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
    echo "検査対象の単体テスト設計書が見つかりません: ${file_path:-（未指定）}" >&2
    return 1
  fi
  judge_required_sections "$file_path" "$(cat "$file_path")"
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

  local full='## テスト対象
対象API
## テストの粒度と自動化の方針
API単位で自動化する
## 本書が扱わない範囲
他のAPI
## §1 テスト観点
...
## §2 テストケース一覧
...
## §3 入力条件
...
## §4 期待結果
...
## §5 異常系
...
## §6 境界値
...
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

  # 系3: 合成フィクスチャ3件をファイルとして書き出し、12節を正順で持つ → すべて許可
  local fixture fixture_path fixture_ok=1 tmp3
  tmp3="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  for fixture in api-login api-list api-update; do
    fixture_path="$tmp3/${fixture}-API単体テスト設計書.md"
    printf '%s\n' "$full" > "$fixture_path"
    if ! run_file_check "$fixture_path" >/dev/null; then
      fixture_ok=0
    fi
  done
  rm -rf "$tmp3"
  if [ "$fixture_ok" -eq 1 ]; then
    echo "  [PASS] 系3: 書き出した合成フィクスチャ3件の12節が名前・順序とも一致する"
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
    echo "  [PASS] 系4e: 4スペース字下げのコード行は後続の12節を隠さない（${msg}）"
  else
    echo "  [FAIL] 系4e: 4スペース字下げのコード行をフェンスと誤認した（exit=${code}）" >&2
    rc=1
  fi

  # 系4b: 12節が揃っていても順序が違う → 拒否
  local reordered
  reordered="$(printf '%s\n' "$full" | awk '
    /^## テストの粒度と自動化の方針$/ { second=$0; getline second_body; next }
    /^## 本書が扱わない範囲$/ { print; getline; print; print second; print second_body; next }
    { print }
  ')"
  if msg="$(judge "docs/design/apis/api-order/基本設計/API単体テスト設計書.md" "$reordered")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系4b: 12節の順序が違えば拒否される（${msg}）"
  else
    echo "  [FAIL] 系4b: 12節の順序が違うのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 単体テスト設計書は基本設計フェーズで作る - 宣言が無い → 通知
  local tmp5
  tmp5="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
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
  tmp6="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  mkdir -p "$tmp6/docs/rules/example"
  cat > "$tmp6/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計フォルダに置く | 観測による | 静的解析 |
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
  tmp7="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  mkdir -p "$tmp7/docs/rules/example"
  cat > "$tmp7/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計は docs/design/画面A/基本設計 に置く | 観測による | 静的解析 |
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
  tmp8="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  mkdir -p "$tmp8/docs/rules/example"
  cat > "$tmp8/docs/rules/example/rule.md" <<'EOF'
# 例

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 単体テスト設計書は基本設計フェーズで作る | 基本設計は docs/design/画面A/基本設計 に置く | 観測による | 静的解析 |
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
  tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
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
  tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  mkdir -p "$tmp11/docs/rules/example"
  cat > "$tmp11/docs/rules/example/rule.md" <<'EOF'
# 例

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 金額を小数で扱わない | 内容 | 根拠 | 静的解析: 何か ／ テスト: 境界値を確かめる |
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
  tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-unit-test-design-doc-sections-self-test.XXXXXX")"
  mkdir -p "$tmp12/docs/rules/example"
  cat > "$tmp12/docs/rules/example/rule.md" <<'EOF'
# 例

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 金額を小数で扱わない | 内容 | 根拠 | 静的解析: 何か ／ テスト: 境界値を確かめる |
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
