// ai-management-portal 共通: 全体検索モーダル UI。
// "/" キー押下でモーダルを開き、即時候補を出す。Enter で遷移、Esc で閉じる。

import { loadIndex, search, buildPortalUrl } from "./search-index.js";

function buildEntryUrl(entry) {
  return buildPortalUrl(entry.path);
}

const KIND_LABEL = {
  page: "ページ",
  rule: "規約",
  design: "デザイン",
  flow: "フロー",
  doc: "ドキュメント",
  other: "",
};

let _modal = null;
let _input = null;
let _resultsEl = null;
let _activeIdx = -1;
let _results = [];

function ensureStyle() {
  if (document.getElementById("dp-search-style")) return;
  const style = document.createElement("style");
  style.id = "dp-search-style";
  style.textContent = `
    .dp-search-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 9000; display: none; align-items: flex-start; justify-content: center; padding-top: 80px; }
    .dp-search-overlay.is-open { display: flex; }
    .dp-search-modal { width: min(720px, calc(100% - 32px)); max-height: calc(100vh - 160px); background: var(--panel, #fff); color: var(--text, #1f2937); border: 1px solid var(--border, #e5e7eb); border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); display: flex; flex-direction: column; overflow: hidden; }
    .dp-search-input-row { display: flex; align-items: center; gap: 10px; padding: 14px 18px; border-bottom: 1px solid var(--border, #e5e7eb); }
    .dp-search-input-row .material-symbols-outlined { font-size: 22px; color: var(--text-muted, #6b7280); }
    .dp-search-input { flex: 1; background: transparent; color: inherit; border: 0; outline: none; font: inherit; font-size: 16px; padding: 4px 0; }
    .dp-search-hint { font-size: 11px; color: var(--text-muted, #6b7280); border: 1px solid var(--border, #e5e7eb); border-radius: 4px; padding: 1px 6px; }
    .dp-search-results { overflow-y: auto; padding: 6px 0; }
    .dp-search-empty { padding: 18px; text-align: center; color: var(--text-muted, #6b7280); font-size: 13px; }
    .dp-search-item { display: block; padding: 10px 18px; cursor: pointer; border-left: 3px solid transparent; text-decoration: none; color: inherit; }
    .dp-search-item:hover, .dp-search-item.is-active { background: var(--accent-soft, #eff4ff); border-left-color: var(--accent, #1d4ed8); }
    .dp-search-item .dp-search-title { font-weight: 700; font-size: 14px; color: var(--text, #1f2937); display: flex; align-items: center; gap: 8px; }
    .dp-search-item .dp-search-kind { display: inline-block; font-size: 10px; font-weight: 700; padding: 1px 6px; border-radius: 3px; background: var(--accent-soft, #eff4ff); color: var(--accent, #1d4ed8); border: 1px solid var(--accent-border, #c7d6f5); flex: 0 0 auto; }
    .dp-search-item .dp-search-path { font-family: ui-monospace, "SF Mono", Consolas, monospace; font-size: 11px; color: var(--text-muted, #6b7280); margin-top: 2px; }
    .dp-search-item .dp-search-snippet { font-size: 12px; color: var(--text-sub, #4b5563); margin-top: 4px; line-height: 1.5; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .dp-search-footer { border-top: 1px solid var(--border, #e5e7eb); padding: 8px 18px; font-size: 11px; color: var(--text-muted, #6b7280); display: flex; gap: 14px; flex-wrap: wrap; }
    .dp-search-footer kbd { background: var(--panel-2, #fafbfc); border: 1px solid var(--border, #e5e7eb); border-bottom-width: 2px; border-radius: 3px; padding: 0 5px; font-family: ui-monospace, "SF Mono", Consolas, monospace; font-size: 11px; }
  `;
  document.head.appendChild(style);
}

