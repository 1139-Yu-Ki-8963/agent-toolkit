#!/usr/bin/env bash
# check-improvement-index.sh — 指摘改善一覧の構造・解決状態・指示書とのキー対応を検査する。
#
# 使い方:
#   bash docs/scripts/check-improvement-index.sh
#   bash docs/scripts/check-improvement-index.sh --unresolved-zero
#   bash docs/scripts/check-improvement-index.sh --cross-check
#   bash docs/scripts/check-improvement-index.sh --self-test
#
# 必要性: この台帳の完了判定が本スクリプトを参照している一方、従来は実体がなく、見出しの
#   必要要素・未解決状態・指示書とのキー対応を再現可能な方法で判定できなかった。
#
# 代替案を採用しなかった理由:
#   - grep等の都度実行: 注記付きの項目名や状態の説明文があり、実行者ごとに判定がぶれる
#   - 指示書形式検査への統合: 台帳固有のキー対応と解決状態は一般の指示書形式検査の責務ではない
#   - Makefile・package.jsonへの追加: いずれも既存しないため、この検査だけの実行基盤を増やす
#
# 保守責任者: 人手（ユーザー）。台帳の見出し・必要要素・状態・元の指摘の形式を変える場合は、
#   本スクリプトと自己テストを同時に更新する。
#
# 廃棄条件: docs/tasks/指摘改善一覧.md による指摘追跡と、その元の指摘を指示書へ記録する運用を
#   廃止した時。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER="${REPO_ROOT}/docs/tasks/指摘改善一覧.md"
TASKS_DIR="${REPO_ROOT}/docs/tasks"

unknown_missing_target() {
  local target="$1"
  echo "[UNKNOWN] 検査対象が見つからないため判定できません: ${target}" >&2
  return 2
}

extract_heading_keys() {
  local ledger="$1"
  awk '
    /^### [0-9]+-[0-9]+\. / {
      key = $0
      sub(/^### /, "", key)
      sub(/\..*/, "", key)
      print key
    }
  ' "$ledger"
}

