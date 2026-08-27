#!/usr/bin/env bash
# check-currency-float-type.sh — 金額と数量の計算の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 金額と数量の計算の決まり
#
# 対象の規則（検査列に「静的解析:」を含む6件すべてを検査する）:
#   1. 金額を小数で扱わない
#      — 金額らしい識別子の宣言が誤差の出る小数型（float/double）でないかを
#        コードファイルで走査する（既存の検査）
#   2. 端数の扱いを式ごとに決める
#      — 「計算式」の欄を持つ Markdown 表に、丸め・端数の欄があるかを走査する
#   3. 計算の順序を明示する
#      — 同じ表に、順序・順番の欄があるかを走査する
#   4. 単位を式と項目に付ける
#      — 同じ表に、単位の欄があるかを走査する（数量を扱う識別子側の検査は
#        次項「既知の限界」を参照）
#   5. 式を設計書へ書く
#      — cwd 配下（.git 配下を除く）をファイル名で走査し、名前に「基本設計書」
#        を含む文書を探す。見つかった場合、中身に「計算式」の語が無ければ
#        違反とする
#   6. 境界の値で確かめる
#      — 金額語彙と四則演算子が同一行で共起する行があるかで「計算を行う
#        記述」の有無をまず見る。無ければ対象外とする。あれば cwd 配下の
#        docs/rules/**/rule.md の「## このプロジェクトの規則」表から、
#        規則名「境界の値で確かめる」の宣言（試験ファイルの名前の型）を
#        引く。宣言が無ければ判定せず通知にとどめる。宣言があれば、
#        書き込み対象ファイルの拡張子を除いた名前を含む、宣言の名前の型に
#        一致する試験ファイルが cwd 配下に実在するかを走査する
#
# （「単位を式と項目に付ける」のうち「数量を扱う識別子に単位を示す語が
#   含まれているか」というコード側の検査も、単位語彙が識別子として現れる
#   保証が無く誤検知が避けられないため実装せず、設計書側の欄の検査のみ
#   に留めた。既知の限界として明記する）
#
# 判定の設計:
#   金額の小数型検査は、型キーワード float/double と金額語彙の同一行での
#   共起という記号的な特徴で機械的に検出する（既存の設計を維持）。
#   計算式の表に関する3規則は、対象プロジェクトごとに基本設計書の配置が
#   異なるため、ファイルパスではなく「本文の内容が計算式の表という構造を
#   持つかどうか」で走査対象を特定する。Markdown 表の見出し行に「計算式」
#   列があれば、その表を計算式の記述とみなし、他の必須の欄（丸め・端数／
#   順序・順番／単位）の有無を見出し行から機械的に判定する。
#   「式を設計書へ書く」は検査列が「基本設計書に計算の式の記述が実在するか
#   を走査する」であり、書き込み対象ファイルの本文ではなく別文書の存在
#   確認を求めるため、ファイル名で対象文書を探す方式を取る
#   （check-doc-heading-addendum.sh と同じ考え方）。文書が無い場合を違反として
#   block すると「まだ書いていないだけ」を止めてしまうため、見つからない
#   場合は対象外として素通しし、見つかった場合にのみ中身を検査する。
#
# 対象ファイル:
#   金額の小数型検査は、float / double という型キーワードを持つ言語の拡張子
#   （.java/.cs/.go/.kt/.swift/.cpp/.cc/.c/.php）に限定する。JavaScript /
#   TypeScript / Ruby は数値型が単一で float 型キーワードを持たないため対象外
#   （既知の限界として本文に明記）。
#   計算式の表検査は Markdown（.md）に限定する。
#   「式を設計書へ書く」は cwd 配下でファイル名に「基本設計書」を含む
#   最初のファイルを対象文書とし、書き込み対象ファイルの拡張子に依存しない。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外（Edit は差分のみで全文を持たないため対象外）
#   - file_path の拡張子が対象言語一覧・.md のいずれでもない → 対象外
#   - float/double 型キーワードと金額語彙が同一行で共起しない → 対象外
#     （例: 金額と無関係な double の使用、BigDecimal 等の小数型でない金額宣言）
#   - 本文に「計算式」列を持つ表が無い → 対象外（計算式の記述ではない文書に
#     規則を適用しない）
#   - 式を設計書へ書く: cwd が空・存在しない → 対象外（fail-open）。
#     「基本設計書」を含む文書が見当たらない → 対象外（見つかった場合のみ
#     中身を検査する）
#
# 既知の限界:
#   - JavaScript / TypeScript のように float 型キーワードを持たない言語では
#     金額の小数型検査は機能しない（規則自体は該当するが、型キーワードでの
#     機械検出が成立しない）
#   - 同一行での文字列共起のみを見るため、コメント中の言及も誤検知しうる
#   - 計算式の表検査は見出し行の列名一致でしか判定できない。各行の内容の
#     妥当性（丸めの方法が実際に正しいか等）までは判定しない
#   - 「単位を式と項目に付ける」はコード識別子側を検査しない（上記参照）
#   - 式を設計書へ書く: ファイル名に「基本設計書」を含む最初の1件のみを見る。
#     「計算式」の語の有無という近似判定であり、書かれている式が実際の
#     コードの式と対応しているかまでは検証しない
#
# 既知の限界（境界の値で確かめる）:
#   - 試験ファイルの名前の型は「このプロジェクトの規則」の宣言から
#     `*` を含む語を1つ取り出す方式で読む。宣言が自由な文章のため、
#     複数の型が書かれている場合は最初の1つだけを見る
#   - 試験ファイルの実在だけを見る。その試験が実際に境界の値
#     （0・上限・下限・端数）を使っているかまでは確かめない
#
# 止めるか知らせるか:
#   金額を小数で扱わない: 止める（金額を誤差の出る小数型で扱ったまま計算が積み重なると、丸め誤差が履歴に残り事後に検出できなくなるため）
#   端数の扱いを式ごとに決める: 止める（端数の扱いを決めないまま式が確定すると、計算結果の食い違いが履歴に固定され事後に是正できなくなるため）
#   計算の順序を明示する: 止める（順序を決めないまま式が確定すると、実装ごとに異なる結果が履歴に固定されるため）
#   単位を式と項目に付ける: 止める（単位を欠いた式が確定すると、後から数値の意味を復元できなくなるため）
#   式を設計書へ書く: 止める（計算式を欠いた基本設計書が確定すると、実装の根拠となる式を後から復元できなくなるため）
#   境界の値で確かめる: 止める（境界値の試験を欠いたまま計算処理が確定すると、境界での不具合が検出されないまま履歴に残るため）
#
# 逃げ道:
#   CURRENCY_FLOAT_TYPE_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-currency-float-type.sh --self-test
set -uo pipefail
export LC_ALL=C

