#!/usr/bin/env bash
# check-managing-configs-commit-gate.sh の回帰テスト（18 ケース）
# 実行: bash check-managing-configs-commit-gate.test.sh → exit 0（全 PASS）/ 1（FAIL あり）
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SELF_DIR/check-managing-configs-commit-gate.sh"
MARKER_LIB="$HOME/agent-home/tools/hooks/shared/marker-path.sh"

TMPROOT="$(mktemp -d)"
export TMPDIR="$TMPROOT/"
SESSION="testsession"
MARKER_DIR="$TMPROOT/claude-hooks/$SESSION"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

# 一時 git リポジトリを準備（メインツリー扱い = marker_path は /tmp/claude-hooks にフォールバック）
REPO="$TMPROOT/repo"
mkdir -p "$REPO/skills/foo" "$REPO/.claude/rules/bar" "$REPO/src"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "test"
printf '# skill\n' > "$REPO/skills/foo/SKILL.md"
printf '# rule\n' > "$REPO/.claude/rules/bar/rule.md"
printf 'code\n' > "$REPO/src/a.sh"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m init

reset_markers() { rm -rf "$MARKER_DIR"; }

run_case() { # $1=command 文字列 $2=cwd（省略時 $REPO） $3=env prefix（省略可）
  local cmd="$1"
  local cwd="${2:-$REPO}"
  local envprefix="${3:-}"
  local json
  json=$(jq -n --arg cmd "$cmd" --arg cwd "$cwd" --arg session "$SESSION" \
    '{session_id: $session, cwd: $cwd, tool_input: {command: $cmd}}')
  STDERR_LOG="$TMPROOT/stderr.log"
  if [ -n "$envprefix" ]; then
    printf '%s' "$json" | env $envprefix bash "$SCRIPT" > "$TMPROOT/stdout.log" 2> "$STDERR_LOG"
  else
    printf '%s' "$json" | bash "$SCRIPT" > "$TMPROOT/stdout.log" 2> "$STDERR_LOG"
  fi
  RC=$?
}

assert() { # $1=期待値判定(0/1) $2=ケース名
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf 'PASS: %s\n' "$2"
  else FAIL=$((FAIL+1)); printf 'FAIL: %s (rc=%s)\n' "$2" "$RC"; cat "$STDERR_LOG" 2>/dev/null; fi
}

write_report() { # $1=asset_type $2=verdict行を含めるか(pass|nopass) -> report_marker のパスを echo する
  local asset_type="$1" verdict="${2:-pass}"
  . "$MARKER_LIB"
  local report
  report="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-${asset_type}-report.md")"
  {
    printf '# managing-agent-configs report (%s)\n\n' "$asset_type"
    printf 'CRITICAL: 0 / WARN: 0 / INFO: 0\n'
    printf 'test: 実行検証で要件達成\n'
    if [ "$verdict" = "pass" ]; then
      printf 'REVIEW-TEST-VERDICT: PASS\n'
    fi
  } > "$report"
  printf '%s' "$report"
}

write_passed_marker() { # $1=asset_type $2...=relpath... （report も併せて生成する既定ヘルパー）
  local asset_type="$1"; shift
  . "$MARKER_LIB"
  local report report_hash marker
  report="$(write_report "$asset_type" pass)"
  report_hash=$(shasum -a 256 "$report" | awk '{print $1}')
  marker="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-${asset_type}-test-passed")"
  printf 'REPORT_SHA256=%s\n' "$report_hash" > "$marker"
  for f in "$@"; do
    ( cd "$REPO" && shasum -a 256 "$f" ) >> "$marker"
  done
}

