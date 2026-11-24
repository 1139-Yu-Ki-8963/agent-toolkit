// 描いたスライド(.dc.html)を、ブラウザの中で測り、検査して、画像を書くスクリプトの雛形。
// このファイルは直接使わない。`node tools/measure.js <資料のフォルダ>` が、settings と measuredErrors を埋めた全文を、標準出力に出す。
// AI は、出た全文を、そのまま、Playwright の MCP のツール browser_run_code_unsafe の code に渡す。
// 返す値(短い形): { slides: { <名前>: { out, lang, fonts, brokenImages, elements, conclusionLines, emphasisCount, frame, fullWidthExempt, fullWidth, errorCount, errors: [{check, message}] } } }
// 返す値と同じ JSON を、settings.jsonPath(<資料のフォルダ>/測った値.json)に、ブラウザのダウンロードの保存(saveAs)で書く。
// 測る要素: data-part か data-role を持つ要素。外側はクラス s、本文領域はクラス bd、結論の一文はクラス cc。
// 文字の箱は、行の箱(行の高さの箱)。字の形の箱でなく、line-height の高さで、行の中央に置く。
async (page) => {
  const settings = /*SETTINGS*/ {};
  const measuredErrors = /*MEASURED_ERRORS*/ null;
  const { size, slides, limits, frameParts, jsonPath } = settings;
  const ROOT_CLASS = 's';
  const BODY_CLASS = 'bd';
  const CONCLUSION_CLASS = 'cc';
  const MAX_ERRORS = 40;

  if (!(size.width > 0 && size.height > 0)) throw new Error('size に、スライドの大きさがない');
  const tab = await page.context().newPage();
  const result = {};
  try {
    await tab.setViewportSize(size);
    for (const { name, src, out, fullWidthExempt } of slides) {
      await tab.goto('about:blank');
      await tab.setContent('<input type="file">');
      await tab.setInputFiles('input', src);
      const text = await tab.evaluate(() => document.querySelector('input').files[0].text());
      const lang = text.match(/<html[^>]*\slang="([^"]+)"/i)?.[1] ?? 'ja';
      const head = text.match(/<helmet>([\s\S]*?)<\/helmet>/i)?.[1];
      const body = text.match(/<x-dc[^>]*>([\s\S]*)<\/x-dc>/i)?.[1].replace(/<helmet>[\s\S]*?<\/helmet>/i, '');
      if (head === undefined || body === undefined) throw new Error(`helmet か x-dc がない: ${src}`);
      await tab.setContent(`<!doctype html><html lang="${lang}"><head><meta charset="utf-8">${head}</head><body style="margin:0">${body}</body></html>`, { waitUntil: 'load' });
      const measured = await tab.evaluate(async ({ rootClass, bodyClass, conclusionClass, frameParts }) => {
        await document.fonts.ready;
        await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
        const box = (r) => [r.left, r.top, r.right, r.bottom].map((v) => Math.round(v * 10) / 10);
        const roots = document.querySelectorAll(`.${rootClass}`);
        if (roots.length !== 1) throw new Error(`クラス ${rootClass} の要素が 1 つでない`);
        const rootEl = roots[0];
        const bodyEl = rootEl.querySelector(`.${bodyClass}`);
        const parse = (s) => { const m = /rgba?\(\s*([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)(?:[ ,/]+([\d.]+))?\s*\)/.exec(s); return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : { r: 0, g: 0, b: 0, a: 0 }; };
        const effectiveBg = (el) => {
          const layers = [];
          for (let e = el; e && e.nodeType === 1; e = e.parentElement) layers.push(parse(getComputedStyle(e).backgroundColor));
          let c = { r: 255, g: 255, b: 255 };
          for (const l of layers.reverse()) c = { r: l.r * l.a + c.r * (1 - l.a), g: l.g * l.a + c.g * (1 - l.a), b: l.b * l.a + c.b * (1 - l.a) };
          return `rgb(${Math.round(c.r)}, ${Math.round(c.g)}, ${Math.round(c.b)})`;
        };
        const textNodes = (el, own) => {
          const out = [];
          const walk = (n) => { for (const c of n.childNodes) { if (c.nodeType === 3 && c.textContent.trim()) out.push(c); else if (c.nodeType === 1 && !own) walk(c); } };
          walk(el);
          return out;
        };
        const rectsOf = (nodes) => nodes.flatMap((n) => { const g = document.createRange(); g.selectNodeContents(n); return [...g.getClientRects()].filter((r) => r.width > 0 && r.height > 0); });
        // 行の箱: 字の形の箱の中央に、行の高さ(line-height)の高さの箱を置く。line-height が数でないときは、字の形の箱のまま。
        const lineBoxes = (el, nodes) => {
          const lh = parseFloat(getComputedStyle(el).lineHeight);
          return rectsOf(nodes).map((r) => {
            const h = Number.isFinite(lh) ? lh : r.height;
            const cy = (r.top + r.bottom) / 2;
            return { left: r.left, right: r.right, top: cy - h / 2, bottom: cy + h / 2 };
          });
        };
        const countLines = (rects) => {
          const sorted = [...rects].sort((a, b) => a.top - b.top);
          let lines = 0, curTop = 0, curBottom = -Infinity;
          for (const r of sorted) {
            if (lines === 0 || r.top >= curTop + (curBottom - curTop) * 0.5) { lines++; curTop = r.top; curBottom = r.bottom; }
            else curBottom = Math.max(curBottom, r.bottom);
          }
          return lines;
        };
        const targets = [...rootEl.querySelectorAll('[data-part],[data-role]')];
        const ids = new Map(targets.map((e, i) => [e, i]));
        const elements = targets.map((e) => {
          const cs = getComputedStyle(e);
          const own = textNodes(e, true);
          const lb = lineBoxes(e, own);
          const textBox = lb.length ? box({ left: Math.min(...lb.map((r) => r.left)), top: Math.min(...lb.map((r) => r.top)), right: Math.max(...lb.map((r) => r.right)), bottom: Math.max(...lb.map((r) => r.bottom)) }) : null;
          const ancestors = [];
          for (let p = e.parentElement; p; p = p.parentElement) if (ids.has(p)) ancestors.push(ids.get(p));
          const isSvg = e instanceof SVGElement;
          return {
            id: ids.get(e), ancestors, tag: e.tagName.toLowerCase(),
            part: e.getAttribute('data-part'), role: e.getAttribute('data-role'),
            text: own.map((n) => n.textContent.trim()).join(''),
            box: box(e.getBoundingClientRect()), textBox,
            fontSize: parseFloat(cs.fontSize), color: isSvg ? cs.fill : cs.color, bg: effectiveBg(e),
            inBody: !!bodyEl && bodyEl.contains(e),
          };
        });
        const cEl = rootEl.querySelector(`.${conclusionClass}`);
        return {
          root: box(rootEl.getBoundingClientRect()),
          body: bodyEl ? box(bodyEl.getBoundingClientRect()) : null,
          conclusion: cEl ? { lines: countLines(rectsOf(textNodes(cEl, false))) } : null,
          emphasisCount: rootEl.querySelectorAll('[data-emphasis]').length,
          frame: Object.fromEntries(frameParts.map((n) => { const f = rootEl.querySelector(`[data-part="${n}"]`); const b = f ? box(f.getBoundingClientRect()) : null; return [n, b ? { top: b[1], left: b[0] } : null]; })),
          fullWidth: [...rootEl.querySelectorAll('[data-full-width]')].map((f) => box(f.getBoundingClientRect())),
          fonts: [...document.fonts].filter((f) => f.status === 'loaded').length,
          brokenImages: [...document.images].filter((i) => !i.naturalWidth).length,
          elements,
        };
      }, { rootClass: ROOT_CLASS, bodyClass: BODY_CLASS, conclusionClass: CONCLUSION_CLASS, frameParts });
      await tab.screenshot({ path: out });
      measured.fullWidthExempt = !!fullWidthExempt;
      const errors = measuredErrors(measured, limits);
      result[name] = {
        out, lang, fonts: measured.fonts, brokenImages: measured.brokenImages,
        elements: measured.elements.length, conclusionLines: measured.conclusion ? measured.conclusion.lines : null, emphasisCount: measured.emphasisCount,
        frame: measured.frame, fullWidthExempt: measured.fullWidthExempt, fullWidth: measured.fullWidth,
        errorCount: errors.length, errors: errors.slice(0, MAX_ERRORS),
      };
    }
    // 測った値の JSON を、返す値と同じ中身で書く
    const json = JSON.stringify({ slides: result });
    await tab.goto('about:blank');
    await tab.setContent('<a id="save">save</a>');
    await tab.evaluate((t) => { const a = document.getElementById('save'); a.href = URL.createObjectURL(new Blob([t], { type: 'application/json' })); a.download = 'measured.json'; }, json);
    const [dl] = await Promise.all([tab.waitForEvent('download'), tab.click('#save')]);
    await dl.saveAs(jsonPath);
  } finally {
    await tab.close();
  }
  return { slides: result };
}
