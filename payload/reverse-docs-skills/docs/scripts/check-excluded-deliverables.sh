#!/usr/bin/env bash
# check-excluded-deliverables.sh — 対象外の記録が2つの検査から別の意味で
# 読まれる問題（改善課題1-255）の修正を確かめる。
#
# 背景:
#   docs/scope-and-progress/excluded-kinds.json の excludedKinds は設計単位の
#   6種別（screen/api/table/batch/report/external）専用であり、
#   generation-engine/scripts/unit-list/check-excluded-kinds-consistency.sh が
#   presentKinds との完全一致を機械で確かめる。ところが
#   delivery-payload/references/deliverable-inventory.json は60件の納品物を
#   定義しており、6種別に属さないもの（entity-state 等）を対象外にする経路が
#   excludedKinds には無い。excludedKinds へ直接追記すると整合の検査が壊れる。
#   本検査は、6種別に属さない納品物を受ける新しい鍵 excludedDeliverables が
#   定義文書（contract.md）に明記されていること、その鍵が
#   build-deliverable-inventory.sh から正しく読まれ「対象なし」判定に使われる
#   こと、そして整合の検査（excludedKinds専用）には回帰が無いことを確かめる。
#
# 使い方:
#   check-excluded-deliverables.sh                  定義文書へ鍵の形式が明記
#                                                    されているかを見る
#   check-excluded-deliverables.sh --check-resolution
#                                                    実際に生成を行い、対象なし
#                                                    判定と整合の検査の合否を見る
#   check-excluded-deliverables.sh --self-test       自己テスト
#
# 終了コード: 0=合格。1=不合格。2=判定不能（走査対象が存在しない・一時領域を
#             作れない等）。
#
# 設計判断: .claude/rules/always/tasks/instruction-format/rule.md の
#   「設計判断」節「check-excluded-deliverables.sh」を参照。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACT_DOC="$REPO_ROOT/.claude/skills/orchestrating-ai-development-setup/references/contract.md"
BUILD_SCRIPT="$REPO_ROOT/generation-engine/scripts/build-deliverable-inventory.sh"
CONSISTENCY_SCRIPT="$REPO_ROOT/generation-engine/scripts/unit-list/check-excluded-kinds-consistency.sh"
OUTPUT_LAYOUT_SCRIPT="$REPO_ROOT/generation-engine/scripts/output-layout.sh"
CATALOG="$REPO_ROOT/delivery-payload/references/portal-catalog.json"

usage() {
  cat >&2 <<'USAGE'
Usage: check-excluded-deliverables.sh
       check-excluded-deliverables.sh --check-resolution
       check-excluded-deliverables.sh --self-test
USAGE
}

# _label_for_kind: portal-catalog.json から表示名を引く。
_label_for_kind() {
  jq -r --arg k "$1" '.categories[].blueprints[] | select(.kind==$k) | .label' "$CATALOG"
}

# run_check: excludedDeliverables の形式が定義文書に明記されているかを見る。
run_check() {
  local doc="$1"
  if [ ! -f "$doc" ]; then
    echo "[UNKNOWN] 定義文書が見つからないため判定できません: ${doc}（操作: run_check / 想定原因: パス指定の誤り、または未配置）" >&2
    return 2
  fi
  if ! grep -qF 'excludedDeliverables' "$doc"; then
    echo "[FAIL] 定義文書に excludedDeliverables の記載が無い: ${doc}" >&2
    return 1
  fi
  if ! grep -qF 'category' "$doc"; then
    echo "[FAIL] 定義文書に category（上流不在／対象不在の区別）の記載が無い: ${doc}" >&2
    return 1
  fi
  if ! grep -qF '上流不在' "$doc" || ! grep -qF '対象不在' "$doc"; then
    echo "[FAIL] 定義文書に category の2値（上流不在・対象不在）の両方が記載されていない: ${doc}" >&2
    return 1
  fi
  echo "[PASS] 定義文書（${doc}）に excludedDeliverables の形式と category の2値が明記されている"
  return 0
}

