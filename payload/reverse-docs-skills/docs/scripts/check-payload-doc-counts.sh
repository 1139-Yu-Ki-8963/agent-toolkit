#!/usr/bin/env bash
# 納品先向け設計文書に置いた機械計測可能な数値と一覧だけを正本と照合する。
# 文章の記述内容、時点付き記録、機械的な対応を定義できない数値と一覧は対象外である。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PAYLOAD_DOC_COUNT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DEFINITIONS="${PAYLOAD_DOC_COUNT_DEFINITIONS:-$REPO_ROOT/docs/references/payload-doc-count-checks.json}"
TMP_FILES=()

cleanup() {
  local path
  for path in "${TMP_FILES[@]}"; do
    [ -n "$path" ] && rm -rf "$path"
  done
}
trap cleanup EXIT

make_tmp_dir() {
  local variable="$1" path
  if ! path="$(mktemp -d "${TMPDIR:-/tmp}/check-payload-doc-counts.XXXXXX" 2>/dev/null)" || [ -z "$path" ]; then
    echo "[UNKNOWN] mktempで一時領域を作成できません" >&2
    return 2
  fi
  TMP_FILES+=("$path")
  printf -v "$variable" '%s' "$path"
}

measure() {
  local metric="$1" kind path filter start end pattern
  kind="$(jq -r --arg metric "$metric" '.metrics[$metric].kind // empty' "$DEFINITIONS")"
  path="$(jq -r --arg metric "$metric" '.metrics[$metric].path // empty' "$DEFINITIONS")"
  case "$kind" in
    jq)
      filter="$(jq -r --arg metric "$metric" '.metrics[$metric].filter // empty' "$DEFINITIONS")"
      jq -r "$filter" "$REPO_ROOT/$path"
      ;;
    markdown_table_rows|markdown_headings)
      start="$(jq -r --arg metric "$metric" '.metrics[$metric].start // empty' "$DEFINITIONS")"
      end="$(jq -r --arg metric "$metric" '.metrics[$metric].end // empty' "$DEFINITIONS")"
      pattern="$(jq -r --arg metric "$metric" '.metrics[$metric].pattern // empty' "$DEFINITIONS")"
      awk -v start="$start" -v end="$end" -v pattern="$pattern" '
        index($0, start) { starts++; active=1 }
        active && index($0, end) { ends++; active=0 }
        active && $0 ~ pattern { count++ }
        END {
          if (starts != 1 || ends != 1) exit 2
          print count + 0
        }
      ' "$REPO_ROOT/$path"
      ;;
    *)
      echo "[UNKNOWN] 未対応の計測種別です: $metric" >&2
      return 2
      ;;
  esac
}

run_check() {
  local total=0 matched=0 failed=0 metric path template value expected content
  if [ ! -e "$REPO_ROOT/delivery-payload/references" ]; then
    echo "[PASS] 対象なし: delivery-payload/references/ がありません"
    return 0
  fi
  if [ ! -r "$DEFINITIONS" ] || ! jq -e '
    . as $root |
    (.metrics | type == "object" and length > 0) and
    (.assertions | type == "array" and length > 0) and
    all(.metrics[];
      type == "object" and
      (.path | type == "string" and length > 0) and
      (
        (.kind == "jq" and (.filter | type == "string" and length > 0)) or
        ((.kind == "markdown_table_rows" or .kind == "markdown_headings") and
          (.start | type == "string" and length > 0) and
          (.end | type == "string" and length > 0) and
          (.pattern | type == "string" and length > 0))
      )
    ) and
    all(.assertions[]; . as $assertion |
      type == "object" and
      (.metric | type == "string" and length > 0) and
      (.path | type == "string" and length > 0) and
      (.template | type == "string" and length > 0 and contains("{{value}}")) and
      ($root.metrics | has($assertion.metric))
    )
  ' "$DEFINITIONS" >/dev/null 2>&1; then
    echo "[UNKNOWN] 件数対応の定義を読み取れません: $DEFINITIONS" >&2
    return 2
  fi
  while IFS=$'\t' read -r metric path template; do
    total=$((total + 1))
    if ! value="$(measure "$metric")"; then
      return 2
    fi
    expected="${template//\{\{value\}\}/$value}"
    content="$(<"$REPO_ROOT/$path")"
    if [[ "$content" == *"$expected"* ]]; then
      matched=$((matched + 1))
      echo "[PASS] $path: $metric"
    else
      failed=$((failed + 1))
      echo "[FAIL] $path: $metric の実測値に対応する記述がありません" >&2
    fi
  done < <(jq -r '.assertions[] | [.metric, .path, .template] | @tsv' "$DEFINITIONS")
  echo "検査 $total 件 / 一致 $matched 件 / 不一致 $failed 件"
  [ "$failed" -eq 0 ]
}

