#!/usr/bin/env bash
# rules-bash-runner.sh - PreToolUse(Bash) hook
#
# 役割: rules 系 PreToolUse(Bash) hook 10 本を 1 プロセスに集約するランナー。
#       非該当コマンドでは fork ゼロで即抜けし、全 Bash 実行の直列レイテンシを削減する。
# 仕様: 各 hook の正本は従来どおり各 rules ディレクトリの .sh（挙動・仕様は変更しない）。
#       本ランナーはトリガー条件に一致した hook にだけ stdin JSON をそのまま渡して起動し、
#       stdout・stderr・exit code を透過する。ガード条件は各 hook 内部の判定の上位集合であること。
#
# 集約対象（実行順は旧 settings.json の登録順を保存）:
#   1. always/response/guard/check-no-deferral-pre-bash.sh      (gh pr/issue create・comment)
#   2. always/response/guard/check-no-delegation-pre-bash.sh    (対話必須コマンド)
#   3. always/placement/file-guard/check-claude-home-root-marker.sh         (~/.claude ルート直下ドットファイル)
#   4. always/agent/subagent-selection/check-main-agent-direct-work.sh  (常時: 内部に read-only 許可リストを持つ)
#   5. always/placement/directory-structure/check-mkdir-allowlist.sh (mkdir)
#   6. always/agent-config/review/check-managing-configs-commit-gate.sh    (git commit)
#   7. scoped/tooling/shell/check-curl-egress.sh               (curl / wget)
#   8. always/gate/phase-step-task/check-phase-entry-tasks.sh      (update-flow-status.sh)
#   9. always/local-environment/port-management/check-port-launch.sh        (dev サーバー起動: vite/next/uvicorn/prisma studio/http.server)
#   10. always/placement/flow-context-guard/check-flow-context-guard.sh (git commit: flow-values.yml 不在検知)
#
# 1/5/6/7 は前方一致ではなく部分一致（*pattern*）で判定する。cd 前置（cd dir && git commit）
# や git -C 形式（git -C dir commit）でコマンド文字列の先頭が変わり前方一致が素通りするため（2026-07-05 実測）。
# 6 の dispatch 条件（*git*commit*）は意図的に粗い上位集合。精密な複合コマンド分割・
# git commitizen 等の語境界判定は check-managing-configs-commit-gate.sh 内部が担う（2026-07-06 拡張）。
set -u

input="$(cat)"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

R="$HOME/.claude/rules"

run_hook() {
  [ -f "$1" ] || return 0
  _out=$(printf '%s' "$input" | bash "$1")
  _rc=$?
  [ -n "$_out" ] && printf '%s\n' "$_out"
  if [ "$_rc" -ne 0 ]; then
    # block 経路: 子の stdout（additionalContext JSON）を stderr にも複製する。
    # exit 2 時の子 stderr は透過済みだが、子が理由を stdout の JSON にしか
    # 書いていない場合に UI 上「No stderr output」と誤表示されるのを防ぐ。
    [ -n "$_out" ] && printf '%s\n' "$_out" >&2
    exit "$_rc"
  fi
  return 0
}

# 1. gh pr/issue create・comment の先送り表現 block
case "$cmd" in
  *"gh pr create"*|*"gh issue create"*|*"gh issue comment"*|*"gh pr comment"*)
    run_hook "$R/always/response/guard/check-no-deferral-pre-bash.sh" ;;
esac

# 2. 対話必須コマンド block（コマンド中のどこでも）
case "$cmd" in
  *"gh auth login"*|*"npm login"*|*"docker login"*|*"gcloud auth login"*|*"aws configure"*|*"ssh-keygen"*|*"vercel login"*|*"supabase login"*|*"render login"*|*"heroku login"*)
    run_hook "$R/always/response/guard/check-no-delegation-pre-bash.sh" ;;
esac

# 3. ~/.claude ルート直下ドットファイル生成 block（".claude/." を含む場合のみ）
case "$cmd" in
  *".claude/."*)
    run_hook "$R/always/placement/file-guard/check-claude-home-root-marker.sh" ;;
esac

# 4. メイン直接作業 block（read-only 許可リスト判定は hook 内部が持つため常時起動）
run_hook "$R/always/agent/subagent-selection/check-main-agent-direct-work.sh"

# 5. mkdir 許可リスト照合
case "$cmd" in
  *"mkdir "*)
    run_hook "$R/always/placement/directory-structure/check-mkdir-allowlist.sh" ;;
esac

# 6. managing 系テスト完了ゲート（dispatch は粗い上位集合。精密判定は gate 側が行う）
case "$cmd" in
  *git*commit*)
    run_hook "$R/always/agent-config/review/check-managing-configs-commit-gate.sh" ;;
esac

# 7. 外部 curl / wget の egress block（localhost と call-api.sh のみ許可）
case "$cmd" in
  *curl*|*wget*)
    run_hook "$R/scoped/tooling/shell/check-curl-egress.sh" ;;
esac

# 8. phase 突入前の step タスク登録ゲート
case "$cmd" in
  *"update-flow-status.sh"*)
    run_hook "$R/always/gate/phase-step-task/check-phase-entry-tasks.sh" ;;
esac

# 9. dev サーバー起動時のポート割当検査（vite/next/uvicorn/prisma studio/http.server）
case "$cmd" in
  *vite*|*"next dev"*|*"next start"*|*uvicorn*|*"prisma studio"*|*"http.server"*)
    run_hook "$R/always/local-environment/port-management/check-port-launch.sh" ;;
esac

# 10. ~/Projects/ 配下 git commit 時の flow-values.yml 不在検知
case "$cmd" in
  *git*commit*)
    run_hook "$R/always/placement/flow-context-guard/check-flow-context-guard.sh" ;;
esac

exit 0
