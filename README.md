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
├── public-skills/               単体で動く公開スキル集
│   ├── README.md
│   └── skills/
│       ├── creating-agent-skills/
│       ├── testing-agent-skills/
│       └── reporting-textlint-findings/
├── reverse-docs-skills/         リバース設計書の往復検証フロー(35 スキル)
│   ├── .claude/skills/
│   └── shared/                  6 スキル共通の共有資産
├── ai-consulting-toolkit/       AI コンサルティング用スキル集
├── claude-code-template/        プロジェクト用 CLAUDE.md の雛形と初期化スクリプト
└── explanation-slides-kit/      解説スライドの生成キット
```

## public-skills(単体で動く公開スキル集)

`payload/public-skills/skills/` の各スキルは、他のスキル、規約、hook を参照せず単体で動く。導入手順と一覧は [`payload/public-skills/README.md`](payload/public-skills/README.md) にある。

| スキル | 何をするか | 前提 |
|---|---|---|
| [`creating-agent-skills`](payload/public-skills/skills/creating-agent-skills/SKILL.md) | スキル運用規程(3 原則 20 規則)と雛形をもとに、スキルを新規に作る、または規程に合わせて書き直す。依頼がスキルの定義に合わなければ中止して案内する | なし |
| [`testing-agent-skills`](payload/public-skills/skills/testing-agent-skills/SKILL.md) | 作ったスキルを、何も知らない実行者(サブエージェント)に実行させ、不明瞭な点を洗い出して直す。成果物は一時フォルダに書き、終了時に消す | サブエージェントを起動できる環境 |
| [`reporting-textlint-findings`](payload/public-skills/skills/reporting-textlint-findings/SKILL.md) | md を textlint で検査し、指摘箇所に波線を引いた HTML を書き出す | node と textlint 6 パッケージ(一覧はスキルの SKILL.md) |

`creating-agent-skills` と `testing-agent-skills` は対で使う。前者の完了の報告が、動作を確かめるときに後者を案内する。

## reverse-docs-skills(リバース設計書の往復検証フロー)

`payload/reverse-docs-skills/` は独立したスキル集で、各スキルは他スキルのフォルダに依存せず単独で起動できる。共有資産(テンプレート、章対応表、監査スクリプト)は `shared/` に同梱済みである。全 35 スキルのうち主要 6 スキルを挙げる。

| スキル | 担当 |
|---|---|
| [`generating-screen-list-for-reverse-docs`](payload/reverse-docs-skills/.claude/skills/generating-screen-list-for-reverse-docs/SKILL.md) | レガシーコードベースを 4 phase(スタック調査、検出戦略の宣言、抽出、整合の検証)で画面単位にグルーピングし、画面一覧の HTML を生成する。validate と build は jq に依存する |
| [`orchestrating-reverse-docs-flow`](payload/reverse-docs-skills/.claude/skills/orchestrating-reverse-docs-flow/SKILL.md) | 画面の状態(未開通、開通済み、基準確立済み)を判定し、他 5 スキルの引数を事前に解決して呼び出す統括役 |
| [`unlocking-reverse-target-screens`](payload/reverse-docs-skills/.claude/skills/unlocking-reverse-target-screens/SKILL.md) | 設計書のない画面をモック API でログイン後まで開通させ、動作確認できる状態にする |
| [`syncing-reverse-env`](payload/reverse-docs-skills/.claude/skills/syncing-reverse-env/SKILL.md) | ポート番号だけが違う 2 つの検証環境を用意して同期し、完全一致の証明を基準タグとして確立する |
| [`rebuilding-screen-unit-from-docs`](payload/reverse-docs-skills/.claude/skills/rebuilding-screen-unit-from-docs/SKILL.md) | 画面詳細設計書だけから単体テスト観点で 1 ファイルを再生成し、原本と 5 つの計測で突合する |
| [`rebuilding-code-from-docs`](payload/reverse-docs-skills/.claude/skills/rebuilding-code-from-docs/SKILL.md) | 画面基本設計書だけからコードを再生成し、元コードと機械突合して設計書の欠落を見つける |

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
