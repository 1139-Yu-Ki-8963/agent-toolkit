#!/bin/bash
# check-git-author-allowlist.sh のテスト。
# PreToolUse(Bash) hook: git commit / git push 直前に author name/email を検証する。
# 本テストは resolve_git_ctx_dir 経由のコンテキスト解決（cd 前置・-C 明示）の
# 回帰確認を主眼とする。
#
# 実行: bash check-git-author-allowlist.test.sh
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-git-author-allowlist.sh"
pass=0
fail=0
REAL_HOME="$HOME"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

STUB="$TMPROOT/bin"
mkdir -p "$STUB"
HOMEDIR="$TMPROOT/home"
mkdir -p "$HOMEDIR/.claude"
OTHERDIR="$TMPROOT/other-repo"
mkdir -p "$OTHERDIR"

cat > "$STUB/git" <<'EOF'
#!/bin/bash
LOG="${STUB_GIT_CALL_LOG:-/dev/null}"
printf '%s\n' "$*" >> "$LOG"
case "$*" in
  *"var GIT_AUTHOR_IDENT"*)
    echo "${STUB_AUTHOR_IDENT:-1139-Yu-Ki-8963 <63326271+1139-Yu-Ki-8963@users.noreply.github.com> 1700000000 +0900}"
    exit 0
    ;;
  *"symbolic-ref"*)
    echo "refs/remotes/origin/main"
    exit 0
    ;;
  *"merge-base"*)
    echo "abc123"
    exit 0
    ;;
  *"log --format="*)
    if [ -n "${STUB_LOG_OUTPUT:-}" ]; then
      printf '%s\n' "$STUB_LOG_OUTPUT"
    fi
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$STUB/git"

# marker-path.sh ライブラリを HOMEDIR にコピー（編集禁止・実体を source する）
mkdir -p "$HOMEDIR/agent-home/tools/hooks/shared"
cp "${REAL_HOME:-$HOME}/agent-home/tools/hooks/shared/marker-path.sh" "$HOMEDIR/agent-home/tools/hooks/shared/marker-path.sh"

PATHX="$STUB:/usr/bin:/bin:/opt/homebrew/bin"

run_case() { # $1=case_id $2=command $3=cwd
  STDOUT_LOG="$TMPROOT/stdout_$1"
  STDERR_LOG="$TMPROOT/stderr_$1"
  local cid="$1" command="$2" cwd="$3"
  printf '{"tool":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$command" "$cwd" \
    | env HOME="$HOMEDIR" PATH="$PATHX" \
        STUB_AUTHOR_IDENT="${STUB_AUTHOR_IDENT:-}" \
        STUB_LOG_OUTPUT="${STUB_LOG_OUTPUT:-}" \
        STUB_GIT_CALL_LOG="${STUB_GIT_CALL_LOG:-}" \
        bash "$SCRIPT" > "$STDOUT_LOG" 2> "$STDERR_LOG"
  RC=$?
}

assert_exit() { if [ "$RC" -eq "$1" ]; then pass=$((pass+1)); printf '  PASS: %s (exit %s)\n' "$2" "$RC"; else fail=$((fail+1)); printf '  FAIL: %s (expected exit %s, got %s)\n' "$2" "$1" "$RC"; fi; }
assert_log_contains() { if grep -qF -- "$2" "$STUB_GIT_CALL_LOG"; then pass=$((pass+1)); printf '  PASS: %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL: %s (git call log did not contain "%s": %s)\n' "$1" "$2" "$(cat "$STUB_GIT_CALL_LOG" 2>/dev/null)"; fi; }
assert_log_not_contains() { if grep -qF -- "$2" "$STUB_GIT_CALL_LOG"; then fail=$((fail+1)); printf '  FAIL: %s (git call log unexpectedly contained "%s")\n' "$1" "$2"; else pass=$((pass+1)); printf '  PASS: %s\n' "$1"; fi; }
assert_stderr_contains() { if grep -qF -- "$2" "$STDERR_LOG"; then pass=$((pass+1)); printf '  PASS: %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL: %s (stderr did not contain "%s")\n' "$1" "$2"; fi; }
assert_stdout_contains() { if grep -qF -- "$2" "$STDOUT_LOG"; then pass=$((pass+1)); printf '  PASS: %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL: %s (stdout did not contain "%s")\n' "$1" "$2"; fi; }

echo "=== check-git-author-allowlist.sh tests ==="

