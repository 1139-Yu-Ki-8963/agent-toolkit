#!/usr/bin/env bash
# check-glossary-missing-forbidden-terms.sh — 業務の言葉の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 業務の言葉の決まり
#
# 対象の規則（検査列に「静的解析:」を含む4件すべてを検査する）:
#   1. 使ってはいけない語を明示する
#      — 用語一覧の表を含む文書に「使わない語」の区分があるかを走査する
#        （既存の検査）
#   2. 語ごとに識別子を対応させる
#      — 用語一覧の表に識別子の列があり、各行の識別子欄が埋まっているかを
#        走査する
#   3. 定義を1文で書く
#      — 用語一覧の表に定義の列があり、各行の定義欄が埋まっているかを走査する
#   4. 表示の文言と語を揃える
#      — 画面の文言に、用語の一覧で使わないと定めた語が使われていないかを
#        走査する。書き込み対象ファイルが画面の文言を持つファイル（.tsx/.jsx/
#        .vue/.html/.svelte）の場合にのみ対象とする
#
# 判定の設計:
#   使わない語の区分の検査は、対象プロジェクトごとに用語集ファイルの名前や
#   配置は異なるため、ファイルパスではなく「本文の内容が用語一覧の表という
#   構造を持つかどうか」で走査対象を特定する（既存の設計を維持）。
#   識別子・定義の欄の検査は、同じ用語一覧の表を対象に、見出し行から列の
#   位置を特定し、区切り行を除いた各データ行の該当する列の値が空でないかを
#   走査する。Markdown 表の列は `|` 区切りの分割結果から先頭と末尾の空要素を
#   除いた実列だけを数えることで、位置ずれなく判定する。
#   「表示の文言と語を揃える」は、用語一覧の文書と画面の表示文言という
#   別々のファイルを突き合わせる必要があり、両者の場所は対象プロジェクトごとに
#   異なるため、cwd 配下の docs/rules/**/rule.md の「## このプロジェクトの規則」
#   表から規則名「表示の文言と語を揃える」の宣言（使わない語の一覧）を引いて
#   仲立ちにする。宣言が無ければ判定せず通知にとどめる。宣言があれば、その
#   内容を区切り文字（半角空白・全角空白・読点・コンマ・中黒）で語へ分割し、
#   いずれかの語が書き込み対象ファイルの本文に含まれていないかを走査する。
#
# 対象ファイル:
#   使ってはいけない語を明示する／語ごとに識別子を対応させる／定義を1文で
#   書くの3規則は Markdown（.md）に限定する。
#   表示の文言と語を揃えるは画面の文言を持つファイル（.tsx/.jsx/.vue/.html/
#   .svelte）に限定する。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外（Edit は差分のみで全文を持たないため対象外）
#   - file_path の拡張子が .md ではない → 対象外（1〜3の3規則）
#   - 本文に用語一覧の表（見出し行に「用語」と「識別子」または「定義」を含む
#     表）が無い → 対象外（用語集ではない文書に規則を適用しない）
#   - file_path の拡張子が画面の文言を持つファイルの拡張子ではない → 対象外
#     （表示の文言と語を揃える）
#   - cwd 配下の docs/rules/**/rule.md に「表示の文言と語を揃える」の宣言が
#     無い → 判定せず通知にとどめる（表示の文言と語を揃える）
#
# 既知の限界:
#   - 「使わない語」の区分の有無は見出し・列名の文字列一致でしか判定できない。
#     内容として禁止語を挙げていても、決まった語彙（使わない語/非推奨語/禁止語）
#     を使っていない文書は誤検知しうる
#   - 識別子・定義の欄の検査は、値が非空かどうかしか見ない。定義が1文である
#     かどうか、識別子が実際にコードへ存在するかどうかまでは判定しない
#   - 表示の文言と語を揃える: 宣言から値を取り出す方式は、宣言が自由な文章
#     のため最初に一致した1つだけを見る（複数の語が取り出せても、本文へ
#     実際に含まれていた最初の語だけを拒否理由として示す）。区切りの前後に
#     ある見出しラベル（「使わない語:」等）も語として取り出されうる
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-glossary-missing-forbidden-terms.sh --self-test
#
# 止めるか知らせるか:
#   使ってはいけない語を明示する: 止める（禁止語の宣言が抜けたまま用語集が使われ続けると、後から誤用が積み重なり是正が難しくなるため）
#   語ごとに識別子を対応させる: 止める（識別子の欠落した用語が資料に広まると、後から対応付けを復元するのが難しいため）
#   定義を1文で書く: 止める（定義を欠いた用語が資料に広まると、意味の統一を後から取り戻せなくなるため）
#   表示の文言と語を揃える: 止める（禁止語を含む画面文言が公開されると、利用者に見えた表現は取り消せないため）
#
# 逃げ道:
#   GLOSSARY_MISSING_FORBIDDEN_TERMS_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
set -uo pipefail
export LC_ALL=C

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${GLOSSARY_MISSING_FORBIDDEN_TERMS_SKIP_REASON:-}" ]; then
    echo "[GLOSSARY-MISSING-FORBIDDEN-TERMS-SKIP] 理由: ${GLOSSARY_MISSING_FORBIDDEN_TERMS_SKIP_REASON}"
    return 0
  fi
  return 1
}