# --- C1: managed staged あり・マーカーなし → block ---
reset_markers
git -C "$REPO" stage skills/foo/SKILL.md 2>/dev/null
printf 'updated\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case 'git add -A && git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" 'managed staged・マーカーなし block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C2: git -C <repo> commit -m x → block ---
reset_markers
printf 'updated2\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case "git -C $REPO commit -m x" "$TMPROOT"
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" 'git -C 形式 block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C3: cd <repo>; git commit -m x → block ---
reset_markers
printf 'updated3\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case "cd $REPO; git commit -m x"
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" 'cd; 複合コマンド block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C4: 改行区切りで git commit を含む複合 → block ---
reset_markers
printf 'updated4\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case "$(printf 'echo hello\ngit commit -m x')"
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" '改行区切り複合コマンド block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C5: git commitizen init → exit 0（語境界誤検知なし） ---
reset_markers
run_case 'git commitizen init'
assert "$([ "$RC" -eq 0 ]; echo $?)" 'git commitizen 誤検知なし'

# --- C6: git log --grep "commit" → exit 0 ---
reset_markers
run_case 'git log --grep "commit"'
assert "$([ "$RC" -eq 0 ]; echo $?)" 'git log --grep commit 誤検知なし'

# --- C7: MANAGING_MARKER_LIB=/nonexistent で git commit → fail-loud block ---
reset_markers
printf 'updated7\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case 'git commit -m x' "$REPO" 'MANAGING_MARKER_LIB=/nonexistent/marker-path.sh'
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-GATE-DISABLED' "$STDERR_LOG"; echo $?)" 'fail-loud: lib 不在 block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C8: テスト→マーカー生成→ commit → exit 0 ---
reset_markers
printf 'updated8\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
write_passed_marker skills skills/foo/SKILL.md
run_case 'git commit -m x'
assert "$([ "$RC" -eq 0 ]; echo $?)" 'ハッシュ一致 → 通過'
git -C "$REPO" commit -q -m "c8" >/dev/null 2>&1 || true

# --- C9: マーカー生成後に managed ファイル再編集 + add → block（stale） ---
reset_markers
printf 'updated9\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
write_passed_marker skills skills/foo/SKILL.md
printf 'updated9-modified\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case 'git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'stale' "$STDERR_LOG"; echo $?)" '再編集後 stale block'

# --- C10: 再編集を revert して staged がマーカーと一致 → exit 0 ---
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
printf 'updated9\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case 'git commit -m x'
assert "$([ "$RC" -eq 0 ]; echo $?)" 'revert 後ハッシュ一致 → 通過'
git -C "$REPO" commit -q -m "c10" >/dev/null 2>&1 || true

# --- C11: 非 managed ファイルのみの commit（マーカーなし）→ exit 0 ---
reset_markers
printf 'src-updated\n' > "$REPO/src/a.sh"
git -C "$REPO" add src/a.sh
run_case 'git commit -m x'
assert "$([ "$RC" -eq 0 ]; echo $?)" '非managedのみ commit → 通過'
git -C "$REPO" reset -q HEAD src/a.sh >/dev/null 2>&1
git -C "$REPO" checkout -q -- src/a.sh

# --- C12: managed_asset_type() の単体検証 ---
. "$MARKER_LIB"
unit_pass=0
unit_fail=0
check_type() {
  local path="$1" expect="$2" got
  got="$(managed_asset_type "$path")"
  if [ "$got" = "$expect" ]; then
    unit_pass=$((unit_pass+1))
  else
    unit_fail=$((unit_fail+1))
    printf 'UNIT FAIL: %s -> got=%q expect=%q\n' "$path" "$got" "$expect"
  fi
}
check_type "skills/x/SKILL.md" "skills"
check_type "skills/x/scripts/a.sh" "skills"
check_type "skills/x/references/b.md" "skills"
check_type ".claude/rules/x/rule.md" "rules"
check_type ".claude/rules/x/a.sh" "rules"
check_type "rules/x/prh.yml" "rules"
check_type "routines/x/ルーティン設計書.md" "routines"
check_type "tools/hooks/a.sh" "hooks"
check_type "src/a.sh" ""
check_type "docs/readme.md" ""
check_type "skills/x/assets/a.png" ""
assert "$([ "$unit_fail" -eq 0 ]; echo $?)" 'managed_asset_type 単体検証(11パス)'

