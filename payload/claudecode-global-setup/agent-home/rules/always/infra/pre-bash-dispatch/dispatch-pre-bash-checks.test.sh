#!/bin/bash
# dispatch-pre-bash-checks.sh のテスト。
#
# git commit / git push 検出をコマンド文字列の前方一致から
# セグメント認識（resolve_git_ctx_dir）へ切り替えた回帰確認。
# `git -C <dir> commit` / `cd <dir> && git commit` 形式でも
# secret 検出等の検査が正しく発火することを確認する。
#
# 実マシンの実 git / node / jq / perl をそのまま使う（実 HOME を使用。
# marker-path.sh は実配置のものをそのまま参照する）。
#
# 実行: bash dispatch-pre-bash-checks.test.sh
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dispatch-pre-bash-checks.sh"
pass=0
fail=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# 実トークン形式(ghp_+36英数字)の正規表現に単独行で一致しないよう2分割し、
# 実行時にのみ結合する(本ソース自体がSECRET-BLOCKに誤検出されるのを避けるため)。
_SECRET_PART1='ghp_1234567890abcdef123456789'
_SECRET_PART2='0abcdef1234'
SECRET_LINE="token = \"${_SECRET_PART1}${_SECRET_PART2}\""

make_repo() { # $1=repo_dir
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test User"
  printf 'hello\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "init"
}

stage_secret() { # $1=repo_dir
  local dir="$1"
  printf '%s\n' "$SECRET_LINE" > "$dir/secret.txt"
  git -C "$dir" add secret.txt
}

stage_plain() { # $1=repo_dir
  local dir="$1"
  printf 'plain change\n' >> "$dir/README.md"
  git -C "$dir" add README.md
}

run_case() { # $1=case_id $2=command $3=cwd $4=env prefix（省略可。例: "HOME=$TMPROOT"）
  STDOUT_LOG="$TMPROOT/stdout_$1"
  STDERR_LOG="$TMPROOT/stderr_$1"
  local envprefix="${4:-}"
  if [ -n "$envprefix" ]; then
    jq -n --arg cmd "$2" --arg cwd "$3" \
        '{"tool":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}' \
      | env $envprefix bash "$SCRIPT" > "$STDOUT_LOG" 2> "$STDERR_LOG"
  else
    jq -n --arg cmd "$2" --arg cwd "$3" \
        '{"tool":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}' \
      | bash "$SCRIPT" > "$STDOUT_LOG" 2> "$STDERR_LOG"
  fi
  RC=$?
}

assert_exit() { if [ "$RC" -eq "$1" ]; then pass=$((pass+1)); printf '  PASS: %s (exit %s)\n' "$2" "$RC"; else fail=$((fail+1)); printf '  FAIL: %s (expected exit %s, got %s)\n' "$2" "$1" "$RC"; fi; }
assert_stderr_contains() { if grep -qF -- "$2" "$STDERR_LOG"; then pass=$((pass+1)); printf '  PASS: %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL: %s (stderr did not contain "%s"; stderr=%s)\n' "$1" "$2" "$(cat "$STDERR_LOG")"; fi; }
assert_stdout_contains() { if grep -qF -- "$2" "$STDOUT_LOG"; then pass=$((pass+1)); printf '  PASS: %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL: %s (stdout did not contain "%s"; stdout=%s)\n' "$1" "$2" "$(cat "$STDOUT_LOG")"; fi; }

echo "=== dispatch-pre-bash-checks.sh tests ==="

# B1: 通常の git commit（前置なし・secret なし）→ exit 0（従来通り）
REPO1="$TMPROOT/repo1"
make_repo "$REPO1"
stage_plain "$REPO1"
run_case b1 'git commit -m "test"' "$REPO1"
assert_exit 0 "B1 通常 git commit・secret なしで exit 0"
assert_stdout_contains "B1 NAMING context 含む" '[NAMING]'

