#!/usr/bin/env bash
# 作業課題一覧の状態と、対応する指示書の実際の置き場を照合する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER="$REPO_ROOT/docs/tasks/作業課題一覧.md"
TASKS_DIR="$REPO_ROOT/docs/tasks"

check_ledger() {
  local ledger="$1"
  local tasks_dir="$2"

  if [ ! -f "$ledger" ] || [ ! -d "$tasks_dir" ] || [ ! -d "$tasks_dir/done" ]; then
    echo "[UNKNOWN] 台帳または指示書の置き場を読み取れないため判定できません: $ledger / $tasks_dir" >&2
    return 2
  fi

  local checked=0
  local mismatches=0
  local skipped=0
  local name state direct_exists done_exists

  while IFS=$'\t' read -r name state; do
    [ -n "$name" ] || continue
    checked=$((checked + 1))

    case "$name" in
      *.md)
        # 見出しが指示書ファイル名の形（.md終わり）の項目だけ、実在確認の対象にする。
        direct_exists=0
        done_exists=0
        if [ -f "$tasks_dir/$name" ]; then
          direct_exists=1
        fi
        if [ -f "$tasks_dir/done/$name" ]; then
          done_exists=1
        fi

        if [ "$direct_exists" -eq 1 ] && [ "$done_exists" -eq 0 ]; then
          # 状態は前方一致で判定する。「完了（コミット: ...）」のように括弧で
          # 実測内容を書き添える記法（instruction-format/rule.md が許容する形）を
          # 完全一致にすると誤って不合格にするため。
          case "$state" in
            完了*)
              echo "[FAIL] 直下にあるのに状態が完了です: $name"
              mismatches=$((mismatches + 1))
              ;;
          esac
        elif [ "$direct_exists" -eq 0 ] && [ "$done_exists" -eq 1 ]; then
          case "$state" in
            完了*) : ;;
            *)
              echo "[FAIL] done/ にあるのに状態が完了ではありません: ${name}（状態=${state:-なし}）"
              mismatches=$((mismatches + 1))
              ;;
          esac
        elif [ "$direct_exists" -eq 1 ] && [ "$done_exists" -eq 1 ]; then
          echo "[FAIL] 直下と done/ の両方にあります: $name"
          mismatches=$((mismatches + 1))
        else
          echo "[FAIL] 直下にも done/ にもありません: $name"
          mismatches=$((mismatches + 1))
        fi
        ;;
      *)
        # 見出しが .md で終わらない項目は、指示書ファイルを持たない
        # （旧番号の台帳から移した項目等）。実在確認は対象外とし、
        # 状態の値だけを検査する（定めた5つの語のいずれかで始まること）。
        skipped=$((skipped + 1))
        case "$state" in
          未着手*|対応中*|完了*|対象外*|未確認*) : ;;
          *)
            echo "[FAIL] 対象外項目の状態が定めた語で始まりません: ${name}（状態=${state:-なし}）"
            mismatches=$((mismatches + 1))
            ;;
        esac
        ;;
    esac
  done < <(awk '
    /^### / {
      if (name != "") print name "\t" state
      name = substr($0, 5)
      state = ""
      next
    }
    name != "" && state == "" && /^\*\*状態\*\*: / {
      state = $0
      sub(/^\*\*状態\*\*: /, "", state)
    }
    END { if (name != "") print name "\t" state }
  ' "$ledger")

  if [ "$checked" -eq 0 ]; then
    echo "[FAIL] 台帳の見出しが0件です"
    return 1
  fi
  if [ "$mismatches" -ne 0 ]; then
    echo "[FAIL] 台帳と置き場の食い違い=${mismatches}件（確認=${checked}件、対象外=${skipped}件（指示書を持たない項目））"
    return 1
  fi

  echo "[PASS] 台帳と置き場の食い違い=0件（確認=${checked}件、対象外=${skipped}件（指示書を持たない項目））"
}

record_self_test() {
  local name="$1"
  local expected="$2"
  local ledger="$3"
  local tasks_dir="$4"
  local actual
  if (check_ledger "$ledger" "$tasks_dir") >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" -eq "$expected" ]; then
    echo "  [PASS] $name"
    SELF_TEST_PASS=$((SELF_TEST_PASS + 1))
  else
    echo "  [FAIL] ${name}（終了コード=${actual}、期待=${expected}）"
    SELF_TEST_FAIL=$((SELF_TEST_FAIL + 1))
  fi
}

