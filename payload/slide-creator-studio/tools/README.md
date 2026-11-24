# tools

スライドを描く道具と、機械のチェックツール。Node.js だけで動き、外のパッケージを使わない。
`--root <置き場>` を付けると、`design-systems/` と `.claude/rules/slide-writing/value-names.json` を探す置き場を替える(省くと、`tools/` の 1 つ上)。

## 数枚作るときの呼び方の順

```
node tools/templates.js <デザインシステムの名前> --brief            # 0. 型を決める: 型の名前と when の一覧(--only <型> で、欄の一覧)
node tools/render.js output-slides/<日>_<資料の名前>                 # 1. 描く: .dc.html と canvas.json を書く
node tools/measure.js output-slides/<日>_<資料の名前>                 # 2. 測る: 測るスクリプトの全文を標準出力に出す
#    その全文を、Playwright の MCP のツール browser_run_code_unsafe の code に、そのまま渡す(画像と、短いまとめと、不合格の一覧が返る)
#    スクリプトが、返す JSON と同じ中身を <資料のフォルダ>/測った値.json に自分で書く(AI は、返った値を書き写さない)
node tools/check.js output-slides/<日>_<資料の名前> --measured output-slides/<日>_<資料の名前>/測った値.json   # 3. 検査: 合格 0、不合格 1
node tools/check.js --design-system <名前>                            # デザインシステムを足した、直したとき
```

## render.js

- コマンド: `node tools/render.js <資料のフォルダ>`
- 入力: 資料のフォルダの `deck.json` と `<名前>.data.json`。`design-systems/<designSystem>/` の `tokens.json`、`templates/<型の名前>.js`、`frame.js`
- 出力: 資料のフォルダの `<名前>.dc.html` と `canvas.json`
- 流れ: スライドごとに、テンプレートの `render(data, tokens, h)` を呼び、返った `{css, body}` を `frame(data, deck, tokens, rendered)` に渡し、返った HTML を書く。

## measure.js

- コマンド: `node tools/measure.js <資料のフォルダ> [--images <画像のフォルダ>]`
- 入力: `deck.json`、`<名前>.dc.html`(先に render.js を回す)、`tokens.json`(スライドの大きさと、下限の値)、`parts.json`、`value-names.json`
- 出力(標準出力): ブラウザの中で動くスクリプトの全文。スクリプトは、測った値の JSON を `<資料のフォルダ>/測った値.json` に、ブラウザのダウンロードの保存(`saveAs`)で書く(`browser_run_code_unsafe` の中では `require` と `import` が使えないため)。スライドの大きさ、下限の値、`.dc.html` と画像のパスは、埋まっている。雛形は `tools/measure-page.js`。
- スクリプトが返す JSON(短い形): `{"slides": {<名前>: {out, lang, fonts, brokenImages, elements, conclusionLines, emphasisCount, frame, fullWidthExempt, fullWidth, errorCount, errors: [{check, message}]}}}`。検査は、ブラウザの中で、`lib.js` の `measuredErrors` が行う。画像は `<資料のフォルダ>/確認用の画像/<名前>.png`。
- 測る要素は、`data-part` か `data-role` を持つ要素。外側はクラス `s`、本文領域は `bd`、結論の一文は `cc`。`frame` は、骨組みの要素(`data-part` が「資料の名前とタイトル」「結論の一文」「ページ番号」「本文領域」)の上端と左端。`fullWidth` は、`data-full-width` を持つ要素の箱 [左, 上, 右, 下]。文字の箱は、行の高さ(line-height)の箱で、字の形の箱でない。

## check.js

