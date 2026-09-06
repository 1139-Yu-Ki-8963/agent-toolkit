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
#   check-acceptance-record.sh <対象リポジトリのルート> --kind <種別> --unit <識別子> [--design-root <設計書のルート>] [--run <実行フォルダ>]
#   check-acceptance-record.sh <対象リポジトリのルート> --common [--design-root <設計書のルート>] [--run <実行フォルダ>]
#   check-acceptance-record.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。合格の記録・基本設計書・
# 単体テスト設計書・共通設計文書は設計書のルート配下で読む。
#
# --common は共通設計文書6つ（業務仕様書・方式設計書・データ設計書・
# エラー設計書・共通外部仕様書・基盤設計書）すべての合格を確かめる
# （工程2-7・2-8の入口はこの形で呼ぶ）。
#
# --run は要確認のキー照合（下記5点目）に使う実行フォルダ。要確認の観点を
# 1つでも持つ記録では--runが必須である。省略した場合、または--runを渡して
# も確認事項の記録.mdを参照できない場合は、要確認-判定不能として不合格に
# する（後方互換より正しさを取る。2026-09-06改善）。要確認を持たない記録
# は--runの有無によらず他の4点だけを検査する。
#
# 単位・共通設計文書の保留は廃止（2026-09-05）。判定は合格・不合格の2値。
# 記録の「判定」が保留を含む合格・不合格以外の値であれば判定-不合格として
# 扱う（record-acceptance.shはもう保留を書かないが、過去の記録が残っていても
# 特別扱いしない）。
#
# 判定=合格の記録は、文書の同一性を見る前に観点の欄を読み次を確かめる
# （改善指示書1-25・1-18・1-25再検証。流れの設計「完了判定の状態」）。
# 値の定義はviewpoint-validation.shをrecord-acceptance.shと共有する。
#   1. 観点がJSONのオブジェクトでなければ観点-形式不正で不合格（文字列・
#      配列・nullはいずれも同じ扱い。to_entriesが偶然通る配列・空文字列の
#      lengthが0でない文字列を見逃さないための検査）
#   2. 観点が1つも無ければ観点-不在で不合格
#   3. 観点のキーが空文字列であれば観点の値-不正（キー空）で不合格
#   4. 観点の値が合・否・要確認のいずれでもなければ観点の値-不正で不合格
#   5. 否が1つでもあるのに判定が合格なら判定-観点と不整合で不合格
#   6. 要確認があるのに--runが無い、または確認事項の記録.mdを参照できない
#      なら要確認-判定不能で不合格
#   7. 要確認があるとき、理由に確認事項一覧のキーが無ければ要確認-キー不在
#      で不合格（record-acceptance.shのcheck_yakukakunin_keyと同じ判定）
# 「対象外」という観点の値は設けない（項目の対象外は基本設計書の項目の
# 書き方で表す。流れの設計の決定）。
#
# 単位のフォルダ名はreverse-shared/scripts/list-units-of.shの出力（5列目）
# から得る（unit-dir-name.shは呼ばない）。一覧の元データが無い、または該当
# する識別子の行が無いときだけ、unit-dir-name.shへ識別子を渡した値を使う
# （一覧不在時の現行維持のためのfallbackであり唯一の定義の再実装ではない）。
#
# 検査キー（内容を要約した意味語。連番禁止）:
#   記録-不在        合格の記録ファイルが実在しない
#   判定-不合格（不合格・不明）  記録の判定が合格以外
#   観点-形式不正    観点がJSONのオブジェクトでない（文字列・配列・null等）
#   観点-不在        判定=合格の記録に観点が1つも無い
#   観点の値-不正    観点の値が合・否・要確認のいずれでもない、またはキーが空
#   判定-観点と不整合  否があるのに判定が合格
#   要確認-判定不能   要確認の観点があるのに--runが無い、または確認事項の記録.mdを参照できない
#   要確認-キー不在   要確認の観点があるのに理由に確認事項一覧のキーが無い
#   同一性-不一致    記録のsha256と現在の文書のsha256が一致しない
#   共有部品-不在    unit-dir-name.shが無い（--kind指定時）
#
# 終了コード:
#   0 = 対象の記録が実在し判定=合格で、観点が整合し、文書のsha256が一致
#   1 = 記録が無い・判定が合格以外・観点が形式不正/不在/不正・観点が判定と
#       不整合・要確認が判定不能またはキーが無い・sha256が不一致
#   2 = 使い方の誤り（判定不能）
#
# 標準出力: 照合を終えると「照合 N 件」を1行出す。
#
# 保守責任者: 人手（ユーザー）。共通設計文書6つの一覧や記録の形を変えるときは、
#   本スクリプトとrecord-acceptance.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
# shellcheck source=viewpoint-validation.sh
. "${SCRIPT_DIR}/viewpoint-validation.sh"
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
  echo "使い方: check-acceptance-record.sh <対象> --kind <種別> --unit <識別子> [--design-root <設計書のルート>] [--run <実行フォルダ>]" >&2
  echo "        check-acceptance-record.sh <対象> --common [--design-root <設計書のルート>] [--run <実行フォルダ>]" >&2
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

