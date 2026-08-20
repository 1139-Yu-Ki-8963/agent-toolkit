// 各 <pre> の右上に「コピー」ボタンを注入する。クリックでブロック内テキストをクリップボードへ。

import { copyToClipboard } from "./md-export.js";

function ensureStyle() {
  if (document.getElementById("dp-code-copy-style")) return;
  const style = document.createElement("style");
  style.id = "dp-code-copy-style";
  style.textContent = `
    .dp-pre-wrap { position: relative; }
    .dp-pre-copy { position: absolute; top: 6px; right: 6px; background: var(--panel, #fff); color: var(--text-sub, #4b5563); border: 1px solid var(--border, #e5e7eb); border-radius: 4px; padding: 2px 8px; font-size: 11px; cursor: pointer; opacity: 0; transition: opacity 0.15s; line-height: 1.4; }
    .dp-pre-wrap:hover .dp-pre-copy { opacity: 1; }
    .dp-pre-copy:hover { color: var(--accent, #1d4ed8); border-color: var(--accent, #1d4ed8); }
    .dp-pre-copy.is-copied { color: var(--success, #16a34a); border-color: var(--success, #16a34a); }
  `;
  document.head.appendChild(style);
}

export function attachCodeCopy(root = document) {
  ensureStyle();
  for (const pre of root.querySelectorAll("pre:not([data-dp-copy])")) {
    pre.setAttribute("data-dp-copy", "1");
    const wrap = document.createElement("div");
    wrap.className = "dp-pre-wrap";
    pre.parentNode?.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "dp-pre-copy";
    btn.textContent = "コピー";
    btn.addEventListener("click", async () => {
      const ok = await copyToClipboard(pre.textContent || "");
      if (ok) {
        btn.textContent = "✓ コピーしました";
        btn.classList.add("is-copied");
        setTimeout(() => { btn.textContent = "コピー"; btn.classList.remove("is-copied"); }, 1500);
      }
    });
    wrap.appendChild(btn);
  }
}

export function initCodeCopy() {
  const run = () => attachCodeCopy(document);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
}
