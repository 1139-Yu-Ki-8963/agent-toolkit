#!/usr/bin/env bash
# 完了状態の行に記録された検収コマンドを列挙し、明示指定時だけ実行する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER="${LEDGER_COMMANDS_LEDGER:-$REPO_ROOT/docs/tasks/指摘改善一覧.md}"
TIMEOUT_SECONDS="${LEDGER_COMMAND_TIMEOUT:-120}"
MODE="list"
ONLY_KEY=""
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

usage() {
  echo "usage: $0 [--list | --run] [--only <key>] [--timeout <seconds>]" >&2
}

extract_commands() {
  local output="$1"

  awk -F '\t' '
    function emit_commands(text, rest, command) {
      rest = text
      while (match(rest, /`[^`]+`/)) {
        command = substr(rest, RSTART + 1, RLENGTH - 2)
        if (command ~ /^(bash|sh|grep|find|node|npm|npx|git|test|awk|diff|cmp|wc|make|jq|perl|mkdir|cp|ruby|python3?|rg|env|cd|command)[[:space:]]/ || command ~ /^(if|for)[[:space:]]/ || command ~ /^[A-Za-z_][A-Za-z0-9_]*=.*[[:space:]]/ || command ~ /^([.]\/|\/)/) {
          print key "\t" command
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
      marker = index($0, "コマンド")
      if (marker > 0 && key != "") emit_commands(substr($0, marker))
    }
  ' "$LEDGER" > "$output"
}

run_with_timeout() {
  local command="$1"

  perl -e '
    use strict;
    use warnings;
    my $limit = shift @ARGV;
    my $pid = fork();
    exit 125 if !defined $pid;
    if ($pid == 0) {
      setpgrp(0, 0);
      exec @ARGV;
      exit 125;
    }
    local $SIG{ALRM} = sub {
      kill "TERM", -$pid;
      select undef, undef, undef, 0.2;
      kill "KILL", -$pid;
      waitpid($pid, 0);
      exit 124;
    };
    alarm $limit;
    waitpid($pid, 0);
    alarm 0;
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$TIMEOUT_SECONDS" bash -c "$command"
}

list_commands() {
  local file="$1"
  local found=0
  local key command

  while IFS=$'\t' read -r key command; do
    if [ -n "$ONLY_KEY" ] && [ "$key" != "$ONLY_KEY" ]; then
      continue
    fi
    printf '%s\t%s\n' "$key" "$command"
    found=1
  done < "$file"

  if [ "$found" -eq 0 ] && [ -n "$ONLY_KEY" ]; then
    echo "[FAIL] 指定したキーに実行対象のコマンドがありません: $ONLY_KEY" >&2
    return 1
  fi
}

run_commands() {
  local file="$1"
  local found=0
  local failed=0
  local indeterminate=0
  local key command status

  while IFS=$'\t' read -r key command; do
    if [ -n "$ONLY_KEY" ] && [ "$key" != "$ONLY_KEY" ]; then
      continue
    fi
    found=1
    echo "[RUN] $key: $command"
    (cd "$REPO_ROOT" && run_with_timeout "$command")
    status=$?
    if [ "$status" -eq 0 ]; then
      echo "[PASS] $key: 終了コード0"
    elif [ "$status" -eq 124 ]; then
      echo "[UNKNOWN] $key: ${TIMEOUT_SECONDS}秒を超えたため判定できません: $command" >&2
      indeterminate=1
    else
      echo "[FAIL] $key: 終了コード$status: $command" >&2
      failed=1
    fi
  done < "$file"

  if [ "$found" -eq 0 ] && [ -n "$ONLY_KEY" ]; then
    echo "[FAIL] 指定したキーに実行対象のコマンドがありません: $ONLY_KEY" >&2
    return 1
  fi
  if [ "$indeterminate" -ne 0 ]; then
    return 2
  fi
  if [ "$failed" -ne 0 ]; then
    return 1
  fi
}

self_test() {
  local fixture="$WORK_DIR/ledger.md"
  local output status

  printf '%s\n' \
    '### case-pass. 成功' \
    '**状態**: 完了。確かめたコマンド: `test -f docs/tasks/指摘改善一覧.md`' \
    '### case-fail. 失敗' \
    '**状態**: 完了。確かめたコマンドは `test -f does-not-exist` である。' \
    '### case-timeout. 時間超過' \
    "**状態**: 完了。確かめたコマンド: \`perl -e 'sleep 2'\`" \
    '### case-open. 未完了' \
    '**状態**: 対応中。確かめたコマンド: `test -f does-not-exist`' > "$fixture"

  output="$(LEDGER_COMMANDS_LEDGER="$fixture" bash "$0" --list)"
  if [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]; then
    echo "[PASS] 完了行のコマンドだけを一覧化する"
  else
    echo "[FAIL] 完了行の抽出件数が一致しない" >&2
    return 1
  fi

  if LEDGER_COMMANDS_LEDGER="$fixture" bash "$0" --run --only case-pass >/dev/null; then
    echo "[PASS] --run --only で指定した成功コマンドを実行する"
  else
    echo "[FAIL] 成功コマンドの実行に失敗した" >&2
    return 1
  fi

  LEDGER_COMMANDS_LEDGER="$fixture" bash "$0" --run --only case-fail >/dev/null 2>&1
  status=$?
  if [ "$status" -eq 1 ]; then
    echo "[PASS] 不合格を終了コード1で返す"
  else
    echo "[FAIL] 不合格の終了コードが1ではない: $status" >&2
    return 1
  fi

  LEDGER_COMMANDS_LEDGER="$fixture" LEDGER_COMMAND_TIMEOUT=1 bash "$0" --run --only case-timeout >/dev/null 2>&1
  status=$?
  if [ "$status" -eq 2 ]; then
    echo "[PASS] 時間超過を判定不能の終了コード2で返す"
  else
    echo "[FAIL] 時間超過の終了コードが2ではない: $status" >&2
    return 1
  fi

  echo "[PASS] self-test"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) MODE="list" ;;
    --run) MODE="run" ;;
    --only)
      shift
      if [ "$#" -eq 0 ]; then usage; exit 2; fi
      ONLY_KEY="$1"
      ;;
    --timeout)
      shift
      if [ "$#" -eq 0 ]; then usage; exit 2; fi
      TIMEOUT_SECONDS="$1"
      ;;
    --self-test) MODE="self-test" ;;
    *) usage; exit 2 ;;
  esac
  shift
done

case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*|0) unknown "時間上限は1以上の整数で指定してください: $TIMEOUT_SECONDS"; exit 2 ;;
esac

if [ ! -f "$LEDGER" ]; then
  unknown "台帳が見つかりません: $LEDGER"
  exit 2
fi

if ! WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ledger-commands.XXXXXX" 2>/dev/null)" || [ -z "$WORK_DIR" ]; then
  unknown "mktempが${TMPDIR:-/tmp}へ一時ディレクトリを作れませんでした。実行環境の制約等が原因の可能性があります"
  exit 2
fi
trap cleanup EXIT HUP INT TERM

if [ "$MODE" = "self-test" ]; then
  self_test
  exit $?
fi

COMMANDS_FILE="$WORK_DIR/commands.tsv"
if ! extract_commands "$COMMANDS_FILE"; then
  unknown "台帳からコマンドを抽出できませんでした: $LEDGER"
  exit 2
fi

if [ "$MODE" = "run" ]; then
  run_commands "$COMMANDS_FILE"
else
  list_commands "$COMMANDS_FILE"
fi
