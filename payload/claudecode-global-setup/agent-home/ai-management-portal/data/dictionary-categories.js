// 置き換え辞書（prh.yml）のカテゴリ定義。
// このファイルだけが手動保守対象。辞書一覧の本体（DICTIONARIES 配列）は
// skills/managing-agent-configs/scripts/manage-portal.mjs の generate が
// ~/.claude/rules/always/review-checklist/text-dictionary/prh.yml（グローバル）と
// 各プロジェクトの prh.yml（committed 分）から自動生成する。
//
// 新しいカテゴリを prh.yml に追加したら、ここにも `{ id, name, desc }` を追記する。
// 未登録カテゴリは verify の「辞書-整合」観点で検出される。

export const CATEGORIES = [
  { id: "katakana-business", name: "カタカナ語の平易化", desc: "英語ビジネス用語のカタカナ音写を平易な日本語へ置き換える" },
  { id: "abbreviations", name: "英字略語の日本語化", desc: "KPI・ADR 等の英字略語を意味の伝わる日本語にする" },
  { id: "loanword-metaphor", name: "比喩・直訳の是正", desc: "分野外の借用語・不自然な直訳を自然な日本語に直す" },
  { id: "claude-ci-terms", name: "Claude Code・CI 用語の統一", desc: "hook・CI の検査類を「確認」系の呼称に統一する" },
  { id: "notation", name: "記法規約", desc: "番号・優先度の書き方（P0 禁止・ステップは 1 始まりの整数）" },
  { id: "official-names", name: "環境・プロジェクト固有の正式名称", desc: "この環境・各プロジェクトの正式名称に統一する（プロジェクト辞書含む）" },
];
