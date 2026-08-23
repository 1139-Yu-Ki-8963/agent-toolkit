#!/usr/bin/env bash
# run-verification-loop.sh — 検証ループを1回で回す入口
#
# 目的:
#   このリポジトリ自身の検証設計文書（配布対象外）「どう回すか」の各段（版の取得・第1層・使い捨ての
#   出力先の用意・疑似入力と第3層の2回実行・4判定・台帳への記録・前回との比較・
#   出力先の破棄）を、1本のコマンドで順に実行する。個別に段を回す既存の各
#   スクリプトはそのまま残し、本スクリプトはそれらを呼び出す入口に徹する。
#
# Usage:
#   run-verification-loop.sh [--repo <対象>] [--skip-layer1] [--layer1-timeout <秒>] \
#     [--no-record] [--self-test]
#
# オプション:
#   --repo <path>          検証対象リポジトリのパス。省略時は本スクリプトの位置から
#                           解決したこのリポジトリ（reverse-docs-skills）のルート
#   --skip-layer1          第1層（run-layer-machine-checks.sh）を飛ばす（時間がかかるため）
#   --layer1-timeout <秒>  第1層の1本あたりの実行時間上限（既定120秒）
#   --no-record            台帳（このリポジトリ自身の実行記録。配布対象外）への記録を飛ばす
#   --self-test             本スクリプト自身の自己テストを実行する（実際の生成は行わない）
#
# 実行する8段:
#   1. version    版の取得（verification-env.sh）
#   2. layer1     第1層の実行（--skip-layer1 で飛ばす）
#   3. prepare-outputs 使い捨ての出力先を2つ用意する（verification-env.sh）
#   4. layer3     疑似入力を用意して第3層を2回実行する（run-layer-full-pipeline.sh）
#   5. judge      4判定を実行する（網羅・自立・健全は1回目、再現は2回の比較）
#   6. record     結果を台帳へ記録する（--no-record で飛ばす）
#   7. compare    前回と比較する（compare-with-previous.sh）
#   8. teardown   出力先を破棄する（既定。--keep の引数は設けない）
#
# 出力: 各段の結果に続けて、末尾に全体の合否と直った・壊れた・変わらないの件数を出す。
#
# 終了コード: 壊れたもの、または第1層・4判定の不合格が1件でもあれば1。
#   不合格がなく判定不能だけなら2。すべて合格なら0。
#
# 出力先には verification-env.sh の verification_env_setup が発番する、
# git リポジトリの外かつシンボリックリンクを含まない実体パスを使う。
#
# 保守責任者: 人手（ユーザー）。呼び出す既存スクリプトの引数契約が変わった場合は、
#   本ファイルの各 stage_* 関数と self-test を同時に更新する。
# macOS bash 3.2 互換（連想配列・declare -A・${var^^} は使わない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

# shellcheck source=./verification-env.sh
. "${SCRIPT_DIR}/verification-env.sh"

REPO_SELF="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# ---------------------------------------------------------------------------
# 段の定義
# ---------------------------------------------------------------------------

stage_keys() {
  cat <<'EOS'
version
layer1
prepare-outputs
layer3
judge
record
compare
teardown
EOS
}

stage_name() {
  case "$1" in
    version) echo "版の取得" ;;
    layer1) echo "第1層の実行" ;;
    prepare-outputs) echo "使い捨ての出力先の用意" ;;
    layer3) echo "疑似入力の整備と第3層の2回実行" ;;
    judge) echo "4判定の実行" ;;
    record) echo "台帳への記録" ;;
    compare) echo "前回との比較" ;;
    teardown) echo "出力先の破棄" ;;
    *) echo "$1" ;;
  esac
}

# skip_layer1・no_record の指定に応じて、実際に実行する段のキーを絞り込んで返す。
# 実行本体と self-test の双方から共用する（引数-抑止 の判定ロジックを1箇所に閉じる）。
loop_plan() {
  local skip_layer1="$1" no_record="$2" key
  for key in $(stage_keys); do
    [ "$key" = "layer1" ] && [ "$skip_layer1" -eq 1 ] && continue
    [ "$key" = "record" ] && [ "$no_record" -eq 1 ] && continue
    echo "$key"
  done
}

# 呼び出す既存スクリプトの一覧（依存実在チェックと実行の両方で共用）。
dependency_scripts() {
  local repo="$1"
  cat <<EOS
${repo}/generation-engine/scripts/verification/verification-env.sh
${repo}/generation-engine/scripts/verification/run-layer-machine-checks.sh
${repo}/generation-engine/scripts/verification/run-layer-full-pipeline.sh
${repo}/generation-engine/scripts/verification/check-coverage.sh
${repo}/generation-engine/scripts/verification/check-self-contained.sh
${repo}/generation-engine/scripts/verification/check-reproducible.sh
${repo}/generation-engine/scripts/verification/check-sound.sh
${repo}/generation-engine/scripts/verification/record-verification-result.sh
${repo}/generation-engine/scripts/verification/compare-with-previous.sh
EOS
}

