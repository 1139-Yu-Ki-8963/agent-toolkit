// スキル一覧のカテゴリ定義とスキル→カテゴリ対応表。
// このファイルだけが手動保守対象。スキル一覧の本体（SKILLS 配列）は
// scripts/generate-catalog.mjs が ~/agent-home/skills/*/SKILL.md から自動生成する。
//
// 新しいスキルを追加したら、ここに `"<id>": "<cat>"`（サブカテゴリがあれば
// `{ cat: "<cat>", sub: "<sub>" }`）を追記してから再生成する。
// 未登録のスキルは自動生成時に cat: "other" 扱いとなり、警告が出る。
// スキルを削除しても、この対応表からは自動で消えない。生成時に
// 「map に残っているが実体がない」警告が出るので、そのタイミングで手で消す。

// カテゴリ定義(表示順)。subs を持つカテゴリは内部を小カテゴリに分割する。
export const CATEGORIES = [
  { id: "impl",   name: "実装・PR",            desc: "issue 着手からコミット・PR まで",
    subs: [
      { key: "issue", label: "issue 起票・選択", tag: "tag-post" },
      { key: "pr",    label: "実装・コミット・PR", tag: "tag-skill" },
    ] },
  { id: "review", name: "レビュー・公開",      desc: "PR レビューと公開可否チェック" },
  { id: "write",  name: "文章品質",            desc: "textlint・曖昧表現・用語辞書" },
  { id: "manage", name: "スキル・フック管理",  desc: "skill / hook の作成・テスト・診断・レビュー・文書化",
    subs: [
      { key: "hook",  label: "hooks 向け",  tag: "tag-pre" },
      { key: "skill", label: "skills 向け", tag: "tag-skill" },
    ] },
  { id: "meta",   name: "規約・補助",          desc: "命名規則・ルーティン登録・ユーザー確認" },
  { id: "design", name: "デザイン・フロント",  desc: "UI 構築とデザインシステム" },
  { id: "dev",    name: "テスト・起動",        desc: "ローカル起動と E2E" },
  { id: "routine",name: "ルーティン",          desc: "cron で定期実行する監視" },
];

// スキル id → カテゴリ対応。値は文字列（cat のみ）か { cat, sub } オブジェクト。
export const SKILL_CATEGORY = {
  "managing-github-issues": { cat: "impl", sub: "issue" },
  "orchestrating-dev-flow": { cat: "impl", sub: "pr" },
  "parallel-dev-worktree": { cat: "impl", sub: "pr" },
  "grouping-commits": { cat: "impl", sub: "pr" },
  "creating-new-project": "dev",
  "reviewing-single-pr-with-inline-comments": "review",
  "reviewing-public-readiness": "review",
  "reviewing-against-rules": "review",
  "adding-textlint-dictionary-terms": "write",
  "managing-agent-configs": { cat: "manage", sub: "skill" },
  "grading-claude-code-project": { cat: "manage", sub: "skill" },
  "eliciting-plan-tacit-knowledge": "meta",
  "subagent-investigation-checklist": "meta",
  "frontend-design": "design",
};
