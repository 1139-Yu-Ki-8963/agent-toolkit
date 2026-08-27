#!/usr/bin/env bash
# check-state-literal-comparison.sh — 状態の移り変わりの決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 状態の移り変わりの決まり
#
# 対象の規則（検査列に「静的解析:」を含む6件すべてを検査する）:
#   1. 状態を文字列の直接の比較で扱わない
#      — 状態を表す識別子と文字列リテラルの直接比較をコードファイルで走査する
#        （既存の検査）
#   2. 移り変わりの引き金を書く
#      — 状態の移り変わりを示す Markdown 表に、引き金・トリガーの欄が
#        あるかを走査する
#   3. 移り変わりを1箇所で行う
#      — 同じ状態項目への代入が、コードファイル内の複数箇所に現れていないか
#        を走査する
#   4. 状態を列挙する
#      — cwd 配下（.git 配下を除く）をファイル名で走査し、名前に「基本設計書」
#        を含む文書を探す。見つかった場合、中身に状態の一覧（「状態一覧」
#        「状態の一覧」の語）が無ければ違反とする
#   5. 許す移り変わりを表で書く
#      — 同じ基本設計書に、状態の移り変わりの表（見出し行に「遷移」または
#        「移り変わり」の語と「元」または「先」の語を持つ表）が無ければ
#        違反とする
#   6. 終わりの状態を決める
#      — 同じ基本設計書に、終わりの状態を示す語（終了状態／完了状態／
#        終端状態／最終状態／終わりの状態）が無ければ違反とする
#
# 判定の設計:
#   文字列直接比較の検査は、比較演算子と引用符という記号的な特徴で機械的に
#   検出する（既存の設計を維持）。
#   移り変わりの引き金の検査は、対象プロジェクトごとに基本設計書の配置が
#   異なるため、ファイルパスではなく「本文の内容が状態の移り変わりの表という
#   構造を持つかどうか」で走査対象を特定する。見出し行に「遷移」または
#   「移り変わり」の語と、それに続く「元」または「先」の語を持つ表を状態
#   遷移表とみなし、見出し行に「引き金」または「トリガー」の欄があるかを
#   機械的に判定する。
#   移り変わりを1箇所で行う検査は、同一ファイル内で同じ状態項目（識別子）
#   への代入（=。比較演算子 ==・===・!=・!== は除く）が複数行に現れるかを
#   数える。ファイルをまたいだ集約は判定しない（既知の限界を参照）。
#   状態を列挙する・許す移り変わりを表で書く・終わりの状態を決めるの3規則は、
#   検査列がいずれも「基本設計書に…が実在するかを走査する」であり、
#   書き込み対象ファイルの本文ではなく別文書の存在確認を求めるため、
#   ファイル名で対象文書を探す方式を取る（check-doc-heading-addendum.sh
#   と同じ考え方）。文書が無い場合を違反として block すると「まだ書いて
#   いないだけ」を止めてしまうため、見つからない場合は対象外として素通し
#   し、見つかった場合にのみ中身を検査する。
#
# 対象ファイル:
#   文字列直接比較の検査・移り変わりを1箇所で行う検査は、拡張子がコード
#   ファイルらしいもの（.js/.jsx/.ts/.tsx/.py/.java/.go/.rb/.php/.cs/.kt/.swift）
#   に限定する。設計文書中の例示コードでの誤検知を避けるため。
#   移り変わりの引き金の検査は Markdown（.md）に限定する。
#   状態を列挙する・許す移り変わりを表で書く・終わりの状態を決めるの3規則は
#   cwd 配下でファイル名に「基本設計書」を含む最初のファイルを対象文書とし、
#   書き込み対象ファイルの拡張子に依存しない。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外（Edit は差分のみで全文を持たないため対象外）
#   - file_path の拡張子がコードファイル一覧・.md のいずれでもない → 対象外
#   - 比較の相手が文字列リテラル（引用符）ではなく定数・変数（例: STATUS_DONE）
#     → 対象外（規則が禁じるのは「文字列の直接の比較」であり、名前の付いた
#     定数との比較は規則が推奨する書き方そのもののため）
#   - 本文に状態の移り変わりの表（見出し行に「遷移」または「移り変わり」の語
#     と「元」または「先」の語を持つ表）が無い → 対象外
#   - 同じ状態項目への代入が1箇所のみ → 対象外（規則が推奨する書き方そのもの）
#   - 4・5・6: cwd が空・存在しない → 対象外（fail-open）。「基本設計書」を
#     含む文書が見当たらない → 対象外（見つかった場合のみ中身を検査する）
#
# 既知の限界:
#   - status/state を含む識別子であればプロパティアクセスの有無に関わらず検出する
#     ため、"statusbar" のように状態とは無関係な識別子も誤検知しうる
#   - 複数行にまたがる比較式は検出できない
#   - 移り変わりの引き金の検査は見出し行の列名一致でしか判定できない
#   - 移り変わりを1箇所で行う検査は、同一ファイル内の代入箇所しか数えない。
#     複数ファイルへ分散した代入は検出できない。誤検知を避けるため、
#     同一の代入先識別子（完全一致）が3行以上に現れた場合のみ違反とする
#     （2行までは条件分岐の両分岐での代入等、正当な書き方でありうるため）
#   - 4・5・6: ファイル名に「基本設計書」を含む最初の1件のみを見る。いずれも
#     決まった語・記号的な特徴（見出し・表・語彙）の有無という近似判定で
#     あり、列挙された状態が実際に対象の実装と対応しているか、表の各行が
#     妥当かまでは検証しない
#
# 止めるか知らせるか:
#   状態を文字列の直接の比較で扱わない: 止める（状態を文字列の直接比較で扱ったまま実装が積み重なると、取り違えの起きる比較が履歴に残り事後に是正できなくなるため）
#   移り変わりの引き金を書く: 止める（引き金を欠いた状態遷移表が確定すると、何が状態を動かすのかを後から復元できなくなるため）
#   移り変わりを1箇所で行う: 止める（同じ状態への代入が複数箇所に分散したまま実装が積み重なると、どこが正の更新経路かを後から復元できなくなるため）
#   状態を列挙する: 止める（状態の一覧を欠いた基本設計書が確定すると、実装が扱う状態の全体像を後から復元できなくなるため）
#   許す移り変わりを表で書く: 止める（許す移り変わりの表を欠いた基本設計書が確定すると、許可されない遷移が実装に紛れ込んでも検出できなくなるため）
#   終わりの状態を決める: 止める（終わりの状態の区分を欠いた基本設計書が確定すると、処理がいつ完了したかを後から判定できなくなるため）
#
# 逃げ道:
#   STATE_LITERAL_COMPARISON_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-state-literal-comparison.sh --self-test
set -uo pipefail
export LC_ALL=C

