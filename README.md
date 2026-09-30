# agent-toolkit

Claude Code で使うスキル集を、公開できると判断した範囲だけ選んで配布するリポジトリ。各スキル集は `payload/` の下に 1 フォルダずつ置き、正本(private な作業環境)から `scripts/sync-payload.mjs` で写す。

2026-09-29 に、PC 全体の環境をセットアップする bundle `claudecode-global-setup`(スキル、規約、hook、サブエージェント、インストーラ)を閉じた。正本の側が 2026-09-20 に全面解体され、配布物だけが残っていたため。いまの配布物は、フォルダを置くだけで動くスキル集だけである。

## 導入

使いたいスキルのフォルダを、Claude Code のスキルの置き場へ複製する。settings.json への追加は要らない。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/payload/public-skills/skills/<スキル名> ~/.claude/skills/
```

プロジェクトだけで使うなら `<repo>/.claude/skills/` へ複製する。

## payload 構成

```
payload/
└── public-skills/               単体で動く公開スキル集
    ├── README.md
    ├── agent-skill-templates/   規程、雛形 2 つ、手引き、記入例(スキルの references の正本)
    └── skills/
        ├── drafting-agent-skill-from-template/
        ├── reviewing-agent-skills/
        ├── testing-agent-skills/
        └── reporting-textlint-findings/
```

2026-09-29 に、reverse-docs-skills、claude-code-template、explanation-slides-kit、ai-driven-development-setup、ai-consulting-toolkit の公開をやめた。

## public-skills(単体で動く公開スキル集)

`payload/public-skills/skills/` の各スキルは、他のスキル、規約、hook を参照せず単体で動く。導入手順と一覧は [`payload/public-skills/README.md`](payload/public-skills/README.md) にある。

| スキル | 何をするか | 前提 |
|---|---|---|
| [`drafting-agent-skill-from-template`](payload/public-skills/skills/drafting-agent-skill-from-template/SKILL.md) | 雛形の組の型に沿って、スキルの下書きを新規に作る。規程との照合と動作の確認は行わず、次のスキルを案内する。依頼がスキルの定義に合わなければ中止して案内する | なし |
| [`reviewing-agent-skills`](payload/public-skills/skills/reviewing-agent-skills/SKILL.md) | 既存のスキルを規程の 20 規則と 1 つずつ照らし、規則の番号、箇所、根拠、直し方の案を一覧にする。ファイルは変更しない | なし |
| [`testing-agent-skills`](payload/public-skills/skills/testing-agent-skills/SKILL.md) | 作ったスキルを、何も知らない実行者(サブエージェント)に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |
| [`reporting-textlint-findings`](payload/public-skills/skills/reporting-textlint-findings/SKILL.md) | md を textlint で検査し、指摘箇所に波線を引いた HTML を書き出す | node と textlint 6 パッケージ(一覧はスキルの SKILL.md) |

3 つは、下書きを作る(drafting)、規程と照らす(reviewing)、動かして直す(testing)の順で使い、前のスキルの完了の報告が次を案内する。規程、雛形、手引き、記入例の正本は [`payload/public-skills/agent-skill-templates/`](payload/public-skills/agent-skill-templates/) にあり、スキルの `references/` はその写しである。

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
