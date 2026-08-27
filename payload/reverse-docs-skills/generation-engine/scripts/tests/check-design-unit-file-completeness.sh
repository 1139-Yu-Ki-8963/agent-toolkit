#!/usr/bin/env bash
# 配置の定義（design-unit-layout.json）が挙げるファイルを、種別を横断してすべて
# 実際に生成できるかを確かめる完備性検査。
#
# 背景（docs/tasks/設計書の生成のばらつきをなくす指示書.md 2.4）:
#   機能（feature）は基本設計に機能設計書.md、テスト設計に機能テスト設計書.mdを
#   挙げる定義を持つが、実測では機能9件すべてで前者しか生成されず、
#   同じ状態が起きても機械で気付く仕組みが無かった。種別ごとの個別実装
#   （scaffold-design-unit.sh の各スキル呼び出し）を見るだけでは、定義と実際の
#   生成物の対応を横断的に突き合わせられない。
#
# 判定:
#   delivery-payload/references/design-unit-layout.json が宣言する全種別
#   （screen/api/table/batch/report/external/feature）・全phase（basic/detail/test。ファイル束が
#   空配列のphaseは対象外）について、scaffold-design-unit.sh で実際に展開し、
#   宣言されたファイルがすべて実在するかを jq の宣言と直接突き合わせて確認する
#   （scaffold-design-unit.sh 自身の --verify にも重ねて頼るが、判定の正は本スクリプトが
#   宣言 JSON から独立に読み直す点にある）。
#   screen も同じ宣言に含むが、3サブフォルダの束を scaffold-screen.sh が独自に
#   展開するため、非画面ループから除外し、同スクリプトの展開 + --verify へ委譲する。
#
# 使い方:
#   check-design-unit-file-completeness.sh [--repo <リポジトリのパス>]
#   check-design-unit-file-completeness.sh --self-test
#
# 終了コード:
#   0 = 全種別・全phase・screen で宣言ファイルがすべて実在
#   1 = 1件以上欠落、または宣言ファイル自体が見つからない
#
# 保守責任者: 人手（ユーザー）。design-unit-layout.json の kinds/phases 構造、または
#   scaffold-screen.sh の必須ファイル一覧を変える場合は本スクリプトと self-test を
#   同時に更新する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DEFAULT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 宣言 JSON（layout_json のパス）と output_dir・kind・phase を受け取り、
# 宣言されたファイルがすべて output_dir 配下に実在するかを確認する。
# 欠落があれば FAIL 行を標準出力へ列挙し、戻り値 1。全件実在なら戻り値 0。
verify_unit_files() {
  local layout_json="$1" output_dir="$2" kind="$3" phase="$4" unit_dir="$5"
  local files
  files="$(jq -r --arg k "$kind" --arg p "$phase" '.kinds[$k].phases[$p][]' "$layout_json" 2>/dev/null)" || {
    echo "FAIL ${kind}/${phase}: 宣言の読み取りに失敗"
    return 1
  }
  local rc=0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$output_dir/$unit_dir/$f" ]; then
      echo "FAIL ${kind}/${phase}: 宣言ファイルが実在しない: $f"
      rc=1
    fi
  done <<EOF
$files
EOF
  return "$rc"
}

