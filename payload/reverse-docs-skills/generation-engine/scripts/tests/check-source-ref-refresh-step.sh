#!/usr/bin/env bash
# check-source-ref-refresh-step.sh — 配る開発フローの Phase5 に、実装変更へ
# 追従して設計書の source_ref を更新する段と完了記録欄があるかを検査する。
#
# 使い方:
#   bash generation-engine/scripts/tests/check-source-ref-refresh-step.sh
#   bash generation-engine/scripts/tests/check-source-ref-refresh-step.sh --check-mechanized-selection
#   bash generation-engine/scripts/tests/check-source-ref-refresh-step.sh --check-detection-link
#   bash generation-engine/scripts/tests/check-source-ref-refresh-step.sh --self-test
#
# 必要性・代替案を採用しなかった理由・保守責任者・廃棄条件は、正本
# docs/rules/portal/page-conventions/rule.md の「check-source-ref-refresh-step.sh」を参照する。
# macOS bash 3.2 互換（連想配列・mapfile は使わない）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/delivery-payload/templates/delivered-skills/dev-flow/SKILL.md"
SELF_TEST_TMP=""
REFRESH_SECTION=""
NORMALIZED_REFRESH_SECTION=""
STEP1=""
STEP2=""
STEP3=""
STEP4=""

EXPECTED_INTRO='実装と動作確認が終わったら、規約レビューと統合の前に次を実行する。この段へ入る前に、実装を含むローカルコミットを作成し、そのコミットを `HEAD` にする。後述の種別別拡張マニフェストから解決した実装パス集合 `<パス>` のいずれかに `git diff --name-only HEAD -- <パス>` が残る場合は、未コミットの実装を見落とすため `[UNKNOWN]`（終了コード2相当）とする。'
EXPECTED_STEP1='1. `reverse-docs-engine/delivery-payload/references/output-layout.json` で7種別の `<kind>UnitRoot` と `<kind>ManifestExt` を解決し、各ユニットルート配下の全詳細設計書を機械的に列挙する。各詳細設計書のfrontmatterから比較元の `source_ref` を全長40桁のコミットとして読む一方、実装パス集合 `<パス>` は `source_ref` から得ず、種別別拡張マニフェストから独立に解決する。非画面6種別は詳細設計書の `detailDocPath` または設計単位のキーと `units[].unitKey` を結び、対応する `files` と、既存契約にある場合は `sourceFile` を実装パス集合にする。画面は設計単位の `screenKey` または `screenId` と `screens[]` を結び、対応する `files` と `entryFile` を実装パス集合にする。全設計書を人手なしで列挙・joinし、集合内の各 `<パス>` へ `git diff --name-only <source_ref>..HEAD -- <パス>` を実行する。1件以上の変更が出た設計単位を `[STALE]`、変更が無ければ `[FRESH]` と判定する。設計書とマニフェストの対応欠落、複数候補の矛盾、実装パス集合の空、`source_ref` の欠落または全長40桁のコミットとして解決不能、実装パスの欠落、未コミット差分、またはコマンド失敗は `[UNKNOWN]`（終了コード2相当）とする'
EXPECTED_STEP2='2. `[STALE]` の場合は、差分判定が選んだ設計単位の詳細設計書をすべて更新し、それぞれの `source_ref` を `git rev-parse HEAD` の全長40桁のコミットへ置き換える。`output-layout.json`、種別別拡張マニフェストとのjoin、差分判定が対象を決めるため、人が対象実装パスや設計単位を再選択しない'
EXPECTED_STEP3='3. 更新した設計書を実装と同じ変更へ含める。`[FRESH]` の場合は、差分が無く影響しないと判定した設計単位と根拠を完了記録へ残す'
EXPECTED_STEP4='4. `[UNKNOWN]` または更新の失敗時は統合せず、原因を解消して同じ鮮度判定を再実行する'
EXPECTED_DETECTION='更新後に `/maintaining-portal --mode regenerate --root "$PWD" --source-root "$PWD"` で一覧とポータルの表示値を作り直し、`bash reverse-docs-engine/generation-engine/scripts/check-derived-values.sh "$PWD" --commits-only` を実行する。「表示コミット-ポータル」または「表示コミット-画面」が検知された場合は統合せず、本段へ戻る。鮮度判定、`source_ref` の更新、同じ `/maintaining-portal --mode regenerate`、表示コミットの検査を順に再実行する。'
EXPECTED_RECORD_LINE='| 設計書 | <更新した場合は「更新: `<設計単位のキーと更新後のコミット（全長40桁）の一覧>`」、更新しなかった場合は「影響なし: <鮮度判定が示した根拠>」> |'