check_structure() {
  local ledger="$1"
  [ -f "$ledger" ] || { unknown_missing_target "$ledger"; return 2; }

  local output result
  output="$(awk '
    function finish_heading(  missing) {
      if (key == "") return
      missing = ""
      if (!phenomenon) missing = missing " 現象"
      if (!correction) missing = missing " 修正内容"
      if (!verification) missing = missing " 確認方法または検収方法"
      if (!completion) missing = missing " 完了条件"
      if (!state) missing = missing " 状態"
      if (missing != "") {
        print "[FAIL] " key " に必要な要素がありません:" missing
        failed = 1
      }
    }
    /^### / {
      finish_heading()
      key = ""
      if ($0 ~ /^### [0-9]/ && $0 !~ /^### [0-9]+-[0-9]+\. .+/) {
        print "[FAIL] 見出しの形が不正です（期待: ### N-N. 題名）: " $0
        failed = 1
        next
      }
      if ($0 !~ /^### [0-9]+-[0-9]+\. .+/) next
      key = $0
      sub(/^### /, "", key)
      sub(/\..*/, "", key)
      if (seen[key]++) {
        print "[FAIL] 見出しのキーが重複しています: " key
        failed = 1
      }
      count++
      phenomenon = correction = verification = completion = state = 0
      next
    }
    /^\*\*現象([^*]*)\*\*(:|$)/ { if (key != "") phenomenon = 1 }
    /^\*\*修正内容([^*]*)\*\*(:|$)/ { if (key != "") correction = 1 }
    /^\*\*(確認方法|検収方法)([^*]*)\*\*(:|$)/ { if (key != "") verification = 1 }
    /^\*\*完了条件([^*]*)\*\*(:|$)/ { if (key != "") completion = 1 }
    /^\*\*状態\*\*:/ { if (key != "") state = 1 }
    END {
      finish_heading()
      if (count == 0) {
        print "[FAIL] 対象の見出しがありません"
        failed = 1
      }
      exit failed
    }
  ' "$ledger")"
  result=$?
  if [ "$result" -eq 0 ]; then
    echo "[PASS] 台帳の見出しと必要な要素を確認しました（$(extract_heading_keys "$ledger" | wc -l | tr -d ' ')件）"
  else
    printf '%s\n' "$output"
  fi
  return "$result"
}

extract_last_states() {
  local ledger="$1"
  awk '
    /^### / {
      if (key != "") print key "\t" state
      key = ""
      state = ""
      if ($0 !~ /^### [0-9]+-[0-9]+\. /) next
      key = $0
      sub(/^### /, "", key)
      sub(/\..*/, "", key)
      next
    }
    /^\*\*状態\*\*:/ { if (key != "") state = $0 }
    END { if (key != "") print key "\t" state }
  ' "$ledger"
}

check_unresolved_zero() {
  local ledger="$1"
  [ -f "$ledger" ] || { unknown_missing_target "$ledger"; return 2; }

  local unresolved
  unresolved="$(extract_last_states "$ledger" | awk -F '\t' '
    $2 !~ /^\*\*状態\*\*: 完了($|[（。 ])/ { print $1 "\t" ($2 == "" ? "(状態行なし)" : $2) }
  ')"
  if [ -n "$unresolved" ]; then
    echo "[FAIL] 完了以外の見出しがあります:" >&2
    printf '%s\n' "$unresolved" | sed 's/^/  /' >&2
    return 1
  fi

  echo "[PASS] 完了以外の見出しは0件です"
}

check_cross_check() {
  local ledger="$1" tasks_dir="$2"
  [ -f "$ledger" ] || { unknown_missing_target "$ledger"; return 2; }
  [ -d "$tasks_dir" ] || { unknown_missing_target "$tasks_dir"; return 2; }

  local tmpdir=""
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    return 2
  fi
  trap 'if [ -n "${tmpdir:-}" ]; then rm -rf "$tmpdir"; fi' RETURN

  extract_heading_keys "$ledger" | LC_ALL=C sort -u > "$tmpdir/ledger-keys.txt"
  : > "$tmpdir/referenced-keys.tsv"

  local file value token failed=0 checked=0
  while IFS= read -r file; do
    value="$(awk '/^\*\*元の指摘\*\*:/ { print; exit }' "$file")"
    [ -n "$value" ] || continue
    value="${value#**元の指摘**:}"
    value="$(printf '%s' "$value" | tr '、' ',' | tr -d '`')"
    IFS=',' read -r -a tokens <<< "$value"
    for token in "${tokens[@]}"; do
      token="$(printf '%s' "$token" | tr -d '[:space:]')"
      [ -z "$token" ] && continue
      [ "$token" = "なし" ] && continue
      [ "$token" = "—" ] && continue
      printf '%s\t%s\n' "$token" "$file" >> "$tmpdir/referenced-keys.tsv"
    done
  done < <(rg --files "$tasks_dir" -g '*指示書.md' | LC_ALL=C sort)

  while IFS=$'\t' read -r token file; do
    [ -n "$token" ] || continue
    checked=$((checked + 1))
    if [[ ! "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
      echo "[FAIL] 元の指摘の値がキー形式ではありません: ${token} (${file})"
      failed=1
    elif ! grep -Fxq "$token" "$tmpdir/ledger-keys.txt"; then
      echo "[FAIL] 指示書の元の指摘が台帳にありません: ${token} (${file})"
      failed=1
    fi
  done < "$tmpdir/referenced-keys.tsv"

  if [ "$failed" -eq 0 ]; then
    echo "[PASS] 指示書の元の指摘と台帳のキーを照合しました（${checked}件）"
  fi

  rm -rf "$tmpdir"
  tmpdir=""
  trap - RETURN
  return "$failed"
}

record_self_test() {
  local name="$1" expected="$2"
  shift 2
  total=$((total + 1))
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    echo "  [PASS] ${name}"
    pass=$((pass + 1))
  else
    echo "  [FAIL] ${name}（終了コード=${actual}、期待=${expected}）"
    fail=$((fail + 1))
  fi
}

run_self_test() {
  local pass=0 fail=0 total=0
  local tmpdir=""
  # 置き場を明示するのは、引数なしの mktemp が既定の置き場へ書こうとして失敗する環境があるためである（実測 2026-08-24）。素直な mktemp へ戻さない。
  if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "${BASH_SOURCE[0]}" .sh).XXXXXX" 2>/dev/null)" || [ -z "$tmpdir" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境のサンドボックス制約等が原因である可能性があります）"
    exit 2
  fi
  trap 'if [ -n "${tmpdir:-}" ]; then rm -rf "$tmpdir"; fi' EXIT

  mkdir -p "$tmpdir/tasks"
  cat > "$tmpdir/valid.md" <<'EOF'
### 1-1. 見出しA
**現象**: 現象
**修正内容**: 修正
**確認方法**: 確認
**完了条件**: 条件
**状態**: 完了

### 1-2. 見出しB
**現象（実測事実）**
現象
**修正内容（到達状態）**
修正
**検収方法（機械検査）**
検収
**完了条件**
条件
**状態**: 完了（確認済み）
EOF
  cp "$tmpdir/valid.md" "$tmpdir/missing.md"
  sed -i.bak '/^\*\*修正内容\*\*: 修正$/d' "$tmpdir/missing.md"
  rm "$tmpdir/missing.md.bak"
  awk '
    !changed && /^\*\*状態\*\*: 完了$/ { print "**状態**: 未着手"; changed = 1; next }
    { print }
  ' "$tmpdir/valid.md" > "$tmpdir/unresolved.md"
  cp "$tmpdir/valid.md" "$tmpdir/invalid-heading.md"
  printf '\n### 2-1 見出しの終止符なし\n' >> "$tmpdir/invalid-heading.md"

  cat > "$tmpdir/tasks/matched指示書.md" <<'EOF'
**元の指摘**: 1-1, 1-2

本文中の例示:
**元の指摘**: 9-9
EOF
  record_self_test "必要要素が揃った台帳" 0 check_structure "$tmpdir/valid.md"
  record_self_test "必要要素の欠落を検出" 1 check_structure "$tmpdir/missing.md"
  record_self_test "不正な見出し形式を検出" 1 check_structure "$tmpdir/invalid-heading.md"
  record_self_test "全見出しが完了" 0 check_unresolved_zero "$tmpdir/valid.md"
  record_self_test "未着手を検出" 1 check_unresolved_zero "$tmpdir/unresolved.md"
  record_self_test "指示書のキーが全て台帳に存在" 0 check_cross_check "$tmpdir/valid.md" "$tmpdir/tasks"

  cat > "$tmpdir/tasks/missing-key指示書.md" <<'EOF'
**元の指摘**: 1-3
EOF
  record_self_test "台帳に無い元の指摘を検出" 1 check_cross_check "$tmpdir/valid.md" "$tmpdir/tasks"
  record_self_test "検査対象不在を判定不能として区別" 2 check_structure "$tmpdir/not-found.md"

  echo "実行 ${total} 件 / 成功 ${pass} 件 / 失敗 ${fail} 件"
  local result=0
  [ "$fail" -eq 0 ] || result=1
  rm -rf "$tmpdir"
  tmpdir=""
  trap - EXIT
  return "$result"
}

case "${1:-}" in
  "") check_structure "$LEDGER"; exit $? ;;
  --unresolved-zero) check_unresolved_zero "$LEDGER"; exit $? ;;
  --cross-check) check_cross_check "$LEDGER" "$TASKS_DIR"; exit $? ;;
  --self-test) run_self_test; exit $? ;;
  *) echo "不明な引数: $1" >&2; exit 1 ;;
esac
