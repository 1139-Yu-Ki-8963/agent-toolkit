# claude-code-template

チーム共有の Claude Code 設定テンプレート。任意のプロジェクトにコピーして導入し、`/adapt` コマンドでプロジェクトに自己適応させる。

## 設計方針

- **入口は標準コマンドを正とする**: 独自コマンドは `/adapt` と `/safe-commit` の 2 つだけ
- **規範は `.claude/rules/` に一元化**: CLAUDE.md には事実、rules には規範を書く
- **hooks は Node.js 実装**: Windows / macOS / Linux で同一動作。`node:` ビルトインのみ
- **既定配線は最小 2 本**: 危険操作ガードと未適応検知のみ。他 6 本は未配線で同梱
- **ガードは fail-open**: エラー時は素通し。主防衛線は `permissions.deny`
- **deny は誤検知ゼロ級のみ**: 確実に事故となる操作だけを自動拒否

## 前提条件

- Node.js 18 以上（hooks 実行に必須）
- Claude Code v2.1.198 以上を推奨

## 導入手順

```
テンプレ置き場 [A]          導入先プロジェクト [B]
claude-code-template/       your-project/
├── init.mjs ─────────────→ (コピーされない)
├── CLAUDE.md ────────────→ CLAUDE.md
├── .gitattributes ───────→ .gitattributes
├── .claude/ ─────────────→ .claude/
│   ├── hooks/                ├── hooks/
│   ├── rules/                ├── rules/
│   ├── skills/               ├── skills/
│   └── ...                   └── ...
└── README.md ────────────→ (コピーされない)
```

```bash
node <テンプレ置き場>/init.mjs <導入先>
```

- 既存ファイルは上書きしない（冪等・非破壊）
- 内容が異なるファイルは `.template-new` を並置して報告する
- `.gitignore` は不足行のみ末尾に追記する

## 導入後の手順（代表者 1 回）

1. 導入されたファイルを `git commit` する
2. `/adapt` を実行してプロジェクトに適応させる
3. 適応結果を `git commit` する

## 構成ツリー

```
.claude/
├── README.md                 # 運用マニュアル
├── TEMPLATE_VERSION          # テンプレ版数
├── settings.json             # permissions + hooks 配線
├── rules/                    # 作業規範（番号帯で分類）
│   ├── 00-global.md          #   全体規範（常時適用）
│   ├── 10-frontend.md        #   フロントエンド（paths 条件）
│   ├── 20-backend.md         #   バックエンド（paths 条件）
│   ├── 30-security.md        #   セキュリティ（常時適用）
│   ├── 40-testing.md         #   テスト（paths 条件）
│   ├── 50-database.md        #   データベース（paths 条件）
│   └── 90-infra.md           #   インフラ（paths 条件）
├── skills/
│   ├── adapt/SKILL.md        # /adapt — プロジェクト適応
│   └── safe-commit/SKILL.md  # /safe-commit — 確認つきコミット
└── hooks/
    ├── pre-tool-use.mjs      # [配線済] 危険操作ガード
    ├── session-start.mjs     # [配線済] 未適応検知
    ├── lib/common.mjs        # 共通ライブラリ
    ├── lib/check-adapt.mjs   # /adapt 完了判定 CLI
    ├── optional/             # [未配線] 6 本
    └── tests/guard.test.mjs  # テストスイート
```

## 更新の配布

テンプレ管理層（hooks・skills/adapt・skills/safe-commit・.claude/README.md・TEMPLATE_VERSION）は `--update` フラグで上書き更新できる:

```bash
node <テンプレ置き場>/init.mjs --update <導入先>
```

プロジェクト所有層（CLAUDE.md・rules・settings.json）は上書きしない。

## テンプレ自体の開発規約

- ガードのパターンを変更する場合は、先にフィクスチャを `tests/guard.test.mjs` に追加する
- CI は `node --check`（構文）+ `JSON.parse`（設定）+ `node --test`（テスト）の 3 段
- hooks は `node:` ビルトインのみ使用する