# 桁数を名前に含む型（Go の float64 / float32、C# の Single/Double 相当の
# 別名など）も誤差の出る小数である。桁数を許さない形にしていたため、
# Go でよく書かれる float64 が素通りしていた
# （実測 2026-08-24: 別の言語の書き方を与えて分かった）。
TYPE_RE='\<(float|double)[0-9]*\>'
MONEY_RE='(amount|price|cost|fee|total|balance|payment|charge|salary)'

BASIC_DESIGN_DOC_NEEDLE='基本設計書'

# 指定した cwd 配下（.git 配下を除く）から、ファイル名に needle を含む
# 最初のファイルを返す。見つからなければ空を返す
find_doc_by_name() {
  local cwd="$1" needle="$2"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' -name "*${needle}*" 2>/dev/null | head -1
}

is_typed_ext() {
  case "$1" in
    *.java|*.cs|*.go|*.kt|*.swift|*.cpp|*.cc|*.c|*.php) return 0 ;;
    *) return 1 ;;
  esac
}

# 計算式の表の見出し行を検査し、欠けている欄を規則ごとに1行1件返す
scan_formula_table_header() {
  local header_hit="$1"
  printf '%s' "$header_hit" | grep -qE '(丸め|端数)' || echo "拒否[端数の扱いを式ごとに決める]: 計算式の表に丸め・端数の欄がありません"
  printf '%s' "$header_hit" | grep -qE '(順序|順番)' || echo "拒否[計算の順序を明示する]: 計算式の表に順序・順番の欄がありません"
  printf '%s' "$header_hit" | grep -qF '単位' || echo "拒否[単位を式と項目に付ける]: 計算式の表に単位の欄がありません"
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

# 「境界の値で確かめる」規則の判定
judge_boundary_test() {
  # $1: cwd, $2: file_path, $3: content
  local cwd="$1" file_path="$2" content="$3"

  if ! printf '%s\n' "$content" | grep -iE "$MONEY_RE" 2>/dev/null | grep -qE '[+*/-]'; then
    echo "対象外[境界の値で確かめる]: 計算を行う記述が見当たりません"
    return 0
  fi

  local override
  override="$(lookup_project_override_content "$cwd" "境界の値で確かめる")"
  if [ -z "$override" ]; then
    echo "通知[境界の値で確かめる]: このプロジェクトの規則に試験の置き場の宣言がないため判定していません。リバース解析を実行すると判定の対象になります"
    return 0
  fi

  local pattern
  pattern="$(printf '%s\n' "$override" | tr ' ' '\n' | grep -F '*' | head -1)"
  if [ -z "$pattern" ]; then
    echo "通知[境界の値で確かめる]: このプロジェクトの規則に宣言はありますが、試験ファイルの名前の型（* を含む語）が読み取れません"
    return 0
  fi

  local base
  base="$(basename "$file_path")"
  base="${base%.*}"

  local found candidate candidate_name
  found=""
  while IFS= read -r candidate; do
    [ -z "$candidate" ] && continue
    candidate_name="$(basename "$candidate")"
    case "$candidate_name" in
      *"$base"*) found="$candidate"; break ;;
    esac
  done < <(find "$cwd" -type f -not -path '*/.git/*' -name "$pattern" 2>/dev/null)

  if [ -z "$found" ]; then
    echo "拒否[境界の値で確かめる]: 計算を行う処理（${base}）に対応する試験が見当たりません"
    return 2
  fi

  local relpath="${found#"$cwd"/}"
  echo "許可[境界の値で確かめる]: 対応する試験（${relpath}）が実在します"
  return 0
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は「式を設計書へ書く」を対象外として扱う）
  local file_path="$1" content="$2" cwd="${3:-}"

  # 規則: 境界の値で確かめる
  if [ -n "$cwd" ]; then
    local boundary_msg boundary_code
    if boundary_msg="$(judge_boundary_test "$cwd" "$file_path" "$content")"; then boundary_code=0; else boundary_code=$?; fi
    if [ "$boundary_code" -eq 2 ]; then
      echo "$boundary_msg"
      return 2
    fi
    echo "$boundary_msg"
  fi

  # 規則: 式を設計書へ書く（書き込み対象ファイルの拡張子に依存しない）
  local basic_design_doc
  basic_design_doc="$(find_doc_by_name "$cwd" "$BASIC_DESIGN_DOC_NEEDLE")"
  if [ -n "$basic_design_doc" ]; then
    local doc_body relpath
    doc_body="$(cat "$basic_design_doc" 2>/dev/null)"
    relpath="${basic_design_doc#"$cwd"/}"
    if ! printf '%s' "$doc_body" | grep -qF '計算式'; then
      echo "拒否[式を設計書へ書く]: 基本設計書（${relpath}）は実在しますが、計算式の記述が見当たりません"
      return 2
    fi
  fi

  if is_typed_ext "$file_path"; then
    local hit
    hit=$(printf '%s\n' "$content" | grep -inE "$TYPE_RE" 2>/dev/null | grep -Ei "$MONEY_RE" 2>/dev/null | head -1)

    if [ -n "$hit" ]; then
      echo "拒否[金額を小数で扱わない]: 金額らしい識別子が誤差の出る小数型で宣言されています（${hit}）"
      return 2
    fi

    echo "許可[金額を小数で扱わない]: 金額らしい識別子が小数型で宣言されている行は見当たりません"
    return 0
  fi

  case "$file_path" in
    *.md) ;;
    *) echo "対象外[金額を小数で扱わない]: float/double 型を持つ言語の拡張子、または計算式の表を検査できる Markdown のいずれでもありません（${file_path}）"; return 0 ;;
  esac

  local header_hit
  header_hit=$(printf '%s\n' "$content" | grep -E '^\|' 2>/dev/null | grep -F '計算式' 2>/dev/null | head -1)

  if [ -z "$header_hit" ]; then
    echo "対象外[端数の扱いを式ごとに決める]: 計算式の欄を持つ表が見当たりません"
    echo "対象外[計算の順序を明示する]: 計算式の欄を持つ表が見当たりません"
    echo "対象外[単位を式と項目に付ける]: 計算式の欄を持つ表が見当たりません"
    return 0
  fi

  local missing
  missing="$(scan_formula_table_header "$header_hit")"

  if [ -n "$missing" ]; then
    printf '%s\n' "$missing"
    return 2
  fi

  echo "許可[端数の扱いを式ごとに決める]: 計算式の表に丸め・端数の欄があります"
  echo "許可[計算の順序を明示する]: 計算式の表に順序・順番の欄があります"
  echo "許可[単位を式と項目に付ける]: 計算式の表に単位の欄があります"
  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${CURRENCY_FLOAT_TYPE_SKIP_REASON:-}" ]; then
    echo "[CURRENCY-FLOAT-TYPE-SKIP] 理由: ${CURRENCY_FLOAT_TYPE_SKIP_REASON}"
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
  [ -z "$content" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

  local msg code
  if msg="$(judge "$file_path" "$content" "$cwd")"; then code=0; else code=$?; fi

  [ "$code" -eq 0 ] && exit 0

  ctx="[CURRENCY-FLOAT-TYPE-BLOCK] ${msg}。金額は誤差の出ない型（整数の最小単位・BigDecimal 等）で扱ってから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: double + totalPrice の宣言 → 拒否
  local c1='public class Order {
  private double totalPrice;
}'
  if msg="$(judge "Order.java" "$c1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: double totalPrice は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 金額の小数宣言なのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: float + unitCost の宣言（別言語）→ 拒否
  local c2='public class Item {
    public float unitCost;
}'
  if msg="$(judge "Item.cs" "$c2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: float unitCost は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 金額の小数宣言なのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: 金額と無関係な double の使用 → 許可
  local c3='public class Point {
  private double distance;
}'
  if msg="$(judge "Point.java" "$c3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 金額と無関係な double は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 金額と無関係な小数宣言なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: BigDecimal 等の小数型でない金額宣言 → 許可
  local c4='public class Order {
  private BigDecimal amount;
}'
  if msg="$(judge "Order.java" "$c4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: BigDecimal による金額宣言は許可される（${msg}）"
  else
    echo "  [FAIL] 系4: BigDecimal 宣言なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: float/double 型キーワードを持たない言語の拡張子（.ts） → 対象外として許可
  local c5='let totalPrice: number = 0.0;'
  if msg="$(judge "order.ts" "$c5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: float/double を持たない言語は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系5: 対象外言語なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 計算式の表に丸め・端数の欄が無い → 拒否（端数の扱いを式ごとに決める）
  local c6='# 計算規則
