// project-portal 共通: 共通ヘッダ拡張モジュール
// テーマ切替とフォントサイズ切替のコントロールを既存ヘッダに注入する。
// 既存ヘッダがない場合は <body> 直下に固定配置でフォールバックする。
// 各 HTML は <head> に次の 1 行を追加するだけでよい:
//   <script type="module" src="<相対パス>/src/common/header.js"></script>

import { initTheme, getCurrentTheme, cycleTheme } from "./theme.js";
import { initFontScale, getCurrentFontScale, cycleFontScale } from "./font-scale.js";
import * as search from "./search-ui.js";
import { initShortcuts } from "./shortcuts.js";
import { pageToMd, copyToClipboard, downloadMd, safeFilename } from "./md-export.js";
import { initCodeCopy } from "./code-copy.js";
import { initTableExport } from "./table-export.js";
import { initShareUrl } from "./share-url.js";
import { copyLlmPrompt } from "./llm-context.js";
import { initRelatedPages } from "./related-pages.js";
import { getGitHubEditUrl } from "./edit-on-github.js";
import { initToc } from "./toc.js";

const ICON_MAP_THEME = { light: "dark_mode", dark: "light_mode" };
const LABEL_MAP_THEME = { light: "ダーク表示", dark: "ライト表示" };
const LABEL_MAP_FONT = { s: "S", m: "M", l: "L" };

function ensureMaterialSymbols() {
  if (document.querySelector('link[href*="Material+Symbols+Outlined"]')) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,400,0..1,-25..0";
  document.head.appendChild(link);
}

function ensureStyle() {
  if (document.getElementById("dp-common-style")) return;
  const style = document.createElement("style");
  style.id = "dp-common-style";
  style.textContent = `
    .material-symbols-outlined { font-variation-settings: "FILL" 0, "wght" 400, "GRAD" 0, "opsz" 24; font-size: inherit; vertical-align: middle; line-height: 1; }
    .dp-controls { display: inline-flex; align-items: center; gap: 6px; }
    .dp-controls--fixed { position: fixed; top: 12px; right: 12px; z-index: 100; background: var(--panel, var(--bg, #ffffff)); border: 1px solid var(--border, #e5e7eb); border-radius: 999px; padding: 4px 8px; box-shadow: 0 2px 8px rgba(31,41,55,0.08); }
    .dp-btn { display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; background: transparent; color: var(--text-sub, var(--text, #4b5563)); border: 1px solid var(--border, #e5e7eb); border-radius: 6px; cursor: pointer; font: inherit; font-size: 12px; line-height: 1; }
    .dp-btn:hover { border-color: var(--accent, #1d4ed8); color: var(--accent, #1d4ed8); }
    .dp-btn .material-symbols-outlined { font-size: 18px; }
    .dp-btn-label { font-size: 12px; }
    @media (max-width: 720px) { .dp-btn-label { display: none; } }

    /* Dark theme overrides for global portal palette.
       カラーパレット v2（color-palette-proposal.html）: インディゴ＝進む / オーカー＝考える / コッパー＝止まる
       style.css の [data-theme="dark"] を尊重するため、ここでは値を再宣言せず
       style.css に委譲する（旧定義は青系の旧色だったため削除）。 */
    :root[data-theme="dark"] body { background: var(--bg); color: var(--text); }

    /* Default body font follows data-font-scale via --dp-base-font (set by font-scale.js). */
    body { font-size: var(--dp-base-font, 15px); }
  `;
  document.head.appendChild(style);
}

function makeBtn({ iconName, ariaLabel, labelText, onClick }) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "dp-btn";
  btn.setAttribute("aria-label", ariaLabel);
  btn.title = ariaLabel;
  const ic = document.createElement("span");
  ic.className = "material-symbols-outlined";
  ic.setAttribute("aria-hidden", "true");
  ic.setAttribute("translate", "no");
  ic.textContent = iconName;
  btn.appendChild(ic);
  if (labelText) {
    const lab = document.createElement("span");
    lab.className = "dp-btn-label";
    lab.textContent = labelText;
    btn.appendChild(lab);
  }
  btn.addEventListener("click", onClick);
  return { btn, iconEl: ic, labelEl: btn.querySelector(".dp-btn-label") };
}

