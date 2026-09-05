#!/usr/bin/env bash
set -u

# record-acceptance.sh — 基本設計の完了判定の記録を書く（単位・共通設計文書）
#
# 目的:
#   合格の記録は文書の同一性（sha256）とコミットを持たなければ、後で文書が
#   変わったときに古い合格が生き残る。記録の形を1つに決め、詳細設計へ進む
#   機能（check-acceptance-record.sh）がその形だけを読めば済むようにする。
#
# 使い方:
#   record-acceptance.sh <対象リポジトリのルート> --run <実行フォルダ> \
#     --kind <種別> --unit <識別子> --verdict <合格|不合格|保留> \
#     --viewpoints "<観点=合|否;...>" [--reason "<理由>"] [--design-root <設計書のルート>]
#   record-acceptance.sh <対象リポジトリのルート> --run <実行フォルダ> \
#     --common <文書名> --verdict <合格|不合格|保留> \
#     --viewpoints "<観点=合|否;...>" [--reason "<理由>"] [--design-root <設計書のルート>]
#   record-acceptance.sh --self-test
#
# --design-root の既定は対象リポジトリのルート。合格の記録・基本設計書・
# 単体テスト設計書・共通設計文書は設計書のルート配下で読み書きする。
# コミットの値は対象コード（--design-root ではなく対象）のHEADを使う。
#
# 出力:
#   <対象>/ai-work/records/basic-design-acceptance/<種別>-<単位のフォルダ名>.json
#   （共通設計文書は common-<文書名>.json）に
#   {"種別","識別子","文書":{"<文書名>":"<sha256>"},"コミット":"<対象のHEAD>",
#    "判定","観点":{...},"理由","判定した実行"}
#
# 単位のフォルダ名はreverse-shared/scripts/unit-dir-name.shで作る（唯一の
# 定義を再実装しない）。種別ごとの文書名（基本設計書・単体テスト設計書。
# featureも他の6種別と同じく2件）はreverse-shared/scripts/design-doc-name.sh
# で作る（check-basic-design.shと共有し、実名の二重定義を持たない）。単位の
# 記録はreverse-shared/scripts/units-status.shの完了判定も更新する（無ければ
# この更新だけ省く）。
#
# 終了コード:
#   0 = 記録を書いた
#   2 = 使い方の誤り・種別が不正・判定の値が不正・共有部品が無い（判定不能）
#
# 保守責任者: 人手（ユーザー）。記録の形（キー）を変えるときは、本スクリプトと
#   check-acceptance-record.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
DESIGN_DOC_NAME_SH="${SCRIPT_DIR}/design-doc-name.sh"
UNITS_STATUS_SH="${SCRIPT_DIR}/units-status.sh"