| 対象 | 計算式 | 順序 | 単位 |
|---|---|---|---|
| 消費税 | 税抜額 * 税率 | 1 | 円 |'
  if msg="$(judge "docs/計算規則.md" "$c6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '端数の扱いを式ごとに決める'; then
    echo "  [PASS] 系6: 丸め・端数の欄が無い計算式の表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 丸め・端数の欄が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 計算式の表に順序・順番の欄が無い → 拒否（計算の順序を明示する）
  local c7='# 計算規則
| 対象 | 計算式 | 丸め | 単位 |
|---|---|---|---|
| 消費税 | 税抜額 * 税率 | 切り捨て | 円 |'
  if msg="$(judge "docs/計算規則.md" "$c7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '計算の順序を明示する'; then
    echo "  [PASS] 系7: 順序・順番の欄が無い計算式の表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系7: 順序・順番の欄が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 計算式の表に根拠の欄が無くても許可
  local c8='# 計算規則
| 対象 | 計算式 | 丸め | 順序 | 単位 |
|---|---|---|---|---|
| 消費税 | 税抜額 * 税率 | 切り捨て | 1 | 円 |'
  if msg="$(judge "docs/計算規則.md" "$c8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系8: 根拠の欄が無い計算式の表は許可される（${msg}）"
  else
    echo "  [FAIL] 系8: 根拠の欄が無い計算式の表が拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: 計算式の表に単位の欄が無い → 拒否（単位を式と項目に付ける）
  local c9='# 計算規則