run_awk_capture() {
  local label="$1" rc output
  shift
  if [ "${SOURCE_REF_TEST_FAIL_COMMAND:-}" = "awk" ]; then
    echo "[UNKNOWN] ${label}でawkの故障を検知したため判定できません" >&2
    return 2
  fi
  output="$(awk "$@" 2>&1)"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "[UNKNOWN] ${label}でawkが失敗したため判定できません: $output" >&2
    return 2
  fi
  CAPTURED_OUTPUT="$output"
  return "$rc"
}

run_awk_text_capture() {
  local label="$1" input="$2" rc output
  shift 2
  if [ "${SOURCE_REF_TEST_FAIL_COMMAND:-}" = "awk" ]; then
    echo "[UNKNOWN] ${label}でawkの故障を検知したため判定できません" >&2
    return 2
  fi
  output="$(awk "$@" <<< "$input" 2>&1)"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "[UNKNOWN] ${label}でawkが失敗したため判定できません: $output" >&2
    return 2
  fi
  CAPTURED_OUTPUT="$output"
  return "$rc"
}

grep_text() {
  local mode="$1" pattern="$2" text_value="$3" rc
  if [ "${SOURCE_REF_TEST_FAIL_COMMAND:-}" = "grep" ]; then
    echo "[UNKNOWN] 意味検査でgrepの故障を検知したため判定できません" >&2
    return 2
  fi
  if [ "$mode" = "fixed" ]; then
    grep -qF "$pattern" <<< "$text_value"
  else
    grep -qE "$pattern" <<< "$text_value"
  fi
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "[UNKNOWN] 意味検査でgrepが失敗したため判定できません" >&2
    return 2
  fi
  return "$rc"
}

