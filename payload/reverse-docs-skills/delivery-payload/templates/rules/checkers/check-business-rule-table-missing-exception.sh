#!/usr/bin/env bash
# check-business-rule-table-missing-exception.sh — 業務の判定の書き方の決まりの linter
#
# timing: PreToolUse(Write)
# 対象規約: 業務の判定の書き方の決まり
#
# 対象の規則（検査列に「静的解析:」を含む5件すべてを検査する）:
#   1. 例外と境界を明示する
#      — 業務の判定表（条件・結果の見出しを持つ表）に、例外の列があるかを
#        走査する（既存の検査）
#   2. 判定を1箇所に集める
#      — コードファイルの複雑な条件式が、同じリポジトリ内の他のファイルにも
#        同一の文字列で現れていないかを走査する
#   3. 規則に名前を付けて参照する
#      — 業務の判定表に、名前の列があるかを走査する（列の値がコード識別子と
#        して実際に使われているかは検査しない。次項「既知の限界」を参照）
#   4. 判定を表示の層に置かない
#      — 表示を組み立てる層らしいファイル（コンポーネント・ビュー・ページ・
#        テンプレート）に、複雑な条件式（比較演算子と論理演算子を combine
#        した if 文）が無いかを走査する
#   5. 判定を表で書く
#      — cwd 配下（.git 配下を除く）をファイル名で走査し、名前に「基本設計書」
#        を含む文書を探す。見つかった場合、中身に業務の判定表（条件・結果の
#        見出しを持つ表）が無ければ違反とする
#
# （「規則に名前を付けて参照する」のうち「その名前がコード中の識別子として
#   使われているかを走査する」という後半部分は、設計書とコードの対応する
#   ファイルを機械的に特定する手段が無いため実装せず、判定表の名前の列の
#   有無の検査のみに留めた。既知の限界として明記する）
#
# 判定の設計:
#   例外の列の検査は、対象プロジェクトごとに業務規則を記述するファイルの
#   名前や配置は異なるため、ファイルパスではなく「本文の内容が条件と結果の
#   対応を示す判定表という構造を持つかどうか」で走査対象を特定する（既存の
#   設計を維持）。名前の列の検査も同じ判定表を対象に、見出し行へ「名前」の
#   列があるかを機械的に判定する。
#   判定を1箇所に集める検査は、書き込み対象ファイルの if 文の条件式のうち
#   比較演算子と論理演算子（&&・||）を combine した「複雑な条件式」を抽出し、
#   git grep（--untracked を含む）でリポジトリ内の他のファイルに同一の
#   文字列が無いかを走査する。単純な条件（`if (x)` 等）は対象外とすることで
#   誤検知を抑える。
#   判定を表示の層に置かない検査は、ファイルパスや拡張子から表示を組み立てる
#   層らしいファイルを特定し、同じ「複雑な条件式」の抽出結果が1件でもあれば
#   違反とする。
#   判定を表で書くは検査列が「基本設計書に業務の判定を示す表が実在するか
#   を走査する」であり、書き込み対象ファイルの本文ではなく別文書の存在
#   確認を求めるため、ファイル名で対象文書を探す方式を取る
#   （check-doc-heading-addendum.sh と同じ考え方）。文書が無い場合を違反として
#   block すると「まだ書いていないだけ」を止めてしまうため、見つからない
#   場合は対象外として素通しし、見つかった場合にのみ中身を検査する。
#
# 対象ファイル:
#   例外・名前の列の検査は Markdown（.md）に限定する。
#   判定を1箇所に集める検査・判定を表示の層に置かない検査は、コードファイル
#   らしい拡張子（.js/.jsx/.ts/.tsx/.py/.java/.go/.rb/.php/.cs/.kt/.swift）に
#   限定する。
#   判定を表で書くは cwd 配下でファイル名に「基本設計書」を含む最初の
#   ファイルを対象文書とし、書き込み対象ファイルの拡張子に依存しない。
#
# 除外条件（誤検知回避）:
#   - tool_name が Write 以外 → 対象外（Edit は差分のみで全文を持たないため対象外）
#   - file_path の拡張子が .md でもコードファイル一覧でもない → 対象外
#   - 本文に判定表（見出し行に「条件」と「結果」を含む表）が無い → 対象外
#     （業務規則の判定表ではない文書に規則を適用しない）
#   - if 文の条件式に比較演算子と論理演算子の両方が無い → 対象外（単純な
#     条件は判定を1箇所に集める検査・判定を表示の層に置かない検査の対象外）
#   - 書き込み先ディレクトリが git リポジトリでない → 判定を1箇所に集める
#     検査は判定不能として素通し（fail-open）
#   - ファイルパスが表示を組み立てる層らしい拡張子・ディレクトリ名のいずれ
#     にも一致しない → 判定を表示の層に置かない検査は対象外
#   - 判定を表で書く: cwd が空・存在しない → 対象外（fail-open）。
#     「基本設計書」を含む文書が見当たらない → 対象外（見つかった場合のみ
#     中身を検査する）
#
# 既知の限界:
#   - 見出し行の列名一致でしか判定できない。実質的に例外・名前を別表・別節へ
#     書いていても、その語を見出しに使っていない場合は誤検知しうる
#   - 「規則に名前を付けて参照する」は、名前の列の値が実際にコード識別子
#     として使われているかまでは検査しない
#   - 判定を1箇所に集める検査は、条件式の文字列が完全に一致する場合のみ
#     検出する。表現が異なるが同じ業務判定を行う条件は検出できない
#   - 判定を表示の層に置かない検査は、ディレクトリ名・拡張子による表示層の
#     推定であり、実際の層構造とは一致しないことがある
#   - 判定を表で書く: ファイル名に「基本設計書」を含む最初の1件のみを見る。
#     条件・結果の見出しを持つ表の有無という近似判定であり、表の各行の
#     妥当性までは検証しない
#
# 止めるか知らせるか:
#   例外と境界を明示する: 止める（例外の欄を欠いた判定表がそのまま確定すると、境界条件の欠落が履歴に残り事後に気付けなくなるため）
#   判定を1箇所に集める: 止める（同じ判定条件が複数箇所に複製されたままコミットされると、片方だけ直る不整合が履歴に固定されるため）
#   規則に名前を付けて参照する: 止める（名前の欄を欠いた判定表が確定すると、規則の参照先を後から復元できなくなるため）
#   判定を表示の層に置かない: 止める（表示の層に紛れ込んだ業務判定がそのまま確定すると、誤った層構造が履歴に固定され事後の是正コストが増すため）
#   判定を表で書く: 止める（判定表を欠いた基本設計書が確定すると、業務判定の根拠を後から復元できなくなるため）
#
# 逃げ道:
#   BUSINESS_RULE_TABLE_MISSING_EXCEPTION_SKIP_REASON に理由を書けば通る。理由が空の場合は通らない
#
# 使い方:
#   フック本体として: PreToolUse(Write) の入力 JSON を stdin から受け取る
#   単体実行: check-business-rule-table-missing-exception.sh --self-test
set -uo pipefail
export LC_ALL=C

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

