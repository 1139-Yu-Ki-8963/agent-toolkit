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
# 判定が保留の記録は、標準エラーへ[SKIP]判定-保留を出して飛ばす。飛ばした
# 記録は不合格に数えず、同一性の照合も行わない。呼び出し側に断りの引数は
# 無く、この既定の振る舞いが完了の唯一の定義になる（第1回改善指示書
# 1-17。引数で切り替える案は意味を2つ残し付け忘れで再発するため退けた）。
#
# 単位のフォルダ名はreverse-shared/scripts/list-units-of.shの出力（5列目）
# から得る（unit-dir-name.shは呼ばない）。一覧の元データが無い、または該当
# する識別子の行が無いときだけ、unit-dir-name.shへ識別子を渡した値を使う
# （一覧不在時の現行維持のためのfallbackであり唯一の定義の再実装ではない）。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   記録-不在        合格の記録ファイルが実在しない
#   判定-保留（飛ばす）  記録の判定が保留（不合格に数えず飛ばす）
#   判定-不合格（不合格・不明）  記録の判定が不合格または不明（保留は含まない）
#   同一性-不一致    記録のsha256と現在の文書のsha256が一致しない
#   共有部品-不在    unit-dir-name.shが無い（--kind指定時）
#
# 終了コード:
#   0 = 対象の記録（保留を除く）が実在し判定=合格で、文書のsha256が一致
#   1 = 記録が無い・判定が不合格または不明・sha256が不一致（保留は除く）
#   2 = 使い方の誤り（判定不能）
#
# 標準出力: 照合を終えると「照合 N 件 / 飛ばした保留 M 件」を1行出す。
#
# 保守責任者: 人手（ユーザー）。共通設計文書6つの一覧や記録の形を変えるときは、
#   本スクリプトとrecord-acceptance.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
LIST_UNITS_OF_SH="${SCRIPT_DIR}/list-units-of.sh"
COMMON_DOCS="業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書 基盤設計書"

# 単位のフォルダ名をlist-units-of.shの5列目から得る。一覧が無い、または
# 該当する識別子の行が無ければ、unit-dir-name.shへ識別子を渡した値へ
# fallbackする（一覧不在時の現行維持）。
unit_folder_name() {
  local design_root="$1" kind="$2" unit="$3" folder=""
  if [ -f "$LIST_UNITS_OF_SH" ]; then
    folder="$(bash "$LIST_UNITS_OF_SH" "$design_root" "$kind" 2>/dev/null \
      | awk -F'\t' -v id="$unit" '$1==id{print $5; exit}')"
  fi
  if [ -z "$folder" ]; then
    folder="$(bash "$UNIT_DIR_NAME_SH" "$unit")"
  fi
  printf '%s' "$folder"
}

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

