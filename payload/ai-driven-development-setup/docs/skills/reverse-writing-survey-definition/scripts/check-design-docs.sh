#!/usr/bin/env bash
set -u

# check-design-docs.sh — 要件定義書・共通設計文書の見出し構成と実在を検査する
#
# 目的:
#   要件定義書・共通設計文書は規約「設計書の書き方の決まり」の内容を節に
#   1対1で持つ。見出しの欠落・追記章・省略記載・位置づけの行の欠落・未記入
#   プレースホルダーの残存・実装位置(file:line)の記述を機械で検出する。
#
# 使い方:
#   check-design-docs.sh <文書.md>...
#   check-design-docs.sh --self-test
#
# 文書名(拡張子を除くbasename)を references/design-doc-sections.json の
# キーと照合する。キーに無いbasenameは「文書名-不明」で不合格とする。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   節-欠落        sectionsの各見出しが「## <節名>」として順にある
#   見出し-欠落    requiredHeadingsの各語を含む見出しがある
#   位置づけ-欠落  placementLineがtrue（または要件定義書）の文書で、各§節見出しの
#                  直後に「**この節の位置づけ: 」で始まる行がある
#   追記章-禁止    forbiddenChapterPrefixesで始まる見出しが無い
#   省略-禁止      forbiddenPhrasesが本文に無い
#   末尾-欠落      requiredTailSectionsの見出しがある
#   未記入-残存    「<...>」形式のプレースホルダーが残っていない
#   位置-禁止      file:line形式の実装位置の記述が無い
#   文書名-不明    basenameがdesign-doc-sections.jsonのキーに無い
#
# 終了コード:
#   0 = 全件合格
#   1 = 1件以上不合格（[FAIL]行を標準エラーへ列挙）
#   2 = 使い方の誤り・ファイル不在（判定不能）
#
# 保守責任者: 人手（ユーザー）。見出しの構成を変えるときは
#   references/design-doc-sections.json と様式を同時に直す。
#
# macOS bash 3.2 互換（連想配列は不使用）。jq を使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECTIONS_JSON="${SCRIPT_DIR}/../references/design-doc-sections.json"

FAIL_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $1: $2" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

passck() {
  PASS_COUNT=$((PASS_COUNT + 1))
}

has_jq() {
  command -v jq > /dev/null 2>&1
}