function findHostHeader() {
  // 既存ヘッダ規約のうち「コントロール挿入に適した内側コンテナ」を優先する。
  // - rules サブサイト: <header class="hd"> > <div class="hd-inner"> をターゲット
  // - 一般 portal / その他サブサイト: .topbar 直下
  return document.querySelector(".hd-inner, .topbar, .pt-topbar, .ds-topbar, .bridge-header, header > nav, header");
}

function flashBtn(ctl, msg) {
  const prev = ctl.labelEl?.textContent;
  if (ctl.labelEl) ctl.labelEl.textContent = msg;
  setTimeout(() => { if (ctl.labelEl && prev != null) ctl.labelEl.textContent = prev; }, 1500);
}

function mountControls() {
  const host = document.createElement("div");
  host.className = "dp-controls";

  const themeCtl = makeBtn({
    iconName: ICON_MAP_THEME[getCurrentTheme()],
    ariaLabel: "テーマ切替",
    labelText: LABEL_MAP_THEME[getCurrentTheme()],
    onClick: () => {
      cycleTheme();
      const cur = getCurrentTheme();
      themeCtl.iconEl.textContent = ICON_MAP_THEME[cur];
      themeCtl.labelEl && (themeCtl.labelEl.textContent = LABEL_MAP_THEME[cur]);
    },
  });

  const fontCtl = makeBtn({
    iconName: "format_size",
    ariaLabel: "フォントサイズ切替（S / M / L）",
    labelText: LABEL_MAP_FONT[getCurrentFontScale()],
    onClick: () => {
      cycleFontScale();
      fontCtl.labelEl && (fontCtl.labelEl.textContent = LABEL_MAP_FONT[getCurrentFontScale()]);
    },
  });

  const searchCtl = makeBtn({
    iconName: "search",
    ariaLabel: "全体検索を開く（ / キー）",
    labelText: "検索",
    onClick: () => search.open(),
  });

  const copyCtl = makeBtn({
    iconName: "content_copy",
    ariaLabel: "ページ全体を Markdown としてコピー",
    labelText: "MD コピー",
    onClick: async () => {
      const ok = await copyToClipboard(pageToMd());
      flashBtn(copyCtl, ok ? "✓ コピー済" : "失敗");
    },
  });

  const downloadCtl = makeBtn({
    iconName: "download",
    ariaLabel: "ページ全体を .md としてダウンロード",
    labelText: "MD DL",
    onClick: () => {
      const title = (document.querySelector("h1")?.textContent || document.title || "page").trim();
      downloadMd(pageToMd(), safeFilename(title) + ".md");
      flashBtn(downloadCtl, "✓ DL");
    },
  });

  const llmCtl = makeBtn({
    iconName: "smart_toy",
    ariaLabel: "ページ全体を LLM 入力プロンプトとしてコピー",
    labelText: "LLM",
    onClick: async () => {
      const ok = await copyLlmPrompt();
      flashBtn(llmCtl, ok ? "✓ LLM" : "失敗");
    },
  });

  const editUrl = getGitHubEditUrl();
  const editCtl = editUrl
    ? makeBtn({
        iconName: "edit",
        ariaLabel: "GitHub でこのページを編集",
        labelText: "編集",
        onClick: () => window.open(editUrl, "_blank", "noopener"),
      })
    : null;

  host.appendChild(searchCtl.btn);
  host.appendChild(copyCtl.btn);
  host.appendChild(downloadCtl.btn);
  host.appendChild(llmCtl.btn);
  if (editCtl) host.appendChild(editCtl.btn);
  host.appendChild(themeCtl.btn);
  host.appendChild(fontCtl.btn);

  const header = findHostHeader();
  if (header) {
    header.appendChild(host);
  } else {
    host.classList.add("dp-controls--fixed");
    document.body.appendChild(host);
  }
}

function init() {
  initTheme();
  initFontScale();
  ensureMaterialSymbols();
  ensureStyle();
  mountControls();
  initShortcuts();
  initCodeCopy();
  initTableExport();
  initShareUrl();
  initToc();
  initRelatedPages();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
