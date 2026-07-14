// 観測・ログ フロー群。
export const OBSERVE_FLOWS = [
  {
    id: "skill-log",
    title: "スキル発火ログ",
    badge: "観測",
    summary: "PreToolUse(Skill) hook がスキル起動のたびに 1 行 JSONL を追記し、いつ・どのスキルが・どれだけ使われたかを後から集計可能にする。",
    trigger: "Skill ツールが実行される直前。PreToolUse(matcher=Skill) が毎回発火する。",
    relatedSkills: [],
    steps: [
      { n: 1, title: "発火", detail: "Skill 実行直前に skill-log-recorder.sh（timeout 5 秒）が呼ばれる。" },
      { n: 2, title: "抽出", detail: "入力 JSON から session_id と skill 名を jq で抽出する。" },
      { n: 3, title: "追記", detail: "~/agent-home/sessions/.skill-log/{session-id}.jsonl に {ts, skill} を 1 行追記する。" },
      { n: 4, title: "副作用", detail: "parallel-dev-worktree 発火時は実装セッションマーカー .impl-session-{id} を書き込む。" },
    ],
    diagram: "Skill 呼び出し → PreToolUse skill-log-recorder.sh → session_id+skill 抽出 → {ts,skill} を JSONL 追記",
    notes: [
      "集計は grep + sort + uniq でファイルを横断して回数を出せる。",
      "保存先: ~/agent-home/sessions/.skill-log/{session-id}.jsonl",
    ],
  },
  {
    id: "session-summary",
    title: "セッション要約",
    badge: "観測",
    summary: "/clear 実行時に SessionEnd hook が発火し、headless モードの別 claude プロセスがその回のセッションを Markdown で要約する。",
    trigger: "/clear 実行時（SessionEnd）。発動スキル一覧は skill-log を参照する。",
    relatedSkills: [],
    steps: [
      { n: 1, title: "SessionEnd 発火", detail: "/clear で SessionEnd hook が起動する（timeout 180 秒）。" },
      { n: 2, title: "headless 要約", detail: "別 claude プロセスがセッションを Markdown 要約する。" },
      { n: 3, title: "3 項目で構成", detail: "発動スキル一覧（回数付き）・主な決定事項・次回への引き継ぎ事項を書く。" },
      { n: 4, title: "保存", detail: "~/agent-home/sessions/YYYY-MM-DD/claude-code_{session-id}.md に保存する。" },
    ],
    diagram: "/clear → SessionEnd → headless claude 要約 → 3項目 Markdown → sessions/YYYY-MM-DD/ に保存",
    notes: [
      "失敗時は {session-id}.md.error にフォールバックする。",
      "再帰防止: CLAUDE_HOOK_SUMMARY_RUNNING=1 を先頭で検知して即 exit。",
    ],
  },
];
