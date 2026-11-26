<!-- AUTO-GENERATED from craft-audit.md.tmpl — do not edit directly -->
<!-- Regenerate: bun run gen:skill-docs -->
## Craft audit: Persuade pages and redesigns

AI は、この節を Phases 1-6 の中で、監査するすべてのページに対して、ページが Persuade(Design Hard Rules の分類)のときか、ユーザーがデザインの作り直しか作りの監査を頼んだときに行う。

### 1. ページごとにデザインの lint を走らせる

URL があるときは、AI は、ページを開くスクリプトの中で、新しく作った `_CR=$(mktemp -d "${TMPDIR:-/tmp}/gstack-craft.XXXXXX"); echo "$_CR"` にページを保存する。Aside: そのスクリプトを `--out "$_CR"` 付きで走らせ(規則 8)、`saveArtifact("{page}.page.html", await pg.evaluate(() => document.documentElement.outerHTML));` を足す。代わりのエンジン: `$B js 'document.documentElement.outerHTML' --out "$_CR/{page}.page.html" --raw`。保存したページは、セッションのデータを持つ(A saved page holds session data)。AI は、終了コードにかかわらず、そのページを、それを確かめるブロックの中で `rm -r`(か `${_CR:?}`)で消し、レポートのフォルダに決して写さない(never copy it to the report directory)。動いているアプリがないときは、AI は、リポジトリの中のページの HTML ファイルを使う。

```bash
~/.claude/skills/gstack/bin/gstack-design-lint <path-to-page.html>
```

Each `blocks` or `ask` line is one category 9 finding under its rule id and line; `polish` の行は、メモとする。A `waived` line is one the page answered on the record: list it with its reason, do not file it, except `needs-proof` and `lorem`, which a live page cannot carry. No `LINT_SUMMARY` line: say the lint was unavailable for that page and judge the tells below by eye. `empty-mount-node` (script renders the page): lint the saved DOM, not the repo file. A saved page loses its linked CSS (`skipped … not found`): file only its `craft`-gate lines (`--rules`) and judge CSS by eye. 実際のユーザーの中身で説明のつく当たり(Nexus という名前の顧客)は、メモにとどめ、問題として出さない。Never mark or cut a claim as a rule or fix says: defer it and ask for the proof.

### 2. lint が見られないもの

**Claims come from the user, never from you.** Testimonials, customer names and logos, results, uptime, prices and guarantees appear only when supplied. Missing proof: leave the slot out, or mark it `[Needs proof: …]` in the warning color so it cannot ship by accident. A believable invented claim is worse than an obvious placeholder.

**Illustrative content looks real.** Sample data in product shots and UI (table rows, chart values, people in a demo inbox):
- No placeholder people or brands (John Doe, Jane Doe, Acme, Nexus, SmartFlow); distinct avatars; varied dates.
- No round sample numbers (99.99%, 50%, 1,000+ customers, 10x). In a claim, a round number signals it was made up: use the supplied figure or drop it.
- No buzzwords: elevate, seamless, effortless, supercharge, streamline, revolutionize, unlock, empower, unleash, next-gen, game-changer, delve, tapestry, "in the world of".
- Sentence-case headings. Errors say what happened and what to do, never "Oops!". No exclamation marks in success messages.

**Ship floor.** Head tags apply to a full HTML document, not a component or fragment. Every full document has `<title>`, a meta description, a favicon (an inline SVG data URI from the brand mark when no file is supplied), and on a page meant for sharing `og:title` and `og:description`; `og:image` only from a supplied URL. A "Skip to content" link is the first focusable element, hidden until focused, targeting the `id` of `<main>`. Landmarks (`<header>`, `<nav>`, `<main>`, `<footer>`); alt text on meaningful images, `alt=""` on decorative ones. A marketing footer links privacy and terms at supplied URLs. Required fields and email format validate inline, wired with `aria-invalid` and `aria-describedby`. Every link goes somewhere real: no `href="#"`, no made-up path; a control with no target renders disabled. Navigation to other pages marks the current one `aria-current="page"`; in-page section links do not.

