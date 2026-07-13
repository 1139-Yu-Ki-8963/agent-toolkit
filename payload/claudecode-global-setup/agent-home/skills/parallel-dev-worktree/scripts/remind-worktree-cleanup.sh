#!/usr/bin/env bash
# Stop hook: 実装フロー（orchestrating-dev-flow。旧 full-cycle-flow 互換）完了時の未片付けを検出して書き戻す。
#   (1) WORKTREE-CLEANUP: セッションの cwd がマージ済み & クリーンな worktree のまま
#       → Phase 10 の片付け（cd <main> && git worktree remove --force）が未実施。
#       対象パス: <repo>/.claude/worktrees/*（slot 例外）と ~/Projects/worktrees/*（中央規約）
#   (2) FLOW-SELFIMPROVE-PENDING: マージ到達済みなのに fixing-flow-frictions 未起動（旧世代セッションのみ発火）。
#
# どちらも decision:block で書き戻すが、counter で 2 回到達時に自動解除する
# （check-no-deferral-stop.sh と同じ livelock guard）。正常な沈黙ケースで無限ループしない。

set -u

. "$HOME/agent-home/tools/hooks/shared/marker-path.sh"

[ -n "${CLAUDE_HOOK_SUMMARY_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_AUTOCOMMIT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_FLOW_REPORT_RUNNING:-}" ] && exit 0
[ -n "${CLAUDE_HOOK_DICT_RUNNING:-}" ] && exit 0

input="$(cat)"
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$session" ] && exit 0

# 実装フロー起動セッションのみ対象（orchestrating-dev-flow が現行。full-cycle-flow は旧名互換）
log="$HOME/agent-home/sessions/.skill-log/${session}.jsonl"
[ ! -f "$log" ] && exit 0
grep -qE '"skill"[[:space:]]*:[[:space:]]*"(orchestrating-dev-flow|full-cycle-flow)"' "$log" || exit 0

msgs=""

# ── (1) worktree 片付け検出（cwd ベース）──
# cwd が .claude/worktrees/<wt> 配下で、その branch が origin/main にマージ済み &
# 実作業の未コミット変更が無いなら、Phase 10-2 の片付けが未実施。
case "$cwd" in
  */.claude/worktrees/*|*/Projects/worktrees/*)
    # branch・main・worktree ルートを git から正確に取得する
    if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
      wt_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
      main=$(git -C "$cwd" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
      branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")
      if [ -n "$wt_root" ] && [ -n "$main" ] && [ "$wt_root" != "$main" ]; then
        git -C "$cwd" fetch origin main >/dev/null 2>&1 || true
        merged=0
        git -C "$cwd" merge-base --is-ancestor HEAD origin/main 2>/dev/null && merged=1
        # 実作業の未コミット差分（生成物以外）が無いか
        art='\.status\.json|PROGRESS\.md|\.worktree-ports\.env|node_modules|tsconfig\.tsbuildinfo|package-lock\.json'
        dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -vE "$art" | grep -c . || echo 0)
        if [ "$merged" = 1 ] && [ "${dirty:-0}" = 0 ]; then
          msgs="${msgs}[WORKTREE-CLEANUP] マージ済み & クリーンな worktree（${wt_root} / ブランチ ${branch}）が残っています。orchestrating-dev-flow Phase 10 に従い後片付けしてください:
  cd ${main} && git worktree remove --force ${wt_root}
  git -C ${main} branch -D ${branch}
（cd <main> 先行で削除すれば cwd は main にリセットされます）
"
        fi
      fi
    fi
    ;;
esac

# ── (2) フロー自己改善（Phase 11-2）未実施検出 ──
# マージ到達（fixing-review-findings または auto-ship が skill-log にある）かつ
# fixing-flow-frictions 未起動なら soft リマインド。
if grep -qE '"skill"[[:space:]]*:[[:space:]]*"(fixing-review-findings|auto-ship)"' "$log"; then
  if ! grep -qE '"skill"[[:space:]]*:[[:space:]]*"fixing-flow-frictions"' "$log"; then
    msgs="${msgs}[FLOW-SELFIMPROVE-PENDING] full-cycle-flow Phase 11-2「フロー自己改善」が未実施です。Skill(\"fixing-flow-frictions\") を起動してください（再発フリクションが閾値未満なら沈黙して終了します）。
"
  fi
fi

[ -z "$msgs" ] && exit 0

# counter livelock guard（2 回到達で自動解除）
counter="$(marker_path "$cwd" "$session" remind-worktree-cleanup.count)"
hits=0
[ -f "$counter" ] && hits=$(cat "$counter" 2>/dev/null || echo 0)
hits=$((hits + 1))
printf '%d' "$hits" > "$counter"
if [ "$hits" -ge 2 ]; then
  rm -f "$counter"
  exit 0
fi

jq -n --arg r "$msgs" '{"decision":"block","reason":$r}'
exit 0
