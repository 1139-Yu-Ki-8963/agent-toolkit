#!/usr/bin/env bash
# check-delivery-glossary.sh — 配布文書が使う言葉に説明が付いているかを検査する
#
# 何を見るか:
#   delivery-payload/references/配布文書の言葉.json の宣言（terms・glossaryDocument・
#   glossaryHeading・referringDocuments）を読み、次の4点を検査する。
#     1. glossaryDocument に glossaryHeading の節が存在する
#     2. terms のすべてが、その節の中に行として現れる
#     3. terms のいずれも、その節より前の行に現れない（説明より先に使われていないこと）。
#        ただし glossaryHeading と同じ見出しレベルの、より前にある見出し節が無い場合
#        （glossaryHeading が文書中で最初の同レベル見出しである場合）、見出しより前の
#        前置き文（タイトル・導入の一文等、見出しの外側にある文章）は対象外とする。
#        前置き文は「節」に属さず、節どうしの前後関係を検査する本項目の対象にならない
#     4. referringDocuments の各文書が、先頭 20 行以内で glossaryDocument と
#        「言葉」の両方に言及している
#
# なぜ要るか:
#   設計判断は .claude/rules/scoped/portal/page-conventions/rule.md の
#   「## 設計判断」内「### check-delivery-glossary.sh」に置く。
#
# 使い方:
#   check-delivery-glossary.sh             このリポジトリを検査する
#   check-delivery-glossary.sh --self-test  判定の妥当性を検査する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DEFS_REL="delivery-payload/references/配布文書の言葉.json"

