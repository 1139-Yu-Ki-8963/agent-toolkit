// 権限ダイアログの監査ログ（permission-request.mjs）
// 有効化: settings.json の hooks に PermissionRequest を追加（optional/README.md 参照）
// 設計: 記録のみ。自動 allow / deny はしない。fail-open。

import { readInput, appendLog } from '../lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  appendLog('permission', {
    tool: input.tool_name,
    input: JSON.stringify(input.tool_input || {}).slice(0, 200),
  });
} catch { /* fail-open */ }
