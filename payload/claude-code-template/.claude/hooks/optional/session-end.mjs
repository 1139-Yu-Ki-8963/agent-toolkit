// 終了記録（session-end.mjs）
// 有効化: settings.json の hooks に SessionEnd を追加（optional/README.md 参照）
// 設計: 記録のみ。既定タイムアウトが短い（5秒）ため重い処理を足してはならない。fail-open。

import { readInput, appendLog } from '../lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  appendLog('session', { event: 'end' });
} catch { /* fail-open */ }
