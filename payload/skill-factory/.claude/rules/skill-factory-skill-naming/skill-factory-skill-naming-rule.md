---
paths:
  - ".claude/skills/*/SKILL.md"
---

# skill-factory のスキルの名前の付け方の規約

## この規約について

この規約は、skill-factory の `.claude/skills/` に置く、スキルを作る作業のためのスキルの名前の付け方を決める規約です。規約 skill-writing-rule がどのスキルにも当てはまる書き方を決めるのに対して、この規約は、skill-factory の中だけで、スキルの役割と名前の最初の語を対応させます。

## この規約が満たすこと

- 規則は、スキルの名前を見れば合否が決まる文で書き、判定の仕方と対象の行を持つ。
- 規則は、スキルの役割と名前の最初の語の対応だけを持つ。
- 文は、文章の書き方の規約に従う。

## 適用する場面

skill-factory の `.claude/skills/` に置くスキルに名前を付けるとき。そのスキルの名前を照合するとき。

## 前提とする規約

- text-writing-rule.md

## 守ること

規則 1: スキルの名前の最初の語
- 判定の仕方: AI の推論
- 対象: skill-factory の `.claude/skills/` の下のフォルダの名前と、そのフォルダの `SKILL.md` の frontmatter の `name`
- 名前の最初の語は、スキルの役割ごとに、次の表の語とする。

| スキルの役割 | 名前の最初の語 |
|---|---|
| 依頼を聞き取り、要件の文書を書く | defining |
| 設計の文書か、スキルのファイルを新しく書く | drafting か designing |
| 成果物の中身から図を書く | drawing |
| 画面が読む状態のファイルを書き換える | updating |
| 文書を規約か雛形に照らし、指摘の一覧を出す | checking |
| 指摘を受けて、対象のファイルを直す | fixing |
| テストを流して、判定の記録を書く | testing |
| 規約の一式を直す | revising |
| 文書を書き直した全文を、新しいファイルに書く | rewrite |

- 採用した理由: 名前の最初の語の決まりは、規約 skill-writing-rule の用語の表にあった。規約 skill-writing-rule は `output/` の下のスキルにも読み込まれるので、ユーザーが作るスキルの名前まで決めていた。
- 採用しなかった理由: 「規約 skill-writing-rule に、名前の最初の語の決まりを当てるスキルの名前の一覧を足す」案では、単独で配る規約 skill-writing-rule が、skill-factory のスキルの名前を持つ。
