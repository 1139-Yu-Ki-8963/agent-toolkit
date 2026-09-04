#!/usr/bin/env bash
set -u

# start-run.sh — 実行フォルダを作り、run.json に8つの設定値と対象のコミットを書く
# （reverse単位・setup単位で共有する部品）
#
# 目的:
#   各単位の統括の手順0（前提の確認）が呼ぶ。setup側は
#   docs/skills/setup-orchestrating-units/scripts/start-run.sh の3行の入口経由で
#   本スクリプトを呼ぶ。対象リポジトリのHEADを実行開始時点に固定し、
#   実行の識別子（YYYY-MM-DD-<対象のHEAD短縮7桁>）を作り、
#   <output-root>/<project-name>/<識別子>/ に run.json と
#   confirmations/・logs/・code-readings/・reports/ を作る。
#
# 使い方:
#   start-run.sh <対象リポジトリのルート> --project-name <先方の名前> --output-root <出力の置き場の親> \
#     [--units <単位をカンマ区切り>] [--scope <出力の範囲>] [--deploy-to <対象プロジェクトのリポジトリのルート>] \
#     [--tests <出力する|出力しない>]
#   start-run.sh --self-test
#
# --units の既定: setup,reverse
# --scope の既定: 全部（他に「基本設計まで」「一覧まで」を受け付ける。値の妥当性は
#   本スクリプトでは検査しない。使い道はplan-setup.shの--untilへの対応づけであり、
#   その対応はdocs/skills/setup-orchestrating-units/SKILL.mdの手順1が持つ）
#
# --deploy-to: 設計書を先方リポジトリへ展開する使い方のときだけ指定する
#   （先方リポジトリのルート）。指定が無ければ設計書は作業場所だけに置く
#   使い方となり、run.jsonの「設計書の置き場」は<実行フォルダ>/designになる
#   （このとき配下に docs/design/・ai-work/records/ を作る）。
#
# --tests の既定: 出力しない（単体テスト設計書・種別内結合テスト設計書・
#   種別横断結合テスト設計書のいずれも作らない）。「出力する」を指定すると
#   基本設計を書く機能が単体テスト設計書を対で書く。値は「出力する」
#   「出力しない」のいずれかで、それ以外は使い方の誤り（終了コード1）。
#
# run.json のキー:
#   対象リポジトリ・対象プロジェクトの名前・出力の置き場・実行の識別子・実行する単位・
#   出力の範囲・テスト設計書の出力（この7つが設定値）・対象のコミット（対象リポジトリの
#   HEADのフルハッシュ。設定値ではなく実行開始時に確定する値）・設計書の置き場（--deploy-toの値、
#   または<実行フォルダ>/design。設計書の書き込み先を各機能が読む値）
#
# 出力:
#   標準出力に実行フォルダの絶対パスを1行で出す。
#
# 終了コード:
#   0 = 実行フォルダを作った
#   1 = 引数不正、対象リポジトリが存在しない、対象がgitリポジトリでない、
#       または同じ実行フォルダが既に存在する
#   2 = --self-test で一時領域の作成に失敗
#
# 保守責任者: 人手（ユーザー）。run.jsonのキーを変える場合は
#   本スクリプトと docs/skills/setup-orchestrating-units/SKILL.md と
#   README.md の「入力の一覧」を同時に更新する。
#
# macOS bash 3.2 互換（連想配列・mapfileは不使用）。

usage() {
  echo "usage: $(basename "$0") <対象リポジトリのルート> --project-name <対象プロジェクトの名前> --output-root <出力の置き場の親> [--units <単位をカンマ区切り>] [--scope <出力の範囲>] [--deploy-to <対象プロジェクトのリポジトリのルート>] [--tests <出力する|出力しない>] | --self-test" >&2
}

# 簡易なJSON文字列エスケープ（バックスラッシュとダブルクォートのみ）
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_start() {
  local target="$1" project_name="$2" output_root="$3" units="$4" scope="$5" deploy_to="$6" tests="$7"
  if [ ! -d "$target" ]; then
    echo "ERROR: 対象リポジトリのルートが存在しない: $target" >&2
    return 1
  fi
  if [ "$tests" != "出力する" ] && [ "$tests" != "出力しない" ]; then
    echo "ERROR: --tests は 出力する か 出力しない のいずれかを指定する: $tests" >&2
    return 1
  fi
  local commit
  commit="$(git -C "$target" rev-parse HEAD 2>/dev/null)"
  if [ -z "$commit" ]; then
    echo "ERROR: 対象リポジトリがgitリポジトリでない、またはHEADを解決できない: $target" >&2
    return 1
  fi
  local short="${commit:0:7}"
  local today
  today="$(date +%Y-%m-%d)"
  local identifier="${today}-${short}"
  local run_dir="${output_root%/}/${project_name}/${identifier}"
  if [ -e "$run_dir" ]; then
    echo "ERROR: 実行フォルダが既に存在する: $run_dir" >&2
    return 1
  fi
  local design_root
  if [ -n "$deploy_to" ]; then
    design_root="$deploy_to"
  else
    design_root="${run_dir}/design"
    mkdir -p "${design_root}/docs/design" "${design_root}/ai-work/records"
  fi

  mkdir -p "${run_dir}/confirmations" "${run_dir}/logs" "${run_dir}/code-readings" "${run_dir}/reports"
  cat > "${run_dir}/run.json" <<JSON
{
  "対象リポジトリ": "$(json_escape "$target")",
  "先方の名前": "$(json_escape "$project_name")",
  "出力の置き場": "$(json_escape "$output_root")",
  "実行の識別子": "$(json_escape "$identifier")",
  "実行する単位": "$(json_escape "$units")",
  "出力の範囲": "$(json_escape "$scope")",
  "テスト設計書の出力": "$(json_escape "$tests")",
  "対象のコミット": "$(json_escape "$commit")",
  "設計書の置き場": "$(json_escape "$design_root")"
}
JSON
  echo "$run_dir"
  return 0
}