load_refresh_section() {
  local file="$1" rc
  check_readable "$file" || return $?
  run_awk_capture "更新の段の抽出" '
    /^[[:space:]]*(```|~~~)/ {
      if (capture == 1) print
      in_fence = !in_fence
      next
    }
    in_fence == 1 {
      if (capture == 1) print
      next
    }
    /^## Phase5 / { in_phase5 = 1 }
    in_phase5 == 1 && /^## / && $0 !~ /^## Phase5 / { in_phase5 = 0 }
    $0 == "### 設計書の表示コミットを更新する" {
      total++
      if (in_phase5 == 1) {
        phase5_total++
        capture = 1
        print
        next
      }
    }
    capture == 1 && /^### / {
      if ($0 == "### 入口のページを更新する") immediately_before_entry = 1
      capture = 0
      next
    }
    capture == 1 { print }
    END {
      if (total != 1 || phase5_total != 1 || immediately_before_entry != 1) exit 1
    }
  ' "$file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$rc" in
      2) return 2 ;;
      *) echo "[FAIL] 更新の段は文書内に1件だけ存在し、Phase5内の「入口のページを更新する」直前でなければなりません"; return 1 ;;
    esac
  fi
  REFRESH_SECTION="$CAPTURED_OUTPUT"
}

extract_numbered_step() {
  local section="$1" number="$2"
  run_awk_text_capture "番号付き手順の抽出" "$section" -v number="$number" '
    $0 ~ ("^" number "\\.") { in_step = 1 }
    in_step == 1 && $0 ~ "^[1-4]\\." && $0 !~ ("^" number "\\.") { exit }
    in_step == 1 && NF {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      printf "%s", $0
    }
    END { print "" }
  ' || return $?
  printf '%s\n' "$CAPTURED_OUTPUT"
}

normalize_text() {
  run_awk_text_capture "section正規化" "$1" 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); printf "%s", $0 } END { print "" }' || return $?
  printf '%s\n' "$CAPTURED_OUTPUT"
}

check_readable() {
  local file="$1"
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "[UNKNOWN] SKILL.mdを読み取れないため判定できません: $file" >&2
    return 2
  fi
}

check_section_grammar() {
  local expected actual rc
  expected="### 設計書の表示コミットを更新する$EXPECTED_INTRO$EXPECTED_STEP1$EXPECTED_STEP2$EXPECTED_STEP3$EXPECTED_STEP4$EXPECTED_DETECTION"
  actual="$(normalize_text "$REFRESH_SECTION")"
  rc=$?
  if [ "$rc" -ne 0 ]; then return 2; fi
  NORMALIZED_REFRESH_SECTION="$actual"
  if [ "$actual" != "$expected" ]; then
    echo "[FAIL] 更新の段がcanonical section grammarと一致しません（余分な非空文、欠落、または順序違反があります）"
    return 1
  fi
}

prepare_refresh_context() {
  local file="$1" rc
  load_refresh_section "$file" || return $?
  check_section_grammar || return $?
  STEP1="$(extract_numbered_step "$REFRESH_SECTION" 1)"; rc=$?; if [ "$rc" -ne 0 ]; then return 2; fi
  STEP2="$(extract_numbered_step "$REFRESH_SECTION" 2)"; rc=$?; if [ "$rc" -ne 0 ]; then return 2; fi
  STEP3="$(extract_numbered_step "$REFRESH_SECTION" 3)"; rc=$?; if [ "$rc" -ne 0 ]; then return 2; fi
  STEP4="$(extract_numbered_step "$REFRESH_SECTION" 4)"; rc=$?; if [ "$rc" -ne 0 ]; then return 2; fi
}

check_step_present() {
  local file="$1" rc
  check_readable "$file" || return $?
  if [ -z "$REFRESH_SECTION" ]; then
    echo "[FAIL] 見出し「設計書の表示コミットを更新する」がありません"
    return 1
  fi
  grep_text fixed '`source_ref`' "$REFRESH_SECTION"
  rc=$?
  if [ "$rc" -eq 2 ]; then return 2; fi
  if [ "$rc" -ne 0 ]; then
    echo "[FAIL] 更新の段に source_ref の記述がありません"
    return 1
  fi
  run_awk_capture "完了記録の設計書欄の検査" -v "expected=$EXPECTED_RECORD_LINE" '
    /^[[:space:]]*(```|~~~)/ { in_fence = !in_fence; next }
    in_fence == 1 {
      if (in_completion == 1 && $0 == expected) exact++
      if (in_completion == 1 && $0 ~ /^\| 設計書 \|/) design_rows++
      next
    }
    $0 == "### 完了の記録" { in_completion = 1; found_section++; next }
    in_completion == 1 && /^### / { in_completion = 0 }
    in_completion == 1 && /^## / { in_completion = 0 }
    in_completion == 1 && $0 == expected { exact++ }
    in_completion == 1 && /^\| 設計書 \|/ { design_rows++ }
    END { exit(found_section == 1 && exact == 1 && design_rows == 1 ? 0 : 1) }
  ' "$file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 2 ]; then return 2; fi
    echo "[FAIL] 完了記録の設計書欄がcanonical exact formatと一致しません"
    return 1
  fi
  echo "[PASS] source_ref 更新の段と完了記録の設計書欄があります"
}

check_mechanized_selection() {
  if [ -z "$REFRESH_SECTION" ]; then
    echo "[FAIL] 更新対象の機械選択を記述する段がありません"
    return 1
  fi
  if [ "$STEP1" != "$EXPECTED_STEP1" ] || [ "$STEP2" != "$EXPECTED_STEP2" ] || [ "$STEP3" != "$EXPECTED_STEP3" ] || [ "$STEP4" != "$EXPECTED_STEP4$EXPECTED_DETECTION" ]; then
    echo "[FAIL] 番号付き手順の意味関係がcanonical grammarと一致しません"
    return 1
  fi
  echo "[PASS] output-layout.json と差分判定により更新対象を機械選択します"
}

