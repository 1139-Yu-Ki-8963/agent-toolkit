#!/usr/bin/env bash
set -u

# check-acceptance-record.sh — 基本設計の合格の記録が現在の文書と一致するか確かめる
#
# 目的:
#   共通処理の詳細設計・単位の詳細設計は、合格の記録が現在の文書と一致する
#   ことを入口で確かめないと、書き直された基本設計書に古い合格のまま
#   詳細設計を進めてしまう。記録の形はrecord-acceptance.shが書く形と1つに
#   決まっている。
#
# 使い方:
#   check-acceptance-record.sh <対象リポジトリのルート> --kind <種別> --unit <識別子> [--design-root <設計書のルート>]
#   check-acceptance-record.sh <対象リポジトリのルート> --common [--design-root <設計書のルート>]
#   check-acceptance-record.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。合格の記録・基本設計書・
# 単体テスト設計書・共通設計文書は設計書のルート配下で読む。
#
# --common は共通設計文書6つ（業務仕様書・方式設計書・データ設計書・
# エラー設計書・共通外部仕様書・基盤設計書）すべての合格を確かめる
# （工程2-7・2-8の入口はこの形で呼ぶ）。
#
# 単位のフォルダ名はreverse-shared/scripts/unit-dir-name.shで作る（唯一の
# 定義を再実装しない）。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   記録-不在      合格の記録ファイルが実在しない
#   判定-不合格    記録の判定が合格ではない（不合格・保留・不明）
#   同一性-不一致  記録のsha256と現在の文書のsha256が一致しない
#   共有部品-不在  unit-dir-name.shが無い（--kind指定時）
#
# 終了コード:
#   0 = 対象の記録が実在し判定=合格で、文書のsha256がすべて一致
#   1 = 記録が無い・判定が合格でない・sha256が不一致
#   2 = 使い方の誤り（判定不能）
#
# 保守責任者: 人手（ユーザー）。共通設計文書6つの一覧や記録の形を変えるときは、
#   本スクリプトとrecord-acceptance.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
COMMON_DOCS="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

usage_error() {
  echo "使い方: check-acceptance-record.sh <対象> --kind <種別> --unit <識別子> [--design-root <設計書のルート>]" >&2
  echo "        check-acceptance-record.sh <対象> --common [--design-root <設計書のルート>]" >&2
  echo "        check-acceptance-record.sh --self-test" >&2
  exit 2
}

species_folder() {
  case "$1" in
    screen) echo screens ;;
    api) echo apis ;;
    table) echo tables ;;
    batch) echo batches ;;
    report) echo reports ;;
    external) echo externals ;;
    feature) echo features ;;
    *) echo "" ;;
  esac
}

# 記録ファイルの判定=合格・文書のsha256一致を確かめる。$1: 対象  $2: 記録ファイル
# $3: 文書ディレクトリ（記録の「文書」キーがこの下のファイル名に対応する）
check_record_record() {
  local record="$1" doc_dir="$2"
  if [ ! -f "$record" ]; then
    echo "[FAIL] 記録-不在: ${record} が実在しません" >&2
    return 1
  fi
  local verdict
  verdict="$(jq -r '.["判定"] // empty' "$record" 2>/dev/null)"
  if [ "$verdict" != "合格" ]; then
    echo "[FAIL] 判定-不合格: ${record} の判定は「${verdict:-空}」です" >&2
    return 1
  fi
  local names name recorded_sha current_sha
  names="$(jq -r '.["文書"] // {} | keys[]' "$record" 2>/dev/null)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    recorded_sha="$(jq -r --arg n "$name" '.["文書"][$n] // empty' "$record" 2>/dev/null)"
    if [ -f "${doc_dir}/${name}" ]; then
      current_sha="$(shasum -a 256 "${doc_dir}/${name}" | awk '{print $1}')"
    else
      current_sha=""
    fi
    if [ "$recorded_sha" != "$current_sha" ] || [ -z "$current_sha" ]; then
      echo "[FAIL] 同一性-不一致: ${record} の「${name}」が現在の文書と一致しません" >&2
      return 1
    fi
  done <<NAMES
$names
NAMES
  return 0
}

check_record_common_all() {
  local design_root="$1" doc name record ok=0
  for name in $COMMON_DOCS; do
    record="${design_root}/ai-work/records/basic-design-acceptance/common-${name}.json"
    if ! check_record_record "$record" "${design_root}/docs/design/common"; then
      ok=1
    fi
  done
  return "$ok"
}

