// ai-management-portal 共通: 共通ヘッダ拡張モジュール
// サイト全体スコープの機能（テーマ切替）のみをヘッダに残す。
// ページ単位の操作（MD コピー / MD DL / LLM コピー / GitHub 編集）は page-actions.js が担当する。

import { initTheme, getCurrentTheme, cycleTheme } from "./theme.js";
import { initShortcuts } from "./shortcuts.js";
import { initCodeCopy } from "./code-copy.js";
import { initTableExport } from "./table-export.js";
import { initShareUrl } from "./share-url.js";
import { initToc } from "./toc.js";
import { makeBtn, findPortalRoot } from "./controls.js";
import { initPageActions } from "./page-actions.js";

const ICON_MAP_THEME = { light: "dark_mode", dark: "light_mode" };
const LABEL_MAP_THEME = { light: "ダーク表示", dark: "ライト表示" };

const NAV_LINKS = [
  { path: "catalog/skills.html", label: "スキル一覧" },
];

function ensureMaterialSymbols() {
  if (document.querySelector('link[href*="Material+Symbols+Outlined"]')) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,400,0..1,-25..0";
  document.head.appendChild(link);
}

function findHostHeader() {
  return document.querySelector(".hd-inner, .topbar, .pt-topbar, .ds-topbar, header > nav, header");
}

function buildGeneratedHeader() {
  const portalRoot = findPortalRoot();
  const header = document.createElement("header");
  header.className = "topbar";

  const brand = document.createElement("a");
  brand.className = "brand";
  brand.href = portalRoot ? portalRoot + "index.html" : "#";
  brand.innerHTML = `
    <span class="brand-title">agent-toolkit ポータル</span>
    <span class="brand-sub">skills · design</span>
  `;
  header.appendChild(brand);

  const wrapper = document.body.firstElementChild;
  const target = wrapper && wrapper !== header ? wrapper : document.body;
  target.insertBefore(header, target.firstChild);
  return header;
}

function ensureNav(header) {
  let nav = header.querySelector(".topnav");
  if (!nav) {
    const portalRoot = findPortalRoot();
    nav = document.createElement("nav");
    nav.className = "topnav";
    nav.innerHTML = NAV_LINKS.map(({ path, label }) => {
      const href = portalRoot ? portalRoot + path : path;
      return `<a href="${href}">${label}</a>`;
    }).join("\n");
    const brand = header.querySelector(".brand");
    if (brand) {
      brand.insertAdjacentElement("afterend", nav);
    } else {
      header.appendChild(nav);
    }
  }
  if (!nav.id) nav.id = "site-nav";
  return nav;
}

// ドロワー切替（≤768px）: ハンバーガーボタンで .topnav の開閉を制御する。
// Escape・パネル外クリック・ナビ内リンククリックで閉じ、閉時はトグルボタンへフォーカスを戻す。
function setNavOpen(nav, toggle, open) {
  nav.classList.toggle("is-open", open);
  toggle.setAttribute("aria-expanded", open ? "true" : "false");
  toggle.setAttribute("aria-label", open ? "メニューを閉じる" : "メニューを開く");
  const icon = toggle.querySelector(".material-symbols-outlined");
  if (icon) icon.textContent = open ? "close" : "menu";
  document.body.classList.toggle("nav-open-lock", open);
}

function ensureNavToggle(header, nav) {
  if (header.querySelector(".nav-toggle")) return;
  const toggle = document.createElement("button");
  toggle.type = "button";
  toggle.className = "nav-toggle";
  toggle.setAttribute("aria-expanded", "false");
  toggle.setAttribute("aria-controls", nav.id);
  toggle.setAttribute("aria-label", "メニューを開く");
  toggle.innerHTML = `<span class="material-symbols-outlined">menu</span>`;

  toggle.addEventListener("click", () => {
    setNavOpen(nav, toggle, !nav.classList.contains("is-open"));
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && nav.classList.contains("is-open")) {
      setNavOpen(nav, toggle, false);
      toggle.focus();
    }
  });

  document.addEventListener("click", (e) => {
    if (!nav.classList.contains("is-open")) return;
    if (nav.contains(e.target) || toggle.contains(e.target)) return;
    setNavOpen(nav, toggle, false);
  });

  nav.addEventListener("click", (e) => {
    if (e.target.closest("a") && nav.classList.contains("is-open")) {
      setNavOpen(nav, toggle, false);
      toggle.focus();
    }
  });

  const brand = header.querySelector(".brand");
  if (brand) {
    brand.insertAdjacentElement("afterend", toggle);
  } else {
    header.insertBefore(toggle, header.firstChild);
  }
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

  host.appendChild(themeCtl.btn);

  let header = findHostHeader();
  if (!header) header = buildGeneratedHeader();
  const nav = ensureNav(header);
  ensureNavToggle(header, nav);
  header.appendChild(host);
}

function init() {
  initTheme();
  ensureMaterialSymbols();
  mountControls();
  initPageActions();
  initShortcuts();
  initCodeCopy();
  initTableExport();
  initShareUrl();
  initToc();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
