#!/usr/bin/env bash
# lib/rule-resolver.sh — プロジェクト上書き（委譲可）規約の受け口解決ヘルパー
#
# 「委譲可」を宣言した規約の hook が、プロジェクト側の rule ファイルを
# グローバル既定より優先して読むための共通関数。source して使う。
#
# resolve_rule_file <cwd> <新相対パス> [<旧相対パス>...]
#   ${cwd}/.claude/rules/<相対パス> を引数順に探し、最初に実在したパスを echo する。
#   どれも実在しなければ第 1 引数（新形式パス）をそのまま echo する
#   （呼び出し側は実在チェックで「許可リストなし」等を判定できる）。
#
# 旧相対パス引数は移行互換のため。プロジェクト側が旧 <name>-rules/ 形式のまま
# でも解決できる。全プロジェクトが新形式へ移行したら旧引数を削除してよい。

resolve_rule_file() {
  _rr_cwd="$1"
  shift
  _rr_primary="${_rr_cwd}/.claude/rules/$1"
  for _rr_rel in "$@"; do
    _rr_path="${_rr_cwd}/.claude/rules/${_rr_rel}"
    if [ -f "$_rr_path" ]; then
      printf '%s' "$_rr_path"
      return 0
    fi
  done
  printf '%s' "$_rr_primary"
}
