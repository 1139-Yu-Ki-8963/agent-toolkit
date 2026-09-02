#!/usr/bin/env bash
# report-progress.sh — docs/tasks/指摘改善一覧.md の状態集計と、codex並行実行の稼働状況・
# main統合状況・公開状態をまとめて出す定期報告ツール。
#
# 使い方:
#   bash docs/scripts/report-progress.sh              指摘の状態集計だけを出す
#   bash docs/scripts/report-progress.sh --full        codex稼働状況・main統合・公開状態も含めた全体を出す
#   bash docs/scripts/report-progress.sh --self-test   スクリプト自身と規約適合の検査
#
# 必要性: 指摘改善一覧.md の状態集計を人手のワンライナー（grep -c）で行うと、1見出しに複数の
#   状態行が残っている場合に二重カウントする。実際に2026-08-19、見出し87件に対しgrep -cが
#   105件の状態行を検出し、見出し数と合わない集計をユーザーへ誤って報告する事故が起きた。
#   繰り返し実行するたびに同じ誤りを防ぐには、判定ロジックをスクリプトへ固定する必要がある。
#
# 集計方式: `### ` で始まる見出し全般（`### N-N.` の番号付きキーだけでなく、内容を要約した
#   意味語キーの見出しも対象）について、次の見出しの直前に現れた最後の`**状態**:`行だけを1件
#   として数える。同じ見出しの中に古い状態行が残っていても二重カウントしない。冒頭の指示書
#   前付け（`## ` 見出し配下）にある状態行は、最初の`### `見出しに出会うまで捨てられるため
#   数えない。
#
# 2026-08-28 修正: 走査条件が `### N-N.` の番号付きキーだけに固定されていたため、内容を
#   要約した意味語キーの見出し（`### ER図-テーブル詳細タブ.` 等）20件が一度も数えられて
#   いなかった（実測: 見出し156件・番号付き136件・意味語キー20件）。台帳の形式規約
#   （issue-ledger-format/rule.md）が意味語キーも許すよう改めたことに合わせ、走査条件を
#   `### ` 全般へ広げた。
#
# 規約: .claude/rules/always/tasks/issue-ledger-format/rule.md（状態の語彙・1見出し1状態行の原則・
#   見出しキーは番号付きでも意味語キーでもよい）
#
# 代替案を採用しなかった理由:
#   - Bash ツール直叩き（都度ワンライナーを書く）: 実行のたびに集計ロジックがぶれ、実際に
#     二重カウントの事故が起きた
#   - 既存 Makefile ターゲット拡張: このリポジトリに Makefile は存在せず、新規導入は本スクリプト
#     専用の依存を増やすだけになる
#   - package.json scripts 追加: 同様に、このリポジトリはビルド設定を持たない
#
# 保守責任者: 人手（ユーザー）。指摘改善一覧.md の見出し形式・状態語彙を変える場合は、本スクリプトと
#   .claude/rules/always/tasks/issue-ledger-format/rule.md を同時に更新する。
#
# 廃棄条件: 指摘改善一覧.md による指摘の追跡運用を廃止した時。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER="${REPO_ROOT}/docs/tasks/指摘改善一覧.md"
ALLOWED_STATES="未着手 対応中 完了 対象外 未確認"
self_test_tmpdir=""

# 公開先リポジトリのローカルパスは受け口 .claude/rules/always/publish/publish-values.txt から読む。
# 定義: ~/agent-home/rules/always/publish/toolkit-payload-cycle/rule.md
# 受け口が無い場合、本体はハードコードした既定値を持たない。print_publish_status() が
# 判定不能として扱う（定義: .claude/rules/always/verification/indeterminate-result/rule.md）。
PUBLISH_VALUES_FILE="${REPO_ROOT}/.claude/rules/always/publish/publish-values.txt"

_publish_value() {
  local key="$1"
  [ -f "$PUBLISH_VALUES_FILE" ] || return 1
  grep -E "^${key}=" "$PUBLISH_VALUES_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-
}

_pv_toolkit_dir="$(_publish_value TOOLKIT_DIR)"
if [ -n "$_pv_toolkit_dir" ]; then
  case "$_pv_toolkit_dir" in
    "~"/*) _pv_toolkit_dir="${HOME}${_pv_toolkit_dir#\~}" ;;
    "~") _pv_toolkit_dir="$HOME" ;;
  esac
  DEFAULT_TOOLKIT_DIR="$_pv_toolkit_dir"
else
  DEFAULT_TOOLKIT_DIR=""
fi
unset _pv_toolkit_dir

is_allowed_state() {
  case " $ALLOWED_STATES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

extract_issue_states() {
  local ledger="$1"
  awk '
    /^### / {
      if (key) print key "\t" state
      key = $0
      sub(/^### /, "", key)
      sub(/\..*/, "", key)
      state = "(状態行なし)"
      next
    }
    /^\*\*状態\*\*:/ { state = $0 }
    END { if (key) print key "\t" state }
  ' "$ledger"
}

