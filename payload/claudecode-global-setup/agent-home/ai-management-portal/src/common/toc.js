// ai-management-portal 共通: 長文ページに sticky TOC を右ペインに表示する。
// h2 / h3 が 2 個以上ある場合のみ起動。スクロール位置に応じて現在地ハイライト。

function slugify(text) {
  return (text || "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^\w぀-ヿ㐀-鿿-]/g, "")
    .slice(0, 80) || "section";
}

export function initToc() {
  const headings = [...document.querySelectorAll("main h2, main h3, .pm-main h2, .pm-main h3, .wrap h2, .wrap h3")];
  // dp-search-modal や dp-related 配下を除外
  const eligible = headings.filter((h) => !h.closest(".dp-search-modal, .dp-related, .dp-toc"));
  if (eligible.length < 2) return;

  const aside = document.createElement("aside");
  aside.className = "dp-toc";
  let html = "<h3>目次</h3><ol>";
  for (const h of eligible) {
    if (!h.id) h.id = slugify(h.textContent || "");
    const text = (h.textContent || "").replace(/\s+/g, " ").trim().replace(/§$/, "").trim();
    const depth = h.tagName.toLowerCase() === "h3" ? 3 : 2;
    html += `<li class="depth-${depth}" data-id="${h.id}"><a href="#${h.id}">${text}</a></li>`;
  }
  html += "</ol>";
  aside.innerHTML = html;
  document.body.appendChild(aside);

  const items = [...aside.querySelectorAll("li")];
  const map = new Map(items.map((li) => [li.dataset.id, li]));
  const observer = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (e.isIntersecting) {
          for (const li of items) li.classList.remove("is-current");
          map.get(e.target.id)?.classList.add("is-current");
        }
      }
    },
    { rootMargin: "-30% 0px -55% 0px" },
  );
  for (const h of eligible) observer.observe(h);
}
