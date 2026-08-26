#!/usr/bin/env bash
# 顧客提示文書の文体（敬体/常体）を検査する（1-237）。
# 除外は定義ファイルのbasenameと配置条件が両方一致した内部文書だけに限る。
set -uo pipefail

_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd
}

_exclusion_json() {
  printf '%s/delivery-payload/references/document-style-exclusions.json\n' "$(_repo_root)"
}

_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[UNKNOWN] 必須コマンドが見つからないため判定できません: $command_name" >&2
    return 2
  fi
}

_check_dependencies() {
  _require_command node || return 2
  _require_command jq || return 2
}

_validate_definition() {
  local definition="$1"
  if [ ! -r "$definition" ]; then
    echo "[UNKNOWN] 文体除外の定義を読めないため判定できません: $definition" >&2
    return 2
  fi
  if ! jq -e '
    (.schemaVersion | type == "number") and
    .schemaVersion >= 2 and
    (.excludedBasenames | type == "array" and length > 0) and
    all(.excludedBasenames[];
      (.basename | type == "string" and length > 0) and
      (.allowedPathFragments | type == "array" and length > 0) and
      all(.allowedPathFragments[];
        type == "string" and startswith("/") and endswith("/") and
        (split("/") | length) >= 3
      )
    )
  ' "$definition" >/dev/null 2>&1; then
    echo "[UNKNOWN] 文体除外の定義が不正なため判定できません: $definition" >&2
    return 2
  fi
}

_normalize_path() {
  local f="$1" dir base
  dir="$(cd "$(dirname "$f")" && pwd -P)" || return 1
  base="$(basename "$f")"
  printf '%s/%s\n' "${dir%/}" "$base"
}

_is_excluded_file() {
  local f="$1" definition="$2"
  local base="" normalized="" fragment=""
  base="$(basename "$f")"
  normalized="$(_normalize_path "$f")"

  while IFS= read -r fragment; do
    [ -n "$fragment" ] || continue
    if [[ "$normalized" == *"$fragment"* ]]; then
      return 0
    fi
  done < <(jq -r --arg base "$base" \
    '.excludedBasenames[]? | select(.basename == $base) | .allowedPathFragments[]? // empty' \
    "$definition" 2>/dev/null)
  return 1
}

scan_file() {
  local f="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    let text;
    try {
      text = fs.readFileSync(path, "utf8");
    } catch (error) {
      console.error(`[UNKNOWN] 文書を読み取れないため判定できません: ${path}`);
      process.exit(2);
    }
    const noComments = text.replace(/<!--[\s\S]*?-->/g, "");
    const lines = noComments.split("\n");
    const jodoRe = /(である|だ)$/;
    const keitaiRe = /(です|ます|でしょう|ましょう|ください)$/;
    let failed = false;
    let inFence = false;
    lines.forEach((line, idx) => {
      const lineNo = idx + 1;
      const trimmed = line.trim();
      if (/^```/.test(trimmed)) { inFence = !inFence; return; }
      if (inFence) return;
      if (trimmed === "" || /^\s*\|/.test(trimmed) || /^#/.test(trimmed)) return;
      trimmed.split("。").forEach((sentence) => {
        const s = sentence
          .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
          .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
          .replace(/[\*_~`]/g, "")
          .trim();
        if (!s || keitaiRe.test(s)) return;
        if (jodoRe.test(s)) {
          console.log(`FAIL ${path}:${lineNo} 常体の文末を検出: ${s}。`);
          failed = true;
        }
      });
    });
    process.exit(failed ? 1 : 0);
  ' "$f"
}

list_markdown_files() {
  local target="$1"
  find "$target" -type f -name '*.md' -print0 2>/dev/null
}

fail_markdown_file_listing() {
  return 1
}

