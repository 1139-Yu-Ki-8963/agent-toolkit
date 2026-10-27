#!/usr/bin/env node
// スキル作成の確認と承認の画面の中継(設計: docs/スキル作成の確認と承認の画面/設計書.html)。
// 使い方: skill-factory/ で `node ui/server.mjs`。
// 見本や既にある作業のフォルダを開くときだけ、`node ui/server.mjs <作業のフォルダのパスかスキルの名前>` とする。
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const uiDir = path.dirname(fileURLToPath(import.meta.url));
const factoryDir = path.dirname(uiDir);
const outputDir = path.join(factoryDir, 'output');
const port = Number(process.env.PORT || 4173);
const arg = process.argv[2];

// 会話の ID は、起動ごとに 1 つ。1 回目の送信は --session-id、2 回目からは --resume で同じ会話を続ける
const sessionId = randomUUID();
let sessionStarted = false;
const startTime = Date.now();
// 作業のフォルダが決まる前の会話(仮の会話)の置き場
const pending = path.join(uiDir, '.pending', `${sessionId}.md`);
let workDir = !arg ? null
  : fs.existsSync(arg) && fs.statSync(arg).isDirectory() ? path.resolve(arg) : path.join(outputDir, arg);
let busy = false;

// 作業のフォルダは、起動したあとに output/*/ui/state.json が書かれた最初のフォルダとし、決まったら止めるまで同じフォルダとする
function findWorkDir() {
  if (workDir) return workDir;
  let first = null;
  let firstTime = Infinity;
  for (const name of fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : []) {
    const state = path.join(outputDir, name, 'ui', 'state.json');
    if (!fs.existsSync(state)) continue;
    const time = fs.statSync(state).mtimeMs;
    if (time >= startTime && time < firstTime) {
      first = path.join(outputDir, name);
      firstTime = time;
    }
  }
  if (first) {
    workDir = first;
    // 仮の会話を、作業のフォルダの conversation.md の後ろに移す
    if (fs.existsSync(pending)) {
      const conv = path.join(workDir, 'ui', 'conversation.md');
      fs.appendFileSync(conv, fs.readFileSync(pending, 'utf8'));
      fs.rmSync(pending);
    }
  }
  return workDir;
}

function conversationPath() {
  const dir = findWorkDir();
  return dir ? path.join(dir, 'ui', 'conversation.md') : pending;
}

// conversation.md の 1 件は、「ユーザー:」か「Claude Code:」で始まる行から、次の同じ形の行の前まで
function append(who, text) {
  const conv = conversationPath();
  fs.mkdirSync(path.dirname(conv), {recursive: true});
  fs.appendFileSync(conv, `${who}: ${text.trim()}\n\n`);
}

// 画面からの文を conversation.md に追記し、Claude Code に渡し、途中の返事も 1 つずつ追記する
function prompt(text) {
  append('ユーザー', text);
  busy = true;
  const args = ['-p', sessionStarted ? '--resume' : '--session-id', sessionId,
    '--output-format', 'stream-json', '--verbose',
    // claude -p は許可の確認に答えられないので、ファイルの書き込みを許す
    '--permission-mode', 'acceptEdits', text];
  const child = spawn('claude', args, {cwd: factoryDir, stdio: ['ignore', 'pipe', 'pipe']});
  let rest = '';
  let err = '';
  let replied = false;
  child.stdout.on('data', d => {
    rest += d;
    const lines = rest.split('\n');
    rest = lines.pop();
    for (const line of lines) {
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.type === 'system' && msg.subtype === 'init') sessionStarted = true;
      if (msg.type !== 'assistant') continue;
      for (const c of msg.message.content || []) {
        if (c.type === 'text' && c.text.trim()) { append('Claude Code', c.text); replied = true; }
      }
    }
  });
  child.stderr.on('data', d => { err += d; });
  child.on('error', e => { err += e.message; });
  child.on('close', code => {
    busy = false;
    if (code !== 0 || !replied) append('Claude Code', `(終了コード ${code}) ${err.trim()}`);
  });
}

// 段階の名前は、画面の段階の帯と同じ
const STAGES = ['要件定義書', '分割設計書', '構成の案', 'SKILL.md の下書き', '照合と修正', 'テスト計画書', 'シナリオ', 'テストの実行'];