# _write_full_present_fixture: 6種別すべてとfeatureが実在するとみなせる
# 最小フィクスチャを output_root へ組み立てる。excludedKinds は空にする。
# check-excluded-kinds-consistency.sh の write_declaration/write_artifacts と
# 同じ配置規則（output-layout.sh 経由）を踏襲するが、当該スクリプトを
# source すると末尾のCLI分岐（$# の扱いが呼び出し元のシェルに依存し不安定）
# に巻き込まれるため、ここでは独立に実装する。
_write_full_present_fixture() {
  local output_root="$1"
  # shellcheck source=../../generation-engine/scripts/output-layout.sh
  . "$OUTPUT_LAYOUT_SCRIPT"
  local layout_json
  layout_json="$(resolve_output_layout "$output_root")" || return 1

  local kind label html_rel manifest_key manifest_rel manifest_ext_key manifest_ext_rel
  local present_kinds='["screen","api","table","batch","report","external"]'
  mkdir -p "$output_root/docs/scope-and-progress"
  jq -n --argjson present "$present_kinds" \
    '{generatedAt:"2026-08-24T00:00:00+09:00",surveyDocPath:"docs/design/common/アーキテクチャ調査書.md",allKinds:["screen","api","table","batch","report","external"],presentKinds:$present,excludedKinds:[]}' \
    > "$output_root/docs/scope-and-progress/excluded-kinds.json"

  for kind in screen api table batch report external feature; do
    label="$(output_layout_kind_label "$layout_json" "$kind")" || return 1
    html_rel="$(output_layout_get "$layout_json" unitListHtml "$label")" || return 1
    case "$kind" in
      screen) manifest_key="screenManifest"; manifest_ext_key="screenManifestExt" ;;
      api) manifest_key="apiManifest"; manifest_ext_key="apiManifestExt" ;;
      table) manifest_key="tableManifest"; manifest_ext_key="tableManifestExt" ;;
      batch) manifest_key="batchManifest"; manifest_ext_key="batchManifestExt" ;;
      report) manifest_key="reportManifest"; manifest_ext_key="reportManifestExt" ;;
      external) manifest_key="externalManifest"; manifest_ext_key="externalManifestExt" ;;
      feature) manifest_key="featureManifest"; manifest_ext_key="featureManifestExt" ;;
    esac
    manifest_rel="$(output_layout_get "$layout_json" "$manifest_key")" || return 1
    manifest_ext_rel="$(output_layout_get "$layout_json" "$manifest_ext_key")" || return 1
    mkdir -p "$output_root/$(dirname "$html_rel")" "$output_root/$(dirname "$manifest_rel")" "$output_root/$(dirname "$manifest_ext_rel")"
    printf '<html></html>\n' > "$output_root/$html_rel"
    printf '{"units":[{"unitKey":"fixture"}]}\n' > "$output_root/$manifest_rel"
    printf '{"units":[{"unitKey":"fixture","category":"test"}]}\n' > "$output_root/$manifest_ext_rel"
  done
}

