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
#     --kind <種別> --unit <識別子> --verdict <合格|不合格> \
#     --viewpoints "<観点=合|否|要確認;...>" --judged "<文書名>=<sha256>;..." \
#     [--reason "<理由>"] [--design-root <設計書のルート>]
#   record-acceptance.sh <対象リポジトリのルート> --run <実行フォルダ> \
#     --common <文書名> --verdict <合格|不合格> \
#     --viewpoints "<観点=合|否|要確認;...>" --judged "<文書名>=<sha256>" \
#     [--reason "<理由>"] [--design-root <設計書のルート>]
#   record-acceptance.sh --self-test
#
# 単位・共通設計文書の保留は廃止（2026-09-05）。判定は合格・不合格の2値。
#
# --judged は判定した時点の文書の同一性の値（sha256）。判定の直前に
# `shasum -a 256 <文書>` で取る。共通設計文書は1件、単位は基本設計書・
# 単体テスト設計書の2件を渡す。記録を書く直前に現在の値と突き合わせ、
# 1件でも一致しなければ記録を作らない（第1回改善指示書1-23）。
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
# 単位のフォルダ名はreverse-shared/scripts/list-units-of.shの出力（5列目）
# から得る（unit-dir-name.shは呼ばない）。一覧の元データが無い、または該当
# する識別子の行が無いときだけ、unit-dir-name.shへ識別子を渡した値を使う
# （一覧不在時の現行維持のためのfallbackであり唯一の定義の再実装ではない）。
# 種別ごとの文書名（基本設計書・単体テスト設計書。featureも他の6種別と
# 同じく2件）はreverse-shared/scripts/design-doc-name.shで作る
# （check-basic-design.shと共有し、実名の二重定義を持たない）。単位の
# 記録はreverse-shared/scripts/units-status.shの完了判定も更新する（無ければ
# この更新だけ省く）。
#
# 観点の値に要確認が含まれるとき、--reasonへ確認事項一覧のキーを含める。
# キーが<実行フォルダ>/confirmations/確認事項の記録.mdに実在しなければ
# 記録を作らない（第1回改善指示書1-18）。--runは常に必須（使い方の誤り）
# なので、確認事項の記録.mdが読めない場合は要確認-判定不能として記録を
# 作らない（2026-09-06改善。読む側のcheck-acceptance-record.shと同じ区別）。
#
# 観点のキーが空文字列の項目（例: "外部仕様の確定=合;=合"）も観点-キー空
# として拒む（読む側が空のキーを観点の値-不正として拒むのと対にする）。
#
# 終了コード:
#   0 = 記録を書いた
#   1 = 判定した時点と記録を書く時点で文書の同一性の値が食い違う（記録を作らない）
#   2 = 使い方の誤り・種別が不正・判定の値が不正・観点のキーが空・
#       要確認のキーが確認事項の記録に無い・確認事項の記録.mdを参照できない
#       （判定不能）
#
# 保守責任者: 人手（ユーザー）。記録の形（キー）を変えるときは、本スクリプトと
#   check-acceptance-record.shを同時に直す。
#
# 廃棄条件: 合格の記録を別の仕組みに置き換えた時。
#
# macOS bash 3.2 互換。jqを使用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR_NAME_SH="${SCRIPT_DIR}/unit-dir-name.sh"
LIST_UNITS_OF_SH="${SCRIPT_DIR}/list-units-of.sh"
DESIGN_DOC_NAME_SH="${SCRIPT_DIR}/design-doc-name.sh"
UNITS_STATUS_SH="${SCRIPT_DIR}/units-status.sh"
# shellcheck source=viewpoint-validation.sh
. "${SCRIPT_DIR}/viewpoint-validation.sh"

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
  echo "使い方: record-acceptance.sh <対象> --run <実行フォルダ> --kind <種別> --unit <識別子> --verdict <合格|不合格> --viewpoints \"<観点=合|否|要確認;...>\" --judged \"<文書名>=<sha256>;...\" [--reason \"...\"] [--design-root <設計書のルート>]" >&2
  echo "        record-acceptance.sh <対象> --run <実行フォルダ> --common <文書名> --verdict <合格|不合格> --viewpoints \"...\" --judged \"<文書名>=<sha256>\" [--reason \"...\"] [--design-root <設計書のルート>]" >&2
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


