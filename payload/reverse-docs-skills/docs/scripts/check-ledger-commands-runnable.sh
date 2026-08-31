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

  # 状態行に「配布対象外」と断ってあるコマンドは第3列へ1を立てて出す。
  # 断り自体は無条件の除外根拠にしない。run_commands 側で参照先パスの
  # 実在を確かめ、実在すれば正本として実行する（下記 repo_only_paths_exist
  # のコメントを参照）。
  awk -F '\t' '
    function emit_commands(text, repo_only,    rest, command) {
      rest = text
      while (match(rest, /`[^`]+`/)) {
        command = substr(rest, RSTART + 1, RLENGTH - 2)
        if (command ~ /^(bash|sh|grep|find|node|npm|npx|git|test|awk|diff|cmp|wc|make|jq|perl|mkdir|cp|ruby|python3?|rg|env|cd|command)[[:space:]]/ || command ~ /^(if|for)[[:space:]]/ || command ~ /^[A-Za-z_][A-Za-z0-9_]*=.*[[:space:]]/ || command ~ /^([.]\/|\/)/) {
          print key "\t" command "\t" repo_only
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
      repo_only = ($0 ~ /配布対象外/) ? 1 : 0
      if (marker > 0 && key != "") emit_commands(substr($0, marker), repo_only)
    }
  ' "$LEDGER" > "$output"
}

# 断り書き（配布対象外）だけで無条件に飛ばすと、正本でも確かめられなくなる。
# 正本には配布対象外の資産（例: このリポジトリの自立検査そのもの）が実在
# するため、正本でだけは確かめられるべきである。
# そのため参照先の実在で分岐する。正本では実行され、配布先でだけ飛ぶ。
# 2026-08-28 の実測で、配布先の154件のうち2件
#（`同期定義-登録漏れ防止`・`自立検査-走査範囲不足`）がこの形に当たった。
# `check-ledger-commands-portable.sh` の repo_only 判定は `.claude/rules/`
# 配下の参照に限定しており、この2件目
#（`generation-engine/scripts/verification/check-self-contained.sh` 参照）
# には当たらないため、あちらの口をそのまま使うことはできない。
repo_only_paths_exist() {
  local command="$1"
  local path all_exist=1

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ ! -e "$REPO_ROOT/$path" ]; then
      all_exist=0
    fi
  done < <(printf '%s' "$command" | grep -oE '[A-Za-z0-9_./-]+\.(sh|md|json|mjs|cjs|py|html|css|yml)')

  [ "$all_exist" -eq 1 ]
}

# 配布先には Node.js と Python の依存が置かれない。置くと版管理へ混入する。
# 置かずに参照だけを渡すことで、配布先でも測れるようにする。
# 実測（2026-08-28）で、配布先の 1-203・1-224 がブラウザの依存の不在で
# 判定不能になっていた。参照を渡すと測れる。
# 参照先が無い場合は何も渡さず、従来どおり判定不能のまま進む。
resolve_dep_env() {
  LEDGER_DEP_ENV=()
  local node_deps py
  node_deps="${LEDGER_NODE_PATH:-$HOME/Projects/reverse-docs-skills/node_modules}"
  py="${LEDGER_GLOSSARY_PYTHON:-$HOME/Projects/reverse-docs-skills/generation-engine/scripts/glossary/.venv/bin/python}"
  [ -d "$node_deps" ] && LEDGER_DEP_ENV+=("NODE_PATH=$node_deps")
  [ -x "$py" ] && LEDGER_DEP_ENV+=("GLOSSARY_PYTHON=$py")
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
  ' "$TIMEOUT_SECONDS" env "${LEDGER_DEP_ENV[@]}" bash -c "$command"
}

list_commands() {
  local file="$1"
  local found=0
  local key command repo_only

  while IFS=$'\t' read -r key command repo_only; do
    if [ -n "$ONLY_KEY" ] && [ "$key" != "$ONLY_KEY" ]; then
      continue
    fi
    printf '%s\t%s\t%s\n' "$key" "$command" "$repo_only"
    found=1
  done < "$file"

  if [ "$found" -eq 0 ] && [ -n "$ONLY_KEY" ]; then
    echo "[FAIL] 指定したキーに実行対象のコマンドがありません: $ONLY_KEY" >&2
    return 1
  fi
}

run_commands() {
  resolve_dep_env
  local file="$1"
  local found=0
  local failed=0
  local indeterminate=0
  local skipped=0
  local key command repo_only status

  while IFS=$'\t' read -r key command repo_only; do
    if [ -n "$ONLY_KEY" ] && [ "$key" != "$ONLY_KEY" ]; then
      continue
    fi
    found=1
    if [ "$repo_only" = "1" ] && ! repo_only_paths_exist "$command"; then
      echo "[SKIP] $key: 配布対象外の資産を参照するため対象外: $command"
      skipped=$((skipped + 1))
      continue
    fi
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
  echo "対象外 $skipped 件"
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

  # 断り書き（配布対象外）があっても、参照先パスの実在で分岐する。
  local repo_only_fixture="$WORK_DIR/repo-only.md"
  printf '%s\n' \
    '### case-repo-only-missing. 配布対象外・参照先なし' \
    '**状態**: 完了。配布対象外のため、この確かめは正本でだけ成立する。確かめたコマンドは `test -f docs/scripts/does-not-exist-anywhere.sh` である。' \
    '### case-repo-only-present. 配布対象外・参照先あり' \
    '**状態**: 完了。配布対象外のため、この確かめは正本でだけ成立する。確かめたコマンドは `test -f docs/scripts/check-ledger-commands-runnable.sh` である。' \
    > "$repo_only_fixture"

  output="$(LEDGER_COMMANDS_LEDGER="$repo_only_fixture" bash "$0" --run --only case-repo-only-missing 2>&1)"
  status=$?
  if [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -q '\[SKIP\]'; then
    echo "[PASS] 参照先が実在しない配布対象外コマンドを対象外として数え、不合格にしない"
  else
    echo "[FAIL] 参照先不在時の対象外判定が期待と一致しない: $status" >&2
    printf '%s\n' "$output" | sed 's/^/    /' >&2
    return 1
  fi

  if _cap="$(LEDGER_COMMANDS_LEDGER="$repo_only_fixture" bash "$0" --run --only case-repo-only-present 2>&1)"; then
    echo "[PASS] 参照先が実在すれば配布対象外の断り書きがあっても実行して合格と判定する"
  else
    echo "[FAIL] 参照先が実在するのに実行されなかった" >&2
    printf '%s\n' "$_cap" | sed 's/^/      /' >&2
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
