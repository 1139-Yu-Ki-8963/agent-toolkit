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

- `drafting-skill-with-template`: 依頼にある作業を、規約と雛形に従ったエージェントスキルとして新しく書き、何も知らないサブエージェントに規約と比べさせて、違反がなくなるまで直す。
- `checking-skill-with-template`: 既存のエージェントスキルの全ファイルを、雛形の形と機械的に突き合わせ、規約の規則と 1 つずつ比べ、反する箇所を雛形の該当行または規則の番号、ファイルと行、違反の内容、直し方の案とともに一覧にしてチャットに表示する。ファイルは変更しない。発動する場面は、作ったスキルや既存のスキルが規約に合っているかを確かめたいとき。発動しない場面は、スキルの新規の作成、指摘の修正、スキルを実際に実行させる動作の検証。
- `revising-skill-writing-rule`: スキル作成の規約の一式(規約、雛形、完成例)に規則を足す、直す、消すときに、置く節の決定、肯定形の規則の文、節の中の番号の振り直しと参照の修正、ピンクの象を除く書き直し、承認、反映、全スキルとの照合までを規則 改訂-1(この規約に規則を足す、直す、消すときに守ること)の手順で行う。発動する場面は、スキルの書き方の規約に規則を足したい、直したい、消したいとき。発動しない場面は、スキルの新規の作成や修正、既存のスキルと規約との照合だけ、雛形や完成例だけの変更。
- `designing-skill-test-cases`: 既存のエージェントスキルの `SKILL.md` と付属のファイルから、機能の一覧、機能ごとの確かめる深さと観点、機能ごとのテストケースと「最終出力の中身」のケース、手順の分岐の一覧、期待結果の種類ごとの判定の表からなるテストケースの文書を 1 つ、指定の出力先に書き出す。
- `designing-skill-test-scenarios`: テストケースの文書(`テストケース.md`)を読み、同じ依頼と見本のファイルで確かめられるケースを 1 つのシナリオにまとめ、シナリオごとの依頼の文、回答、選ぶ選択肢、見本のファイル、委任の返事、実行の回数、通る step と、分岐の網羅を決めて、テストシナリオの文書を 1 つ書き出す。
- `testing-skill-with-template`: テストシナリオの文書のシナリオごとに、そのスキルについて何も知らない実行者のサブエージェントに対象のスキルを実行させ、テストケースごとに「合格」「不合格」「判定できない」の 3 値で判定して、実行者と判定者の返り値の全文と実行後の成果物の写しとテスト結果の文書を、指定の出力先の実行日時のフォルダに書く。
- `converting-mermaid-md-to-html`: Mermaid の図を含む md ファイル 1 本を、図を描画した 1 ページの HTML に変換する。図はホイールで拡大、ドラッグで移動、右上のボタンで元に戻せる。上のバーに目次ボタンを持ち、ブラウザで直接開ける。md の中身は変更しない。発動する場面は、Mermaid の図を含む md を HTML に変換したい、md の図をブラウザで拡大して読みたいと依頼されたとき。発動しない場面は、複数の md をまとめたサイトの作成、md の内容の修正や整形や分割、Mermaid の図そのものの作成や修正、PDF やスライドへの変換、Web への公開。
- `reporting-textlint-findings`: md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。規約ができる前に書いた古い形のスキルで、`references/step共通の決まり.md` を持たず、`.textlintrc.json` をスキルの直下に置く。規約との照合の対象にはならない。古い形のまま収録している。

## 規約(`.claude/rules/skill-writing/`)

スキルの書き方の規約の 1 ファイル版(13 の節、46 規則)と、`SKILL.md` の雛形、完成例の 3 本。規約は「適用する場面、守ること、理由」の節を持ち、守ることは「規則 <節の短い名前>-<節の中の番号>: <観点>」の行と箇条書きの組で書く。規則を参照するときは、番号に観点の見出しを添える。drafting、checking、designing(cases、scenarios)、testing、revising、converting の 7 本は雛形の新しい形(step の見出しの印を末尾の `[]` に、情報の見出しを罫線つきに、固定の phase と文言に対象と相手を入れる)に合わせてある。reporting-textlint-findings は古い形のまま収録している。数の上限や選択肢の値は雛形の「変数」の節が持ち、規約は変数の名前で指す。先頭の `paths` が `.claude/skills/**/*` と `.claude/rules/skill-writing/**/*` を指すので、このプロジェクトの中のスキルと規約自身を触るときだけ読み込まれる。規約は、できあがったスキルが満たすことだけを持ち、どう書くかは雛形の「書き方の決まり」が持つ。

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
