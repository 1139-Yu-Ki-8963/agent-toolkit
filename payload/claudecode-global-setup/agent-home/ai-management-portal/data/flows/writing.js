// 文章品質 フロー群。
export const WRITING_FLOWS = [
  {
    id: "writing-quality",
    title: "textlint 自動修正",
    badge: "品質",
    summary: "日本語長文の保存で PostToolUse の textlint が発火し、置き換え辞書規約（text-dictionary/rule.md）の違反時手順に従って違反を即修正する。",
    trigger: "日本語の長文（記事・ドキュメント・プランファイル）を書くとき、または [TEXTLINT] が additionalContext に注入されたとき。英語のみ・コードのみ・1〜2 文の返答はスキップ。",
    relatedSkills: [],
    steps: [
      { n: 1, title: ".md 保存", detail: "Write/Edit で日本語ドキュメントを保存する。" },
      { n: 2, title: "textlint 発火", detail: "PostToolUse hook が textlint を実行する。" },
      { n: 3, title: "違反注入", detail: "違反があれば [TEXTLINT]、gh 操作前なら [TEXTLINT-BLOCK] を注入する。" },
      { n: 4, title: "即修正", detail: "hook が注入する `~/.claude/rules/always/review-checklist/text-dictionary/rule.md` の違反時手順に従い、rules 側の指示通りに Edit 修正する（スキル呼び出し不要）。" },
    ],
    diagram: ".md 保存 → PostToolUse textlint → [TEXTLINT] 注入 → 該当ルールで即修正 → [TEXTLINT-CLEAN]",
    notes: [
      "[TEXTLINT-CLEAN] 注入は違反解消を意味する。次の作業へ即進む。",
      "[TEXTLINT-STALE] は廃止済み。違反が残っても停止せず可能な範囲で進める。",
    ],
  },
  {
    id: "adding-textlint-dictionary-terms",
    title: "用語辞書の登録と置換",
    badge: "辞書",
    summary: "カタカナビジネス用語・英語バズワードを置き換え辞書（tools/linter/prh.yml）に登録し、リポジトリ内の既存使用箇所も一括で整合させる。",
    trigger: "「<語>を置き換え辞書に登録」「prh.yml に追加」「平易な日本語に置換したい」と言われたとき。技術略語（API・JSON・SDK 等）は対象外。",
    relatedSkills: ["adding-textlint-dictionary-terms"],
    steps: [
      { n: 1, title: "重複確認", detail: "prh.yml に既存エントリがないか確認する。", skill: "adding-textlint-dictionary-terms" },
      { n: 2, title: "辞書登録", detail: "prh.yml の末尾に置き換えエントリを追加する。" },
      { n: 3, title: "既存箇所の置換", detail: "リポジトリ内の既存使用箇所を Edit で一括置換する。" },
    ],
    diagram: "重複確認 → prh.yml へ追加 → 既存使用箇所を一括置換",
    notes: [],
  },
];
