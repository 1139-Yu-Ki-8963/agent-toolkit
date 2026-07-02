// ai-management-portal 共通: ページ単位の操作ボタン（MD コピー / MD DL / LLM コピー）
// 「文書として持ち出す価値のあるページ」（design/・claude/ 配下）にのみ、最初の <h1> 直後（hero がある場合は hero 直後）に .dp-page-actions を挿入する。
// index.html・catalog/ 等の一覧・ダッシュボード画面では何もしない。

import { pageToMd, copyToClipboard, downloadMd, safeFilename } from "./md-export.js";
import { copyLlmPrompt } from "./llm-context.js";
import { makeBtn, flashBtn, findPortalRoot } from "./controls.js";

function isDocPage() {
  const portalRoot = findPortalRoot();
  if (!portalRoot) return false;
  const rootPath = new URL(portalRoot).pathname;
  const curPath = location.pathname;
  if (!curPath.startsWith(rootPath)) return false;
  const rel = curPath.slice(rootPath.length);
  return rel.startsWith("design/") || rel.startsWith("claude/");
}

export function initPageActions() {
  if (!isDocPage()) return;

  const h1 = document.querySelector("h1");
  if (!h1) return;

  const host = document.createElement("div");
  host.className = "dp-page-actions";

  const copyCtl = makeBtn({
    iconName: "content_copy",
    ariaLabel: "ページ全体を Markdown としてコピー",
    labelText: "MD コピー",
    onClick: async () => {
      const ok = await copyToClipboard(pageToMd());
      flashBtn(copyCtl, ok ? "✓ コピー済" : "失敗");
    },
  });

  const downloadCtl = makeBtn({
    iconName: "download",
    ariaLabel: "ページ全体を .md としてダウンロード",
    labelText: "MD DL",
    onClick: () => {
      const title = (document.querySelector("h1")?.textContent || document.title || "page").trim();
      downloadMd(pageToMd(), safeFilename(title) + ".md");
      flashBtn(downloadCtl, "✓ DL");
    },
  });

  const llmCtl = makeBtn({
    iconName: "smart_toy",
    ariaLabel: "ページ全体を LLM 入力プロンプトとしてコピー",
    labelText: "LLM コピー",
    onClick: async () => {
      const ok = await copyLlmPrompt();
      flashBtn(llmCtl, ok ? "✓ LLM" : "失敗");
    },
  });

  host.appendChild(copyCtl.btn);
  host.appendChild(downloadCtl.btn);
  host.appendChild(llmCtl.btn);

  const hero = h1.closest(".page-hero, .pm-hero");
  const anchor = hero || h1;
  anchor.insertAdjacentElement("afterend", host);
}