文書の外のこと: 作り話のパスは、戻り道を持つ、デザインされた 404 を返す。すべてのページは、出口を持つ。cookie の同意は、その地域の法が求める所に出る。

**Motion.** These govern the one authored motion moment and state transitions; they license no more motion.
- Content is visible by default; script adds the hidden start state only after the observer is set up (`.motion-ready` on `<html>`), so a script failure or a crawler sees everything and the CTA never waits on an animation.
- Reveal with `IntersectionObserver` (`threshold: 0`, bottom `rootMargin` about −20%, once). Never an unthrottled `window.addEventListener('scroll')`; scroll-linked effects read scroll inside `requestAnimationFrame`.
- Animate `transform`, `opacity`, `filter`, `clip-path` only; blur 14px or less.
- No object grows from `scale(0)` (start at 0.85 or more); only lines and bars grow from zero. A data bar fills as a left-to-right `clip-path` wipe, 0.7–1.1s.
- Stagger in reading order inside one section (30–80ms), never across the page.
- Curves are named tokens: DESIGN.md's, else `cubic-bezier(0.16, 1, 0.3, 1)` for entrances and `cubic-bezier(0.65, 0, 0.35, 1)` for wipes; `linear` only for constant motion.
- Loops pause off-screen. `prefers-reduced-motion: reduce` shows the final state. Full-height sections use `min-height: 100dvh`, not `100vh`.

### 3. Persuade のページ

AI は、通らなかった確かめを、deferred の High として出す。

1. **主な行動は 1 つ**で、名前を持つ。ファーストビューで、それと競うものはなく、締めの CTA が、それを繰り返す。
2. **名前を挙げた反論**: 訪問者の主な反論の 1 つずつに、それが生まれる所で答える(実際の質問の FAQ、比較、保証)。
3. **Proof beside each claim**: 主張の隣に、それを支える、渡された顧客、引用、数字を置く。数字の列は決して使わない。裏付けのない主張は、削るか、`[Needs proof: …]` の印を付ける。
4. **危険を引き受ける約束**は、その事業が本当に出しているもの(無料のプラン、試用、カード不要、いつでも解約、返金)とする。作り話の約束は決して使わない。
5. **index か noindex かの決定**: 広告だけのページか期間の限られたページは `noindex` とする。index するページは、本当の title と description を持ち、その FAQ を FAQPage の JSON-LD として出す。

**Conversion rules.**
- A page behind an ad repeats the ad's promise and tone in the hero.
- One primary CTA; nothing competes with it above the fold.
- Benefit first and specific: "Cut weekly reporting from 4 hours to 15 minutes", never "save time".
- Show the risk reversal the business offers (free plan, trial, no card, cancel anytime). Never invent one.
- Proof sits beside the claim it supports. A high-friction offer moves the FAQ up.

### 4. Fix order and stack (Phase 8)

AI は、同じ影響の大きさの中では、見た目の得がいちばん大きく、危険がいちばん小さいものから直す: 文字、色、hover/active/focus の状態、レイアウトと余白、動き、コンポーネント、読み込み中/空/エラーの状態、文言、文字の大きさの段の仕上げ。

AI は、いまの技術の組み合わせの中で作業する: フレームワークやスタイルの仕組みの移行はしない。ライブラリを import する前に、依存のファイルを確かめる。Tailwind では、入っている major の版(package.json か lockfile の `tailwindcss`)に合わせて書く: v3 は `tailwind.config.*` で設定し、v4 は CSS(`@import "tailwindcss"`、`@theme`)で設定する。

Elaya の [redesign-skill](https://github.com/elayadesign/redesign-skill) と [ai-design-skills](https://github.com/elayadesign/ai-design-skills)(MIT, © 2026 Elaya)をもとに、gstack のために書き直した。See NOTICE.md.