self_test() {
  local pass=0 fail=0
  local root
  if ! root="$(mktemp -d "${TMPDIR:-/tmp}/start-run-self-test.XXXXXX" 2>/dev/null)" || [ -z "$root" ]; then
    echo "[UNKNOWN] 一時ディレクトリの作成に失敗したため判定できません（mktempが一時領域へ書き込めませんでした。実行環境の制約が原因である可能性があります）" >&2
    exit 2
  fi

  local target="${root}/target"
  mkdir -p "$target"
  local test_author_name="self-test"
  local test_author_email="63326271+1139-Yu-Ki-8963@users.noreply.github.com"
  ( cd "$target" && git init -q \
    && git -c "user.name=${test_author_name}" -c "user.email=${test_author_email}" commit -q --allow-empty -m init ) >/dev/null 2>&1
  local commit
  commit="$(git -C "$target" rev-parse HEAD 2>/dev/null)"
  local short="${commit:0:7}"
  local today
  today="$(date +%Y-%m-%d)"

  local out_root="${root}/out"
  mkdir -p "$out_root"

  # ケース1: 実行フォルダを作りrun.jsonに7つの値（既定の実行する単位・出力の範囲を含む）を書く
  local out1 rc1=0
  out1="$("$0" "$target" --project-name acme --output-root "$out_root" 2>&1)" || rc1=$?
  local expected_dir="${out_root}/acme/${today}-${short}"
  if [ "$rc1" -eq 0 ] && [ "$out1" = "$expected_dir" ] \
    && [ -f "${expected_dir}/run.json" ] \
    && [ -d "${expected_dir}/confirmations" ] && [ -d "${expected_dir}/logs" ] \
    && [ -d "${expected_dir}/code-readings" ] && [ -d "${expected_dir}/reports" ] \
    && grep -q "対象リポジトリ" "${expected_dir}/run.json" \
    && grep -q "先方の名前" "${expected_dir}/run.json" \
    && grep -q "出力の置き場" "${expected_dir}/run.json" \
    && grep -q "実行の識別子" "${expected_dir}/run.json" \
    && grep -q "対象のコミット" "${expected_dir}/run.json" \
    && grep -q "$commit" "${expected_dir}/run.json" \
    && grep -q '"実行する単位": "setup,reverse"' "${expected_dir}/run.json" \
    && grep -q '"出力の範囲": "全部"' "${expected_dir}/run.json" \
    && grep -q '"テスト設計書の出力": "出力しない"' "${expected_dir}/run.json"; then
    pass=$((pass+1)); echo "  [PASS] ケース1: 実行フォルダを作りrun.jsonに既定の実行する単位・出力の範囲・テスト設計書の出力を書く"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース1: 実行フォルダの作成が不正 (exit ${rc1})" >&2
    printf '%s\n' "$out1" | sed 's/^/    /' >&2
  fi

  # ケース2: 既に同じ実行フォルダがある場合は終了コード1
  local out2 rc2=0
  out2="$("$0" "$target" --project-name acme --output-root "$out_root" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 1 ]; then
    pass=$((pass+1)); echo "  [PASS] ケース2: 実行フォルダが既にあれば終了コード1"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース2: 既存の実行フォルダを検知しない (exit ${rc2})" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
  fi

  # ケース3: 対象がgitリポジトリでない場合は終了コード1
  local not_git="${root}/not-git"
  mkdir -p "$not_git"
  local out3 rc3=0
  out3="$("$0" "$not_git" --project-name acme --output-root "$out_root" 2>&1)" || rc3=$?
  if [ "$rc3" -eq 1 ]; then
    pass=$((pass+1)); echo "  [PASS] ケース3: 対象がgitリポジトリでなければ終了コード1"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース3: 非gitリポジトリを検知しない (exit ${rc3})" >&2
    printf '%s\n' "$out3" | sed 's/^/    /' >&2
  fi

  # ケース4: --units と --scope を明示指定するとrun.jsonへそのまま書く
  local target2="${root}/target2"
  mkdir -p "$target2"
  ( cd "$target2" && git init -q \
    && git -c "user.name=${test_author_name}" -c "user.email=${test_author_email}" commit -q --allow-empty -m init ) >/dev/null 2>&1
  local out4 rc4=0
  out4="$("$0" "$target2" --project-name acme2 --output-root "$out_root" --units reverse --scope "一覧まで" 2>&1)" || rc4=$?
  if [ "$rc4" -eq 0 ] \
    && grep -q '"実行する単位": "reverse"' "${out4}/run.json" \
    && grep -q '"出力の範囲": "一覧まで"' "${out4}/run.json"; then
    pass=$((pass+1)); echo "  [PASS] ケース4: --units・--scope を明示指定するとrun.jsonへそのまま書く"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース4: --units・--scope の明示指定が反映されない (exit ${rc4})" >&2
    printf '%s\n' "$out4" | sed 's/^/    /' >&2
  fi

  # ケース5: --deploy-to を指定すると設計書の置き場が先方リポジトリのルートになる
  local target3="${root}/target3"
  mkdir -p "$target3"
  ( cd "$target3" && git init -q \
    && git -c "user.name=${test_author_name}" -c "user.email=${test_author_email}" commit -q --allow-empty -m init ) >/dev/null 2>&1
  local out5 rc5=0
  out5="$("$0" "$target3" --project-name acme3 --output-root "$out_root" --deploy-to "$target3" 2>&1)" || rc5=$?
  if [ "$rc5" -eq 0 ] \
    && grep -qF "\"設計書の置き場\": \"${target3}\"" "${out5}/run.json"; then
    pass=$((pass+1)); echo "  [PASS] ケース5: --deploy-toを指定すると設計書の置き場が先方リポジトリのルートになる"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース5: --deploy-toが設計書の置き場に反映されない (exit ${rc5})" >&2
    printf '%s\n' "$out5" | sed 's/^/    /' >&2
  fi

  # ケース6: --deploy-toが無ければ設計書の置き場は実行フォルダ配下のdesignになる
  if grep -qF "\"設計書の置き場\": \"${expected_dir}/design\"" "${expected_dir}/run.json" \
    && [ -d "${expected_dir}/design/docs/design" ] \
    && [ -d "${expected_dir}/design/ai-work/records" ]; then
    pass=$((pass+1)); echo "  [PASS] ケース6: --deploy-toが無ければ設計書の置き場は実行フォルダ配下のdesignになる"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース6: 既定の設計書の置き場が実行フォルダ配下のdesignにならない" >&2
  fi

  # ケース7: --tests 出力する を指定するとrun.jsonへそのまま書く
  local target4="${root}/target4"
  mkdir -p "$target4"
  ( cd "$target4" && git init -q \
    && git -c "user.name=${test_author_name}" -c "user.email=${test_author_email}" commit -q --allow-empty -m init ) >/dev/null 2>&1
  local out7 rc7=0
  out7="$("$0" "$target4" --project-name acme4 --output-root "$out_root" --tests 出力する 2>&1)" || rc7=$?
  if [ "$rc7" -eq 0 ] \
    && grep -q '"テスト設計書の出力": "出力する"' "${out7}/run.json"; then
    pass=$((pass+1)); echo "  [PASS] ケース7: --tests 出力する を指定するとrun.jsonへそのまま書く"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース7: --tests 出力する の指定が反映されない (exit ${rc7})" >&2
    printf '%s\n' "$out7" | sed 's/^/    /' >&2
  fi

  # ケース8: --tests に不正な値を指定すると終了コード1
  local out8 rc8=0
  out8="$("$0" "$target4" --project-name acme5 --output-root "$out_root" --tests 不正 2>&1)" || rc8=$?
  if [ "$rc8" -eq 1 ]; then
    pass=$((pass+1)); echo "  [PASS] ケース8: --tests に不正な値を指定すると終了コード1"
  else
    fail=$((fail+1)); echo "  [FAIL] ケース8: --tests の不正な値を検知しない (exit ${rc8})" >&2
    printf '%s\n' "$out8" | sed 's/^/    /' >&2
  fi
  rm -rf "$root"

  if [ "$fail" -eq 0 ]; then
    echo "self-test 全項目 PASS（PASS=${pass} FAIL=${fail}）"
    return 0
  fi
  echo "self-test FAIL（PASS=${pass} FAIL=${fail}）" >&2
  return 1
}

main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  local target="" project_name="" output_root="" units="setup,reverse" scope="全部" deploy_to="" tests="出力しない"
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-name) project_name="${2:-}"; shift 2 ;;
      --output-root) output_root="${2:-}"; shift 2 ;;
      --units) units="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --deploy-to) deploy_to="${2:-}"; shift 2 ;;
      --tests) tests="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ "${#args[@]}" -ne 1 ] || [ -z "$project_name" ] || [ -z "$output_root" ]; then
    usage
    exit 1
  fi
  target="${args[0]}"

  run_start "$target" "$project_name" "$output_root" "$units" "$scope" "$deploy_to" "$tests"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