# 観点の値が 合・否・要確認 のいずれかであることを確かめる。$1: viewpoints。
# 値が空・`=`が無い項目・3値以外の値はすべて同じ扱いで拒否する（流れの設計
# 「完了判定の状態」の「観点の値は 合・否・要確認 の3つ」）。キーが空文字列
# の項目（例: "=合"）も拒む（読む側のcheck-acceptance-record.shが空のキー
# を観点の値-不正として拒むのと対にする。改善指示書対応）。
check_viewpoint_values_valid() {
  local viewpoints="$1"
  [ -n "$viewpoints" ] || return 0
  local old_ifs="$IFS" k v item
  IFS=';'
  local arr=($viewpoints)
  IFS="$old_ifs"
  for item in "${arr[@]}"; do
    [ -n "$item" ] || continue
    case "$item" in
      *=*)
        k="${item%%=*}"
        v="${item#*=}"
        ;;
      *)
        k="$item"
        v=""
        ;;
    esac
    if [ -z "$k" ]; then
      echo "[FAIL] 観点-キー空: 値=${v}" >&2
      return 1
    fi
    if ! is_valid_viewpoint_value "$v"; then
      echo "[FAIL] 観点-値不正: ${k}=${v}" >&2
      return 1
    fi
  done
  return 0
}

# 判定（--verdict）と観点（--viewpoints）の整合を確かめる。$1: verdict
# $2: viewpoints。否が1つでもあるのに合格、否が無く要確認と合だけなのに
# 不合格は、record-acceptance.shが観点との整合を検査して確定する
# （設計判断: 流れの設計「完了判定の状態」の「誰が決めるか」を参照）。
check_verdict_viewpoint_consistency() {
  local verdict="$1" viewpoints="$2"
  local has_no=1
  case "$viewpoints" in
    *=否*) has_no=0 ;;
  esac
  if [ "$has_no" -eq 0 ] && [ "$verdict" = "合格" ]; then
    return 1
  fi
  if [ "$has_no" -eq 1 ] && [ "$verdict" = "不合格" ]; then
    return 2
  fi
  return 0
}

# 判定した時点の同一性の値（judged_json）と、記録を書く時点の現在値
# （docs_json）を突き合わせる。docs_jsonの各文書名について一致しなければ
# 標準エラーへ差分を出し、1件でも食い違えば1を返す（第1回改善指示書1-23）。
check_judged_match() {
  local judged_json="$1" docs_json="$2"
  local name cur judged_val mismatch=0
  for name in $(printf '%s' "$docs_json" | jq -r 'keys[]'); do
    cur="$(printf '%s' "$docs_json" | jq -r --arg n "$name" '.[$n]')"
    judged_val="$(printf '%s' "$judged_json" | jq -r --arg n "$name" '.[$n] // "__不在__"')"
    if [ "$judged_val" = "__不在__" ] || [ "$judged_val" != "$cur" ]; then
      echo "[FAIL] 同一性-判定後変更: ${name} が判定した後に変わっています" >&2
      mismatch=1
    fi
  done
  return "$mismatch"
}