count_state_lines_per_heading() {
  local ledger="$1"
  awk '
    /^### / {
      if (key) print key "\t" cnt
      key = $0
      sub(/^### /, "", key)
      sub(/\..*/, "", key)
      cnt = 0
      next
    }
    /^\*\*状態\*\*:/ { cnt++ }
    END { if (key) print key "\t" cnt }
  ' "$ledger"
}

print_state_summary() {
  local ledger="$1"
  if [ ! -f "$ledger" ]; then
    echo "[UNKNOWN] 台帳が見つかりません: $ledger" >&2
    return 2
  fi

  local total
  total="$(extract_issue_states "$ledger" | wc -l | tr -d ' ')"
  echo "総数: ${total}件"

  extract_issue_states "$ledger" \
    | sed -E 's/^[^\t]*\t\*\*状態\*\*: ([^（。]*).*/\1/' \
    | LC_ALL=C sort | LC_ALL=C uniq -c | LC_ALL=C sort -rn \
    | awk '{cnt=$1; $1=""; sub(/^ /,""); print "  " $0 ": " cnt "件"}'
}

print_codex_workers() {
  local worktrees
  worktrees="$(ps aux 2>/dev/null | grep "codex exec -C" | grep -v grep | grep -oE '\-C [^ ]+' | awk '{print $2}' | sort -u)"

  if [ -z "$worktrees" ]; then
    echo "  稼働中のcodex execなし"
    return 0
  fi

  echo "$worktrees" | while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    local name commit dirty
    name="$(basename "$wt")"
    commit="$(git -C "$wt" log -1 --oneline 2>/dev/null || echo "(取得不可)")"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${name}: ${commit} / 未コミット行数=${dirty}"
  done
}

print_recent_merges() {
  git -C "$REPO_ROOT" log -5 --oneline 2>/dev/null
}

print_publish_status() {
  local toolkit="$DEFAULT_TOOLKIT_DIR"
  if [ -z "$toolkit" ]; then
    echo "  [UNKNOWN] 判定不能（受け口なし: ${PUBLISH_VALUES_FILE} が無い、またはTOOLKIT_DIRが未設定のため公開先を特定できない）"
    return 0
  fi
  if [ ! -d "$toolkit" ]; then
    echo "  公開先リポジトリが見つかりません: $toolkit"
    return 0
  fi
  ( cd "$toolkit" && git fetch origin main >/dev/null 2>&1
    local local_head remote_head
    local_head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    remote_head="$(git rev-parse origin/main 2>/dev/null || echo unknown)"
    if [ "$local_head" = "$remote_head" ] && [ "$local_head" != "unknown" ]; then
      echo "  公開済み: ${local_head}"
    else
      echo "  未公開または未確認: local=${local_head} / origin/main=${remote_head}"
    fi
  )
}

run_full_report() {
  echo "## 定期報告（$(date '+%H:%M')時点）"
  echo
  echo "### 指摘の全体（見出し単位・重複なし）"
  print_state_summary "$LEDGER"
  echo
  echo "### codex作業者（最大3件同時）"
  print_codex_workers
  echo
  echo "### 直近でmainへ統合した件"
  print_recent_merges
  echo
  echo "### 公開状態"
  print_publish_status
}

