#!/usr/bin/env bash
# check-dev-flow-completion.sh — 開発フロー(Phase5)完了記録の実在と中身を検査する
#
# 目的:
#   このリポジトリ自身が定める納品完了の条件（配布対象外）の第5段「開発フローが通る」は、配った /dev-flow スキルの
#   Phase5ゲートが対話でしか確定できないため、これまで機械判定の手順を持たなかった。
#   Phase5確定時にゲートの提示物3点（実装概要・動作確認結果表・規約レビュー結果）を
#   対象プロジェクトの docs/scope-and-progress/開発フロー完了記録.md へ追記する手順を
#   dev-flow の SKILL.md に足し、本スクリプトはその記録の実在と中身を検査する。
#
# 使い方:
#   check-dev-flow-completion.sh <対象プロジェクトのパス>
#   check-dev-flow-completion.sh --self-test
#
# 記録ファイルの形式（delivery-payload/templates/delivered-skills/dev-flow/SKILL.md と対応）:
#   <対象プロジェクトのパス>/docs/scope-and-progress/開発フロー完了記録.md
#   「## 記録」見出しの下へ、Phase5 確定のたびに「### <ISO8601日時>」の節を追記する
#   （新しい記録が上）。各節は次を持つ:
#     - | 要求 | <値> | 行（開発要件の要約。空・プレースホルダは不可）
#     - | コミット | `<40桁16進>` | 行
#     - | 入口のページ | 更新: `<40桁16進>` または 影響なし: <根拠> | 行
#     - #### 実装概要（空でない本文）
#     - #### 動作確認結果（「| ケース | 結果 |」形式の表。各行の結果列は "pass" のみ許可）
#     - #### 規約レビュー結果（空でない本文）
#
# 判定:
#   - 記録ファイルが無ければ不合格
#   - 記録が1件も無ければ不合格
#   - 各記録について、見出し形式・要求・コミット・実装概要・規約レビュー結果・
#     動作確認結果（不合格行を含まないこと）を検査し、1件でも欠落・不合格があれば
#     その記録を不合格として数える
#   - 不合格件数が1件でもあれば終了コード1
#
# 保守責任者: 人手（ユーザー）。記録の形式（見出し・表の列名・許可する結果値）を
# 変える場合は本ファイルと dev-flow/SKILL.md と self-test を同時に更新する。
# 廃棄条件: 開発フロー完了記録の機械判定自体を廃止した時、または /dev-flow を無人で
# 1往復させるシナリオ実行器に置き換えた時。
# macOS bash 3.2 互換（連想配列・mapfile は使わない）。
set -uo pipefail

RECORD_REL="docs/scope-and-progress/開発フロー完了記録.md"

# ブロック（見出し行〜次の見出し行の直前まで）を1件検査する。
# 引数: block（対象ブロックの本文）
# 戻り値: 合格なら0、不合格なら1（詳細は stderr へ列挙）
judge_record() {
  local block="$1" ok=1 heading

  heading="$(printf '%s\n' "$block" | head -1)"

  if ! printf '%s' "$heading" | grep -qE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
    echo "    見出しがISO8601形式でない: $heading" >&2
    ok=0
  fi

  local req_cell req_val
  req_cell="$(printf '%s\n' "$block" | grep -E '^\| *要求 *\|' | head -1 | awk -F'|' '{print $3}')"
  req_val="$(printf '%s' "$req_cell" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [ -z "$req_val" ] || printf '%s' "$req_val" | grep -qE '^<.*>$'; then
    echo "    要求が未記入: $heading" >&2
    ok=0
  fi

  local commit_cell commit_val
  commit_cell="$(printf '%s\n' "$block" | grep -E '^\| *コミット *\|' | head -1 | awk -F'|' '{print $3}')"
  commit_val="$(printf '%s' "$commit_cell" | tr -d ' `')"
  if ! printf '%s' "$commit_val" | grep -qE '^[0-9a-f]{40}$'; then
    echo "    コミットが40桁の16進でない: $heading (値: $commit_val)" >&2
    ok=0
  fi

  local portal_cell portal_val
  portal_cell="$(printf '%s\n' "$block" | grep -E '^\| *入口のページ *\|' | head -1 | awk -F'|' '{print $3}')"
  portal_val="$(printf '%s' "$portal_cell" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if ! printf '%s' "$portal_val" | grep -qE '^更新: *`?[0-9a-f]{40}`?$|^影響なし: *[^ <].+'; then
    echo "    入口のページの状態が未記入または形式違反: $heading" >&2
    ok=0
  fi

  local impl_body
  impl_body="$(printf '%s\n' "$block" | awk '/^#### 実装概要/{f=1;next} /^#### /{f=0} f{print}' | sed '/^[[:space:]]*$/d')"
  if [ -z "$impl_body" ]; then
    echo "    実装概要が空: $heading" >&2
    ok=0
  fi

  local review_body
  review_body="$(printf '%s\n' "$block" | awk '/^#### 規約レビュー結果/{f=1;next} /^#### /{f=0} f{print}' | sed '/^[[:space:]]*$/d')"
  if [ -z "$review_body" ]; then
    echo "    規約レビュー結果が空: $heading" >&2
    ok=0
  fi

  local verify_block verify_rows bad_rows
  verify_block="$(printf '%s\n' "$block" | awk '/^#### 動作確認結果/{f=1;next} /^#### /{f=0} f{print}')"
  verify_rows="$(printf '%s\n' "$verify_block" | grep -E '^\|' | grep -vE '^\| *ケース *\|' | grep -vE '^\|[-: ]+\|[-: ]+\|?$')"
  if [ -z "$verify_rows" ]; then
    echo "    動作確認結果の表が無い: $heading" >&2
    ok=0
  else
    bad_rows="$(printf '%s\n' "$verify_rows" | awk -F'|' '{gsub(/[[:space:]]/,"",$3); if ($3 != "pass") print}')"
    if [ -n "$bad_rows" ]; then
      echo "    動作確認結果に pass 以外の結果を含む: $heading" >&2
      printf '%s\n' "$bad_rows" | sed 's/^/      /' >&2
      ok=0
    fi
  fi

  [ "$ok" -eq 1 ]
}

