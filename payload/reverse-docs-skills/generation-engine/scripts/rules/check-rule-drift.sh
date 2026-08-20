#!/usr/bin/env bash
# check-rule-drift.sh — 規約派生物（rule.md / *.mdc）の手作業編集検知（台帳を使わない再生成突合）
#
# 目的:
#   docs/rules/ の定義から派生物を一時ディレクトリへ生成し直し、実際の派生物
#   （<out_root>/.claude/rules/**/rule.md・<out_root>/.cursor/rules/*.mdc）と
#   内容を突き合わせる。ハッシュを記録した台帳は持たない。台帳は状態をファイルへ
#   持つ仕組みであり、記録と現物がずれたときにどちらが正かを決められない。毎回
#   その場で定義から生成して比べれば、docs/rules/ が唯一の正になる。設計の定義は
#   delivery-payload/references/規約定義と派生生成の設計.md の6節。
#
# 対象（丸ごと生成されるファイルだけ）:
#   <out_root>/.claude/rules/**/rule.md
#   <out_root>/.cursor/rules/*.mdc
#   AGENTS.md と各ツールのhooks登録ファイルは、既存内容の一部だけを差し替える
#   方式のため対象外（ファイル全体の突合では人の手による他の編集と区別できない）。
#
# 使い方:
#   check-rule-drift.sh <docs/rules のルート> <出力先リポジトリルート>
#   check-rule-drift.sh --self-test
#
# 判定方法:
#   1. mktemp -d で一時ディレクトリを作る
#   2. build-derived-rules.sh <docs/rules のルート> <一時ディレクトリ> --apply を実行する
#      （同ディレクトリに配備されている build-derived-rules.sh を呼ぶ。
#      --deploy-rule-scripts は本スクリプトと build-derived-rules.sh を同じフォルダへ
#      複製するため、常に隣に実在する前提でよい）
#   3. 一時ディレクトリの生成物と、出力先リポジトリの現物を対象2種類で1件ずつ比べる
#   4. 内容が違う・現物にしかない・一時ディレクトリにしかない、をそれぞれ報告する
#   5. 一時ディレクトリを削除する
#
# 終了コード: ずれなし0 / ずれあり1 / 前提不足（root不在・生成失敗等）2
#
# 保守責任者: 人手（ユーザー）。対象パターン（丸ごと生成されるファイルの種類）を
#   増減する場合は本スクリプトの list_targets と
#   delivery-payload/references/規約定義と派生生成の設計.md の6節を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build-derived-rules.sh"

usage() {
  echo "usage: $0 <docs/rules のルート> <出力先リポジトリルート> | --self-test" >&2
  exit 2
}

# root からの相対パスで、対象2種類（丸ごと生成されるファイルだけ）を
# 決定的な順序（path昇順）で列挙する（bash 3.2互換のためmapfileは使わない）。
list_targets() {
  local root="$1"
  (
    cd "$root" 2>/dev/null || exit 0
    if [ -d ".claude/rules" ]; then
      find ".claude/rules" -type f -name 'rule.md' 2>/dev/null
    fi
    if [ -d ".cursor/rules" ]; then
      find ".cursor/rules" -type f -name '*.mdc' 2>/dev/null
    fi
  ) | LC_ALL=C sort || true
}

# docs/rules の定義から一時ディレクトリへ生成し直し、出力先リポジトリの現物と突合する。
cmd_check() {
  local rules_root="$1" out_root="$2"
  # 明示テンプレート付きmktemp -d（"${TMPDIR:-/tmp}/<name>.XXXXXX"）を使う。裸のmktemp -dは
  # $TMPDIRを無視し書き込み許可の外にある既定領域を使うため、サンドボックス実行環境では
  # 失敗する（改善課題「一時ディレクトリ-作成先」。手元の環境で動いても裸の形へ戻すな）。
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-drift.XXXXXX")"

  local build_rc=0
  "$BUILD_SCRIPT" "$rules_root" "$tmp" --apply >/dev/null 2>&1 || build_rc=$?
  if [ "$build_rc" -ne 0 ]; then
    echo "ERROR: build-derived-rules.sh --apply が失敗した（rules_root=${rules_root}）" >&2
    rm -rf "$tmp"
    return 2
  fi

  local drift=0 rel

  # 定義から生成されるはずのものを基準に、現物との一致（MODIFIED）・不在（DELETED）を検知する
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${out_root}/${rel}" ]; then
      echo "DELETED: ${rel}"
      drift=1
      continue
    fi
    if ! diff -q "${tmp}/${rel}" "${out_root}/${rel}" >/dev/null 2>&1; then
      echo "MODIFIED: ${rel}"
      drift=1
    fi
  done <<LIST
$(list_targets "$tmp")
LIST

  # 現物にはあるが、定義からの生成物には無いもの（ADDED）を検知する
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "${tmp}/${rel}" ]; then
      echo "ADDED: ${rel}"
      drift=1
    fi
  done <<LIST
$(list_targets "$out_root")
LIST

  rm -rf "$tmp"

  if [ "$drift" -eq 0 ]; then
    echo "CLEAN: 定義からの再生成と一致（ずれなし）"
    return 0
  fi
  echo "DRIFT: 生成物に定義との不一致がある。手作業編集の可能性がある。定義（docs/rules/）を直して再生成するか、意図した変更なら定義側を直す" >&2
  return 1
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

