// hooks 共通ライブラリ
// 全 hook がこのファイルを import する。node: ビルトインのみ使用（npm 依存禁止）。
// エラー時は素通しする fail-open 設計。

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

export function projectDir() {
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

export async function readInput() {
  try {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    let raw = Buffer.concat(chunks).toString('utf8');
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    return JSON.parse(raw);
  } catch { return null; }
}

export function output(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

export function preToolDecision(decision, reason) {
  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: decision,
      permissionDecisionReason: reason,
    },
  });
}

export function normPath(p) {
  if (!p) return '';
  return p.replace(/\\/g, '/').replace(/\/+/g, '/').toLowerCase();
}

export function isSecretBasename(base) {
  if (!base) return false;
  const lower = base.toLowerCase();
  if (lower === '.env') return true;
  if (lower.startsWith('.env.')) {
    const safeSuffixes = ['.example', '.sample', '.template', '.dist', '.schema'];
    if (safeSuffixes.some(s => lower.endsWith(s))) return false;
    return true;
  }
  if (/\.(pem|p12|pfx)$/i.test(base)) return true;
  if (/^id_(rsa|ed25519|ecdsa|dsa)$/i.test(lower)) return true;
  if (/^id_(rsa|ed25519|ecdsa|dsa)\./i.test(lower) && !lower.endsWith('.pub')) return true;
  if (lower === '.netrc' || lower === '.htpasswd') return true;
  return false;
}

export function isSecretPath(p) {
  const np = normPath(p);
  const base = np.split('/').pop() || '';
  if (isSecretBasename(base)) return true;
  if (/(?:^|\/)(secrets|\.ssh|\.aws)\//.test(np)) return true;
  return false;
}

export function stripQuoted(cmd) {
  if (!cmd) return '';
  let result = cmd;
  result = result.replace(/<<-?\s*'?(\w+)'?.*?\n[\s\S]*?\n\s*\1/g, '');
  result = result.replace(/'[^']*'/g, '');
  result = result.replace(/"([^"]*)"/g, (match, inner) => {
    if (inner.includes('$(')) return match;
    return '';
  });
  return result;
}

export function splitSubcommands(cmd) {
  const stripped = stripQuoted(cmd);
  return stripped.split(/\s*(?:&&|;)\s*/).map(s => s.trim()).filter(Boolean);
}

export function findAdaptMarkers(root) {
  const markers = [];
  const markerRe = /<!--\s*ADAPT:/;
  function scanFile(filePath, relPath) {
    try {
      const content = readFileSync(filePath, 'utf8');
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (markerRe.test(lines[i])) {
          markers.push({ file: relPath, line: i + 1, text: lines[i].trim() });
        }
      }
    } catch { /* fail-open */ }
  }
  scanFile(join(root, 'CLAUDE.md'), 'CLAUDE.md');
  function scanDir(dir, relDir) {
    try {
      const entries = readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = join(dir, entry.name);
        const relPath = relDir ? relDir + '/' + entry.name : entry.name;
        if (entry.isDirectory()) scanDir(fullPath, relPath);
        else if (entry.isFile() && entry.name.endsWith('.md')) {
          scanFile(fullPath, '.claude/rules/' + relPath);
        }
      }
    } catch { /* fail-open */ }
  }
  scanDir(join(root, '.claude', 'rules'), '');
  return markers;
}

export function appendLog(name, record) {
  try {
    const logsDir = join(projectDir(), '.claude', 'hooks', 'logs');
    mkdirSync(logsDir, { recursive: true });
    const logPath = join(logsDir, name + '.log');
    const entry = JSON.stringify({ ts: new Date().toISOString(), ...record }) + '\n';
    try {
      const stat = statSync(logPath);
      if (stat.size > 1024 * 1024) {
        const content = readFileSync(logPath, 'utf8');
        const lines = content.split('\n');
        const half = Math.floor(lines.length / 2);
        writeFileSync(logPath, lines.slice(half).join('\n'));
      }
    } catch { /* ファイル未存在は無視 */ }
    writeFileSync(logPath, entry, { flag: 'a' });
  } catch { /* fail-open */ }
}