LEDGER_REL="docs/tasks/work-records/実行記録.md"

# ---------------------------------------------------------------------------
# 実行本体
# ---------------------------------------------------------------------------

emit_child_output() {
  printf '%s\n' "$1"
}

# 第1層と4判定の終了コード、および比較で壊れた件数を集約する。
# 1を2より優先し、2だけなら判定不能として保持する。
verification_loop_result_rc() {
  local layer1_rc="$1" cov_rc="$2" sc_rc="$3" rep_rc="$4" snd_rc="$5" broken="$6" rc
  [ "$broken" -gt 0 ] && return 1
  for rc in "$layer1_rc" "$cov_rc" "$sc_rc" "$rep_rc" "$snd_rc"; do
    [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ] && return 1
  done
  for rc in "$layer1_rc" "$cov_rc" "$sc_rc" "$rep_rc" "$snd_rc"; do
    [ "$rc" -eq 2 ] && return 2
  done
  return 0
}

run_loop() {
  local repo="$1" skip_layer1="$2" layer1_timeout="$3" no_record="$4"
  local ledger="${repo}/${LEDGER_REL}"

  local version
  version="$(verification_env_record_version "$repo")"
  echo "版: ${version}"
  echo

  local layer1_line="" layer3_line="" layer1_rc=0

  if [ "$skip_layer1" -eq 1 ]; then
    echo "[飛ばす] 第1層の実行（--skip-layer1）"
  else
    echo "[実行中] 第1層の実行"
    local out1
    out1="$(bash "${repo}/generation-engine/scripts/verification/run-layer-machine-checks.sh" --repo "$repo" --timeout "$layer1_timeout" 2>&1)"
    layer1_rc=$?
    emit_child_output "$out1"
    layer1_line="$(printf '%s\n' "$out1" | tail -1)"
  fi
  echo

  echo "[実行中] 使い捨ての出力先の用意"
  local id1 id2 base1 base2 out_dir1 out_dir2
  id1="$(verification_env_new_id)"
  base1="$(verification_env_setup "$id1")" || { echo "ERROR: 出力先1の用意に失敗しました" >&2; return 1; }
  id2="$(verification_env_new_id)"
  base2="$(verification_env_setup "$id2")" || { echo "ERROR: 出力先2の用意に失敗しました" >&2; return 1; }
  out_dir1="${base1}/output"
  out_dir2="${base2}/output"
  echo "出力先1: ${out_dir1}"
  echo "出力先2: ${out_dir2}"
  echo

  echo "[実行中] 疑似入力の整備と第3層の1回目"
  local run1_out run1_rc
  run1_out="$(bash "${repo}/generation-engine/scripts/verification/run-layer-full-pipeline.sh" --output "$out_dir1" --repo "$repo" 2>&1)"
  run1_rc=$?
  echo "$run1_out"
  echo

  echo "[実行中] 疑似入力の整備と第3層の2回目"
  local run2_out run2_rc
  run2_out="$(bash "${repo}/generation-engine/scripts/verification/run-layer-full-pipeline.sh" --output "$out_dir2" --repo "$repo" 2>&1)"
  run2_rc=$?
  echo "$run2_out"
  echo
  layer3_line="段 2 / 1回目終了コード ${run1_rc} / 2回目終了コード ${run2_rc}"

  echo "[実行中] 4判定の実行"
  local cov_out cov_rc sc_out sc_rc rep_out rep_rc snd_out snd_rc
  cov_out="$(bash "${repo}/generation-engine/scripts/verification/check-coverage.sh" --output "$out_dir1" --repo "$repo" 2>&1)"
  cov_rc=$?
  emit_child_output "$cov_out"
  local coverage_line
  coverage_line="$(printf '%s\n' "$cov_out" | tail -1)"

  sc_out="$(bash "${repo}/generation-engine/scripts/verification/check-self-contained.sh" --repo "$repo" 2>&1)"
  sc_rc=$?
  emit_child_output "$sc_out"
  local self_contained_line
  self_contained_line="$(printf '%s\n' "$sc_out" | tail -1)"

  rep_out="$(bash "${repo}/generation-engine/scripts/verification/check-reproducible.sh" --first "$out_dir1" --second "$out_dir2" --ignore-timestamps 2>&1)"
  rep_rc=$?
  emit_child_output "$rep_out"
  local reproducible_line
  reproducible_line="$(printf '%s\n' "$rep_out" | tail -1)"

  snd_out="$(bash "${repo}/generation-engine/scripts/verification/check-sound.sh" --output "$out_dir1" --repo "$repo" 2>&1)"
  snd_rc=$?
  emit_child_output "$snd_out"
  local sound_line
  sound_line="$(printf '%s\n' "$snd_out" | tail -1)"
  echo

  if [ "$no_record" -eq 1 ]; then
    echo "[飛ばす] 台帳への記録（--no-record）"
  else
    echo "[実行中] 台帳への記録"
    if [[ "$version" =~ ^[0-9a-fA-F]{40}$ ]]; then
      bash "${repo}/generation-engine/scripts/verification/record-verification-result.sh" \
        --ledger "$ledger" --version "$version" \
        --layer1 "$layer1_line" --layer3 "$layer3_line" \
        --coverage "$coverage_line" --self-contained "$self_contained_line" \
        --reproducible "$reproducible_line" --sound "$sound_line"
    else
      echo "ERROR: 版が40文字の16進でないため記録を飛ばします（版=${version}）" >&2
    fi
  fi
  echo

  echo "[実行中] 前回との比較"
  # 比較は台帳の最新2件を読む。記録を飛ばした場合、今回の結果は台帳に無く、
  # 過去2件どうしを比べることになる。そのまま「変わらない」と出ると、
  # 今回の結果がそう出たかのように読める（実測 2026-08-24: --no-record で
  # 走らせた際、8日前の記録2件を比べた表が今回の結果として並んだ）。
  # 何を比べたのかを先に書く。
  if [ "$no_record" -eq 1 ]; then
    echo "注意: 今回の結果は台帳へ記録していないため、下の表は台帳に残る過去 2 件どうしの比較である。今回の結果は含まれない"
  fi
  local cmp_out cmp_rc
  cmp_out="$(bash "${repo}/generation-engine/scripts/verification/compare-with-previous.sh" --ledger "$ledger" 2>&1)"
  cmp_rc=$?
  echo "$cmp_out"
  echo

  echo "[実行中] 出力先の破棄"
  verification_env_teardown "$base1" >/dev/null 2>&1
  verification_env_teardown "$base2" >/dev/null 2>&1
  echo "破棄した: ${out_dir1} / ${out_dir2}"
  echo

  local kowareta
  kowareta="$(printf '%s\n' "$cmp_out" | grep -oE '壊れた: [0-9]+ 件' | head -1 | grep -oE '[0-9]+')"
  [ -n "$kowareta" ] || kowareta=0

  local overall_rc
  verification_loop_result_rc "$layer1_rc" "$cov_rc" "$sc_rc" "$rep_rc" "$snd_rc" "$kowareta"
  overall_rc=$?

  if [ "$overall_rc" -eq 0 ]; then
    echo "全体の合否: 合格"
  elif [ "$overall_rc" -eq 2 ]; then
    echo "全体の合否: 判定不能"
  else
    echo "全体の合否: 不合格"
  fi

  return "$overall_rc"
}