# 判定=合格の記録の観点の欄を検査する。$1: 記録ファイル $2: run_dir
# （空文字列は「--run未指定」を意味する。要確認が無ければ影響しない）
# 改善指示書1-25・1-18。観点-形式不正・観点-不在・観点の値-不正・
# 判定-観点と不整合・要確認-判定不能・要確認-キー不在の順に確かめ、
# 最初の不合格で止める。
check_viewpoints_field() {
  local record="$1" run_dir="$2"
  local vp_type
  vp_type="$(jq -r '(.["観点"] // {}) | type' "$record" 2>/dev/null)"
  if [ "$vp_type" != "object" ]; then
    echo "[FAIL] 観点-形式不正: ${record} の観点がオブジェクトではありません（${vp_type:-判定不能}）" >&2
    return 1
  fi
  local vp_count
  vp_count="$(jq -r '.["観点"] // {} | length' "$record" 2>/dev/null)"
  if [ -z "$vp_count" ] || [ "$vp_count" -eq 0 ]; then
    echo "[FAIL] 観点-不在: ${record} に観点が1つもありません" >&2
    return 1
  fi
  local entries key value has_no=1 vp_str=""
  entries="$(jq -r '.["観点"] // {} | to_entries[] | "\(.key)=\(.value)"' "$record" 2>/dev/null)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if [ -z "$key" ]; then
      echo "[FAIL] 観点の値-不正: キー空（値=${value}）" >&2
      return 1
    fi
    if ! is_valid_viewpoint_value "$value"; then
      echo "[FAIL] 観点の値-不正: ${key}=${value}" >&2
      return 1
    fi
    [ "$value" = "否" ] && has_no=0
    vp_str="${vp_str}${vp_str:+;}${key}=${value}"
  done <<VPLINES
$entries
VPLINES
  if [ "$has_no" -eq 0 ]; then
    echo "[FAIL] 判定-観点と不整合: ${record} は判定が合格なのに否の観点があります" >&2
    return 1
  fi
  local reason yk_rc
  reason="$(jq -r '.["理由"] // empty' "$record" 2>/dev/null)"
  if [ -n "$run_dir" ]; then
    check_yakukakunin_key "$vp_str" "$reason" "$run_dir"
    yk_rc=$?
    case "$yk_rc" in
      0) ;;
      2)
        echo "[FAIL] 要確認-判定不能: ${record} は確認事項の記録を参照できません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
        return 1
        ;;
      *)
        echo "[FAIL] 要確認-キー不在: ${record} の理由に確認事項一覧のキーがありません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
        return 1
        ;;
    esac
  else
    case "$vp_str" in
      *=要確認*)
        echo "[FAIL] 要確認-判定不能: ${record} は要確認の観点を持ちますが--runが指定されていません" >&2
        return 1
        ;;
    esac
  fi
  return 0
}

# 記録ファイルの判定=合格・観点の整合・文書のsha256一致を確かめる。
# $1: 記録ファイル $2: 文書ディレクトリ（記録の「文書」キーがこの下の
# ファイル名に対応する） $3: run_dir（要確認のキー照合用。空でよい）
check_record_record() {
  local record="$1" doc_dir="$2" run_dir="${3:-}"
  CHECKED_COUNT=$((CHECKED_COUNT + 1))
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
  if ! check_viewpoints_field "$record" "$run_dir"; then
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
  local design_root="$1" run_dir="${2:-}" doc name record ok=0
  for name in $COMMON_DOCS; do
    record="${design_root}/ai-work/records/basic-design-acceptance/common-${name}.json"
    if ! check_record_record "$record" "${design_root}/docs/design/common" "$run_dir"; then
      ok=1
    fi
  done
  return "$ok"
}

