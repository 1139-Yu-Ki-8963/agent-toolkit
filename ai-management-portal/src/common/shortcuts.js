// ai-management-portal 共通: キーボードショートカット
// "g d"      → ダッシュボード TOP
// "g s"      → スキル一覧
// "?"        → ショートカット一覧モーダル

import { findPortalRoot } from "./controls.js";

function go(path) {
  const root = findPortalRoot();
  if (!root) return;
  location.href = root + path;
}

const GO_TARGETS = {
  d: "index.html",
  s: "catalog/skills.html",
};

let _gPending = false;
let _gTimer = null;

function isTypingTarget(el) {
  if (!el) return false;
  const tag = el.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA") return true;
  if (el.isContentEditable) return true;
  return false;
}

function openHelp() {
  if (document.getElementById("dp-shortcut-help")) return;
  const overlay = document.createElement("div");
  overlay.id = "dp-shortcut-help";
  overlay.className = "dp-search-overlay is-open";
  overlay.style.zIndex = "9100";
  const modal = document.createElement("div");
  modal.className = "dp-search-modal";
  modal.style.maxWidth = "480px";
  modal.innerHTML = `
    <div class="dp-search-input-row"><span class="material-symbols-outlined">keyboard</span><div class="dp-search-input" style="font-weight:700">キーボードショートカット</div></div>
    <div class="dp-search-results" style="padding:10px 18px;font-size:13px">
      <p><kbd>g</kbd> <kbd>d</kbd> ダッシュボード TOP</p>
      <p><kbd>g</kbd> <kbd>s</kbd> スキル一覧</p>
      <p><kbd>?</kbd> このヘルプを開く</p>
      <p><kbd>Esc</kbd> 閉じる</p>
    </div>`;
  overlay.appendChild(modal);
  document.body.appendChild(overlay);
  overlay.addEventListener("click", (e) => { if (e.target === overlay) overlay.remove(); });
  const onKey = (e) => { if (e.key === "Escape") { overlay.remove(); document.removeEventListener("keydown", onKey); } };
  document.addEventListener("keydown", onKey);
}

function onKey(e) {
  if (e.altKey || e.ctrlKey || e.metaKey) return;
  if (isTypingTarget(e.target)) return;

  if (_gPending) {
    const target = GO_TARGETS[e.key.toLowerCase()];
    _gPending = false;
    clearTimeout(_gTimer);
    if (target) { go(target); e.preventDefault(); return; }
    return;
  }

  if (e.key === "?") { openHelp(); e.preventDefault(); return; }
  if (e.key === "g") {
    _gPending = true;
    _gTimer = setTimeout(() => { _gPending = false; }, 1200);
    e.preventDefault();
    return;
  }
}

export function initShortcuts() {
  document.addEventListener("keydown", onKey);
}
