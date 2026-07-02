// ページ本文を LLM 入力プロンプト形式 (説明 prefix + MD 本体) でクリップボードに入れる。

import { pageToMd, copyToClipboard } from "./md-export.js";

const PROMPT_PREFIX = (title) =>
  `以下は AI マネジメントポータルのドキュメント「${title}」です。読み込んでください。\n\n` +
  `---\n\n`;

export async function copyLlmPrompt() {
  const title = (document.querySelector("h1")?.textContent || document.title || "ドキュメント").trim();
  const md = pageToMd();
  const text = PROMPT_PREFIX(title) + md;
  return copyToClipboard(text);
}
