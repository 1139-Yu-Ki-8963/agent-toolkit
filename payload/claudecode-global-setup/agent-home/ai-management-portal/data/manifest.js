// ドキュメントポータルの目次定義。
// agent-home の全フローをカテゴリ「フロー一覧」配下に列挙する。
// 各 tool の href "#/flow/<id>" は同タブ内部ルート（flow-detail.js が描画する）。
export const VISUAL_TOOL_GROUPS = [
  {
    id: "flow",
    title: "フロー一覧",
    icon: "bolt",
    sub: "実装・レビュー・運用・機械強制・文章品質・観測の各フロー",
    sections: [
      {
        id: "orchestration",
        title: "統合フロー",
        sub: "全開発フローを束ねる統合起点",
        toolIds: ["orchestrating-dev-flow"],
      },
      {
        id: "impl",
        title: "実装・PR",
        sub: "issue 着手から PR・マージまで",
        toolIds: [
          "managing-github-issues",
          "parallel-dev-worktree",
          "grouping-commits",
          "formatting-pr",
          "fixing-review-findings",
        ],
      },
      {
        id: "review",
        title: "レビュー",
        sub: "PR レビューと自動修正",
        toolIds: ["pr-review-workflow", "reviewing-prs"],
      },
      {
        id: "ops",
        title: "運用",
        sub: "手動起動の運用操作",
        toolIds: ["seed-deploy"],
      },
      {
        id: "write",
        title: "文章品質",
        sub: "textlint・曖昧表現・用語辞書",
        toolIds: ["adding-textlint-dictionary-terms"],
      },
      {
        id: "enforce",
        title: "機械強制（hook）",
        sub: "Edit/commit/push を hook が制御",
        toolIds: ["worktree-required", "no-delegation", "no-deferral", "author-guard"],
      },
      {
        id: "observe",
        title: "観測・ログ",
        sub: "スキル発火ログとセッション要約",
        toolIds: ["skill-log", "session-summary"],
      },
    ],
    tools: [
      // --- 統合フロー ---
      { id: "orchestrating-dev-flow", title: "orchestrating-dev-flow（統合実装フロー）", description: "5 ルート × 13 Phase の統合開発フロー", href: "#/flow/orchestrating-dev-flow", badge: "統合" },
      // --- 実装・PR ---
      { id: "managing-github-issues", title: "issue 選択 → 実装着手（pick モード）", description: "GitHub issue 一覧を表形式で表示し、番号選択から orchestrating-dev-flow を起動する。", href: "#/flow/managing-github-issues", badge: "起点" },
      { id: "parallel-dev-worktree", title: "worktree 開発フロー", description: "origin から worktree を切って実装し、PR 作成後に畳む。規模を問わず適用。", href: "#/flow/parallel-dev-worktree", badge: "実装" },
      { id: "grouping-commits", title: "コミット整形", description: "変更ファイルを目的別に分類し、単一目的のコミットを複数作成する。", href: "#/flow/grouping-commits", badge: "commit" },
      { id: "formatting-pr", title: "PR 本文整形", description: "PR テンプレートに厳密準拠した本文を組み立て、gh pr create する。", href: "#/flow/formatting-pr", badge: "PR" },
      { id: "fixing-review-findings", title: "レビュー指摘の自動修正", description: "レビューの警告・critical を worktree 内で修正し、再レビュー・自動マージまで進める。", href: "#/flow/fixing-review-findings", badge: "fix" },
      // --- レビュー ---
      { id: "pr-review-workflow", title: "複数 PR 一括レビュー", description: "open PR を選び、Reviewer と Fixer のサブエージェントを並列起動して LGTM まで完結する。", href: "#/flow/pr-review-workflow", badge: "一括" },
      { id: "reviewing-prs", title: "単一 PR レビュー", description: "差分確認・コメント投稿・インラインコメント・自動フルレビューを gh で実行する。", href: "#/flow/reviewing-prs", badge: "review" },
      // --- 運用 ---
      { id: "seed-deploy", title: "seed 即反映", description: "supabase/seeds 変更を worktree→commit→PR→マージ→db reset→再起動まで自走する。", href: "#/flow/seed-deploy", badge: "運用" },
      // --- 文章品質 ---
      { id: "writing-quality", title: "textlint 自動修正", description: "日本語長文の保存で textlint が発火し、text-dictionary/rule.md の違反時手順で違反を即修正する。", href: "#/flow/writing-quality", badge: "品質" },
      { id: "adding-textlint-dictionary-terms", title: "用語辞書の登録と置換", description: "カタカナ・英語バズワードを prh.yml に登録し、既存使用箇所を一括置換する。", href: "#/flow/adding-textlint-dictionary-terms", badge: "辞書" },
      // --- 機械強制（hook） ---
      { id: "worktree-required", title: "WORKTREE 強制", description: "worktree 未作成のままの編集を block し、parallel-dev-worktree の起動を促す。", href: "#/flow/worktree-required", badge: "hook" },
      { id: "no-delegation", title: "NO-DELEGATION 強制", description: "ユーザーへの操作依頼を禁止し、対話ログインは token 代替へ書き換えさせる。", href: "#/flow/no-delegation", badge: "hook" },
      { id: "no-deferral", title: "NO-DEFERRAL 強制", description: "「別 PR で対応」等の先送り表現を PR/issue/応答から排除する。", href: "#/flow/no-deferral", badge: "hook" },
      { id: "author-guard", title: "AUTHOR 強制", description: "commit/push の author を y__u 名義 1 件に限定し、逸脱を block する。", href: "#/flow/author-guard", badge: "hook" },
      // --- 観測・ログ ---
      { id: "skill-log", title: "スキル発火ログ", description: "PreToolUse(Skill) が発火のたびに JSONL を追記し、回数を集計可能にする。", href: "#/flow/skill-log", badge: "観測" },
      { id: "session-summary", title: "セッション要約", description: "SessionEnd で headless プロセスがセッションを Markdown 要約として残す。", href: "#/flow/session-summary", badge: "観測" },
    ],
  },
  {
    id: "design",
    title: "設計ガイド",
    icon: "architecture",
    sub: "CLAUDE.md・Rules・Skills・Subagents・Hooks・ループの設計ルール集",
    tools: [
      { id: "config-placement-design", title: "設定層 配置判定ガイド", description: "「どこに書くか」を 8 問の決定木で判定する横断ガイド。", href: "design/config-placement.html", badge: "設計" },
      { id: "claude-md-design", title: "CLAUDE.md 設計ガイド", description: "CLAUDE.md の方針とロードタイミング・サイズ制約のルール集。", href: "design/claude-md.html", badge: "設計" },
      { id: "rules-design", title: "Rules 設計ガイド", description: "~/.claude/rules/ の規約と eager/lazy 注入戦略。", href: "design/rules.html", badge: "設計" },
      { id: "skill-design", title: "Skills 設計ガイド", description: "スキルの定義・判定フロー・命名・フォルダ構造のルール集。", href: "design/skill.html", badge: "設計" },
      { id: "subagent-design", title: "Subagents 設計ガイド", description: "カスタムサブエージェントの設計ルール集。", href: "design/subagent.html", badge: "設計" },
      { id: "hooks-design", title: "Hooks 設計ガイド", description: "hook script の配置ルール。ownership×scope の 4 象限。", href: "design/hooks.html", badge: "設計" },
      { id: "output-style-design", title: "Output styles 設計ガイド", description: "システムプロンプトを丸ごと差し替える設定。配置場所・frontmatter 仕様・有効化手順。", href: "design/output-style.html", badge: "設計" },
      { id: "statusline-design", title: "Statusline 設計ガイド", description: "ステータス行を描画する statusline.py の入力仕様と実装構成。", href: "design/statusline.html", badge: "設計" },
      { id: "loop-design", title: "Loop 設計ガイド", description: "指示を自動繰り返しへ昇格させる設計原則。", href: "design/loop.html", badge: "設計" },
      { id: "worktree-design", title: "Worktree 運用設計ガイド", description: "git worktree の仕組み・必須化の設計判断・クリーンアップ・未決事項。", href: "design/worktree.html", badge: "設計" },
    ],
  },
  {
    id: "architecture",
    title: "仕組み解説",
    icon: "hub",
    sub: "複数の config 層・スキル・サブエージェントが繋がって1つの機構を成す仕組みの解説",
    tools: [
      { id: "review-architecture", title: "レビュー基盤 仕組み解説", description: "観点の正本（rules）・単一入口スキル・専門家サブエージェントの3層構造。", href: "architecture/review-architecture.html", badge: "仕組み" },
      { id: "tacit-knowledge-architecture", title: "計画暗黙知プローブ 仕組み解説", description: "弱モデル初見読解 × 二重ゲート hook で計画の省略前提を検出・明文化する仕組み。", href: "architecture/tacit-knowledge-architecture.html", badge: "仕組み" },
    ],
  },
  {
    id: "registry",
    title: "登録一覧",
    icon: "list_alt",
    sub: "Rules・Skills・Subagents・Hooks・Output styles・Routinesの実体一覧と利用統計",
    tools: [
      { id: "rules-catalog", title: "Rules 一覧", description: "全ルールをカテゴリ別に一覧化。機械強制タグ確認。", href: "catalog/rules.html", badge: "rules" },
      { id: "skills-catalog", title: "Skills 一覧", description: "全スキルをカテゴリ別に一覧化。絞り込み付きカタログ。", href: "catalog/skills.html", badge: "skills" },
      { id: "subagents-catalog", title: "Subagents 一覧", description: "カスタムサブエージェント定義をロール別に一覧化。", href: "catalog/subagents.html", badge: "agents" },
      { id: "hooks-catalog", title: "Hooks 一覧", description: "hooks を発火イベント別に一覧化。絞り込み付きカタログ。", href: "catalog/hooks.html", badge: "hooks" },
      { id: "output-styles-catalog", title: "Output styles 一覧", description: "配置済みの Output style ファイルをスコープ別に一覧化。", href: "catalog/output-styles.html", badge: "styles" },
      { id: "routines-catalog", title: "Routines 一覧", description: "routines/ 配下の定期実行ルーティンを一覧化。", href: "catalog/routines.html", badge: "routines" },
      { id: "usage-catalog", title: "スキル利用頻度", description: "skill-log の起動回数を集計し発火健全性を診断。", href: "catalog/usage.html", badge: "usage" },
      { id: "public-set-catalog", title: "公開セット台帳", description: "公開用リポジトリへ切り出す際の資産別同梱判定を一覧化。", href: "catalog/public-set.html", badge: "public" },
    ],
  },
  {
    id: "pc-config",
    title: "PC 設定",
    icon: "computer",
    sub: "ディレクトリ設計・ポート管理・worktree スロット・開発環境のマシン固有設定",
    tools: [
      { id: "pc-directory-design", title: "ディレクトリ設計ガイド", description: "~/（ホーム）と agent-home の全ディレクトリの責務・管理方針を 1 枚で把握する。", href: "design/pc-directory.html", badge: "構成" },
    ],
  },
  {
    id: "tools",
    title: "ツール設定",
    icon: "handyman",
    sub: "MCP ツール（Playwright 等）の出力先管理・設定ガイド",
    tools: [
      { id: "playwright-config", title: "Playwright 設定ガイド", description: "Playwright MCP の出力先集約・hook 強制・許可パスの設計と設定手順。", href: "design/playwright.html", badge: "MCP" },
    ],
  },
  {
    id: "claude-config",
    title: ".claude 設定",
    icon: "settings",
    sub: "~/.claude のアーキテクチャ・設定・ルール・動的データを俯瞰する",
    tools: [
      { id: "claude-architecture", title: "アーキテクチャ概要", description: ".claude の責務と agent-home との分担、静的・動的の二層構造を 1 枚で把握する。", href: "claude/architecture.html", badge: "概要" },
      { id: "claude-directory", title: "ディレクトリ構造", description: "直下 21 ディレクトリと主要ファイルの責務・寿命・参照元をツリーと早見表で整理する。", href: "claude/directory.html", badge: "構造" },
      { id: "claude-settings", title: "設定ファイル", description: "CLAUDE.md / settings.json / statusline.py / README.md の役割と主要セクションを一覧化する。", href: "claude/settings.html", badge: "設定" },
      { id: "claude-rules", title: "CLAUDE.md ルール一覧", description: "全プロジェクト共通の番号付き節（§1〜§18、16 節）を趣旨・発火条件・再帰防止の 3 軸で整理する。", href: "claude/rules.html", badge: "ルール" },
      { id: "claude-workflows", title: "機械強制ワークフロー", description: "hook が注入するタグと Claude の応答手順、代表ワークフロー（AUTO-COMMIT・FLOW-SELECT）を一覧化する。", href: "claude/workflows.html", badge: "hook" },
      { id: "claude-dynamic", title: "動的データ・状態", description: "ランタイムで成長するファイル群を寿命・保持目的・削除可否で分類する。gitignore 判定の材料として使う。", href: "claude/dynamic.html", badge: "状態" },
      { id: "claude-tooling", title: "設定すべきツール一覧", description: "CLAUDE.md・Rules・Skills・Subagents・Hooks・Output styles・Statusline など、設定・整備すべきツール群を横断的に一覧化する。", href: "claude/tooling.html", badge: "一覧" },
    ],
  },
  {
    id: "codex-config",
    title: ".codex 設定",
    icon: "build",
    sub: "~/.codex のアーキテクチャ・設定・hook（今後追加予定）",
    tools: [],
  },
];
