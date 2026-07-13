// カテゴリ詳細: 1 カテゴリに属するビジュアルツールをカード一覧で表示する。
// パンくず（TOP / カテゴリ名）と戻る導線を付ける。
// href が "#" で始まる内部ルートは同タブ遷移、それ以外は別タブで開く。
import { VISUAL_TOOL_GROUPS } from "../data/manifest.js?v=4";
import { el } from "./dom.js?v=4";

function backLink() {
  return el("div", { class: "back-link" }, el("a", { href: "#/" }, "← カテゴリ一覧へ戻る"));
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
  card.appendChild(el("div", { class: "card-count" }, isInternal ? "表を開く →" : "別タブで開く ↗"));
  return card;
}

export function renderCategory(catId, root) {
  root.innerHTML = "";
  const group = VISUAL_TOOL_GROUPS.find((g) => g.id === catId);
  if (!group) {
    root.appendChild(el("div", { class: "doc-crumbs", html: '<a href="#/">TOP</a> / 不明なカテゴリ' }));
    root.appendChild(el("p", { class: "card-desc" }, `カテゴリが見つかりません: ${catId}`));
    root.appendChild(backLink());
    return;
  }

  root.appendChild(el("div", {
    class: "doc-crumbs",
    html: `<a href="#/">TOP</a> / ${group.title}`,
  }));

  root.appendChild(el("div", { class: "section-header" }, [
    el("h2", { class: "section-title" }, group.title),
    group.sub ? el("span", { class: "section-sub" }, group.sub) : null,
  ]));

  if (Array.isArray(group.sections) && group.sections.length > 0) {
    renderSections(group, root);
  } else {
    const cards = el("div", { class: "cards" });
    group.tools.forEach((t) => cards.appendChild(toolCard(group, t)));
    root.appendChild(cards);
  }

  root.appendChild(backLink());
}

// sections が定義されたカテゴリは、サブカテゴリ見出し + カード群を群ごとに描画する。
// toolIds に未掲載の tool は末尾の「その他」群へ自動収容し、取りこぼしを防ぐ。
function renderSections(group, root) {
  const byId = new Map(group.tools.map((t) => [t.id, t]));
  const placed = new Set();

  group.sections.forEach((sec) => {
    const tools = (sec.toolIds ?? []).map((id) => byId.get(id)).filter(Boolean);
    if (tools.length === 0) return;
    tools.forEach((t) => placed.add(t.id));
    root.appendChild(subSection(group, sec.icon, sec.title, sec.sub, tools));
  });

  const leftovers = group.tools.filter((t) => !placed.has(t.id));
  if (leftovers.length > 0) {
    root.appendChild(subSection(group, "", "その他", null, leftovers));
  }
}

function subSection(group, icon, title, sub, tools) {
  const wrap = el("section", { class: "cat-subsection" });
  wrap.appendChild(el("div", { class: "cat-sub-head" }, [
    icon ? el("span", { class: "cat-sub-icon" }, icon) : null,
    el("h3", { class: "cat-sub-title" }, title),
    sub ? el("span", { class: "cat-sub-desc" }, sub) : null,
    el("span", { class: "cat-sub-count" }, `${tools.length}`),
  ]));
  const cards = el("div", { class: "cards" });
  tools.forEach((t) => cards.appendChild(toolCard(group, t)));
  wrap.appendChild(cards);
  return wrap;
}
