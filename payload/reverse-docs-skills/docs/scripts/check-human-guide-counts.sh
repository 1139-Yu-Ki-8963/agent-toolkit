#!/usr/bin/env bash
# 人向け資料に置いた機械計測可能な件数だけを正本と照合する。
# 文章の意味、時点付き記録、一覧の説明内容、第1層の検査本数は対象外である。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HUMAN_GUIDE_COUNT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DEFINITIONS="${HUMAN_GUIDE_COUNT_DEFINITIONS:-$REPO_ROOT/docs/references/human-guide-count-checks.json}"
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
  if ! path="$(mktemp -d "${TMPDIR:-/tmp}/check-human-guide-counts.XXXXXX" 2>/dev/null)" || [ -z "$path" ]; then
    echo "[UNKNOWN] mktempで一時領域を作成できません" >&2
    return 2
  fi
  TMP_FILES+=("$path")
  printf -v "$variable" '%s' "$path"
}

measure() {
  local metric="$1" kind path filter pattern
  kind="$(jq -r --arg metric "$metric" '.metrics[$metric].kind // empty' "$DEFINITIONS")"
  path="$(jq -r --arg metric "$metric" '.metrics[$metric].path // empty' "$DEFINITIONS")"
  case "$kind" in
    directories)
      find "$REPO_ROOT/$path" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
      ;;
    jq)
      filter="$(jq -r --arg metric "$metric" '.metrics[$metric].filter // empty' "$DEFINITIONS")"
      jq -r "$filter" "$REPO_ROOT/$path"
      ;;
    fixed_string_count)
      pattern="$(jq -r --arg metric "$metric" '.metrics[$metric].pattern // empty' "$DEFINITIONS")"
      awk -v pattern="$pattern" '{ line=$0; while ((position=index(line, pattern)) > 0) { count++; line=substr(line, position + length(pattern)) } } END { print count + 0 }' "$REPO_ROOT/$path"
      ;;
    *)
      echo "[UNKNOWN] 未対応の計測種別です: $metric" >&2
      return 2
      ;;
  esac
}

run_check() {
  local total=0 matched=0 failed=0 metric path template value expected
  if [ ! -e "$REPO_ROOT/docs/guides" ]; then
    echo "[PASS] 対象なし: docs/guides/ がありません"
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
        .kind == "directories" or
        (.kind == "jq" and (.filter | type == "string" and length > 0)) or
        (.kind == "fixed_string_count" and (.pattern | type == "string" and length > 0))
      )
    ) and
    all(.assertions[]; . as $assertion |
      type == "object" and
      (.metric | type == "string") and
      (.path | type == "string") and
      (.template | type == "string") and
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
    if grep -Fq "$expected" "$REPO_ROOT/$path"; then
      matched=$((matched + 1))
      echo "[PASS] $path: $expected"
    else
      failed=$((failed + 1))
      echo "[FAIL] $path: $expected がありません" >&2
    fi
  done < <(jq -r '.assertions[] | [.metric, .path, .template] | @tsv' "$DEFINITIONS")
  echo "検査 $total 件 / 一致 $matched 件 / 不一致 $failed 件"
  [ "$failed" -eq 0 ]
}

self_test() {
  local fixture
  make_tmp_dir fixture || return 2
  mkdir -p "$fixture/.claude/skills/a" "$fixture/.claude/skills/b" \
    "$fixture/delivery-payload/references" "$fixture/docs/guides" "$fixture/docs/references"
  printf '%s\n' '{"categories":[{"blueprints":[{},{},{}]}]}' > "$fixture/delivery-payload/references/portal-catalog.json"
  printf '%s\n' '{"parents":[{"children":[{},{}]}]}' > "$fixture/delivery-payload/references/rule-taxonomy.json"
  printf '%s\n' 'リポジトリ内2本＋納品専用3本 規約(2件)' > "$fixture/docs/guides/reverse-docs-overview.html"
  printf '%s\n' '配下のスキル数は 2 本である' > "$fixture/docs/guides/スキル一覧.html"
  printf '%s\n' '納品物カタログには3件が定義されている。規約は2件である。' > "$fixture/docs/guides/納品物ガイド.html"
  printf '%s\n' '<div class="label">成果物数</div><div class="value">2<span class="unit">本</span></div>' '<div class="label">スキル</div><div class="value">2<span class="unit">本</span></div>' '<span class="count">2本</span>' '<tr><td class="id">a</td></tr><tr><td class="id">b</td></tr>' > "$fixture/docs/guides/成果物一覧.html"
  cp "$DEFINITIONS" "$fixture/docs/references/human-guide-count-checks.json"

  if HUMAN_GUIDE_COUNT_ROOT="$fixture" HUMAN_GUIDE_COUNT_DEFINITIONS="$fixture/docs/references/human-guide-count-checks.json" bash "${BASH_SOURCE[0]}" >/dev/null; then
    echo "[PASS] 一致する合成資料"
  else
    echo "[FAIL] 一致する合成資料" >&2
    return 1
  fi
  printf '%s\n' '配下のスキル数は 9 本である' > "$fixture/docs/guides/スキル一覧.html"
  if _cap="$(HUMAN_GUIDE_COUNT_ROOT="$fixture" HUMAN_GUIDE_COUNT_DEFINITIONS="$fixture/docs/references/human-guide-count-checks.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 不一致を検出できません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  fi
  echo "[PASS] 不一致を検出"

  if _cap="$(HUMAN_GUIDE_COUNT_ROOT="$fixture" HUMAN_GUIDE_COUNT_DEFINITIONS="$fixture/docs/references/missing.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
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

  printf '%s\n' '{"metrics":{"x":{"kind":"fixed_string_count","path":"docs/guides/成果物一覧.html"}},"assertions":[{"metric":"x","path":"docs/guides/成果物一覧.html","template":"{{value}}"}]}' > "$fixture/docs/references/invalid.json"
  if _cap="$(HUMAN_GUIDE_COUNT_ROOT="$fixture" HUMAN_GUIDE_COUNT_DEFINITIONS="$fixture/docs/references/invalid.json" bash "${BASH_SOURCE[0]}" 2>&1)"; then
    echo "[FAIL] 不正な定義を判定不能にできません" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    return 1
  else
    local invalid_rc=$?
    if [ "$invalid_rc" -ne 2 ]; then
      echo "[FAIL] 不正な定義が終了コード2になりません" >&2
      return 1
    fi
  fi
  echo "[PASS] 不正な定義を判定不能として区別"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  run_check
fi
