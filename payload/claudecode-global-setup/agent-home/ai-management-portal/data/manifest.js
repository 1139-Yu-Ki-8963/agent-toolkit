// ドキュメントポータルの目次定義。
// agent-toolkit に実際に同梱しているコンテンツのみをカテゴリとして列挙する。
export const VISUAL_TOOL_GROUPS = [
  {
    id: "design",
    title: "設計ガイド",
    icon: "architecture",
    sub: "CLAUDE.md・rules・スキル・hook・サブエージェント・ループの設計ルール集",
    tools: [
      { id: "config-placement-design", title: "設定層 配置判定ガイド", description: "「どこに書くか」を決定木で判定する横断ガイド。7 層の使い分けを一枚で参照。", href: "design/config-placement.html", badge: "設計" },
      { id: "claude-md-design", title: "CLAUDE.md 設計ガイド", description: "ロードタイミング・サイズ制約・書く / 書かない判定フロー。", href: "design/claude-md.html", badge: "設計" },
      { id: "rules-design", title: "rules 設計ガイド", description: "eager / lazy 注入戦略・カテゴリ分類・hook script 同居原則。", href: "design/rules.html", badge: "設計" },
      { id: "skill-design", title: "Skill 設計ガイド", description: "スキルの定義・判定フロー・命名・フォルダ構造のルール集。", href: "design/skill.html", badge: "設計" },
      { id: "hooks-design", title: "Hooks 設計ガイド", description: "hook script の配置ルール。ownership×scope の 4 象限。", href: "design/hooks.html", badge: "設計" },
      { id: "subagent-design", title: "Subagent 設計ガイド", description: "カスタムサブエージェントの設計ルール集。", href: "design/subagent.html", badge: "設計" },
      { id: "loop-design", title: "Loop 設計ガイド", description: "繰り返し実行を設計する原則。5 アクション・6 パーツ・評価役の分離。", href: "design/loop.html", badge: "設計" },
    ],
  },
  {
    id: "registry",
    title: "一覧カタログ",
    icon: "list_alt",
    sub: "同梱スキルの実体一覧",
    tools: [
      { id: "skills-catalog", title: "スキル一覧", description: "同梱スキルをカテゴリ別に一覧化。絞り込み付きカタログ。", href: "catalog/skills.html", badge: "skills" },
    ],
  },
];
