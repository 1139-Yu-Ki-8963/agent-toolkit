#!/usr/bin/env bash
set -u

# check-basic-phase.sh — 共通設計文書6つの機械検査を集約する
#
# 目的:
#   基本設計の完了判定のうち、共通設計文書6つは道標を描く機能の手順5の
#   最後で機械検査する。見出し構成の検査は道標を描く機能のcheck-design-docs.sh
#   を呼ぶ。単位ごとの機械検査は基本設計書を書く機能のcheck-basic-design.sh
#   がその機能の完了時の処理として直接呼ぶため、本スクリプトは持たない。
#
# 使い方:
#   check-basic-phase.sh <対象リポジトリのルート> --common --run <実行フォルダ> [--design-root <設計書のルート>]
#   check-basic-phase.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。共通設計文書は設計書の
# ルート配下で読む。
#
# 出力:
#   <実行フォルダ>/logs/basic-phase-check.json に
#   {"共通設計文書":{"<文書名>":{"実在":bool,"合格":bool}},"判定":"合格"|"不合格"}
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   共有部品-不在   check-design-docs.shが無い
#   文書-不在       共通設計文書が実在しない
#
# 終了コード:
#   0 = 全共通設計文書が合格
#   1 = 1件以上が不合格
#   2 = 使い方の誤り・共有部品が無い（判定不能）
#
# 保守責任者: 人手（ユーザー）。共通設計文書6つの一覧を変えるときは、
#   本スクリプトと道標を描く機能の様式を同時に直す。
#
# 廃棄条件: 完了判定の集約を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_DOCS_SH="${SCRIPT_DIR}/../../reverse-drawing-map/scripts/check-design-docs.sh"
COMMON_DOCS="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

usage_error() {
  echo "使い方: check-basic-phase.sh <対象リポジトリのルート> --common --run <実行フォルダ> [--design-root <設計書のルート>]" >&2
  echo "        check-basic-phase.sh --self-test" >&2
  exit 2
}

deps_available() {
  [ -f "$DESIGN_DOCS_SH" ]
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" design_root="$target" common_mode=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --common) common_mode=1; shift ;;
      --run) run_dir="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done
  [ -n "$run_dir" ] || usage_error
  [ "$common_mode" -eq 1 ] || usage_error

  if ! deps_available; then
    echo "[FAIL] 共有部品-不在: check-design-docs.sh がありません" >&2
    exit 2
  fi

  mkdir -p "${run_dir%/}/logs" 2>/dev/null
  local out_json="${run_dir%/}/logs/basic-phase-check.json"

  local overall_fail=0 doc doc_path common_entries="" entry
  for doc in $COMMON_DOCS; do
    doc_path="${design_root}/docs/design/common/${doc}.md"
    if [ ! -f "$doc_path" ]; then
      echo "[FAIL] 文書-不在: ${doc_path} が実在しません" >&2
      overall_fail=1
      entry="$(jq -n --arg d "$doc" '{($d): {"実在": false, "合格": false}}')"
    else
      if bash "$DESIGN_DOCS_SH" "$doc_path" > /dev/null 2>>"${run_dir%/}/logs/basic-phase-check-common.log"; then
        entry="$(jq -n --arg d "$doc" '{($d): {"実在": true, "合格": true}}')"
      else
        overall_fail=1
        entry="$(jq -n --arg d "$doc" '{($d): {"実在": true, "合格": false}}')"
      fi
    fi
    common_entries="${common_entries}${entry}
"
  done

  local common_json verdict
  common_json="$(printf '%s' "$common_entries" | jq -s 'add // {}')"
  if [ "$overall_fail" -eq 0 ]; then verdict="合格"; else verdict="不合格"; fi

  jq -n --argjson common "$common_json" --arg v "$verdict" \
    '{"共通設計文書": $common, "判定": $v}' > "$out_json"

  echo "判定: ${verdict}"
  if [ "$overall_fail" -eq 1 ]; then
    exit 1
  fi
  exit 0
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/check-basic-phase-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
  trap 'rm -rf "$base"' RETURN

  local total=0 fail=0

  check() {
    local name="$1" ok="$2"
    total=$((total + 1))
    if [ "$ok" -eq 0 ]; then
      echo "PASS: ${name}"
    else
      echo "FAIL: ${name}"
      fail=$((fail + 1))
    fi
  }

  # --- 使い方エラー系 ---
  bash "$SCRIPT_DIR/check-basic-phase.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/check-basic-phase.sh" "$base" > "$base/u2.out" 2>"$base/u2.err"
  check "使い方-run未指定は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/check-basic-phase.sh" "$base" --run "$base" > "$base/u3.out" 2>"$base/u3.err"
  check "使い方-common未指定は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local tmpl_dir="${SCRIPT_DIR}/../../reverse-drawing-map/templates/common"
  local docs="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

  write_common_docs() {
    local d="$1" name
    mkdir -p "$d/docs/design/common"
    for name in $docs; do
      sed -E 's/<[^<>]+>/記入済み/g' "${tmpl_dir}/${name}.md" > "$d/docs/design/common/${name}.md"
    done
  }

  # --- 合格-共通設計文書6つとも実在 ---
  local d1="$base/target1" run1="$base/run1"
  mkdir -p "$d1" "$run1"
  write_common_docs "$d1"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d1" --common --run "$run1" > "$base/c1.out" 2>"$base/c1.err"
  local rc1=$?
  check "合格-共通設計文書6つ: 終了コード0" "$([ "$rc1" -eq 0 ] && echo 0 || echo 1)"
  local verdict1
  verdict1="$(jq -r '.["判定"]' "$run1/logs/basic-phase-check.json" 2>/dev/null)"
  check "合格-共通設計文書6つ: 判定が合格" "$([ "$verdict1" = "合格" ] && echo 0 || echo 1)"

  # --- 設計書ルート分離-対象に書かない ---
  local d1c="$base/target1-code-only" design1="$base/design1" run1d="$base/run1d"
  mkdir -p "$d1c" "$design1" "$run1d"
  write_common_docs "$design1"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d1c" --common --run "$run1d" --design-root "$design1" > "$base/c1d.out" 2>"$base/c1d.err"
  check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -e "$d1c/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側にdocsが作られています）"
    fail=$((fail + 1))
  fi

  # --- 不合格-共通設計文書が1つ不在 ---
  local d2="$base/target2" run2="$base/run2"
  mkdir -p "$d2" "$run2"
  write_common_docs "$d2"
  rm -f "$d2/docs/design/common/基盤設計書.md"
  bash "$SCRIPT_DIR/check-basic-phase.sh" "$d2" --common --run "$run2" > "$base/c2.out" 2>"$base/c2.err"
  local rc2=$?
  check "不合格-共通設計文書不在: 終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"
  local base_ok2
  base_ok2="$(jq -r '.["共通設計文書"]["基盤設計書"]["実在"]' "$run2/logs/basic-phase-check.json" 2>/dev/null)"
  check "不合格-共通設計文書不在: 実在がfalse" "$([ "$base_ok2" = "false" ] && echo 0 || echo 1)"

  echo "実行 ${total} 件 / 失敗 ${fail} 件"
  if [ "$fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================
# エントリポイント
# ============================================================

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ $# -lt 1 ]; then
  usage_error
fi

run_main "$@"