check_doc() {
  local file="$1" json="$2"
  local base
  base="$(basename "$file")"
  base="${base%.md}"

  local key_exists
  key_exists="$(jq -r --arg k "$base" 'has($k)' "$json")"
  if [ "$key_exists" != "true" ]; then
    fail "文書名-不明" "${file}: 「${base}」は design-doc-sections.json のキーにありません"
    return
  fi

  local content
  content="$(cat "$file")"

  # 節-欠落
  local -a sections
  local n_sections
  n_sections="$(jq -r --arg k "$base" '.[$k].sections | length' "$json")"
  local i
  local ok_sections=1
  local actual_headings
  actual_headings="$(grep -E '^## ' "$file" || true)"
  local expected_list=""
  for ((i=0; i<n_sections; i++)); do
    local s
    s="$(jq -r --arg k "$base" --argjson i "$i" '.[$k].sections[$i]' "$json")"
    expected_list="${expected_list}## ${s}
"
  done
  expected_list="$(printf '%s' "$expected_list" | sed '/^$/d')"
  local actual_list
  actual_list="$(printf '%s\n' "$actual_headings" | head -n "$n_sections")"
  if [ "$expected_list" = "$actual_list" ]; then
    passck
  else
    fail "節-欠落" "${file}: 見出しが規定と一致しません（実際: $(printf '%s' "$actual_list" | tr '\n' '/')）"
    ok_sections=0
  fi

  # 見出し-欠落
  local n_req
  n_req="$(jq -r --arg k "$base" '.[$k].requiredHeadings | length' "$json")"
  local ok_req=1
  for ((i=0; i<n_req; i++)); do
    local term
    term="$(jq -r --arg k "$base" --argjson i "$i" '.[$k].requiredHeadings[$i]' "$json")"
    if ! grep -qE "^#{2,3} .*${term}" "$file"; then
      fail "見出し-欠落" "${file}: 「${term}」を含む見出しがありません"
      ok_req=0
    fi
  done
  [ "$n_req" -gt 0 ] 2>/dev/null && [ "$ok_req" -eq 1 ] && passck

  # 位置づけ-欠落
  local placement_line
  placement_line="$(jq -r --arg k "$base" '.[$k].placementLine' "$json")"
  if [ "$placement_line" = "true" ] || [ "$base" = "要件定義書" ]; then
    local ok_place=1
    for ((i=0; i<n_sections; i++)); do
      local s
      s="$(jq -r --arg k "$base" --argjson i "$i" '.[$k].sections[$i]' "$json")"
      local heading_line_no
      heading_line_no="$(grep -n -F "## ${s}" "$file" | head -1 | cut -d: -f1)"
      if [ -z "$heading_line_no" ]; then
        continue
      fi
      local next_nonblank
      next_nonblank="$(awk -v start="$heading_line_no" 'NR>start && NF>0 {print; exit}' "$file")"
      if [[ "$next_nonblank" != "**この節の位置づけ: "* ]]; then
        fail "位置づけ-欠落" "${file}: 「## ${s}」の直後に位置づけの行がありません"
        ok_place=0
      fi
    done
    [ "$ok_place" -eq 1 ] && passck
  fi

  # 追記章-禁止
  local n_forbid
  n_forbid="$(jq -r '.common.forbiddenChapterPrefixes | length' "$json")"
  local ok_forbid=1
  for ((i=0; i<n_forbid; i++)); do
    local prefix
    prefix="$(jq -r --argjson i "$i" '.common.forbiddenChapterPrefixes[$i]' "$json")"
    if grep -qE "^#{2,3} ${prefix}" "$file"; then
      fail "追記章-禁止" "${file}: 「${prefix}」で始まる見出しがあります"
      ok_forbid=0
    fi
  done
  [ "$ok_forbid" -eq 1 ] && passck

  # 省略-禁止
  local n_phrases
  n_phrases="$(jq -r '.common.forbiddenPhrases | length' "$json")"
  local ok_phrases=1
  for ((i=0; i<n_phrases; i++)); do
    local phrase
    phrase="$(jq -r --argjson i "$i" '.common.forbiddenPhrases[$i]' "$json")"
    if grep -qF "$phrase" "$file"; then
      fail "省略-禁止" "${file}: 「${phrase}」が本文にあります"
      ok_phrases=0
    fi
  done
  [ "$ok_phrases" -eq 1 ] && passck

  # 末尾-欠落
  local n_tail
  n_tail="$(jq -r '.common.requiredTailSections | length' "$json")"
  local ok_tail=1
  for ((i=0; i<n_tail; i++)); do
    local tail
    tail="$(jq -r --argjson i "$i" '.common.requiredTailSections[$i]' "$json")"
    if ! grep -qF "## ${tail}" "$file"; then
      fail "末尾-欠落" "${file}: 「${tail}」の見出しがありません"
      ok_tail=0
    fi
  done
  [ "$ok_tail" -eq 1 ] && passck

  # 未記入-残存
  local placeholder_lines
  placeholder_lines="$(grep -nE '<[^<>]+>' "$file" || true)"
  if [ -n "$placeholder_lines" ]; then
    local cnt
    cnt="$(printf '%s\n' "$placeholder_lines" | grep -c '.')"
    fail "未記入-残存" "${file}: 未記入のプレースホルダーが${cnt}件あります（例: $(printf '%s\n' "$placeholder_lines" | head -1)）"
  else
    passck
  fi

  # 位置-禁止
  local pos_lines
  pos_lines="$(grep -nE '[A-Za-z0-9_./-]+\.(ts|js|py|rb|php|java|go|pl|cs|tsx|jsx):[0-9]+' "$file" || true)"
  if [ -n "$pos_lines" ]; then
    fail "位置-禁止" "${file}: 実装位置(file:line)の記述があります（例: $(printf '%s\n' "$pos_lines" | head -1)）"
  else
    passck
  fi
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-design-docs-self-test.XXXXXX")" || { echo "一時領域を作成できません" >&2; return 2; }
  trap 'rm -rf "$tmp"' RETURN

  local self_fail=0
  local self_total=0

  local self_dir
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  local tmpl_dir="${self_dir}/../templates"

  local -a doc_names=("要件定義書" "業務仕様書" "方式設計書" "データ設計書" "エラー設計書" "共通外部仕様書" "基盤設計書")
  local -a doc_paths=(
    "${tmpl_dir}/要件定義書.md"
    "${tmpl_dir}/common/業務仕様書.md"
    "${tmpl_dir}/common/方式設計書.md"
    "${tmpl_dir}/common/データ設計書.md"
    "${tmpl_dir}/common/エラー設計書.md"
    "${tmpl_dir}/common/共通外部仕様書.md"
    "${tmpl_dir}/common/基盤設計書.md"
  )

  local filled_dir="${tmp}/filled"
  mkdir -p "$filled_dir"
  local i
  for i in "${!doc_names[@]}"; do
    local name="${doc_names[$i]}"
    local src="${doc_paths[$i]}"
    sed -E 's/<[^<>]+>/記入済み/g' "$src" > "${filled_dir}/${name}.md"
  done

  assert_exit() {
    local desc="$1" expected="$2"; shift 2
    self_total=$((self_total + 1))
    "$@" > "${tmp}/out.log" 2>"${tmp}/err.log"
    local actual=$?
    if [ "$actual" = "$expected" ]; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} (期待終了コード ${expected} / 実際 ${actual})"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  assert_contains() {
    local desc="$1" key="$2"
    self_total=$((self_total + 1))
    if grep -qF "[FAIL] ${key}" "${tmp}/err.log"; then
      echo "PASS: ${desc}"
    else
      echo "FAIL: ${desc} （${key} の不合格が出ていません）"
      sed -n '1,20p' "${tmp}/err.log"
      self_fail=$((self_fail + 1))
    fi
  }

  # 合格-完成形
  local -a filled_paths=()
  for name in "${doc_names[@]}"; do
    filled_paths+=("${filled_dir}/${name}.md")
  done
  assert_exit "合格-完成形" 0 bash "$0" "${filled_paths[@]}"

  # 不合格-様式のまま
  assert_exit "不合格-様式のまま" 1 bash "$0" "${doc_paths[0]}"
  assert_contains "不合格-様式のまま: 未記入-残存が出る" "未記入-残存"

  # 不合格-節の欠落
  local missing_section="${tmp}/方式設計書.md"
  awk '/^## §7 災害対策方式$/{skip=1} !skip{print}' "${filled_dir}/方式設計書.md" > "$missing_section"
  assert_exit "不合格-節の欠落" 1 bash "$0" "$missing_section"
  assert_contains "不合格-節の欠落: 節-欠落が出る" "節-欠落"

  # 不合格-追記章
  local extra_chapter="${tmp}/業務仕様書.md"
  cp "${filled_dir}/業務仕様書.md" "$extra_chapter"
  printf '\n## 追記\n記入済み\n' >> "$extra_chapter"
  assert_exit "不合格-追記章" 1 bash "$0" "$extra_chapter"
  assert_contains "不合格-追記章: 追記章-禁止が出る" "追記章-禁止"

  # 不合格-省略
  local abbrev="${tmp}/エラー設計書.md"
  cp "${filled_dir}/エラー設計書.md" "$abbrev"
  printf '\n以下略\n' >> "$abbrev"
  assert_exit "不合格-省略" 1 bash "$0" "$abbrev"
  assert_contains "不合格-省略: 省略-禁止が出る" "省略-禁止"

  # 不合格-位置
  local pos="${tmp}/データ設計書.md"
  cp "${filled_dir}/データ設計書.md" "$pos"
  printf '\nsrc/app.ts:120 を参照する。\n' >> "$pos"
  assert_exit "不合格-位置" 1 bash "$0" "$pos"
  assert_contains "不合格-位置: 位置-禁止が出る" "位置-禁止"

  # 不合格-文書名
  local memo="${tmp}/memo.md"
  echo "# memo" > "$memo"
  assert_exit "不合格-文書名" 1 bash "$0" "$memo"
  assert_contains "不合格-文書名: 文書名-不明が出る" "文書名-不明"

  echo "実行 ${self_total} 件 / 失敗 ${self_fail} 件"
  if [ "$self_fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if ! has_jq; then
  echo "jq が必要です" >&2
  exit 2
fi

if [ ! -f "$SECTIONS_JSON" ]; then
  echo "見出し定義が見つかりません: ${SECTIONS_JSON}" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  echo "使い方: check-design-docs.sh <文書.md>..." >&2
  exit 2
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "ファイルが見つかりません: $f" >&2
    exit 2
  fi
done

for f in "$@"; do
  check_doc "$f" "$SECTIONS_JSON"
done

echo "合格 ${PASS_COUNT} 件 / 不合格 ${FAIL_COUNT} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
