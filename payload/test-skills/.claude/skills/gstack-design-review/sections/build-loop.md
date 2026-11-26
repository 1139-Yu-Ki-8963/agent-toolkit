## 組み立てのループ: `--build`

この節は、作っている途中の UI のための、選んだときだけ走る手順である。AI は、画面を作りながら、節(画面の区域)ごとに、ローカルのプレビューで状態ごとのスクリーンショットを取り、画像と DOM を読んで確かめ、直す。この手順は、監査の Phase に代わって走る。この手順は、commit、stash、checkout、reset を一切行わない(この作業の変更は、commit しないまま残る)。人がいない実行では、ユーザーに聞かず、聞くことを「要る入力」として報告に書く。

**7 つの項目**(AI は、スクリーンショットの 1 枚ずつで確かめる):

| # | 項目 | 確かめ方 |
|---|------|------|
| 1 | 行の内側の余白が、1 行のときも 2 行のときも保たれる(2 行以上の行で、文と行の縁の間が 8px 以上) | 画像と、下の関数の `rows` |
| 2 | 隣り合う行の間に、息をする余白がある(ある行の文と次の行の文の間が 16px 以上) | 画像と、下の関数の `gaps` |
| 3 | 説明の文が、上に余白を持ち(一覧の下から 12px 以上)、隣の節と同じ控えめな見せ方をしている | 画像で、隣の節と比べる |
| 4 | 状態の注記は、自分の行に置かれ、注意の見せ方を持つ(名前と同じ太さ、明るさ、大きさで行の中に埋もれない。アイコンか自分の面を持つか、名前より薄く小さい) | 画像 |
| 5 | 見出し、名前、補足が、隣の節と同じ順に上から並んでいる | 画像で、隣の節と比べる |
| 6 | 押せる所が、ゆとりのある大きさを持つ(幅 480px 以下で、行の中の操作の部品が、どちらの向きも 32px 以上) | 下の関数の `small` |
| 7 | 幅 375 で、何もはみ出さない(節の中の要素が画面を越えず、スクロールしない要素が自分の箱からあふれない) | 下の関数の `overflow` |

項目 3 と 5 では、リポジトリの流儀が優先する。AI は、隣の節と比べて判断する。

AI は、項目 1、2、6、7 の数を、対象の節を開いた状態で、次の関数を `browser_evaluate` で走らせて読む(`SECTION` は、対象の節の CSS selector):

```js
() => {
  const root = document.querySelector('SECTION');
  if (!root) return JSON.stringify({ error: 'section not found' });
  const rr = root.getBoundingClientRect();
  const kids = [...root.querySelectorAll('li, [role=row], tr, [role=listitem]')];
  const rows = kids.map(e => { const r = e.getBoundingClientRect(), s = getComputedStyle(e); return { text: e.textContent.trim().slice(0, 30), top: Math.round(r.top), bottom: Math.round(r.bottom), padTop: s.paddingTop, padBottom: s.paddingBottom }; });
  const gaps = rows.slice(1).map((r, i) => r.top - rows[i].bottom);
  const small = [...root.querySelectorAll('a, button, input, select, [role=button]')].map(e => ({ e, r: e.getBoundingClientRect() })).filter(x => x.r.width > 0 && (x.r.width < 32 || x.r.height < 32)).map(x => ({ text: (x.e.textContent || x.e.getAttribute('aria-label') || '').trim().slice(0, 30), w: Math.round(x.r.width), h: Math.round(x.r.height) }));
  const overflow = [...root.querySelectorAll('*')].filter(e => e.getBoundingClientRect().right > innerWidth + 1 || e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflowX === 'visible').map(e => e.tagName + '.' + [...e.classList].join('.')).slice(0, 20);
  return JSON.stringify({ section: { w: Math.round(rr.width), h: Math.round(rr.height) }, rows, gaps, small, overflow, pageScrollX: document.documentElement.scrollWidth > innerWidth });
}
```

数は、判断の材料である。AI は、数と画像の両方を見て、項目ごとに「通る」か「通らない」かを決める。

### 1. 状態の一覧

AI は、実行のフォルダを作る:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RUN="$ROOT/test-reports/gstack-design-review/design-build-run-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN" && chmod 700 "$RUN" && echo "RUN: $RUN"
```

ブロックは、毎回新しいシェルで走る。`<run-dir>` は、表示された `RUN:` のパスである。AI は、仕様と差分から `<run-dir>/inventory.json` を Write で書く。中身は、変更が見せうる、シナリオ × 重ねて出るもの × busy、success、error、empty のすべてである。

```json
{"version":1,"within":"<節の CSS selector>","fixtures":"<リポジトリからのフィクスチャのフォルダ>","touched":["<自分で作った、まだ git にないファイル>"],
 "states":[{"name":"owner","url":"http://127.0.0.1:5300/settings?as=owner","expect":"<この状態だけが描く selector>"},
           {"name":"remove-confirm","mode":"screenshot","steps":"click Remove on the second row"}]}