self_test() {
  local fixture
  make_tmp_dir fixture || return 2
  mkdir -p "$fixture/delivery-payload/references" "$fixture/docs/references"
  printf '%s\n' '{"parents":[{"children":[{"key":"a","toolDefined":true},{"key":"b","toolDefined":true}]}]}' > "$fixture/delivery-payload/references/rule-taxonomy.json"
  printf '%s\n' '{"kinds":[{},{}]}' > "$fixture/delivery-payload/references/design-unit-layout.json"
  printf '%s\n' '親カテゴリを 1 個、子カテゴリを 2 個' '子カテゴリは次の 2 件である。' '' '- `a`' '- `b`' '' 'これらは本文入りである。' > "$fixture/delivery-payload/references/規約定義と派生生成の設計.md"
  printf '%s\n' '2 種別の詳細設計' > "$fixture/delivery-payload/references/実装契約定義.md"
  printf '%s\n' '影響を受ける build-*.sh の実在ファイルは以下の 2 本である' '| build-portal.sh | x |' '| validate-manifest.sh | x |' '| build-matrix-pages.sh | x |' '## 段階的移行方針' '### generation-engine/scripts/extract/ 配下の抽出スクリプト群（2本）' '### extract-a.sh' '### extract-b.sh' '### build-matrix-data.sh' > "$fixture/delivery-payload/references/manifest-schema-extensions.md"
  cp "$DEFINITIONS" "$fixture/docs/references/payload-doc-count-checks.json"

  if PAYLOAD_DOC_COUNT_ROOT="$fixture" PAYLOAD_DOC_COUNT_DEFINITIONS="$fixture/docs/references/payload-doc-count-checks.json" bash "${BASH_SOURCE[0]}" >/dev/null; then
    echo "[PASS] 一致する合成資料"
  else
    echo "[FAIL] 一致する合成資料" >&2
    return 1
  fi
  printf '%s\n' '9 種別の詳細設計' > "$fixture/delivery-payload/references/実装契約定義.md"
  if _cap="$(PAYLOAD_DOC_COUNT_ROOT="$fixture" PAYLOAD_DOC_COUNT_DEFINITIONS="$fixture/docs/references/payload-doc-count-checks.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 不一致を検出できません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  fi
  echo "[PASS] 不一致を検出"

  printf '%s\n' '親カテゴリを 1 個、子カテゴリを 2 個' '子カテゴリは次の 2 件である。' '' '- `a`' '- `b`' '- `余分`' '' 'これらは本文入りである。' > "$fixture/delivery-payload/references/規約定義と派生生成の設計.md"
  printf '%s\n' '2 種別の詳細設計' > "$fixture/delivery-payload/references/実装契約定義.md"
  if _cap="$(PAYLOAD_DOC_COUNT_ROOT="$fixture" PAYLOAD_DOC_COUNT_DEFINITIONS="$fixture/docs/references/payload-doc-count-checks.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 一覧の余分な項目を検出できません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  fi
  echo "[PASS] 一覧の余分な項目を検出"

  printf '%s\n' '親カテゴリを 1 個、子カテゴリを 2 個' '子カテゴリは次の 2 件である。' '' '- `a`' '- `b`' '' 'これらは本文入りである。' > "$fixture/delivery-payload/references/規約定義と派生生成の設計.md"
  sed 's/## 段階的移行方針/## 存在しない終了位置/' "$fixture/delivery-payload/references/manifest-schema-extensions.md" > "$fixture/delivery-payload/references/manifest-schema-extensions.tmp"
  mv "$fixture/delivery-payload/references/manifest-schema-extensions.tmp" "$fixture/delivery-payload/references/manifest-schema-extensions.md"
  if _cap="$(PAYLOAD_DOC_COUNT_ROOT="$fixture" PAYLOAD_DOC_COUNT_DEFINITIONS="$fixture/docs/references/payload-doc-count-checks.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 終了位置の欠落を判定不能にできません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  else
    local marker_rc=$?
    if [ "$marker_rc" -ne 2 ]; then
      echo "[FAIL] 終了位置の欠落が終了コード2になりません" >&2
      return 1
    fi
  fi
  echo "[PASS] 終了位置の欠落を判定不能として区別"

  if _cap="$(PAYLOAD_DOC_COUNT_ROOT="$fixture" PAYLOAD_DOC_COUNT_DEFINITIONS="$fixture/docs/references/missing.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 定義の欠落を判定不能にできません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  else
    local missing_rc=$?
    if [ "$missing_rc" -ne 2 ]; then
      echo "[FAIL] 定義の欠落が終了コード2になりません" >&2
      return 1
    fi
  fi
  echo "[PASS] 定義の欠落を判定不能として区別"

  printf '%s\n' '一時ディレクトリではない' > "$fixture/not-a-directory"
  if _cap="$(TMPDIR="$fixture/not-a-directory" bash "${BASH_SOURCE[0]}" --self-test 2>&1)"; then
    echo "[FAIL] mktemp失敗を判定不能にできません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  else
    local mktemp_rc=$?
    if [ "$mktemp_rc" -ne 2 ]; then
      echo "[FAIL] mktemp失敗が終了コード2になりません" >&2
      return 1
    fi
  fi
  echo "[PASS] mktemp失敗を判定不能として区別"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  run_check
fi
