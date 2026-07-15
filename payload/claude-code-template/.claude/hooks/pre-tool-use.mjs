// 危険操作ガード（pre-tool-use.mjs）
// 配線: PreToolUse — matcher: "Bash|PowerShell|Write|Edit"
// 設計: deny は誤検知ゼロ級の破壊操作のみ。判断が分かれる操作は ask に落とす。
// fail-open: エラー時は素通しする。

import { readInput, preToolDecision, normPath, isSecretPath, stripQuoted, splitSubcommands, appendLog } from './lib/common.mjs';

const DANGEROUS_PATHS = ['/', '/*', '~/', '~/*', '$home', '/etc', '/usr', '/var', '/home'];
const DRIVE_RE = /^[a-z]:[/\\]?$/i;

function isDangerousRmTarget(target) {
  const t = normPath(target.replace(/["']/g, ''));
  if (!t) return false;
  if (DANGEROUS_PATHS.includes(t) || DANGEROUS_PATHS.includes(t.replace(/\/+$/, ''))) return true;
  if (DRIVE_RE.test(target.trim())) return true;
  return false;
}

function isForceFlag(token) {
  if (token === '--force') return true;
  if (token === '-f') return true;
  if (/^-[a-zA-Z]*f[a-zA-Z]*$/.test(token) && token !== '-fd') return true;
  return false;
}

function hasForceNoLease(cmd) {
  if (/--force-with-lease\b/.test(cmd)) return false;
  const tokens = cmd.split(/\s+/);
  return tokens.some(t => isForceFlag(t)) || /--force\b/.test(cmd);
}

function checkRmDanger(sub) {
  if (!/\brm\b/.test(sub)) return null;
  if (/\s-[^\s]*r/.test(sub) && /\s-[^\s]*f/.test(sub)) {
    const parts = sub.split(/\s+/);
    for (const p of parts) {
      if (!p.startsWith('-') && p !== 'rm' && p !== 'sudo' && isDangerousRmTarget(p)) {
        return 'rm -rf の対象が危険なパス (' + p + ') です';
      }
    }
  }
  if (/-[^\s]*rf|-[^\s]*fr/.test(sub)) {
    const parts = sub.split(/\s+/);
    for (const p of parts) {
      if (!p.startsWith('-') && p !== 'rm' && p !== 'sudo' && isDangerousRmTarget(p)) {
        return 'rm -rf の対象が危険なパス (' + p + ') です';
      }
    }
  }
  return null;
}

function checkBashDeny(cmd) {
  const full = stripQuoted(cmd);

  // fork bomb
  if (/:\(\)\s*\{[^}]*\|[^}]*\}\s*;?\s*:/.test(cmd)) return 'fork bomb を検出しました';

  // force push to main/master（-f ショートフラグも検出、--force-with-lease は除外）
  if (/\bgit\s+push\b/.test(full) && hasForceNoLease(full) && /\b(main|master)\b/.test(full)) {
    return 'main/master への force push を検出しました';
  }

  // $() コマンド置換内の rm -rf も検出
  const cmdSubMatches = cmd.match(/\$\(([^)]+)\)/g);
  if (cmdSubMatches) {
    for (const m of cmdSubMatches) {
      const inner = m.slice(2, -1);
      const reason = checkRmDanger(inner);
      if (reason) return reason;
    }
  }

  const subs = splitSubcommands(cmd);
  for (const sub of subs) {
    const rmReason = checkRmDanger(sub);
    if (rmReason) return rmReason;

    // mkfs
    if (/\bmkfs\b/.test(sub)) return 'mkfs を検出しました';
    // dd of=/dev/
    if (/\bdd\b/.test(sub) && /\bof=\/dev\//.test(sub)) return 'dd of=/dev/ を検出しました';
    // Format-Volume / format X:
    if (/\bFormat-Volume\b/i.test(sub)) return 'Format-Volume を検出しました';
    if (/\bformat\s+[a-z]:/i.test(sub)) return 'format (ドライブ) を検出しました';

    // PowerShell Remove-Item（複数フラグをスキップして対象パスを抽出）
    if (/Remove-Item\b/i.test(sub) && /-(Recurse|Force)/i.test(sub)) {
      if (/\$env:USERPROFILE/i.test(sub)) {
        return 'Remove-Item の対象が危険なパスです';
      }
      const tokens = sub.split(/\s+/);
      const riIdx = tokens.findIndex(t => /^Remove-Item$/i.test(t));
      let target = '';
      if (riIdx >= 0) {
        for (let i = riIdx + 1; i < tokens.length; i++) {
          const tok = tokens[i].replace(/["']/g, '');
          if (tok.startsWith('-')) continue;
          target = tok;
          break;
        }
      }
      if (DRIVE_RE.test(target)) {
        return 'Remove-Item の対象が危険なパスです';
      }
    }
  }
  return null;
}

function checkBashAsk(cmd) {
  const full = stripQuoted(cmd);
  // curl/wget | sh
  if (/\b(curl|wget)\b/.test(full) && /\|\s*(sh|bash|zsh)\b/.test(full)) {
    return 'パイプ経由のスクリプト実行を検出しました';
  }
  // PowerShell iwr/irm | iex
  if (/\b(iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b/i.test(full) && /\|\s*(iex|Invoke-Expression)\b/i.test(full)) {
    return 'パイプ経由のスクリプト実行を検出しました';
  }
  const subs = splitSubcommands(cmd);
  for (const sub of subs) {
    // git clean -x
    if (/\bgit\s+clean\b/.test(sub) && /-[^\s]*x/.test(sub)) return 'git clean -x を検出しました';
    // force push (非 main/master、-f ショートフラグも検出)
    if (/\bgit\s+push\b/.test(sub) && hasForceNoLease(sub) && !/\b(main|master)\b/.test(sub)) {
      return 'force push を検出しました';
    }
    // terraform destroy
    if (/\bterraform\s+destroy\b/.test(sub)) return 'terraform destroy を検出しました';
    // kubectl delete namespace
    if (/\bkubectl\s+delete\s+namespace\b/.test(sub)) return 'kubectl delete namespace を検出しました';
    // DROP DATABASE/SCHEMA
    if (/\bDROP\s+(DATABASE|SCHEMA)\b/i.test(sub)) return 'DROP DATABASE/SCHEMA を検出しました';
    // shutdown / reboot
    if (/\b(shutdown|reboot|poweroff|halt)\b/.test(sub)) return 'shutdown/reboot を検出しました';
    // 秘密ファイルパスの参照
    const tokens = sub.split(/\s+/);
    for (const token of tokens) {
      if (isSecretPath(token)) return '秘密ファイル (' + token + ') への操作を検出しました';
    }
  }
  return null;
}

try {
  const input = await readInput();
  if (!input) process.exit(0);

  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};

  // Write / Edit: file_path が秘密ファイルなら ask
  if (toolName === 'Write' || toolName === 'Edit' || toolName === 'MultiEdit') {
    const filePath = toolInput.file_path || '';
    if (isSecretPath(filePath)) {
      appendLog('guard', { tool: toolName, path: filePath, decision: 'ask' });
      preToolDecision('ask', '秘密ファイル (' + filePath + ') への書き込みを検出しました');
    }
    process.exit(0);
  }

  // Bash / PowerShell
  if (toolName === 'Bash' || toolName === 'PowerShell') {
    const command = toolInput.command || '';
    if (!command) process.exit(0);

    const denyReason = checkBashDeny(command);
    if (denyReason) {
      appendLog('guard', { tool: toolName, command, decision: 'deny', reason: denyReason });
      preToolDecision('deny', denyReason);
      process.exit(0);
    }

    const askReason = checkBashAsk(command);
    if (askReason) {
      appendLog('guard', { tool: toolName, command, decision: 'ask', reason: askReason });
      preToolDecision('ask', askReason);
      process.exit(0);
    }

    appendLog('guard', { tool: toolName, command, decision: 'allow' });
  }
} catch { /* fail-open */ }
