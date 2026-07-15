export default [
  {
    id: 15,
    date: "2026-06-27",
    title: "ユーザープロフィール編集機能",
    route: "feature-with-full-planning",
    gates: [
      {
        name: "pre-impl",
        result: "PASS",
        findings: []
      },
      {
        name: "impl-quality",
        result: "FAIL",
        retries: 1,
        findings: [
          { severity: "CRITICAL", message: "認証チェック漏れ: PATCH /api/users/:id に認可ガードがない", resolved: true }
        ]
      },
      {
        name: "pre-push",
        result: "PASS",
        findings: [
          { severity: "INFO", message: "テストカバレッジが前回比 -2%（78% → 76%）", resolved: false }
        ]
      }
    ]
  },
  {
    id: 14,
    date: "2026-06-26",
    title: "経費精算フォーム",
    route: "feature-with-full-planning",
    gates: [
      { name: "pre-impl", result: "PASS", findings: [] },
      { name: "impl-quality", result: "PASS", findings: [] },
      {
        name: "pre-push",
        result: "FAIL",
        retries: 2,
        findings: [
          { severity: "CRITICAL", message: "XSS 脆弱性: ユーザー入力が未サニタイズで innerHTML に挿入", resolved: true },
          { severity: "WARN", message: "未使用の import が 3 件残存", resolved: true }
        ]
      }
    ]
  },
  {
    id: 13,
    date: "2026-06-25",
    title: "DB インデックス追加",
    route: "refactor-with-safety-guarantee",
    gates: [
      { name: "impl-quality", result: "PASS", findings: [] },
      { name: "pre-push", result: "PASS", findings: [] }
    ]
  }
];
