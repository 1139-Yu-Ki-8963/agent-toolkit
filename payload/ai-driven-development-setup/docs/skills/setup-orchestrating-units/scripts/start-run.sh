#!/usr/bin/env bash
set -u

# start-run.sh — 実行フォルダを作り、run.json に6つの設定値と対象のコミットを書く
#
# 目的:
#   統括の手順0（前提の確認）が呼ぶ。対象リポジトリのHEADを実行開始時点に固定し、
#   実行の識別子（YYYY-MM-DD-<対象のHEAD短縮7桁>）を作り、
#   <output-root>/<project-name>/<識別子>/ に run.json と
#   confirmations/・logs/・facts/・reports/ を作る。
#
# 使い方:
#   start-run.sh <対象リポジトリのルート> --project-name <先方の名前> --output-root <出力の置き場の親> \
#     [--units <単位をカンマ区切り>] [--scope <出力の範囲>]
#   start-run.sh --self-test
#
# --units の既定: setup,reverse
# --scope の既定: 全部（他に「基本設計まで」「一覧まで」を受け付ける。値の妥当性は
#   本スクリプトでは検査しない。使い道はplan-setup.shの--untilへの対応づけであり、
#   その対応はdocs/skills/setup-orchestrating-units/SKILL.mdの手順1が持つ）
#
# run.json のキー:
#   対象リポジトリ・先方の名前・出力の置き場・実行の識別子・実行する単位・出力の範囲
#   （この6つが設定値）・対象のコミット（対象リポジトリのHEADのフルハッシュ。
#   設定値ではなく実行開始時に確定する値）
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
  echo "usage: $(basename "$0") <対象リポジトリのルート> --project-name <先方の名前> --output-root <出力の置き場の親> [--units <単位をカンマ区切り>] [--scope <出力の範囲>] | --self-test" >&2
}

# 簡易なJSON文字列エスケープ（バックスラッシュとダブルクォートのみ）
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_start() {
  local target="$1" project_name="$2" output_root="$3" units="$4" scope="$5"
  if [ ! -d "$target" ]; then
    echo "ERROR: 対象リポジトリのルートが存在しない: $target" >&2
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
  mkdir -p "${run_dir}/confirmations" "${run_dir}/logs" "${run_dir}/facts" "${run_dir}/reports"
  cat > "${run_dir}/run.json" <<JSON
{
  "対象リポジトリ": "$(json_escape "$target")",
  "先方の名前": "$(json_escape "$project_name")",
  "出力の置き場": "$(json_escape "$output_root")",
  "実行の識別子": "$(json_escape "$identifier")",
  "実行する単位": "$(json_escape "$units")",
  "出力の範囲": "$(json_escape "$scope")",
  "対象のコミット": "$(json_escape "$commit")"
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
    && [ -d "${expected_dir}/facts" ] && [ -d "${expected_dir}/reports" ] \
    && grep -q "対象リポジトリ" "${expected_dir}/run.json" \
    && grep -q "先方の名前" "${expected_dir}/run.json" \
    && grep -q "出力の置き場" "${expected_dir}/run.json" \
    && grep -q "実行の識別子" "${expected_dir}/run.json" \
    && grep -q "対象のコミット" "${expected_dir}/run.json" \
    && grep -q "$commit" "${expected_dir}/run.json" \
    && grep -q '"実行する単位": "setup,reverse"' "${expected_dir}/run.json" \
    && grep -q '"出力の範囲": "全部"' "${expected_dir}/run.json"; then
    pass=$((pass+1)); echo "  [PASS] ケース1: 実行フォルダを作りrun.jsonに既定の実行する単位・出力の範囲を書く"
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

  local target="" project_name="" output_root="" units="setup,reverse" scope="全部"
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --project-name) project_name="${2:-}"; shift 2 ;;
      --output-root) output_root="${2:-}"; shift 2 ;;
      --units) units="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [ "${#args[@]}" -ne 1 ] || [ -z "$project_name" ] || [ -z "$output_root" ]; then
    usage
    exit 1
  fi
  target="${args[0]}"

  run_start "$target" "$project_name" "$output_root" "$units" "$scope"
  exit $?
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
