// ai-management-portal 共通: 検索インデックスの遅延読込・スコアリング
// 検索 UI が初回アクセス時のみ動的 import する。

let _index = null;
let _loading = null;

const SEARCH_INDEX_PATH = "data/search-index.js";

function findPortalRoot() {
  // 現在の URL パスから ai-management-portal ルートを推定する。
  const u = new URL(location.href);
  const pieces = u.pathname.split("/");
  const i = pieces.lastIndexOf("ai-management-portal");
  if (i < 0) return null;
  pieces.length = i + 1;
  return u.origin + pieces.join("/") + "/";
}

export async function loadIndex() {
  if (_index) return _index;
  if (_loading) return _loading;
  _loading = (async () => {
    const root = findPortalRoot();
    if (!root) return null;
    const mod = await import(root + SEARCH_INDEX_PATH);
    _index = mod.default;
    return _index;
  })();
  return _loading;
}

// 簡易スコアリング: タイトル一致 > 見出し一致 > 本文一致
export function search(query, { limit = 30 } = {}) {
  if (!_index) return [];
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const terms = q.split(/\s+/).filter(Boolean);
  const results = [];
  for (const entry of _index.entries) {
    const title = entry.title.toLowerCase();
    const headings = entry.headings.join(" ").toLowerCase();
    const snippet = entry.snippet.toLowerCase();
    let score = 0;
    let matchedTerms = 0;
    for (const t of terms) {
      let termScore = 0;
      if (title.includes(t)) termScore += 10;
      if (headings.includes(t)) termScore += 5;
      if (snippet.includes(t)) termScore += 1;
      if (termScore > 0) matchedTerms++;
      score += termScore;
    }
    if (matchedTerms === terms.length && score > 0) {
      results.push({ entry, score });
    }
  }
  results.sort((a, b) => b.score - a.score);
  return results.slice(0, limit);
}

export function buildPortalUrl(relPath) {
  const root = findPortalRoot();
  if (!root) return relPath;
  return root + relPath;
}