check_detection_link() {
  local rc
  if [ -z "$REFRESH_SECTION" ]; then
    echo "[FAIL] 検知後の対処先となる更新の段がありません"
    return 1
  fi
  grep_text fixed "$EXPECTED_DETECTION" "$NORMALIZED_REFRESH_SECTION"
  rc=$?
  if [ "$rc" -eq 2 ]; then return 2; fi
  if [ "$rc" -ne 0 ]; then
    echo "[FAIL] 再生成、表示コミット検査、不一致時の統合禁止と更新段への復帰が一連の動作として記述されていません"
    return 1
  fi
  echo "[PASS] check-derived-values.sh の検知結果から更新の段へ辿れます"
}

run_step_check() {
  local file="$1"
  prepare_refresh_context "$file" || return $?
  check_step_present "$file"
}

run_mechanized_check() {
  local file="$1"
  prepare_refresh_context "$file" || return $?
  check_mechanized_selection
}

run_detection_check() {
  local file="$1"
  prepare_refresh_context "$file" || return $?
  check_detection_link
}

run_forced_internal_failure() {
  local command_name="$1" file="$2"
  SOURCE_REF_TEST_FAIL_COMMAND="$command_name" run_all "$file"
}

run_all() {
  local file="$1" rc=0 unknown=0 result
  prepare_refresh_context "$file" || return $?
  for result in check_step_present check_mechanized_selection check_detection_link; do
    if [ "$result" = "check_step_present" ]; then
      "$result" "$file"
    else
      "$result"
    fi
    case $? in
      0) ;;
      2) unknown=1 ;;
      *) rc=1 ;;
    esac
  done
  if [ "$unknown" -ne 0 ]; then
    return 2
  fi
  if [ "$rc" -ne 0 ]; then
    echo "[FAIL] source_ref 更新手順の検査に不合格があります"
    return 1
  fi
  echo "[PASS] source_ref 更新手順の全検査に合格しました"
}

cleanup_self_test_tmp() {
  if [ -n "$SELF_TEST_TMP" ] && [ -d "$SELF_TEST_TMP" ]; then
    rm -rf "$SELF_TEST_TMP"
  fi
}

