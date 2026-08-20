// 運用フロー群（手動起動の運用操作）。
// クラウド自動ルーティンは routines.js に移動済み。
export const OPS_FLOWS = [
  {
    id: "seed-deploy",
    title: "seed 即反映",
    badge: "運用",
    summary: "ローカルの supabase/seeds/*.sql 更新後、worktree→commit→push→PR 作成→マージ→git pull→supabase db reset→アプリ再起動までを自動実行する（<project>-<project> 専用）。",
    trigger: "「seed を反映して」「seed を更新した」「マージまでして」と言われ、supabase/seeds/*.sql に未コミット変更があるとき。seed 以外のコードも変更されている場合は parallel-dev-worktree を使う。",
    relatedSkills: ["seed-deploy", "parallel-dev-worktree", "grouping-commits", "formatting-pr"],
    steps: [
      { n: 1, title: "worktree 作成", detail: "seed 変更を隔離する worktree を切る。", skill: "seed-deploy" },
      { n: 2, title: "commit + push", detail: "seed ファイルをコミットして push する。", skill: "grouping-commits" },
      { n: 3, title: "PR 作成 + マージ", detail: "PR を作成しマージまで進める。", skill: "formatting-pr" },
      { n: 4, title: "DB リセット", detail: "git pull 後に supabase db reset で seed を反映する。" },
      { n: 5, title: "アプリ再起動", detail: "ローカル開発アプリを再起動して反映を確認する。" },
    ],
    diagram: "worktree → commit → push → PR → マージ → git pull → supabase db reset → アプリ再起動",
    notes: [
      "seed ファイルに変更がない、または DB リセットのみ求められたときはスキップ。",
    ],
  },
];
