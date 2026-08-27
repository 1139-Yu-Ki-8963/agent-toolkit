#!/usr/bin/env bash
set -uo pipefail

# validate-rule-judgment-coverage.sh — 規約の「規則の数」と検査の「判定の数」の対応を測る
#
# 出典: docs/tasks/検査を規則と対応させる指示書.md（3.1節・3.6節）
#
# 目的:
#   delivery-payload/templates/rules/tool-defined/ 配下の規約 .md それぞれについて、
#   「## 規則」の表が持つ規則の数と、対応する検査スクリプト
#   （delivery-payload/references/rule-taxonomy.json の checker から引く）が
#   出す判定の数を数え、両者が一致しているかを規約ごとに報告する。
#
# 数え方:
#   規則の数   — 「## 規則」の表（見出し行・区切り行を除く）の行のうち、
#                検査列（第4列）が「不可:」または「判定不能:」で始まらないもの。
#                「## このプロジェクトの規則」の表は対象プロジェクトのリバース
#                解析が起こすものであり、配る側の規則ではないため数えない。
#   判定の数   — 対応する検査スクリプトの中で
#                拒否[<規則名>] / 通知[<規則名>] / 許可[<規則名>] / 対象外[<規則名>]
#                のいずれかの形で規則名を出している箇所の異なり数。
#                指示書3.1節は拒否・通知・許可の3つを挙げるが、実装には
#                素通しの理由を示す「対象外」の形も使われている。規則へ
#                判定が対応しているかを数える目的に対して動詞の別は関係
#                しないため、4つとも数える（指示書との既知の差）。
#   規約と検査の対応 — rule-taxonomy.json の parents[].children[].checker から
#                引く。値が null または空の規約は「検査なし」として扱う。
#   比較は日本語を含むため LC_ALL=C sort -u を使う。素の sort -u は日本語の
#   文字列を誤って重複扱いすることが確認されている。
#
# 判定の5状態:
#   一致       規則の数と判定の数が等しい
#   不足       判定の数が規則の数より少ない
#   過剰       判定の数が規則の数より多い
#   検査なし    対応する検査スクリプトが無い（checkerがnullまたは空）
#   名前の不一致 検査が出す規則名のうち、規約の表（「## 規則」の全行。
#                不可の行を含む）に無いものがある。この状態は件数の一致・
#                不一致より優先して報告する（誤字を捕まえる目的のため）
#
# 終了コード:
#   0 = すべての規約が「一致」
#   1 = 1件以上「不足」「過剰」「名前の不一致」がある、または「検査なし」
#       だけが該当する場合も1とする（その旨を出力へ書く）
#
# 既知の限界:
#   - 検査列が 判定不能: で始まる規則は、機械による判定ができないと
#     宣言されたものとして規則の数から除く。不可: も同じ扱いとする
#   - 「対象外」を数えることは指示書3.1節が挙げる拒否・通知・許可の3つとは
#     異なる（上記「数え方」に既知の差として明記済み）
#   - 規則名の一致は「## 規則」の表の第1列（規則名）との完全一致でしか見ない。
#     表記の揺れ（全角半角・空白の位置違い等）は同一の規則として扱えず、
#     偽の「名前の不一致」として報告されうる
#   - 判定の数の走査はファイル全体を対象とし、コメントと実際の出力を
#     区別しない。ヘッダコメントに角括弧付きの規則名やプレースホルダを
#     書くと、それも判定として数えられ、規約の表に無い名前であれば
#     「名前の不一致」として報告される
#
# 使い方:
#   validate-rule-judgment-coverage.sh              全規約を測って報告する
#   validate-rule-judgment-coverage.sh --self-test   自己テストを走らせる
#
# 保守責任者: 人手（ユーザー）。数え方（動詞の種類・不可の扱い）を変える場合は
#   本スクリプトと docs/tasks/検査を規則と対応させる指示書.md と
#   .claude/rules/scoped/portal/page-conventions/rule.md の該当節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

# macOS標準awkは多バイト文字列の "==" 比較に既知の不具合があり、日本語の
# 規則名を取り違える（compare-with-previous.sh の設計判断と同種の事象を実測で確認済み）。
# LC_ALL=C を明示することで回避する。
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

TAXONOMY_JSON="${REPO_ROOT}/delivery-payload/references/rule-taxonomy.json"
TOOLDEFINED_DIR="${REPO_ROOT}/delivery-payload/templates/rules/tool-defined"
CHECKERS_DIR="${REPO_ROOT}/delivery-payload/templates/rules/checkers"

# ---------------------------------------------------------------------------
# 抽出関数
# ---------------------------------------------------------------------------