run_self_test() {
  local tmpdir=""
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  trap 'if [ -n "${tmpdir:-}" ]; then rm -rf "$tmpdir"; fi' EXIT

  mkdir -p "$tmpdir/tasks/done"
  touch "$tmpdir/tasks/進行中指示書.md"
  touch "$tmpdir/tasks/done/完了済み指示書.md"

  local valid="$tmpdir/valid.md"
  local direct_mismatched="$tmpdir/direct-mismatched.md"
  local done_mismatched="$tmpdir/done-mismatched.md"
  local direct_mismatched_paren="$tmpdir/direct-mismatched-paren.md"
  local done_valid_paren="$tmpdir/done-valid-paren.md"
  local missing_md_heading="$tmpdir/missing-md-heading.md"
  local no_file_valid="$tmpdir/no-file-valid.md"
  local no_file_invalid_state="$tmpdir/no-file-invalid-state.md"

  printf '%s\n' \
    '### 進行中指示書.md' \
    '**状態**: 着手できる' \
    '' \
    '### 完了済み指示書.md' \
    '**状態**: 完了' > "$valid"
  printf '%s\n' \
    '### 進行中指示書.md' \
    '**状態**: 完了' \
    > "$direct_mismatched"
  printf '%s\n' \
    '### 完了済み指示書.md' \
    '**状態**: 着手できる' > "$done_mismatched"
  # 直し2: 括弧で実測内容を書き添えた「完了（...）」も前方一致で「完了」と
  # 判定されるべき。直下にあるのに括弧付き完了は不合格のままであること。
  printf '%s\n' \
    '### 進行中指示書.md' \
    '**状態**: 完了（コミット: abc1234）' \
    > "$direct_mismatched_paren"
  # done/ にあり、括弧付き完了は合格になること（完全一致では不合格になっていた退行の検知）。
  printf '%s\n' \
    '### 完了済み指示書.md' \
    '**状態**: 完了（コミット: abc1234。追加の実測: 再確認済み）' > "$done_valid_paren"
  # 直し1: 見出しが .md で終わるのに直下にも done/ にも無い項目は、引き続き不合格。
  printf '%s\n' \
    '### 存在しない指示書.md' \
    '**状態**: 未着手' > "$missing_md_heading"
  # 直し1: 見出しが .md で終わらない項目（指示書を持たない項目）は実在確認を飛ばし、
  # 定めた5語のいずれかで始まる状態なら合格。
  printf '%s\n' \
    '### 指示書を持たない課題の要約' \
    '**状態**: 未着手' > "$no_file_valid"
  # 直し1: 指示書を持たない項目でも、状態が定めた5語のいずれでも始まらなければ不合格。
  printf '%s\n' \
    '### 指示書を持たない課題の要約2' \
    '**状態**: 確認済み' > "$no_file_invalid_state"

  SELF_TEST_PASS=0
  SELF_TEST_FAIL=0
  record_self_test "正常な台帳" 0 "$valid" "$tmpdir/tasks"
  record_self_test "直下なのに完了の台帳" 1 "$direct_mismatched" "$tmpdir/tasks"
  record_self_test "done/ なのに未完了の台帳" 1 "$done_mismatched" "$tmpdir/tasks"
  record_self_test "直下なのに括弧付き完了の台帳" 1 "$direct_mismatched_paren" "$tmpdir/tasks"
  record_self_test "done/ で括弧付き完了の台帳（前方一致で合格）" 0 "$done_valid_paren" "$tmpdir/tasks"
  record_self_test "見出しが.md終わりで両方に無い台帳" 1 "$missing_md_heading" "$tmpdir/tasks"
  record_self_test "指示書を持たない項目（状態が定めた語）" 0 "$no_file_valid" "$tmpdir/tasks"
  record_self_test "指示書を持たない項目（状態が定めた語でない）" 1 "$no_file_invalid_state" "$tmpdir/tasks"

  local total=$((SELF_TEST_PASS + SELF_TEST_FAIL))
  echo "実行 ${total} 件 / 成功 ${SELF_TEST_PASS} 件 / 失敗 ${SELF_TEST_FAIL} 件"
  local result=0
  [ "$SELF_TEST_FAIL" -eq 0 ] || result=1
  rm -rf "$tmpdir"
  tmpdir=""
  trap - EXIT
  return "$result"
}

case "${1:-}" in
  "") check_ledger "$LEDGER" "$TASKS_DIR" ;;
  --self-test) run_self_test ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