IDENT='[A-Za-z0-9_.]*(status|state)[A-Za-z0-9_]*'
CMP='(==|===|!=|!==)'
STR='("[^"]*"|'"'"'[^'"'"']*'"'"')'
PATTERN="(${IDENT}[[:space:]]*${CMP}[[:space:]]*${STR})|(${STR}[[:space:]]*${CMP}[[:space:]]*${IDENT})"

BASIC_DESIGN_DOC_NEEDLE='基本設計書'
STATE_ENUM_RE='状態(の)?一覧'
TERMINAL_STATE_RE='(終了状態|完了状態|終端状態|最終状態|終わりの状態)'

# 指定した cwd 配下（.git 配下を除く）から、ファイル名に needle を含む
# 最初のファイルを返す。見つからなければ空を返す
find_doc_by_name() {
  local cwd="$1" needle="$2"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    return 0
  fi
  find "$cwd" -type f -not -path '*/.git/*' -name "*${needle}*" 2>/dev/null | head -1
}

# 状態の移り変わりの表（見出し行に「遷移」または「移り変わり」の語と
# 「元」または「先」の語を持つ）が本文に含まれるかを判定する
has_transition_table() {
  local content="$1"
  printf '%s\n' "$content" | grep -E '^\|' 2>/dev/null | grep -E '(遷移|移り変わり)' 2>/dev/null | grep -qE '(元|先)' 2>/dev/null
}