run_self_test() {
  local pass=0 fail=0 total=0
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! self_test_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$self_test_tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi
  trap 'if [ -n "${self_test_tmpdir:-}" ]; then rm -rf "$self_test_tmpdir"; fi' EXIT

  cat > "$self_test_tmpdir/case1.md" << 'EOF'
### 1-1. 見出しA
**状態**: 完了

### 1-2. 見出しB
**状態**: 未着手

### 1-3. 見出しC
**状態**: 対応中
EOF
  total=$((total + 1))
  local out1
  out1="$(print_state_summary "$self_test_tmpdir/case1.md")"
  if echo "$out1" | grep -q "総数: 3件" && echo "$out1" | grep -q "完了: 1件" && echo "$out1" | grep -q "未着手: 1件" && echo "$out1" | grep -q "対応中: 1件"; then
    echo "  [PASS] 単純ケース-集計一致"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 単純ケース-集計一致"
    echo "$out1" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  cat > "$self_test_tmpdir/case2.md" << 'EOF'
### 1-1. 見出しA
**状態**: 未着手

再確認した。

**状態**: 完了

### 1-2. 見出しB
**状態**: 未着手
EOF
  total=$((total + 1))
  local out2
  out2="$(print_state_summary "$self_test_tmpdir/case2.md")"
  if echo "$out2" | grep -q "総数: 2件" && echo "$out2" | grep -q "完了: 1件" && echo "$out2" | grep -q "未着手: 1件"; then
    echo "  [PASS] 複数状態行-二重カウントなし"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 複数状態行-二重カウントなし"
    echo "$out2" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  local dupcount
  dupcount="$(count_state_lines_per_heading "$self_test_tmpdir/case2.md" | awk -F'\t' '$2>1' | wc -l | tr -d ' ')"
  if [ "$dupcount" = "1" ]; then
    echo "  [PASS] 1見出し複数状態行の検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 1見出し複数状態行の検出（検出件数=${dupcount}、期待=1）"
    fail=$((fail + 1))
  fi

  total=$((total + 1))
  if [ -f "$LEDGER" ]; then
    local heading_count summary_total
    heading_count="$(grep -c '^### ' "$LEDGER")"
    summary_total="$(extract_issue_states "$LEDGER" | wc -l | tr -d ' ')"
    if [ "$heading_count" = "$summary_total" ]; then
      echo "  [PASS] 実リポジトリ台帳-見出し数と集計総数の一致（${heading_count}件）"
      pass=$((pass + 1))
    else
      echo "  [FAIL] 実リポジトリ台帳-見出し数と集計総数の一致（見出し=${heading_count} / 集計=${summary_total}）"
      fail=$((fail + 1))
    fi
  else
    echo "  [SKIP] 実リポジトリ台帳が見つからないため対象外"
    pass=$((pass + 1))
  fi

  cat > "$self_test_tmpdir/case3.md" << 'EOF'
### 1-1. 見出しA
**状態**: 完了

### 意味語キー-単純見出し
**状態**: 未着手
EOF
  total=$((total + 1))
  local out3
  out3="$(print_state_summary "$self_test_tmpdir/case3.md")"
  if echo "$out3" | grep -q "総数: 2件" && echo "$out3" | grep -q "完了: 1件" && echo "$out3" | grep -q "未着手: 1件"; then
    echo "  [PASS] 意味語キー見出し-集計に含まれる"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 意味語キー見出し-集計に含まれる"
    echo "$out3" | sed 's/^/    /'
    fail=$((fail + 1))
  fi

  cat > "$self_test_tmpdir/case4.md" << 'EOF'
### 意味語キー-重複. 見出しの説明
**状態**: 未着手

再確認した。

**状態**: 完了
EOF
  total=$((total + 1))
  local dupcount2
  dupcount2="$(count_state_lines_per_heading "$self_test_tmpdir/case4.md" | awk -F'\t' '$2>1' | wc -l | tr -d ' ')"
  if [ "$dupcount2" = "1" ]; then
    echo "  [PASS] 意味語キー見出し-複数状態行の検出"
    pass=$((pass + 1))
  else
    echo "  [FAIL] 意味語キー見出し-複数状態行の検出（検出件数=${dupcount2}、期待=1）"
    fail=$((fail + 1))
  fi

  if [ -f "$LEDGER" ]; then
    local bad_values
    bad_values="$(extract_issue_states "$LEDGER" | sed -E 's/^[^\t]*\t\*\*状態\*\*: ([^（。]*).*/\1/' | LC_ALL=C sort -u | while IFS= read -r v; do
      is_allowed_state "$v" || echo "$v"
    done)"
    if [ -n "$bad_values" ]; then
      echo "  [INFO] 規約外の状態値が実台帳に残っています（別途手動での是正が必要）: $(echo "$bad_values" | tr '\n' ' ')"
    fi
  fi

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  local result=0
  [ "$fail" -eq 0 ] || result=1
  if rm -rf "$self_test_tmpdir"; then
    self_test_tmpdir=""
    trap - EXIT
  else
    echo "[FAIL] 一時ディレクトリを削除できません: $self_test_tmpdir" >&2
    result=1
  fi
  return "$result"
}

case "${1:-}" in
  --full) run_full_report ;;
  --self-test) run_self_test; exit $? ;;
  "") echo "### 指摘の全体（見出し単位・重複なし）"; print_state_summary "$LEDGER" ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac
