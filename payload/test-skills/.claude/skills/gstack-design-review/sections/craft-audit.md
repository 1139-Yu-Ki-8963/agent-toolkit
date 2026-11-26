## 作りの監査: Persuade のページと作り直し

AI は、この節を Phases 1-6 の中で、監査するすべてのページに対して、ページが Persuade(SKILL.md の「デザインの厳しい決まり」の分類)のときか、ユーザーがデザインの作り直しか作りの監査を頼んだときに行う。

### 1. ページごとに、描かれた DOM を読む

URL があるときは、AI は、ページを開いた状態で、`browser_snapshot` と、次の関数を `browser_evaluate` で走らせ、ページの作りを読む(ファイルには保存しない。保存するときは、SKILL.md の「秘密の値を伏せる決まり」に従う):

```js
() => JSON.stringify({
  title: document.title,
  description: document.querySelector('meta[name=description]')?.content ?? null,
  favicon: !!document.querySelector('link[rel~=icon]'),
  og: [...document.querySelectorAll('meta[property^="og:"]')].map(m => m.getAttribute('property')),
  firstFocusable: (() => { const e = document.querySelector('a[href], button, input, [tabindex]'); return e ? e.outerHTML.slice(0, 120) : null; })(),
  landmarks: ['header', 'nav', 'main', 'footer'].filter(t => document.querySelector(t)),
  imgsNoAlt: [...document.images].filter(i => !i.hasAttribute('alt')).map(i => i.src.split('?')[0]).slice(0, 20),
  deadLinks: [...document.querySelectorAll('a[href="#"], a:not([href])')].map(a => a.textContent.trim().slice(0, 30)).slice(0, 20),
  ariaCurrent: [...document.querySelectorAll('[aria-current]')].map(e => e.textContent.trim().slice(0, 30)),
  headings: [...document.querySelectorAll('h1,h2,h3')].map(h => h.textContent.trim().slice(0, 60)),
  buttons: [...document.querySelectorAll('button, a[role=button], .btn')].map(b => b.textContent.trim().slice(0, 30)).slice(0, 30),
  text: document.body.innerText.slice(0, 4000)
})
```

動いているアプリがないときは、AI は、リポジトリの中のページの HTML ファイルを Read で読む。スクリプトがページを描く(本体が空の mount の要素だけを持つ)ときは、ファイルでなく、描かれたページを読む。

AI は、読んだものを、SKILL.md のチェックリストの分類 9 の型と、下の「作りの観点の一覧」と、「2. 型の一覧では見えないもの」の観点に照らす。

#### 作りの観点の一覧

この一覧は、SKILL.md のチェックリストに無い観点を、`[名前] 何を見るか → 既定の直し` の形で並べる。段は、**High**(当たれば High の問題)、**Medium**(当たれば Medium の問題。ページの事情で説明がつくときは、理由を付けて免除してよい)、**Polish**(メモ。成績に入れない)の 3 つである。数の観点は、`browser_evaluate` で計算された値を読んで確かめる。

色と面:
- High [purple-blue-gradient] 紫から青、紫からピンク、暗い地のシアンのグラデーション → アンカーの色相 1 つと単色の文字
- High [pure-black-white] トークンの外の色としての #000 か #fff → アンカーの色相に寄せる(彩度 0.005 以上)
- Medium [absolute-surface-token] 真っ黒か真っ白になる面のトークン → 紙の色を色付けする
- Medium [zero-chroma-neutrals] 彩度 0 の oklch() の無彩色 → 無彩色に彩度 0.005 以上
- Medium [accent-footprint] 1 画面の約 5% を超えるアクセントの色 → アクセントを操作と 1 つの信号に戻す
- Medium [glow-wash] ぼかした玉、円い光の輪、ずれのない色の光 → 単色か粒子の面。高さは明るさで、影はずれとぼかしで
- Medium [framework-palette] フレームワークの既定のパレット(Tailwind の indigo-500、slate-900 など) → ページのために OKLCH で混ぜた色

文字:
- High [italic-word-in-heading] ローマン体の見出しの中の、イタリックの 1 語 → 改行するか、見出し全体を 1 つの組み方に
- Medium [accented-word] 色、太さ、蛍光、下線で 1 語だけ目立たせた見出し → 見出し全体を 1 つの組み方に、改行、2 行目を別の大きさに
- High [caps-leading] 折り返しうる大文字の見出しの行の高さが 1.0 未満 → 1.0 以上(1.02〜1.08 を勧める)
- Medium [caps-lockup-leading] 1 行の大文字の組の行の高さが 1.02 未満 → 1.02 にするか、幅 320px で折り返さないことを確かめる
- Medium [monospace-costume] 中身がコードでないラベル、注記、小さな文字の等幅 → 本文の書体で、1 段小さく、ふつうの大文字小文字で
- High [wide-tracking] 大文字にしたか 0.03em を超えて字間を空けた小さな文字のラベル → 本文の書体で、1 段小さく、文の形で、字間なし

構造とレイアウト:
- Medium [template-cards] 同じ 3 つの、見出しの上のアイコンの札、角の丸い札の中のアイコン、太い色の横の縞 → 幅と高さを変える、アイコンは行の中に、細い枠か枠なし
- High [vh-height] vh で高さを決めたヒーロー → dvh か svh
- High [raw-spacing] `--space-*` のトークンがあるのに、直に書いた padding、margin、gap → トークン
- Medium [off-scale-spacing] ページの段から外れた余白 → 段に乗せる(目の補正は 3 か所まで)
- Medium [overflow-x-unclipped] html と body に overflow-x がない、か 100vw の幅 → 両方に `overflow-x: clip`、幅は 100%
- Medium [hero-balance] ヒーローの中身が画面の中央から外れる、か絵が文から離れている → 中身を画面の中央に、絵を文の横に
- High [hero-fold] 幅 1280 で、見出しの下端かヒーローの最初の操作が、800px の折り目より下 → 見出しの大きさと行の高さを詰める、リードを 2 行に、padding を削る
- High [wide-container] 1920×1080 で、入れ物に max-width がない、左右の余白が 120px 未満、グリッドの列が増える → 1360〜1520px で止めて中央に、列の数を保つ
- High [bare-fr-track] 画像を持つグリッドの列が素の 1fr → `minmax(0, 1fr)`
- High [display-head-unwrapped] 見出しに `overflow-wrap: break-word` と `min-width: 0` がない → 両方を付ける
- High [radio-tab-jump] JS の守りのない、`position: absolute; top: 0` の CSS だけのラジオのタブ → ラジオを流れの中に大きさ 0 で置くか、`preventScroll` の処理
- High [double-sticky] `position: sticky; top: 0` の要素が 2 つ → 2 つ目は `top: var(--banner-height)`
- Medium [screen-word-budget] 900px の 1 画面に約 80 語を超える文、か操作の前に 3 つ以上の文の塊を持つヒーロー → 見出し、1 文、操作。区分は、見出しの塊、そのあとに構図
- Medium [section-gap] 幅 1440 で区分の間が 120px 未満、すべての間が同じ、か 10 以上の区分 → 120px 以上で変化を付ける、1 ページに 6〜9 区分
- Medium [heading-rhythm] 見出しが、導く区分より、前のものに近い → 見出しの上の余白を、下の 2 倍以上に
- Medium [cramped-padding] 塗った箱の横から 8px(か 0.5em)より近い文字 → 箱に padding、16px の余白
- Medium [thin-section] ヒーローの下の、広い画面に細い本文だけの、重さのない区分 → 本文を広げる、絵を足す、言い切りを置く、区分をまとめる
- Medium [small-section-heads] 幅 1440 で、ヒーローの下の h2 の中央の値が 40px 未満 → h2 を区分の大きさに、項目の題を題の大きさに
- Medium [dead-band] ヒーローのいちばん下の中身と折り目の間に、160px を超える何もない帯 → 中身を中央に、絵か見出しを大きく(文で埋めない)
- Medium [hand-drawn-svg] 120px 以上で、3 つ以上の曲線か塗りを持ち、文字のないインラインの SVG(手で描いた絵) → 写真、作ったプロダクト、大きな文字
- Medium [empty-picture] 300×200px 以上の、色の面のほかに何も見せない枠か、グラデーションの塊 → ユーザーの画像、出典のある写真、本物のプロダクト
- Medium [counting-marks] 数を表す、24 個以上の同じ印 → 数を文字で書く
- Medium [photo-wall] ヒーローの下で、写真がページの 3 分の 1 を超える → いちばん強い写真を大きく残し、残りは文字、図、プロダクト、表で運ぶ
- Medium [email-band-close] 役目が購読、参加、出席、視聴、来訪でないページが、メールの登録のフォームで終わる → 訪問者が来た目的か、最後の強い区分で終える

