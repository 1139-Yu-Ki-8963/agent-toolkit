#!/usr/bin/env node
// スキル作成の確認と承認の画面の中継サーバー(設計: docs/スキル作成の確認と承認の画面/設計書.html)。
// 使い方: skill-factory/ で `node ui/server.mjs`。
// 作業のフォルダは、AI が output/<開始日時>/ui/state.json を書いたときに決まる。途中の作業は、画面の「続きから」(/api/resume)で開く。
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
// 別名 sonnet は、そのときの最新の Sonnet を指す
const model = process.env.CLAUDE_MODEL || 'sonnet';

// 会話の ID は、起動ごとに 1 つ。1 回目の送信は --session-id、2 回目からは --resume で同じ会話を続ける。
// 作業のフォルダの ui/session.json から再開したときは、その ID で --resume する
let sessionId = randomUUID();
let sessionStarted = false;
const startTime = Date.now();
// 作業のフォルダが決まる前の会話(仮の会話)の置き場
let pending = path.join(uiDir, '.pending', `${sessionId}.md`);
let workDir = null;
let busy = false;
// いま動いている claude の子プロセス(止めるときに kill する)
let child = null;
// Claude Code が Skill のツールで呼んだスキルの名前を、呼んだ順に並べたもの(起動から止めるまで)
const skillCalls = [];
// Agent か Task のツールの呼び出しのうち、結果がまだ返っていないものの id
const openAgents = new Set();

// 作業のフォルダが決まったら、その ui/session.json に会話の ID を書く(再開のときに読む)
function saveSession(dir) {
  fs.mkdirSync(path.join(dir, 'ui'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'ui', 'session.json'), JSON.stringify({sessionId}) + '\n');
}

// 作業のフォルダは、起動したあとに output/*/ui/state.json が書かれた最初のフォルダとし、決まったら止めるまで同じフォルダとする
function findWorkDir() {
  // state.json が消えた(スキルの名前を変えて移した)作業のフォルダは探し直す
  if (workDir && !fs.existsSync(path.join(workDir, 'ui', 'state.json'))) workDir = null;
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
    saveSession(workDir);
    // 仮の会話を、作業のフォルダの conversation.md の後ろに移す
    if (fs.existsSync(pending)) {
      const conv = path.join(workDir, 'ui', 'conversation.md');
      fs.appendFileSync(conv, fs.readFileSync(pending, 'utf8'));
      fs.rmSync(pending);
    }
  }
  return workDir;
}

// 途中の作業の一覧: output/*/ui/state.json がある作業
function listWorks() {
  const works = [];
  for (const name of fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : []) {
    const file = path.join(outputDir, name, 'ui', 'state.json');
    if (!fs.existsSync(file)) continue;
    let state;
    try { state = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { continue; }
    const artifacts = Array.isArray(state.artifacts) ? state.artifacts : [];
    const started = artifacts.filter(a => a.status !== '未着手');
    const lastArtifact = started.length ? started[started.length - 1] : null;
    works.push({
      dir: path.relative(factoryDir, path.join(outputDir, name)),
      workName: state.workName || name,
      stage: state.stage,
      artifact: lastArtifact ? {name: lastArtifact.name, status: lastArtifact.status} : null,
      savedAt: fs.statSync(file).mtime.toISOString(),
      done: artifacts.length === 8 && artifacts.every(a => a.status === '済み'),
    });
  }
  return works;
}

// 途中の作業を続ける: そのフォルダを作業のフォルダにし、ui/session.json の会話の ID があれば、次の送信から --resume する
function resume(rel) {
  const dir = path.resolve(factoryDir, rel);
  if (!dir.startsWith(outputDir + path.sep) || !fs.existsSync(path.join(dir, 'ui', 'state.json'))) return null;
  workDir = dir;
  let saved = null;
  try { saved = JSON.parse(fs.readFileSync(path.join(dir, 'ui', 'session.json'), 'utf8')).sessionId; } catch {}
  if (saved) { sessionId = saved; sessionStarted = true; }
  else { sessionId = randomUUID(); sessionStarted = false; }
  pending = path.join(uiDir, '.pending', `${sessionId}.md`);
  saveSession(dir);
  return path.relative(factoryDir, dir);
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

// 画面からの文を conversation.md に追記し、Claude Code に渡し、途中の返事も 1 つずつ追記する。
// Claude Code に渡す文の 1 行目は「画面: <作業のフォルダ>」(未決定なら「画面: 新規」)とし、conversation.md には元の文だけを書く
function prompt(text) {
  append('ユーザー', text);
  busy = true;
  const dir = findWorkDir();
  const full = `画面: ${dir ? path.relative(factoryDir, dir) : '新規'}\n${text}`;
  const args = ['-p', sessionStarted ? '--resume' : '--session-id', sessionId,
    '--output-format', 'stream-json', '--verbose',
    // --resume の 2 回目からも毎回付ける
    '--model', model,
    // claude -p は許可の確認に答えられないので、ファイルの書き込みを許す
    '--permission-mode', 'acceptEdits'];
  child = spawn('claude', args, {cwd: factoryDir, stdio: ['pipe', 'pipe', 'pipe']});
  child.stdin.on('error', () => {});
  child.stdin.end(full);
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
      // ツールの結果が返ったら、そのサブエージェントを、結果が返っていない一覧から外す
      if (msg.type === 'user') for (const c of (msg.message && msg.message.content) || []) if (c.type === 'tool_result') openAgents.delete(c.tool_use_id);
      if (msg.type !== 'assistant') continue;
      for (const c of msg.message.content || []) {
        if (c.type === 'text' && c.text.trim()) { append('Claude Code', c.text); replied = true; }
        // Claude Code が Skill のツールを呼んだら、そのスキルの名前を、呼んだ順の一覧に足す
        if (c.type === 'tool_use' && c.name === 'Skill' && c.input && c.input.skill) skillCalls.push(c.input.skill);
        if (c.type === 'tool_use' && (c.name === 'Agent' || c.name === 'Task')) openAgents.add(c.id);
      }
    }
  });
  child.stderr.on('data', d => { err += d; });
  child.on('error', e => { err += e.message; });
  child.on('close', code => {
    busy = false;
    child = null;
    openAgents.clear();
    if (code !== 0 || !replied) append('Claude Code', `(終了コード ${code}) ${err.trim()}`);
  });
}

