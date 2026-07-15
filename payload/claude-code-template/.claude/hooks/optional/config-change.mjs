// 設定変更の監査ログ（config-change.mjs）
// 有効化: settings.json の hooks に ConfigChange を追加（optional/README.md 参照）
// 設計: 記録 + systemMessage で 1 行警告（ブロックしない）。fail-open。

import { readInput, output, appendLog } from '../lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  appendLog('config-change', {
    changes: JSON.stringify(input.tool_input || {}).slice(0, 500),
  });
  output({
    hookSpecificOutput: {
      hookEventName: 'ConfigChange',
      systemMessage: '設定が変更されました。意図した変更か確認してください。',
    },
  });
} catch { /* fail-open */ }
