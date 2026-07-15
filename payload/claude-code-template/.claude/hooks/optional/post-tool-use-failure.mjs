// 失敗の監査ログ（post-tool-use-failure.mjs）
// 有効化: settings.json の hooks に PostToolUseFailure を追加（optional/README.md 参照）
// 設計: 記録 + EACCES/ENOSPC のみ additionalContext を返す。fail-open。

import { readInput, output, appendLog } from '../lib/common.mjs';

try {
  const input = await readInput();
  if (!input) process.exit(0);
  const error = (input.tool_response?.error || '').slice(0, 500);
  appendLog('tool-failure', { tool: input.tool_name, error });

  if (/EACCES|EPERM|Access is denied/i.test(error)) {
    output({
      hookSpecificOutput: {
        hookEventName: 'PostToolUseFailure',
        additionalContext: 'OS の権限エラーが発生しました。ファイルやディレクトリの権限を確認してください。',
      },
    });
  } else if (/ENOSPC/i.test(error)) {
    output({
      hookSpecificOutput: {
        hookEventName: 'PostToolUseFailure',
        additionalContext: 'ディスク容量が不足しています。不要なファイルを削除してください。',
      },
    });
  }
} catch { /* fail-open */ }