check_record_unit() {
  local design_root="$1" kind="$2" unit="$3" run_dir="${4:-}" folder dirname record
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
  check_record_record "$record" "${design_root}/docs/design/${folder}/${dirname}" "$run_dir"
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local kind="" unit="" common_mode=0 design_root="$target" run_dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --common) common_mode=1; shift ;;
      --design-root) design_root="$2"; shift 2 ;;
      --run) run_dir="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done

  CHECKED_COUNT=0

  local rc
  if [ "$common_mode" -eq 1 ]; then
    check_record_common_all "$design_root" "$run_dir"
    rc=$?
  elif [ -n "$kind" ] && [ -n "$unit" ]; then
    check_record_unit "$design_root" "$kind" "$unit" "$run_dir"
    rc=$?
  else
    usage_error
  fi
  echo "照合 ${CHECKED_COUNT} 件"
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
    bash "$record_sh" "$d" --run "$run" --common "$name" --verdict 合格 --viewpoints "業務ルールと例外系の確定=合" \
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

  # --- 保留は廃止。record-acceptance.shはもう保留を書けない ---
  local d3="$base/target3"
  mkdir -p "$d3/docs/design/screens/src_pages_Pending.tsx" "$d3/ai-work/records/basic-design-acceptance"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md"
  bash "$record_sh" "$d3" --run "$run" --kind screen --unit "src/pages/Pending.tsx" \
    --verdict 保留 --viewpoints "不明点の不在=否" \
    --judged "画面基本設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md")" \
    --reason "既定を置けない不明点がある" > /dev/null 2>"$base/rec_pending.err"
  local rc_pending=$?
  check "record-acceptance.shは判定「保留」を終了コード2で拒否する" "$([ "$rc_pending" -eq 2 ] && echo 0 || echo 1)"

  # --- 過去に書かれた保留の記録が残っていても特別扱いせず不合格として扱う ---
  local pending_record="$d3/ai-work/records/basic-design-acceptance/screen-src_pages_Pending.tsx.json"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/Pending.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"保留","観点":{},"理由":"既定を置けない不明点がある","判定した実行":"legacy"}' \
    > "$pending_record"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/Pending.tsx" \
    > "$base/v10.out" 2>"$base/v10.err"
  local rc10=$?
  check "過去の保留の記録は終了コード1" "$([ "$rc10" -eq 1 ] && echo 0 || echo 1)"
  check "過去の保留の記録は理由に判定-不合格" "$(grep -qF '判定-不合格' "$base/v10.err" && echo 0 || echo 1)"

  bash "$record_sh" "$d3" --run "$run" --kind screen --unit "src/pages/Pending.tsx" \
    --verdict 不合格 --viewpoints "不明点の不在=否" \
    --judged "画面基本設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d3/docs/design/screens/src_pages_Pending.tsx/画面単体テスト設計書.md")" \
    --reason "業務ルールが未確定" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/Pending.tsx" \
    > "$base/v11.out" 2>"$base/v11.err"
  check "不合格なら終了コード1" "$([ $? -eq 1 ] && echo 0 || echo 1)"
  check "不合格なら理由に判定-不合格" "$(grep -qF '判定-不合格' "$base/v11.err" && echo 0 || echo 1)"

  # --- 共通設計文書6つがすべて合格でなければ終了コード1（保留は経由しない） ---
  mkdir -p "$d3/docs/design/common"
  for name in 業務仕様書 方式設計書 データ設計書 エラー設計書 共通外部仕様書; do
    echo "# ${name}" > "$d3/docs/design/common/${name}.md"
    bash "$record_sh" "$d3" --run "$run" --common "$name" --verdict 合格 --viewpoints "業務ルールと例外系の確定=合" \
      --judged "${name}.md=$(sha_of "$d3/docs/design/common/${name}.md")" --reason "" > /dev/null 2>&1
  done
  echo "# 基盤設計書" > "$d3/docs/design/common/基盤設計書.md"
  bash "$record_sh" "$d3" --run "$run" --common 基盤設計書 \
    --verdict 不合格 --viewpoints "非機能の方式の確定=否" \
    --judged "基盤設計書.md=$(sha_of "$d3/docs/design/common/基盤設計書.md")" --reason "性能方式が未確定" > /dev/null 2>&1
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --common \
    > "$base/v12.out" 2>"$base/v12.err"
  check "共通設計文書の1つが不合格なら終了コード1" "$([ $? -eq 1 ] && echo 0 || echo 1)"
  check "共通設計文書の不合格は理由に判定-不合格" "$(grep -qF '判定-不合格' "$base/v12.err" && echo 0 || echo 1)"

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
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/YakuKakunin.tsx" --run "$run" \
    > "$base/v13.out" 2>"$base/v13.err"
  check "要確認を含む合格の記録は照合で終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 観点の値が3値の外なら終了コード1（改善指示書1-25） ---
  mkdir -p "$d3/docs/design/screens/src_pages_BadValue.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_BadValue.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_BadValue.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_BadValue.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_BadValue.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/BadValue.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"外部仕様の確定":"不明"},"理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_BadValue.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/BadValue.tsx" \
    > "$base/v14.out" 2>"$base/v14.err"
  local rc14=$?
  check "観点の値が3値の外なら終了コード1" "$([ "$rc14" -eq 1 ] && echo 0 || echo 1)"
  check "観点の値が3値の外なら理由に観点の値-不正" "$(grep -qF '観点の値-不正' "$base/v14.err" && echo 0 || echo 1)"

  # --- 否があるのに判定が合格なら終了コード1 ---
  mkdir -p "$d3/docs/design/screens/src_pages_BadNo.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_BadNo.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_BadNo.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_BadNo.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_BadNo.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/BadNo.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"業務ルールと例外系の確定":"否"},"理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_BadNo.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/BadNo.tsx" \
    > "$base/v15.out" 2>"$base/v15.err"
  local rc15=$?
  check "否があるのに判定が合格なら終了コード1" "$([ "$rc15" -eq 1 ] && echo 0 || echo 1)"
  check "否があるのに判定が合格の理由に判定-観点と不整合" "$(grep -qF '判定-観点と不整合' "$base/v15.err" && echo 0 || echo 1)"

  # --- 観点が1つも無いなら終了コード1 ---
  mkdir -p "$d3/docs/design/screens/src_pages_EmptyVp.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_EmptyVp.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_EmptyVp.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_EmptyVp.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_EmptyVp.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/EmptyVp.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{},"理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_EmptyVp.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/EmptyVp.tsx" \
    > "$base/v16.out" 2>"$base/v16.err"
  local rc16=$?
  check "観点が1つも無いなら終了コード1" "$([ "$rc16" -eq 1 ] && echo 0 || echo 1)"
  check "観点が1つも無いなら理由に観点-不在" "$(grep -qF '観点-不在' "$base/v16.err" && echo 0 || echo 1)"

  # --- --run指定で要確認のキーが理由に無いなら終了コード1（書く側が拒む値を読む側も拒む） ---
  mkdir -p "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/YakuKakuninNoKey.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"非機能の方式の確定":"要確認"},"理由":"未確定のまま進める","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_YakuKakuninNoKey.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/YakuKakuninNoKey.tsx" --run "$run" \
    > "$base/v17.out" 2>"$base/v17.err"
  local rc17=$?
  check "--run指定で要確認のキーが理由に無いなら終了コード1" "$([ "$rc17" -eq 1 ] && echo 0 || echo 1)"
  check "--run指定で要確認のキーが理由に無い理由に要確認-キー不在" "$(grep -qF '要確認-キー不在' "$base/v17.err" && echo 0 || echo 1)"

  # --- 理由を確認事項一覧のキーを含む形へ戻すと終了コード0になる ---
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_YakuKakuninNoKey.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/YakuKakuninNoKey.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"非機能の方式の確定":"要確認"},"理由":"性能-数値目標は要確認事項一覧に登録済み","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_YakuKakuninNoKey.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/YakuKakuninNoKey.tsx" --run "$run" \
    > "$base/v18.out" 2>"$base/v18.err"
  check "正しい形へ戻すと終了コード0になる" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 観点が文字列なら終了コード1（観点-形式不正） ---
  mkdir -p "$d3/docs/design/screens/src_pages_VpString.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_VpString.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_VpString.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_VpString.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_VpString.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/VpString.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":"合","理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_VpString.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/VpString.tsx" \
    > "$base/v19.out" 2>"$base/v19.err"
  local rc19=$?
  check "観点が文字列なら終了コード1" "$([ "$rc19" -eq 1 ] && echo 0 || echo 1)"
  check "観点が文字列なら理由に観点-形式不正" "$(grep -qF '観点-形式不正' "$base/v19.err" && echo 0 || echo 1)"

  # --- 観点が配列（値がすべて合・否・要確認内でも）終了コード1（観点-形式不正。to_entriesが配列も通る抜け道の封じ） ---
  mkdir -p "$d3/docs/design/screens/src_pages_VpArray.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_VpArray.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_VpArray.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_VpArray.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_VpArray.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/VpArray.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":["合","合"],"理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_VpArray.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/VpArray.tsx" \
    > "$base/v20.out" 2>"$base/v20.err"
  local rc20=$?
  check "観点が配列なら終了コード1" "$([ "$rc20" -eq 1 ] && echo 0 || echo 1)"
  check "観点が配列なら理由に観点-形式不正" "$(grep -qF '観点-形式不正' "$base/v20.err" && echo 0 || echo 1)"

  # --- 観点のキーが空文字列なら終了コード1（読む側。観点の値-不正） ---
  mkdir -p "$d3/docs/design/screens/src_pages_EmptyKey.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_EmptyKey.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_EmptyKey.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_EmptyKey.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_EmptyKey.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/EmptyKey.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"":"合"},"理由":"","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_EmptyKey.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/EmptyKey.tsx" \
    > "$base/v21.out" 2>"$base/v21.err"
  local rc21=$?
  check "観点のキーが空文字列なら終了コード1" "$([ "$rc21" -eq 1 ] && echo 0 || echo 1)"
  check "観点のキーが空文字列なら理由に観点の値-不正" "$(grep -qF '観点の値-不正' "$base/v21.err" && echo 0 || echo 1)"

  # --- 要確認ありで--run無しなら終了コード1（要確認-判定不能。後方互換より正しさを取る） ---
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/YakuKakunin.tsx" \
    > "$base/v22.out" 2>"$base/v22.err"
  local rc22=$?
  check "要確認ありで--run無しなら終了コード1" "$([ "$rc22" -eq 1 ] && echo 0 || echo 1)"
  check "要確認ありで--run無しなら理由に要確認-判定不能" "$(grep -qF '要確認-判定不能' "$base/v22.err" && echo 0 || echo 1)"

  # --- 確認事項の記録.mdが0バイトでもクラッシュせず終了コード1（bash 3.2の
  #     空配列展開でset -uが誤爆する不具合の再発防止。要確認-キー不在） ---
  local runempty="$base/run-empty-confirmations"
  mkdir -p "$runempty/confirmations"
  : > "$runempty/confirmations/確認事項の記録.md"
  mkdir -p "$d3/docs/design/screens/src_pages_EmptyConfFile.tsx"
  echo "# 画面基本設計書" > "$d3/docs/design/screens/src_pages_EmptyConfFile.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d3/docs/design/screens/src_pages_EmptyConfFile.tsx/画面単体テスト設計書.md"
  jq -n --arg n "画面基本設計書.md" --arg s "$(sha_of "$d3/docs/design/screens/src_pages_EmptyConfFile.tsx/画面基本設計書.md")" \
    --arg n2 "画面単体テスト設計書.md" --arg s2 "$(sha_of "$d3/docs/design/screens/src_pages_EmptyConfFile.tsx/画面単体テスト設計書.md")" \
    '{"種別":"screen","識別子":"src/pages/EmptyConfFile.tsx","文書":{($n):$s,($n2):$s2},"コミット":"","判定":"合格","観点":{"非機能の方式の確定":"要確認"},"理由":"未確定のまま進める","判定した実行":"legacy"}' \
    > "$d3/ai-work/records/basic-design-acceptance/screen-src_pages_EmptyConfFile.tsx.json"
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d3" --kind screen --unit "src/pages/EmptyConfFile.tsx" --run "$runempty" \
    > "$base/v23.out" 2>"$base/v23.err"
  local rc23=$?
  check "確認事項の記録.mdが0バイトでも終了コード1（クラッシュしない）" "$([ "$rc23" -eq 1 ] && echo 0 || echo 1)"
  check "確認事項の記録.mdが0バイトなら理由に要確認-キー不在" "$(grep -qF '要確認-キー不在' "$base/v23.err" && echo 0 || echo 1)"

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