is_code_ext() {
  case "$1" in
    *.js|*.jsx|*.ts|*.tsx|*.py|*.java|*.go|*.rb|*.php|*.cs|*.kt|*.swift) return 0 ;;
    *) return 1 ;;
  esac
}

is_presentation_layer() {
  local file_path="$1"
  case "$file_path" in
    *.jsx|*.tsx|*.vue|*.erb) return 0 ;;
  esac
  printf '%s' "$file_path" | grep -qiE '/(components?|views?|pages?|templates?)/' 2>/dev/null
}

# 比較演算子と論理演算子を combine した複雑な if 条件式を1行1件で列挙する
extract_complex_conditions() {
  local content="$1"
  printf '%s\n' "$content" \
    | grep -oE 'if[[:space:]]*\([^()]*\)' 2>/dev/null \
    | sed -E 's/^if[[:space:]]*\(//; s/\)[[:space:]]*$//' \
    | while IFS= read -r cond; do
        if printf '%s' "$cond" | grep -qE '(&&|\|\|)' 2>/dev/null \
          && printf '%s' "$cond" | grep -qE '(==|===|!=|!==|>=|<=|>|<)' 2>/dev/null; then
          printf '%s\n' "$cond"
        fi
      done | sort -u
}

# $1: file_path。git リポジトリのルートを返す（判定不能なら空を返す）
resolve_repo_root() {
  local file_path="$1" dir
  dir="$(dirname "$file_path")"
  [ -d "$dir" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

judge() {
  # $1: file_path, $2: content, $3: cwd（省略可。省略時は「判定を表で書く」を対象外として扱う）
  local file_path="$1" content="$2" cwd="${3:-}"

  # 規則: 判定を表で書く（書き込み対象ファイルの拡張子に依存しない）
  local basic_design_doc
  basic_design_doc="$(find_doc_by_name "$cwd" "$BASIC_DESIGN_DOC_NEEDLE")"
  if [ -n "$basic_design_doc" ]; then
    local doc_body relpath doc_header_hit
    doc_body="$(cat "$basic_design_doc" 2>/dev/null)"
    relpath="${basic_design_doc#"$cwd"/}"
    doc_header_hit=$(printf '%s\n' "$doc_body" | grep -E '^\|' 2>/dev/null | grep -E '条件' 2>/dev/null | grep -E '結果' 2>/dev/null | head -1)
    if [ -z "$doc_header_hit" ]; then
      echo "拒否[判定を表で書く]: 基本設計書（${relpath}）は実在するが、業務の判定を示す表（条件と結果の対応）が見当たりません"
      return 2
    fi
  fi

  if is_code_ext "$file_path"; then
    local conds cond
    conds="$(extract_complex_conditions "$content")"

    if [ -n "$conds" ] && is_presentation_layer "$file_path"; then
      echo "拒否[判定を表示の層に置かない]: 表示を組み立てる層に複雑な条件式があります（$(printf '%s' "$conds" | head -1)）"
      return 2
    fi

    if [ -n "$conds" ]; then
      local repo_root
      repo_root="$(resolve_repo_root "$file_path")"
      if [ -n "$repo_root" ]; then
        local rel_path hit
        rel_path="${file_path#"$repo_root"/}"
        while IFS= read -r cond; do
          [ -z "$cond" ] && continue
          hit=$(git -C "$repo_root" grep -F -l --untracked -e "$cond" -- . 2>/dev/null | grep -vF -- "$rel_path" | head -1)
          if [ -n "$hit" ]; then
            echo "拒否[判定を1箇所に集める]: 同一の条件式が他のファイルにも現れています（${hit}: ${cond}）"
            return 2
          fi
        done <<EOF
$conds
EOF
      fi
    fi

    echo "許可[判定を表示の層に置かない]: 表示を組み立てる層に複雑な条件式は見当たりません"
    echo "許可[判定を1箇所に集める]: 他ファイルと重複する条件式は見当たりません"
    return 0
  fi

  case "$file_path" in
    *.md) ;;
    *)
      echo "対象外[例外と境界を明示する]: Markdown ファイル、またはコードファイルのいずれでもありません（${file_path}）"
      echo "対象外[規則に名前を付けて参照する]: Markdown ファイル、またはコードファイルのいずれでもありません（${file_path}）"
      return 0
      ;;
  esac

  local header_hit
  header_hit=$(printf '%s\n' "$content" | grep -E '^\|' 2>/dev/null | grep -E '条件' 2>/dev/null | grep -E '結果' 2>/dev/null | head -1)

  if [ -z "$header_hit" ]; then
    echo "対象外[例外と境界を明示する]: 業務の判定表（条件・結果の見出しを持つ表）が見当たりません"
    echo "対象外[規則に名前を付けて参照する]: 業務の判定表（条件・結果の見出しを持つ表）が見当たりません"
    return 0
  fi

  local missing=()
  printf '%s' "$header_hit" | grep -qE '例外' 2>/dev/null || missing+=("拒否[例外と境界を明示する]: 例外の欄が見当たりません（${header_hit}）")
  printf '%s' "$header_hit" | grep -qE '名前' 2>/dev/null || missing+=("拒否[規則に名前を付けて参照する]: 名前の欄が見当たりません（${header_hit}）")

  if [ "${#missing[@]}" -gt 0 ]; then
    printf '%s\n' "${missing[@]}"
    return 2
  fi

  echo "許可[例外と境界を明示する]: 判定表の見出しに「例外」の列があります"
  echo "許可[規則に名前を付けて参照する]: 判定表の見出しに「名前」の列があります"
  return 0
}