function buildModal() {
  const overlay = document.createElement("div");
  overlay.className = "dp-search-overlay";
  overlay.setAttribute("role", "dialog");
  overlay.setAttribute("aria-modal", "true");
  overlay.setAttribute("aria-label", "全体検索");

  const modal = document.createElement("div");
  modal.className = "dp-search-modal";

  const inputRow = document.createElement("div");
  inputRow.className = "dp-search-input-row";
  const icon = document.createElement("span");
  icon.className = "material-symbols-outlined";
  icon.textContent = "search";
  icon.setAttribute("aria-hidden", "true");
  icon.setAttribute("translate", "no");
  const input = document.createElement("input");
  input.type = "search";
  input.className = "dp-search-input";
  input.placeholder = "全文検索（タイトル / 見出し / 本文）...";
  input.setAttribute("aria-label", "検索クエリ");
  const hint = document.createElement("span");
  hint.className = "dp-search-hint";
  hint.textContent = "Esc";
  inputRow.appendChild(icon);
  inputRow.appendChild(input);
  inputRow.appendChild(hint);

  const results = document.createElement("div");
  results.className = "dp-search-results";

  const footer = document.createElement("div");
  footer.className = "dp-search-footer";
  footer.innerHTML = '<span><kbd>↑↓</kbd> 移動</span><span><kbd>Enter</kbd> 開く</span><span><kbd>Esc</kbd> 閉じる</span><span>全 <span class="dp-search-total"></span> 文書</span>';

  modal.appendChild(inputRow);
  modal.appendChild(results);
  modal.appendChild(footer);
  overlay.appendChild(modal);

  document.body.appendChild(overlay);

  overlay.addEventListener("click", (e) => { if (e.target === overlay) close(); });
  input.addEventListener("input", () => { _activeIdx = -1; renderResults(input.value); });
  input.addEventListener("keydown", onInputKey);

  _modal = overlay;
  _input = input;
  _resultsEl = results;
}

function renderResults(query) {
  _resultsEl.innerHTML = "";
  if (!query.trim()) {
    const empty = document.createElement("div");
    empty.className = "dp-search-empty";
    empty.textContent = "キーワードを入力してください。タイトル / 見出し / 本文から候補を表示します。";
    _resultsEl.appendChild(empty);
    _results = [];
    return;
  }
  _results = search(query);
  if (_results.length === 0) {
    const empty = document.createElement("div");
    empty.className = "dp-search-empty";
    empty.textContent = `「${query}」に一致する文書はありません。`;
    _resultsEl.appendChild(empty);
    return;
  }
  for (let i = 0; i < _results.length; i++) {
    const { entry } = _results[i];
    const a = document.createElement("a");
    a.className = "dp-search-item" + (i === _activeIdx ? " is-active" : "");
    a.href = buildEntryUrl(entry);
    const titleRow = document.createElement("div");
    titleRow.className = "dp-search-title";
    if (KIND_LABEL[entry.kind]) {
      const k = document.createElement("span");
      k.className = "dp-search-kind";
      k.textContent = KIND_LABEL[entry.kind];
      titleRow.appendChild(k);
    }
    const t = document.createElement("span");
    t.textContent = entry.title;
    titleRow.appendChild(t);
    const path = document.createElement("div");
    path.className = "dp-search-path";
    path.textContent = entry.path;
    const snippet = document.createElement("div");
    snippet.className = "dp-search-snippet";
    snippet.textContent = entry.snippet;
    a.appendChild(titleRow);
    a.appendChild(path);
    a.appendChild(snippet);
    a.addEventListener("mouseenter", () => { _activeIdx = i; updateActive(); });
    _resultsEl.appendChild(a);
  }
}

function updateActive() {
  const items = _resultsEl.querySelectorAll(".dp-search-item");
  items.forEach((el, i) => el.classList.toggle("is-active", i === _activeIdx));
  const active = items[_activeIdx];
  if (active) active.scrollIntoView({ block: "nearest" });
}

function onInputKey(e) {
  if (e.key === "Escape") { close(); e.preventDefault(); return; }
  if (e.key === "ArrowDown") { _activeIdx = Math.min(_activeIdx + 1, _results.length - 1); updateActive(); e.preventDefault(); return; }
  if (e.key === "ArrowUp") { _activeIdx = Math.max(_activeIdx - 1, 0); updateActive(); e.preventDefault(); return; }
  if (e.key === "Enter") {
    const sel = _results[_activeIdx >= 0 ? _activeIdx : 0];
    if (sel) location.href = buildEntryUrl(sel.entry);
    e.preventDefault();
  }
}

export async function open() {
  if (!_modal) buildModal();
  ensureStyle();
  _modal.classList.add("is-open");
  _input.value = "";
  _input.focus();
  _activeIdx = -1;
  renderResults("");
  const idx = await loadIndex();
  const totalEl = _modal.querySelector(".dp-search-total");
  if (totalEl && idx) totalEl.textContent = idx.entries.length;
}

export function close() {
  if (_modal) _modal.classList.remove("is-open");
}

export function isOpen() {
  return !!_modal && _modal.classList.contains("is-open");
}