# $1: rule.md のパス
# 「## 規則」の表（見出し行・区切り行を除く）の各行を "<規則名><TAB><検査列>" で出力する。
# 「## このプロジェクトの規則」以降は含めない。
extract_rule_rows() {
  local file="$1"
  awk -F'|' '
    /^## 規則[ \t]*$/ { insec=1; next }
    /^## / { if (insec == 1) exit }
    insec == 1 && /^\|/ {
      line = $0
      if (line ~ /^\|[-: ]+\|[-: ]+\|/) next
      name = $2; gsub(/^[ \t]+|[ \t]+$/, "", name)
      check = $5; gsub(/^[ \t]+|[ \t]+$/, "", check)
      if (name == "規則") next
      print name "\t" check
    }
  ' "$file" 2>/dev/null
}

# $1: rule.md のパス → 検査列が「不可:」または「判定不能:」で始まらない行数
count_rules() {
  extract_rule_rows "$1" | awk -F'\t' '$2 !~ /^不可:/ && $2 !~ /^判定不能:/' | wc -l | tr -d ' '
}

# $1: rule.md のパス → 「## 規則」の表の全行（不可を含む）の規則名一覧（重複あり）
rule_names_all() {
  extract_rule_rows "$1" | cut -f1
}

# $1: 検査スクリプトのパス → 拒否[...]/通知[...]/許可[...]/対象外[...] の
# 括弧内の規則名一覧（重複あり）
extract_judgment_names() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -oE '(拒否|通知|許可|対象外)\[[^]]*\]' "$file" 2>/dev/null \
    | sed -E 's/^(拒否|通知|許可|対象外)\[(.*)\]$/\2/'
}

# $1: 検査スクリプトのパス → 判定の数（異なり数）
count_judgments() {
  local file="$1"
  [ -f "$file" ] || { printf '0'; return 0; }
  extract_judgment_names "$file" | LC_ALL=C sort -u | grep -c .
}