run_check_with_definition_and_lister() {
  local definition="$1" lister="$2"
  shift 2
  local targets=("$@") files=()
  local t="" f="" out="" scan_rc=0 list_file=""

  _check_dependencies || return 2
  _validate_definition "$definition" || return 2
  for t in "${targets[@]}"; do
    if [ -d "$t" ]; then
      if ! list_file="$(mktemp "${TMPDIR:-/tmp}/check-document-style-files.XXXXXX" 2>/dev/null)" || [ -z "$list_file" ]; then
        echo "[UNKNOWN] 文書一覧用の一時ファイルを作成できないため判定できません" >&2
        return 2
      fi
      if ! "$lister" "$t" > "$list_file"; then
        rm -f "$list_file"
        list_file=""
        echo "[UNKNOWN] 対象ディレクトリの文書を列挙できないため判定できません: $t" >&2
        return 2
      fi
      while IFS= read -r -d '' f; do files+=("$f"); done < "$list_file"
      rm -f "$list_file"
      list_file=""
    elif [ -f "$t" ]; then
      files+=("$t")
    else
      echo "[UNKNOWN] 指定された対象が存在しないため判定できません: $t" >&2
      return 2
    fi
  done

  if [ "${#files[@]}" -eq 0 ]; then
    echo "[UNKNOWN] 対象のMarkdownファイルが見つからないため判定できません: ${targets[*]}" >&2
    return 2
  fi

  local total_fail=0 clean=0 excluded=0
  for f in "${files[@]}"; do
    if _is_excluded_file "$f" "$definition"; then
      excluded=$((excluded + 1))
      continue
    fi
    out="$(scan_file "$f" 2>&1)"
    scan_rc=$?
    case "$scan_rc" in
      0)
        clean=$((clean + 1))
        ;;
      1)
        [ -n "$out" ] && echo "$out"
        total_fail=$((total_fail + 1))
        ;;
      *)
        [ -n "$out" ] && echo "$out" >&2
        echo "[UNKNOWN] 文書の走査に失敗したため判定できません: $f" >&2
        return 2
        ;;
    esac
  done

  local rc=0
  if [ "$total_fail" -gt 0 ]; then
    echo "FAIL: 常体の文末を持つ文書 ${total_fail} 件（CLEAN ${clean} 件）"
    rc=1
  else
    echo "CLEAN: ${clean} 件の文書に常体の文末はない"
  fi
  echo "除外 ${excluded} 件"
  return "$rc"
}

run_check_with_definition() {
  local definition="$1"
  shift
  run_check_with_definition_and_lister "$definition" list_markdown_files "$@"
}

run_check() {
  local definition
  definition="$(_exclusion_json)"
  run_check_with_definition "$definition" "$@"
}