is_code_ext() {
  case "$1" in
    *.js|*.jsx|*.ts|*.tsx|*.py|*.java|*.go|*.rb|*.php|*.cs|*.kt|*.swift) return 0 ;;
    *) return 1 ;;
  esac
}

# 状態遷移表の見出し行を検査し、「引き金」の欄が無ければ理由を返す
scan_transition_table_header() {
  local content="$1"
  local header_hit
  header_hit=$(printf '%s\n' "$content" | grep -E '^\|' 2>/dev/null | grep -E '(遷移|移り変わり)' 2>/dev/null | grep -E '(元|先)' 2>/dev/null | head -1)

  if [ -z "$header_hit" ]; then
    echo "対象外[移り変わりの引き金を書く]: 状態の移り変わりの表が見当たりません"
    return 0
  fi

  if printf '%s' "$header_hit" | grep -qE '(引き金|トリガー)'; then
    echo "許可[移り変わりの引き金を書く]: 状態の移り変わりの表に引き金の欄があります"
    return 0
  fi

  echo "拒否[移り変わりの引き金を書く]: 状態の移り変わりの表はあるが引き金・トリガーの欄が見当たりません（${header_hit}）"
  return 2
}

# 同一ファイル内で同じ代入先識別子（status/state を含む）への代入が
# 3行以上に現れる場合、その識別子名を返す
scan_scattered_state_assignment() {
  local content="$1"
  printf '%s\n' "$content" \
    | grep -oE "${IDENT}[[:space:]]*=[[:space:]]*[^=]" 2>/dev/null \
    | grep -oE "^${IDENT}" 2>/dev/null \
    | sort \
    | uniq -c \
    | awk '$1 >= 3 { $1=""; sub(/^ /, ""); print }'
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は規則4・5・6を対象外として扱う）
  local file_path="$1" content="$2" cwd="${3:-}"

  # 規則: 状態を列挙する／許す移り変わりを表で書く／終わりの状態を決める
  # （書き込み対象ファイルの拡張子に依存しない）
  local basic_design_doc
  basic_design_doc="$(find_doc_by_name "$cwd" "$BASIC_DESIGN_DOC_NEEDLE")"
  if [ -n "$basic_design_doc" ]; then
    local doc_body relpath
    doc_body="$(cat "$basic_design_doc" 2>/dev/null)"
    relpath="${basic_design_doc#"$cwd"/}"

    if ! printf '%s' "$doc_body" | grep -qE -- "$STATE_ENUM_RE"; then
      echo "拒否[状態を列挙する]: 基本設計書（${relpath}）は実在するが、状態の一覧の記述が見当たりません"
      return 2
    fi

    if ! has_transition_table "$doc_body"; then
      echo "拒否[許す移り変わりを表で書く]: 基本設計書（${relpath}）は実在するが、状態の移り変わりの表が見当たりません"
      return 2
    fi

    if ! printf '%s' "$doc_body" | grep -qE -- "$TERMINAL_STATE_RE"; then
      echo "拒否[終わりの状態を決める]: 基本設計書（${relpath}）は実在するが、終わりの状態の区分が見当たりません"
      return 2
    fi
  fi

  if is_code_ext "$file_path"; then
    local hit
    hit=$(printf '%s\n' "$content" | grep -inE "$PATTERN" 2>/dev/null | head -1)

    if [ -n "$hit" ]; then
      echo "拒否[状態を文字列の直接の比較で扱わない]: 状態を文字列リテラルと直接比較している行があります（${hit}）"
      return 2
    fi

    local scattered
    scattered="$(scan_scattered_state_assignment "$content")"
    if [ -n "$scattered" ]; then
      echo "拒否[移り変わりを1箇所で行う]: 同じ状態項目への代入が複数箇所に現れています（${scattered}）"
      return 2
    fi

    echo "許可: 状態を文字列リテラルと直接比較している行、および同一項目への分散した代入は見当たりません"
    return 0
  fi

  case "$file_path" in
    *.md) ;;
    *) echo "対象外: コードファイルの拡張子、または状態の移り変わりの表を検査できる Markdown のいずれでもありません（${file_path}）"; return 0 ;;
  esac

  local msg code
  if msg="$(scan_transition_table_header "$content")"; then code=0; else code=$?; fi
  echo "$msg"
  return "$code"
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${STATE_LITERAL_COMPARISON_SKIP_REASON:-}" ]; then
    echo "[STATE-LITERAL-COMPARISON-SKIP] 理由: ${STATE_LITERAL_COMPARISON_SKIP_REASON}"
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

  ctx="[STATE-LITERAL-COMPARISON-BLOCK] ${msg}。状態は名前の付いた定数として定義し、文字列の直接比較をやめてから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: status を文字列リテラルと直接比較 → 拒否
  local c1='function isShipped(order) {
  return order.status == "shipped";
}'
  if msg="$(judge "order.js" "$c1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: status == \"shipped\" は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 文字列直接比較なのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 文字列リテラルを先に置いた逆順の比較 → 拒否
  local c2='if ("active" === user.state) { return true; }'
  if msg="$(judge "user.ts" "$c2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系2: \"active\" === state は拒否される（${msg}）"
  else
    echo "  [FAIL] 系2: 逆順の文字列直接比較なのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: 名前の付いた定数との比較（文字列リテラルではない）→ 許可
  local c3='if (order.status == STATUS_SHIPPED) { return true; }'
  if msg="$(judge "order.js" "$c3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 定数との比較は許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 定数比較なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: コードファイルの拡張子ではない（.md） → 対象外として許可
  local c4='order.status == "shipped"'
  if msg="$(judge "docs/example.md" "$c4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: コードファイル以外は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: コードファイル以外なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5（近傍事例）: status/state を含まない通常の比較 → 許可
  local c5='if (count == 5) { return true; }'
  if msg="$(judge "app.js" "$c5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系5: status/state を含まない比較は許可される（${msg}）"
  else
    echo "  [FAIL] 系5: 無関係な比較なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系6: 状態遷移表に引き金の欄が無い → 拒否（移り変わりの引き金を書く）
  local c6='# 状態遷移