# run_check_resolution: 2つの検収を実際の生成で確かめる。
#   (a) excludedDeliverables へ6種別以外(entity-state)を載せると
#       build-deliverable-inventory.sh が「対象なし」と判定し、かつ
#       check-excluded-kinds-consistency.sh は合格を保つ（検収方法2・3）
#   (b) 6種別のexcludedKindsへ6種別以外を混ぜるとcheck-excluded-kinds-
#       consistency.sh が従来どおり不合格を出す（検収方法4・回帰確認）
run_check_resolution() {
  if [ ! -f "$BUILD_SCRIPT" ] || [ ! -f "$CONSISTENCY_SCRIPT" ] || [ ! -f "$OUTPUT_LAYOUT_SCRIPT" ]; then
    echo "[UNKNOWN] 生成・検査スクリプトが見つからないため判定できません" >&2
    return 2
  fi
  local fail=0

  # --- (a) excludedDeliverables で entity-state を対象外にする ---
  local tmp_a
  if ! tmp_a="$(mktemp -d "${TMPDIR:-/tmp}/check-excluded-deliverables.XXXXXX" 2>/dev/null)" || [ -z "$tmp_a" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  if ! _write_full_present_fixture "$tmp_a" >"$tmp_a/fixture.log" 2>&1; then
    echo "[FAIL] フィクスチャ(a)の組み立てに失敗した" >&2
    cat "$tmp_a/fixture.log" >&2
    fail=1
  else
    jq '.excludedDeliverables = [{"kind":"entity-state","label":"状態遷移図","reason":"観測できる状態の遷移が無いため","category":"上流不在"}]' \
      "$tmp_a/docs/scope-and-progress/excluded-kinds.json" > "$tmp_a/docs/scope-and-progress/excluded-kinds.json.tmp" \
      && mv "$tmp_a/docs/scope-and-progress/excluded-kinds.json.tmp" "$tmp_a/docs/scope-and-progress/excluded-kinds.json"

    if ! bash "$BUILD_SCRIPT" "$tmp_a" >"$tmp_a/build.log" 2>&1; then
      echo "[FAIL] excludedDeliverables を持つフィクスチャで納品物一覧の生成が失敗した" >&2
      cat "$tmp_a/build.log" >&2
      fail=1
    else
      local label_a md_a
      label_a="$(_label_for_kind entity-state)"
      md_a="$tmp_a/docs/納品物一覧.md"
      if grep -F "| ${label_a} |" "$md_a" | grep -q '対象なし'; then
        echo "[PASS] 検収方法2: excludedDeliverables を持つ entity-state が「対象なし」と判定された"
      else
        echo "[FAIL] 検収方法2: entity-state が「対象なし」と判定されなかった" >&2
        fail=1
      fi
    fi

    if bash "$CONSISTENCY_SCRIPT" "$tmp_a" >"$tmp_a/consistency.log" 2>&1; then
      echo "[PASS] 検収方法3: excludedDeliverables があっても整合の検査は合格を保つ"
    else
      echo "[FAIL] 検収方法3: excludedDeliverables を追加しただけで整合の検査が不合格になった" >&2
      cat "$tmp_a/consistency.log" >&2
      fail=1
    fi
  fi
  rm -rf "$tmp_a"

  # --- (b) 6種別のexcludedKindsへ6種別以外を混ぜる（回帰: 従来どおり不合格） ---
  local tmp_b
  if ! tmp_b="$(mktemp -d "${TMPDIR:-/tmp}/check-excluded-deliverables.XXXXXX" 2>/dev/null)" || [ -z "$tmp_b" ]; then
    echo "[UNKNOWN] 一時ディレクトリを作れないため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  mkdir -p "$tmp_b/docs/scope-and-progress"
  jq -n '{generatedAt:"2026-08-24T00:00:00+09:00",surveyDocPath:"docs/design/common/アーキテクチャ調査書.md",allKinds:["screen","api","table","batch","report","external"],presentKinds:["screen","api","table","batch","report"],excludedKinds:[{kind:"external",label:"外部連携",reason:"対象外"},{kind:"entity-state",label:"状態遷移図",reason:"混入テスト"}]}' \
    > "$tmp_b/docs/scope-and-progress/excluded-kinds.json"
  local out_b rc_b=0
  out_b="$(bash "$CONSISTENCY_SCRIPT" "$tmp_b" 2>&1)" || rc_b=$?
  if [ "$rc_b" -eq 0 ]; then
    echo "[FAIL] 検収方法4: 6種別以外を excludedKinds へ混ぜても整合の検査が合格してしまう（回帰）" >&2
    fail=1
  elif printf '%s' "$out_b" | grep -qF '6種別が presentKinds と excludedKinds に重複なく完全分割されていない'; then
    echo "[PASS] 検収方法4: 6種別以外を excludedKinds へ混ぜると整合の検査が従来どおり不合格になる"
  else
    echo "[FAIL] 検収方法4: 不合格理由が完全分割の崩れではない" >&2
    printf '%s\n' "$out_b" | sed 's/^/    /' >&2
    fail=1
  fi
  rm -rf "$tmp_b"

  if [ "$fail" -ne 0 ]; then
    return 1
  fi
  echo "[PASS] excludedDeliverables による対象なし判定と、整合の検査(excludedKinds専用)の回帰なしを確認した"
  return 0
}

run_self_test() {
  local total=0 fail=0

  # ケース1: 実物の定義文書に鍵の形式が明記されている
  total=$((total + 1))
  if _cap="$(run_check "$CONTRACT_DOC" 2>&1)"; then
    echo "  [PASS] ケース1: 実物の定義文書に excludedDeliverables の形式が明記されている"
  else
    echo "  [FAIL] ケース1: 実物の定義文書に明記されていない" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
    fail=$((fail + 1))
  fi

  # ケース2: 定義文書が存在しない場合は判定不能(UNKNOWN・終了コード2)
  total=$((total + 1))
  local rc2=0
  run_check "${CONTRACT_DOC}.does-not-exist" >/dev/null 2>&1
  rc2=$?
  if [ "$rc2" -eq 2 ]; then
    echo "  [PASS] ケース2: 定義文書が無いと判定不能(終了コード2)になる"
  else
    echo "  [FAIL] ケース2: 定義文書が無いときの終了コードが2でない(rc=${rc2})" >&2
    fail=$((fail + 1))
  fi

  # ケース3: 鍵の記載が無い文書では不合格(終了コード1)になる
  total=$((total + 1))
  local tmp_doc rc3=0
  if ! tmp_doc="$(mktemp "${TMPDIR:-/tmp}/check-excluded-deliverables.XXXXXX" 2>/dev/null)" || [ -z "$tmp_doc" ]; then
    echo "  [UNKNOWN] 一時ファイルを作れないため自己テストの一部を判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    return 2
  fi
  printf '# 契約書\n\nexcludedKinds のみを説明する文書。\n' > "$tmp_doc"
  run_check "$tmp_doc" >/dev/null 2>&1
  rc3=$?
  if [ "$rc3" -eq 1 ]; then
    echo "  [PASS] ケース3: excludedDeliverables の記載が無い文書は不合格(rc=1)になる"
  else
    echo "  [FAIL] ケース3: 記載が無いときの終了コードが1でない(rc=${rc3})" >&2
    fail=$((fail + 1))
  fi

  # ケース4: 鍵はあるが category の2値説明が無い文書も不合格になる
  total=$((total + 1))
  printf '# 契約書\n\nexcludedDeliverables を持つが category の説明が無い文書。\n' > "$tmp_doc"
  local rc4=0
  run_check "$tmp_doc" >/dev/null 2>&1
  rc4=$?
  if [ "$rc4" -eq 1 ]; then
    echo "  [PASS] ケース4: category の2値説明が無い文書は不合格(rc=1)になる"
  else
    echo "  [FAIL] ケース4: category未記載時の終了コードが1でない(rc=${rc4})" >&2
    fail=$((fail + 1))
  fi
  rm -f "$tmp_doc"

  # ケース5: --check-resolution が想定どおりの結果を返す（検収方法2・3・4を実測）
  total=$((total + 1))
  local rc5=0
  run_check_resolution >/dev/null 2>&1
  rc5=$?
  if [ "$rc5" -eq 0 ]; then
    echo "  [PASS] ケース5: --check-resolution が対象なし判定・整合の検査の合否とも想定どおりになる"
  else
    echo "  [FAIL] ケース5: --check-resolution が想定と異なる結果になった(rc=${rc5})" >&2
    fail=$((fail + 1))
  fi

  echo "実行 ${total} 件 / 成功 $((total - fail)) 件 / 失敗 ${fail} 件"
  [ "$fail" -eq 0 ]
}

main() {
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    --check-resolution)
      run_check_resolution
      exit $?
      ;;
    "")
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  run_check "$CONTRACT_DOC"
  exit $?
}

main "$@"