usage_error() {
  echo "使い方: record-acceptance.sh <対象> --run <実行フォルダ> --kind <種別> --unit <識別子> --verdict <合格|不合格|保留> --viewpoints \"<観点=合|否;...>\" [--reason \"...\"] [--design-root <設計書のルート>]" >&2
  echo "        record-acceptance.sh <対象> --run <実行フォルダ> --common <文書名> --verdict <合格|不合格|保留> --viewpoints \"...\" [--reason \"...\"] [--design-root <設計書のルート>]" >&2
  echo "        record-acceptance.sh --self-test" >&2
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

doc_sha_json() {
  local path="$1" name="$2" sha=""
  if [ -f "$path" ]; then
    sha="$(shasum -a 256 "$path" | awk '{print $1}')"
  fi
  jq -n --arg n "$name" --arg s "$sha" '{($n): $s}'
}

parse_viewpoints_json() {
  local vp="$1"
  [ -n "$vp" ] || { echo '{}'; return 0; }
  local old_ifs="$IFS" k v entries=""
  IFS=';'
  local arr=($vp)
  IFS="$old_ifs"
  local item
  for item in "${arr[@]}"; do
    [ -n "$item" ] || continue
    k="${item%%=*}"
    v="${item#*=}"
    entries="${entries}$(jq -n --arg k "$k" --arg v "$v" '{($k): $v}')
"
  done
  printf '%s' "$entries" | jq -s 'add // {}'
}

execution_id_of() {
  local run_dir="$1" val=""
  if [ -f "${run_dir%/}/run.json" ]; then
    val="$(jq -r '.["実行の識別子"] // empty' "${run_dir%/}/run.json" 2>/dev/null)"
  fi
  [ -n "$val" ] || val="$(basename "$run_dir")"
  printf '%s' "$val"
}

record_unit() {
  local target="$1" run_dir="$2" kind="$3" unit="$4" verdict="$5" viewpoints="$6" reason="$7" design_root="$8"
  local folder
  folder="$(species_folder "$kind")"
  if [ -z "$folder" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    return 2
  fi
  if [ ! -f "$UNIT_DIR_NAME_SH" ]; then
    echo "[FAIL] 共有部品-不在: unit-dir-name.sh がありません" >&2
    return 2
  fi
  if [ ! -f "$DESIGN_DOC_NAME_SH" ]; then
    echo "[FAIL] 共有部品-不在: design-doc-name.sh がありません" >&2
    return 2
  fi

  local dirname unit_path docs_json basic_name test_name
  dirname="$(bash "$UNIT_DIR_NAME_SH" "$unit")"
  unit_path="${design_root}/docs/design/${folder}/${dirname}"

  basic_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" basic 2>/dev/null)"
  test_name="$(bash "$DESIGN_DOC_NAME_SH" "$kind" test 2>/dev/null)"
  if [ -z "$basic_name" ] || [ -z "$test_name" ]; then
    echo "[FAIL] 使い方-種別: ${kind} は種別ではありません" >&2
    return 2
  fi

  docs_json="$(printf '%s\n%s\n' \
    "$(doc_sha_json "${unit_path}/${basic_name}" "$basic_name")" \
    "$(doc_sha_json "${unit_path}/${test_name}" "$test_name")" \
    | jq -s 'add')"

  local commit vp_json exec_id out_dir out_file
  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_viewpoints_json "$viewpoints")"
  exec_id="$(execution_id_of "$run_dir")"
  out_dir="${design_root}/ai-work/records/basic-design-acceptance"
  mkdir -p "$out_dir" 2>/dev/null
  out_file="${out_dir}/${kind}-${dirname}.json"

  jq -n --arg kind "$kind" --arg id "$unit" --argjson docs "$docs_json" \
    --arg commit "$commit" --arg verdict "$verdict" --argjson vp "$vp_json" \
    --arg reason "$reason" --arg exec "$exec_id" \
    '{"種別":$kind,"識別子":$id,"文書":$docs,"コミット":$commit,"判定":$verdict,"観点":$vp,"理由":$reason,"判定した実行":$exec}' \
    > "$out_file"

  if [ -f "$UNITS_STATUS_SH" ]; then
    bash "$UNITS_STATUS_SH" "$run_dir" set "$kind" "$unit" 完了判定 "$verdict" > /dev/null 2>&1
  fi

  echo "記録: ${out_file}"
  return 0
}

record_common() {
  local target="$1" run_dir="$2" doc_name="$3" verdict="$4" viewpoints="$5" reason="$6" design_root="$7"
  local doc_path="${design_root}/docs/design/common/${doc_name}.md"
  local docs_json commit vp_json exec_id out_dir out_file
  docs_json="$(doc_sha_json "$doc_path" "${doc_name}.md")"
  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_viewpoints_json "$viewpoints")"
  exec_id="$(execution_id_of "$run_dir")"
  out_dir="${design_root}/ai-work/records/basic-design-acceptance"
  mkdir -p "$out_dir" 2>/dev/null
  out_file="${out_dir}/common-${doc_name}.json"

  jq -n --argjson docs "$docs_json" --arg commit "$commit" --arg verdict "$verdict" \
    --argjson vp "$vp_json" --arg reason "$reason" --arg exec "$exec_id" \
    '{"種別":null,"識別子":null,"文書":$docs,"コミット":$commit,"判定":$verdict,"観点":$vp,"理由":$reason,"判定した実行":$exec}' \
    > "$out_file"

  echo "記録: ${out_file}"
  return 0
}

