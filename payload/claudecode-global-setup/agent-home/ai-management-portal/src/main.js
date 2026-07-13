// エントリポイント。ハッシュルーティングの初期化。
// ルート:
//   #/                  → TOP（カテゴリカード一覧）
//   #/category/<catId>  → カテゴリ詳細（カテゴリ内フローのカード一覧）
//   #/flow/<id>         → フロー詳細（概要・トリガー・ステップ・図・関連スキル・注意）
import { renderTop } from "./top.js?v=4";
import { renderCategory } from "./category-view.js?v=4";
import { renderFlowDetail } from "./flow-detail.js?v=4";

function getRoot() { return document.getElementById("app-main"); }

// #/flow/<id> では TOP 専用要素（ヒーロー・規模サマリ）を非表示にする。
// それ以外のルートでは元に戻す。
function setTopElementsVisible(visible) {
  const display = visible ? "" : "none";
  const hero = document.querySelector(".pm-hero");
  const metricGrid = document.querySelector(".metric-grid");
  const summaryLabel = Array.from(document.querySelectorAll(".sec-label"))
    .find((el) => el.textContent.trim() === "規模サマリ");
  if (hero) hero.style.display = display;
  if (metricGrid) metricGrid.style.display = display;
  if (summaryLabel) summaryLabel.style.display = display;
}

function route() {
  const root = getRoot();
  if (!root) return;
  root.scrollTo?.(0, 0);
  window.scrollTo?.(0, 0);
  const path = location.hash.replace(/^#/, "") || "/";
  const mCat = path.match(/^\/category\/(.+)$/);
  if (mCat) { setTopElementsVisible(true); renderCategory(decodeURIComponent(mCat[1]), root); return; }
  const mFlow = path.match(/^\/flow\/(.+)$/);
  if (mFlow) { setTopElementsVisible(false); renderFlowDetail(decodeURIComponent(mFlow[1]), root); return; }
  setTopElementsVisible(true);
  renderTop(root);
}

window.addEventListener("hashchange", route);
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", route);
} else {
  route();
}