# 記録ファイルの判定=合格・文書のsha256一致を確かめる。$1: 記録ファイル
# $2: 文書ディレクトリ（記録の「文書」キーがこの下のファイル名に対応する）
# 判定が保留の記録は不合格に数えず飛ばす（CHECKED_COUNT/SKIPPED_PENDING_COUNTへ集計）。
check_record_record() {
  local record="$1" doc_dir="$2"
  CHECKED_COUNT=$((CHECKED_COUNT + 1))
  if [ ! -f "$record" ]; then
    echo "[FAIL] 記録-不在: ${record} が実在しません" >&2
    return 1
  fi
  local verdict
  verdict="$(jq -r '.["判定"] // empty' "$record" 2>/dev/null)"
  if [ "$verdict" = "保留" ]; then
    echo "[SKIP] 判定-保留: ${record} は保留のため照合を飛ばします" >&2
    SKIPPED_PENDING_COUNT=$((SKIPPED_PENDING_COUNT + 1))
    return 0
  fi
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
  dirname="$(unit_folder_name "$design_root" "$kind" "$unit")"
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

  CHECKED_COUNT=0
  SKIPPED_PENDING_COUNT=0

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
  echo "照合 ${CHECKED_COUNT} 件 / 飛ばした保留 ${SKIPPED_PENDING_COUNT} 件"
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
  echo "# 画面基本設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"

  local record_sh="${SCRIPT_DIR}/record-acceptance.sh"
  sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
  local run="$base/run"
  mkdir -p "$run"

  bash "$record_sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" \
    --judged "画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")" \
    --reason "" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d" --kind screen --unit "src/pages/OrderList.tsx" \
    > "$base/v1.out" 2>"$base/v1.err"
  check "合格記録は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  echo "# 変更後" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
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
    bash "$record_sh" "$d" --run "$run" --common "$name" --verdict 合格 --viewpoints "" \
      --judged "${name}.md=$(sha_of "$d/docs/design/common/${name}.md")" --reason "" > /dev/null 2>&1
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
  echo "# 画面基本設計書" > "$design3/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$design3/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  bash "$record_sh" "$dc2" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" \
    --judged "画面基本設計書.md=$(sha_of "$design3/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$design3/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")" \
    --reason "" --design-root "$design3" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$dc2" --kind screen --unit "src/pages/OrderList.tsx" --design-root "$design3" \
    > "$base/v6.out" 2>"$base/v6.err"
  check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 種別ごとの文書名で記録直後の照合が0（api・table・feature） ---
  local d2="$base/target2" run2="$base/run2"
  mkdir -p "$d2" "$run2"

  mkdir -p "$d2/docs/design/apis/api_get_orders"
  echo "# API基本設計書" > "$d2/docs/design/apis/api_get_orders/API基本設計書.md"
  echo "# API単体テスト設計書" > "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md"
  bash "$record_sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" \
    --judged "API基本設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API基本設計書.md");API単体テスト設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md")" \
    --reason "" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" \
    > "$base/v7.out" 2>"$base/v7.err"
  check "api種別: 記録直後の照合は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/tables/orders"
  echo "# 論理データモデル" > "$d2/docs/design/tables/orders/論理データモデル.md"
  echo "# テーブル単体テスト設計書" > "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md"
  bash "$record_sh" "$d2" --run "$run2" --kind table --unit "orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" \
    --judged "論理データモデル.md=$(sha_of "$d2/docs/design/tables/orders/論理データモデル.md");テーブル単体テスト設計書.md=$(sha_of "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md")" \
    --reason "" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind table --unit "orders" \
    > "$base/v8.out" 2>"$base/v8.err"
  check "table種別: 記録直後の照合は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/features/注文機能"
  echo "# 機能設計書" > "$d2/docs/design/features/注文機能/機能設計書.md"
  echo "# 機能単体テスト設計書" > "$d2/docs/design/features/注文機能/機能単体テスト設計書.md"
  bash "$record_sh" "$d2" --run "$run2" --kind feature --unit "注文機能" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" \
    --judged "機能設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能設計書.md");機能単体テスト設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能単体テスト設計書.md")" \
    --reason "" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind feature --unit "注文機能" \
    > "$base/v9.out" 2>"$base/v9.err"
  check "feature種別: 記録直後の照合は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 保留の単位は既定で飛ばす ---
  local d3="$base/target3"
  mkdir -p "$d3/docs/design/screens/src_pages_Pending.tsx" "$d3/ai-work/records/basic-design-acceptance"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md"
  bash "$record_sh" "$d3" --run "$run" --kind screen --unit "src/pages/Pending.tsx" \
    --verdict 保留 --viewpoints "不明点の不在=否" \
    --judged "画面基本設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md")" \
    --reason "既定を置けない不明点がある" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/Pending.tsx" \
    > "$base/v10.out" 2>"$base/v10.err"
  check "保留の単位は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  check "保留の単位は理由にSKIP判定-保留" "$(grep -qF '判定-保留' "$base/v10.err" && echo 0 || echo 1)"

  bash "$record_sh" "$d3" --run "$run" --kind screen --unit "src/pages/Pending.tsx" \
    --verdict 不合格 --viewpoints "不明点の不在=否" \
    --judged "画面基本設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md")" \
    --reason "業務ルールが未確定" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/Pending.tsx" \
    > "$base/v11.out" 2>"$base/v11.err"
  check "保留でなく不合格なら終了コード1" "$([ $? -eq 1 ] && echo 0 || echo 1)"
  check "保留でなく不合格なら理由に判定-不合格" "$(grep -qF '判定-不合格' "$base/v11.err" && echo 0 || echo 1)"

  # --- 共通設計文書の1つが保留でも残りが合格なら終了コード0 ---
  mkdir -p "$d3/docs/design/common"
  for name in 業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書; do
    echo "# ${name}" > "$d3/docs/design/common/${name}.md"
    bash "$record_sh" "$d3" --run "$run" --common "$name" --verdict 合格 --viewpoints "" \
      --judged "${name}.md=$(sha_of "$d3/docs/design/common/${name}.md")" --reason "" > /dev/null 2>&1
  done
  echo "# 基盤設計書" > "$d3/docs/design/common/基盤設計書.md"
  bash "$record_sh" "$d3" --run "$run" --common 基盤設計書 \
    --verdict 保留 --viewpoints "" \
    --judged "基盤設計書.md=$(sha_of "$d3/docs/design/common/基盤設計書.md")" --reason "既定を置けない不明点がある" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --common \
    > "$base/v12.out" 2>"$base/v12.err"
  check "共通設計文書の1つが保留でも残りが合格なら終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  check "共通設計文書の保留はSKIP判定-保留" "$(grep -qF '判定-保留' "$base/v12.err" && echo 0 || echo 1)"

  # --- 観点に要確認を含む合格の記録は照合で終了コード0 ---
  mkdir -p "$d3/docs/design/screens/src_pages_YakuKakunin.tsx" "$run/confirmations"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_YakuKakunin.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_YakuKakunin.tsx/画面単体テスト設計書.md"
  cat > "$run/confirmations/確認事項の記録.md" <<'CONFEOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 性能-数値目標 | src/pages/YakuKakunin.tsx | 確認事項 | 性能の数値目標が無い | 既定なし | 方式設計書 | 未回答 | 未回答 |
CONFEOF
  bash "$record_sh" "$d3" --run "$run" --kind screen --unit "src/pages/YakuKakunin.tsx" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" \
    --judged "画面基本設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_YakuKakunin.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_YakuKakunin.tsx/画面単体テスト設計書.md")" \
    --reason "性能-数値目標は要確認事項一覧に登録済み" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/YakuKakunin.tsx" \
    > "$base/v13.out" 2>"$base/v13.err"
  check "要確認を含む合格の記録は照合で終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

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