parse_kv_pairs_json() {
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
  local target="$1" run_dir="$2" kind="$3" unit="$4" verdict="$5" viewpoints="$6" reason="$7" design_root="$8" judged_json="$9"
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
  dirname="$(unit_folder_name "$design_root" "$kind" "$unit")"
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

  if ! check_judged_match "$judged_json" "$docs_json"; then
    return 1
  fi

  local commit vp_json exec_id out_dir out_file
  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_kv_pairs_json "$viewpoints")"
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
  local target="$1" run_dir="$2" doc_name="$3" verdict="$4" viewpoints="$5" reason="$6" design_root="$7" judged_json="$8"
  local doc_path="${design_root}/docs/design/common/${doc_name}.md"
  local docs_json commit vp_json exec_id out_dir out_file
  docs_json="$(doc_sha_json "$doc_path" "${doc_name}.md")"

  if ! check_judged_match "$judged_json" "$docs_json"; then
    return 1
  fi

  commit="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
  vp_json="$(parse_kv_pairs_json "$viewpoints")"
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

  local run_dir="" kind="" unit="" common="" verdict="" viewpoints="" reason="" design_root="$target" judged=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run_dir="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --unit) unit="$2"; shift 2 ;;
      --common) common="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --viewpoints) viewpoints="$2"; shift 2 ;;
      --judged) judged="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --design-root) design_root="$2"; shift 2 ;;
      *) usage_error ;;
    esac
  done

  [ -n "$run_dir" ] || usage_error
  [ -n "$judged" ] || usage_error

  case "$verdict" in
    合格|不合格) ;;
    *)
      echo "[FAIL] 使い方-判定: ${verdict:-（空）} は 合格・不合格 のいずれでもありません" >&2
      exit 2
      ;;
  esac

  if ! check_viewpoint_values_valid "$viewpoints"; then
    exit 2
  fi

  check_verdict_viewpoint_consistency "$verdict" "$viewpoints"
  case "$?" in
    1)
      echo "[FAIL] 判定-観点不整合: 否があるため合格にできません" >&2
      exit 2
      ;;
    2)
      echo "[FAIL] 判定-観点不整合: 否が無いため不合格にできません" >&2
      exit 2
      ;;
  esac

  local yk_rc
  check_yakukakunin_key "$viewpoints" "$reason" "$run_dir"
  yk_rc=$?
  case "$yk_rc" in
    0) ;;
    2)
      echo "[FAIL] 要確認-判定不能: 確認事項の記録を参照できません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
      exit 2
      ;;
    *)
      echo "[FAIL] 要確認-キー不在: 理由に確認事項一覧のキーがありません（${run_dir%/}/confirmations/確認事項の記録.md）" >&2
      exit 2
      ;;
  esac

  local judged_json
  judged_json="$(parse_kv_pairs_json "$judged")"

  local rc
  if [ -n "$common" ]; then
    record_common "$target" "$run_dir" "$common" "$verdict" "$viewpoints" "$reason" "$design_root" "$judged_json"
    rc=$?
  elif [ -n "$kind" ] && [ -n "$unit" ]; then
    record_unit "$target" "$run_dir" "$kind" "$unit" "$verdict" "$viewpoints" "$reason" "$design_root" "$judged_json"
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

  sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

  # --- 使い方エラー系 ---
  bash "$SCRIPT_DIR/record-acceptance.sh" > "$base/u1.out" 2>"$base/u1.err"
  check "使い方-引数無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local d="$base/target" run="$base/run"
  mkdir -p "$d" "$run"
  # gitのコミットは不要。対象のコミットが空でも記録は書ける（コミット=空文字）ことを確かめる

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 不明 --viewpoints "" --judged "x=y" > "$base/u2.out" 2>"$base/u2.err"
  check "使い方-判定不正は終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 保留 --viewpoints "" --judged "x=y" > "$base/u2b.out" 2>"$base/u2b.err"
  check "使い方-判定「保留」は廃止のため終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  local yk_bad_record="$d/ai-work/records/basic-design-acceptance/screen-src_pages_OrderList.tsx.json"
  rm -f "$yk_bad_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 合格 --viewpoints "外部仕様の確定=不明" --judged "x=y" > "$base/u2c.out" 2>"$base/u2c.err"
  local rc2c=$?
  check "観点の値が不明なら終了コード2" "$([ "$rc2c" -eq 2 ] && echo 0 || echo 1)"
  check "観点の値が不明なら理由に観点-値不正" "$(grep -qF '観点-値不正' "$base/u2c.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$yk_bad_record" ]; then
    echo "PASS: 観点の値が不明なら記録を作らない"
  else
    echo "FAIL: 観点の値が不明なら記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" --verdict 合格 --viewpoints "" > "$base/u3.out" 2>"$base/u3.err"
  check "使い方-judged無しは終了コード2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

  # --- 単位の記録 ---
  mkdir -p "$d/docs/design/screens/src_pages_OrderList.tsx"
  echo "# 画面基本設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  echo "# 画面単体テスト設計書" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md"
  local judged1
  judged1="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合;単体テスト設計書の実在=合" --judged "$judged1" --reason "" \
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
    --verdict 不合格 --viewpoints "非機能の方式の確定=否" --judged "基盤設計書.md=$(sha_of "$d/docs/design/common/基盤設計書.md")" --reason "性能方式が未確定" \
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
  local judged3
  judged3="画面基本設計書.md=$(sha_of "$design2/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$design2/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$dc" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged3" --reason "" --design-root "$design2" \
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
  local judged4
  judged4="API基本設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API基本設計書.md");API単体テスト設計書.md=$(sha_of "$d2/docs/design/apis/api_get_orders/API単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged4" --reason "" > "$base/r4.out" 2>"$base/r4.err"
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
  local judged5
  judged5="論理データモデル.md=$(sha_of "$d2/docs/design/tables/orders/論理データモデル.md");テーブル単体テスト設計書.md=$(sha_of "$d2/docs/design/tables/orders/テーブル単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind table --unit "orders" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged5" --reason "" > "$base/r5.out" 2>"$base/r5.err"
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
  local judged6
  judged6="機能設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能設計書.md");機能単体テスト設計書.md=$(sha_of "$d2/docs/design/features/注文機能/機能単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind feature --unit "注文機能" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged6" --reason "" > "$base/r6.out" 2>"$base/r6.err"
  check "feature種別: 終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local feature_record="$d2/ai-work/records/basic-design-acceptance/feature-注文機能.json"
  local feature_basic feature_test
  feature_basic="$(jq -r '.["文書"]["機能設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  feature_test="$(jq -r '.["文書"]["機能単体テスト設計書.md"] // empty' "$feature_record" 2>/dev/null)"
  check "feature種別: 文書名が機能設計書.mdでsha256が空でない" "$([ -n "$feature_basic" ] && echo 0 || echo 1)"
  check "feature種別: 文書名が機能単体テスト設計書.mdでsha256が空でない" "$([ -n "$feature_test" ] && echo 0 || echo 1)"

  # --- 解釈できない種別は記録を作らず終了コード2 ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind 不正種別 --unit "何か" \
    --verdict 合格 --viewpoints "" --judged "x=y" --reason "" > "$base/r7.out" 2>"$base/r7.err"
  local rc7=$?
  check "解釈できない種別は終了コード2" "$([ "$rc7" -eq 2 ] && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$d2/ai-work/records/basic-design-acceptance/不正種別-何か.json" ]; then
    echo "PASS: 解釈できない種別は記録を作らない"
  else
    echo "FAIL: 解釈できない種別は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 要確認を含む合格の記録（確認事項一覧にキーが実在） ---
  mkdir -p "${run2}/confirmations"
  cat > "${run2}/confirmations/確認事項の記録.md" <<'CONFEOF'