function lastModified(dir) {
  let time = fs.statSync(dir).mtimeMs;
  for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
    const full = path.join(dir, e.name);
    time = Math.max(time, e.isDirectory() ? lastModified(full) : fs.statSync(full).mtimeMs);
  }
  return time;
}

// 作業のフォルダが決まる前に画面の文書の欄に出す md。ui/はじめに.md の後ろに、動く準備と既にあるスキルを足す
function startPage() {
  const lines = [fs.readFileSync(path.join(uiDir, 'はじめに.md'), 'utf8'), '## 動く準備', ''];
  const v = spawnSync('claude', ['--version'], {encoding: 'utf8'});
  lines.push('- 中継サーバー: 動いている');
  lines.push(v.status === 0
    ? `- Claude Code: ${v.stdout.trim()}`
    : '- Claude Code: `claude` のコマンドがない。`npm install -g @anthropic-ai/claude-code` で入れてから、中継サーバーを起動し直す');
  lines.push('', '## 既にあるスキル', '');
  const names = fs.existsSync(outputDir)
    ? fs.readdirSync(outputDir, {withFileTypes: true}).filter(e => e.isDirectory()).map(e => e.name) : [];
  if (!names.length) lines.push('なし');
  else {
    lines.push('| スキルの名前 | いまの段階 | 最後に変えた日時 |', '|---|---|---|');
    for (const name of names.sort()) {
      const dir = path.join(outputDir, name);
      const statePath = path.join(dir, 'ui', 'state.json');
      let stage = 'なし';
      try { const n = JSON.parse(fs.readFileSync(statePath, 'utf8')).stage; stage = `${n} ${STAGES[n - 1]}`; } catch {}
      const time = new Date(lastModified(dir)).toLocaleString('ja-JP');
      lines.push(`| ${name} | ${stage} | ${time} |`);
    }
  }
  return lines.join('\n') + '\n';
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, {'Content-Type': 'text/plain; charset=utf-8', ...headers});
  res.end(body);
}

const types = {'.html': 'text/html', '.json': 'application/json', '.md': 'text/markdown', '.svg': 'image/svg+xml', '.txt': 'text/plain'};

function sendFile(res, file, download) {
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return send(res, 404, 'ファイルがありません');
  const headers = {'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store'};
  if (download) headers['Content-Disposition'] = `attachment; filename*=UTF-8''${encodeURIComponent(path.basename(file))}`;
  send(res, 200, fs.readFileSync(file), headers);
}

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/') {
    return send(res, 200, fs.readFileSync(path.join(uiDir, 'index.html')), {'Content-Type': 'text/html; charset=utf-8'});
  }
  if (req.method === 'GET' && url.pathname === '/api/status') {
    return send(res, 200, JSON.stringify({busy}), {'Content-Type': 'application/json'});
  }
  if (req.method === 'GET' && url.pathname === '/api/start') {
    return send(res, 200, startPage(), {'Content-Type': 'text/markdown; charset=utf-8', 'Cache-Control': 'no-store'});
  }
  if (req.method === 'GET' && url.pathname.startsWith('/files/')) {
    const rel = decodeURIComponent(url.pathname.slice('/files/'.length));
    if (rel === 'ui/conversation.md') return sendFile(res, conversationPath(), false);
    const dir = findWorkDir();
    if (!dir) return send(res, 404, '作業のフォルダがまだありません');
    // 作業のフォルダの下のファイルだけを返す
    const file = path.resolve(dir, rel);
    if (!file.startsWith(dir + path.sep)) return send(res, 403, '作業のフォルダの外のファイルです');
    return sendFile(res, file, url.searchParams.has('download'));
  }
  if (req.method === 'POST' && url.pathname === '/api/prompt') {
    let body = '';
    req.on('data', d => { body += d; });
    req.on('end', () => {
      const text = String(JSON.parse(body || '{}').text || '').trim();
      if (!text) return send(res, 400, '文が空です');
      if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに送ってください。');
      prompt(text);
      send(res, 202, '送りました');
    });
    return;
  }
  send(res, 404, 'ありません');
}).listen(port, '127.0.0.1', () => {
  console.log(`作業のフォルダ: ${workDir || 'AI が state.json を書いたときに決まる'}`);
  console.log(`画面: http://127.0.0.1:${port}/`);
});