run_self_test() {
  if [ "${SOURCE_REF_SELF_TEST_FORCE_UNKNOWN:-0}" = "1" ]; then
    echo "[UNKNOWN] 故障注入により自己テストを判定不能として終了します" >&2
    return 2
  fi
  if ! SELF_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-source-ref-refresh-step.XXXXXX" 2>/dev/null)" || [ -z "$SELF_TEST_TMP" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため自己テストを実行できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）" >&2
    return 2
  fi
  trap cleanup_self_test_tmp EXIT

  local pass=0 fail=0 unknown=0 fixture no_step no_record misplaced_record sibling_record negated_record no_selection keyword_salad numbered_keyword_salad multiline_valid reverse_join no_link detection_keyword_salad overridden_step excluded_step unneeded_step safe_override wrong_phase wrong_position duplicate_before_phase fenced_section extra_sentence
  fixture="$SELF_TEST_TMP/complete.md"
  if ! cp "$SKILL_MD" "$fixture" || [ ! -s "$fixture" ]; then
    echo "[UNKNOWN] 実物のSKILL.mdを自己テスト用に複製できないため判定できません（cpが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi

  assert_pass() {
    local label="$1" rc out
    shift
    out="$("$@" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      pass=$((pass + 1))
    elif [ "$rc" -eq 2 ]; then
      unknown=1
      echo "[UNKNOWN] self-test: ${label}: ${out}" >&2
    else
      fail=$((fail + 1))
      echo "  [FAIL] self-test: ${label}（合格を期待）"
    fi
  }
  assert_fail() {
    local label="$1" rc out
    shift
    out="$("$@" 2>&1)"
    rc=$?
    if [ "$rc" -eq 1 ]; then
      pass=$((pass + 1))
    elif [ "$rc" -eq 2 ]; then
      unknown=1
      echo "[UNKNOWN] self-test: ${label}: ${out}" >&2
    else
      fail=$((fail + 1))
      echo "  [FAIL] self-test: ${label}（終了コード1を期待、実際: ${rc}）"
    fi
  }
  assert_unknown() {
    local label="$1" rc out
    shift
    out="$("$@" 2>&1)"
    rc=$?
    if [ "$rc" -eq 2 ]; then
      case "$out" in
        *'[UNKNOWN]'*) pass=$((pass + 1)); return ;;
      esac
    fi
    fail=$((fail + 1))
    echo "  [FAIL] self-test: ${label}（[UNKNOWN]と終了コード2を期待、実際: ${rc}）"
  }

  assert_pass "実物は全検査に合格する" run_all "$fixture"
  assert_pass "実物は機械選択検査に合格する" run_mechanized_check "$fixture"
  assert_pass "実物は検知リンク検査に合格する" run_detection_check "$fixture"

  no_step="$SELF_TEST_TMP/no-step.md"
  if ! sed '/^### 設計書の表示コミットを更新する$/,/^### /{/^### 入口のページを更新する$/!d;}' "$fixture" > "$no_step" || [ ! -s "$no_step" ]; then
    echo "[UNKNOWN] 段欠落の自己テスト入力を作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "更新の段が無ければ不合格になる" run_step_check "$no_step"

  no_record="$SELF_TEST_TMP/no-record.md"
  if ! grep -vF '| 設計書 |' "$fixture" > "$no_record" || [ ! -s "$no_record" ]; then
    echo "[UNKNOWN] 欄欠落の自己テスト入力を作れないため判定できません（grepが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "完了記録の設計書欄が無ければ不合格になる" run_step_check "$no_record"

  misplaced_record="$SELF_TEST_TMP/misplaced-record.md"
  if ! grep -vF '| 設計書 |' "$fixture" > "$misplaced_record" || [ ! -s "$misplaced_record" ]; then
    echo "[UNKNOWN] 欄移設の自己テスト入力を作れないため判定できません（grepが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  if ! printf '\n| 設計書 | 更新後のコミット / 影響なし: 理由 |\n' >> "$misplaced_record"; then
    echo "[UNKNOWN] 欄移設の自己テスト入力を作れないため判定できません（printfが失敗しました）" >&2
    return 2
  fi
  assert_fail "設計書欄が完了記録の外なら不合格になる" run_step_check "$misplaced_record"

  sibling_record="$SELF_TEST_TMP/sibling-record.md"
  if ! awk -v expected="$EXPECTED_RECORD_LINE" '
    $0 == expected { next }
    /^ファイルを新規作成する場合/ && inserted == 0 {
      print "### 別の完了欄"
      print ""
      print expected
      print ""
      inserted = 1
    }
    { print }
    END { if (inserted == 0) exit 2 }
  ' "$fixture" > "$sibling_record" || [ ! -s "$sibling_record" ]; then
    echo "[UNKNOWN] 兄弟H3へ移した完了記録fixtureを作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "canonical行が完了記録の兄弟H3配下なら不合格になる" run_step_check "$sibling_record"

  negated_record="$SELF_TEST_TMP/negated-record.md"
  if ! sed 's/更新しなかった場合は「影響なし:/更新しなかった場合も「更新不要:/' "$fixture" > "$negated_record" || [ ! -s "$negated_record" ]; then
    echo "[UNKNOWN] 否定文の完了記録fixtureを作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "完了記録の設計書欄を否定文へ変えたら不合格になる" run_step_check "$negated_record"

  no_selection="$SELF_TEST_TMP/no-selection.md"
  if ! sed 's/git diff --name-only/git diff --stat/' "$fixture" > "$no_selection" || [ ! -s "$no_selection" ]; then
    echo "[UNKNOWN] 機械選択欠落の自己テスト入力を作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "差分判定が無ければ機械選択検査は不合格になる" run_mechanized_check "$no_selection"

  keyword_salad="$SELF_TEST_TMP/keyword-salad.md"
  if ! {
    echo '### 設計書の表示コミットを更新する'
    echo 'output-layout.json 7種別 <kind>UnitRoot <kind>ManifestExt 全詳細設計書を機械的に列挙 frontmatterから比較元の `source_ref` を全長40桁のコミットとして読む 実装パス集合 `<パス>` は `source_ref` から得ず 種別別拡張マニフェストから独立に解決 detailDocPath units[].unitKey `files` `sourceFile` `screenKey` `screenId` `screens[]` `entryFile` 全設計書を人手なしで列挙・join git diff --name-only <source_ref>..HEAD -- <パス> git diff --name-only HEAD -- <パス> 実装を含むローカルコミット 対応欠落 複数候補の矛盾 実装パス集合の空 未コミット差分 終了コード2相当 人が対象実装パスや設計単位を再選択しない git rev-parse HEAD 全長40桁のコミット [STALE] [FRESH] [UNKNOWN]'
  } > "$keyword_salad" || [ ! -s "$keyword_salad" ]; then
    echo "[UNKNOWN] キーワード羅列の自己テスト入力を作れないため判定できません（brace出力が失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "必須語の羅列だけなら機械選択検査は不合格になる" run_mechanized_check "$keyword_salad"

  numbered_keyword_salad="$SELF_TEST_TMP/numbered-keyword-salad.md"
  if ! {
    echo '### 設計書の表示コミットを更新する'
    echo '1. output-layout.json 7種別 <kind>UnitRoot <kind>ManifestExt 全詳細設計書を機械的に列挙 frontmatterから比較元の `source_ref` を全長40桁のコミットとして読む 実装パス集合 `<パス>` は `source_ref` から得ず 種別別拡張マニフェストから独立に解決 detailDocPath units[].unitKey `files` `sourceFile` `screenKey` `screenId` `screens[]` `entryFile` 全設計書を人手なしで列挙・join git diff --name-only <source_ref>..HEAD -- <パス> git diff --name-only HEAD -- <パス> 実装を含むローカルコミット 対応欠落 複数候補の矛盾 実装パス集合の空 未コミット差分 終了コード2相当 [STALE] [FRESH] [UNKNOWN]'
    echo '2. [STALE] すべて更新 git rev-parse HEAD 全長40桁のコミット 人が対象実装パスや設計単位を再選択しない'
    echo '3. [FRESH] 完了記録'
    echo '4. [UNKNOWN] 統合せず 再実行'
  } > "$numbered_keyword_salad" || [ ! -s "$numbered_keyword_salad" ]; then
    echo "[UNKNOWN] 番号付きキーワード羅列の自己テスト入力を作れないため判定できません（brace出力が失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "手順番号付きでも必須語の羅列だけなら機械選択検査は不合格になる" run_mechanized_check "$numbered_keyword_salad"

  multiline_valid="$SELF_TEST_TMP/multiline-valid.md"
  if ! awk '{
    gsub("。各詳細設計書", "。\n   各詳細設計書")
    gsub("。非画面6種別", "。\n   非画面6種別")
    gsub("。画面は", "。\n   画面は")
    gsub("。全設計書", "。\n   全設計書")
    gsub("置き換える。`output-layout.json`", "置き換える。\n   `output-layout.json`")
    print
  }' "$fixture" > "$multiline_valid" || [ ! -s "$multiline_valid" ]; then
    echo "[UNKNOWN] 複数行手順の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_pass "手順内の意味関係を保った改行だけなら合格する" run_mechanized_check "$multiline_valid"

  reverse_join="$SELF_TEST_TMP/reverse-join.md"
  if ! sed -e 's/非画面6種別/__NON_SCREEN__/' -e 's/画面は設計単位/非画面6種別は設計単位/' -e 's/__NON_SCREEN__/画面/' "$fixture" > "$reverse_join" || [ ! -s "$reverse_join" ]; then
    echo "[UNKNOWN] 逆joinの自己テスト入力を作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "画面と非画面のjoin関係を逆にしたら不合格になる" run_mechanized_check "$reverse_join"

  no_link="$SELF_TEST_TMP/no-link.md"
  if ! sed 's/check-derived-values\.sh/check-values.sh/g' "$fixture" > "$no_link" || [ ! -s "$no_link" ]; then
    echo "[UNKNOWN] 検知リンク欠落の自己テスト入力を作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "検知器へのリンクが無ければ不合格になる" run_detection_check "$no_link"

  detection_keyword_salad="$SELF_TEST_TMP/detection-keyword-salad.md"
  if ! {
    echo '### 設計書の表示コミットを更新する'
    echo 'maintaining-portal --mode regenerate check-derived-values.sh 表示コミット-ポータル 表示コミット-画面 本段へ戻る'
  } > "$detection_keyword_salad" || [ ! -s "$detection_keyword_salad" ]; then
    echo "[UNKNOWN] 検知リンクのキーワード羅列入力を作れないため判定できません（brace出力が失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "検知リンクの必須語を1行に羅列しただけなら不合格になる" run_detection_check "$detection_keyword_salad"

  overridden_step="$SELF_TEST_TMP/overridden-step.md"
  if ! awk '
    BEGIN { in_section = 0; inserted = 0 }
    /^### 設計書の表示コミットを更新する$/ { in_section = 1 }
    in_section == 1 && /^### / && $0 != "### 設計書の表示コミットを更新する" {
      print "上記1〜4は実行せず、担当者が任意選択する"
      inserted = 1
      in_section = 0
    }
    { print }
    END {
      if (in_section == 1) {
        print "上記1〜4は実行せず、担当者が任意選択する"
        inserted = 1
      }
      if (inserted == 0) exit 2
    }
  ' "$fixture" > "$overridden_step" || [ ! -s "$overridden_step" ]; then
    echo "[UNKNOWN] 上書き指示の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "有効な更新段を否定・人手選択の指示で上書きしたら不合格になる" run_all "$overridden_step"

  excluded_step="$SELF_TEST_TMP/excluded-step.md"
  if ! awk '
    BEGIN { in_section = 0; inserted = 0 }
    /^### 設計書の表示コミットを更新する$/ { in_section = 1 }
    in_section == 1 && /^### / && $0 != "### 設計書の表示コミットを更新する" {
      print "ただし、本段は適用対象外とする。更新対象は担当者の裁量で決定する。"
      inserted = 1
      in_section = 0
    }
    { print }
    END {
      if (in_section == 1) {
        print "ただし、本段は適用対象外とする。更新対象は担当者の裁量で決定する。"
        inserted = 1
      }
      if (inserted == 0) exit 2
    }
  ' "$fixture" > "$excluded_step" || [ ! -s "$excluded_step" ]; then
    echo "[UNKNOWN] 適用除外指示の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "有効な更新段を適用除外・担当者裁量で上書きしたら不合格になる" run_all "$excluded_step"

  unneeded_step="$SELF_TEST_TMP/unneeded-step.md"
  if ! awk '
    /^### 入口のページを更新する$/ && inserted == 0 {
      print "本段は実施不要とし、更新対象は担当者が決定する。"
      inserted = 1
    }
    { print }
    END { if (inserted == 0) exit 2 }
  ' "$fixture" > "$unneeded_step" || [ ! -s "$unneeded_step" ]; then
    echo "[UNKNOWN] 実施不要指示の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "実施不要・担当者決定で上書きしたら不合格になる" run_all "$unneeded_step"

  safe_override="$SELF_TEST_TMP/safe-override.md"
  if ! awk '
    /^### 入口のページを更新する$/ && inserted == 0 {
      print "担当者の裁量に委ねず、機械判定へ従う。"
      inserted = 1
    }
    { print }
    END { if (inserted == 0) exit 2 }
  ' "$fixture" > "$safe_override" || [ ! -s "$safe_override" ]; then
    echo "[UNKNOWN] 安全な裁量否定の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "canonical grammar外の裁量否定追記も不合格になる" run_all "$safe_override"

  wrong_phase="$SELF_TEST_TMP/wrong-phase.md"
  if ! sed 's/^## Phase5 実装と動作確認$/## Phase6 実装と動作確認/' "$fixture" > "$wrong_phase" || [ ! -s "$wrong_phase" ]; then
    echo "[UNKNOWN] 別Phase配置の自己テスト入力を作れないため判定できません（sedが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "更新の段がPhase5外なら不合格になる" run_all "$wrong_phase"

  wrong_position="$SELF_TEST_TMP/wrong-position.md"
  if ! awk '
    /^### 入口のページを更新する$/ && inserted == 0 {
      print "### 別の更新段"
      print "別の処理を行う。"
      inserted = 1
    }
    { print }
    END { if (inserted == 0) exit 2 }
  ' "$fixture" > "$wrong_position" || [ ! -s "$wrong_position" ]; then
    echo "[UNKNOWN] 直前配置違反の自己テスト入力を作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "更新の段が入口更新の直前でなければ不合格になる" run_all "$wrong_position"

  duplicate_before_phase="$SELF_TEST_TMP/duplicate-before-phase.md"
  if ! {
    printf '### 設計書の表示コミットを更新する\n\n前方に置いた偽の段。\n\n'
    awk '
      /^### 設計書の表示コミットを更新する$/ { in_target = 1; print; next }
      in_target == 1 && /^### 入口のページを更新する$/ { in_target = 0; print; next }
      in_target == 1 { next }
      { print }
    ' "$fixture"
  } > "$duplicate_before_phase" || [ ! -s "$duplicate_before_phase" ]; then
    echo "[UNKNOWN] 前方同名節とPhase5空節のfixtureを作れないため判定できません（生成コマンドが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "文書前方に同名節がありPhase5側が空でも不合格になる" run_all "$duplicate_before_phase"

  fenced_section="$SELF_TEST_TMP/fenced-section.md"
  if ! awk '
    /^### 設計書の表示コミットを更新する$/ && opened == 0 {
      print "```markdown"
      opened = 1
    }
    { print }
    /^### 入口のページを更新する$/ && opened == 1 && closed == 0 {
      print "```"
      closed = 1
    }
    END { if (opened == 0 || closed == 0) exit 2 }
  ' "$fixture" > "$fenced_section" || [ ! -s "$fenced_section" ]; then
    echo "[UNKNOWN] コードフェンス内sectionのfixtureを作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "コードフェンス内の同名見出しは実効sectionとして扱わない" run_all "$fenced_section"

  extra_sentence="$SELF_TEST_TMP/extra-sentence.md"
  if ! awk '
    /^### 入口のページを更新する$/ && inserted == 0 {
      print "判定結果を参考に、最終的な対象は状況に応じて調整する。"
      inserted = 1
    }
    { print }
    END { if (inserted == 0) exit 2 }
  ' "$fixture" > "$extra_sentence" || [ ! -s "$extra_sentence" ]; then
    echo "[UNKNOWN] 任意言い換え追記のfixtureを作れないため判定できません（awkが失敗したか、空の入力を生成しました）" >&2
    return 2
  fi
  assert_fail "canonical grammar外の任意の非空追記は不合格になる" run_all "$extra_sentence"

  assert_unknown "存在しない入力は判定不能になる" run_step_check "$SELF_TEST_TMP/missing.md"
  assert_unknown "section抽出awkの失敗はUNKNOWNとして伝播する" run_forced_internal_failure awk "$fixture"
  assert_unknown "意味検査grepの失敗はUNKNOWNとして伝播する" run_forced_internal_failure grep "$fixture"
  assert_unknown "self-test driverは故障注入のUNKNOWNと終了コード2を伝播する" env SOURCE_REF_SELF_TEST_FORCE_UNKNOWN=1 bash "$0" --self-test

  if [ "$unknown" -ne 0 ]; then
    echo "[UNKNOWN] self-test内の検査が判定不能になりました" >&2
    return 2
  fi
  echo "self-test: PASS=${pass} FAIL=${fail}"
  [ "$fail" -eq 0 ]
}

main() {
  case "${1:-}" in
    "") run_all "$SKILL_MD" ;;
    --check-mechanized-selection) run_mechanized_check "$SKILL_MD" ;;
    --check-detection-link) run_detection_check "$SKILL_MD" ;;
    --self-test) run_self_test ;;
    *)
      echo "ERROR: unrecognized argument: $1" >&2
      return 1
      ;;
  esac
}

main "$@"
