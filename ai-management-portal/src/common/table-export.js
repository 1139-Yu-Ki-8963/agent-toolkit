// 各 <table> の下に「CSV / TSV / MD」コピーボタンを注入。

import { copyToClipboard, tableMd, tableTsv, tableCsv } from "./md-export.js";

function ensureStyle() {
  if (document.getElementById("dp-table-export-style")) return;
  const style = document.createElement("style");
  style.id = "dp-table-export-style";
  style.textContent = `
    .dp-table-export { display: flex; gap: 6px; margin: 4px 0 10px; font-size: 11px; }
    .dp-table-export button { background: var(--panel, #fff); color: var(--text-sub, #4b5563); border: 1px solid var(--border, #e5e7eb); border-radius: 4px; padding: 2px 8px; cursor: pointer; font: inherit; font-size: 11px; }
    .dp-table-export button:hover { color: var(--accent, #1d4ed8); border-color: var(--accent, #1d4ed8); }
    .dp-table-export button.is-copied { color: var(--success, #16a34a); border-color: var(--success, #16a34a); }
  `;
  document.head.appendChild(style);
}

const FORMATS = [
  { label: "MD", fn: tableMd },
  { label: "CSV", fn: tableCsv },
  { label: "TSV", fn: tableTsv },
];

export function attachTableExport(root = document) {
  ensureStyle();
  for (const tbl of root.querySelectorAll("table:not([data-dp-export])")) {
    tbl.setAttribute("data-dp-export", "1");
    if (tbl.rows.length < 2) continue; // 1 行だけの表 (toolbar 等) は対象外
    const bar = document.createElement("div");
    bar.className = "dp-table-export";
    for (const f of FORMATS) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = f.label;
      btn.addEventListener("click", async () => {
        const ok = await copyToClipboard(f.fn(tbl));
        if (ok) {
          const prev = btn.textContent;
          btn.textContent = "✓ " + prev;
          btn.classList.add("is-copied");
          setTimeout(() => { btn.textContent = prev; btn.classList.remove("is-copied"); }, 1500);
        }
      });
      bar.appendChild(btn);
    }
    tbl.parentNode?.insertBefore(bar, tbl.nextSibling);
  }
}

export function initTableExport() {
  const run = () => attachTableExport(document);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
  window.addEventListener("hashchange", () => setTimeout(run, 80));
}