run_main() {
  local target="$1"; shift
  target="${target%/}"
  [ -d "$target" ] || usage_error

  local run_dir="" kind="" unit="" common="" verdict="" viewpoints="" reason="" design_root="$target"
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --common) common="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --viewpoints) viewpoints="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done

  [ -n "$run_dir" ] || usage_error

  case "$verdict" in
    合格|不合格|保留) ;;
    *)
      echo "[FAIL] 使い方-判定: ${verdict:-（空）} は 合格・不合格・保留 のいずれでもありません" >&2
      exit 2
      ;;
  esac

  local rc
  if [ -n "$common" ]; then
    record_common "$target" "$run_dir" "$common" "$verdict" "$viewpoints" "$reason" "$design_root"
    rc=$?
  elif [ -n "$kind" ] && [ -n "$unit" ]; then
    record_unit "$target" "$run_dir" "$kind" "$unit" "$verdict" "$viewpoints" "$reason" "$design_root"
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
  base="$(mktemp -d "${TMPDIR:-/tmp}/record-acceptance-self-test.XXXXXX")" || { echo "一時領域を作れません" >&2; return 2; }
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
  bash "$SCRIPT_DIR/record-acceptance.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d="$base/target" run="$base/run"
  mkdir -p "$d" "$run"
  # gitのコミットは不要。対象のコミットが空でも記録は書ける（コミット=空文字）ことを確かめる

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 不明 --viewpoints "" > "$base/u2.out" 2>"$base/u2.err"
  check "使い方-判定不正は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  # --- 単位の記録 ---
  mkdir -p "$d/docs/design/screens/src_pages_OrderList.tsx"
  echo "# 画面基本設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合;単体テスト設計書の実在=合" --reason "" \
    > "$base/r1.out" 2>"$base/r1.err"
  check "単位の記録: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  local record_file="$d/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  check "単位の記録: ファイルが実在" "$([ -f "$record_file" ] && echo 0 || echo 1)"

  local verdict1 sha1 sha_expected1
  verdict1="$(jq -r '.["判定"]' "$record_file" 2>/dev/null)"
  check "単位の記録: 判定が合格" "$([ "$verdict1" = "合格" ] && echo 0 || echo 1)"
  sha1="$(jq -r '.["文書"]["画面基本設計書.md"]' "$record_file" 2>/dev/null)"
  sha_expected1="$(shasum -a 256 "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md" | awk '{print $1}')"
  check "単位の記録: 画面基本設計書の文書名でsha256が一致" "$([ "$sha1" = "$sha_expected1" ] && echo 0 || echo 1)"
  check "単位の記録: 画面基本設計書のsha256が空でない" "$([ -n "$sha1" ] && echo 0 || echo 1)"

  local vp1
  vp1="$(jq -r '.["観点"]["外部仕様の確定"]' "$record_file" 2>/dev/null)"
  check "単位の記録: 観点が反映される" "$([ "$vp1" = "合" ] && echo 0 || echo 1)"

  local status1
  status1="$(bash "${SCRIPT_DIR}/units-status.sh" "$run" get screen "src/pages/OrderList.tsx" 完了判定 2>/dev/null)"
  check "単位の記録: units-status.shの完了判定が更新される" "$([ "$status1" = "合格" ] && echo 0 || echo 1)"

  # --- 共通設計文書の記録 ---
  mkdir -p "$d/docs/design/common"
  echo "# 基盤設計書" > "$d/docs/design/common/基盤設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --common 基盤設計書 \
    --verdict 不合格 --viewpoints "非機能の方式の確定=否" --reason "性能方式が未確定" \
    > "$base/r2.out" 2>"$base/r2.err"
  check "共通設計文書の記録: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  local common_record="$d/ai-work/records/basic-design-acceptance/common-基盤設計書.json"
  local verdict2 reason2
  verdict2="$(jq -r '.["判定"]' "$common_record" 2>/dev/null)"
  reason2="$(jq -r '.["理由"]' "$common_record" 2>/dev/null)"
  check "共通設計文書の記録: 判定が不合格" "$([ "$verdict2" = "不合格" ] && echo 0 || echo 1)"
  check "共通設計文書の記録: 理由が反映される" "$([ "$reason2" = "性能方式が未確定" ] && echo 0 || echo 1)"

  # --- 設計書ルート分離-対象に書かない ---
  local dc="$base/target-code-only" design2="$base/design2"
  mkdir -p "$dc" "$design2/docs/design/screens/src_pages_OrderList.tsx"
  echo "# 画面基本設計書" > "$design2/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$design2/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$dc" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" --design-root "$design2" \
    > "$base/r3.out" 2>"$base/r3.err"
  check "設計書ルート分離-合格" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -e "$dc/ai-work" ] && [ ! -e "$dc/docs" ]; then
    echo "PASS: 設計書ルート分離-対象に書かない"
  else
    echo "FAIL: 設計書ルート分離-対象に書かない（対象側に書かれています）"
    fail=$((fail + 1))
  fi
  local record_file2="$design2/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  check "設計書ルート分離-記録が設計書のルートにある" "$([ -f "$record_file2" ] && echo 0 || echo 1)"

  # --- 種別ごとの文書名が実名と一致（api・table・feature） ---
  local d2="$base/target2" run2="$base/run2"
  mkdir -p "$d2" "$run2"

  mkdir -p "$d2/docs/design/apis/api_get_orders"
  echo "# API基本設計書" > "$d2/docs/design/apis/api_get_orders/API基本設計書.md"
  echo "# API単体テスト設計書" > "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" > "$base/r4.out" 2>"$base/r4.err"
  check "api種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local api_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  local api_basic api_test
  api_basic="$(jq -r '.["文書"]["API基本設計書.md"] // empty' "$api_record" 2>/dev/null)"
  api_test="$(jq -r '.["文書"]["API単体テスト設計書.md"] // empty' "$api_record" 2>/dev/null)"
  check "api種別: 文書名がAPI基本設計書.mdでsha256が空でない" "$([ -n "$api_basic" ] && echo 0 || echo 1)"
  check "api種別: 文書名がAPI単体テスト設計書.mdでsha256が空でない" "$([ -n "$api_test" ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/tables/orders"
  echo "# 論理データモデル" > "$d2/docs/design/tables/orders/論理データモデル.md"
  echo "# テーブル単体テスト設計書" > "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind table --unit "orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" > "$base/r5.out" 2>"$base/r5.err"
  check "table種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local table_record="$d2/ai-work/records/basic-design-acceptance/table-orders.json"
  local table_basic table_test
  table_basic="$(jq -r '.["文書"]["論理データモデル.md"] // empty' "$table_record" 2>/dev/null)"
  table_test="$(jq -r '.["文書"]["テーブル単体テスト設計書.md"] // empty' "$table_record" 2>/dev/null)"
  check "table種別: 文書名が論理データモデル.mdでsha256が空でない" "$([ -n "$table_basic" ] && echo 0 || echo 1)"
  check "table種別: 文書名がテーブル単体テスト設計書.mdでsha256が空でない" "$([ -n "$table_test" ] && echo 0 || echo 1)"

  mkdir -p "$d2/docs/design/features/注文機能"
  echo "# 機能設計書" > "$d2/docs/design/features/注文機能/機能設計書.md"
  echo "# 機能単体テスト設計書" > "$d2/docs/design/features/注文機能/機能単体テスト設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind feature --unit "注文機能" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --reason "" > "$base/r6.out" 2>"$base/r6.err"
  check "feature種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local feature_record="$d2/ai-work/records/basic-design-acceptance/feature-注文機能.json"
  local feature_basic feature_test
  feature_basic="$(jq -r '.["文書"]["機能設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  feature_test="$(jq -r '.["文書"]["機能単体テスト設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  check "feature種別: 文書名が機能設計書.mdでsha256が空でない" "$([ -n "$feature_basic" ] && echo 0 || echo 1)"
  check "feature種別: 文書名が機能単体テスト設計書.mdでsha256が空でない" "$([ -n "$feature_test" ] && echo 0 || echo 1)"

  # --- 解釈できない種別は記録を作らず終了コード2 ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind 不正種別 --unit "何か" \
    --verdict 合格 --viewpoints "" --reason "" > "$base/r7.out" 2>"$base/r7.err"
  local rc7=$?
  check "解釈できない種別は終了コード2" "$([ "$rc7" -eq 2 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$d2/ai-work/records/basic-design-acceptance/不正種別-何か.json" ]; then
    echo "PASS: 解釈できない種別は記録を作らない"
  else
    echo "FAIL: 解釈できない種別は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

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
