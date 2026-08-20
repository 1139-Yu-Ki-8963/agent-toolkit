// 成功実行の監査ログ（post-tool-use.mjs）
// 有効化: settings.json の hooks に PostToolUse を追加（optional/README.md 参照）
// 設計: 記録のみ。文脈注入はしない。fail-open。

import { readInput, appendLog } from '../lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  appendLog('tool-use', {
    tool: input.tool_name,
    target: JSON.stringify(input.tool_input || {}).slice(0, 200),
    duration_ms: input.tool_response?.duration_ms,
  });
} catch { /* fail-open */ }