飾りと文言:
- High [generic-hero-copy] 埋め草の書き出し("Built for the modern team"、"In today's landscape")か "quietly trusted by" → プロダクトがすることを、その名詞で言う
- Medium [generic-cta-copy] 主な操作の横の、決まりきった 2 つ目の操作(Learn more、Get started、Book a demo) → 操作は 1 つか、行き先に名前を付けた 2 つ目
- Medium [template-footer-line] 決まりきったフッターの行(All rights reserved) → ページ自身の行か、なし
- Medium [template-nav] 反射のナビゲーション(左に文字のロゴ、並んだリンク、右にボタン、下に細い罫) → ナビゲーションを決めて別の形にするか、理由を付けて残す
- Medium [template-footer] 反射のフッター(4 列のリンク、SNS の列、著作権) → フッターを決めて別の形にするか、理由を付けて残す
- High [invented-proof] 作り話の数、推薦の声、ロゴの壁、事例の数 → ユーザーの数、文の枠、か何もなし
- High [drawn-browser-chrome] 手で描いたブラウザのバー(信号の 3 つの丸、URL の札)か OS の窓の題のバー → `<figure>` の中の本物のスクリーンショットか、枠なし
- Medium [device-frame] スマホ、ノート PC、端末、エディタの枠 → 本物の中身を持つ枠を 1 つか、なし
- Medium [imitation-material] プロダクト、写真の縁、物の代わりの、飾った div → 枠の中に作ったプロダクト、本物の素材、か何もなし
- High [template-punctuation] 雛形の約物(中黒でつないだ情報の列、リンクの文に付けた矢印、飾りの状態の点) → 改行、列、細い罫。ラベルには動詞を
- Medium [wireframe-slots] 1 ページに 6 つ以上の空の枠、か 1 行に 4 つ以上 → 文字で組む。残す枠は、本物の写真かプロダクトを持つ
- Medium [repeated-fact] 1 つの事実(価格、時間、数)が 4 つ以上の区分に出る → 事実は、働く所で 1 回だけ言う
- High [fake-send] 通信なしで成功を表示するフォーム → 確かめを行い、送り先がないことを、送り先ができるまで正直に言う

動きと操作:
- Medium [spacing-transition] margin か padding の切り替えの動き → transform
- Medium [hover-tells] すべてのカードに同じ浮き上がり、1 つの要素に 2 つの効果、hover で大きくなる画像、動かない物への hover → 1 つの要素に 1 つの信号を、画像でなく入れ物に
- High [focus-ring-fade] だんだん出る focus の輪 → すぐ出す(outline と box-shadow を transition から外す)
- High [tooltip-focus-delay] focus の遅れが hover の遅れと同じツールチップ → hover は 800〜1000ms、focus は 0
- High [autorotate-no-pause] hover と focus で止まらない、自動で回る中身 → hover と focus で止める。5 秒を超えるときは、見える一時停止の操作
- Medium [missing-states] `:active` か `:disabled` の状態がない → 操作の部品がとりうるすべての状態
- High [autoplay-unmuted] muted のない自動再生の動画 → `autoplay muted loop playsinline`
- High [lazy-lcp] 最初の画像かヒーローの動画に `loading="lazy"` → LCP の画像に `fetchpriority="high"`
- Medium [video-without-poster] poster か優先の指定のない動画 → 付ける
- High [input-state-shift] 崩れる入力の状態(幅の変わる枠、枠で作った focus の輪、不透明度だけの使えない状態) → 変わらない枠、outline、同じ高さ、使えない状態を 3 つの手がかりで
- Medium [control-height] マーケティングのページで、操作の部品の高さが 44〜52px の外 → その範囲の数
- High [content-hidden-at-rest] JavaScript が走るまで中身を隠す表示のクラス → 既定で見せる。`.js` のクラスの下でだけ隠すか、`@starting-style` で見えている状態から動かす

素材とアクセシビリティ:
- High [emoji-decoration] アイコンの代わりの絵文字 → 1 つのアイコンの集まり、自作の SVG、か文字組み
- Medium [two-icon-libraries] 1 ページに 2 つのアイコンの集まり → 1 つにする
- High [unlabeled-decoration] `aria-hidden="true"` もラベルもない、飾りの `<svg>`、`<canvas>`、CSS の絵 → 隠すか、名前を付ける
- High [broken-image] 元のない、か読み込めない `<img>` → 本物のファイル
- High [stock-photo-hotlink] ストックのサイトの写真への直のリンク → ユーザーの画像か、ページに出典を書いた写真
- High [text-occlusion] ほかの要素の下に描かれた文字 → 文字に自分の場所か、覆いの上の自分の面を与える
- High [gray-on-color] 塗りと 1 段しか違わないボタンの文字、か色の付いた面の上の灰色の文字 → 組になる文字の色のトークン
- High [literal-outside-tokens] トークンの外に直に書いた色か font-family → トークンに上げる
- High [button-label-wraps] 折り返すボタンのラベルか主なナビゲーションのリンク → 短くする。`white-space: nowrap`
- Medium [link-wraps] 折り返すフッターのリンク、タブ、パンくず → 短くする
- High [fake-avatar] 作り物の人の顔写真への直のリンク → ユーザーの人、頭文字、か顔写真なし
- Medium [alert] 知らせに `alert()` → 行の中に出す

仕上げ(Polish):
- [two-primary-buttons] 1 ページに 2 つの塗りの主なボタン、か横並び → 塗りの主なボタンは 1 つ。2 つ目は文字か枠の操作に
- [icon-coin] 色の付いた丸の中のアイコン → アイコンを行の中に、むき出しで
- [display-figures-tabular] 等幅の数字のない、大きな数 → `font-variant-numeric: tabular-nums`
- [stamped-recipe] 6 つ以上の selector に押した同じ入れ物の作り方、か操作でない 5 つ以上の要素の丸い札の角 → 作り方を変える。丸い札は操作、タグ、バッジだけに
- [scroll-choreography-mix] 2 つ以上のスクロールの演出の型 → 1 ページに 1 つ
- [stock-person-photo] 人の語を持つストック写真の URL → ユーザーの写真
- [page-invariants] 主なボタンの形、入れ物の幅、列の間、角の丸みがページの中でずれる → それぞれ 1 つの作り方に
- [text-sliver] 幅 1440 で、細く押しつぶされた文の塊 → 塊に場所を与えるか、列をまとめる
- [tiny-slot] どちらかの向きが 40px 未満の枠 → 入れるものに合わせた大きさに
- [font-weight-count] 本文の中で使う 4 つ以上の太さ → 太さは 3 つまで
- [lonely-grid-item] 最後の行に 1 つだけ残るグリッドか折り返しの行 → 数か列を変える
- [justified-text] `hyphens: auto` のない両端揃え → `hyphens: auto` か左揃え
- [missing-lang] lang のない文書 → `<html>` に lang
- [hairline-under-shadow] 1 つの面に、広くやわらかい影と細い枠の両方 → 影か枠のどちらか
- [house-style] 1 ページで 4 つ以上の観点を免除した → その選択を DESIGN.md に書き、あとのページが受け継ぐようにする