| キー | 単位 | 種類 | 事項 | 既定 | 反映先 | 回答 | 状態 |
|---|---|---|---|---|---|---|---|
| 性能-数値目標 | api/get_orders | 確認事項 | 性能の数値目標が無い | 既定なし | 方式設計書 | 未回答 | 未回答 |
CONFEOF
  local yk_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r8.out" 2>"$base/r8.err"
  check "要確認を含む合格の記録は終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"
  local yk_vp
  yk_vp="$(jq -r '.["観点"]["非機能の方式の確定"]' "$yk_record" 2>/dev/null)"
  check "要確認を含む合格の記録: 観点の値が要確認" "$([ "$yk_vp" = "要確認" ] && echo 0 || echo 1)"

  # --- 要確認でキー不在なら終了コード2で記録を作らない ---
  rm -f "$yk_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "根拠のないキー" \
    > "$base/r9.out" 2>"$base/r9.err"
  local rc9=$?
  check "要確認でキー不在は終了コード2" "$([ "$rc9" -eq 2 ] && echo 0 || echo 1)"
  check "要確認でキー不在の理由に要確認-キー不在" "$(grep -qF '要確認-キー不在' "$base/r9.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$yk_record" ]; then
    echo "PASS: 要確認でキー不在は記録を作らない"
  else
    echo "FAIL: 要確認でキー不在は記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 方式設計書の7節が要求水準を持たない状態で要確認の単位の判定が定まり照合が0を返す ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 \
    --viewpoints "外部仕様の確定=合;業務ルールと例外系の確定=合;非機能の方式の確定=要確認;データの整合性・トランザクション境界・排他の確定=合;不明点の不在=合;単体テスト設計書の実在=合" \
    --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r10.out" 2>"$base/r10.err"
  local rc10r=$?
  local rc10c=1
  if [ "$rc10r" -eq 0 ]; then
    bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
      > "$base/r10chk.out" 2>"$base/r10chk.err"
    rc10c=$?
  fi
  check "方式設計書の7節が要求水準を持たない状態で要確認の単位の判定が定まり照合が0を返す" "$([ "$rc10r" -eq 0 ] && [ "$rc10c" -eq 0 ] && echo 0 || echo 1)"

  # --- 外部仕様の確定が要確認でも判定が定まり照合が0を返す（第1回改善指示書1-22・再検証） ---
  local ext_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 \
    --viewpoints "外部仕様の確定=要確認;業務ルールと例外系の確定=合;非機能の方式の確定=合;データの整合性・トランザクション境界・排他の確定=合;不明点の不在=合;単体テスト設計書の実在=合" \
    --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r10x.out" 2>"$base/r10x.err"
  local rc10xr=$?
  local rc10xc1=1
  local vp_ext1=""
  if [ "$rc10xr" -eq 0 ]; then
    bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
      > "$base/r10xchk1.out" 2>"$base/r10xchk1.err"
    rc10xc1=$?
    vp_ext1="$(jq -r '.["観点"]["外部仕様の確定"]' "$ext_record" 2>/dev/null)"
  fi
  check "外部仕様の確定が要確認でも判定が定まり照合が0を返す" "$([ "$rc10xr" -eq 0 ] && [ "$rc10xc1" -eq 0 ] && [ "$vp_ext1" = "要確認" ] && echo 0 || echo 1)"

  # --- 同じ記録を2回照合しても外部仕様の確定の値が変わらない（第1回改善指示書1-22・再検証） ---
  bash "$SCRIPT_DIR/check-acceptance-record.sh" "$d2" --kind api --unit "api/get_orders" --run "$run2" \
    > "$base/r10xchk2.out" 2>"$base/r10xchk2.err"
  local rc10xc2=$?
  local vp_ext2
  vp_ext2="$(jq -r '.["観点"]["外部仕様の確定"]' "$ext_record" 2>/dev/null)"
  check "外部仕様の確定が要確認の記録を2回照合しても観点の値が一致する" "$([ "$rc10xc2" -eq 0 ] && [ "$vp_ext1" = "$vp_ext2" ] && echo 0 || echo 1)"

  # --- 判定と観点の整合（コードレビュー警告1: 否ありなのに合格・要確認のみなのに不合格） ---
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=否" --judged "$judged4" --reason "" \
    > "$base/r12.out" 2>"$base/r12.err"
  local rc12=$?
  check "否ありなのに合格は終了コード2" "$([ "$rc12" -eq 2 ] && echo 0 || echo 1)"
  check "否ありなのに合格の理由に判定-観点不整合" "$(grep -qF '判定-観点不整合' "$base/r12.err" && echo 0 || echo 1)"

  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run2" --kind api --unit "api/get_orders" \
    --verdict 不合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r13.out" 2>"$base/r13.err"
  local rc13=$?
  check "要確認のみなのに不合格は終了コード2" "$([ "$rc13" -eq 2 ] && echo 0 || echo 1)"
  check "要確認のみなのに不合格の理由に判定-観点不整合" "$(grep -qF '判定-観点不整合' "$base/r13.err" && echo 0 || echo 1)"

  # --- 判定した時点と記録を書く時点の同一性の食い違い（第1回改善指示書1-23） ---
  local judged_old="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  echo "# 画面基本設計書（改訂）" > "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged_old" --reason "" \
    > "$base/r10.out" 2>"$base/r10.err"
  local rc10=$?
  check "判定後に文書が変わったら終了コード1" "$([ "$rc10" -eq 1 ] && echo 0 || echo 1)"
  check "判定後に文書が変わったら理由に同一性-判定後変更" "$(grep -qF '同一性-判定後変更' "$base/r10.err" && echo 0 || echo 1)"
  local before_mtime after_mtime
  before_mtime="$(jq -r '.["文書"]["画面基本設計書.md"]' "$record_file" 2>/dev/null)"
  check "判定後に文書が変わっても既存の記録は上書きされない" "$([ "$before_mtime" = "$sha_expected1" ] && echo 0 || echo 1)"

  # --- 判定した時点と記録を書く時点が同じなら終了コード0 ---
  local judged_now
  judged_now="画面基本設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面基本設計書.md");画面単体テスト設計書.md=$(sha_of "$d/docs/design/screens/src_pages_OrderList.tsx/画面単体テスト設計書.md")"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/OrderList.tsx" \
    --verdict 合格 --viewpoints "外部仕様の確定=合" --judged "$judged_now" --reason "" \
    > "$base/r11.out" 2>"$base/r11.err"
  check "判定した時点と記録を書く時点が同じなら終了コード0" "$([ $? -eq 0 ] && echo 0 || echo 1)"

  # --- 観点のキーが空文字列なら終了コード2（書く側。観点-キー空） ---
  local emptykey_record="$d/ai-work/records/basic-design-acceptance/screen-src_pages_EmptyKeyWrite.tsx.json"
  rm -f "$emptykey_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d" --run "$run" --kind screen --unit "src/pages/EmptyKeyWrite.tsx" \
    --verdict 合格 --viewpoints "=合" --judged "x=y" \
    > "$base/r14.out" 2>"$base/r14.err"
  local rc14=$?
  check "観点のキーが空文字列なら終了コード2" "$([ "$rc14" -eq 2 ] && echo 0 || echo 1)"
  check "観点のキーが空文字列なら理由に観点-キー空" "$(grep -qF '観点-キー空' "$base/r14.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$emptykey_record" ]; then
    echo "PASS: 観点のキーが空文字列なら記録を作らない"
  else
    echo "FAIL: 観点のキーが空文字列なら記録を作らない（記録ファイルが実在します）"
    fail=$((fail + 1))
  fi

  # --- 要確認ありで確認事項の記録.mdが読めないなら終了コード2（要確認-判定不能） ---
  local run3="$base/run3-no-confirmations"
  mkdir -p "$run3"
  local noyk_record="$d2/ai-work/records/basic-design-acceptance/api-api_get_orders.json"
  rm -f "$noyk_record"
  bash "$SCRIPT_DIR/record-acceptance.sh" "$d2" --run "$run3" --kind api --unit "api/get_orders" \
    --verdict 合格 --viewpoints "非機能の方式の確定=要確認" --judged "$judged4" --reason "性能-数値目標は要確認事項一覧に登録済み" \
    > "$base/r15.out" 2>"$base/r15.err"
  local rc15b=$?
  check "要確認ありで確認事項の記録.mdが読めないなら終了コード2" "$([ "$rc15b" -eq 2 ] && echo 0 || echo 1)"
  check "要確認ありで確認事項の記録.mdが読めない理由に要確認-判定不能" "$(grep -qF '要確認-判定不能' "$base/r15.err" && echo 0 || echo 1)"
  total=$((total + 1))
  if [ ! -f "$noyk_record" ]; then
    echo "PASS: 要確認ありで確認事項の記録.mdが読めないなら記録を作らない"
  else
    echo "FAIL: 要確認ありで確認事項の記録.mdが読めないなら記録を作らない（記録ファイルが実在します）"
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
