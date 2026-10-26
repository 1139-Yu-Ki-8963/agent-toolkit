# public-skills

Claude Code で使うスキルと、スキルの書き方の規約を公開する置き場。`.claude/` の下に、規約(`rules/`)とスキル(`skills/`)を、プロジェクトに置いてそのまま動く形で収めている。

## 導入

この `.claude/` フォルダの中身を、使うプロジェクトの直下の `.claude/` に置く(既に `.claude/` があるときは、中の `rules/` と `skills/` を足す)。

```bash
git clone <このリポジトリ>
cp -R public-skills/.claude/rules/skill-writing <プロジェクト>/.claude/rules/
cp -R public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

規約とスキルだけなら settings.json への追加は要らない(hook を使うときは「hook の導入」の章を見る)。規約は、プロジェクトの中の `.claude/skills/` の下のファイルを読むか書くときに自動で読み込まれ、常時読み込まれるものはない。

規約の一式が自動で読み込まれる前提で動くのは、drafting-skill-with-template と checking-skill-with-template の 2 本だけ。この 2 本は、自分の `SKILL.md` を読んだときに規約が読み込まれる前提で動くので、プロジェクトの中の `.claude/skills/` に置く。`~/.claude/skills/` に置くと規約が読み込まれず、最初の step で中止する。revising-skill-writing-rule は規約のフォルダをパスで受け取って読む。ほかのスキルは `references/step共通の決まり.md` だけで動くので、置き場所を選ばない。

## hook の導入

スキル開発の流れ(`docs/流れ/スキル開発の流れ.md`)は、hook 3 本が動いている前提で書いてある。`.claude/hooks/` をプロジェクトの `.claude/` に置き、プロジェクトの `.claude/settings.json` に次の登録を足す。hook は `.claude/rules`、`.claude/skills`、`.claude/skills/tests` を、自分の置き場からの相対パスで見るので、パスの書き換えは要らない。

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-tool-use-write-file.js", "timeout": 60 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-tool-use-write-file.js", "timeout": 60 } ] },
      { "matcher": "", "hooks": [ { "type": "command", "command": "node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-tool-use-any-tool.js", "timeout": 60 } ] }
    ]
  }
}
```

| hook | 何をするか |
|---|---|
| pre-tool-use-write-file | テスト計画書を持つスキルのファイルとテスト計画書の書き換えを、fixing-skill、revising-skill-writing-rule、fixing-test-plan、designing-skill-test-cases、designing-skill-test-scenarios の手順の外では止める |
| post-tool-use-any-tool | どのツールの操作のあとでも、守るファイルの変化を、スキルの手順の跡と突き合わせる |
| post-tool-use-write-file | `.md` を変えたら、当たる規約のパスの一覧を添えて照合と直しを促し、規約を変えたらピンクの象を除く書き直しとユーザーの承認を促す |

各 hook の登録の値と確かめ方は、`.claude/hooks/<hook の名前>/README.md` にある。

## 収録スキル

スキルを作る、直す、照合する、テストする 13 本のスキルと、その規約は、配布リポジトリ agent-toolkit の `payload/skill-factory/` に移した。このリポジトリには、単体で使うスキルと、規約を直すスキルだけを収める。

- `revising-skill-writing-rule`: スキル作成の規約の一式(規約、雛形、完成例)に決まりを足す、直す、消す依頼を、規約の規則、雛形、規約の冒頭の章、設計書、規約にも雛形にもしないものに仕分けて既にある決まりと突き合わせ、置く位置の決定、置き場の形の文、節の中の番号の振り直しと参照の修正、ピンクの象を除く書き直し、承認、反映までを規約の改訂の規則の手順で行う。
- `converting-mermaid-md-to-html`: Mermaid の図を含む md ファイル 1 本を、md の中身を変えずに、図をホイールで拡大、ドラッグで移動、右上のボタンで元に戻せて、上のバーに目次ボタンを持ち、ブラウザで直接開ける 1 ページの HTML に変換する。
- `reporting-textlint-findings`: md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。
- `managing-textlint-banned-words`: textlint の禁止語の辞書と設定と hooks を依頼どおりの状態にし、辞書を一覧で表示する。

