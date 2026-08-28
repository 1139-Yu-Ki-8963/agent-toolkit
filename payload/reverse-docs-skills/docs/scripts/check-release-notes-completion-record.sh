#!/usr/bin/env bash
# check-release-notes-completion-record.sh — 1-269の判定表「4. 自己テストに
# 版の置き換えケースがありPASS」「5. 台帳の文言とsamplesへの検査結果が
# 記録されている」の確かめる手段を機械化する。
#
# 背景: 更新履歴（release-notes）ページが永続化した入力から作り直され、
# 旧版が新版へ置き換わることは build-portal.sh --self-test --case 48
# （run_prepared_detail_pages_self_test）のケース52として既に実装済みで
# ある。このケースが実際にPASSするかどうかは、ケースの中身を読んで判断
# する対象ではなく、実行して「PASS: --self-test ケース52」という決まった
# 行が出るかどうかで機械的に確定できる。同様に、台帳
# （docs/tasks/指摘改善一覧.md）の1-203の完了条件に「既に生成済みの納品物へ
# 検査を当てて0件になる」旨の文言が実在すること、および samples への検査
# 結果が本指示書自身の記録として残っていることは、記録の有無という一点
# だけを見れば機械的に確定できる。趣旨の評価そのものは対象にしない。
#
# 使い方:
#   bash docs/scripts/check-release-notes-completion-record.sh                  全検査
#   bash docs/scripts/check-release-notes-completion-record.sh --replacement-case
#   bash docs/scripts/check-release-notes-completion-record.sh --ledger-wording
#   bash docs/scripts/check-release-notes-completion-record.sh --samples-record
#   bash docs/scripts/check-release-notes-completion-record.sh --self-test      自己テスト
#
# 終了コード: 0=合格。1=不合格。2=判定不能。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_PORTAL="$REPO_ROOT/generation-engine/scripts/build-portal.sh"
LEDGER="$REPO_ROOT/docs/tasks/指摘改善一覧.md"
INSTRUCTION_DOC="$REPO_ROOT/docs/tasks/更新履歴ページの永続化漏れと検収を生成済み納品物へ当てる指示書.md"

LEDGER_HEADING="### 1-203."
LEDGER_PHRASE="既に生成済みの納品物へ検査を当てて0件になる"

# 判定4: build-portal.sh --self-test --case 48 を実際に走らせ、
# 版の置き換えケース（ケース52）のPASS行が出るかを見る。
check_replacement_case() {
  if [ ! -f "$BUILD_PORTAL" ]; then
    echo "[UNKNOWN] 対象ファイルが存在しません: $BUILD_PORTAL" >&2
    return 2
  fi
  local log
  if ! log="$(bash "$BUILD_PORTAL" --self-test --case 48 2>&1)"; then
    :
  fi
  if printf '%s\n' "$log" | grep -qF "PASS: --self-test ケース52"; then
    echo "合格: ケース52（版の置き換え）がPASSした"
    return 0
  fi
  echo "不合格: ケース52（版の置き換え）のPASS行が見つからない"
  printf '%s\n' "$log" | tail -20
  return 1
}

# 台帳(指摘改善一覧.md)の1-203ブロック内に、完了条件の文言があるかを見る。
check_ledger_wording() {
  local file="$1" heading="$2" phrase="$3" block
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] 対象ファイルが存在しません: $file" >&2
    return 2
  fi
  block="$(awk -v h="$heading" '
    index($0, h) == 1 { infile = 1 }
    infile && /^### / && index($0, h) != 1 { infile = 0 }
    infile { print }
  ' "$file")"
  if [ -z "$block" ]; then
    echo "不合格: 見出し「${heading}」が見つかりません"
    return 1
  fi
  if printf '%s\n' "$block" | grep -qF "$phrase"; then
    echo "合格: 台帳の${heading}に完了条件の文言がある"
    return 0
  fi
  echo "不合格: 台帳の${heading}に完了条件の文言が無い"
  return 1
}

# 指示書自身の対応の記録に、samplesへの検査結果（件数・FAIL件数・対象種別）
# が記録されているかを見る。
check_samples_record() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "[UNKNOWN] 対象ファイルが存在しません: $file" >&2
    return 2
  fi
  if grep -qE 'generation-engine/samples.*FAIL0?件' "$file" \
    && grep -qF "リリースノート" "$file"; then
    echo "合格: samplesへの検査結果の記録がある"
    return 0
  fi
  echo "不合格: samplesへの検査結果の記録が見つからない"
  return 1
}