ページが描けなかったときは、その観点を「通った」としない。描けなかったことを、報告に書く。当たったものの 1 つずつは、型の名前と、当たった箇所を持つ、分類 9 の 1 件の問題とする。軽いものは、polish の段のメモとする。実際のユーザーの中身で説明のつく当たり(Nexus という名前の顧客)は、メモにとどめ、問題として出さない。AI は、主張を、決まりや直しが言うとおりに印を付けたり削ったりしない。deferred とし、裏付けを求める。

### 2. 型の一覧では見えないもの

**主張は、ユーザーから来る。AI から来ることは決してない。** 推薦の声、顧客の名前とロゴ、成果、稼働率、価格、保証は、渡されたときだけ出す。裏付けがないとき: その枠を外すか、誤って世に出ないように、注意の色で `[Needs proof: …]` の印を付ける。もっともらしい作り話の主張は、明らかな仮の文より悪い。

**例として見せる中身は、本物らしく見せる。** プロダクトの画像と UI の見本のデータ(表の行、グラフの値、デモの受信箱の人):
- 仮の人やブランドを使わない(John Doe、Jane Doe、Acme、Nexus、SmartFlow)。顔写真は 1 人ずつ違え、日付はばらつかせる。
- 切りのいい見本の数を使わない(99.99%、50%、1,000+ customers、10x)。主張の中の切りのいい数は、作り話のしるしである: 渡された数を使うか、外す。
- 宣伝の決まり文句を使わない: elevate、seamless、effortless、supercharge、streamline、revolutionize、unlock、empower、unleash、next-gen、game-changer、delve、tapestry、"in the world of"。
- 見出しは、文の形の大文字の使い方(最初の語だけ大文字)。エラーは、何が起きたかと、何をすればよいかを言い、決して "Oops!" と言わない。成功の言葉に、感嘆符を付けない。

**世に出す最低の線。** head の要素の決まりは、部品や断片でなく、HTML の文書の全体に当てる。すべての文書の全体は、`<title>`、meta の description、favicon(ファイルが渡されないときは、ブランドの印から作ったインラインの SVG の data URI)を持ち、共有するためのページは `og:title` と `og:description` を持つ。`og:image` は、渡された URL からだけとする。「Skip to content」のリンクは、最初に focus できる要素で、focus されるまで隠れ、`<main>` の `id` を指す。ランドマーク(`<header>`、`<nav>`、`<main>`、`<footer>`)を持つ。意味のある画像は代替テキストを持ち、飾りの画像は `alt=""` を持つ。マーケティングのフッターは、渡された URL で、プライバシーと規約へのリンクを持つ。必須の欄とメールアドレスの形は、その場で確かめ、`aria-invalid` と `aria-describedby` でつなぐ。すべてのリンクは本当の行き先を持つ: `href="#"` も、作り話のパスも使わない。行き先のない操作の部品は、使えない状態で描く。ほかのページへのナビゲーションは、今のページに `aria-current="page"` を付ける。ページの中の区分へのリンクには付けない。

文書の外のこと: 作り話のパスは、戻り道を持つ、デザインされた 404 を返す。すべてのページは、出口を持つ。cookie の同意は、その地域の法が求める所に出る。

