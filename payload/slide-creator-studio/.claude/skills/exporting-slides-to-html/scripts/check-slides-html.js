// 全ページを 1 つにまとめた HTML をブラウザで開き、全ページが見えることを確かめるスクリプト。
// スクリプトは、HTML を開き、→ のキーで最後のページまで 1 ページずつ進み、ページごとに画像を作る。
// 使い方: AI は、このファイルを写し、写しの「AI が書き換える値」の 2 つだけを書き換えて、写しのパスを、
// Playwright の MCP のツール browser_run_code_unsafe の filename に渡して 1 回呼ぶ。
// ツールが filename のファイルを読めないときは、写しの全文を、同じツールの code に渡す。
// 返す値: { pages, stage, results }。
//   pages: まとめた HTML が持つページの数
//   stage: ページの大きさ(px)
//   results: ページごとの { no, title, counter, visible, root, fonts, brokenImages, marks, out }
//     counter: 画面の下の「<今のページ> / <ページの数>」の文字
//     visible: 見えているページの数(1 が正しい)
//     root: ページの中の、スライドのいちばん外の要素の幅と高さ(px)
//     fonts: 読み込めたフォントの数
//     brokenImages: 欠けた絵の数
//     marks: スライドに、値で埋まらずに残った差し込みの印(「{{名前}}」)の数
//     out: そのページの画像のパス
async (page) => {
  // ---- AI が書き換える値(ここから) ----
  // src: まとめた HTML の絶対パス
  const src = '<まとめた HTML の絶対パス>';
  // outDir: ページごとの画像を置く、一時のフォルダの絶対パス(末尾に / を付けない)
  const outDir = '<画像を置くフォルダの絶対パス>';
  // ---- AI が書き換える値(ここまで) ----

  // デザインシステムの frame.js が決めたクラスの名前
  const ROOT_CLASS = 's'; // スライドのいちばん外の要素
  const BAR = 56; // build-slides-html.js の、ページを切り替えるボタンの行の高さ(px)

  const tab = await page.context().newPage();
  const results = [];
  try {
    await tab.setContent('<input type="file">');
    await tab.setInputFiles('input', src);
    const html = await tab.evaluate(() => document.querySelector('input').files[0].text());
    // ファイルの中身を、この名前の URL の応答として返し、ページを URL を持つ文書として開く。外へは通信しない。
    const url = 'https://slides.invalid/slides.html';
    await tab.route(url, (route) => route.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
    await tab.goto(url, { waitUntil: 'load' });
    const stage = await tab.evaluate(() => {
      const s = document.getElementById('stage');
      return { width: s.offsetWidth, height: s.offsetHeight };
    });
    await tab.setViewportSize({ width: stage.width, height: stage.height + BAR });
    const pages = await tab.evaluate(() => document.querySelectorAll('#stage iframe').length);
    if (pages === 0) throw new Error(`ページが 1 つもない: ${src}`);
    await tab.keyboard.press('Home');
    for (let no = 1; no <= pages; no++) {
      if (no > 1) await tab.keyboard.press('ArrowRight');
      const outer = await tab.evaluate(() => {
        const frames = [...document.querySelectorAll('#stage iframe')];
        const shown = frames.filter((f) => !f.hidden);
        return { visible: shown.length, index: frames.indexOf(shown[0]), title: shown[0]?.title ?? '', counter: document.getElementById('no').textContent, hash: location.hash };
      });
      if (outer.visible !== 1 || outer.index !== no - 1) throw new Error(`${no} ページ目が見えていない: ${JSON.stringify(outer)}`);
      const handle = await tab.locator('#stage iframe').nth(no - 1).elementHandle();
      const frame = await handle.contentFrame();
      const inner = await frame.evaluate(async (rootClass) => {
        await document.fonts.ready;
        await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
        const el = document.querySelector(`.${rootClass}`);
        const r = el ? el.getBoundingClientRect() : { width: 0, height: 0 };
        return {
          root: { width: Math.round(r.width), height: Math.round(r.height) },
          fonts: [...document.fonts].filter((f) => f.status === 'loaded').length,
          brokenImages: [...document.images].filter((i) => !i.naturalWidth).length,
          marks: el ? (el.outerHTML.match(/\{\{[^{}]+\}\}/g) || []).length : 0,
        };
      }, ROOT_CLASS);
      const out = `${outDir}/${no}.png`;
      await tab.screenshot({ path: out });
      results.push({ no, title: outer.title, counter: outer.counter, visible: outer.visible, ...inner, out });
    }
    await tab.keyboard.press('ArrowRight');
    const last = await tab.evaluate(() => document.getElementById('no').textContent);
    if (last !== `${pages} / ${pages}`) throw new Error(`最後のページの先へ進んだ: ${last}`);
    return { pages, stage, results };
  } finally {
    await tab.close();
  }
}
