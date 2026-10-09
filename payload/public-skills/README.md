# public-skills

Claude Code で使うスキルと、スキルの書き方の規約を公開する置き場。`.claude/` の下に、規約(`rules/`)とスキル(`skills/`)を、プロジェクトに置いてそのまま動く形で収めている。

## 導入

この `.claude/` フォルダの中身を、使うプロジェクトの直下の `.claude/` に置く(既に `.claude/` があるときは、中の `rules/` と `skills/` を足す)。

```bash
git clone <このリポジトリ>
cp -R public-skills/.claude/rules/skill-writing <プロジェクト>/.claude/rules/
cp -R public-skills/.claude/skills/<スキル名> <プロジェクト>/.claude/skills/
```

settings.json への追加は要らない。規約は、プロジェクトの中の `.claude/skills/` の下のファイルを読むか書くときに自動で読み込まれ、常時読み込まれるものはない。

規約の一式が自動で読み込まれる前提で動くのは、drafting-skill-with-template と checking-skill-with-template の 2 本だけ。この 2 本は、自分の `SKILL.md` を読んだときに規約が読み込まれる前提で動くので、プロジェクトの中の `.claude/skills/` に置く。`~/.claude/skills/` に置くと規約が読み込まれず、最初の step で中止する。revising-skill-writing-rule は規約のフォルダをパスで受け取って読む。ほかのスキルは `references/step共通の決まり.md` だけで動くので、置き場所を選ばない。

## 収録スキル

- `drafting-skill-with-template`: 依頼にある作業を、雛形「スキルの雛形(phase と step)」と規約に従ったエージェントスキルとして新しく書き、何も知らないサブエージェントに規約と比べさせて、違反がなくなるまで直す。
- `checking-skill-with-template`: 雛形「スキルの雛形(phase と step)」で作った既存のスキルの全ファイルを、雛形の本文と機械的に突き合わせ、規約の規則と 1 つずつ比べ、反する箇所を雛形の該当行または規則、ファイル:行、違反の内容、直し方の案とともに一覧にしてチャットに表示する。
- `fixing-skill-with-template`: 雛形「スキルの雛形(phase と step)」で作った既存のスキルを、checking-skill-with-template が出した指摘の一覧に沿って、指摘を 4 つの種類に仕分け、決めた直し方で直し、修正の結果をチャットに表示する。
- `revising-skill-writing-rule`: スキル作成の規約の一式(規約、雛形、完成例)に決まりを足す、直す、消す依頼を、規約の規則、雛形、規約の冒頭の章、設計書、規約にも雛形にもしないものに仕分けて既にある決まりと照らし、置く位置の決定、置き場の形の文、節の中の番号の振り直しと参照の修正、ピンクの象を除く書き直し、承認、反映、全スキルと完成例との照合までを規約の改訂の規則の手順で行う。
- `designing-skill-test-cases`: 雛形「スキルの雛形(phase と step)」で作った既存のスキルの `SKILL.md` と付属のファイルから、機能の一覧、機能ごとの確かめる深さと観点、機能ごとのテストケースと「最終出力の中身」のケース、手順の分岐の一覧、期待結果の種類ごとの判定の表からなるテストケースの文書を 1 つ、指定の出力先に書き出す。
- `designing-skill-test-scenarios`: 雛形「スキルの雛形(phase と step)」で作ったスキルのテストケースの文書(`テストケース.md`)を読み、同じ依頼と見本のファイルで確かめられるケースを 1 つのシナリオにまとめ、シナリオごとの依頼の文、回答、選ぶ選択肢、見本のファイル、委任の返事、実行の回数、通る step と、分岐の網羅を決めて、テストシナリオの文書を 1 つ書き出す。
- `testing-skill-with-template`: 雛形「スキルの雛形(phase と step)」で作ったスキルのテストシナリオの文書のシナリオごとに、そのスキルについて何も知らない実行者のサブエージェントに対象のスキルを実行させ、テストケースごとに「合格」「不合格」「判定できない」の 3 値で判定して、実行者と判定者の返り値の全文と実行後の成果物の写しとテスト結果の文書を、指定の出力先の実行日時のフォルダに書く。
- `fixing-skill-from-test-results`: 雛形「スキルの雛形(phase と step)」で作ったスキルを、testing-skill-with-template が書いたテスト結果の文書に沿って、不合格と判定できないのケースの原因を 5 つの種類に仕分け、スキルの誤りだけを直し、もう一度テストする依頼の文を含む修正の結果をチャットに表示する。
- `converting-mermaid-md-to-html`: Mermaid の図を含む md ファイル 1 本を、md の中身を変えずに、図をホイールで拡大、ドラッグで移動、右上のボタンで元に戻せて、上のバーに目次ボタンを持ち、ブラウザで直接開ける 1 ページの HTML に変換する。
- `reporting-textlint-findings`: md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。規約ができる前に書いた古い形のスキルで、`references/step共通の決まり.md` を持たず、`.textlintrc.json` をスキルの直下に置く。規約との照合の対象にはならない。古い形のまま収録している。
- `managing-textlint-banned-words`: textlint の禁止語の辞書と設定と hooks を依頼どおりの状態にし、辞書を一覧で表示する。

## 規約(`.claude/rules/skill-writing/`)

スキルの書き方の規約(9 の節、32 規則。雛形の構造に依存する決まりは、雛形「スキルの雛形(phase と step)」の章「この雛形で作るスキルが守ること」にある)と、`SKILL.md` の雛形、完成例の 3 本。規約は「この規約について」「この規約が満たすこと」「適用する場面」「守ること」の章を持ち、守ることは「規則 <番号>: <観点>」の行と箇条書きの組で書く。規則は観点で参照する。drafting、checking、designing(cases、scenarios)、testing、revising、converting の 7 本は雛形の新しい形(step の見出しの印を末尾の `[]` に、情報の見出しを罫線つきに、固定の phase と文言に対象と相手を入れる)に合わせてある。reporting-textlint-findings は古い形のまま収録している。数の上限は雛形の規則が持ち、選択肢、固定の名前、ツールの呼び方は、雛形の「決まった値の一覧」の章が持つ。先頭の `paths` が `.claude/skills/**/*` と `.claude/rules/skill-writing/**/*` を指すので、このプロジェクトの中のスキルと規約自身を触るときだけ読み込まれる。規約は、できあがったスキルが満たすことだけを持ち、どう書くかは雛形の「書き方の決まり」が持つ。

`.claude/rules/text-writing/` には、文章の書き方の規約(見出しや名前に誰が何を誰にを入れる、見たままの言葉で書く、名前は何であるかで付ける、文には主語を書く)が 1 本ある。雛形が山かっこを埋める語句の合否の基準としてこれを指す。`paths` を持たず、常に読み込まれる。

## 使い方の流れ

スキルを新しく作るときは、作る、規約と比べる、テストを設計する、実行して検証する、の順に使う。規約そのものを直すときは revising-skill-writing-rule を使う。converting-mermaid-md-to-html と reporting-textlint-findings は単体で使う。各スキルは他のスキルを参照せず、単体で完結する。

## 構成

リポジトリの直下にあるのは、この README と、`.claude/` と、`.gitignore`(node_modules の除外だけ)の 3 つ。

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
```

`step共通の決まり.md` は、ツールの呼び方、チャットへの表示の書式、中止の決まり、完了の確認の手順を持つ。各スキルは最初の step でこれを読むので、スキルは規約の一式がなくても単体で動く。規約の一式が要るのは、スキルを書くときと、規約と比べるときだけ。
