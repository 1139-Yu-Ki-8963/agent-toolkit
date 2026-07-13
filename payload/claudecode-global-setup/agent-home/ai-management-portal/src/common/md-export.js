// ai-management-portal 共通: HTML → Markdown 変換 (現在表示中の <main> 内本文をターゲットにする最小実装)

const DEFAULT_SELECTOR = "main, .pm-main, .app .main, .wrap main, body";

function findMain(doc) {
  for (const sel of DEFAULT_SELECTOR.split(",").map((s) => s.trim())) {
    const el = doc.querySelector(sel);
    if (el) return el;
  }
  return doc.body;
}

function shouldSkip(node) {
  if (node.nodeType !== Node.ELEMENT_NODE) return false;
  if (!node.classList) return false;
  return (
    node.classList.contains("dp-share-btn") ||
    node.classList.contains("dp-pre-copy") ||
    node.classList.contains("dp-table-export") ||
    node.classList.contains("dp-controls") ||
    node.classList.contains("dp-search-overlay")
  );
}

function inlineMd(node) {
  if (node.nodeType === Node.TEXT_NODE) return node.textContent.replace(/\s+/g, " ");
  if (node.nodeType !== Node.ELEMENT_NODE) return "";
  if (shouldSkip(node)) return "";
  const tag = node.tagName.toLowerCase();
  if (tag === "button") return "";
  const inner = [...node.childNodes].map(inlineMd).join("");
  if (tag === "code") return "`" + inner.replace(/`/g, "\\`") + "`";
  if (tag === "strong" || tag === "b") return `**${inner}**`;
  if (tag === "em" || tag === "i") return `*${inner}*`;
  if (tag === "a") return `[${inner}](${node.getAttribute("href") || ""})`;
  if (tag === "br") return "\n";
  return inner;
}

function blockMd(node, depth = 0) {
  if (node.nodeType === Node.TEXT_NODE) {
    const t = node.textContent.replace(/\s+/g, " ").trim();
    return t ? t + "\n\n" : "";
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return "";
  if (shouldSkip(node)) return "";
  const tag = node.tagName.toLowerCase();
  if (["script", "style", "noscript", "template", "header", "footer", "nav", "aside", "button"].includes(tag)) return "";

  switch (tag) {
    case "h1": return `# ${inlineMd(node).trim()}\n\n`;
    case "h2": return `## ${inlineMd(node).trim()}\n\n`;
    case "h3": return `### ${inlineMd(node).trim()}\n\n`;
    case "h4": return `#### ${inlineMd(node).trim()}\n\n`;
    case "h5": return `##### ${inlineMd(node).trim()}\n\n`;
    case "h6": return `###### ${inlineMd(node).trim()}\n\n`;
    case "p": {
      const txt = inlineMd(node).trim();
      return txt ? txt + "\n\n" : "";
    }
    case "ul": return [...node.children].map((li) => `- ${inlineMd(li).trim()}`).join("\n") + "\n\n";
    case "ol": return [...node.children].map((li, i) => `${i + 1}. ${inlineMd(li).trim()}`).join("\n") + "\n\n";
    case "pre": {
      const code = node.querySelector("code");
      const lang = code ? (code.className.match(/language-(\w+)/)?.[1] ?? "") : "";
      const txt = (code || node).textContent.replace(/\n+$/, "");
      return "```" + lang + "\n" + txt + "\n```\n\n";
    }
    case "blockquote": {
      const inner = [...node.childNodes].map((c) => blockMd(c, depth + 1)).join("");
      return inner.split("\n").map((l) => l ? `> ${l}` : ">").join("\n") + "\n\n";
    }
    case "table": return tableMd(node) + "\n\n";
    case "hr": return "---\n\n";
    case "br": return "\n";
    default: {
      // ブロック子を再帰
      return [...node.childNodes].map((c) => blockMd(c, depth + 1)).join("");
    }
  }
}

export function tableMd(table) {
  const rows = [...table.querySelectorAll("tr")];
  if (rows.length === 0) return "";
  const cellText = (cell) => inlineMd(cell).replace(/\|/g, "\\|").trim();
  const head = rows[0];
  const heads = [...head.children].map(cellText);
  const align = heads.map(() => "---");
  const body = rows.slice(1).map((r) => "| " + [...r.children].map(cellText).join(" | ") + " |");
  return "| " + heads.join(" | ") + " |\n| " + align.join(" | ") + " |\n" + body.join("\n");
}

export function tableTsv(table) {
  return [...table.querySelectorAll("tr")]
    .map((r) => [...r.children].map((c) => c.textContent.replace(/\s+/g, " ").trim()).join("\t"))
    .join("\n");
}

export function tableCsv(table) {
  const escape = (s) => {
    const t = s.replace(/\s+/g, " ").trim();
    return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
  };
  return [...table.querySelectorAll("tr")]
    .map((r) => [...r.children].map((c) => escape(c.textContent)).join(","))
    .join("\n");
}

export function pageToMd(rootEl) {
  const root = rootEl || findMain(document);
  const md = blockMd(root).replace(/\n{3,}/g, "\n\n").trim();
  return md + "\n";
}

export async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // fallback
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); return true; }
    finally { ta.remove(); }
  }
}

export function downloadMd(text, filename) {
  const blob = new Blob([text], { type: "text/markdown;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

export function safeFilename(s) {
  return (s || "page").replace(/[\/\\:*?"<>|]/g, "_").slice(0, 100).trim() || "page";
}