# B2: staged 差分に secret を含む状態で、通常の git commit が exit 2 で block（回帰確認）
REPO2="$TMPROOT/repo2"
make_repo "$REPO2"
stage_secret "$REPO2"
run_case b2 'git commit -m "test"' "$REPO2"
assert_exit 2 "B2 通常 git commit・secret ありで exit 2"
assert_stderr_contains "B2 [SECRET-BLOCK] タグ含む" "[SECRET-BLOCK]"

# B3: `git -C <dir> commit` 形式で、secret 検出が正しく発火すること
REPO3="$TMPROOT/repo3"
make_repo "$REPO3"
stage_secret "$REPO3"
NONREPO_CWD="$TMPROOT/nonrepo_cwd"
mkdir -p "$NONREPO_CWD"
run_case b3 "git -C $REPO3 commit -m x" "$NONREPO_CWD"
assert_exit 2 "B3 git -C <dir> commit で secret 検出発火 → exit 2"
assert_stderr_contains "B3 [SECRET-BLOCK] タグ含む" "[SECRET-BLOCK]"

# B4: `cd <dir> && git commit` 形式でも同様に secret 検出が発火すること
REPO4="$TMPROOT/repo4"
make_repo "$REPO4"
stage_secret "$REPO4"
run_case b4 "cd $REPO4 && git commit -m x" "$NONREPO_CWD"
assert_exit 2 "B4 cd <dir> && git commit で secret 検出発火 → exit 2"
assert_stderr_contains "B4 [SECRET-BLOCK] タグ含む" "[SECRET-BLOCK]"

# B5: `git -C <dir> commit` 形式で、secret が無ければ exit 0 になること（誤検出なし確認）
REPO5="$TMPROOT/repo5"
make_repo "$REPO5"
stage_plain "$REPO5"
run_case b5 "git -C $REPO5 commit -m x" "$NONREPO_CWD"
assert_exit 0 "B5 git -C <dir> commit・secret なしで exit 0"

# B6: git checkout -b foo（変更しない5分岐の1つ）が従来通り動作すること（回帰確認）
run_case b6 "git checkout -b feature/foo" "$NONREPO_CWD"
assert_exit 0 "B6 git checkout -b で exit 0"
assert_stdout_contains "B6 ブランチ命名 NAMING context 含む" '[NAMING] ブランチ'

# dispatch-pre-bash-checks.sh は既定で $HOME/agent-home/tools/hooks/shared/marker-path.sh を source する。
# HOME=$TMPROOT を注入する B7/B8 のため、実 lib を $TMPROOT 配下にも配置する（author-check.test.sh と同じ発想）。
mkdir -p "$TMPROOT/agent-home/tools/hooks/shared"
cp "${HOME}/agent-home/tools/hooks/shared/marker-path.sh" "$TMPROOT/agent-home/tools/hooks/shared/marker-path.sh"

# B7: HOME=$TMPROOT 注入で `cd ~/repo3 && git commit` のチルダが REPO3 (secret staged 済み) に
# 正しく展開され、secret 検出が発火すること（回帰確認）
run_case b7 "cd ~/repo3 && git commit -m x" "$NONREPO_CWD" "HOME=$TMPROOT"
assert_exit 2 "B7 cd ~/repo3 (チルダ展開) で secret 検出発火 → exit 2"
assert_stderr_contains "B7 [SECRET-BLOCK] タグ含む" "[SECRET-BLOCK]"

# B8: HOME=$TMPROOT 注入で `git -C ~/repo3 commit` のチルダが REPO3 に正しく展開されること
run_case b8 "git -C ~/repo3 commit -m x" "$NONREPO_CWD" "HOME=$TMPROOT"
assert_exit 2 "B8 git -C ~/repo3 (チルダ展開) で secret 検出発火 → exit 2"
assert_stderr_contains "B8 [SECRET-BLOCK] タグ含む" "[SECRET-BLOCK]"

echo ""
echo "=== result: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
