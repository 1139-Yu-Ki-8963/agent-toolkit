#!/usr/bin/env bash
set -euo pipefail

# check-worktree-commit-guard.sh — reverse-docs-skills 検証環境の同梱ガード（PreToolUse(Bash) 相当）
#
# 目的: original-code-*/reverse-code-* worktree（syncing-reverse-env が用意する検証用環境）に
# 対する git commit/git push の誤操作を機械的に防ぐ。安全柵の全体像は RUNBOOK.md を参照。
#
# 使い方:
#   フック本体として: PreToolUse(Bash) のフック入力 JSON（tool_input.command / cwd を含む）を
#     stdin から受け取り、判定結果に応じて exit code を返す（0=許可・2=拒否）。
#   単体実行:
#     check-worktree-commit-guard.sh --self-test
#
# 判定ロジック（優先順）:
#   1. cwd から worktree のトップレベルディレクトリ名を解決する（`git rev-parse --show-toplevel` の
#      basename）。解決できない場合（git管理外・パス不在等）は「worktree外」として対象外
#      （exit 0・fail-open）。
#   2. worktree名が `original-code-*` または `reverse-code-*` のいずれにも一致しない場合も
#      「worktree外（管理対象外）」として対象外（exit 0・fail-open）。
#   3. 上記いずれかに一致する場合のみ判定する:
#      - `git push` は常に拒否（exit 2）。original/reverse いずれのworktreeからのpushも禁止。
#        push可能な唯一の経路は正本リポジトリ（reverse-docs-skills本体）からの操作であり、
#        検証用worktree（original-code-*/reverse-code-*のいずれも）は対象外。
#      - `git commit` はworktree名で分岐する:
#          original-code-* → 拒否（exit 2）。リバース元は常に「正」であり変更不可のため。
#          reverse-code-*   → 許可（exit 0）。設計書だけからの再構築先であり書き込み対象。
#      - commit/push以外のgitコマンド・非gitコマンドは対象外（exit 0）。
#
# 既知の限界:
#   - 引用符内の空白は解釈しない単純なトークン走査であるため、コミットメッセージに
#     「push」という語を含む場合（例: git commit -m "before push"）、誤ってpushコマンドと
#     判定される可能性がある。本ガードはfail-open設計のため、この誤検知は「安全側に倒れる」
#     （余計にblockされる）方向にのみ作用し、危険な操作を通してしまう方向には作用しない。
#   - worktree名の判定はcwdのgit toplevelのbasenameのみを見る。symlink経由・相対パスの
#     `-C`指定等でcwdとgit toplevelの対応がずれる環境では誤判定しうる。
#
# 保守責任者: 人手（ユーザー）。worktree命名規則（original-code-*/reverse-code-*）を変更した
# 場合は本スクリプトとRUNBOOK.mdの両方を同時に更新する。
#
# macOS bash 3.2 互換。

worktree_name() {
  # $1: cwd
  # 標準出力にworktree名（トップレベルのbasename）を書き出す。解決不能ならexit 1で返す。
  cwd="$1"
  toplevel="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || true
  if [ -z "${toplevel:-}" ]; then
    return 1
  fi
  basename "$toplevel"
  return 0
}

command_has_git_subcommand() {
  # $1: コマンド文字列, $2: サブコマンド名（push|commit）
  # 簡易判定（既知の限界はファイル冒頭を参照）
  sub="$2"
  printf '%s' "$1" | grep -Eq "git([[:space:]]+-[A-Za-z]([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+${sub}([[:space:]]|\$)"
}

judge() {
  # $1: cwd, $2: command
  # 標準出力: 判定理由の1行メッセージ。戻り値: 0=許可・2=拒否
  cwd="$1"
  command="$2"

  if ! name="$(worktree_name "$cwd")"; then
    echo "対象外: worktreeを解決できません（git管理外またはパス不在。fail-open）"
    return 0
  fi

  case "$name" in
    original-code-*)
      if command_has_git_subcommand "$command" push; then
        echo "拒否: original-code-* worktree（${name}）からのgit pushは禁止（正本以外からのpush厳禁）"
        return 2
      fi
      if command_has_git_subcommand "$command" commit; then
        echo "拒否: original-code-* worktree（${name}）へのcommitは禁止（リバース元は常に「正」で変更不可）"
        return 2
      fi
      echo "対象外: commit/push以外のコマンドです（worktree=${name}）"
      return 0
      ;;
    reverse-code-*)
      if command_has_git_subcommand "$command" push; then
        echo "拒否: reverse-code-* worktree（${name}）からのgit pushは禁止（配布物への書き込みは一方通行同期のみで行う）"
        return 2
      fi
      if command_has_git_subcommand "$command" commit; then
        echo "許可: reverse-code-* worktree（${name}）へのcommitは許可"
        return 0
      fi
      echo "対象外: commit/push以外のコマンドです（worktree=${name}）"
      return 0
      ;;
    *)
      echo "対象外: 管理対象外のworktree名です（${name}。fail-open）"
      return 0
      ;;
  esac
}

self_test() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-worktree-commit-guard-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN
  rc=0

  # 系1: original-code-* worktreeでのcommitは拒否される
  dir1="$tmp/original-code-sample-system"
  mkdir -p "$dir1"
  (cd "$dir1" && git init -q)
  if msg="$(judge "$dir1" 'git commit -m "test"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系1: original-code-* worktreeでのcommitが拒否される（${msg}）"
  else
    echo "  [FAIL] 系1: original-code-* worktreeでのcommitが拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系2: reverse-code-* worktreeでのcommitは許可される
  dir2="$tmp/reverse-code-sample-system-screen-1"
  mkdir -p "$dir2"
  (cd "$dir2" && git init -q)
  if msg="$(judge "$dir2" 'git commit -m "test"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系2: reverse-code-* worktreeでのcommitが許可される（${msg}）"
  else
    echo "  [FAIL] 系2: reverse-code-* worktreeでのcommitが許可されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系3: reverse-code-* worktreeからのgit pushは（commitが許可される環境でも）拒否される
  if msg="$(judge "$dir2" 'git push origin HEAD:main')"; then code=0; else code=$?; fi
  if [ "$code" -eq 2 ]; then
    echo "  [PASS] 系3: reverse-code-* worktreeからのgit pushが拒否される（${msg}）"
  else
    echo "  [FAIL] 系3: reverse-code-* worktreeからのgit pushが拒否されなかった（exit=${code}）" >&2
    rc=1
  fi

  # 系4: worktree外（管理対象外のworktree名）は対象外として素通しされる
  dir4="$tmp/some-unrelated-repo"
  mkdir -p "$dir4"
  (cd "$dir4" && git init -q)
  if msg="$(judge "$dir4" 'git commit -m "test"')"; then code=0; else code=$?; fi
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] 系4: worktree外（管理対象外の名前）は対象外として素通しされる（${msg}）"
  else
    echo "  [FAIL] 系4: worktree外なのにblockされた（exit=${code}）" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    echo "self-test 全項目 PASS"
  else
    echo "self-test FAIL" >&2
  fi
  return "$rc"
}

main() {
  input="$(cat)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  [ -z "$cwd" ] && cwd="$PWD"
  if [ -z "$command" ]; then
    exit 0
  fi
  if msg="$(judge "$cwd" "$command")"; then code=0; else code=$?; fi
  if [ "$code" -ne 0 ]; then
    echo "$msg" >&2
  fi
  exit "$code"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

main
