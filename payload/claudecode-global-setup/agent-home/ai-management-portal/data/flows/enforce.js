// 機械強制（hook）フロー群。CLAUDE.md の各節と tools/hooks/*.sh に対応する。
export const ENFORCE_FLOWS = [
  {
    id: "worktree-required",
    title: "WORKTREE 強制",
    badge: "hook",
    summary: "worktree が未作成のままの Write/Edit/NotebookEdit を block し、parallel-dev-worktree の Phase 1〜3 起動を促す。",
    trigger: "PreToolUse が [WORKTREE-REQUIRED] を注入したとき。",
    relatedSkills: ["parallel-dev-worktree"],
    steps: [
      { n: 1, title: "ガード", detail: "メイン作業ツリーでの編集を検出して block する。" },
      { n: 2, title: "worktree 作成", detail: "parallel-dev-worktree の Phase 1〜3 で worktree を作る。", skill: "parallel-dev-worktree" },
      { n: 3, title: "移動して再試行", detail: "cd \"$WT\" で worktree に移動してから編集を再試行する。" },
    ],
    diagram: "編集検出 → [WORKTREE-REQUIRED] block → worktree 作成 → cd $WT → 編集再試行",
    notes: [
      "例外パス: ~/.claude/* ~/agent-home/* と git 管理外パス。",
      "ユーザーが「main で直接」と明示したら touch /tmp/.allow-main-edit（ワンショット消費）。",
    ],
  },
  {
    id: "no-delegation",
    title: "NO-DELEGATION 強制",
    badge: "hook",
    summary: "ユーザーへの操作依頼を全面禁止する。対話必須コマンドは deny、依頼文は書き直しを強制し、ログインは token ベース代替へ誘導する。",
    trigger: "最終応答や PR/issue 本文に依頼文（「〜してください」等）、または対話ログイン（gh auth login 等）が含まれるとき。",
    relatedSkills: [],
    steps: [
      { n: 1, title: "deny", detail: "permissions.deny が対話必須コマンドを実行前に拒否する。" },
      { n: 2, title: "PreToolUse 検出", detail: "check-no-delegation-pre-bash.sh が [NO-DELEGATION-BLOCK] で exit 2 する。" },
      { n: 3, title: "書き直し", detail: "依頼文を削除し、Claude 自身のツールで完遂する応答へ差し替える。" },
      { n: 4, title: "代替不能なら中止", detail: "[NO-DELEGATION-ABORT] フォーマットで事実報告する。" },
    ],
    diagram: "deny → PreToolUse [NO-DELEGATION-BLOCK] → 依頼文削除 → token 代替で完遂 / [NO-DELEGATION-ABORT]",
    notes: [
      "本番接続は PROD-SKILL-READ により <project>-deploy-production 必読を強制する。",
      "同 hook が 2 連続発火したら 3 回目の書き直しをせず事実報告する。",
    ],
  },
  {
    id: "no-deferral",
    title: "NO-DEFERRAL 強制",
    badge: "hook",
    summary: "「別 PR で対応」「残課題」「今後対応」等の先送り表現を PR/issue/コメント/最終応答から全面排除する。例外脱出口はない。",
    trigger: "gh pr/issue create/comment 発行時、Write/Edit 保存時、最終応答時に先送り句を検出したとき。",
    relatedSkills: [],
    steps: [
      { n: 1, title: "PreToolUse", detail: "[NO-DEFERRAL-BLOCK] で gh pr/issue 操作を exit 2 する。" },
      { n: 2, title: "PostToolUse", detail: "Write/Edit は成功させ、[NO-DEFERRAL] で次ターンへ警告する。" },
      { n: 3, title: "Stop", detail: "[NO-DEFERRAL-RESPONSE] で最終応答を decision:block で書き直す。" },
      { n: 4, title: "本ターンで完遂", detail: "禁止句を削除し、当該作業を本ターン内で完遂する。" },
    ],
    diagram: "先送り句検出 → [NO-DEFERRAL-BLOCK/RESPONSE] → 禁止句削除 → 本ターンで完遂",
    notes: [
      "唯一の除外: PR テンプレの「未実施・残課題」が「- なし」等の空白既定のみ。",
      "「別 PR / 別 issue に分割」の選択肢は提示しない。",
    ],
  },
  {
    id: "author-guard",
    title: "AUTHOR 強制",
    badge: "hook",
    summary: "commit/push の author を y__u 名義 1 件のみに限定する。PreToolUse hook と husky pre-push が二重に block する。",
    trigger: "commit 前に [GIT-AUTHOR-BLOCK]、push 前に [GIT-AUTHOR-PUSH-BLOCK] が注入されたとき。",
    relatedSkills: [],
    steps: [
      { n: 1, title: "commit 前検査", detail: "[GIT-AUTHOR-BLOCK] 時は ~/.gitconfig の [user] を y__u に直してから再実行する。" },
      { n: 2, title: "push 前検査", detail: "[GIT-AUTHOR-PUSH-BLOCK] 時は rebase --reset-author で author を書き換えてから再 push する。" },
    ],
    diagram: "commit → [GIT-AUTHOR-BLOCK] gitconfig 修正 / push → [GIT-AUTHOR-PUSH-BLOCK] rebase --reset-author → 再 push",
    notes: [
      "許可: name=y__u / email=y__u@users.noreply.github.com の 1 組のみ。",
      "--no-verify による bypass、GIT_AUTHOR_* の export、-c user.email のワンショット指定は禁止。",
    ],
  },
];