self_test() {
  local tmpdir=""
  _check_dependencies || return 2
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした）"
    return 2
  fi
  self_test_tmpdir="$tmpdir"
  trap 'if [ -n "${self_test_tmpdir:-}" ]; then rm -rf "$self_test_tmpdir"; fi' EXIT

  local pass=0 fail=0 actual_rc=0 out=""
  assert_rc() {
    local label="$1" expected="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
      actual_rc=0
    else
      actual_rc=$?
    fi
    if [ "$actual_rc" -eq "$expected" ]; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label (期待=$expected 実際=$actual_rc)" >&2
      fail=$((fail + 1))
    fi
  }
  assert_contains() {
    local label="$1" needle="$2"
    shift 2
    out="$("$@" 2>&1)"
    if grep -qF -- "$needle" <<< "$out"; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label (出力に「$needle」が含まれない)" >&2
      fail=$((fail + 1))
    fi
  }

  mkdir -p "$tmpdir/customer" "$tmpdir/.claude/skills/sample" \
    "$tmpdir/docs/rules/sample" "$tmpdir/.claude/agents"
  printf '%s\n' '# 敬体' '' '本書は対象の仕様を示します。' > "$tmpdir/customer/polite.md"
  printf '%s\n' '# 常体混入' '' '本書は対象の仕様を示します。この項目は未確定である。' > "$tmpdir/customer/mixed.md"
  printf '%s\n' '# 句点なし常体' '' 'この項目は未確定である' > "$tmpdir/customer/plain-no-period.md"
  printf '%s\n' '# 末尾常体' '' '前文は敬体です。末尾は常体である' > "$tmpdir/customer/trailing-no-period.md"
  printf '%s\n' '# 装飾付き常体' '' 'この機能は**未確定である**。' > "$tmpdir/customer/decorated.md"
  printf '%s\n' '# 単一アスタリスク' '' 'この機能は*未確定である*。' > "$tmpdir/customer/single-asterisk.md"
  printf '%s\n' '# 単一アンダースコア' '' 'この機能は_未確定である_。' > "$tmpdir/customer/single-underscore.md"
  printf '%s\n' '# リンク' '' 'この機能は[未確定である](details.md)。' > "$tmpdir/customer/link.md"
  printf '%s\n' '# 内部スキル' '' 'このスキルは作業手順を定義するものである。' > "$tmpdir/.claude/skills/sample/SKILL.md"
  printf '%s\n' '# 設計判断' '' 'この判断は内部作業のためである。' > "$tmpdir/docs/rules/sample/design-notes.md"
  printf '%s\n' '# レビュー担当' '' 'この担当は規約を確認するものである。' > "$tmpdir/.claude/agents/rule-reviewer.md"
  printf '%s\n' '# 顧客提示単位資料' '' '本書は顧客へ提示する単位資料である。' > "$tmpdir/customer/SKILL.md"
  printf '%s\n' '# 顧客提示設計書' '' '本書は顧客へ提示する設計書である。' > "$tmpdir/customer/設計書様式.md"
  printf '%s\n' '# 一覧外' '' 'この文書は対象の仕様を示すものである。' > "$tmpdir/customer/design-notes-old.md"
  printf '%s\n' '# コメント' '' '<!-- この記入規則は常体でよい。 -->' '' '本書は対象の仕様を示します。' > "$tmpdir/customer/comment.md"
  printf '%s\n' '# 表' '' '| 項目 | 説明 |' '|---|---|' '| 例 | 未確定である |' '' '本書は対象の仕様を示します。' > "$tmpdir/customer/table.md"
  printf '%s\n' '{broken json' > "$tmpdir/invalid-exclusions.json"

  assert_rc '敬体だけの顧客提示文書は合格' 0 run_check "$tmpdir/customer/polite.md"
  assert_rc '常体を混ぜた顧客提示文書は不合格' 1 run_check "$tmpdir/customer/mixed.md"
  assert_rc '句点なしの常体文も不合格' 1 run_check "$tmpdir/customer/plain-no-period.md"
  assert_rc '敬体文の後にある句点なし常体文も不合格' 1 run_check "$tmpdir/customer/trailing-no-period.md"
  assert_rc '装飾された常体文も不合格' 1 run_check "$tmpdir/customer/decorated.md"
  assert_rc '単一アスタリスクで装飾された常体文も不合格' 1 \
    run_check "$tmpdir/customer/single-asterisk.md"
  assert_rc '単一アンダースコアで装飾された常体文も不合格' 1 \
    run_check "$tmpdir/customer/single-underscore.md"
  assert_rc 'リンク表示文字が常体なら不合格' 1 run_check "$tmpdir/customer/link.md"
  assert_rc '内部配置のSKILL.mdは除外' 0 run_check "$tmpdir/.claude/skills/sample/SKILL.md"
  assert_rc '内部配置のdesign-notes.mdは除外' 0 run_check "$tmpdir/docs/rules/sample/design-notes.md"
  assert_rc '内部配置のrule-reviewer.mdは除外' 0 run_check "$tmpdir/.claude/agents/rule-reviewer.md"
  assert_rc '顧客提示配置のSKILL.mdは除外せず不合格' 1 run_check "$tmpdir/customer/SKILL.md"
  assert_rc '顧客提示配置の設計書様式.mdは除外せず不合格' 1 run_check "$tmpdir/customer/設計書様式.md"
  assert_rc '一覧外の文書は不合格' 1 run_check "$tmpdir/customer/design-notes-old.md"
  assert_rc 'HTMLコメント内の常体は無視' 0 run_check "$tmpdir/customer/comment.md"
  assert_rc '表の行にある常体は無視' 0 run_check "$tmpdir/customer/table.md"
  assert_rc '存在しない対象は判定不能' 2 run_check "$tmpdir/customer/no-such-file.md"
  assert_rc '実在対象と存在しない対象の混在は判定不能' 2 \
    run_check "$tmpdir/customer/polite.md" "$tmpdir/customer/no-such-file.md"
  assert_rc 'ディレクトリの文書列挙失敗は判定不能' 2 \
    run_check_with_definition_and_lister "$(_exclusion_json)" \
      fail_markdown_file_listing "$tmpdir/customer"
  assert_rc '文書読み取り失敗は判定不能' 2 scan_file "$tmpdir/customer/no-such-file.md"
  assert_contains '文書読み取り失敗はUNKNOWNを出力' '[UNKNOWN]' \
    scan_file "$tmpdir/customer/no-such-file.md"
  assert_rc '存在しない除外定義は判定不能' 2 \
    run_check_with_definition "$tmpdir/no-such-exclusions.json" "$tmpdir/customer/polite.md"
  assert_contains '存在しない除外定義はUNKNOWNを出力' '[UNKNOWN]' \
    run_check_with_definition "$tmpdir/no-such-exclusions.json" "$tmpdir/customer/polite.md"
  assert_rc '不正な除外定義は判定不能' 2 \
    run_check_with_definition "$tmpdir/invalid-exclusions.json" "$tmpdir/customer/polite.md"
  assert_rc '不足した依存コマンドは判定不能' 2 _require_command 'document-style-missing-command'
  assert_rc '内部除外と顧客提示文書の混在は合格' 0 run_check "$tmpdir/.claude/skills/sample/SKILL.md" "$tmpdir/customer/polite.md"
  assert_contains '除外件数を出力する' '除外 1 件' run_check "$tmpdir/.claude/skills/sample/SKILL.md" "$tmpdir/customer/polite.md"

  echo "self-test: ${pass} PASS, ${fail} FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  if [ "${1:-}" = '--self-test' ]; then self_test; exit $?; fi
  if [ "$#" -eq 0 ]; then
    echo "使い方: $0 <ファイルまたはディレクトリ...> | --self-test" >&2
    exit 2
  fi
  run_check "$@"
}

main "$@"
