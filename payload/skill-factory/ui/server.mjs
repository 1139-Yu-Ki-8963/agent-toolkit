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
// 画面から動かす claude にだけ渡す指示。端末だけで使う claude には渡らない。--resume の 2 回目からも毎回渡す
const screenPrompt = [
  'この会話は、確認と承認の画面の中継サーバーから動いている。ユーザーは、画面のボタンと入力欄で答える。規約 skill-making-flow の規則「確認と承認の画面を使うときに AI が足す動作」に、次の 7 つを足す。',
  '1. AI は、state.json を、規約 skill-making-flow の規則「確認と承認の画面を使うときに AI が足す動作」のとおりに書く。AI は、updating-skill-factory-ui-state を会話の中で 1 回だけ呼び、2 回目からは、そのスキルのリファレンス「画面の状態のファイルの形」と「段階のスキルの表示と state.json の値の対応表」のとおりに Write で直接書く。2 つのリファレンスは、.claude/skills/updating-skill-factory-ui-state/references/ の「画面の状態のファイルの形.md」と「段階のスキルの表示と state.json の値の対応表.md」である。AI は、会話の要約のあとは、もう一度 updating-skill-factory-ui-state を呼ぶ。',
  '2. AI は、段階 1 の最初の state.json を、screen を「AI が読む」にして書く。',
  '3. AI は、step 5-1 で調べ始める前の state.json を、「段階のスキルの表示と state.json の値の対応表.md」の「step 5-1 で調べ始める前に state.json を書く時点」の行のとおりに書く。',
  '4. AI は、画面で項目 7-1、7-10 の問いを 1 問で出す。必ず入れる部分の欄と要るファイルの欄の答えは、問いの答えの文の後ろの括弧で届く。',
  '5. AI は、聞き取りの記録の章「答え」に、画面が送った答えの選択肢の文と補足の文を、言い換えずに写す。',
  '6. AI は、段階 1 のユーザーへの完了の報告のあとの動作と、hook が頼む照合を行う時点を、規約 skill-making-flow の規則「確認と承認の画面を使うときに AI が足す動作」を全文読み、そのとおりに行う。AI は、段階 1 の完了の報告のあとの state.json の downloads を、要件定義書と聞き取りの記録のパスにし、質問を足さずに返事を終える。AI は、段階 2 を、ユーザーが「次の作業へ進む」で始まる文を送ったときに始める。AI は、段階 2 から 7 のユーザーへの完了の報告のあとは、規約 skill-making-flow の規則「ユーザーへの完了の報告のあとに次の段階を始める」のとおりに、同じ返事の中で次の段階のスキルを始め、そのスキルがユーザーに質問か承認を出す所まで進める。AI は、段階 5 の照合と修正の組を、修正のスキルの完了の報告のあとも、規約 skill-making-flow の段階 5 の進め方のとおりに、同じ返事の中で続け、ユーザーに質問か承認を出す所まで進める。AI は、段階 5 の 1 回目の照合と同時に、規約 skill-making-flow の規則 4 のとおりに段階 6 を承認の手前まで進め、step の番号が変わったときはテスト計画書を書き直す。AI は、hook が差し込む Markdown の照合の依頼について、照合を流すかをユーザーに聞かない。AI は、hook が頼む Markdown の照合と直しを、分割設計書の章 3 のすべてのスキルの段階 8 が合格したあとに、まとめて 1 回だけ行う。',
  '7. AI は、1 回の返事の中で、聞き取りの記録.md を 1 回の Write で書く。',
].join(' ');

// 会話の ID は、起動ごとに 1 つ。1 回目の送信は --session-id、2 回目からは --resume で同じ会話を続ける。
// 作業のフォルダの ui/session.json から再開したときは、その ID で --resume する
let sessionId = randomUUID();
let sessionStarted = false;
const startTime = Date.now();
// 起動の前から state.json があった作業。送信のあとに書かれたときだけ、作業のフォルダの候補にする(別の会話の session.json を上書きしないため)
const worksAtStart = new Set((fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : []).filter(name => fs.existsSync(path.join(outputDir, name, 'ui', 'state.json'))));
let promptSent = false;
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
// Agent か Task のツールの呼び出しの説明と、結果が返ったか(直近の送信の分。画面 8-1 の進み具合が読む)
let agentCalls = [];
// 前の会話を続けられないと分かったときの state.json の更新日時。state.json が書き直されるまで、画面は前の会話の問いを出さない
let lostStateTime = null;
const lostText = '前の会話を続けられないので、新しい会話で始めます。成果物のパスを送ってください';
// 「あとで続ける」か「やめる」で離れた作業。作業のフォルダの候補にしない(「続きから」で開くと外す)
const leftWorks = new Set();