check_record_unit() {
  local design_root="$1" kind="$2" unit="$3" folder dirname record
  folder="$(species_folder "$kind")"
  if [ -z "$folder" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    return 2
  fi
  if [ ! -f "$UNIT_DIR_NAME_SH" ]; then
    echo "[FAIL] 共有部品-不在: unit-dir-name.sh がありません" >&2
    return 2
  fi
  dirname="$(bash "$UNIT_DIR_NAME_SH" "$unit")"
  record="${design_root}/ai-work/records/basic-design-acceptance/${kind}-${dirname}.json"
  check_record_record "$record" "${design_root}/docs/design/${folder}/${dirname}"
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local kind="" unit="" common_mode=0 design_root="$target"
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --common) common_mode=1; shift ;;
      --design-root) design_root="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done

  local rc
  if [ "$common_mode" -eq 1 ]; then
    check_record_common_all "$design_root"
    rc=$?
  elif [ -n "$kind" ] && [ -n "$unit" ]; then
    check_record_unit "$design_root" "$kind" "$unit"
    rc=$?
  else
    usage_error
  fi
  exit "$rc"
}

# ============================================================
# 自己テスト
# ============================================================

self_test() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/check-acceptance-record-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
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

  bash "$SCRIPT_DIR/check-acceptance-record.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d="$base/target"
  mkdir -p "$d/docs/design/screens/src_pages_OrderList.tsx" "$d/ai-work/records/basic-design-acceptance"
  echo "# 基本設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/基本設計書.md"
  echo "# 単体テスト設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/単体テスト設計書.md"

  local record_sh="${SCRIPT_DIR}/record-acceptance.sh"
  local run="$base/run"
  mkdir -p "$run"

  bash "$record_sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --kind screen --unit "src/pages/OrderList.tsx" \
    > "$base/v1.out" 2>"$base/v1.err"
  check "合格記録は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  echo "# 変更後" > "$d/docs/design/screens/src_pages_OrderList.tsx/基本設計書.md"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --kind screen --unit "src/pages/OrderList.tsx" \
    > "$base/v2.out" 2>"$base/v2.err"
  local rc2=$?
  check "文書変更後は終了コード1" "$([ "$rc2" -eq 1 ] && echo 0 || echo 1)"
  check "文書変更後は理由に同一性-不一致" "$(grep -qF '同一性-不一致' "$base/v2.err" && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --kind screen --unit "src/pages/存在しない.tsx" \
    > "$base/v3.out" 2>"$base/v3.err"
  local rc3=$?
  check "記録が無ければ終了コード1" "$([ "$rc3" -eq 1 ] && echo 0 || echo 1)"
  check "記録が無ければ理由に記録-不在" "$(grep -qF '記録-不在' "$base/v3.err" && echo 0 || echo 1)"

  # --- 共通設計文書の全件確認 ---
  mkdir -p "$d/docs/design/common"
  local name
  for name in 業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書; do
    echo "# ${name}" > "$d/docs/design/common/${name}.md"
    bash "$record_sh" "$d" --run "$run" --common "$name" --verdict 合格 --viewpoints "" --reason "" > /dev/null 2>&1
  done
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --common > "$base/v4.out" 2>"$base/v4.err"
  check "共通設計文書6つとも合格なら終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  echo "# 変更後" > "$d/docs/design/common/基盤設計書.md"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --common > "$base/v5.out" 2>"$base/v5.err"
  local rc5=$?
  check "共通設計文書のうち1つ変更で終了コード1" "$([ "$rc5" -eq 1 ] && echo 0 || echo 1)"

  # --- 設計書ルート分離-対象に書かない ---
  local dc2="$base/target-code-only" design3="$base/design3"
  mkdir -p "$dc2" "$design3/docs/design/screens/src_pages_OrderList.tsx" "$design3/ai-work/records/basic-design-acceptance"
  echo "# 基本設計書" > "$design3/docs/design/screens/src_pages_OrderList.tsx/基本設計書.md"
  echo "# 単体テスト設計書" > "$design3/docs/design/screens/src_pages_OrderList.tsx/単体テスト設計書.md"
  bash "$record_sh" "$dc2" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" --design-root "$design3" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$dc2" --kind screen --unit "src/pages/OrderList.tsx" --design-root "$design3" \
    > "$base/v6.out" 2>"$base/v6.err"
  check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"

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