- コマンド: `node tools/check.js <資料のフォルダ> [--measured <測った値の JSON>]`(スライドの検査)
- コマンド: `node tools/check.js --design-system <名前>`(デザインシステムの検査)
- 出力: 標準出力に `{"ok": true|false, "errors": [{"slide", "check", "message"}]}`。終了コードは、合格 0、不合格 1。
- 検査: データが schema に合う(欄、型、字数と個数の上限)、数字が `from` の見出しの節にある、データが色や大きさを持たない、`data-part` が `parts.json` にある、測った値の検査(文字の大きさ、コントラスト比、はみ出し、あふれ、重なり、結論の行数、強調の数)、デザインシステムの検査(値の名前、部品の意図、テンプレート、見本のデータ)。
- コードの見た目の数の検査(`code-values`。デザインシステムの検査): `base.css` の、文字の種類のクラス(`.t-<文字の種類>`)の大きさ、太さ、行の高さが、値「文字の大きさ.<文字の種類>」「文字の太さ.<文字の種類>」「文字の行の高さ.<文字の種類>」と同じであること。そのほかの px の数が、直後のコメントに値の名前を持ち(`8px/*間隔.軸と軸の値*/`)、その値と同じであること。値から計算した数は、コメントに、値の名前を「 + 」「 - 」でつないだ式を持つ(`31px/*カードの左右の余白 - カードの枠線の太さ*/`)。色コードが、`tokens.json` の色の値にあること。`*.js` と `templates/*.js` が、px の数、font-weight の数、色コード、計算に使う 2 桁以上の数を、直に持たないこと(値は `V('<値の名前>')` で引く。値でない数の行は、行のコメントに「値でない: <理由>」を持つ)。
- 意図の文が言う値の検査(`intent-values`。デザインシステムの検査): `parts.json` の意図の文が言う px の数と色コードが、`tokens.json` の値にあること。同じ数の値が 1 つでもあれば合格にするので、その値が、その部品の値であるかは、AI が読んで確かめる。
- 部品の実装の検査(`part-implemented`。デザインシステムの検査): `parts.json` の部品が、デザインシステムのコード(`*.js`、`templates/*.js`)の `data-part` にあること。コードを持たない部品は、`parts.json` の項目に `"template": false` を持つ。
- タイトルの検査(`title-source`): データの `section` が、元の資料の全文(見出しの行を含む)に、空白と読点を外した文字列(`norm`)のままで含まれることを確かめ、テンプレートが `sectionFixed`(決まったタイトル。`summary` は「まとめ」、`next-actions` は「次のアクション」)を持つときは、`section` が `sectionFixed` と同じであることを確かめる。
- 骨組みの位置の検査(`frame-position`): 全スライドで、骨組みの要素の上端と左端が、最初のスライドと同じ(許容 1px)。
- 図の幅の検査(`full-width`): テンプレートが、本文領域の幅いっぱいにする要素に属性 `data-full-width` を付ける。スライドごとに、その要素が 1 つ以上あり、左端が本文領域の左端、右端が本文領域の右端(許容 1px)にそろう。幅いっぱいの要素を持たない型は、テンプレートが `fullWidth: false` と理由 `fullWidthWhy`(文字列)を持つときだけ、対象の外とする。
- 表記の検査(`notation`): データの結論の一文と、`content` の text の欄の、数字と前後 2 字の切れ端が、元の資料と空白の有無だけが違うとき、不合格。
- 字数の数え方: デザインシステムの `frame.js` が `countChars(text, tokens)` を出していれば、それを呼ぶ。出していなければ、改行を数えず、半角の英数字を、値「数字の半角の幅(字の大きさに対する比)」の字として数える。
- 値の名前の形: `文字の大きさの下限.<data-role>`、`コントラスト比の下限`(`コントラスト比の下限.<data-role>` があれば先に使う)、`結論の一文の行数の上限`、`強調の要素の数の上限`、`結論の一文の字数の上限`、`数の桁区切り`。この名前は `tools/lib.js` の `LIMIT_NAMES` と `SEPARATOR_NAME` と、`tools/check.js` の冒頭の `NAME` が持つ。
- `--measured` の JSON は、measure.js のスクリプトが返す短い形(`errors` を持つ)でも、`elements` を持つ全部入りの形でも読む。

## templates.js

- コマンド: `node tools/templates.js <デザインシステムの名前> [--brief] [--only <型の名前>[,<型の名前>…]]`
- 出力(標準出力の JSON): テンプレートごとに、型の名前、`when`、使う部品、見本のデータのファイル、`schema` の欄の一覧(欄の道筋、型、必須か、上限の値の名前と値)。`--brief` は、型の名前と `when` だけ。`--only` は、その型だけ。
- 使う場面: 型を決めるときと、データを書くときに、テンプレートのファイルを全部読まずに済ませる。
- 画像の欄(型 `image`)は、欄の一覧に、`shape`(`src` と `alt` の書き方)を添えて出る。

## 画像の欄(型 image)

- データの形: `{"src": "<画像のファイルのパス>", "alt": "<代わりの文>"}`。`src` は、資料のフォルダからの相対パスか、デザインシステムの素材の `ds:illustration/<名前>`。対応する拡張子は、png、jpg、jpeg、gif、svg、webp。
- 描くとき: テンプレートの `render` が、ヘルパー `h.image(img, attrs)`(画像を data URI(base64)にした `<img>` の HTML)と `h.imageSize(img)`(元の大きさ)を呼ぶ。`.dc.html` は、外のファイルを指さない。
- 検査: `check.js` が、欄の項目(`src`、`alt` だけ)、`alt` が空でないこと、`src` のファイルがあることを確かめる(`schema`、`image`)。

## extract.js

- コマンド: `node tools/extract.js <.dc.html のファイル> [--out <フォルダ>]`
- 入力: `.dc.html`。デザインシステムの `frame.js` が、`<script type="application/json" data-slide-data>` に、そのスライドの中身のデータ(`.data.json` の全文。`<` は `<`)を埋め込む。`<body>` の終わりの前、`x-dc` の外にあり、見た目と、measure.js の測りには影響しない。
- 出力: `<名前>.data.json`(`--out` のフォルダ。省くと、`.dc.html` と同じフォルダ)。
- 埋め込みのない `.dc.html`(古い作りのスライド)は、標準エラーに「このスライドは、中身のデータを持たない。元の資料から作り直す」と出し、終了コード 1 で終える。
