#!/usr/bin/env bash
# docs/tasks/done/ の指示書について、判定表の状態と目視理由を集計する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_DONE_DIR="$REPO_ROOT/docs/tasks/done"
SELF_TEST_TMPDIR=""

cleanup_self_test() {
  if [ -n "$SELF_TEST_TMPDIR" ] && [ -d "$SELF_TEST_TMPDIR" ]; then
    rm -rf -- "$SELF_TEST_TMPDIR"
  fi
}

unknown() {
  echo "[UNKNOWN] $1" >&2
  return 2
}

analyze_done_dir() {
  local done_dir="$1"
  local files=()
  local file

  if [ ! -d "$done_dir" ]; then
    unknown "done ディレクトリが見つかりません: $done_dir"
    return $?
  fi

  while IFS= read -r file; do
    if [ "$(basename "$file")" = "この場所について.md" ]; then
      continue
    fi
    files+=("$file")
  done < <(find "$done_dir" -type f -name '*.md' -print | LC_ALL=C sort)

  if [ "${#files[@]}" -eq 0 ]; then
    unknown "指示書が見つかりません: $done_dir"
    return $?
  fi

  LC_ALL=C awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function filename(path, parts, count) {
      count = split(path, parts, "/")
      return parts[count]
    }
    function parse_columns(line, count, column_index, character, previous, method_text) {
      delete cols
      count = 1
      cols[count] = ""
      previous = ""
      for (column_index = 1; column_index <= length(line); column_index++) {
        character = substr(line, column_index, 1)
        if (character == "|" && previous != "\\") {
          method_text = trim(cols[count])
          if (count == 3 && method_text ~ /^`/ && method_text !~ /`$/) {
            cols[count] = cols[count] character
          } else {
            count++
            cols[count] = ""
          }
        } else {
          cols[count] = cols[count] character
        }
        previous = character
      }
      for (column_index = 1; column_index <= count; column_index++) {
        cols[column_index] = trim(cols[column_index])
        gsub(/\\[|]/, "|", cols[column_index])
      }
      return count
    }
    function allowed_reason(reason) {
      if (reason ~ /(不要|要しない|依存しない|突き合わせない)/) return 0
      return (reason ~ /文面/ && reason ~ /評価/) ||
        (reason ~ /複数/ && reason ~ /資料/ && reason ~ /突き合わせ/) ||
        (reason ~ /実行環境/ && reason ~ /依存/)
    }
    function append_name(list, name) {
      return list == "" ? name : list "、" name
    }
    function finish_file(name) {
      if (current_file == "") return
      total++
      name = filename(current_file)
      if (has_table) {
        table_files++
      } else {
        no_table_names = append_name(no_table_names, name)
      }
      if (has_bad_state) {
        bad_state_files++
        bad_state_names = append_name(bad_state_names, name)
      }
      if (has_visual) {
        visual_files++
        visual_names = append_name(visual_names, name)
      }
      if (has_bad_visual) {
        bad_visual_files++
        bad_visual_names = append_name(bad_visual_names, name)
      }
    }
    FNR == 1 {
      finish_file()
      current_file = FILENAME
      in_fence = 0
      in_verdict_section = 0
      has_table = 0
      has_bad_state = 0
      has_visual = 0
      has_bad_visual = 0
      method_col = 0
      state_col = 0
      reason_col = 0
    }
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    /^### 判定の充足状況/ {
      in_verdict_section = 1
      method_col = state_col = reason_col = 0
      next
    }
    /^### / {
      in_verdict_section = 0
      method_col = state_col = reason_col = 0
      next
    }
    !in_verdict_section { next }
    /^\|/ {
      column_count = parse_columns($0)
      if (method_col == 0) {
        for (column = 2; column < column_count; column++) {
          if (cols[column] == "確かめる手段") method_col = column
          if (cols[column] == "状態") state_col = column
          if (cols[column] == "確かめた内容") reason_col = column
        }
        if (method_col > 0 && state_col > 0 && reason_col > 0) has_table = 1
        next
      }
      if (cols[2] ~ /^-+$/) next
      method = cols[method_col]
      state = cols[state_col]
      reason = cols[reason_col]
      gsub(/^`|`$/, "", method)
      if (state != "完了" && state != "対象外") has_bad_state = 1
      if (method == "目視") {
        has_visual = 1
        if (!allowed_reason(reason)) has_bad_visual = 1
      }
    }
    END {
      finish_file()
      printf "指示書総数: %d件\n", total
      printf "判定表を持つ指示書: %d件\n", table_files
      printf "判定表なし: %d件\n", total - table_files
      if (total > table_files) printf "  %s\n", no_table_names
      printf "未着手・対応中などが残る指示書: %d件\n", bad_state_files
      if (bad_state_files > 0) printf "  %s\n", bad_state_names
      printf "目視の行を持つ指示書: %d件\n", visual_files
      if (visual_files > 0) printf "  %s\n", visual_names
      printf "理由なし・不適切な理由の目視を持つ指示書: %d件\n", bad_visual_files
      if (bad_visual_files > 0) printf "  %s\n", bad_visual_names
      exit total > table_files || bad_state_files > 0 || bad_visual_files > 0 ? 1 : 0
    }
  ' "${files[@]}"
}

