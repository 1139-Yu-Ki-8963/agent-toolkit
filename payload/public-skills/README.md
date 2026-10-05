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

`~/.claude/skills/` や `~/.claude/rules/` には置かない。規約は作業中のプロジェクトの中のファイルにしか効かないため、`~/.claude/` の下に置いたスキルを読んでも規約が読み込まれず、スキルが最初の step で中止する。

## 収録スキル

- `drafting-skill-with-template`: 依頼にある作業を、規約と雛形に従ったエージェントスキルとして新しく書き、何も知らないサブエージェントに規約と照らさせて、違反がなくなるまで直す。
- `checking-skill-with-template`: 既存のエージェントスキルの全ファイルを、雛形の形と機械的に突き合わせ、規約の規則と 1 つずつ照らし、反する箇所を雛形の該当行または規則の番号、ファイルと行、違反の内容、直し方の案とともに一覧にしてチャットに表示する。
- `designing-skill-test-with-template`: 既存のエージェントスキルの `SKILL.md` と付属のファイルから、対象の説明、仕様、機能の一覧、機能ごとのシナリオ、経路の網羅の表、既知の限界からなるテスト設計の文書を 1 つ書き出す。
- `testing-skill-with-template`: テスト設計の文書を入力に取り、シナリオごとに、そのスキルについて何も知らない実行者(新しく起動したサブエージェント)に対象のスキルを実行させ、記録を機械的に照らし、全シナリオの記録を評価者(新しく起動したサブエージェント)に評価させて、成否、不明瞭な点、独自の判断で補った点、仕様と手順のずれ、直し方の提案、実際に通った機能による経路の網羅率を検証の結果として表示する。
- `converting-mermaid-md-to-html`: Mermaid の図を含む md ファイル 1 本を、図を描画した 1 ページの HTML に変換する。
- `reporting-textlint-findings`: md を textlint で機械検査し、指摘箇所に波線を引いた HTML を出す。

## 規約(`.claude/rules/skill-writing/`)

スキルの書き方の規約の 1 ファイル版(43 規則)と、`SKILL.md` の雛形、完成例の 3 本。規約は「適用する場面、守ること、理由」の節を持ち、守ることは「規則 N: 観点」の行と箇条書きの組で書く。数の上限や選択肢の値は雛形の「変数」の節が持ち、規約は変数の名前で指す。先頭の `paths` が `.claude/skills/**/*` と `.claude/rules/skill-writing/**/*` を指すので、このプロジェクトの中のスキルと規約自身を触るときだけ読み込まれる。

## 使い方の流れ

スキルを新しく作るときは、作る、規約と照らす、テストを設計する、実行して検証する、の順に使う。converting-mermaid-md-to-html と reporting-textlint-findings は単体で使う。各スキルは他のスキルを参照せず、単体で完結する。
