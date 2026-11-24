# slide-creator-studio

このフォルダは、Claude Code で、説明用のスライドを Claude デザイン(Artifact の型「Design」)の上に作るための一式です。規約は、見た目と中身の原則を持ち、デザインシステムは、値とテンプレートを持ち、チェックツールは、スライドを機械で確かめ、スキル 2 本は、作る手順と、HTML にまとめる手順を持ちます。責務の定義と置き場の地図は、プロジェクトの直下の `CLAUDE.md` が持ちます。この文書は、使う人のための説明です。

## 入っているもの

| 置き場 | 中身 |
|---|---|
| `CLAUDE.md` | 一式の責務の定義と、置き場の地図 |
| `.claude/rules/slide-writing/` | 規約。`design-principles.md`(見た目の原則)、`content-principles.md`(話の組み立て、結論の一文、言葉、数字の原則)、`value-names.json`(値の名前の一覧) |
| `design-systems/<名前>/` | デザインシステム。値(`tokens.json`)、部品と意図(`parts.json`)、型ごとのテンプレート(`templates/`)、見本のデータ(`examples/`)、そのデザインシステムだけの NG 例(`ng-examples/`)。今は、`blue-and-gray`(青と灰)と `ink-and-red`(墨と赤)と `navy-and-violet`(紺と紫。デジタル庁のイラストを置く型を持つ)の 3 つ |
| `design-systems/ng-examples/` | どのデザインシステムにも共通の NG 例(画像と一覧) |
| `tools/` | 描く、測る、検査する道具。コマンドは `tools/README.md` |
| `.claude/skills/creating-claude-design-slides/` | スライドを作るスキル |
| `.claude/skills/exporting-slides-to-html/` | 全ページを 1 つの HTML にまとめるスキル |
| `output-slides/<作る日>_<資料の名前>/` | 作ったスライド。元の資料、データ、`.dc.html`、`canvas.json`、確認用の画像 |
| `payload/` | ユーザーが公開すると選んだ成果物への symlink |
| `docs/` | 経緯の記録、確かめの記録 |

## 前提

- Claude Code。ツール `Artifact` で、型「Design」の Artifact を作れること(Claude Code の CLI か、デスクトップのアプリで始めた会話)。
- Node.js。`tools/` は、外のパッケージを使わない。
- Playwright の MCP のツール `browser_run_code_unsafe`。スライドを測って画像にするときと、まとめた HTML を開いて確かめるときに使う。入れていないときは、スキルが入れてよいかを聞く。入れるコマンドは `claude mcp add playwright npx @playwright/mcp@latest`。
- このツールは、AI が書いたコードを、利用者の権限で、Claude Code のサンドボックスの外で動かせる(Playwright MCP の説明では RCE 相当)。使うたびに許可の確認が出たら、実行するコードを見て判断する。

## 使い方

Claude Code に、次の形で依頼する。

**スライドを作る**
- 依頼の例: 「<資料のファイル>を、青と灰で、数枚のスライドにして」
- 動くスキル: creating-claude-design-slides
- 結果: Claude デザインの URL、`output-slides/` の資料のフォルダ、確認用の画像、チェックツールの結果
- デザインシステムの名前が依頼の文にないとき、スキルは、`design-systems/` の一覧を見せて、ユーザーの選択を待つ。

**テンプレートにない型を足す**
- 依頼の例: 「この内容に合う型のテンプレートを足して、スライドにして」
- 動くスキル: creating-claude-design-slides
- 結果: そのデザインシステムの `templates/` に、新しい型が足される

**部品の理由を聞く**
- 依頼の例: 「このスライドの、この棒の色の理由を教えて」
- 動くスキル: creating-claude-design-slides
- 結果: 部品の意図(`parts.json`)、値の理由(`tokens.json`)、数字と言葉の出どころ(データの `from`)から答える

**1 つの HTML にまとめる**
- 依頼の例: 「このスライドを HTML にして」
- 動くスキル: exporting-slides-to-html
- 結果: 資料のフォルダの `<資料の名前>スライド.html`。ブラウザで 1 ページずつ切り替えて見られる

道具のコマンド(描く、測る、検査する、型の一覧を出す)は、`tools/README.md` にある。

## デザインシステムを足すとき

読むもの:

- `.claude/rules/slide-writing/design-principles.md`: 見た目の原則。デザインシステムは、これを 1 つの見た目として実装する。
- `.claude/rules/slide-writing/value-names.json`: 値の名前の一覧。デザインシステムは、このすべての名前に、`tokens.json` の `values` で値を定義する。
- 今あるデザインシステムの 1 つ(`design-systems/blue-and-gray/` か `design-systems/ink-and-red/` か `design-systems/navy-and-violet/`): 置き場の構成と、ファイルの形の手本。

足したあとに、`node tools/check.js --design-system <名前>` を実行する。値の名前、部品の意図、テンプレート、見本のデータを確かめ、合格(終了コード 0)になるまで直す。

## テンプレートを足すとき

読むもの:

- `.claude/skills/creating-claude-design-slides/SKILL.md` の節「テンプレートにない型のとき」: 足す手順。
- `.claude/rules/slide-writing/design-principles.md`: 足した型を照らす原則。
- そのデザインシステムの `templates/` の、いちばん近い型のファイル: 写す元。

足すもの: `templates/<型の名前>.js`(`when`、`parts`、`schema`、`render`)、新しい部品の `parts.json` の行(`name` と `intent`)、新しい値の `tokens.json` の項目、`examples/<型の名前>.data.json`。

## イラストの著作権

`design-systems/ink-and-red/illustration/` と `design-systems/navy-and-violet/illustration/` の PNG 40 点(2 つのフォルダは、同じファイルを持つ)は、デジタル庁の[イラストレーション・アイコン素材](https://www.digital.go.jp/policies/servicedesign/designsystem/Illustration_Icons)のファイルを、変えずに置いたものです。著作権はデジタル庁にあり、利用の条件は、同じフォルダの `LICENSE.txt` に従います。編集、加工して使うときは、出典と編集の内容の表記が要ります。

## 作ったスライドの置き場と、公開するものの選び方

作ったスライドと、公開するものを、2 つのフォルダに分けて置く。

- `output-slides/<作る日>_<資料の名前>/`: 作るスキルが作ったファイルと、HTML にするスキルが作った、全ページを 1 つにまとめた HTML の置き場。このフォルダは公開しない。
- `payload/<作る日>_<資料の名前>/`: ユーザーが公開すると選んだ成果物だけを、`output-slides/` のファイルへの symlink で置く。公開の側は、作ったスライドのうち、このフォルダだけを写す。

公開するときは、次の順で進める。

1. `payload/` の下に、選んだファイルへの相対パスの symlink を置く。
2. 公開の側の承認の記録に、そのファイルの行を足す。
3. 公開の側で同期のスクリプトを走らせ、写したものをコミットして push する。

公開の側は、資料のほかに、一式の `.claude/skills/`、`.claude/rules/`、`design-systems/` の下のデザインシステムごとのフォルダ、`tools/`、この `README.md`、`CLAUDE.md` を、コミットした状態で写す。`ng-examples/` と、`.gitignore` にある見本の描いたファイル(`.dc.html`、`canvas.json`、`確認用の画像/`、`測った値.json`)は、写さない。