# --- C13: cd <repo> && git commit -m x（hook cwd は別ディレクトリ）→ cwd 解決して block ---
reset_markers
printf 'updated13\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case "cd $REPO && git commit -m x" "$TMPROOT"
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" 'cd && 複合コマンド cwd解決 block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C14: cd ~/repo && git commit -m x（HOME=$TMPROOT 注入でチルダが $REPO に展開）→ block ---
# check-managing-configs-commit-gate.sh は既定で $HOME/agent-home/tools/hooks/shared/marker-path.sh を source する。
# HOME=$TMPROOT を注入するテストのため、実 lib を $TMPROOT 配下にも配置する（author-check.test.sh と同じ発想）。
reset_markers
mkdir -p "$TMPROOT/agent-home/tools/hooks/shared"
cp "$MARKER_LIB" "$TMPROOT/agent-home/tools/hooks/shared/marker-path.sh"
printf 'updated14\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
run_case "cd ~/repo && git commit -m x" "$TMPROOT" "HOME=$TMPROOT"
assert "$([ "$RC" -eq 2 ] && grep -q 'MANAGING-COMMIT-BLOCK' "$STDERR_LOG"; echo $?)" 'cd ~/repo (チルダ展開) block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C15: test-passed マーカーはあるが report ファイルが欠落 → block(report欠落) ---
reset_markers
printf 'updated15\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
write_passed_marker skills skills/foo/SKILL.md
report_marker="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-skills-report.md")"
rm -f "$report_marker"
run_case 'git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'report欠落' "$STDERR_LOG"; echo $?)" 'T4: report欠落 block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C16: report はあるが REVIEW-TEST-VERDICT: PASS 行がない → block(reportにPASS宣言なし) ---
reset_markers
printf 'updated16\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
report_marker="$(write_report skills nopass)"
report_hash=$(shasum -a 256 "$report_marker" | awk '{print $1}')
passed_marker="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-skills-test-passed")"
{
  printf 'REPORT_SHA256=%s\n' "$report_hash"
  ( cd "$REPO" && shasum -a 256 skills/foo/SKILL.md )
} > "$passed_marker"
run_case 'git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'reportにPASS宣言なし' "$STDERR_LOG"; echo $?)" 'T4: PASS宣言なし block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C17: report 作成後に needed マーカーが touch される（再編集）→ block(stale, report作成後に再編集) ---
reset_markers
printf 'updated17\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
write_passed_marker skills skills/foo/SKILL.md
needed_marker="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-skills-needed")"
sleep 1
touch "$needed_marker"
run_case 'git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'report作成後に再編集' "$STDERR_LOG"; echo $?)" 'T4: needed が report より新しい stale block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

# --- C18: test-passed マーカー内の REPORT_SHA256 が report の実ハッシュと不一致 → block(stale, ハッシュ不一致) ---
reset_markers
printf 'updated18\n' > "$REPO/skills/foo/SKILL.md"
git -C "$REPO" add skills/foo/SKILL.md
write_passed_marker skills skills/foo/SKILL.md
passed_marker="$(marker_path "$REPO" "$SESSION" "managing-agent-configs-skills-test-passed")"
sed -i.bak 's/^REPORT_SHA256=.*/REPORT_SHA256=deadbeef/' "$passed_marker"
rm -f "${passed_marker}.bak"
run_case 'git commit -m x'
assert "$([ "$RC" -eq 2 ] && grep -q 'reportとマーカーのハッシュ不一致' "$STDERR_LOG"; echo $?)" 'T4: reportハッシュ不一致 block'
git -C "$REPO" reset -q HEAD skills/foo/SKILL.md >/dev/null 2>&1
git -C "$REPO" checkout -q -- skills/foo/SKILL.md

printf '\n%s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