run_self_test() {
  SELF_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/done-instruction-verdicts.XXXXXX")" || {
    unknown "自己テスト用の一時ディレクトリを作成できません"
    return $?
  }
  trap cleanup_self_test EXIT HUP INT TERM

  local good="$SELF_TEST_TMPDIR/good"
  local bad="$SELF_TEST_TMPDIR/bad"
  local output
  local code
  mkdir "$good"
  mkdir "$bad"

  printf '%s\n' \
    '# 正常' \
    '```' \
    '### 判定の充足状況' \
    '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |' \
    '|---|---|---|---|---|' \
    '| 例 | 目視 | 未着手 | — | — |' \
    '```' \
    '### 判定の充足状況' \
    '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |' \
    '|---|---|---|---|---|' \
    '| 1 | `printf "a" | grep a` | 完了 | abc | 完了 |' \
    '| 2 | 目視 | 完了 | abc | 文面の評価を要するため |' \
    '| 3 | `true` | 対象外 | — | 実行対象が存在しないため |' > "$good/正常.md"
  output="$(analyze_done_dir "$good")"
  code=$?
  if [ "$code" -ne 0 ] || ! printf '%s\n' "$output" | grep -q '目視の行を持つ指示書: 1件'; then
    echo "[FAIL] 正常系の自己テスト"
    printf '%s\n' "$output"
    return 1
  fi

  printf '%s\n' '# 判定表なし' > "$bad/判定表なし.md"
  printf '%s\n' \
    '# 空欄状態' \
    '### 判定の充足状況' \
    '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |' \
    '|---|---|---|---|---|' \
    '| 1 | `true` |  | abc | 未記録 |' > "$bad/空欄状態.md"
  printf '%s\n' \
    '# 不備あり' \
    '### 判定の充足状況' \
    '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |' \
    '|---|---|---|---|---|' \
    '| 1 | `true` | 保留 | abc | 未記録 |' > "$bad/不備あり.md"
  printf '%s\n' \
    '# 列の取り違え' \
    '### 判定の充足状況' \
    '| 判定 | 確かめる手段 | 状態 | コミット | 確かめた内容 |' \
    '|---|---|---|---|---|' \
    '| 文面の評価 | 目視 | 対応中 | abc | 完了 |' \
    '| 2 | 目視 | 完了 | abc | 文面の評価は不要 |' > "$bad/列の取り違え.md"
  set +e
  output="$(analyze_done_dir "$bad")"
  code=$?
  set -e
  if [ "$code" -ne 1 ] ||
    ! printf '%s\n' "$output" | grep -q '判定表なし: 1件' ||
    ! printf '%s\n' "$output" | grep -q '未着手・対応中などが残る指示書: 3件' ||
    ! printf '%s\n' "$output" | grep -q '理由なし・不適切な理由の目視を持つ指示書: 1件'; then
    echo "[FAIL] 不備検出の自己テスト"
    printf '%s\n' "$output"
    return 1
  fi

  echo "[PASS] 自己テスト2件"
}

case "${1:-}" in
  --self-test)
    run_self_test
    ;;
  "")
    analyze_done_dir "$DEFAULT_DONE_DIR"
    ;;
  *)
    analyze_done_dir "$1"
    ;;
esac