function markSessionLost() {
  // state.json がないときは、書かれた時点で続けられない状態を終える
  try { lostStateTime = fs.statSync(path.join(workDir, 'ui', 'state.json')).mtimeMs; } catch { lostStateTime = null; }
  append('Claude Code', lostText);
}

function sessionLost() {
  if (!workDir || lostStateTime === null) return false;
  try { return fs.statSync(path.join(workDir, 'ui', 'state.json')).mtimeMs === lostStateTime; } catch { return false; }
}

// 作業のフォルダが決まったら、その ui/session.json に会話の ID を書く(再開のときに読む)
function saveSession(dir) {
  fs.mkdirSync(path.join(dir, 'ui'), {recursive: true});
  fs.writeFileSync(path.join(dir, 'ui', 'session.json'), JSON.stringify({sessionId, workDir: path.relative(factoryDir, dir), writtenAt: new Date().toISOString()}) + '\n');
}

// 作業のフォルダは、起動したあとに output/*/ui/state.json が書かれた最初のフォルダとし、決まったら止めるまで同じフォルダとする
function findWorkDir() {
  // 作業のフォルダそのものが消えたときだけ探し直す。state.json が書き直しの途中でないときに、作業のフォルダを忘れないため
  if (workDir && !fs.existsSync(workDir)) workDir = null;
  if (workDir) return workDir;
  let first = null;
  let firstTime = Infinity;
  for (const name of fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : []) {
    const state = path.join(outputDir, name, 'ui', 'state.json');
    if (!fs.existsSync(state)) continue;
    if (worksAtStart.has(name) && !promptSent) continue;
    if (leftWorks.has(name)) continue;
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

// 途中の作業の状態(要件定義書の章 6)
// 聞き取りの画面の「あとで続ける」「やめる」: AI の返事が終わったら作業を離れ、画面 1 へ戻す。「やめる」の作業は ui/stopped.json を置いて、途中の作業の一覧から外す
function leaveWork(kind) {
  if (!workDir) return;
  if (kind === 'やめる') fs.writeFileSync(path.join(workDir, 'ui', 'stopped.json'), JSON.stringify({stoppedAt: new Date().toISOString()}) + '\n');
  leftWorks.add(path.basename(workDir));
  workDir = null;
  sessionId = randomUUID();
  sessionStarted = false;
  promptSent = false;
  skillCalls.length = 0;
  pending = path.join(uiDir, '.pending', `${sessionId}.md`);
}

// 「完了」は、currentSkill の終えたスキルの数(done)が全本数(total)と同じとき。done がないときは、artifacts の 8 件目が「済み」のとき。
// 「中止」は、キー abort があるとき(画面 K6)
function workState(state, artifacts) {
  const cs = state.currentSkill && typeof state.currentSkill === 'object' ? state.currentSkill : null;
  if (cs && typeof cs.done === 'number' && typeof cs.total === 'number') { if (cs.done >= cs.total) return '完了'; }
  else if (artifacts[7] && artifacts[7].status === '済み') return '完了';
  if (state.abort) return '中止';
  if (state.decision) return '承認待ち';
  const items = state.questions && Array.isArray(state.questions.items) ? state.questions.items : [];
  if (items.some(i => i && i.answer == null)) return `質問中(${items.length} 問のうち ${items.filter(i => i && i.answer != null).length} 問に回答)`;
  return '作業中';
}

// 途中の作業の一覧: output/*/ui/state.json がある作業
function listWorks() {
  const works = [];
  for (const name of fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : []) {
    const file = path.join(outputDir, name, 'ui', 'state.json');
    if (!fs.existsSync(file)) continue;
    if (fs.existsSync(path.join(outputDir, name, 'ui', 'stopped.json'))) continue;
    let state;
    try { state = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { continue; }
    if (!state || typeof state !== 'object' || Array.isArray(state)) continue;
    const artifacts = (Array.isArray(state.artifacts) ? state.artifacts : []).filter(a => a && typeof a === 'object');
    const started = artifacts.filter(a => a.status !== '未着手');
    const lastArtifact = started.length ? started[started.length - 1] : null;
    works.push({
      dir: path.relative(factoryDir, path.join(outputDir, name)),
      workName: state.workName || name,
      stage: state.stage,
      artifact: lastArtifact ? {name: lastArtifact.name, status: lastArtifact.status} : null,
      savedAt: fs.statSync(file).mtime.toISOString(),
      done: workState(state, artifacts) === '完了',
      state: workState(state, artifacts),
    });
  }
  return works;
}

// 途中の作業を続ける: そのフォルダを作業のフォルダにし、ui/session.json の会話の ID があれば、次の送信から --resume する
function resume(rel) {
  const dir = path.resolve(factoryDir, rel);
  if (!dir.startsWith(outputDir + path.sep) || !fs.existsSync(path.join(dir, 'ui', 'state.json'))) return null;
  leftWorks.delete(path.basename(dir));
  // 別の作業に移るときは、前の作業のスキルの呼び出しを持ち越さない
  if (workDir !== dir) skillCalls.length = 0;
  // 仮の会話は、この作業の conversation.md の後ろに移す
  if (fs.existsSync(pending)) {
    fs.appendFileSync(path.join(dir, 'ui', 'conversation.md'), fs.readFileSync(pending, 'utf8'));
    fs.rmSync(pending);
  }
  workDir = dir;
  let saved = null;
  try { saved = JSON.parse(fs.readFileSync(path.join(dir, 'ui', 'session.json'), 'utf8')).sessionId; } catch {}
  if (saved) { sessionId = saved; sessionStarted = true; lostStateTime = null; }
  else {
    sessionId = randomUUID();
    sessionStarted = false;
    markSessionLost();
    // session.json は、会話の ID が変わったときだけ書く
    saveSession(dir);
  }
  pending = path.join(uiDir, '.pending', `${sessionId}.md`);
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
  // 本文の行頭が区切りと同じ形の行は、先頭に \ を付けて区切りと分ける。画面は、この \ を外して出す
  const body = text.trim().replace(/^(ユーザー|Claude Code):/gm, '\\$1:');
  fs.appendFileSync(conv, `${who}: ${body}\n\n`);
}

// 画面からの文を conversation.md に追記し、Claude Code に渡し、途中の返事も 1 つずつ追記する。
// Claude Code に渡す文の 1 行目は「画面: <作業のフォルダ>」(未決定なら「画面: 新規」)とし、conversation.md には元の文だけを書く
// 返事の時間の記録(要件定義書の章 3.2 と章 7): 返事が終わるごとに、<作業のフォルダ>/ui/返事の時間.jsonl に 1 行足す。
// 作業のフォルダが決まっていないときと、作業のフォルダの ui/ がないときは書かない(消えた作業のフォルダを作り直さないため)
function recordTime(sentAt, result, text) {
  const dir = findWorkDir();
  if (!dir || !fs.existsSync(path.join(dir, 'ui'))) return;
  const num = k => (result && typeof result[k] === 'number' ? result[k] : null);
  const row = {sentAt, endedAt: new Date().toISOString(), duration_ms: num('duration_ms'), duration_api_ms: num('duration_api_ms'), num_turns: num('num_turns'), promptHead: Array.from(text).slice(0, 40).join('')};
  try { fs.appendFileSync(path.join(dir, 'ui', '返事の時間.jsonl'), JSON.stringify(row) + '\n'); } catch {}
}

function prompt(text, leave) {
  const sentAt = new Date().toISOString();
  append('ユーザー', text);
  busy = true;
  promptSent = true;
  agentCalls = [];
  const dir = findWorkDir();
  const full = `画面: ${dir ? path.relative(factoryDir, dir) : '新規'}\n${text}`;
  const args = ['-p', sessionStarted ? '--resume' : '--session-id', sessionId,
    '--output-format', 'stream-json', '--verbose',
    // --resume の 2 回目からも毎回付ける
    '--model', model,
    // claude -p は許可の確認に答えられないので、ファイルの書き込みを許す
    '--permission-mode', 'acceptEdits',
    '--append-system-prompt', screenPrompt];
  child = spawn('claude', args, {cwd: factoryDir, stdio: ['pipe', 'pipe', 'pipe']});
  child.stdin.on('error', () => {});
  child.stdin.end(full);
  // 文字を塊の境目で壊さないように、文字列で受ける
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  let rest = '';
  let err = '';
  let noConversation = false;
  const resultErrors = [];
  // stream-json の type が result の行(duration_ms、duration_api_ms、num_turns を持つ)
  let result = null;
  const contentOf = msg => (msg.message && Array.isArray(msg.message.content) ? msg.message.content : []).filter(c => c && typeof c === 'object');
  const readLine = line => {
    let msg;
    try { msg = JSON.parse(line); } catch { return; }
    if (!msg || typeof msg !== 'object') return;
    if (msg.type === 'system' && msg.subtype === 'init') sessionStarted = true;
    if (msg.type === 'result') result = msg;
    if (msg.type === 'result' && Array.isArray(msg.errors)) {
      for (const e of msg.errors) {
        resultErrors.push(String(e));
        if (String(e).startsWith('No conversation found')) noConversation = true;
      }
    }
    // ツールの結果が返ったら、そのサブエージェントを、結果が返っていない一覧から外す
    if (msg.type === 'user') for (const c of contentOf(msg)) if (c.type === 'tool_result') { openAgents.delete(c.tool_use_id); for (const a of agentCalls) if (a.id === c.tool_use_id) a.done = true; }
    if (msg.type !== 'assistant') return;
    for (const c of contentOf(msg)) {
      if (c.type === 'text' && typeof c.text === 'string' && c.text.trim()) append('Claude Code', c.text);
      // Claude Code が Skill のツールを呼んだら、そのスキルの名前を、呼んだ順の一覧に足す
      if (c.type === 'tool_use' && c.name === 'Skill' && c.input && c.input.skill) skillCalls.push(c.input.skill);
      if (c.type === 'tool_use' && (c.name === 'Agent' || c.name === 'Task')) {
        openAgents.add(c.id);
        const input = c.input && typeof c.input === 'object' ? c.input : {};
        agentCalls.push({id: c.id, description: typeof input.description === 'string' ? input.description : '', done: false});
      }
    }
  };
  child.stdout.on('data', d => {
    rest += d;
    const lines = rest.split('\n');
    rest = lines.pop();
    lines.forEach(readLine);
  });
  child.stderr.on('data', d => { err += d; });
  child.on('error', e => { err += e.message; });
  child.on('close', (code, signal) => {
    // 改行で終わらない最後の行も読む
    if (rest) readLine(rest);
    busy = false;
    child = null;
    openAgents.clear();
    for (const a of agentCalls) a.done = true;
    // 送った文の 2 行目から(画面からの文)の先頭 40 文字を添える。作業を離れる前と、会話の ID を替える前に書く
    recordTime(sentAt, result, text);
    // --resume の会話の ID が使えないときは、新しい会話の ID に替える(要件定義書の章 6)
    if (noConversation) {
      sessionId = randomUUID();
      sessionStarted = false;
      if (workDir) { saveSession(workDir); markSessionLost(); }
      else append('Claude Code', lostText);
      return;
    }
    if (code !== 0) append('Claude Code', `(終了コード ${code ?? signal}) ${[err.trim(), ...resultErrors].filter(Boolean).join(' ')}`);
    if (leave) leaveWork(leave);
  });
}

// 中継サーバーを止めるときは、動いている claude に SIGTERM を送り、5 秒以内に終わらなければ SIGKILL を送ってから終わる
function killChild() { if (child) child.kill(); }
function shutdown() {
  if (!child) process.exit(0);
  const c = child;
  c.on('close', () => process.exit(0));
  c.kill('SIGTERM');
  setTimeout(() => c.kill('SIGKILL'), 5000);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGHUP', shutdown);
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

const types = {'.html': 'text/html', '.json': 'application/json', '.css': 'text/css', '.md': 'text/markdown', '.svg': 'image/svg+xml', '.txt': 'text/plain'};

function sendFile(res, file, download) {
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return send(res, 404, 'ファイルがありません');
  const headers = {'Content-Type': (types[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8', 'Cache-Control': 'no-store'};
  if (download) headers['Content-Disposition'] = `attachment; filename*=UTF-8''${encodeURIComponent(path.basename(file))}`;
  send(res, 200, fs.readFileSync(file), headers);
}

// POST の本文を JSON として読む。本文が壊れていたら 400 を返して null
function readJson(req, res, fn) {
  // 文字を塊の境目で壊さないように、全部を受けてから文字列にする
  const chunks = [];
  req.on('data', d => { chunks.push(d); });
  req.on('end', () => {
    let json;
    try { json = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { return send(res, 400, '本文が JSON ではありません'); }
    if (!json || typeof json !== 'object' || Array.isArray(json)) return send(res, 400, '本文が JSON のオブジェクトではありません');
    try { fn(json); } catch (e) { send(res, 500, e.message); }
  });
}

// POST は、Origin が http://localhost:<ポート> か http://127.0.0.1:<ポート> のときだけ受ける(要件定義書の章 7)
function crossOrigin(req) {
  return req.headers.origin !== `http://localhost:${port}` && req.headers.origin !== `http://127.0.0.1:${port}`;
}

function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/') {
    return send(res, 200, fs.readFileSync(path.join(uiDir, 'index.html')), {'Content-Type': 'text/html; charset=utf-8'});
  }
  // 画面が読む値の資料。index.html の link が相対パスで指す
  if (req.method === 'GET' && decodeURIComponent(url.pathname) === '/デザイントークン.css') {
    return sendFile(res, path.join(uiDir, 'デザイントークン.css'), false);
  }
  if (req.method === 'GET' && url.pathname === '/api/status') {
    return send(res, 200, JSON.stringify({busy, hasClaude, skillCalls, subagents: openAgents.size, agentCalls: agentCalls.map(a => ({description: a.description, done: a.done})), workDir: findWorkDir() ? path.relative(factoryDir, findWorkDir()) : null, sessionLost: sessionLost()}), {'Content-Type': 'application/json'});
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
    // 作業のフォルダの下のファイルだけを返す。リンクは、たどった先で確かめる
    const file = path.resolve(dir, rel);
    if (!file.startsWith(dir + path.sep)) return send(res, 403, '作業のフォルダの外のファイルです');
    if (fs.existsSync(file) && !fs.realpathSync(file).startsWith(fs.realpathSync(dir) + path.sep)) return send(res, 403, '作業のフォルダの外のファイルです');
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
  // 段階 2 から 8 の「あとで続ける」: AI に送らずに作業を離れ、画面 1 へ戻す。作業は state.json に残り、「続きから」で戻る
  if (req.method === 'POST' && url.pathname === '/api/leave') {
    return readJson(req, res, () => {
      if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに離れてください。');
      leaveWork('あとで続ける');
      send(res, 200, JSON.stringify({left: true}), {'Content-Type': 'application/json'});
    });
  }
  if (req.method === 'POST' && url.pathname === '/api/prompt') {
    return readJson(req, res, json => {
      const text = String(json.text || '').trim();
      if (!text) return send(res, 400, '文が空です');
      if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに送ってください。');
      // 画面が見ている作業と中継サーバーの作業が違うとき(中継サーバーを起動し直して画面を読み直していないとき)は、画面が見ている作業の会話に渡す
      const seen = json.workDir ? String(json.workDir) : null;
      const current = findWorkDir();
      if (seen && (!current || path.relative(factoryDir, current) !== seen)) {
        if (!resume(seen)) return send(res, 404, 'その作業のフォルダに ui/state.json がありません');
        if (sessionLost()) return send(res, 409, lostText);
      }
      prompt(text, json.leave === 'あとで続ける' || json.leave === 'やめる' ? json.leave : null);
      send(res, 202, '送りました');
    });
  }
  send(res, 404, 'ありません');
}

http.createServer((req, res) => {
  // 1 つの要求の例外で、中継サーバーを落とさない
  try { handle(req, res); }
  catch (e) { send(res, e instanceof URIError || e.code === 'ERR_INVALID_URL' ? 400 : 500, e.message); }
}).on('error', e => {
  if (e.code === 'EADDRINUSE') { console.error(`ポート ${port} は使用中です。PORT=<別の番号> node ui/server.mjs で起動してください`); process.exit(1); }
  throw e;
}).listen(port, '127.0.0.1', () => {
  console.log('中継サーバーを起動しました。');
  console.log(`ブラウザで http://127.0.0.1:${port}/ を開いてください。`);
  console.log('止めるときは Ctrl+C を押してください。');
});