# 理由を書いた場合だけ通す口。理由が空なら通さない
should_skip_with_reason() {
  # 標準出力: skip の記録。戻り値: 0=skip する・1=skip しない
  if [ -n "${BUSINESS_RULE_TABLE_MISSING_EXCEPTION_SKIP_REASON:-}" ]; then
    echo "[BUSINESS-RULE-TABLE-MISSING-EXCEPTION-SKIP] 理由: ${BUSINESS_RULE_TABLE_MISSING_EXCEPTION_SKIP_REASON}"
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

  ctx="[BUSINESS-RULE-TABLE-MISSING-EXCEPTION-BLOCK] ${msg}。指摘された欄の追加、条件式の重複解消、または表示の層からの判定の除去を行ってから再実行してください。"
  jq -n --arg ctx "$ctx" '{"systemMessage":$ctx,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  printf '%s\n' "$ctx" >&2
  exit 2
}

self_test() {
  local rc=0 msg code

  # 系1: 条件・結果の判定表があり「例外」列が無い → 拒否
  local c1='# 業務規則

| 条件 | 結果 |
|---|---|
| 在庫が0 | 注文を受け付けない |
'
  if msg="$(judge "docs/業務規則.md" "$c1")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: 例外列の無い判定表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: 例外列が無いのに許可された（exit=${code}）" >&2
    rc=1
  fi

  # 系2: 条件・結果・例外・名前の判定表がある → 許可
  local c2='# 業務規則

| 名前 | 条件 | 結果 | 例外 |
|---|---|---|---|
| 在庫切れ判定 | 在庫が0 | 注文を受け付けない | 予約商品は受け付ける |
'
  if msg="$(judge "docs/業務規則.md" "$c2")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: 例外列・名前列のある判定表は許可される（${msg}）"
  else
    echo "  [FAIL] 系2: 例外列・名前列があるのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系3（近傍事例）: 「条件」はあるが「結果」列を持たない表（判定表ではない）→ 対象外として許可
  local c3='# 画面一覧

| 条件 | 処理 |
|---|---|
| 未ログイン | ログイン画面へ遷移 |
'
  if msg="$(judge "docs/画面一覧.md" "$c3")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系3: 結果列を持たない表は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系3: 判定表ではないのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系4: Markdown ファイルではない → 対象外として許可
  local c4='| 条件 | 結果 |
|---|---|
| 在庫が0 | 注文を受け付けない |'
  if msg="$(judge "src/table.txt" "$c4")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: Markdown 以外は対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系4: Markdown 以外なのに拒否された（exit=${code}）" >&2
    rc=1
  fi

  # 系5: 条件・結果・例外の判定表はあるが「名前」列が無い → 拒否（規則に名前を付けて参照する）
  local c5='# 業務規則

| 条件 | 結果 | 例外 |
|---|---|---|
| 在庫が0 | 注文を受け付けない | 予約商品は受け付ける |
'
  if msg="$(judge "docs/業務規則.md" "$c5")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '規則に名前を付けて参照する'; then
    echo "  [PASS] 系5: 名前列の無い判定表は拒否される（${msg}）"
  else
    echo "  [FAIL] 系5: 名前列が無いのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系6: 同一の複雑な条件式が他のファイルにも現れる → 拒否（判定を1箇所に集める）
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-business-rule-table-missing-exception-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  printf 'function isEligible(order) {\n  if (order.amount >= 10000 && order.status === "active") {\n    return true;\n  }\n}\n' > "$tmp/other.js"
  local c6='function checkOrder(order) {
  if (order.amount >= 10000 && order.status === "active") {
    return true;
  }
}'
  if msg="$(judge "$tmp/target.js" "$c6")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '判定を1箇所に集める'; then
    echo "  [PASS] 系6: 他ファイルと重複する複雑な条件式は拒否される（${msg}）"
  else
    echo "  [FAIL] 系6: 重複条件式があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系7: 複雑な条件式だが他のファイルに重複が無い → 許可
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-business-rule-table-missing-exception-self-test.XXXXXX")"
  ( cd "$tmp" && git init -q 2>/dev/null )
  printf 'export const z = 1;\n' > "$tmp/other.js"
  local c7='function checkOrder(order) {
  if (order.amount >= 10000 && order.status === "active") {
    return true;
  }
}'
  if msg="$(judge "$tmp/target.js" "$c7")"; then code=0; else code=$?; fi
  rm -rf "$tmp"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系7: 他ファイルに重複が無い複雑な条件式は許可される（${msg}）"
  else
    echo "  [FAIL] 系7: 重複が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系8: 表示を組み立てる層（components配下）に複雑な条件式がある → 拒否（判定を表示の層に置かない）
  local c8='function render(order) {
  if (order.amount >= 10000 && order.status === "active") {
    return renderEligible();
  }
}'
  if msg="$(judge "src/components/OrderCard.tsx" "$c8")"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '判定を表示の層に置かない'; then
    echo "  [PASS] 系8: 表示層の複雑な条件式は拒否される（${msg}）"
  else
    echo "  [FAIL] 系8: 表示層に複雑な条件式があるのに許可、または規則名が含まれない（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系9（近傍事例）: 表示の層らしくないファイルの同じ複雑な条件式 → 許可（判定を表示の層に置かない検査は対象外）
  local c9='function isEligible(order) {
  if (order.amount >= 10000 && order.status === "active") {
    return true;
  }
}'
  if msg="$(judge "src/services/orderService.js" "$c9")"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系9: 表示の層ではないファイルの複雑な条件式は表示層検査の対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系9: 表示層ではないのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系10: 基本設計書らしき文書が cwd に無い → 対象外として許可（判定を表で書く）
  local tmp10
  tmp10="$(mktemp -d "${TMPDIR:-/tmp}/check-business-rule-table-missing-exception-self-test.XXXXXX")"
  mkdir -p "$tmp10/docs"
  printf '# メモ\n' > "$tmp10/docs/メモ.md"
  if msg="$(judge "docs/note.md" '' "$tmp10")"; then code=0; else code=$?; fi
  rm -rf "$tmp10"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系10: 基本設計書が見当たらなければ対象外として許可される（${msg}）"
  else
    echo "  [FAIL] 系10: 基本設計書が無いのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系11: 基本設計書は実在するが業務の判定表（条件・結果）が無い → 拒否（判定を表で書く）
  local tmp11
  tmp11="$(mktemp -d "${TMPDIR:-/tmp}/check-business-rule-table-missing-exception-self-test.XXXXXX")"
  mkdir -p "$tmp11/docs"
  printf '# 注文機能基本設計書\n\n## 外部仕様\n画面の項目を定める。\n' > "$tmp11/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp11")"; then code=0; else code=$?; fi
  rm -rf "$tmp11"
  if [ "$code" -eq 2 ] && printf '%s' "$msg" | grep -qF '判定を表で書く'; then
    echo "  [PASS] 系11: 業務の判定表が無い基本設計書は拒否される（${msg}）"
  else
    echo "  [FAIL] 系11: 業務の判定表が無いのに許可、または規則名不一致（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系12: 基本設計書に業務の判定表（条件・結果）がある → 許可
  local tmp12
  tmp12="$(mktemp -d "${TMPDIR:-/tmp}/check-business-rule-table-missing-exception-self-test.XXXXXX")"
  mkdir -p "$tmp12/docs"
  printf '# 注文機能基本設計書\n\n## 業務仕様の確定\n| 条件 | 結果 |\n|---|---|\n| 在庫が0 | 注文を受け付けない |\n' > "$tmp12/docs/注文機能基本設計書.md"
  if msg="$(judge "docs/note.md" '' "$tmp12")"; then code=0; else code=$?; fi
  rm -rf "$tmp12"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系12: 業務の判定表がある基本設計書は許可される（${msg}）"
  else
    echo "  [FAIL] 系12: 業務の判定表があるのに拒否された（exit=${code}, ${msg}）" >&2
    rc=1
  fi

  # 系13: 環境変数に理由を設定すると should_skip_with_reason は skip する
  local skip_out skip_code
  if skip_out="$(BUSINESS_RULE_TABLE_MISSING_EXCEPTION_SKIP_REASON="テスト理由" should_skip_with_reason)"; then skip_code=0; else skip_code=$?; fi
  if [ "$skip_code" -eq 0 ] && printf '%s' "$skip_out" | grep -qF 'BUSINESS-RULE-TABLE-MISSING-EXCEPTION-SKIP' && printf '%s' "$skip_out" | grep -qF 'テスト理由'; then
    echo "  [PASS] 系13: 理由を設定すると should_skip_with_reason は skip する（${skip_out}）"
  else
    echo "  [FAIL] 系13: 理由があるのに skip しない、またはタグ・理由が含まれない（exit=${skip_code}, ${skip_out}）" >&2
    rc=1
  fi

  # 系14: 環境変数を空文字にすると should_skip_with_reason は skip しない
  local skip_code2
  if BUSINESS_RULE_TABLE_MISSING_EXCEPTION_SKIP_REASON="" should_skip_with_reason >/dev/null 2>&1; then skip_code2=0; else skip_code2=$?; fi
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
  *) run_hook ;;
esac