FORBIDDEN_RE='(使わない語|非推奨語|禁止語)'

# 用語一覧の表を走査し、識別子・定義の欄の欠落を検出する
# 出力: identifier-missing / identifier-blank / definition-missing / definition-blank を1行1件
scan_glossary_table_columns() {
  local content="$1"
  printf '%s\n' "$content" | awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN { in_table = 0; idx_ident = 0; idx_def = 0 }
    !in_table && /^\|/ && $0 ~ /用語/ && ($0 ~ /識別子/ || $0 ~ /定義/) {
      in_table = 1
      n = split($0, cols, "|"); ncols = n - 2
      for (i = 1; i <= ncols; i++) {
        cell = trim(cols[i+1])
        if (cell == "識別子") idx_ident = i
        if (cell == "定義") idx_def = i
      }
      next
    }
    in_table == 1 && /^\|[-: ]*\|/ { next }
    in_table == 1 && /^\|/ {
      n = split($0, cols, "|"); ncols = n - 2
      ident_val = ""; def_val = ""
      for (i = 1; i <= ncols; i++) {
        cell = trim(cols[i+1])
        if (i == idx_ident) ident_val = cell
        if (i == idx_def) def_val = cell
      }
      if (idx_ident > 0 && ident_val == "") print "identifier-blank"
      if (idx_def > 0 && def_val == "") print "definition-blank"
      next
    }
    in_table == 1 { in_table = 0 }
    END {
      if (idx_ident == 0) print "identifier-missing"
      if (idx_def == 0) print "definition-missing"
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

# 「表示の文言と語を揃える」規則の判定
judge_display_wording() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  case "$file_path" in
    *.tsx|*.jsx|*.vue|*.html|*.svelte) ;;
    *) echo "対象外[表示の文言と語を揃える]: 画面の文言を持つファイルの拡張子ではありません（${file_path}）"; return 0 ;;
  esac

  local override
  override="$(lookup_project_override_content "$cwd" "表示の文言と語を揃える")"
  if [ -z "$override" ]; then
    echo "通知[表示の文言と語を揃える]: このプロジェクトの規則に使わない語の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local terms filtered
  terms="$(printf '%s' "$override" | sed 's/、/\n/g; s/,/\n/g; s/・/\n/g; s/　/\n/g; s/ /\n/g')"
  filtered="$(printf '%s\n' "$terms" | sed '/^[[:space:]]*$/d')"
  if [ -z "$filtered" ]; then
    echo "通知[表示の文言と語を揃える]: このプロジェクトの規則に宣言はありますが、使わない語を読み取れません"
    return 0
  fi

  local found="" term
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    if printf '%s' "$content" | grep -qF -- "$term" 2>/dev/null; then
      found="$term"
      break
    fi
  done <<< "$filtered"

  if [ -n "$found" ]; then
    echo "拒否[表示の文言と語を揃える]: 画面の文言に、用語の一覧で使わないと定めた語が使われています（${found}）"
    return 2
  fi

  echo "許可[表示の文言と語を揃える]: 使わないと定めた語は画面の文言に見当たりません"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は「表示の文言と語を揃える」を対象外として扱う）
  local file_path="$1" content="$2" cwd="${3:-}"

  if [ -n "$cwd" ]; then
    local dw_msg dw_code
    if dw_msg="$(judge_display_wording "$cwd" "$file_path" "$content")"; then dw_code=0; else dw_code=$?; fi
    if [ "$dw_code" -eq 2 ]; then
      echo "$dw_msg"
      return 2
    fi
    echo "$dw_msg"
  fi

  case "$file_path" in
    *.md) ;;
    *)
      echo "対象外[語ごとに識別子を対応させる]: Markdownファイルではありません（${file_path}）"
      echo "対象外[定義を1文で書く]: Markdownファイルではありません（${file_path}）"
      echo "対象外[使ってはいけない語を明示する]: Markdownファイルではありません（${file_path}）"
      return 0
      ;;
  esac

  local header_hit
  header_hit=$(printf '%s\n' "$content" | grep -E '^\|' 2>/dev/null | grep -E '用語' 2>/dev/null | grep -E '(識別子|定義)' 2>/dev/null | head -1)

  if [ -z "$header_hit" ]; then
    echo "対象外[語ごとに識別子を対応させる]: 用語一覧の表（用語・識別子・定義の見出しを持つ表）が見当たりません"
    echo "対象外[定義を1文で書く]: 用語一覧の表（用語・識別子・定義の見出しを持つ表）が見当たりません"
    echo "対象外[使ってはいけない語を明示する]: 用語一覧の表（用語・識別子・定義の見出しを持つ表）が見当たりません"
    return 0
  fi

  local violations missing=""
  violations="$(scan_glossary_table_columns "$content")"

  if printf '%s\n' "$violations" | grep -qE '^identifier-(missing|blank)$'; then
    missing="${missing}拒否[語ごとに識別子を対応させる]: 用語一覧の表の識別子の欄が埋まっていません"$'\n'
  fi
  if printf '%s\n' "$violations" | grep -qE '^definition-(missing|blank)$'; then
    missing="${missing}拒否[定義を1文で書く]: 用語一覧の表の定義の欄が埋まっていません"$'\n'
  fi
  if ! printf '%s\n' "$content" | grep -qE "$FORBIDDEN_RE" 2>/dev/null; then
    missing="${missing}拒否[使ってはいけない語を明示する]: 用語一覧に使わない語の区分が見当たりません"$'\n'
  fi

  if [ -n "$missing" ]; then
    printf '%s' "$missing"
    return 2
  fi

  echo "許可[語ごとに識別子を対応させる]: 用語一覧の表の識別子の欄が埋まっています"
  echo "許可[定義を1文で書く]: 用語一覧の表の定義の欄が埋まっています"
  echo "許可[使ってはいけない語を明示する]: 用語一覧に使わない語の区分があります"
  return 0
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
  [ -z "$content" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[GLOSSARY-MISSING-FORBIDDEN-TERMS-BLOCK] ${msg}。指摘された欄・区分を用語一覧の表へ追加してから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 用語一覧の表があり「使わない語」の区分が無い → 拒否
  local c1='# 用語集

| 用語 | 識別子 | 定義 |
|---|---|---|
| 注文 | order | 利用者が行う購入の申し込み |
'
  if msg="$(judge "docs/glossary/用語集.md" "$c1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: 使わない語の区分が無い用語一覧は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 区分が無いのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 用語一覧の表があり「使わない語」の区分もある → 許可
  local c2='# 用語集

| 用語 | 識別子 | 定義 |
|---|---|---|
| 注文 | order | 利用者が行う購入の申し込み |

## 使わない語

- 発注（旧名称。「注文」を使う）
'
  if msg="$(judge "docs/glossary/用語集.md" "$c2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 使わない語の区分がある用語一覧は許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 区分があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: 「用語」への地の文での言及のみ（表構造ではない）→ 対象外として許可
  local c3='# 設計方針

この文書では用語の定義を行う。詳細は別紙を参照。
'
  if msg="$(judge "docs/design.md" "$c3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 表構造ではない地の文言及は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 表が無いのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: Markdown ファイルではない → 対象外として許可
  local c4='| 用語 | 識別子 | 定義 |
|---|---|---|
| 注文 | order | 購入の申し込み |'
  if msg="$(judge "src/table.txt" "$c4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: Markdown 以外は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: Markdown 以外なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 識別子の列そのものが無い → 拒否（語ごとに識別子を対応させる）
  local c5='# 用語集

| 用語 | 定義 |
|---|---|
| 注文 | 利用者が行う購入の申し込み |

## 使わない語

- 発注（旧名称。「注文」を使う）
'
  if msg="$(judge "docs/glossary/用語集.md" "$c5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '語ごとに識別子を対応させる'; then
    echo "  [PASS] 系5: 識別子の列が無い用語一覧は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: 識別子の列が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系6: 識別子の列はあるが値が空 → 拒否（語ごとに識別子を対応させる）
  local c6='# 用語集

| 用語 | 識別子 | 定義 |
|---|---|---|
| 注文 |  | 利用者が行う購入の申し込み |

## 使わない語

- 発注
'
  if msg="$(judge "docs/glossary/用語集.md" "$c6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '語ごとに識別子を対応させる'; then
    echo "  [PASS] 系6: 識別子の欄が空の用語一覧は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 識別子の欄が空なのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 定義の列そのものが無い → 拒否（定義を1文で書く）
  local c7='# 用語集

| 用語 | 識別子 |
|---|---|
| 注文 | order |

## 使わない語

- 発注
'
  if msg="$(judge "docs/glossary/用語集.md" "$c7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '定義を1文で書く'; then
    echo "  [PASS] 系7: 定義の列が無い用語一覧は拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 定義の列が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 定義の列はあるが値が空 → 拒否（定義を1文で書く）
  local c8='# 用語集

| 用語 | 識別子 | 定義 |
|---|---|---|
| 注文 | order |  |

## 使わない語

- 発注
'
  if msg="$(judge "docs/glossary/用語集.md" "$c8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '定義を1文で書く'; then
    echo "  [PASS] 系8: 定義の欄が空の用語一覧は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 定義の欄が空なのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: 画面の文言を持つファイルの拡張子ではない → 対象外（表示の文言と語を揃える）
  local tmp9
  tmp9="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-missing-forbidden-terms-self-test.XXXXXX")"
  local c9='ページのコンテンツ'
  if msg="$(judge "src/util.py" "$c9" "$tmp9")"; then code=0; else code=$?; fi
  rm -rf "$tmp9"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[表示の文言と語を揃える]'; then
    echo "  [PASS] 系9: 画面の文言を持たない拡張子は「表示の文言と語を揃える」で対象外になる（${msg}）"
  else
    echo "  [FAIL] 系9: 対象外にならない、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 画面の文言を持つファイルだが宣言が無い → 通知（表示の文言と語を揃える）
  local tmp10
  tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-missing-forbidden-terms-self-test.XXXXXX")"
  local c10='<div>ようこそ</div>'
  if msg="$(judge "src/page.html" "$c10" "$tmp10")"; then code=0; else code=$?; fi
  rm -rf "$tmp10"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[表示の文言と語を揃える]'; then
    echo "  [PASS] 系10: 宣言が無ければ「表示の文言と語を揃える」は通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系10: 宣言が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: 宣言があり使わない語が画面の文言に含まれる → 拒否（表示の文言と語を揃える）
  local tmp11
  tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-missing-forbidden-terms-self-test.XXXXXX")"
  mkdir -p "$tmp11/docs/rules/business-domain/glossary-wording"
  cat > "$tmp11/docs/rules/business-domain/glossary-wording/rule.md" <<'EOF'
