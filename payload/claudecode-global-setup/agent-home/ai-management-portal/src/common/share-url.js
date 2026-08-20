// h2 / h3 にアンカー ID を自動付与し、hover で「§ コピー」ボタンを出す。

import { copyToClipboard } from "./md-export.js";

function ensureStyle() {
  if (document.getElementById("dp-share-url-style")) return;
  const style = document.createElement("style");
  style.id = "dp-share-url-style";
  style.textContent = `
    .dp-anchored { position: relative; }
    .dp-anchored .dp-share-btn { opacity: 0; margin-left: 8px; font-size: 11px; color: var(--text-muted, #6b7280); border: 1px solid var(--border, #e5e7eb); background: var(--panel, #fff); border-radius: 4px; padding: 0 6px; cursor: pointer; line-height: 1.5; vertical-align: middle; }
    .dp-anchored:hover .dp-share-btn { opacity: 1; }
    .dp-share-btn:hover { color: var(--accent, #1d4ed8); border-color: var(--accent, #1d4ed8); }
    .dp-share-btn.is-copied { color: var(--success, #16a34a); border-color: var(--success, #16a34a); }
  `;
  document.head.appendChild(style);
}

function slugify(text) {
  return (text || "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^\w぀-ヿ㐀-鿿-]/g, "")
    .slice(0, 80) || "section";
}

export function attachShareUrl(root = document) {
  ensureStyle();
  for (const h of root.querySelectorAll("h2:not([data-dp-share]), h3:not([data-dp-share])")) {
    h.setAttribute("data-dp-share", "1");
    h.classList.add("dp-anchored");
    if (!h.id) h.id = slugify(h.textContent || "");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "dp-share-btn";
    btn.title = "アンカー付き URL をコピー";
    btn.textContent = "§";
    btn.addEventListener("click", async (e) => {
      e.preventDefault();
      const url = location.origin + location.pathname + location.search + "#" + h.id;
      const ok = await copyToClipboard(url);
      if (ok) {
        btn.textContent = "✓";
        btn.classList.add("is-copied");
        setTimeout(() => { btn.textContent = "§"; btn.classList.remove("is-copied"); }, 1500);
      }
    });
    h.appendChild(btn);
  }
}

export function initShareUrl() {
  const run = () => attachShareUrl(document);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
}