check_all() {
  local repo="$1"
  local layout_json="$repo/delivery-payload/references/design-unit-layout.json"
  local scaffold="$repo/generation-engine/scripts/scaffold-design-unit.sh"
  local scaffold_screen="$repo/generation-engine/scripts/scaffold-screen.sh"
  local template_root="$repo/delivery-payload/templates/リバース検証"
  local unit_test_design_dir
  unit_test_design_dir="$(jq -r '.layout.unitTestDesignDir' "$repo/delivery-payload/references/output-layout.json")"
  # 1-210の残件対応。basic-design/detail-designの名前も
  # scaffold-design-unit.sh側と同じくunitPhaseDirNamesを正として読む
  # （トップレベルキーのため.layout配下ではなく直接参照する。
  # build-portal.sh等の既存踏襲と同じ読み方）。
  local unit_basic_design_dir unit_detail_design_dir
  unit_basic_design_dir="$(jq -r '.unitPhaseDirNames.basic' "$repo/delivery-payload/references/output-layout.json")"
  unit_detail_design_dir="$(jq -r '.unitPhaseDirNames.detail' "$repo/delivery-payload/references/output-layout.json")"

  if [ ! -f "$layout_json" ]; then
    echo "ERROR: 宣言ファイルが見つかりません: $layout_json" >&2
    return 1
  fi
  if [ ! -f "$scaffold" ]; then
    echo "ERROR: scaffold-design-unit.sh が見つかりません: $scaffold" >&2
    return 1
  fi

  local tmp
  if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-completeness.XXXXXX" 2>/dev/null)" || [ -z "$tmp" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  tmp="$(cd "$tmp" && pwd -P)"

  local rc=0
  local kinds kind
  kinds="$(jq -r '.kinds | keys[] | select(. != "screen")' "$layout_json")"
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    local phases phase
    phases="$(jq -r --arg k "$kind" '.kinds[$k].phases | keys[]' "$layout_json")"
    while IFS= read -r phase; do
      [ -n "$phase" ] || continue
      local file_count
      file_count="$(jq -r --arg k "$kind" --arg p "$phase" '.kinds[$k].phases[$p] | length' "$layout_json")"
      if [ "$file_count" -eq 0 ]; then
        continue
      fi
      local unit_id="completeness-${kind}-${phase}"
      local phase_label
      case "$phase" in
        basic) phase_label="$unit_basic_design_dir" ;;
        detail) phase_label="$unit_detail_design_dir" ;;
        test) phase_label="$unit_test_design_dir" ;;
        *) phase_label="$phase" ;;
      esac
      if ! bash "$scaffold" "$kind" "$phase" "$tmp" "$unit_id" "完備性検査${kind}" "$template_root" >/dev/null 2>&1; then
        echo "FAIL ${kind}/${phase}: 展開に失敗"
        rc=1
        continue
      fi
      local unit_root_key
      unit_root_key="$(jq -r --arg k "$kind" '.kinds[$k]' "$layout_json" >/dev/null 2>&1; echo ok)" >/dev/null 2>&1 || true
      # scaffold-design-unit.sh の展開先は <output-layout>/<kind>-<unit_id>/<phase_label>
      local unit_dir
      unit_dir="$(find "$tmp" -type d -name "${kind}-${unit_id}" 2>/dev/null | head -1)"
      if [ -z "$unit_dir" ]; then
        echo "FAIL ${kind}/${phase}: 展開先ディレクトリが見つからない"
        rc=1
        continue
      fi
      if ! verify_unit_files "$layout_json" "$tmp" "$kind" "$phase" "${unit_dir#"$tmp"/}/${phase_label}"; then
        rc=1
        continue
      fi
      echo "PASS ${kind}/${phase}"
    done <<EOF
$phases
EOF
  done <<EOF
$kinds
EOF

  # screen は共通宣言に含むが、専用の3サブフォルダ構造を持つため
  # scaffold-screen.sh 自身の --verify へ委譲して「全種別」を横断する。
  if [ -f "$scaffold_screen" ]; then
    if bash "$scaffold_screen" "$tmp" completeness-screen "完備性検査画面" >/dev/null 2>&1 \
       && bash "$scaffold_screen" --verify "$tmp" completeness-screen >/dev/null 2>&1; then
      echo "PASS screen"
    else
      echo "FAIL screen: 展開またはverifyに失敗"
      rc=1
    fi
  else
    echo "FAIL screen: scaffold-screen.sh が見つからない"
    rc=1
  fi

  rm -rf "$tmp"
  return "$rc"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------
