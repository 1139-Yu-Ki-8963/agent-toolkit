#!/usr/bin/env bash
# 画面とAPIの対応づけの担当所在を検査する: orchestrating-ai-development-setup の
# Step 3-1 が「screen種別とapi種別の両方が揃った後にrelatedApisを解決する担当」を
# 明記しているか、generating-screen-list-for-reverse-docs の Step 2-4 が
# 「api-manifestが既存なら--api-manifestを渡す」ことを明記しているかを grep で検査する。
#
# 改善課題: 画面とAPIの対応づけ-担当不在（このリポジトリ自身の改修課題台帳に記録。配布対象外）。
# 2026-08-11実測: 画面拡張マニフェスト35件すべてにrelatedApisが無く、画面-API-テーブル
# 対応表の画面軸が0件になった。原因は「api-manifestが後から確立した場合にrelatedApisを
# 解決し直す担当」がどのSKILL.mdにも存在しないこと。本スクリプトは、その担当の記述が
# 実在するかを機械検査する（担当を持つのは記述であり、本検査は記述の有無を確認する）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

check_step_section() {
  local file="$1" start_marker="$2" end_marker="$3" pattern="$4" desc="$5"
  local section
  section="$(awk -v s="$start_marker" -v e="$end_marker" '
    $0 ~ s {flag=1}
    flag {print}
    flag && $0 ~ e && $0 !~ s {exit}
  ' "$file")"
  if printf '%s' "$section" | grep -qF -- "$pattern"; then
    echo "  [PASS] $desc"
    return 0
  else
    echo "  [FAIL] $desc" >&2
    return 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-screen-api-linkage-contract-self-test.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi
  trap 'rm -rf "$tmp"' EXIT
  rc=0

  # --- 修正前を模したフィクスチャ（担当の記述が無い） ---
  cat > "$tmp/orch-before.md" <<'MD'
## Step 3-1: 実在種別の一覧を生成する

全種別の子スキルが status=DONE を返した後、check-manifest-persistence.sh を実行する。

**完了**: 実在種別の一覧HTMLがすべて存在する。

## Step 3-2: 対象外種別と派生一覧を確定する
MD
  cat > "$tmp/screenlist-before.md" <<'MD'
## Step 2-4: raw正本とraw由来extを確定する

extract-screen-metadata.sh <raw> <source_dir> <ext> --design-docs-dir <dir> を実行する。

## Phase 3: 整合検証
MD

  if _gt_out1="$(check_step_section "$tmp/orch-before.md" "^## Step 3-1" "^## Step 3-2" "--api-manifest" "修正前フィクスチャ(orchestrator)はFAILするべき" 2>&1)"; then
    echo "  [FAIL] 修正前フィクスチャ(orchestrator)がPASSしてしまった（検査が機能していない）" >&2
    printf '%s\n' "$_gt_out1" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 修正前フィクスチャ(orchestrator)は期待どおりFAILする"
  fi
  if _gt_out2="$(check_step_section "$tmp/screenlist-before.md" "^## Step 2-4" "^## Phase 3" "--api-manifest" "修正前フィクスチャ(screenlist)はFAILするべき" 2>&1)"; then
    echo "  [FAIL] 修正前フィクスチャ(screenlist)がPASSしてしまった（検査が機能していない）" >&2
    printf '%s\n' "$_gt_out2" | sed 's/^/    /' >&2
    rc=1
  else
    echo "  [PASS] 修正前フィクスチャ(screenlist)は期待どおりFAILする"
  fi

  # --- 修正後を模したフィクスチャ（担当の記述がある） ---
  cat > "$tmp/orch-after.md" <<'MD'
## Step 3-1: 実在種別の一覧を生成する

全種別の子スキルが status=DONE を返した後、check-manifest-persistence.sh を実行する。

**画面とAPIの対応づけ（本Stepの担当）**: rebuild-screen-derived-pages.sh --api-manifest を実行する。

**完了**: 実在種別の一覧HTMLがすべて存在する。

## Step 3-2: 対象外種別と派生一覧を確定する
MD
  cat > "$tmp/screenlist-after.md" <<'MD'
## Step 2-4: raw正本とraw由来extを確定する

api-manifest.jsonが実在すれば--api-manifestを追加のうえextract-screen-metadata.shを実行する。

## Phase 3: 整合検証
MD

  if check_step_section "$tmp/orch-after.md" "^## Step 3-1" "^## Step 3-2" "--api-manifest" "修正後フィクスチャ(orchestrator)はPASSするべき"; then
    :
  else
    rc=1
  fi
  if check_step_section "$tmp/screenlist-after.md" "^## Step 2-4" "^## Phase 3" "--api-manifest" "修正後フィクスチャ(screenlist)はPASSするべき"; then
    :
  else
    rc=1
  fi

  exit "$rc"
fi

orch_file="$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/SKILL.md"
screenlist_file="$REPO_ROOT/.claude/skills/generating-screen-list-for-reverse-docs/SKILL.md"
rc=0

check_step_section "$orch_file" "^## Step 3-1" "^## Step 3-2" "rebuild-screen-derived-pages.sh" \
  "orchestrating-ai-development-setup Step 3-1がrelatedApis解決の担当を明記している" || rc=1
check_step_section "$screenlist_file" "^## Step 2-4" "^## Phase 3" "--api-manifest" \
  "generating-screen-list-for-reverse-docs Step 2-4がapi-manifest既存時の--api-manifest付与を明記している" || rc=1

exit "$rc"