bst_write_fixture() {
  # $1: docs/rules のルート相当のフィクスチャ
  local root="$1"
  mkdir -p "${root}/agent-operations/ai-behavior"
  cat > "${root}/agent-operations/parent.yml" <<'EOF'
key: agent-operations
title: AIエージェント運用
EOF
  cat > "${root}/agent-operations/ai-behavior/rule.md" <<'EOF'
---
key: ai-behavior
title: AIエージェント行動規約
parent: agent-operations
summary: AIエージェントへの作業委任の取り決め。
scope: always
paths: ["**/*"]
enforcement: advisory
checkable: false
checker: null
uncheckableReason: 行動の是非は静的解析では判定できない。
formatter: none
status: approved
origin: proposal
---

# AIエージェント行動規約

## 概要

テスト用の概要。

## 規則

| 規則 | 内容 | 根拠 | 検査 |
|---|---|---|---|
| 例 | 例 | 例 | 静的解析: 例 |

## 違反時の手順

1. 例
EOF
}

self_test() {
  local rc=0 pass=0 fail=0
  local rules_root out rel_rule rel_mdc

  rules_root="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-drift-self-test-rules.XXXXXX")"
  out="$(mktemp -d "${TMPDIR:-/tmp}/check-rule-drift-self-test-out.XXXXXX")"
  bst_write_fixture "$rules_root"

  "$BUILD_SCRIPT" "$rules_root" "$out" --apply >/dev/null 2>&1

  rel_rule=".claude/rules/always/agent-operations/ai-behavior/rule.md"
  rel_mdc=".cursor/rules/agent-operations-ai-behavior.mdc"

  if [ ! -f "${out}/${rel_rule}" ] || [ ! -f "${out}/${rel_mdc}" ]; then
    echo "  [FAIL] 前提: フィクスチャの生成に失敗した" >&2
    rm -rf "$rules_root" "$out"
    return 1
  fi

  # ケース1（ずれなし・検知しない）: 生成直後は定義と現物が一致する
  local out1 rc1
  rc1=0
  out1="$("$0" "$rules_root" "$out" 2>&1)" || rc1=$?
  if [ "$rc1" -eq 0 ] && printf '%s' "$out1" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  [PASS] ケース1: 生成直後はずれなし（CLEAN・exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース1: 生成直後の判定が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2（ずれあり・検知する）: 現物のrule.mdを書き換えるとMODIFIEDを検知する
  local original_rule out2 rc2
  original_rule="$(cat "${out}/${rel_rule}")"
  printf '%s\n手で書き換えた行\n' "$original_rule" > "${out}/${rel_rule}"
  rc2=0
  out2="$("$0" "$rules_root" "$out" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q "^MODIFIED: ${rel_rule}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース2: rule.mdの手作業編集をMODIFIEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース2: MODIFIED検知が不正 (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi
  printf '%s' "$original_rule" > "${out}/${rel_rule}"

  # ケース3（ずれあり・検知する）: 現物の.mdcを削除するとDELETEDを検知する
  local out3 rc3
  rm -f "${out}/${rel_mdc}"
  rc3=0
  out3="$("$0" "$rules_root" "$out" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ] && printf '%s' "$out3" | grep -q "^DELETED: ${rel_mdc}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース3: .mdcの削除をDELETEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース3: DELETED検知が不正 (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi
  "$BUILD_SCRIPT" "$rules_root" "$out" --apply >/dev/null 2>&1

  # ケース4（ずれあり・検知する）: 定義に無いファイルを現物へ追加するとADDEDを検知する
  local rel_extra=".cursor/rules/extra-not-in-definitions.mdc"
  local out4 rc4
  printf 'extra' > "${out}/${rel_extra}"
  rc4=0
  out4="$("$0" "$rules_root" "$out" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 1 ] && printf '%s' "$out4" | grep -q "^ADDED: ${rel_extra}\$"; then
    pass=$((pass+1)); echo "  [PASS] ケース4: 定義に無いファイルの追加をADDEDとして検知（exit 1）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース4: ADDED検知が不正 (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi
  rm -f "${out}/${rel_extra}"

  # ケース5（ずれなし・検知しない）: 現物を戻すと再びCLEANに戻る
  local out5 rc5
  rc5=0
  out5="$("$0" "$rules_root" "$out" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 0 ] && printf '%s' "$out5" | grep -q '^CLEAN:'; then
    pass=$((pass+1)); echo "  [PASS] ケース5: 現物を戻すと再びずれなしに戻る（CLEAN・exit 0）"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース5: 復元後の判定が不正 (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi

  rm -rf "$rules_root" "$out"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    rc=0
  else
    echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
    rc=1
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

[ $# -eq 2 ] || usage

RULES_ROOT="$1"
OUT_ROOT="$2"

[ -n "$RULES_ROOT" ] && [ -d "$RULES_ROOT" ] || { echo "ERROR: docs/rules のルートが存在しない: ${RULES_ROOT:-（未指定）}" >&2; exit 2; }
[ -n "$OUT_ROOT" ] && [ -d "$OUT_ROOT" ] || { echo "ERROR: 出力先リポジトリルートが存在しない: ${OUT_ROOT:-（未指定）}" >&2; exit 2; }

cmd_check "$RULES_ROOT" "$OUT_ROOT"
