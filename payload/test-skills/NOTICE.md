# NOTICE

このフォルダの skill のうち 8 は、ほかの作品をもとに作っています。pstack から作ったものが 4 つ(そのうち performance は、engineering-handbook を経たもの)、break-ui から作ったものが 1 つ、gstack から作ったものが 3 つです。designing-test-cases は、一般のテスト技法から書いたもので、ほかの作品から作ったものではありません。

engineering-handbook は、このフォルダと同じ作者(1139-Yu-Ki-8963)の、pstack をもとに日本語で作り直した規約と skill の集まりです。ライセンスは MIT License で、pstack の部分の著作権表示と許諾表示を持ちます。

## pstack から作った skill

- 元の作品: pstack(https://github.com/cursor/plugins/tree/main/pstack)
- 元の作者: Lauren Tan
- 元のライセンス: MIT License(下に全文を掲載)
- 訳した元: pstack のミラー(https://github.com/backnotprop/pstack、コミット 2a5621683e2bbb274efea8b52dd69f5beef6c25f、2026 年 11 月 24 日)。このミラーは、cursor/plugins の pstack を写し、Cursor でしか動かなかった skill を、ほかの道具でも動くように書き直したものです。

すべて、英語の原文を日本語に訳したものです。原文をそのまま収録したファイルはありません。

| このフォルダのファイル | もとにしたファイル | 元から変えたこと |
|---|---|---|
| `.claude/skills/create-formal-verification-skill/SKILL.md` | pstack の `skills/create-formal-verification-skill/SKILL.md` | 日本語に訳した。TLA+ の結果を pstack の statechart で読む指示を、反例を最短の手順の並びとしてコードの言葉で読む指示に置き換えた。 |
| `.claude/skills/maintain-formal-verification-skill/SKILL.md` | pstack の `skills/maintain-formal-verification-skill/SKILL.md` | 日本語に訳した。 |
| `.claude/skills/blast-radius/SKILL.md` | pstack の `skills/blast-radius/SKILL.md` | 日本語に訳した。how と why の名前を出す文と、報告を unslop で書く指示を外した。大きな変更で arena を使う手順を、互いの結果を知らない 2 つ以上のサブエージェントに同じ問いを出してまとめる手順に置き換えた。 |
| `.claude/skills/performance/SKILL.md` | engineering-handbook の `skills/performance/SKILL.md`(その元は、pstack の `skills/poteto-mode/playbooks/perf-issue.md` と `skills/benchmark-checklist/SKILL.md`) | ほかの skill(bug-fix、open-pr)と規約の ID への参照を外した。pstack の benchmark-checklist の中身のうち、engineering-handbook の版に入っていなかった点を訳して足した。足した点は、おおまかな見積もりのとき、コアの数と忙しいときの確かめ、本番と同じにする条件の項目、交互に実行する理由、基準値への確かめ、プロファイルの道具の例、調整されていない側の扱い(手順 4 に置いた)、効かなかった変更の扱い、エラーを数える処理と再試行、順位和検定、全体の時間を測る条件と 1% の例、処理が実際に行われたかの確かめの項目、山登りの改善の計測の道具である。コアの数の確かめに、macOS のコマンドを足した。 |

pstack の skill の Codex 向けの設定のファイル(`agents/openai.yaml`)は、写していません。

## break-ui

- 元の作品: break-ui(作者 Emil Kowalski、MIT License)
- 出どころと、元から変えたことは、`.claude/skills/break-ui/SOURCE.md` にあります。
- 元のライセンスの全文は、`.claude/skills/break-ui/LICENSE` にあります。

## gstack から作った skill

- 元の作品: gstack(https://github.com/garrytan/gstack)
- 元の作者: Garry Tan
- 元のライセンス: MIT License。全文は `third-party/gstack/LICENSE` にあります。
- 訳した元: gstack のコミット 789e9badaa754c666fba0ad18032e7c5dad474d7
- gstack がほかの作品から作った部分の表示は `third-party/gstack/NOTICE.md` に、そのライセンスの全文は `third-party/gstack/licenses/` にあります。`gstack-design-review` の `sections/craft-audit.md` は、その表示にある redesign-skill と ai-design-skills(Elaya、MIT License)から作られています。`gstack-design-review` の `SKILL.md` の、Persuade、Operate、Read、Experience のモードの分類の文は、その表示にある impeccable(Paul Bakaus、Apache License 2.0)から gstack が作った `scripts/resolvers/design.ts` が書いた文で、この版では、ほかの文と同じく、一部を日本語に訳して変えています。Apache License 2.0 の全文は、`third-party/gstack/licenses/Apache-2.0.txt` にあります。

| このフォルダのフォルダ | もとにしたフォルダ |
|---|---|
| `.claude/skills/gstack-qa/` | gstack の `qa/` |
| `.claude/skills/gstack-design-review/` | gstack の `design-review/` |
| `.claude/skills/gstack-benchmark/` | gstack の `benchmark/` |

元から変えたことは、次の 4 つです。

- 日本語に訳した。
- gstack の道具(`bin/` のスクリプト、ブラウザの道具 `browse`、`design`)を使わず、Claude Code の道具と Playwright の MCP だけで動く手順に書き直した。gstack の学び、質問、判断、テレメトリの記録と、共有の前置き(`preamble.md`)は消し、要る決まりだけを各 `SKILL.md` に入れた。報告の置き場は、調べるリポジトリの `test-reports/` にした。
- 外の AI(Codex)の意見を、互いの結果を知らない 2 つのサブエージェントの意見に置き換えた。
- frontmatter の `name` を、元の名前の前に `gstack-` を付けた名前にした。雛形(`*.tmpl`)と、節の登録簿(`sections/manifest.json`)は、写していない。

## pstack の元のライセンス

```
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