```

URL の状態は、`?as=<scenario>` と、その状態がデータ付きで描かれたことを示す `expect` の selector を持つ。クリックが要る状態は `"mode":"screenshot"` とし、`steps` の操作のあとに撮る。

### 2. プレビューを用意する(どのラウンドよりも前)

AI は、アプリのプレビューを、loopback(127.0.0.1 か localhost)だけで動かす。ほかのホストは、ユーザーが名前を挙げて許したときだけ使う。AI が自分で足すことは決してない。

API の答えを状態ごとに決めたいときは、AI は、この SKILL.md と同じフォルダの `templates/preview-fixtures.mjs` を使ってよい。このスクリプトは、アプリの Vite(`--root` の `node_modules` から解決する。入れることはしない)か、`--static` のときは素のファイルのサーバーで、API の前置き(既定は `/api/`)の下の要求を、`<fixtures>/<scenario>.json` からだけ答える。答えのない要求は、本番のバックエンドに渡さず、501 を返す。

```bash
P="<この SKILL.md のフォルダ>/templates/preview-fixtures.mjs"
node "$P" start --root . --fixtures <フィクスチャのフォルダ> --port 5300 --state "<run-dir>/preview" &
# PREVIEW: ready url=http://127.0.0.1:5300/ mode=vite state=... log=...
node "$P" stop --state "<run-dir>/preview"
```

フィクスチャのファイルは、シナリオごとに 1 つで、次の形とする(`:name` は 1 つの区切りに当たる。`delay_ms` は busy の状態を見せる):

```json
{ "version": 1, "routes": {
  "GET /api/members": { "status": 200, "json": [{ "name": "Dana Whitfield", "role": "Owner" }] },
  "GET /api/members/:id": { "status": 200, "json": { "name": "Dana Whitfield" }, "delay_ms": 600 },
  "DELETE /api/members/:id": { "status": 409, "json": { "error": "The only owner cannot be removed." } } } }
```

AI は、`browser_navigate` で、状態の 1 つずつの URL を開き、`expect` の selector が出ることを `browser_wait_for` か `browser_evaluate` で確かめる。プレビューが動かないときは、AI は、プレビューを起動し直し、1 回だけ確かめ直す。それでも動かないときは、結果を `unrendered` として終える。

AI は、API の答えがフィクスチャから来ていることを、状態の 1 つずつの origin で、次のコマンドで確かめる。答えが、転送なしの 204 で、ヘッダー `x-preview-fixtures: ready` を持つときだけ、確かめられたとする:

```bash
curl -si "http://127.0.0.1:<port>/api/__preview-fixtures" | head -5
```

確かめられない(どれかの origin が答えない、転送する、`--api` を既定から変えた)ときは、本番のバックエンドに届くかもしれないので、AI は、変えた操作を決して動かさない。

### 3. ラウンド(多くても 3 回)

ラウンド N ごとに、AI は、次を行う:

1. 状態の 1 つずつで、幅 375×812、768×1024、1440×900 の 3 つの幅ごとに、`browser_resize` で幅を変え、秘密の値を伏せ(SKILL.md の「秘密の値を伏せる決まり」)、`browser_take_screenshot` で `filename: "<state>-<width>.png"` を取り、道具の結果が示す保存先から、Bash の `mv` で `<run-dir>/round-N/<state>-<width>.png` へ移す(`"mode":"screenshot"` の状態は、`steps` の操作のあとに撮る。`filename` にパスを渡さないわけは、SKILL.md の Setup の「画像の保存」にある)。2 回目からのラウンドでは、直したファイルをブラウザがキャッシュから読まないように、AI は、状態の URL に `&v=<時刻>`(`date -u +%Y%m%d%H%M%S` の値。URL が問い合わせの文字列を持たないときは `?v=<時刻>`)を足して開く。`?as=<scenario>` は、そのまま残す。
2. AI は、すべての画像を Read で読み、上の関数を走らせ、7 つの項目を確かめる。
3. AI は、変えた操作の 1 つずつを、busy、success、error、立ち直りまで動かし、キーボード(`browser_press_key` の Escape)で閉じて、focus がきっかけの要素に戻ることを `browser_evaluate` の `() => document.activeElement.outerHTML.slice(0, 120)` で確かめる。
4. AI は、ソースとフィクスチャで直す。変更は commit しないまま残す。
5. AI は、ラウンドの結果(状態ごと、幅ごとの、通らない項目)を `<run-dir>/round-N/notes.md` に書く。

描けなかった状態(`expect` の selector が出ない、プレビューが 501 を返した)は、仕掛けの問題であり、ラウンドとは数えない。AI は、原因(フィクスチャの抜けた route、起動していないプレビュー)を直し、その状態を撮り直す。3 回目のラウンドのあとか、それより前に、すべての項目が通ったラウンドのあとに、直すのをやめる。

### 4. 最後の確かめ(読むだけ)

AI は、最後の直しのあとに、何も変えない 1 回の確かめを行う: すべての状態を、すべての幅で撮り直し(ラウンドの手順 1 と同じく、ファイルの名前だけで撮って `<run-dir>/final/` へ移し、URL に `&v=<時刻>` を足して開く)、7 つの項目を確かめる。このあと、ファイルを変えない。ユーザーが書いて許したときのほかは、4 回目の直しのラウンドはない。

AI は、免除する問題(理由があって残すもの)を、理由付きで `<run-dir>/final/waivers.md` に書く。

### 5. 結果

AI は、実行の最後の行を、`DESIGN_BUILD: <結果> rounds=<直したラウンドの数> states=<撮った状態の数>/<一覧の状態の数>` とする。

| 結果 | 意味 | 次 |
|---------|-------|------|
| `clean` / `waived` | すべての状態を、すべての幅で撮り、開いた問題がない(か、すべてに理由付きの免除がある) | そのまま報告する |
| `open` | 範囲はすべて覆ったが、開いた問題がある | 1 件ずつに、理由付きの免除か、PR の本文の 1 行を付ける |
| `incomplete` | どこかに撮れていない状態か、プレビューの 501 がある | その直し方を示し、残りは PR の本文に、確かめていないものとして並べる |
| `unrendered` | ブラウザかプレビューが動かない | その直し方を示す |

最後に、AI は、自分が起動したプレビューを止め、自分が開いたタブを閉じる。
