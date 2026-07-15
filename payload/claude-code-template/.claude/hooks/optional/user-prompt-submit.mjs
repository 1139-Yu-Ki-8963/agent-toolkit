// 秘密情報の送信ブロック（user-prompt-submit.mjs）
// 有効化: settings.json の hooks に UserPromptSubmit を追加（optional/README.md 参照）
// 設計: 確度の高いパターンのみ検査。fail-open。

import { readInput, output, appendLog } from '../lib/common.mjs';

const PATTERNS = [
  { name: 'PEM秘密鍵', re: /-----BEGIN\s+(?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/ },
  { name: 'AWSアクセスキー', re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'GitHub PAT', re: /\b(ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82})\b/ },
  { name: 'Slackトークン', re: /\bxox[baprs]-[A-Za-z0-9-]+\b/ },
  { name: 'Anthropic APIキー', re: /\bsk-ant-[A-Za-z0-9_-]+\b/ },
  { name: '汎用sk-シークレット', re: /\bsk-[A-Za-z0-9]{20,}\b/ },
  { name: 'JWT', re: /\beyJhbGciOi[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/ },
];

try {
  const input = await readInput();
  if (!input) process.exit(0);
  const prompt = input.tool_input?.prompt || input.tool_input?.message || '';
  if (!prompt) process.exit(0);

  for (const { name, re } of PATTERNS) {
    if (re.test(prompt)) {
      appendLog('prompt-guard', { detected: name, decision: 'block' });
      output({
        hookSpecificOutput: {
          hookEventName: 'UserPromptSubmit',
          decision: 'block',
          reason: `${name}らしき文字列を検出しました。秘密情報をプロンプトに含めないでください。`,
        },
      });
      process.exit(0);
    }
  }
} catch { /* fail-open */ }