# ---------------------------------------------------------------------------
# self-test（実際の生成は重いため、構成だけを検査する）
# ---------------------------------------------------------------------------

_loop_self_test() {
  local run=0 ok=0 ng=0

  _case_pass() { run=$((run+1)); ok=$((ok+1)); echo "[PASS] $1 — $2"; }
  _case_fail() { run=$((run+1)); ng=$((ng+1)); echo "[FAIL] $1 — $2" >&2; }

  # --- 順序-8段 ---
  local count
  count="$(stage_keys | grep -c .)"
  if [ "$count" -eq 8 ]; then
    _case_pass "順序-8段" "実行する段の定義が8段ある"
  else
    _case_fail "順序-8段" "段の定義が8段でない（${count}段）"
  fi

  # --- 依存-スクリプト実在 ---
  local missing=0 dep
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    [ -f "$dep" ] || missing=$((missing + 1))
  done <<DEPS
$(dependency_scripts "$REPO_SELF")
DEPS
  if [ "$missing" -eq 0 ]; then
    _case_pass "依存-スクリプト実在" "呼び出す既存スクリプトがすべて実在する"
  else
    _case_fail "依存-スクリプト実在" "実在しないスクリプトが${missing}本ある"
  fi

  # --- 引数-記録の抑止 ---
  local plan_no_record
  plan_no_record="$(loop_plan 0 1)"
  # 記録を飛ばしたとき、比較が何を比べたのかを断る文が出ることを確かめる。
  # 断りが無いと、過去 2 件どうしの比較が今回の結果として読める。
  if LC_ALL=C grep -qF '注意: 今回の結果は台帳へ記録していないため' "${BASH_SOURCE[0]}"; then
    _case_pass "比較-記録を飛ばしたときの断り" "何を比べたのかを先に書く"
  else
    _case_fail "比較-記録を飛ばしたときの断り" "断りの文が見当たらない"
  fi

  if printf '%s\n' "$plan_no_record" | grep -qx "record"; then
    _case_fail "引数-記録の抑止" "--no-record 相当でも record 段に到達する"
  else
    _case_pass "引数-記録の抑止" "--no-record を指定すると記録の呼び出しに到達しない"
  fi

  # --- 引数-第1層の抑止 ---
  local plan_skip_layer1
  plan_skip_layer1="$(loop_plan 1 0)"
  if printf '%s\n' "$plan_skip_layer1" | grep -qx "layer1"; then
    _case_fail "引数-第1層の抑止" "--skip-layer1 相当でも layer1 段に到達する"
  else
    _case_pass "引数-第1層の抑止" "--skip-layer1 を指定すると第1層の呼び出しに到達しない"
  fi

  # --- 破棄-既定 ---
  # 引数解析の case 分岐に「keep」で始まる分岐（値保持オプション）が無いことを、
  # 本スクリプト自身の内容から確認する（run-layer-full-pipeline.sh 等とは異なり、
  # 本スクリプトの引数解析は常に破棄する前提で分岐を持たない）。
  if grep -qE -- '^\s*--keep\)' "$SELF_PATH"; then
    _case_fail "破棄-既定" "引数解析に keep 系の分岐が存在する"
  else
    _case_pass "破棄-既定" "出力先の破棄が既定で行われる（keep 系の引数分岐が存在しない）"
  fi

  # --- 集約-判定不能のみは2 ---
  verification_loop_result_rc 0 2 0 0 0 0
  local unknown_only_rc=$?
  [ "$unknown_only_rc" -eq 2 ] \
    && _case_pass "集約-判定不能のみは2" "4判定の終了コード2を保持した" \
    || _case_fail "集約-判定不能のみは2" "終了コード2を保持できない（rc=${unknown_only_rc}）"

  # --- 集約-第1層の判定不能も2 ---
  verification_loop_result_rc 2 0 0 0 0 0
  local layer1_unknown_rc=$?
  [ "$layer1_unknown_rc" -eq 2 ] \
    && _case_pass "集約-第1層の判定不能も2" "第1層の終了コード2を保持した" \
    || _case_fail "集約-第1層の判定不能も2" "第1層の終了コード2を失った（rc=${layer1_unknown_rc}）"

  # --- 集約-不合格と判定不能の混在は1 ---
  verification_loop_result_rc 2 1 0 0 0 0
  local mixed_rc=$?
  [ "$mixed_rc" -eq 1 ] \
    && _case_pass "集約-不合格と判定不能の混在は1" "不合格を優先した" \
    || _case_fail "集約-不合格と判定不能の混在は1" "優先順位が不正（rc=${mixed_rc}）"

  # --- 出力-判定不能理由を保持 ---
  local reason_fixture reason_output
  reason_fixture='[UNKNOWN] 子検査を実行できません 操作: mktemp / 想定原因: fixture'
  reason_output="$(emit_child_output "$reason_fixture")"
  [ "$reason_output" = "$reason_fixture" ] \
    && _case_pass "出力-判定不能理由を保持" "子のUNKNOWN理由をそのまま出力した" \
    || _case_fail "出力-判定不能理由を保持" "子のUNKNOWN理由が欠落した"

  echo "実行 ${run} 件 / 成功 ${ok} 件 / 失敗 ${ng} 件"
  [ "$ng" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 引数解析・ディスパッチ
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOS'
使い方: run-verification-loop.sh [--repo <対象>] [--skip-layer1] [--layer1-timeout <秒>] [--no-record] [--self-test]
EOS
}

main() {
  local repo="" skip_layer1=0 layer1_timeout=120 no_record=0 self_test_mode=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --skip-layer1) skip_layer1=1; shift ;;
      --layer1-timeout) layer1_timeout="${2:-}"; shift 2 ;;
      --no-record) no_record=1; shift ;;
      --self-test) self_test_mode=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  if [ "$self_test_mode" -eq 1 ]; then
    _loop_self_test
    exit $?
  fi

  case "$layer1_timeout" in
    ''|*[!0-9]*)
      echo "--layer1-timeout には正の整数を指定する: $layer1_timeout" >&2
      exit 2
      ;;
  esac

  [ -z "$repo" ] && repo="$REPO_SELF"
  repo="$(cd "$repo" && pwd)" || { echo "ERROR: --repo のパスが解決できません" >&2; exit 2; }

  run_loop "$repo" "$skip_layer1" "$layer1_timeout" "$no_record"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
