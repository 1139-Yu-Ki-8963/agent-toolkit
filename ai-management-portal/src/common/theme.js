// ai-management-portal 共通: テーマ切替（ライト / ダーク）
// data-theme 属性を <html> に付与し localStorage 永続化する。
// 初回は localStorage > prefers-color-scheme > "light" の優先順で決定する。
// 各サブサイト・ HTML はこのモジュールを直接 import しない。`header.js` 経由で組み込まれる。

const STORAGE_KEY = "ai-management-portal:theme";

export function getCurrentTheme() {
  return document.documentElement.getAttribute("data-theme") || "light";
}

export function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  try { localStorage.setItem(STORAGE_KEY, theme); } catch {}
  document.dispatchEvent(new CustomEvent("ai-management-portal:theme-change", { detail: { theme } }));
}

export function cycleTheme() {
  const next = getCurrentTheme() === "dark" ? "light" : "dark";
  applyTheme(next);
  return next;
}

export function initTheme() {
  let initial;
  try { initial = localStorage.getItem(STORAGE_KEY); } catch {}
  if (!initial) {
    initial = matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  document.documentElement.setAttribute("data-theme", initial);
}
