#!/usr/bin/env node
// 画面の URL を幅 1440、768、375 で開き、写真を撮って測った値を JSON に書く(step 6-2)。
// 終了コード 0 正常、2 呼び出しの誤りか、開けない URL か、ブラウザを起動できない。
const fs = require("fs");
const path = require("path");

const WIDTHS = [1440, 768, 375];
const FOCUS_LIMIT = 100;

function parseColor(text) {
  const m = String(text).match(/rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?\s*\)/);
  if (m) return { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] };
  const h = String(text).match(/^#([0-9a-f]{6})$/i);
  if (h) return { r: parseInt(h[1].slice(0, 2), 16), g: parseInt(h[1].slice(2, 4), 16), b: parseInt(h[1].slice(4, 6), 16), a: 1 };
  return null;
}

function channel(v) {
  const c = v / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function luminance(color) {
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

function contrastRatio(fg, bg) {
  const l1 = luminance(fg);
  const l2 = luminance(bg);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

function parseArgs(argv) {
  const a = { tools: null, photos: null, data: null, urls: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--tools") a.tools = argv[++i];
    else if (argv[i] === "--photos") a.photos = argv[++i];
    else if (argv[i] === "--data") a.data = argv[++i];
    else a.urls.push(argv[i]);
  }
  if (!a.tools || !a.photos || !a.data || a.urls.length === 0) throw new Error("--tools、--photos、--data と、画面の URL が 1 つ以上要る");
  return a;
}

function collectInPage() {
  const sel = (el) => el.id ? `#${el.id}` : el.tagName.toLowerCase() + [...el.classList].map((c) => `.${c}`).join("");
  const bgOf = (el) => {
    for (let e = el; e; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (s.backgroundImage !== "none") return { undetermined: "背景の画像かグラデーション" };
      const m = s.backgroundColor.match(/[\d.]+/g);
      const alpha = m && m.length === 4 ? +m[3] : 1;
      if (alpha === 0) continue;
      if (alpha < 1) return { undetermined: "半透明の背景" };
      return { color: s.backgroundColor };
    }
    return { color: "rgb(255, 255, 255)" };
  };
  const texts = [];
  for (const el of document.body.querySelectorAll("*")) {
    const own = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (!own) continue;
    texts.push({ selector: sel(el), text: el.textContent.trim().slice(0, 40), color: getComputedStyle(el).color, background: bgOf(el) });
  }
  const targets = [...document.querySelectorAll("button, a[href], [role=button], input[type=button], input[type=submit]")].map((el) => {
    const r = el.getBoundingClientRect();
    return { selector: sel(el), width: Math.round(r.width), height: Math.round(r.height) };
  });
  return { overflow: document.documentElement.scrollWidth > window.innerWidth, targets, texts };
}

function toContrast(texts) {
  return texts.map((t) => {
    const fg = parseColor(t.color);
    const bg = t.background.color ? parseColor(t.background.color) : null;
    if (t.background.undetermined) return { selector: t.selector, text: t.text, ratio: null, reason: t.background.undetermined };
    if (!fg || !bg || fg.a < 1) return { selector: t.selector, text: t.text, ratio: null, reason: "半透明の文字の色" };
    return { selector: t.selector, text: t.text, color: t.color, background: t.background.color, ratio: Math.round(contrastRatio(fg, bg) * 100) / 100 };
  });
}

async function focusOrder(page) {
  const order = [];
  for (let i = 0; i < FOCUS_LIMIT; i++) {
    await page.keyboard.press("Tab");
    const s = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return null;
      return el.id ? `#${el.id}` : el.tagName.toLowerCase() + [...el.classList].map((c) => `.${c}`).join("");
    });
    if (s === null || (order.length > 0 && s === order[0])) break;
    order.push(s);
  }
  return order;
}

async function main() {
  let a;
  try {
    a = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.log(`呼び出しの誤り: ${e.message}`);
    process.exit(2);
  }
  const pw = path.join(a.tools, "node_modules", "playwright");
  if (!fs.existsSync(pw)) {
    console.log(`(ブラウザの道具がない: ${pw})`);
    process.exit(2);
  }
  let browser;
  try {
    browser = await require(pw).chromium.launch({ headless: true });
  } catch (e) {
    console.log(`(ブラウザを起動できない: ${String(e.message).split("\n")[0]})`);
    process.exit(2);
  }
  fs.mkdirSync(a.photos, { recursive: true });
  const result = [];
  try {
    for (let i = 0; i < a.urls.length; i++) {
      const url = a.urls[i];
      for (const width of WIDTHS) {
        const page = await browser.newPage({ viewport: { width, height: 900 } });
        const consoleErrors = [];
        page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
        page.on("pageerror", (e) => consoleErrors.push(String(e.message)));
        try {
          await page.goto(url, { waitUntil: "load" });
        } catch (e) {
          console.log(`${url}(開けない: ${String(e.message).split("\n")[0]})`);
          await browser.close();
          process.exit(2);
        }
        const photo = path.join(a.photos, `${i + 1}-${width}.png`);
        await page.screenshot({ path: photo, fullPage: true });
        const m = await page.evaluate(collectInPage);
        const focus = await focusOrder(page);
        result.push({ url, number: i + 1, width, photo, overflow: m.overflow, targets: m.targets, contrast: toContrast(m.texts), focus, console_errors: consoleErrors });
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
  fs.writeFileSync(a.data, JSON.stringify(result, null, 2));
  console.log(`測った: ${a.urls.length} 件の URL、写真 ${result.length} 枚`);
}

if (require.main === module) main();
module.exports = { parseColor, luminance, contrastRatio, toContrast };
