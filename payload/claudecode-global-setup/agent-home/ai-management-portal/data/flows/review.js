// レビュー フロー群。
export const REVIEW_FLOWS = [
  {
    id: "pr-review-workflow",
    title: "複数 PR 一括レビュー",
    badge: "一括",
    summary: "open PR 一覧から対象を選び、Reviewer（reviewing-prs）と Fixer（fixing-review-findings）のサブエージェントを並列起動して、レビュー→警告自動修正→LGTM 投稿まで完結するオーケストレーター。",
    trigger: "「PR を全部レビューして」「まとめてレビューして」「全 PR を LGTM まで処理して」など、複数 PR のレビューと自動修正を一括で行いたいとき。PR が 1 つで手動レビューのみなら reviewing-prs を直接使う。",
    relatedSkills: ["pr-review-workflow", "reviewing-prs", "module-fixing-review-findings"],
    steps: [
      { n: 1, title: "PR 一覧取得", detail: "open PR を一覧し、処理対象を選ぶ。", skill: "pr-review-workflow" },
      { n: 2, title: "Reviewer 並列起動", detail: "PR ごとに reviewing-prs サブエージェントを並列起動する。", skill: "reviewing-prs" },
      { n: 3, title: "結果で分岐", detail: "重大問題あり→request-changes / 警告あり→Fixer 起動 / 問題なし→即 approve。", skill: "module-fixing-review-findings" },
      { n: 4, title: "結果報告", detail: "全 PR の最終結果を表形式で報告する。" },
    ],
    diagram: "PR一覧 → Reviewer×N 並列 → [critical→request / warn→Fixer / clean→approve] → 表で結果報告",
    notes: [
      "複数 PR を同時に処理できる。サブエージェントで並列度を上げる。",
    ],
  },
  {
    id: "reviewing-prs",
    title: "単一 PR レビュー",
    badge: "review",
    summary: "PR 情報取得・行番号付き差分確認・コメント投稿・インラインコメント・返信を gh で実行する。worktree にブランチを持ち込み、AI レビュー・テスト実行・LGTM 投稿まで行う自動フルレビューも提供。",
    trigger: "「PR を見て」「レビューして」「コメントして」「差分を確認」「自動レビュー」「LGTM を出して」など。PR を伴わないローカル編集のみのときはスキップ。",
    relatedSkills: ["reviewing-prs", "module-fixing-review-findings", "pr-review-workflow"],
    steps: [
      { n: 1, title: "PR 情報取得", detail: "gh で PR の概要・差分・既存コメントを取得する。", skill: "reviewing-prs" },
      { n: 2, title: "差分レビュー", detail: "行番号付きで差分を確認し、観点ごとに指摘を整理する。" },
      { n: 3, title: "worktree 持ち込み（フル時）", detail: "ブランチを worktree に持ち込み、テストを実行する。" },
      { n: 4, title: "コメント投稿", detail: "インラインコメント・返信を投稿、または LGTM を出す。" },
    ],
    diagram: "PR取得 → 差分レビュー（行番号付き）→ [フル: worktree+test] → コメント/LGTM 投稿",
    notes: [
      "警告の自動修正は fixing-review-findings に委ねる。",
    ],
  },
];