## 規約(`.claude/rules/skill-writing/`)

スキルの書き方の規約(9 の節、32 規則。雛形の構造に依存する決まりは、雛形「スキルの雛形(phase と step)」の章「この雛形で作るスキルが守ること」にある)と、`SKILL.md` の雛形、完成例の 3 本。規約は「この規約について」「この規約が満たすこと」「適用する場面」「守ること」の章を持ち、守ることは「規則 <番号>: <観点>」の行と箇条書きの組で書く。規則は観点で参照する。drafting、checking、designing(cases、scenarios)、testing、revising、converting の 7 本は雛形の新しい形(step の見出しの印を末尾の `[]` に、情報の見出しを罫線つきに、固定の phase と文言に対象と相手を入れる)に合わせてある。reporting-textlint-findings は古い形のまま収録している。選択肢、固定の名前、ツールの呼び方は、雛形の「決まった値の一覧」の章が持つ。先頭の `paths` が `.claude/skills/**/*` と `.claude/rules/skill-writing/**/*` を指すので、このプロジェクトの中のスキルと規約自身を触るときだけ読み込まれる。規約は、できあがったスキルが満たすことだけを持ち、どう書くかは雛形の「書き方の決まり」が持つ。

`.claude/rules/text-writing/` には、文章の書き方の規約(見出しや名前に誰が何を誰にを入れる、見たままの言葉で書く、名前は何であるかで付ける、文には主語を書く)が 1 本ある。雛形が山かっこを埋める語句の合否の基準としてこれを指す。`paths` を持たず、常に読み込まれる。

## 使い方の流れ

スキルを新しく作るときは、作る、規約と比べる、テストを設計する、実行して検証する、の順に使う。規約そのものを直すときは revising-skill-writing-rule を使う。converting-mermaid-md-to-html と reporting-textlint-findings は単体で使う。各スキルは他のスキルを参照せず、単体で完結する。

## 構成

リポジトリの直下にあるのは、この README と、`.claude/`(規約とスキル)と、`docs/`(公開スキルの検査の状況、設計、スキル開発の流れ、提案、履歴の文書)と、`.gitignore`(node_modules の除外だけ)の 4 つ。

```text
.claude/
├── rules/skill-writing/
│   ├── skill-writing-rule/skill-writing-rule.md          規約
│   ├── skill-template/skill-template.md                  SKILL.md の雛形
│   └── skill-template-completed-example/skill-completed-example.md  完成例
└── skills/
    ├── <スキルの名前>/
    │   ├── SKILL.md
    │   └── references/
    │       ├── step共通の決まり.md    どのスキルも持つ。雛形の「step 共通の決まり」の節の写し
    │       └── <そのスキルのリファレンス>.md
    └── reporting-textlint-findings/   古い形。step共通の決まり.md を持たず、.textlintrc.json を直下に置く
docs/
├── 公開スキルの検査の状況.md   収録スキルごとに、規約との照合、テストシナリオの実施、ピンクの象の除去、文章の書き方の規約との照合を通ったかの表
├── 設計/      エージェントの設定ファイルとプログラムの構成要素の対応表
├── 流れ/      スキル開発の流れの文書と図(md と html)、各スキルの要件、テストの前提の状態に関する問題
├── 提案/      規約と雛形への提案。書き方は 提案/フォーマット.md
└── 履歴/      フィードバックへの修正対応の履歴と、消した規則の記録(消した規則の原文と理由)
```

`step共通の決まり.md` は、ツールの呼び方、チャットへの表示の書式、中止の決まり、完了の確認の手順を持つ。各スキルは最初の step でこれを読むので、スキルは規約の一式がなくても単体で動く。規約の一式が要るのは、スキルを書くときと、規約と比べるときだけ。
