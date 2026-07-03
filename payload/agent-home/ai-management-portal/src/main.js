// エントリポイント。ハッシュルーティングの初期化。
// ルート:
//   #/                  → TOP（カテゴリカード一覧）
//   #/category/<catId>  → カテゴリ詳細（カテゴリ内ツールのカード一覧）
import { renderTop } from "./top.js";
import { renderCategory } from "./category-view.js";

function getRoot() { return document.getElementById("app-main"); }

function route() {
  const root = getRoot();
  if (!root) return;
  root.scrollTo?.(0, 0);
  window.scrollTo?.(0, 0);
  const path = location.hash.replace(/^#/, "") || "/";
  const mCat = path.match(/^\/category\/(.+)$/);
  if (mCat) { renderCategory(decodeURIComponent(mCat[1]), root); return; }
  renderTop(root);
}

window.addEventListener("hashchange", route);
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", route);
} else {
  route();
}