self_test() {
  local pass=0 fail=0

  # ケース1: verify_unit_files 単体 — 宣言ファイルが全件実在すれば合格
  local tmp1
  if ! tmp1="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-completeness-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp1" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  tmp1="$(cd "$tmp1" && pwd -P)"
  cat > "$tmp1/layout.json" <<'JSON'
{"kinds":{"widget":{"phases":{"basic":["A.md","B.md"]}}}}
JSON
  mkdir -p "$tmp1/out/widget-w1/基本設計"
  : > "$tmp1/out/widget-w1/基本設計/A.md"
  : > "$tmp1/out/widget-w1/基本設計/B.md"
  if verify_unit_files "$tmp1/layout.json" "$tmp1/out" widget basic "widget-w1/基本設計" >/dev/null 2>&1; then
    echo "PASS: 宣言ファイル全件実在で合格"
    pass=$((pass + 1))
  else
    echo "FAIL: 宣言ファイル全件実在なのに不合格"
    fail=$((fail + 1))
  fi

  # ケース2: 既存単位の生成後に様式へB.mdを追加 → 不合格・追加ファイル名を報告
  printf '%s\n' '{"kinds":{"widget":{"phases":{"basic":["A.md"]}}}}' > "$tmp1/layout.json"
  rm -f "$tmp1/out/widget-w1/基本設計/B.md"
  printf '%s\n' '{"kinds":{"widget":{"phases":{"basic":["A.md","B.md"]}}}}' > "$tmp1/layout.json"
  local out2
  out2="$(verify_unit_files "$tmp1/layout.json" "$tmp1/out" widget basic "widget-w1/基本設計")"
  local rc2=$?
  if [ "$rc2" -ne 0 ] && printf '%s' "$out2" | grep -q 'B.md'; then
    echo "PASS: 様式へ後から追加したファイルの不足を検出して名前を報告"
    pass=$((pass + 1))
  else
    echo "FAIL: 様式追加後の不足検出（出力: ${out2}）"
    fail=$((fail + 1))
  fi
  rm -rf "$tmp1"

  # ケース3: 1ファイルが欠落（機能テスト設計書0件の再現）→ 不合格・欠落ファイル名を報告
  local tmp2
  if ! tmp2="$(mktemp -d "${TMPDIR:-/tmp}/design-unit-completeness-missing-selftest.XXXXXX" 2>/dev/null)" || [ -z "$tmp2" ]; then
    echo "[UNKNOWN] ä¸æãã£ã¬ã¯ããªã®ä½æã«å¤±æããããå¤å®ã§ãã¾ããï¼mktempãä¸æé åã¸æ¸ãè¾¼ãã¾ããã§ãããå®è¡ç°å¢ã®å¶ç´ãåå ã§ããå¯è½æ§ãããã¾ãï¼" >&2
    exit 2
  fi
  tmp2="$(cd "$tmp2" && pwd -P)"
  printf '%s\n' '{"kinds":{"widget":{"phases":{"basic":["A.md","B.md"]}}}}' > "$tmp2/layout.json"
  mkdir -p "$tmp2/out/widget-w1/基本設計"
  : > "$tmp2/out/widget-w1/基本設計/A.md"
  local out3
  out3="$(verify_unit_files "$tmp2/layout.json" "$tmp2/out" widget basic "widget-w1/基本設計")"
  local rc3=$?
  if [ "$rc3" -ne 0 ] && printf '%s' "$out3" | grep -q 'B.md'; then
    echo "PASS: 片方欠落を検出し欠落ファイル名を報告"
    pass=$((pass + 1))
  else
    echo "FAIL: 片方欠落の検出（出力: ${out3}）"
    fail=$((fail + 1))
  fi
  rm -rf "$tmp2"

  # ケース4: 実リポジトリに対する check_all が全件PASSで終了コード0
  # (実際にscaffold-design-unit.sh/scaffold-screen.shを動かす統合テスト)
  local out4 rc4
  out4="$(check_all "$REPO_DEFAULT" 2>&1)"; rc4=$?
  if [ "$rc4" -eq 0 ] && ! printf '%s\n' "$out4" | grep -q '^FAIL'; then
    echo "PASS: 実リポジトリの全種別・screenで宣言ファイルが完備"
    pass=$((pass + 1))
  else
    echo "FAIL: 実リポジトリの完備性検査（出力: ${out4}）"
    fail=$((fail + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  [ "$fail" -eq 0 ]
}

main() {
  local repo="$REPO_DEFAULT"
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi
  if [ "${1:-}" = "--repo" ]; then
    repo="${2:?--repo にはリポジトリのパスが必要です}"
  fi
  local out rc
  out="$(check_all "$repo")"; rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "CLEAN: 全種別・screenで配置定義のファイルが完備"
  fi
  exit "$rc"
}

main "$@"