| 対象 | 計算式 | 丸め | 順序 |
|---|---|---|---|
| 消費税 | 税抜額 * 税率 | 切り捨て | 1 |'
  if msg="$(judge "docs/計算規則.md" "$c9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '単位を式と項目に付ける'; then
    echo "  [PASS] 系9: 単位の欄が無い計算式の表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系9: 単位の欄が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 計算式の表に丸め・順序・単位のすべての欄がある → 許可
  local c10='# 計算規則
| 対象 | 計算式 | 丸め | 順序 | 単位 |
|---|---|---|---|---|
| 消費税 | 税抜額 * 税率 | 切り捨て | 1 | 円 |'
  if msg="$(judge "docs/計算規則.md" "$c10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 必須の欄がすべて揃った計算式の表は許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 必須の欄が揃っているのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11（近傍事例）: 計算式の欄を持たない表 → 対象外として許可
  local c11='# 画面一覧
| 対象 | 説明 |
|---|---|
| 注文 | 注文一覧を表示する |'
  if msg="$(judge "docs/画面一覧.md" "$c11")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 計算式の欄を持たない表は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 計算式の表ではないのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 基本設計書らしき文書が cwd に無い → 対象外として許可（式を設計書へ書く）
  local tmp12
  if ! tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp12" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp12/docs"
  printf '# メモ\n' > "$tmp12/docs/メモ.md"
  if msg="$(judge "docs/note.md" '' "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: 基本設計書が見当たらなければ「式を設計書へ書く」は対象外として通過する（${msg}）"
  else
    echo "  [FAIL] 系12: 基本設計書が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 基本設計書は実在するが「計算式」の語が見当たらない → 拒否（式を設計書へ書く）
  local tmp13
  if ! tmp13="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp13" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp13/docs"
  printf '# 注文機能基本設計書\n\n## 外部仕様\n画面の項目を定める。\n' > "$tmp13/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp13")"; then code=0; else code=$?; fi
  rm -rf "$tmp13"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '式を設計書へ書く'; then
    echo "  [PASS] 系13: 計算式の記述が無い基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系13: 計算式の記述が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系14: 基本設計書が実在し「計算式」の記述もある → 許可
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp14/docs"
  printf '# 注文機能基本設計書\n\n## 計算式\n税抜額 * 税率 で消費税額を求める。\n' > "$tmp14/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系14: 計算式の記述がある基本設計書は許可される（${msg}）"
  else
    echo "  [FAIL] 系14: 計算式の記述があるのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系15: 計算らしい記述が無いコード → 対象外（境界の値で確かめる）
  local tmp15
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  local c15='public class Point { private double distance; }'
  if msg="$(judge "Point.java" "$c15" "$tmp15")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '対象外[境界の値で確かめる]'; then
    echo "  [PASS] 系15: 計算らしい記述が無ければ「境界の値で確かめる」は対象外になる（${msg}）"
  else
    echo "  [FAIL] 系15: 計算らしい記述が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系16: 計算らしい記述はあるが試験の置き場の宣言が無い → 通知（境界の値で確かめる）
  local tmp16
  if ! tmp16="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp16" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  local c16='public class Order { int total = price * quantity; }'
  if msg="$(judge "Order.java" "$c16" "$tmp16")"; then code=0; else code=$?; fi
  rm -rf "$tmp16"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '通知[境界の値で確かめる]'; then
    echo "  [PASS] 系16: 試験の置き場の宣言が無ければ「境界の値で確かめる」は通知にとどまる（${msg}）"
  else
    echo "  [FAIL] 系16: 宣言が無いのに判定された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系17: 宣言はあるが対応する試験が無い → 拒否（境界の値で確かめる）
  local tmp17
  if ! tmp17="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp17" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp17/docs/rules/business-domain/calculation-rules"
  cat > "$tmp17/docs/rules/business-domain/calculation-rules/rule.md" <<'EOF'