**動き。** これらは、作った 1 つの動きの見せ場と、状態の切り替えを決める。これ以上の動きを許すものではない。
- 中身は、既定で見えている。スクリプトは、observer を用意したあとにだけ、隠れた始まりの状態を足す(`<html>` の `.motion-ready`)。こうすると、スクリプトが失敗しても、クローラーにも、すべてが見え、CTA がアニメーションを待つことは決してない。
- 表示は `IntersectionObserver`(`threshold: 0`、下の `rootMargin` は約 −20%、1 回だけ)で行う。間引かない `window.addEventListener('scroll')` は決して使わない。スクロールに連動した効果は、スクロールの値を `requestAnimationFrame` の中で読む。
- 動かすのは、`transform`、`opacity`、`filter`、`clip-path` だけとする。ぼかしは 14px 以下とする。
- どの物も `scale(0)` から大きくしない(0.85 以上から始める)。0 から伸びるのは、線と棒だけである。データの棒は、左から右への `clip-path` のぬぐいで、0.7〜1.1 秒で満ちる。
- 時差は、1 つの区分の中で、読む順に付ける(30〜80ms)。ページをまたいで付けることは決してない。
- 曲線は、名前付きのトークンとする: DESIGN.md のもの、なければ、登場に `cubic-bezier(0.16, 1, 0.3, 1)`、ぬぐいに `cubic-bezier(0.65, 0, 0.35, 1)`。`linear` は、一定の動きにだけ使う。
- くり返しの動きは、画面の外で止める。`prefers-reduced-motion: reduce` では、終わりの状態を見せる。画面の高さいっぱいの区分は、`100vh` でなく `min-height: 100dvh` を使う。

### 3. Persuade のページ

AI は、通らなかった確かめを、deferred の High として出す。

1. **主な行動は 1 つ**で、名前を持つ。ファーストビューで、それと競うものはなく、締めの CTA が、それを繰り返す。
2. **名前を挙げた反論**: 訪問者の主な反論の 1 つずつに、それが生まれる所で答える(実際の質問の FAQ、比較、保証)。
3. **主張の隣の裏付け**: 主張の隣に、それを支える、渡された顧客、引用、数字を置く。数字の列は決して使わない。裏付けのない主張は、削るか、`[Needs proof: …]` の印を付ける。
4. **危険を引き受ける約束**は、その事業が本当に出しているもの(無料のプラン、試用、カード不要、いつでも解約、返金)とする。作り話の約束は決して使わない。
5. **index か noindex かの決定**: 広告だけのページか期間の限られたページは `noindex` とする。index するページは、本当の title と description を持ち、その FAQ を FAQPage の JSON-LD として出す。

**成約の決まり。**
- 広告の先のページは、ヒーローで、広告の約束と調子をくり返す。
- 主な CTA は 1 つ。ファーストビューで、それと競うものはない。
- 得を先に、具体的に書く: 「週ごとの報告を 4 時間から 15 分に減らす」。決して「時間を節約する」と書かない。
- その事業が出している、危険を引き受ける約束(無料のプラン、試用、カード不要、いつでも解約)を見せる。決して作らない。
- 裏付けは、それが支える主張の隣に置く。手間の大きい申し出では、FAQ を上に動かす。

### 4. 直す順と、技術の組み合わせ(Phase 8)

AI は、同じ影響の大きさの中では、見た目の得がいちばん大きく、危険がいちばん小さいものから直す: 文字、色、hover/active/focus の状態、レイアウトと余白、動き、コンポーネント、読み込み中/空/エラーの状態、文言、文字の大きさの段の仕上げ。

AI は、いまの技術の組み合わせの中で作業する: フレームワークやスタイルの仕組みの移行はしない。ライブラリを import する前に、依存のファイルを確かめる。Tailwind では、入っている major の版(package.json か lockfile の `tailwindcss`)に合わせて書く: v3 は `tailwind.config.*` で設定し、v4 は CSS(`@import "tailwindcss"`、`@theme`)で設定する。

Elaya の [redesign-skill](https://github.com/elayadesign/redesign-skill) と [ai-design-skills](https://github.com/elayadesign/ai-design-skills)(MIT, © 2026 Elaya)をもとに、gstack のために書き直した。See NOTICE.md.