# B1: 前置なし通常の git commit（白リスト author）→ exit 0（回帰確認）
STUB_AUTHOR_IDENT="1139-Yu-Ki-8963 <63326271+1139-Yu-Ki-8963@users.noreply.github.com> 1700000000 +0900"
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b1.log"; : > "$STUB_GIT_CALL_LOG"
run_case b1 "git commit -m x" "$TMPROOT"
assert_exit 0 "B1 前置なし commit・白リスト author で exit 0"
assert_log_contains "B1 commit 検査は hook_cwd (-C $TMPROOT) を使う" "-C $TMPROOT"

# B2: 前置なし git commit（非白リスト author）→ exit 2（回帰確認）
STUB_AUTHOR_IDENT="malicious-user <evil@example.com> 1700000000 +0900"
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b2.log"; : > "$STUB_GIT_CALL_LOG"
run_case b2 "git commit -m x" "$TMPROOT"
assert_exit 2 "B2 非白リスト author で exit 2"
assert_stdout_contains "B2 GIT-AUTHOR-BLOCK タグ含む" "[GIT-AUTHOR-BLOCK]"

# B3: cd <他リポジトリ> && git push 形式で、push 検査が cd 先ディレクトリを対象にすること
STUB_AUTHOR_IDENT="1139-Yu-Ki-8963 <63326271+1139-Yu-Ki-8963@users.noreply.github.com> 1700000000 +0900"
STUB_LOG_OUTPUT=""
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b3.log"; : > "$STUB_GIT_CALL_LOG"
run_case b3 "cd $OTHERDIR && git push origin main" "$TMPROOT"
assert_exit 0 "B3 push 差分なしで exit 0"
assert_log_contains "B3 symbolic-ref が cd 先 (-C $OTHERDIR) を対象にする" "-C $OTHERDIR symbolic-ref"
assert_log_contains "B3 merge-base が cd 先 (-C $OTHERDIR) を対象にする" "-C $OTHERDIR merge-base"
assert_log_contains "B3 log が cd 先 (-C $OTHERDIR) を対象にする" "-C $OTHERDIR log --format="
assert_log_not_contains "B3 hook cwd ($TMPROOT) を誤って対象にしない" "-C $TMPROOT symbolic-ref"

# B4: 前置なし通常の git push → hook_cwd を対象にする（回帰確認）
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b4.log"; : > "$STUB_GIT_CALL_LOG"
run_case b4 "git push origin main" "$TMPROOT"
assert_exit 0 "B4 前置なし push・差分なしで exit 0"
assert_log_contains "B4 symbolic-ref が hook_cwd (-C $TMPROOT) を対象にする" "-C $TMPROOT symbolic-ref"

# B5: cd ~/.claude && git push 形式で、チルダが $HOMEDIR に正しく展開されること（回帰確認）
STUB_AUTHOR_IDENT="1139-Yu-Ki-8963 <63326271+1139-Yu-Ki-8963@users.noreply.github.com> 1700000000 +0900"
STUB_LOG_OUTPUT=""
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b5.log"; : > "$STUB_GIT_CALL_LOG"
run_case b5 "cd ~/.claude && git push origin main" "$TMPROOT"
assert_exit 0 "B5 push 差分なしで exit 0"
assert_log_contains "B5 symbolic-ref が cd 先 (-C $HOMEDIR/.claude) を対象にする" "-C $HOMEDIR/.claude symbolic-ref"
assert_log_not_contains "B5 チルダ未展開のパスを誤って使わない" "-C ~/.claude symbolic-ref"

# B6: git -C ~/.claude commit -m x をSTUB_AUTHOR_IDENT未設定で実行し、
# var GIT_AUTHOR_IDENT 呼び出しが -C $HOMEDIR/.claude を伴うこと（実測されたバグ症状の直接回帰）
unset STUB_AUTHOR_IDENT
STUB_GIT_CALL_LOG="$TMPROOT/gitcalls_b6.log"; : > "$STUB_GIT_CALL_LOG"
run_case b6 "git -C ~/.claude commit -m x" "$TMPROOT"
assert_exit 0 "B6 -C ~/.claude が正しく展開され白リスト author で exit 0"
assert_log_contains "B6 var GIT_AUTHOR_IDENT が -C $HOMEDIR/.claude を対象にする" "-C $HOMEDIR/.claude var GIT_AUTHOR_IDENT"
assert_log_not_contains "B6 チルダ未展開のパスを誤って使わない" "-C ~/.claude var GIT_AUTHOR_IDENT"

echo ""
echo "=== result: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
