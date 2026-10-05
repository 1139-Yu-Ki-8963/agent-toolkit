# agent-toolkit

Claude Code で使うスキル集を、公開できると判断した範囲だけ選んで配布するリポジトリ。各スキル集は `payload/` の下に 1 フォルダずつ置き、正本(private な作業環境)から `scripts/sync-payload.mjs` で写す。

2026-09-29 に、PC 全体の環境をセットアップする bundle `claudecode-global-setup`(スキル、規約、hook、サブエージェント、インストーラ)を閉じた。正本の側が 2026-09-20 に全面解体され、配布物だけが残っていたため。いまの配布物は、フォルダを置くだけで動くスキル集だけである。

## 導入

`payload/public-skills/.claude/` の中身を、使うプロジェクトの直下の `.claude/` に置く。settings.json への追加は要らない。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/payload/public-skills/.claude/rules/skill-writing-compact <プロジェクト>/.claude/rules/
cp -R agent-toolkit/payload/public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

`~/.claude/skills/` や `~/.claude/rules/` には置かない。規約は作業中のプロジェクトの中のファイルにしか効かないため、`~/.claude/` の下に置いたスキルを読んでも規約が読み込まれず、スキルが最初の step で中止する。

## payload 構成

```
payload/
└── public-skills/                        プロジェクトの .claude/ に置いて動く公開スキル集
    ├── README.md
    └── .claude/
        ├── rules/skill-writing-compact/  スキルの書き方の規約(1 ファイル版)、雛形、完成例
        └── skills/
            ├── drafting-skill-with-template/
            ├── checking-skill-against-rules/
            ├── designing-skill-tests/
            └── testing-agent-skills/
```

2026-09-29 に、reverse-docs-skills、claude-code-template、explanation-slides-kit、ai-driven-development-setup、ai-consulting-toolkit の公開をやめた。2026-10-05 に、`.claude/` 配下の構成に改め、規約を 1 ファイル版に一本化し、reviewing-agent-skills(checking-skill-against-rules に置き換え)、reporting-textlint-findings、converting-mermaid-md-to-html の公開をやめた。

## public-skills(プロジェクトに置いて動く公開スキル集)

各スキルは、他のスキルを参照せず単体で動く。導入手順と一覧は [`payload/public-skills/README.md`](payload/public-skills/README.md) にある。

| スキル | 何をするか | 前提 |
|---|---|---|
| [`drafting-skill-with-template`](payload/public-skills/.claude/skills/drafting-skill-with-template/SKILL.md) | 依頼にある作業を、規約と雛形に従ったスキルとして新しく書き、何も知らないサブエージェントに規約と照らさせて、違反がなくなるまで直す | `.claude/rules/skill-writing-compact`、サブエージェントを起動できる環境 |
| [`checking-skill-against-rules`](payload/public-skills/.claude/skills/checking-skill-against-rules/SKILL.md) | 既存のスキルの全ファイルを雛形の形と機械的に突き合わせ、規約の規則と 1 つずつ照らし、違反を一覧にする。ファイルは変更しない | 同上 |
| [`designing-skill-tests`](payload/public-skills/.claude/skills/designing-skill-tests/SKILL.md) | 既存のスキルから、対象の説明、仕様、機能の一覧、シナリオ、経路の網羅の表、既知の限界からなるテスト設計の文書を書き出す | サブエージェントを起動できる環境 |
| [`testing-agent-skills`](payload/public-skills/.claude/skills/testing-agent-skills/SKILL.md) | テスト設計の文書のシナリオを実行者に実行させ、記録を照らし、評価者の評価と合わせて検証の結果を表示する。対象は変更しない | 同上 |

4 つは、作る(drafting)、規約と照らす(checking)、テストを設計する(designing)、実行して検証する(testing)の順で使う。規約は、プロジェクトの `.claude/skills/` の下のファイルを読むか書くときに自動で読み込まれる。

## 更新(payload の同期)

`payload/` の中身は、private な正本のコピーである。`scripts/sync-manifest.json` の対応表に基づき、`scripts/sync-payload.mjs --check` で乖離を検知し、`--apply` で同期する。`git commit` 時には `scripts/check-payload-sync.sh` が乖離を検知して止める。公開の可否は `scripts/public-approval-ledger.md` に記録する。詳細は `CLAUDE.md` を参照。

## ディレクトリ構成

```
agent-toolkit/
├── README.md
├── CLAUDE.md                        このリポジトリで作業する AI 向けの手順書
├── .claude/settings.json            commit 時の同期検査 hook 2 本
├── payload/                         配布物(上の「payload 構成」)
└── scripts/
    ├── sync-manifest.json           正本 → payload の対応表
    ├── sync-payload.mjs             乖離検知と同期(--list / --check / --check-artifacts / --apply)
    ├── check-payload-sync.sh        commit 時に乖離を検知して止める hook
    ├── check-payload-artifacts.sh   commit 時に配布禁止の生成物を検知して止める hook
    ├── payload-artifacts.json       配布禁止パターン(公開側は枠だけ)
    └── public-approval-ledger.md    公開承認台帳
```

## 要件

- 利用者: Claude Code。スキルごとの前提は各スキルの SKILL.md に書いてある。
- 保守者: Node.js 18 以上(同期スクリプト)、bash と jq(commit 時の hook)。

ライセンスは現時点で指定されていない。再配布や利用条件が必要な場合はリポジトリ所有者へ確認すること。
