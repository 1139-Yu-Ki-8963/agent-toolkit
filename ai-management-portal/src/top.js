// TOP 画面: カテゴリのカードリンクだけを並べる。
// 各カードは #/category/<id> へ遷移し、category-view がそのカテゴリのツール一覧を描画する。
import { VISUAL_TOOL_GROUPS } from "../data/manifest.js?v=4";
import { el } from "./dom.js?v=4";

function categoryCard(group) {
  const isEmpty = group.tools.length === 0;
  const card = el("a", { class: `card is-category group-${group.id}${isEmpty ? " is-coming-soon" : ""}`, href: `#/category/${encodeURIComponent(group.id)}` });
  card.appendChild(el("div", { class: "card-head" }, [
    group.icon ? el("span", { class: "card-icon material-symbols-outlined" }, group.icon) : null,
    el("span", { class: "card-title" }, group.title),
  ]));
  if (group.sub) card.appendChild(el("div", { class: "card-desc" }, group.sub));
  card.appendChild(el("div", { class: "card-count" }, group.tools.length > 0 ? `${group.tools.length} ツール →` : "準備中"));
  return card;
}

function toolCard(group, tool) {
  const isInternal = tool.href.startsWith("#");
  const attrs = { class: `card is-visual group-${group.id}`, href: tool.href };
  if (!isInternal) { attrs.target = "_blank"; attrs.rel = "noopener"; }
  const card = el("a", attrs);
  card.appendChild(el("div", { class: "card-head" }, [
    tool.icon ? el("span", { class: "card-icon" }, tool.icon) : null,
    el("span", { class: "card-title" }, tool.title),
    tool.badge ? el("span", { class: "card-badge" }, tool.badge) : null,
  ]));
  card.appendChild(el("div", { class: "card-desc" }, tool.description));
  card.appendChild(el("div", { class: "card-count" }, isInternal ? "詳細を開く →" : "ガイドを開く ↗"));
  return card;
}

function renderCatalogExpanded(group, root) {
  const byId = new Map(group.tools.map((t) => [t.id, t]));
  (group.sections || []).forEach((sec) => {
    const tools = sec.toolIds.map((id) => byId.get(id)).filter(Boolean);
    if (tools.length === 0) return;
    const wrap = el("section", { class: "cat-subsection" });
    wrap.appendChild(el("div", { class: "cat-sub-head" }, [
      el("h3", { class: "cat-sub-title" }, sec.title),
      sec.sub ? el("span", { class: "cat-sub-desc" }, sec.sub) : null,
      el("span", { class: "cat-sub-count" }, `${tools.length}`),
    ]));
    const cards = el("div", { class: "cards" });
    tools.forEach((t) => cards.appendChild(toolCard(group, t)));
    wrap.appendChild(cards);
    root.appendChild(wrap);
  });
}

export function renderTop(root) {
  root.innerHTML = "";
  const cards = el("div", { class: "cards" });
  VISUAL_TOOL_GROUPS.forEach((g) => {
    cards.appendChild(categoryCard(g));
  });
  root.appendChild(cards);
}