# $1: rule.md のパス、$2: 検査スクリプトのパス
# → 検査が出す規則名のうち規約の表に無いもの（1行1件・異なり）
mismatch_names() {
  local rule_md="$1" checker_sh="$2"
  local rule_names_file judgment_names_file
  if ! rule_names_file="$(mktemp "${TMPDIR:-/tmp}/vrjc-rule-names.XXXXXX" 2>/dev/null)" || [ -z "$rule_names_file" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  if ! judgment_names_file="$(mktemp "${TMPDIR:-/tmp}/vrjc-judgment-names.XXXXXX" 2>/dev/null)" || [ -z "$judgment_names_file" ]; then
    echo "[UNKNOWN] 一時ファイルの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  rule_names_all "$rule_md" | LC_ALL=C sort -u > "$rule_names_file"
  extract_judgment_names "$checker_sh" | LC_ALL=C sort -u > "$judgment_names_file"
  LC_ALL=C comm -23 "$judgment_names_file" "$rule_names_file" 2>/dev/null
  rm -f "$rule_names_file" "$judgment_names_file"
}

# ---------------------------------------------------------------------------
# 1規約分の評価
# ---------------------------------------------------------------------------

# $1: rule.md のパス、$2: 検査スクリプトのパス（無い場合は空文字）
# → "<規則の数>\t<判定の数>\t<状態>" を1行出力する
evaluate_regulation() {
  local rule_md="$1" checker_sh="${2:-}"
  local rule_count judgment_count mismatch_count state

  rule_count="$(count_rules "$rule_md")"

  if [ -z "$checker_sh" ] || [ ! -f "$checker_sh" ]; then
    printf '%s\t0\t検査なし\n' "$rule_count"
    return 0
  fi

  judgment_count="$(count_judgments "$checker_sh")"
  mismatch_count="$(mismatch_names "$rule_md" "$checker_sh" | grep -c .)"

  if [ "$mismatch_count" -gt 0 ]; then
    state="名前の不一致"
  elif [ "$rule_count" -eq "$judgment_count" ]; then
    state="一致"
  elif [ "$judgment_count" -lt "$rule_count" ]; then
    state="不足"
  else
    state="過剰"
  fi

  printf '%s\t%s\t%s\n' "$rule_count" "$judgment_count" "$state"
}

# ---------------------------------------------------------------------------
# taxonomy 参照
# ---------------------------------------------------------------------------

# $1: key（.md のベース名） → title（無ければ key そのもの）
title_for_key() {
  local key="$1" title
  title="$(jq -r --arg k "$key" '.parents[]?.children[]? | select(.key == $k) | (.title // empty)' "$TAXONOMY_JSON" 2>/dev/null | head -1)"
  [ -z "$title" ] && title="$key"
  printf '%s' "$title"
}

# $1: key（.md のベース名） → checker のファイル名（無ければ空）
checker_for_key() {
  local key="$1"
  jq -r --arg k "$key" '.parents[]?.children[]? | select(.key == $k) | (.checker // "")' "$TAXONOMY_JSON" 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# 本番実行
# ---------------------------------------------------------------------------

main_report() {
  local match=0 lack=0 excess=0 none=0 mismatch=0
  local mismatch_details=""

  echo "| 規約 | 規則の数 | 判定の数 | 状態 |"
  echo "|---|---|---|---|"

  local f
  for f in "$TOOLDEFINED_DIR"/*.md; do
    [ -f "$f" ] || continue
    local key title checker checker_path result rc jc state bad
    key="$(basename "$f" .md)"
    title="$(title_for_key "$key")"
    checker="$(checker_for_key "$key")"
    checker_path=""
    [ -n "$checker" ] && checker_path="${CHECKERS_DIR}/${checker}"

    result="$(evaluate_regulation "$f" "$checker_path")"
    rc="$(printf '%s' "$result" | cut -f1)"
    jc="$(printf '%s' "$result" | cut -f2)"
    state="$(printf '%s' "$result" | cut -f3)"

    echo "| ${title} | ${rc} | ${jc} | ${state} |"

    case "$state" in
      一致) match=$((match + 1)) ;;
      不足) lack=$((lack + 1)) ;;
      過剰) excess=$((excess + 1)) ;;
      検査なし) none=$((none + 1)) ;;
      名前の不一致)
        mismatch=$((mismatch + 1))
        while IFS= read -r bad; do
          [ -z "$bad" ] && continue
          mismatch_details="${mismatch_details}- ${title}: ${bad}
"
        done < <(mismatch_names "$f" "$checker_path")
        ;;
    esac
  done

  echo ""
  echo "一致: ${match} 件"
  echo "不足: ${lack} 件"
  echo "過剰: ${excess} 件"
  echo "検査なし: ${none} 件"
  echo "名前の不一致: ${mismatch} 件"

  if [ -n "$mismatch_details" ]; then
    echo ""
    echo "名前の不一致の詳細（規約の表に無い名前）:"
    printf '%s' "$mismatch_details"
  fi

  if [ "$none" -gt 0 ]; then
    echo ""
    echo "検査なしの規約が ${none} 件あります。対応する検査スクリプトが無いため終了コード1とします。"
  fi

  if [ "$lack" -gt 0 ] || [ "$excess" -gt 0 ] || [ "$mismatch" -gt 0 ] || [ "$none" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------

# $1: ケース名、$2: rule.md、$3: 検査スクリプト（無ければ空文字）
# $4: 期待する規則の数、$5: 期待する判定の数、$6: 期待する状態
assert_case() {
  local label="$1" rule_md="$2" checker_sh="$3" exp_rc="$4" exp_jc="$5" exp_state="$6"
  local result rc jc state
  result="$(evaluate_regulation "$rule_md" "$checker_sh")"
  rc="$(printf '%s' "$result" | cut -f1)"
  jc="$(printf '%s' "$result" | cut -f2)"
  state="$(printf '%s' "$result" | cut -f3)"
  if [ "$rc" = "$exp_rc" ] && [ "$jc" = "$exp_jc" ] && [ "$state" = "$exp_state" ]; then
    echo "  [PASS] ${label}: 規則${rc}件・判定${jc}件 → ${state}"
    return 0
  else
    echo "  [FAIL] ${label}: 期待 規則${exp_rc}件/判定${exp_jc}件/${exp_state} 実際 規則${rc}件/判定${jc}件/${state}" >&2
    return 1
  fi
}

self_test() {
  local rc=0
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate-rule-judgment-coverage-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  # ケース1: 規則3件・判定3件 → 一致
  cat > "$tmp/case1-rule.md" <<'EOF'
# 規約例1

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則A | 内容A | 根拠A | 静的解析: 検査A |
| 規則B | 内容B | 根拠B | 静的解析: 検査B |
| 規則C | 内容C | 根拠C | 静的解析: 検査C |
EOF
  cat > "$tmp/case1-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則A]: だめ"
echo "許可[規則B]: よい"
echo "通知[規則C]: 知らせる"
EOF
  assert_case "ケース1" "$tmp/case1-rule.md" "$tmp/case1-checker.sh" 3 3 一致 || rc=1

  # ケース2: 規則3件・判定2件 → 不足
  cat > "$tmp/case2-rule.md" <<'EOF'
# 規約例2

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則A | 内容A | 根拠A | 静的解析: 検査A |
| 規則B | 内容B | 根拠B | 静的解析: 検査B |
| 規則C | 内容C | 根拠C | 静的解析: 検査C |
EOF
  cat > "$tmp/case2-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則A]: だめ"
echo "許可[規則B]: よい"
EOF
  assert_case "ケース2" "$tmp/case2-rule.md" "$tmp/case2-checker.sh" 3 2 不足 || rc=1

  # ケース3: 規則3件・判定4件 → 過剰
  # 規則Dは検査列が「不可:」で始まるため規則の数には数えないが、
  # 規約の表には実在する名前のため、検査が誤ってDも判定してしまった状況を模す。
  cat > "$tmp/case3-rule.md" <<'EOF'
# 規約例3

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則A | 内容A | 根拠A | 静的解析: 検査A |
| 規則B | 内容B | 根拠B | 静的解析: 検査B |
| 規則C | 内容C | 根拠C | 静的解析: 検査C |
| 規則D | 内容D | 根拠D | 不可: 判定できない |
EOF
  cat > "$tmp/case3-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則A]: だめ"
echo "許可[規則B]: よい"
echo "通知[規則C]: 知らせる"
echo "対象外[規則D]: 対象外"
EOF
  assert_case "ケース3" "$tmp/case3-rule.md" "$tmp/case3-checker.sh" 3 4 過剰 || rc=1

  # ケース4: 検査列が「不可:」で始まる規則を1件含む（規則3件のうち1件が不可）・判定2件 → 一致
  cat > "$tmp/case4-rule.md" <<'EOF'
# 規約例4

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則X | 内容X | 根拠X | 静的解析: 検査X |
| 規則Y | 内容Y | 根拠Y | 静的解析: 検査Y |
| 規則Z | 内容Z | 根拠Z | 不可: 判定できない |
EOF
  cat > "$tmp/case4-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則X]: だめ"
echo "許可[規則Y]: よい"
EOF
  assert_case "ケース4" "$tmp/case4-rule.md" "$tmp/case4-checker.sh" 2 2 一致 || rc=1

  # ケース5: 「## このプロジェクトの規則」の表に行がある・判定は「## 規則」の分だけ → 一致
  cat > "$tmp/case5-rule.md" <<'EOF'
# 規約例5

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則P | 内容P | 根拠P | 静的解析: 検査P |
| 規則Q | 内容Q | 根拠Q | 静的解析: 検査Q |

## このプロジェクトの規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則R | 内容R | 根拠R | 静的解析: 検査R |
| 規則S | 内容S | 根拠S | 静的解析: 検査S |
| 規則T | 内容T | 根拠T | 静的解析: 検査T |
EOF
  cat > "$tmp/case5-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則P]: だめ"
echo "許可[規則Q]: よい"
EOF
  assert_case "ケース5" "$tmp/case5-rule.md" "$tmp/case5-checker.sh" 2 2 一致 || rc=1

  # ケース6: 検査が規約の表に無い名前を出している → 名前の不一致
  cat > "$tmp/case6-rule.md" <<'EOF'
# 規約例6

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則M | 内容M | 根拠M | 静的解析: 検査M |
| 規則N | 内容N | 根拠N | 静的解析: 検査N |
EOF
  cat > "$tmp/case6-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則M]: だめ"
echo "許可[規則N]: よい"
echo "拒否[規則ゼロ]: 表に無い名前"
EOF
  assert_case "ケース6" "$tmp/case6-rule.md" "$tmp/case6-checker.sh" 2 3 名前の不一致 || rc=1

  # ケース7: checkerがnull（検査スクリプトが無い） → 検査なし
  cat > "$tmp/case7-rule.md" <<'EOF'
# 規約例7

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則K | 内容K | 根拠K | 静的解析: 検査K |
| 規則L | 内容L | 根拠L | 静的解析: 検査L |
EOF
  assert_case "ケース7" "$tmp/case7-rule.md" "" 2 0 検査なし || rc=1

  # ケース8: 同じ規則名を2箇所で出している（拒否[X]と許可[X]）→ 判定1件として数える（異なり数）
  cat > "$tmp/case8-rule.md" <<'EOF'
# 規約例8

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則X | 内容X | 根拠X | 静的解析: 検査X |
EOF
  cat > "$tmp/case8-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則X]: だめな場合"
echo "許可[規則X]: よい場合"
EOF
  assert_case "ケース8" "$tmp/case8-rule.md" "$tmp/case8-checker.sh" 1 1 一致 || rc=1

  # ケース9: 検査列が「判定不能:」で始まる規則を1件含む（規則3件のうち1件が判定不能）・判定2件 → 一致
  cat > "$tmp/case9-rule.md" <<'EOF'
# 規約例9

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 規則J | 内容J | 根拠J | 静的解析: 検査J |
| 規則K | 内容K | 根拠K | 静的解析: 検査K |
| 規則L | 内容L | 根拠L | 判定不能: 判定できない |
EOF
  cat > "$tmp/case9-checker.sh" <<'EOF'
#!/usr/bin/env bash
echo "拒否[規則J]: だめ"
echo "許可[規則K]: よい"
EOF
  assert_case "ケース9" "$tmp/case9-rule.md" "$tmp/case9-checker.sh" 2 2 一致 || rc=1

  rm -rf "$tmp"

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  *) main_report; exit $? ;;
esac