// 中継サーバーを止めるときは、動いている claude も止める
function killChild() { if (child) child.kill(); }
process.on('SIGINT', () => { killChild(); process.exit(0); });
process.on('exit', killChild);

// claude のコマンドがあるかは、起動のときに 1 回だけ確かめ、画面のヘッダーの状態に出す
const hasClaude = spawnSync('claude', ['--version']).status === 0;

// 作業のフォルダが決まる前に画面の文書の欄に出す md
function startPage() {
  return fs.readFileSync(path.join(uiDir, 'はじめに.md'), 'utf8');
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

// POST の本文を JSON として読む。本文が壊れていたら 400 を返して null
function readJson(req, res, fn) {
  let body = '';
  req.on('data', d => { body += d; });
  req.on('end', () => {
    let json;
    try { json = JSON.parse(body || '{}'); } catch { return send(res, 400, '本文が JSON ではありません'); }
    fn(json);
  });
}

// ほかのサイトの画面からの POST は受けない(Origin のホストが Host と違うとき)
function crossOrigin(req) {
  const origin = req.headers.origin;
  if (!origin) return false;
  try { return new URL(origin).host !== req.headers.host; } catch { return true; }
}

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/') {
    return send(res, 200, fs.readFileSync(path.join(uiDir, 'index.html')), {'Content-Type': 'text/html; charset=utf-8'});
  }
  if (req.method === 'GET' && url.pathname === '/api/status') {
    return send(res, 200, JSON.stringify({busy, hasClaude, skillCalls, subagents: openAgents.size, workDir: findWorkDir() ? path.relative(factoryDir, findWorkDir()) : null}), {'Content-Type': 'application/json'});
  }
  // 途中の作業の一覧(開いた直後の画面に出す)
  if (req.method === 'GET' && url.pathname === '/api/works') {
    return send(res, 200, JSON.stringify(listWorks()), {'Content-Type': 'application/json'});
  }
  // 段階ごとに使うスキルと規約の表。画面は、この 1 つのファイルから一覧を出す
  if (req.method === 'GET' && url.pathname === '/api/stages') {
    return sendFile(res, path.join(uiDir, '段階ごとのスキルと規約.json'), false);
  }
  if (req.method === 'GET' && url.pathname === '/api/start') {
    return send(res, 200, startPage(), {'Content-Type': 'text/markdown; charset=utf-8', 'Cache-Control': 'no-store'});
  }
  if (req.method === 'GET' && url.pathname.startsWith('/files/')) {
    const rel = decodeURIComponent(url.pathname.slice('/files/'.length));
    if (rel === 'ui/conversation.md') return sendFile(res, conversationPath(), false);
    const dir = findWorkDir();
    if (!dir) return send(res, 404, '作業のフォルダがまだありません');
    // output/ の下のファイルだけを返す(作業のフォルダからの相対パス。`../` でほかの作業のファイルも指せる)
    const file = path.resolve(dir, rel);
    if (!file.startsWith(outputDir + path.sep)) return send(res, 403, 'output/ の外のファイルです');
    return sendFile(res, file, url.searchParams.has('download'));
  }
  if (req.method === 'POST' && crossOrigin(req)) return send(res, 403, 'ほかのサイトからの送信です');
  if (req.method === 'POST' && url.pathname === '/api/resume') {
    return readJson(req, res, json => {
      if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに続けてください。');
      const dir = resume(String(json.dir || ''));
      if (!dir) return send(res, 404, 'その作業のフォルダに ui/state.json がありません');
      send(res, 200, JSON.stringify({workDir: dir, sessionId}), {'Content-Type': 'application/json'});
    });
  }
  if (req.method === 'POST' && url.pathname === '/api/prompt') {
    return readJson(req, res, json => {
      const text = String(json.text || '').trim();
      if (!text) return send(res, 400, '文が空です');
      if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに送ってください。');
      prompt(text);
      send(res, 202, '送りました');
    });
  }
  send(res, 404, 'ありません');
}).on('error', e => {
  if (e.code === 'EADDRINUSE') { console.error(`ポート ${port} は使用中です`); process.exit(1); }
  throw e;
}).listen(port, '127.0.0.1', () => {
  console.log('作業のフォルダ: AI が state.json を書いたとき、または画面の「続きから」で決まる');
  console.log(`画面: http://127.0.0.1:${port}/`);
});