| 遷移元 | 遷移先 | 条件 |
|---|---|---|
| 未処理 | 処理中 | 受付完了 |'
  if msg="$(judge "docs/状態遷移.md" "$c6")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '移り変わりの引き金を書く'; then
    echo "  [PASS] 系6: 引き金の欄が無い状態遷移表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 引き金の欄が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 状態遷移表に引き金の欄がある → 許可
  local c7='# 状態遷移
| 遷移元 | 遷移先 | 引き金 |
|---|---|---|
| 未処理 | 処理中 | 受付完了 |'
  if msg="$(judge "docs/状態遷移.md" "$c7")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 引き金の欄がある状態遷移表は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 引き金の欄があるのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 同じ状態項目への代入が3箇所（複数の場所）に分散 → 拒否（移り変わりを1箇所で行う）
  local c8='function transition(order) {
  if (a) { order.status = "A"; }
  if (b) { order.status = "B"; }
  if (c) { order.status = "C"; }
}'
  if msg="$(judge "order.js" "$c8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '移り変わりを1箇所で行う'; then
    echo "  [PASS] 系8: 同じ状態項目への3箇所の代入は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 3箇所の代入があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9: 同じ状態項目への代入が1箇所のみ → 許可
  local c9='function transition(order) {
  order.status = "A";
}'
  if msg="$(judge "order.js" "$c9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 同じ状態項目への代入が1箇所のみなら許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 代入が1箇所のみなのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10（近傍事例）: 同じ状態項目への代入が2箇所（閾値未満）→ 許可
  local c10='function transition(order) {
  if (a) { order.status = "A"; } else { order.status = "B"; }
}'
  if msg="$(judge "order.js" "$c10")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 2箇所の代入（閾値未満）は許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 2箇所の代入なのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: 基本設計書らしき文書が cwd に無い → 対象外として許可
  local tmp11
  if ! tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-state-literal-comparison-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp11" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp11/docs"
  printf '# メモ\n' > "$tmp11/docs/メモ.md"
  if msg="$(judge "docs/note.md" '' "$tmp11")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系11: 基本設計書が見当たらなければ対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系11: 基本設計書が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 基本設計書は実在するが状態の一覧の記述が無い → 拒否（状態を列挙する）
  local tmp12
  if ! tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-state-literal-comparison-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp12" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp12/docs"
  printf '# 注文機能基本設計書\n\n## 外部仕様\n画面の項目を定める。\n' > "$tmp12/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '状態を列挙する'; then
    echo "  [PASS] 系12: 状態の一覧が無い基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系12: 状態の一覧が無いのに許可、または規則名不一致（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 状態の一覧はあるが移り変わりの表が無い → 拒否（許す移り変わりを表で書く）
  local tmp13
  if ! tmp13="$(mktemp -d "${TMPDIR:-/tmp}/check-state-literal-comparison-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp13" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp13/docs"
  printf '# 注文機能基本設計書\n\n## 状態一覧\n- 未処理\n- 処理中\n- 完了\n' > "$tmp13/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp13")"; then code=0; else code=$?; fi
  rm -rf "$tmp13"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '許す移り変わりを表で書く'; then
    echo "  [PASS] 系13: 移り変わりの表が無い基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系13: 移り変わりの表が無いのに許可、または規則名不一致（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系14: 状態の一覧・移り変わりの表はあるが終わりの状態の区分が無い → 拒否（終わりの状態を決める）
  local tmp14
  if ! tmp14="$(mktemp -d "${TMPDIR:-/tmp}/check-state-literal-comparison-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp14" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp14/docs"
  printf '# 注文機能基本設計書\n\n## 状態一覧\n- 未処理\n- 処理中\n- 完了\n\n## 状態遷移\n| 遷移元 | 遷移先 |\n|---|---|\n| 未処理 | 処理中 |\n' > "$tmp14/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp14")"; then code=0; else code=$?; fi
  rm -rf "$tmp14"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '終わりの状態を決める'; then
    echo "  [PASS] 系14: 終わりの状態の区分が無い基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系14: 終わりの状態の区分が無いのに許可、または規則名不一致（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系15: 状態の一覧・移り変わりの表・終わりの状態の区分がすべて揃っている → 許可
  local tmp15
  if ! tmp15="$(mktemp -d "${TMPDIR:-/tmp}/check-state-literal-comparison-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp15" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼"
    exit 2
  fi
  mkdir -p "$tmp15/docs"
  printf '# 注文機能基本設計書\n\n## 状態一覧\n- 未処理\n- 処理中\n- 完了状態\n\n## 状態遷移\n| 遷移元 | 遷移先 |\n|---|---|\n| 未処理 | 処理中 |\n' > "$tmp15/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp15")"; then code=0; else code=$?; fi
  rm -rf "$tmp15"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系15: 状態一覧・移り変わりの表・終わりの状態の区分が揃った基本設計書は許可される（${msg}）"
  else
    echo "  [FAIL] 系15: すべて揃っているのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系16: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(STATE_LITERAL_COMPARISON_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'STATE-LITERAL-COMPARISON-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系16: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系16: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系17: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if STATE_LITERAL_COMPARISON_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
  if [ "$skip_code2" -eq 1 ]; then
    echo "  [PASS] 系17: 環境変数が空文字なら should_skip_with_reason は skip しない"
  else
    echo "  [FAIL] 系17: 空文字なのに skip した（exit=${skip_code2}）" >&2
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
