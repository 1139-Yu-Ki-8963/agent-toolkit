// スキル利用頻度のスナップショット（Skill ツール起動回数）。
// 集計元: ~/agent-home/sessions/.skill-log/*.jsonl（全期間 2026-04-29〜06-02, 起動 1855 件）
// 再生成（回数・最終日）:
//   cat ~/agent-home/sessions/.skill-log/*.jsonl | jq -rs 'group_by(.skill)|map({s:.[0].skill,n:length,last:(map(.ts)|max)[0:10]})|sort_by(-.n)|.[]|"\(.n)\t\(.last)\t\(.s)"'
//
// 重要: skill-log は「Skill ツール経由の起動」のみを記録する。0 回 = 不要ではない。
//   hook / CLAUDE.md / cron / 上位スキルから間接起動される場合はカウントされない。
//   そのため診断(diag)は回数だけでなく間接起動・上位代替・トリガー健全性を加味している。
// 注意: skill-log は skill 名のみを残し「どの場所のスキルが発火したか」を区別しない。
//   同名スキルがプロジェクト側 (.claude/skills) にもある場合は project が優先発火するため、
//   grouping-commits / parallel-dev-worktree 等の回数は agent-home 版の実利用を過大評価している可能性がある。
//   （重複していた formatting-pr は agent-home から削除済み。project 版が正本）
//
// diag: keep=維持 / improve=発火改善（呼ばれるべきが呼ばれていない） / merge=統合検討
// snapshot 日: 2026-06-02

export const USAGE_SNAPSHOT = "2026-06-02";

export const SKILL_USAGE = [
  // ── 維持（高頻度・実使用） ──
  { id: "reviewing-prs", n: 481, last: "2026-06-02", diag: "keep" },
  { id: "grouping-commits", n: 178, last: "2026-06-02", diag: "keep" },
  { id: "dev-launch", n: 154, last: "2026-06-02", diag: "keep" },
  { id: "parallel-dev-worktree", n: 82, last: "2026-05-31", diag: "keep" },
  { id: "test-e2e", n: 31, last: "2026-05-31", diag: "keep" },
  { id: "formatting-issue", n: 16, last: "2026-05-25", diag: "keep" },
  { id: "seed-deploy", n: 16, last: "2026-05-23", diag: "keep" },
  { id: "frontend-design", n: 11, last: "2026-05-19", diag: "keep" },
  { id: "managing-hooks", n: 10, last: "2026-06-16", diag: "keep", why: "旧 creating-hooks / reviewing-hooks-config / diagnose-hooks / testing-hooks を統合したライフサイクル管理ハブ" },
  { id: "managing-skills", n: 7, last: "2026-06-16", diag: "keep", why: "旧 creating-custom-skills / reviewing-skills / testing-skills を統合したライフサイクル管理ハブ" },
  { id: "adding-textlint-dictionary-terms", n: 4, last: "2026-06-02", diag: "keep", why: "textlint hook と text-dictionary/rule.md でルールとして常時適用（Skill 起動を経ない。違反修正は同 rule.md が完結する）" },
  { id: "supabase-postgres", n: 3, last: "2026-05-08", diag: "keep" },
  { id: "pr-review-workflow", n: 3, last: "2026-05-16", diag: "keep" },
  { id: "supabase", n: 2, last: "2026-05-08", diag: "keep" },

  // ── 維持（0〜1 回だが hook / CLAUDE / cron で間接起動。カウント過少） ──
  { id: "reviewing-public-readiness", n: 4, last: "2026-05-23", diag: "keep", why: "PUBLISH-SAFETY hook 経由で起動" },
  { id: "managing-github-issues", n: 4, last: "2026-05-17", diag: "keep", why: "旧 creating-issue / picking-issues / verifying-issue-scope を統合。FLOW-SELECT hook / CLAUDE.md の実装フロー入口、issue-N ブランチのコミット前フローで起動" },
  { id: "naming-conventions", n: 1, last: "2026-05-29", diag: "keep", why: "commit/ファイル作成時に NAMING hook とルールで常時適用" },
  { id: "asking-users", n: 1, last: "2026-05-29", diag: "keep", why: "確認・選択肢提示の基盤スキル" },
  { id: "coverage-watchdog", n: 0, last: "-", diag: "keep", why: "cron（週次）起動。Skill ツールを経ない" },
  { id: "daily-screen-health", n: 0, last: "-", diag: "keep", why: "cron（毎日）起動。Skill ツールを経ない" },
  { id: "weekly-clock-skew", n: 0, last: "-", diag: "keep", why: "cron（週次）起動。Skill ツールを経ない" },

  // ── 発火改善（呼ばれるべきが呼ばれていない＝トリガー不全 / 上位スキルが代替） ──
  // Render パック: 本番 backend は Render 使用中（render.yaml / *.onrender.com）だが、
  // <project>-deploy-production が一括代替し、通常反映は git push 自動デプロイのため汎用 render-* が発火しない。
  { id: "render-cli", n: 2, last: "2026-05-29", diag: "improve", why: "本番は Render 利用中。<project>-deploy-production と git push 自動デプロイが代替し汎用が出番なし" },
  { id: "render-deploy", n: 0, last: "-", diag: "improve", why: "同上。境界（汎用=Render 単体操作 / 一括=上位スキル）が未整備" },
  { id: "render-blueprints", n: 0, last: "-", diag: "improve", why: "render.yaml 編集時に発火すべきがトリガー未整備" },
  { id: "render-web-services", n: 0, last: "-", diag: "improve", why: "Render backend 運用時に出番があるが発火せず" },
  { id: "render-static-sites", n: 0, last: "-", diag: "improve", why: "frontend は Vercel のため出番が少ない" },
  { id: "render-background-workers", n: 0, last: "-", diag: "improve" },
  { id: "render-cron-jobs", n: 0, last: "-", diag: "improve" },
  { id: "render-private-services", n: 0, last: "-", diag: "improve" },
  { id: "render-workflows", n: 0, last: "-", diag: "improve" },
  { id: "render-postgres", n: 0, last: "-", diag: "improve", why: "DB は Supabase のため出番が少ない" },
  { id: "render-keyvalue", n: 0, last: "-", diag: "improve" },
  { id: "render-disks", n: 0, last: "-", diag: "improve" },
  { id: "render-domains", n: 0, last: "-", diag: "improve" },
  { id: "render-env-vars", n: 0, last: "-", diag: "improve", why: "Render backend の環境変数設定時に発火すべき" },
  { id: "render-networking", n: 0, last: "-", diag: "improve" },
  { id: "render-scaling", n: 0, last: "-", diag: "improve" },
  { id: "render-docker", n: 0, last: "-", diag: "improve" },
  { id: "render-debug", n: 0, last: "-", diag: "improve", why: "Render デプロイ失敗時に発火すべきがトリガー未整備" },
  { id: "render-monitor", n: 0, last: "-", diag: "improve" },
  { id: "render-mcp", n: 0, last: "-", diag: "improve" },
  { id: "render-migrate-from-heroku", n: 0, last: "-", diag: "improve", why: "Heroku 移行は完了済みのため出番なし（保管）" },
  // 非 Render の発火改善
  { id: "syncing-design-system", n: 0, last: "-", diag: "improve", why: "Design API→React 差分反映。発火機会が稀でトリガーも曖昧" },
  { id: "documenting-workflows", n: 0, last: "-", diag: "improve", why: "関連スキル 2 つ以上追加時に発火すべき。managing-skills への吸収も検討" },
];