# scan <base>
#   <base> 配下の $DEFS_REL を読み、4検査を行う。
#   [FAIL] 行を都度出力し、最後に「検査 <N> 件 / 違反 <M> 件」を出す。
#   違反 0 件なら exit 0、1件以上なら exit 1。
scan() {
  local base="$1"
  local defs="$base/$DEFS_REL"
  local total=0 violations=0

  if ! _gt_out1="$(command -v jq 2>&1)"; then
    echo "[FAIL] jq が見つからない"
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    total=$((total + 1)); violations=$((violations + 1))
    echo "検査 $total 件 / 違反 $violations 件"
    return 1
  fi

  if [ ! -f "$defs" ]; then
    echo "[FAIL] 宣言ファイルが存在しない: $DEFS_REL"
    total=$((total + 1)); violations=$((violations + 1))
    echo "検査 $total 件 / 違反 $violations 件"
    return 1
  fi

  local glossary_doc glossary_heading
  glossary_doc="$(jq -r '.glossaryDocument' "$defs")"
  glossary_heading="$(jq -r '.glossaryHeading' "$defs")"

  local terms=()
  while IFS= read -r line; do terms+=("$line"); done < <(jq -r '.terms[]' "$defs")
  local referring=()
  while IFS= read -r line; do referring+=("$line"); done < <(jq -r '.referringDocuments[]' "$defs")

  local doc_path="$base/$glossary_doc"

  # 検査1: glossaryDocument に glossaryHeading の節が存在する
  total=$((total + 1))
  if [ ! -f "$doc_path" ]; then
    echo "[FAIL] glossaryDocument が存在しない: $glossary_doc"
    violations=$((violations + 1))
    echo "検査 $total 件 / 違反 $violations 件"
    return 1
  fi

  local heading_line
  heading_line="$(grep -nxF -- "$glossary_heading" "$doc_path" | head -1 | cut -d: -f1)"
  if [ -z "$heading_line" ]; then
    echo "[FAIL] ${glossary_doc} に見出し「${glossary_heading}」の節が無い"
    violations=$((violations + 1))
    echo "検査 $total 件 / 違反 $violations 件"
    return 1
  fi

  # 見出しレベル（先頭の # の個数）
  local hd_level=0 rest="$glossary_heading"
  while [ "${rest:0:1}" = "#" ]; do
    hd_level=$((hd_level + 1))
    rest="${rest:1}"
  done

  # 節の終端行（次の同level以上の見出し。無ければ EOF+1）
  local section_end
  section_end="$(awk -v start="$heading_line" -v maxlevel="$hd_level" '
    BEGIN { found = 0 }
    NR > start && !found {
      if (match($0, /^#+/)) {
        lvl = RLENGTH
        if (lvl <= maxlevel) { print NR; found = 1 }
      }
    }
    END { if (!found) print NR + 1 }
  ' "$doc_path")"

  local section_text=""
  if [ $((heading_line + 1)) -le $((section_end - 1)) ]; then
    section_text="$(sed -n "$((heading_line + 1)),$((section_end - 1))p" "$doc_path")"
  fi

  # 検査2: terms のすべてが節の中に行として現れる
  local t
  for t in "${terms[@]}"; do
    total=$((total + 1))
    if ! printf '%s\n' "$section_text" | grep -qF -- "$t"; then
      echo "[FAIL] 節「${glossary_heading}」に用語「${t}」が現れない"
      violations=$((violations + 1))
    fi
  done

  # 検査3: terms のいずれも節より前（同レベルの先行見出し以降）で使われていない
  local first_same_level_line
  first_same_level_line="$(awk -v lvl="$hd_level" '
    {
      allhash = 1
      for (i = 1; i <= lvl; i++) {
        c = substr($0, i, 1)
        if (c != "#") { allhash = 0 }
      }
      nextchar = substr($0, lvl + 1, 1)
      if (allhash && nextchar != "#" && length($0) >= lvl) { print NR; exit }
    }
  ' "$doc_path")"

  local scan_start="$heading_line"
  if [ -n "$first_same_level_line" ] && [ "$first_same_level_line" -lt "$heading_line" ]; then
    scan_start="$first_same_level_line"
  fi

  local before_text=""
  if [ "$scan_start" -le "$((heading_line - 1))" ]; then
    before_text="$(sed -n "${scan_start},$((heading_line - 1))p" "$doc_path")"
  fi

  for t in "${terms[@]}"; do
    total=$((total + 1))
    if [ -n "$before_text" ] && printf '%s\n' "$before_text" | grep -qF -- "$t"; then
      echo "[FAIL] 節「${glossary_heading}」より前で用語「${t}」が使われている"
      violations=$((violations + 1))
    fi
  done

  # 検査4: referringDocuments が先頭20行以内で glossaryDocument と「言葉」の両方に言及
  local rd
  for rd in "${referring[@]}"; do
    total=$((total + 1))
    local rd_path="$base/$rd"
    if [ ! -f "$rd_path" ]; then
      echo "[FAIL] referringDocuments が存在しない: ${rd}"
      violations=$((violations + 1))
      continue
    fi
    local head20
    head20="$(sed -n '1,20p' "$rd_path")"
    if ! printf '%s\n' "$head20" | grep -qF -- "$glossary_doc"; then
      echo "[FAIL] ${rd} の先頭20行に ${glossary_doc} への言及が無い"
      violations=$((violations + 1))
      continue
    fi
    if ! printf '%s\n' "$head20" | grep -qF -- "言葉"; then
      echo "[FAIL] ${rd} の先頭20行に「言葉」への言及が無い"
      violations=$((violations + 1))
    fi
  done

  echo "検査 $total 件 / 違反 $violations 件"
  [ "$violations" -eq 0 ]
}

self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/delivery-glossary.XXXXXX" 2>/dev/null)" || tmp=""
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "[FAIL] 一時ディレクトリを作れないため自己検査を実行できない"
    echo "実行 1 件 / 合格 0 件 / 不合格 1 件"
    return 1
  fi

  local base="$tmp/base"

  make_defs() {
    mkdir -p "$base/delivery-payload/references"
    cat > "$base/delivery-payload/references/配布文書の言葉.json" <<'JSON'
{
  "terms": ["特殊語A", "特殊語B"],
  "glossaryDocument": "README.md",
  "glossaryHeading": "## 言葉",
  "referringDocuments": ["RUNBOOK.md"]
}
JSON
  }

  # ケース1: 正常系（全検査に合格する）
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '概要の一文。' \
    '' \
    '## 言葉' \
    '' \
    '導入文。' \
    '' \
    '| 言葉 | 意味 |' \
    '|---|---|' \
    '| 特殊語A | 説明A。 |' \
    '| 特殊語B | 説明B。 |' \
    '' \
    '## 概要' \
    '' \
    '本文。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    'README.md の「言葉」の節を見よ。' \
    > "$base/RUNBOOK.md"
  if _gt_out2="$(scan "$base" 2>&1)"; then
    echo "[PASS] 正常系はすべて合格する"; pass=$((pass + 1))
  else
    echo "[FAIL] 正常系はすべて合格する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース2: 見出しの節が無い（検査1違反）
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '## 概要' \
    '' \
    '本文。特殊語Aも特殊語Bも書いていない。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    'README.md の「言葉」の節を見よ。' \
    > "$base/RUNBOOK.md"
  if _gt_out3="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 見出しの節が無ければ違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out3" | sed 's/^/    /' >&2
  else
    echo "[PASS] 見出しの節が無ければ違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース3: 節の中に用語が現れない（検査2違反）
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '## 言葉' \
    '' \
    '| 言葉 | 意味 |' \
    '|---|---|' \
    '| 特殊語A | 説明A。 |' \
    '' \
    '## 概要' \
    '' \
    '本文。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    'README.md の「言葉」の節を見よ。' \
    > "$base/RUNBOOK.md"
  if _gt_out4="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 節内に用語が無ければ違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out4" | sed 's/^/    /' >&2
  else
    echo "[PASS] 節内に用語が無ければ違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース4: 節より前（先行する見出し節の中）で用語が使われている（検査3違反）
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '## 先行節' \
    '' \
    'ここで特殊語Aを説明なく使う。' \
    '' \
    '## 言葉' \
    '' \
    '| 言葉 | 意味 |' \
    '|---|---|' \
    '| 特殊語A | 説明A。 |' \
    '| 特殊語B | 説明B。 |' \
    '' \
    '## 概要' \
    '' \
    '本文。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    'README.md の「言葉」の節を見よ。' \
    > "$base/RUNBOOK.md"
  if _gt_out5="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 節より前の見出し節で用語を使っていれば違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out5" | sed 's/^/    /' >&2
  else
    echo "[PASS] 節より前の見出し節で用語を使っていれば違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  # ケース4b: 見出しより前の前置き文（タイトル・導入の一文）だけで用語を使うのは違反にしない
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '導入の一文で特殊語Aに触れる。' \
    '' \
    '## 言葉' \
    '' \
    '| 言葉 | 意味 |' \
    '|---|---|' \
    '| 特殊語A | 説明A。 |' \
    '| 特殊語B | 説明B。 |' \
    '' \
    '## 概要' \
    '' \
    '本文。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    'README.md の「言葉」の節を見よ。' \
    > "$base/RUNBOOK.md"
  if _gt_out6="$(scan "$base" 2>&1)"; then
    echo "[PASS] 見出しより前の前置き文での使用は違反にしない"; pass=$((pass + 1))
  else
    echo "[FAIL] 見出しより前の前置き文での使用は違反にしない"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out6" | sed 's/^/    /' >&2
  fi
  rm -rf "$base"

  # ケース5: referringDocuments が先頭20行以内で言及していない（検査4違反）
  make_defs
  printf '%s\n' \
    '# タイトル' \
    '' \
    '## 言葉' \
    '' \
    '| 言葉 | 意味 |' \
    '|---|---|' \
    '| 特殊語A | 説明A。 |' \
    '| 特殊語B | 説明B。 |' \
    '' \
    '## 概要' \
    '' \
    '本文。' \
    > "$base/README.md"
  printf '%s\n' \
    '# RUNBOOK' \
    '' \
    '言及なし。' \
    > "$base/RUNBOOK.md"
  if _gt_out7="$(scan "$base" 2>&1)"; then
    echo "[FAIL] 参照文書が言及していなければ違反と判定する"; fail=$((fail + 1))
    printf '%s\n' "$_gt_out7" | sed 's/^/    /' >&2
  else
    echo "[PASS] 参照文書が言及していなければ違反と判定する"; pass=$((pass + 1))
  fi
  rm -rf "$base"

  rm -rf "$tmp"
  echo "実行 $((pass + fail)) 件 / 合格 $pass 件 / 不合格 $fail 件"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --self-test)
    self_test
    exit $?
    ;;
  "")
    scan "$REPO_ROOT"
    exit $?
    ;;
  *)
    echo "使い方: $(basename "$0") [--self-test]" >&2
    exit 2
    ;;
esac
