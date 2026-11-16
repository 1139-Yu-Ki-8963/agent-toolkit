# agent-toolkit

Claude Code で使うスキル集を、公開できると判断した範囲だけ選んで配布するリポジトリ。各スキル集は `payload/` の下に 1 フォルダずつ置き、正本(private な作業環境)から `scripts/sync-payload.mjs` で写す。

2026-09-29 に、PC 全体の環境をセットアップする bundle `claudecode-global-setup`(スキル、規約、hook、サブエージェント、インストーラ)を閉じた。正本の側が 2026-09-20 に全面解体され、配布物だけが残っていたため。いまの配布物は、フォルダを置くだけで動くスキル集だけである。

## 導入

`payload/public-skills/.claude/` の中身を、使うプロジェクトの直下の `.claude/` に置く。settings.json への追加は要らない。

```bash
git clone https://github.com/1139-Yu-Ki-8963/agent-toolkit.git
cp -R agent-toolkit/payload/public-skills/.claude/rules/skill-writing <プロジェクト>/.claude/rules/
cp -R agent-toolkit/payload/public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

`~/.claude/skills/` や `~/.claude/rules/` には置かない。規約は作業中のプロジェクトの中のファイルにしか効かないため、`~/.claude/` の下に置いたスキルを読んでも規約が読み込まれず、スキルが最初の step で中止する。

## payload 構成

```
payload/
├── public-skills/                        プロジェクトの .claude/ に置いて動く公開スキル集
│   ├── README.md
│   └── .claude/
│       ├── rules/skill-writing/  スキルの書き方の規約(1 ファイル版)、雛形、完成例
│       └── skills/
│           ├── drafting-skill-with-template/
│           ├── checking-skill-with-template/
│           ├── designing-skill-test-with-template/
│           ├── testing-skill-with-template/
│           ├── converting-mermaid-md-to-html/
│           └── reporting-textlint-findings/
├── ai-consulting-toolkit/                AI 推進コンサルタントの道具箱
│   ├── README.md                         業務フロー・ドキュメント一覧・スキル一覧の入口
│   ├── .claude/skills/                   consult-* スキル
│   ├── docs/                             業務フロー、判定基準、テンプレート、案件フォルダ設計(14)
│   ├── templates/案件雛形/               新しい案件を始めるとき複製するフォルダ一式
│   └── portal/                           業務管理ポータル(データは架空のプロトタイプ)
├── slide-creator-studio/                 Claude デザインの上にスライドを作るスキルと規約
│   ├── README.md
│   ├── .claude/
│   │   ├── rules/slide-writing/  スライドの書き方の規約、デザインシステム「墨と赤」、見本
│   │   └── skills/
│   │       ├── creating-claude-design-slide/
│   │       ├── checking-one-slide-one-message/
│   │       ├── checking-slide-story/
│   │       └── assembling-claude-design-slides/
│   ├── slides/2026-11-14_理想のAI駆動開発フロー/理想のAI駆動開発フロースライド.html   スキルで作った資料 10 枚
│   └── slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html   工程ごとに作る資料の図
├── engineering-handbook/                 ベテランエンジニアのように振る舞わせる規約 2 本とスキル 9 本
│   ├── README.md
│   ├── LICENSE                           MIT(pstack 由来の部分を含む)
│   ├── NOTICE.md                         もとにした pstack の著作権表示と、ファイルの対応
│   ├── rules/                            .claude/rules/ に置く規約(veteran-engineer、agent-behavior)
│   └── skills/                           .claude/skills/ に置くスキル(investigate、bug-fix など 9 本)
```

2026-09-29 に、reverse-docs-skills、claude-code-template、explanation-slides-kit、ai-driven-development-setup、ai-consulting-toolkit の公開をやめた。2026-10-05 に、`.claude/` 配下の構成に改め、規約を 1 ファイル版に一本化し、reviewing-agent-skills(checking-skill-with-template に置き換え)の公開をやめた。同日、ai-consulting-toolkit の公開を再開した(skills、docs、portal に加え、templates と README.md を同期)。

## ai-consulting-toolkit(AI 推進コンサルタントの道具箱)

顧客企業の現場業務をヒアリングし、AI 化の提案・導入・運用管理までを進めるための道具箱。使い方は [`payload/ai-consulting-toolkit/README.md`](payload/ai-consulting-toolkit/README.md) にある。新しい案件は `templates/案件雛形/` を複製して始め、決まりは `docs/14_案件フォルダ設計/案件フォルダ設計.md` にある。

## slide-creator-studio(Claude デザインの上にスライドを作る)

説明用のスライドを、Claude デザイン(Artifact の型「Design」)の上に作るスキル 4 本と、規約 1 本の一式。1 枚を作る、1 枚の図が 1 つの結論だけを伝えているかを判定する、結論の並びが 1 つの話として通るかを判定する、決まった並びで資料に組み立てる、の 4 つができる。使い方は [`payload/slide-creator-studio/README.md`](payload/slide-creator-studio/README.md) にある。2026-11-14 に公開を始めた。

このスキルで作った資料「理想の AI駆動開発フロー(一般論)」10 枚を、1 つの HTML ファイルにまとめて [`payload/slide-creator-studio/slides/`](payload/slide-creator-studio/slides/2026-11-14_理想のAI駆動開発フロー/理想のAI駆動開発フロースライド.html) に置いている。ファイルを落としてブラウザで開き、← → かスペースでページを送る。3 枚目は、周回のボタンを押すと動く。2026-11-16 に公開を始めた。

slide-creator-studio の側では、作ったスライドを非公開の `output-slides/` に置き、公開すると選んだものだけを `payload/` に symlink で置く。この toolkit は、その `payload/` だけを `payload/slide-creator-studio/slides/` に写す(`sync-manifest.json` の mirror の `symlinkRoot`)。

資料「AI 駆動開発フローの資料マップ」は、AI 駆動開発の工程ごとに作る資料と、用意する順を、縦の 1 枚の図にした HTML 1 本([`payload/slide-creator-studio/slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html`](payload/slide-creator-studio/slides/2026-11-14_AI駆動開発フローの資料マップ/AI駆動開発フローの資料マップ.html))。図は、右上のボタン、ホイール、ドラッグで拡大と移動ができ、資料の札を押すと、その資料の説明のスライドが重なって出る。見る人は、ファイルを落として、ブラウザで開く。拡大と移動には @panzoom/panzoom 4.6.2(MIT)を HTML の中に入れて使っている。2026-11-16 に公開を始めた。

## engineering-handbook(ベテランエンジニアのように振る舞わせる規約とスキル)

Claude Code に、ベテランエンジニアの判断と作業の進め方をさせるための一式。規約 2 本(ベテランエンジニアの振る舞い、エージェントの振る舞い)と、作業ごとのスキル 9 本(調査、試作、計画、機能追加、バグ修正、リファクタ、性能改善、PR 作成、PR 対応)からなる。スキルは規約がなくても単体で動く。`rules/` を `.claude/rules/` に、`skills/` を `.claude/skills/` に、必要なものだけ写して使う。使い方は [`payload/engineering-handbook/README.md`](payload/engineering-handbook/README.md) にある。

Cursor の公式プラグインリポジトリにある pstack(作者 Lauren Tan、MIT License)を、日本語に訳し、要約し、Claude Code で単体で動くように作り直したもの。ライセンスは [`payload/engineering-handbook/LICENSE`](payload/engineering-handbook/LICENSE)、もとにしたファイルの対応は [`payload/engineering-handbook/NOTICE.md`](payload/engineering-handbook/NOTICE.md) にある。2026-11-17 に公開を始めた。

## public-skills(プロジェクトに置いて動く公開スキル集)

各スキルは、他のスキルを参照せず単体で動く。導入手順と一覧は [`payload/public-skills/README.md`](payload/public-skills/README.md) にある。

| スキル | 何をするか | 前提 |
|---|---|---|
| [`drafting-skill-with-template`](payload/public-skills/.claude/skills/drafting-skill-with-template/SKILL.md) | 依頼にある作業を、規約と雛形に従ったスキルとして新しく書き、何も知らないサブエージェントに規約と照らさせて、違反がなくなるまで直す | `.claude/rules/skill-writing`、サブエージェントを起動できる環境 |
| [`checking-skill-with-template`](payload/public-skills/.claude/skills/checking-skill-with-template/SKILL.md) | 既存のスキルの全ファイルを雛形の形と機械的に突き合わせ、規約の規則と 1 つずつ照らし、違反を一覧にする。ファイルは変更しない | 同上 |
| [`designing-skill-test-with-template`](payload/public-skills/.claude/skills/designing-skill-test-with-template/SKILL.md) | 既存のスキルから、対象の説明、仕様、機能の一覧、シナリオ、経路の網羅の表、既知の限界からなるテスト設計の文書を書き出す | サブエージェントを起動できる環境 |
| [`testing-skill-with-template`](payload/public-skills/.claude/skills/testing-skill-with-template/SKILL.md) | テスト設計の文書のシナリオを実行者に実行させ、記録を照らし、評価者の評価と合わせて検証の結果を表示する。対象は変更しない | 同上 |
| [`converting-mermaid-md-to-html`](payload/public-skills/.claude/skills/converting-mermaid-md-to-html/SKILL.md) | Mermaid の図を含む md 1 本を、図を描画した 1 ページの HTML に変換する | hugo(extended)。無ければスキルが入れ方を案内する |
| [`reporting-textlint-findings`](payload/public-skills/.claude/skills/reporting-textlint-findings/SKILL.md) | md を textlint で検査し、指摘箇所に波線を引いた HTML を書き出す | node と textlint のパッケージ(一覧はスキルの SKILL.md) |

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