# 金額と数量の計算の決まり

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 境界の値で確かめる | 試験は *.test.java へ置く | 静的解析 |
EOF
  local c17='public class Order { int total = price * quantity; }'
  if msg="$(judge "src/Order.java" "$c17" "$tmp17")"; then code=0; else code=$?; fi
  rm -rf "$tmp17"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '拒否[境界の値で確かめる]'; then
    echo "  [PASS] 系17: 対応する試験が無ければ「境界の値で確かめる」は拒否される（${msg}）"
  else
    echo "  [FAIL] 系17: 対応する試験が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系18: 系17と同じ宣言があり、対応する試験が実在する → 許可（境界の値で確かめる）
  local tmp18
  if ! tmp18="$(mktemp -d "${TMPDIR:-/tmp}/check-currency-float-type-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp18" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp18/docs/rules/business-domain/calculation-rules"
  cat > "$tmp18/docs/rules/business-domain/calculation-rules/rule.md" <<'EOF'
# 金額と数量の計算の決まり

## このプロジェクトの規則

| 規則 | 内容 | 検査 |
|---|---|---|
| 境界の値で確かめる | 試験は *.test.java へ置く | 静的解析 |
EOF
  mkdir -p "$tmp18/src"
  printf 'public class OrderTest {}\n' > "$tmp18/src/Order.test.java"
  local c18='public class Order { int total = price * quantity; }'
  if msg="$(judge "src/Order.java" "$c18" "$tmp18")"; then code=0; else code=$?; fi
  rm -rf "$tmp18"
  if [ "$code" -eq 0 ] && printf '%s' "$msg" | grep -qF '許可[境界の値で確かめる]'; then
    echo "  [PASS] 系18: 対応する試験が実在すれば「境界の値で確かめる」は許可される（${msg}）"
  else
    echo "  [FAIL] 系18: 対応する試験があるのに拒否された、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系19: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(CURRENCY_FLOAT_TYPE_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'CURRENCY-FLOAT-TYPE-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系19: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系19: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系20: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if CURRENCY_FLOAT_TYPE_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系20: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系20: 空文字なのに skip した（exit=${skip_code2}）" >&2
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
  *) run_hook ;;
esac
