#!/usr/bin/env bash
# 完了状態の検収コマンドが、配布先にも存在するパスだけを参照するか検査する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER="${LEDGER_COMMANDS_PORTABLE_LEDGER:-$REPO_ROOT/docs/tasks/指摘改善一覧.md}"
WORK_DIR=""

unknown() {
  echo "[UNKNOWN] $1" >&2
  return 2
}

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf -- "$WORK_DIR"
  fi
}

extract_commands() {
  local output="$1"

  awk -v output="$output" '
    BEGIN { printf "%s", "" > output; close(output) }
    function emit_commands(text, rest, command) {
      rest = text
      while (match(rest, /`[^`]+`/)) {
        command = substr(rest, RSTART + 1, RLENGTH - 2)
        if (command ~ /^(bash|sh|grep|find|node|npm|npx|git|test|awk|diff|cmp|wc|make|jq|perl|mkdir|cp|ruby|python3?|rg|env|cd|command|LC_[A-Z_]+=|[A-Za-z_][A-Za-z0-9_]*=|if |for )/) {
          print key "\t" command > output
        }
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    /^###[[:space:]]+/ {
      heading = $0
      sub(/^###[[:space:]]+/, "", heading)
      split(heading, parts, /[.．]/)
      key = parts[1]
      sub(/[[:space:]]+$/, "", key)
      next
    }
    /^\*\*状態\*\*:[[:space:]]*完了/ {
      if (key != "") emit_commands($0)
    }
  ' "$LEDGER"
}

extract_paths() {
  local commands="$1" output="$2"

  awk -F '\t' -v output="$output" '
    BEGIN { printf "%s", "" > output; close(output) }
    function clean(token) {
      sub(/^[A-Za-z_][A-Za-z0-9_]*=/, "", token)
      gsub(/^["\047([{]+/, "", token)
      gsub(/["\047,;:)}]+$/, "", token)
      sub(/^[!]+/, "", token)
      return token
    }
    function root_file(token) {
      return token ~ /^(README.md|AGENTS.md|CLAUDE.md|RUNBOOK.md|package.json|package-lock.json|\.gitignore)$/
    }
    function rooted_path(token, top) {
      top = token
      sub(/\/.*/, "", top)
      return top ~ /^(\.claude|\.cursor|\.codex|\.git|delivery-payload|generation-engine|docs)$/
    }
    {
      key = $1
      command = substr($0, index($0, "\t") + 1)
      count = split(command, fields, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        path = clean(fields[i])
        if (path == "" || path ~ /^-/ || path ~ /^\$/ || path ~ /^</) continue
        if (path ~ /^\// || path ~ /^~\// || path ~ /^\.\.\// || path ~ /^\.\// || (path ~ /^[A-Za-z0-9_.-]+\// && rooted_path(path)) || root_file(path)) {
          print key "\t" path > output
        }
      }
    }
  ' "$commands"
}

is_excluded() {
  case "$1" in
    docs/tasks/work-records/*)
      # 作業の途中経過であり、配布先で使う対象を持たない。
      return 0
      ;;
    docs/session-prompts/*)
      # このリポジトリの作業を進める手順書であり、配布先で使う対象を持たない。
      return 0
      ;;
    docs/scripts/check-self-contained.sh)
      # このリポジトリの出荷物が自立しているかを測る道具であり、配布先に検査対象がない。
      return 0
      ;;
    .claude/skills/prioritizing-improvement-tasks-from-images/*)
      # このリポジトリ固有の改善課題と台帳を扱い、配布先には対応する台帳がない。
      return 0
      ;;
  esac
  return 1
}

is_published() {
  case "$1" in
    .claude/skills|.claude/skills/*|delivery-payload|delivery-payload/*|generation-engine|generation-engine/*|docs|docs/*|README.md|AGENTS.md|CLAUDE.md|RUNBOOK.md)
      return 0
      ;;
  esac
  return 1
}

check_paths() {
  local paths="$1"
  local key path failed=0 checked=0

  while IFS=$'\t' read -r key path; do
    [ -n "$path" ] || continue
    checked=$((checked + 1))
    if is_excluded "$path" || is_published "$path"; then
      continue
    fi
    echo "[FAIL] $key: 配布対象外のパスを参照しています: $path" >&2
    failed=$((failed + 1))
  done < "$paths"

  if [ "$failed" -ne 0 ]; then
    echo "[SUMMARY] 検査パス${checked}件、不合格${failed}件" >&2
    return 1
  fi
  echo "[PASS] 検査パス${checked}件、不合格0件"
}

self_test() {
  local fixture="$WORK_DIR/ledger.md"
  local commands="$WORK_DIR/commands.tsv"
  local paths="$WORK_DIR/paths.tsv"
  local status

  awk -v output="$fixture" 'BEGIN {
    print "### public. 公開対象" > output
    print "**状態**: 完了。コマンド: `bash generation-engine/scripts/build-portal.sh --self-test`" > output
    print "### excluded. 公開除外" > output
    print "**状態**: 完了。コマンド: `grep -r x docs/tasks/work-records/a.md docs/session-prompts/a.md docs/scripts/check-self-contained.sh .claude/skills/prioritizing-improvement-tasks-from-images/SKILL.md`" > output
    print "### private. 配布対象外" > output
    print "**状態**: 完了。コマンド: `node package.json`" > output
    print "### open. 未完了" > output
    print "**状態**: 対応中。コマンド: `node package-lock.json`" > output
  }'

  LEDGER="$fixture"
  extract_commands "$commands"
  extract_paths "$commands" "$paths"
  check_paths "$paths" >/dev/null 2>&1
  status=$?
  if [ "$status" -eq 1 ]; then
    echo "[PASS] 配布対象外だけを不合格にし、公開除外と未完了行を不合格にしない"
  else
    echo "[FAIL] 公開範囲の判定が期待と一致しない: $status" >&2
    return 1
  fi

  if [ "$(grep -c $'private\tpackage.json' "$paths")" -eq 1 ] && [ "$(grep -c $'open\tpackage-lock.json' "$paths")" -eq 0 ]; then
    echo "[PASS] 見出しキーとパスを対応付け、完了行だけを抽出する"
  else
    echo "[FAIL] パス抽出または見出しキーの対応が不正" >&2
    return 1
  fi

  TMPDIR=/dev/null bash "$0" --self-test >/dev/null 2>&1
  status=$?
  if [ "$status" -eq 2 ]; then
    echo "[PASS] 一時ディレクトリを作れない場合は終了コード2を返す"
  else
    echo "[FAIL] 一時ディレクトリ作成失敗の終了コードが2ではない: $status" >&2
    return 1
  fi

  echo "[PASS] self-test"
}

case "${1:-}" in
  "") ;;
  --self-test) ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac

if [ ! -f "$LEDGER" ]; then
  unknown "台帳が見つかりません: $LEDGER"
  exit 2
fi

if ! WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ledger-commands-portable.XXXXXX" 2>/dev/null)" || [ -z "$WORK_DIR" ]; then
  unknown "mktempが${TMPDIR:-/tmp}へ一時ディレクトリを作れませんでした。実行環境の制約等が原因の可能性があります"
  exit 2
fi
trap cleanup EXIT HUP INT TERM

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

COMMANDS_FILE="$WORK_DIR/commands.tsv"
PATHS_FILE="$WORK_DIR/paths.tsv"
if ! extract_commands "$COMMANDS_FILE"; then
  unknown "台帳からコマンドを抽出できませんでした: $LEDGER"
  exit 2
fi
if ! extract_paths "$COMMANDS_FILE" "$PATHS_FILE"; then
  unknown "コマンドからパスを抽出できませんでした: $LEDGER"
  exit 2
fi
check_paths "$PATHS_FILE"