self_test() {
  local work fail=0
  if ! work="$(mktemp -d "${TMPDIR:-/tmp}/check-release-notes-completion-record-test.XXXXXX" \
      2>/dev/null)" || [ -z "$work" ]; then
    echo "[UNKNOWN] 自己テスト用の一時領域を作成できません" >&2
    return 2
  fi
  trap 'rm -rf "$work"' RETURN

  # --- check_ledger_wording ---
  cat > "$work/ledger-ok.md" <<'EOF'
### 1-203. ポータルの実走検証が2件の不合格を出す

**完了条件**: 生成器側の修正に加え、既に生成済みの納品物へ検査を当てて0件になることを完了条件へ含める。

### 1-204. 次の項目
EOF
  if check_ledger_wording "$work/ledger-ok.md" "$LEDGER_HEADING" "$LEDGER_PHRASE" >/dev/null; then
    echo "PASS: 台帳の文言ありを合格と判定した"
  else
    echo "FAIL: 台帳の文言ありを不合格と誤判定した" >&2
    fail=1
  fi

  cat > "$work/ledger-missing.md" <<'EOF'
### 1-203. ポータルの実走検証が2件の不合格を出す

**完了条件**: 生成器側の修正が完了すること。

### 1-204. 次の項目
EOF
  if ! check_ledger_wording "$work/ledger-missing.md" "$LEDGER_HEADING" "$LEDGER_PHRASE" >/dev/null; then
    echo "PASS: 台帳の文言なしを不合格と判定した"
  else
    echo "FAIL: 台帳の文言なしを合格と誤判定した" >&2
    fail=1
  fi

  if [ -f "$LEDGER" ]; then
    if check_ledger_wording "$LEDGER" "$LEDGER_HEADING" "$LEDGER_PHRASE" >/dev/null; then
      echo "PASS: 実台帳(指摘改善一覧.md)を合格と判定した"
    else
      echo "FAIL: 実台帳(指摘改善一覧.md)を不合格と誤判定した" >&2
      fail=1
    fi
  fi

  # --- check_samples_record ---
  cat > "$work/record-ok.md" <<'EOF'
追記: test-e2e-portal.shをgeneration-engine/samples/project-portalへ当て357件・FAIL0件・リリースノート関連7件全てPASSを確認した
EOF
  if check_samples_record "$work/record-ok.md" >/dev/null; then
    echo "PASS: samples記録ありを合格と判定した"
  else
    echo "FAIL: samples記録ありを不合格と誤判定した" >&2
    fail=1
  fi

  cat > "$work/record-missing.md" <<'EOF'
まだsamplesへは検査を当てていない。
EOF
  if ! check_samples_record "$work/record-missing.md" >/dev/null; then
    echo "PASS: samples記録なしを不合格と判定した"
  else
    echo "FAIL: samples記録なしを合格と誤判定した" >&2
    fail=1
  fi

  if [ -f "$INSTRUCTION_DOC" ]; then
    if check_samples_record "$INSTRUCTION_DOC" >/dev/null; then
      echo "PASS: 実指示書のsamples記録を合格と判定した"
    else
      echo "FAIL: 実指示書のsamples記録を不合格と誤判定した" >&2
      fail=1
    fi
  fi

  return "$fail"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  --replacement-case)
    check_replacement_case
    ;;
  --ledger-wording)
    check_ledger_wording "$LEDGER" "$LEDGER_HEADING" "$LEDGER_PHRASE"
    ;;
  --samples-record)
    check_samples_record "$INSTRUCTION_DOC"
    ;;
  "")
    # 判定不能（終了コード2）を不合格（1）へ丸めない
    # （.claude/rules/always/verification/indeterminate-result/rule.md）。
    # 3つの検査の終了コードのうち、1件でも1（不合格）があれば全体を1とする。
    # 1が1件も無く2（判定不能）が1件でもあれば全体を2とする。
    # どちらも無ければ0とする。
    has_fail=0
    has_unknown=0
    check_replacement_case
    rc=$?
    [ "$rc" -eq 1 ] && has_fail=1
    [ "$rc" -eq 2 ] && has_unknown=1
    check_ledger_wording "$LEDGER" "$LEDGER_HEADING" "$LEDGER_PHRASE"
    rc=$?
    [ "$rc" -eq 1 ] && has_fail=1
    [ "$rc" -eq 2 ] && has_unknown=1
    check_samples_record "$INSTRUCTION_DOC"
    rc=$?
    [ "$rc" -eq 1 ] && has_fail=1
    [ "$rc" -eq 2 ] && has_unknown=1
    if [ "$has_fail" -eq 1 ]; then
      exit 1
    elif [ "$has_unknown" -eq 1 ]; then
      exit 2
    else
      exit 0
    fi
    ;;
  *)
    echo "usage: check-release-notes-completion-record.sh [--replacement-case|--ledger-wording|--samples-record|--self-test]" >&2
    exit 2
    ;;
esac