# 引数: target（対象プロジェクトのパス）
run_check() {
  local target="$1" record_file
  record_file="$target/$RECORD_REL"

  if [ ! -f "$record_file" ]; then
    echo "  [FAIL] 記録ファイルが見つからない: $record_file" >&2
    return 1
  fi

  local total_lines
  total_lines="$(wc -l < "$record_file" | tr -d ' ')"

  local -a starts=()
  while IFS= read -r ln; do
    [ -z "$ln" ] && continue
    starts+=("$ln")
  done < <(grep -n '^### ' "$record_file" | cut -d: -f1)

  local n_starts=${#starts[@]}
  if [ "$n_starts" -eq 0 ]; then
    echo "  [FAIL] 記録が1件も無い: $record_file" >&2
    return 1
  fi

  local i start end block heading fail_count=0
  for ((i = 0; i < n_starts; i++)); do
    start="${starts[$i]}"
    if [ $((i + 1)) -lt "$n_starts" ]; then
      end=$(( ${starts[$((i + 1))]} - 1 ))
    else
      end="$total_lines"
    fi
    block="$(sed -n "${start},${end}p" "$record_file")"
    heading="$(printf '%s\n' "$block" | head -1)"

    if judge_record "$block"; then
      echo "  [PASS] $heading"
    else
      echo "  [FAIL] $heading" >&2
      fail_count=$((fail_count + 1))
    fi
  done

  echo "=== $((n_starts - fail_count))/$n_starts PASS, ${fail_count}/$n_starts FAIL ==="
  [ "$fail_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 自己テスト
# ---------------------------------------------------------------------------
self_test() {
  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-dev-flow-completion-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' RETURN

  local rc=0

  # ケース1: 正しい記録が1件あれば合格すること
  local ok_dir="$tmp/ok-project"
  mkdir -p "$ok_dir/docs/scope-and-progress"
  cat > "$ok_dir/$RECORD_REL" <<'MD'
# 開発フロー完了記録

## 記録

### 2026-08-16T21:40:39+0900

| 項目 | 値 |
|---|---|
| 要求 | 検索結果の並び順に更新日時を追加する |
| コミット | `9c6c98cf58ee27374b0a23e25b14e32ce71e6494` |
| 入口のページ | 更新: `9c6c98cf58ee27374b0a23e25b14e32ce71e6494` |

#### 実装概要

一覧APIのソートキーに updated_at を追加した。

#### 動作確認結果

| ケース | 結果 |
|---|---|
| 既定の並び順 | pass |
| 更新日時での並び替え | pass |

#### 規約レビュー結果

指摘なし。
MD

  if _gt_out1="$(run_check "$ok_dir" 2>&1)"; then
    echo "  [PASS] 陽性: 正しい記録があれば終了コード0"
  else
    echo "  [FAIL] 陽性: 正しい記録なのにFAILした" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    rc=1
  fi

  # ケース2: 記録ファイル自体が無ければ不合格になること
  local missing_dir="$tmp/missing-project"
  mkdir -p "$missing_dir/docs/scope-and-progress"

  local missing_output
  if missing_output=$(run_check "$missing_dir" 2>&1); then
    echo "  [FAIL] 陰性: 記録が無いのにPASSした" >&2
    rc=1
  else
    if printf '%s' "$missing_output" | grep -q "記録ファイルが見つからない"; then
      echo "  [PASS] 陰性: 記録ファイル不在で終了コード1"
    else
      echo "  [FAIL] 陰性: 終了コード1だが不在の理由が出力に無い" >&2
      rc=1
    fi
  fi

  # ケース3: 動作確認結果に不合格を含む記録があれば不合格になること
  local ng_dir="$tmp/ng-project"
  mkdir -p "$ng_dir/docs/scope-and-progress"
  cat > "$ng_dir/$RECORD_REL" <<'MD'
# 開発フロー完了記録

## 記録

### 2026-08-16T21:40:39+0900

| 項目 | 値 |
|---|---|
| 要求 | 検索結果の並び順に更新日時を追加する |
| コミット | `9c6c98cf58ee27374b0a23e25b14e32ce71e6494` |
| 入口のページ | 影響なし: 表示コミット以降の変更は文書だけだった |

#### 実装概要

一覧APIのソートキーに updated_at を追加した。

#### 動作確認結果

| ケース | 結果 |
|---|---|
| 既定の並び順 | pass |
| 更新日時での並び替え | fail |

#### 規約レビュー結果

指摘なし。
MD

  local ng_output
  if ng_output=$(run_check "$ng_dir" 2>&1); then
    echo "  [FAIL] 陰性: 動作確認に不合格を含むのにPASSした" >&2
    rc=1
  else
    if printf '%s' "$ng_output" | grep -q "pass 以外の結果を含む"; then
      echo "  [PASS] 陰性: 動作確認の不合格を検出して終了コード1"
    else
      echo "  [FAIL] 陰性: 終了コード1だが不合格行の指摘が出力に無い" >&2
      rc=1
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <対象プロジェクトのパス>" >&2
  exit 1
fi

run_check "$1"
