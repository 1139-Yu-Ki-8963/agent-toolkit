#!/usr/bin/env bash
# measure-file-diff.test.sh — measure-file-diff.sh の自己テスト（合成フィクスチャ）。
#
# ## 設計判断
#
# **必要性**: measure-file-diff.sh は契約突合（6カテゴリの正規表現抽出＋集合突合）を
# 新設し、verdict の判定式を変更した。抽出ロジックの回帰（一致ペアで誤検出しない・
# 欠落ペアで確実に検出する）を都度手動確認するとトークン消費が大きく再現性もないため、
# 合成フィクスチャによる自己テストをスクリプト化する。
#
# **代替案を採用しなかった理由**:
# - Bash ツール直叩き: 一致/欠落の2ケース×フィクスチャ生成×12行の出力照合を都度
#   手書きすると再現性がなく回帰テストとして機能しない
# - 既存 Makefile ターゲット拡張: 本リポジトリの skills 配下に Makefile は存在しない
# - package.json scripts 追加: 本スキルは Node プロジェクトではなくシェルスクリプト
#   ベースの計測ツールであり scripts セクションを持たない
#
# **保守責任者**: 人手。measure-file-diff.sh の抽出ロジック変更時に同時更新する。
#
# **廃棄条件**: measure-file-diff.sh が契約突合方式を廃止した時、または本スキルが
# 検証専任構成から外れた時。
#
# 使い方:
#   bash measure-file-diff.test.sh
#
# macOS bash 3.2 互換: mapfile 等の bash4 専用機能は使わない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/measure-file-diff.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/measure-file-diff-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

FAIL=0

# --- 合成フィクスチャ本体 ---
# export（interface/const/function）・const リテラル・ハンドラ（const handleXxx +
# JSX onClick）・型（interface）・useState 分割代入・fetch 呼び出しを各1つ以上含む。
read -r -d '' FIXTURE_BASE <<'EOF' || true
import React, { useState } from 'react';

export interface UserProps {
  id: string;
}

export const MAX_COUNT = 10;

export function UserCard({ id }: UserProps) {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    fetch("/api/users");
    setCount(count + 1);
  };

  return (
    <button onClick={handleClick} className="btn">
      {count}
    </button>
  );
}
EOF

# --- ケース1: 一致ペア ---
CASE1_DIR="$WORKDIR/case1"
mkdir -p "$CASE1_DIR"
printf '%s\n' "$FIXTURE_BASE" > "$CASE1_DIR/original.tsx"
printf '%s\n' "$FIXTURE_BASE" > "$CASE1_DIR/generated.tsx"

CASE1_OUTPUT="$(bash "$TARGET" "$CASE1_DIR/generated.tsx" "$CASE1_DIR/original.tsx")"
CASE1_VERDICT="$(printf '%s\n' "$CASE1_OUTPUT" | sed -n 's/^verdict=//p')"
CASE1_CONTRACT="$(printf '%s\n' "$CASE1_OUTPUT" | sed -n 's/^contract_match=//p')"

if [ "$CASE1_VERDICT" = "PASS" ] && [ "$CASE1_CONTRACT" = "YES" ]; then
  echo "ケース1(一致ペア): PASS (verdict=${CASE1_VERDICT} contract_match=${CASE1_CONTRACT})"
else
  echo "ケース1(一致ペア): FAIL (期待 verdict=PASS contract_match=YES / 実測 verdict=${CASE1_VERDICT} contract_match=${CASE1_CONTRACT})"
  printf '%s\n' "$CASE1_OUTPUT"
  FAIL=1
fi

# --- ケース2: export欠落ペア(原本の "export const MAX_COUNT" から export を1件削る) ---
CASE2_DIR="$WORKDIR/case2"
mkdir -p "$CASE2_DIR"
printf '%s\n' "$FIXTURE_BASE" > "$CASE2_DIR/original.tsx"
printf '%s\n' "$FIXTURE_BASE" | sed -E 's/^export const MAX_COUNT/const MAX_COUNT/' > "$CASE2_DIR/generated.tsx"

CASE2_OUTPUT="$(bash "$TARGET" "$CASE2_DIR/generated.tsx" "$CASE2_DIR/original.tsx")"
CASE2_VERDICT="$(printf '%s\n' "$CASE2_OUTPUT" | sed -n 's/^verdict=//p')"
CASE2_CONTRACT="$(printf '%s\n' "$CASE2_OUTPUT" | sed -n 's/^contract_match=//p')"
CASE2_EXPORT_DIFF="$(printf '%s\n' "$CASE2_OUTPUT" | sed -n 's/^export_diff_lines=//p')"

if [ "$CASE2_VERDICT" = "FAIL" ] && [ "$CASE2_CONTRACT" = "NO" ] && [ "$CASE2_EXPORT_DIFF" -ne 0 ]; then
  echo "ケース2(export欠落ペア): PASS (verdict=${CASE2_VERDICT} contract_match=${CASE2_CONTRACT} export_diff_lines=${CASE2_EXPORT_DIFF})"
else
  echo "ケース2(export欠落ペア): FAIL (期待 verdict=FAIL contract_match=NO export_diff_lines!=0 / 実測 verdict=${CASE2_VERDICT} contract_match=${CASE2_CONTRACT} export_diff_lines=${CASE2_EXPORT_DIFF})"
  printf '%s\n' "$CASE2_OUTPUT"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS"
  exit 0
else
  exit 1
fi
