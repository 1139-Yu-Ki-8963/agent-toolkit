// エントリポイント。ハッシュルーティングの初期化。
// ルート:
//   #/                  → TOP（カテゴリカード一覧）
//   #/category/<catId>  → カテゴリ詳細（カテゴリ内フローのカード一覧）
//   #/flow/<id>         → フロー詳細（概要・トリガー・ステップ・図・関連スキル・注意）
import { renderTop } from "./top.js?v=4";
import { renderCategory } from "./category-view.js?v=4";
import { renderFlowDetail } from "./flow-detail.js?v=4";

function getRoot() { return document.getElementById("app-main"); }

// 規模サマリ（.metric-grid とそのラベル）は TOP（#/）でのみ表示する。
// ヒーローは #/category/<id> では維持し、#/flow/<id> でのみ非表示にする。
function setTopElementsVisible(heroVisible, summaryVisible) {
  const heroDisplay = heroVisible ? "" : "none";
  const summaryDisplay = summaryVisible ? "" : "none";
  const hero = document.querySelector(".pm-hero");
  const metricGrid = document.querySelector(".metric-grid");
  const summaryLabel = Array.from(document.querySelectorAll(".sec-label"))
    .find((el) => el.textContent.trim() === "規模サマリ");
  if (hero) hero.style.display = heroDisplay;
  if (metricGrid) metricGrid.style.display = summaryDisplay;
  if (summaryLabel) summaryLabel.style.display = summaryDisplay;
}

function route() {
  const root = getRoot();
  if (!root) return;
  root.scrollTo?.(0, 0);
  window.scrollTo?.(0, 0);
  const path = location.hash.replace(/^#/, "") || "/";
  const mCat = path.match(/^\/category\/(.+)$/);
  if (mCat) { setTopElementsVisible(true, false); renderCategory(decodeURIComponent(mCat[1]), root); return; }
  const mFlow = path.match(/^\/flow\/(.+)$/);
  if (mFlow) { setTopElementsVisible(false, false); renderFlowDetail(decodeURIComponent(mFlow[1]), root); return; }
  setTopElementsVisible(true, true);
  renderTop(root);
}

window.addEventListener("hashchange", route);
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", route);
} else {
  route();
}
