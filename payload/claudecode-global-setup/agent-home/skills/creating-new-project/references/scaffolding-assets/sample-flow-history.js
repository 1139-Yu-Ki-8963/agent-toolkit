export default [
  {
    id: 15,
    date: "2026-06-27",
    title: "ユーザープロフィール編集機能",
    route: "feature-with-full-planning",
    durationMin: 42,
    phases: [
      { phase: 1, name: "ルート判定", durationMin: 1, status: "done" },
      { phase: 2, name: "作業ブランチ準備", durationMin: 2, status: "done" },
      { phase: 3, name: "コンテキスト読み込み", durationMin: 1, status: "done" },
      { phase: 4, name: "構造分析", durationMin: 3, status: "done" },
      { phase: 5, name: "要件ヒアリング", durationMin: 8, status: "done" },
      { phase: 6, name: "仕様書（PRD）作成", durationMin: 5, status: "done" },
      { phase: 7, name: "実装・テスト計画", durationMin: 2, status: "done" },
      { phase: 8, name: "TDD サイクル", durationMin: 12, status: "done", loops: 4 },
      { phase: 9, name: "完了チェック", durationMin: 2, status: "done" },
      { phase: 10, name: "プッシュ前最終確認", durationMin: 2, status: "done" },
      { phase: 11, name: "PR 作成・マージ", durationMin: 3, status: "done" },
      { phase: 12, name: "マージ後片付け", durationMin: 1, status: "done" },
      { phase: 13, name: "メイン同期・自己改善", durationMin: 1, status: "done" }
    ]
  },
  {
    id: 14,
    date: "2026-06-26",
    title: "経費精算フォーム",
    route: "feature-with-full-planning",
    durationMin: 55,
    phases: [
      { phase: 1, name: "ルート判定", durationMin: 1, status: "done" },
      { phase: 2, name: "作業ブランチ準備", durationMin: 2, status: "done" },
      { phase: 3, name: "コンテキスト読み込み", durationMin: 1, status: "done" },
      { phase: 4, name: "構造分析", durationMin: 5, status: "done" },
      { phase: 5, name: "要件ヒアリング", durationMin: 12, status: "done" },
      { phase: 6, name: "仕様書（PRD）作成", durationMin: 6, status: "done" },
      { phase: 7, name: "実装・テスト計画", durationMin: 3, status: "done" },
      { phase: 8, name: "TDD サイクル", durationMin: 15, status: "done", loops: 6 },
      { phase: 9, name: "完了チェック", durationMin: 3, status: "done" },
      { phase: 10, name: "プッシュ前最終確認", durationMin: 2, status: "done" },
      { phase: 11, name: "PR 作成・マージ", durationMin: 3, status: "done" },
      { phase: 12, name: "マージ後片付け", durationMin: 1, status: "done" },
      { phase: 13, name: "メイン同期・自己改善", durationMin: 1, status: "done" }
    ]
  },
  {
    id: 13,
    date: "2026-06-25",
    title: "DB インデックス追加",
    route: "refactor-with-safety-guarantee",
    durationMin: 28,
    phases: [
      { phase: 1, name: "ルート判定", durationMin: 1, status: "done" },
      { phase: 2, name: "作業ブランチ準備", durationMin: 2, status: "done" },
      { phase: 3, name: "コンテキスト読み込み", durationMin: 1, status: "done" },
      { phase: 4, name: "構造分析", durationMin: 4, status: "done" },
      { phase: 7, name: "実装・テスト計画", durationMin: 3, status: "done" },
      { phase: 8, name: "TDD サイクル", durationMin: 0, status: "skipped" },
      { phase: 9, name: "完了チェック", durationMin: 5, status: "done", note: "lint 修正で 2 回ループ" },
      { phase: 10, name: "プッシュ前最終確認", durationMin: 2, status: "done" },
      { phase: 11, name: "PR 作成・マージ", durationMin: 8, status: "done", note: "CI 失敗で再 push" },
      { phase: 12, name: "マージ後片付け", durationMin: 1, status: "done" },
      { phase: 13, name: "メイン同期・自己改善", durationMin: 1, status: "done" }
    ]
  },
  {
    id: 12,
    date: "2026-06-24",
    title: "README 更新",
    route: "config-with-review-and-verify",
    durationMin: 12,
    phases: [
      { phase: 1, name: "ルート判定", durationMin: 1, status: "done" },
      { phase: 2, name: "作業ブランチ準備", durationMin: 1, status: "done" },
      { phase: "D", name: "ドキュメント編集", durationMin: 5, status: "done" },
      { phase: 9, name: "完了チェック", durationMin: 1, status: "done" },
      { phase: 10, name: "プッシュ前最終確認", durationMin: 1, status: "done" },
      { phase: 11, name: "PR 作成・マージ", durationMin: 2, status: "done" },
      { phase: 12, name: "マージ後片付け", durationMin: 1, status: "done" },
      { phase: 13, name: "メイン同期・自己改善", durationMin: 0, status: "done" }
    ]
  }
];
