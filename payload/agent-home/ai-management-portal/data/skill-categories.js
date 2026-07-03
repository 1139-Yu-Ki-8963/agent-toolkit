// スキル一覧のカテゴリ定義とスキル→カテゴリ対応表。
// agent-toolkit に実際に同梱されているスキルのみを対象とする。
// 新しいスキルを skills/ に追加したら、ここにも追記する。

// カテゴリ定義(表示順)。
export const CATEGORIES = [
  { id: "manage", name: "スキル・フック管理", desc: "skill / hook / rule / routine / subagent の作成・テスト・診断・レビュー" },
  { id: "dev", name: "テスト・起動", desc: "ローカル起動と環境検証" },
];

// スキル id → カテゴリ対応。値は文字列（cat のみ）か { cat, sub } オブジェクト。
export const SKILL_CATEGORY = {
  "managing-agent-configs": { cat: "manage", sub: "skill" },
  "syncing-reverse-env": "dev",
  "rebuilding-code-from-docs": "dev",
  "rebuilding-screen-unit-from-docs": "dev",
  "generating-screen-list-for-reverse-docs": "dev",
};