# 用語定義

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 表示の文言と語を揃える | 使わない語: 旧顧客、得意先 | 静的解析 |
EOF
  local c11='<p>旧顧客の一覧を表示します</p>'
  if msg="$(judge "src/page.html" "$c11" "$tmp11")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[表示の文言と語を揃える]'; then
    echo "  [PASS] 系11: 使わない語が画面の文言に含まれれば拒否される（${msg}）"
  else
    echo "  [FAIL] 系11: 使わない語があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 宣言があり使わない語が画面の文言に含まれない → 許可（表示の文言と語を揃える）
  local tmp12
  tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-glossary-missing-forbidden-terms-self-test.XXXXXX")"
  mkdir -p "$tmp12/docs/rules/business-domain/glossary-wording"
  cat > "$tmp12/docs/rules/business-domain/glossary-wording/rule.md" <<'EOF'
# 用語定義

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 表示の文言と語を揃える | 使わない語: 旧顧客、得意先 | 静的解析 |
EOF
  local c12='<p>顧客の一覧を表示します</p>'
  if msg="$(judge "src/page.html" "$c12" "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[表示の文言と語を揃える]'; then
    echo "  [PASS] 系12: 使わない語を含まない画面の文言は許可される（${msg}）"
  else
    echo "  [FAIL] 系12: 使わない語が無いのに拒否、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 環境変数に理由を設定 → should_skip_with_reasonが戻り値0でタグと理由を返す
  local out13
  if out13="$(GLOSSARY_MISSING_FORBIDDEN_TERMS_SKIP_REASON="テスト用の理由" should_skip_with_reason)"; then
    if printf '%s' "$out13" | grep -qF '[GLOSSARY-MISSING-FORBIDDEN-TERMS-SKIP]' && printf '%s' "$out13" | grep -qF 'テスト用の理由'; then
      echo "  [PASS] 系13: 理由を設定するとタグと理由付きでskipされる（${out13}）"
    else
      echo "  [FAIL] 系13: skipされたがタグまたは理由が出力に含まれない（${out13}）" >&2
      rc=1
    fi
  else
    echo "  [FAIL] 系13: 理由を設定したのにskipされなかった" >&2
    rc=1
  fi

  # 系14: 環境変数が空文字 → should_skip_with_reasonが戻り値1を返す
  if GLOSSARY_MISSING_FORBIDDEN_TERMS_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then
    echo "  [FAIL] 系14: 空文字なのにskipされた" >&2
    rc=1
  else
    echo "  [PASS] 系14: 環境変数が空文字ならskipされない"
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
  *) run_hook ;;
esac
