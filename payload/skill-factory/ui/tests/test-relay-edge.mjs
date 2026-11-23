#!/usr/bin/env node
// 中継サーバー(ui/server.mjs)の境界の値と異常の入力のテスト。AI はモック(fake-claude.mjs)を使う。
// 使い方: skill-factory/ で `node ui/tests/test-relay-edge.mjs`。`--case "GET /files/"` のようにケースの名前で 1 件だけ流す。`--list` でケースの名前を出す。終了コード 0 が全件合格。
// 一時フォルダの skill-factory の写しで動き、本物の ui/ と output/ を変えない。
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {check, finish, freePort, makeState, setCase, sleep, until} from './lib/report.mjs';

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const uiDir = path.dirname(testsDir);
const only = process.argv.includes('--case') ? process.argv[process.argv.indexOf('--case') + 1] : null;
const root = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'sf-edge.'));
const uiFiles = ['server.mjs', 'index.html', 'デザイントークン.css', 'はじめに.md', '段階ごとのスキルと規約.json'];

let sf, fake, port, server, serverErr, serverOut;

function makeCopy() {
  const base = fs.mkdtempSync(path.join(root, 'c.'));
  sf = path.join(base, 'sf');
  fake = path.join(base, 'fake');
  fs.mkdirSync(path.join(sf, 'ui'), {recursive: true});
  fs.mkdirSync(path.join(sf, 'output'), {recursive: true});
  fs.mkdirSync(path.join(fake, 'bin'), {recursive: true});
  for (const f of uiFiles) fs.copyFileSync(path.join(uiDir, f), path.join(sf, 'ui', f));
  fs.symlinkSync(process.execPath, path.join(fake, 'bin', 'node'));
  fs.writeFileSync(path.join(fake, 'bin', 'claude'), `#!/bin/sh\nexec node ${JSON.stringify(path.join(testsDir, 'fake-claude.mjs'))} "$@"\n`, {mode: 0o755});
}

function launch(env = {}) {
  const child = spawn('node', ['ui/server.mjs'], {cwd: sf, env: {...process.env, PATH: `${path.join(fake, 'bin')}:/usr/bin:/bin`, FAKE_DIR: fake, PORT: String(port), ...env}, stdio: ['ignore', 'pipe', 'pipe']});
  child.err = '';
  child.out = '';
  child.stderr.on('data', d => { child.err += d; });
  child.stdout.on('data', d => { child.out += d; });
  child.closed = new Promise(r => child.on('close', (code, signal) => r({code, signal})));
  return child;
}

async function start(env) {
  port = port || await freePort();
  server = launch(env);
  const up = await until(() => req('GET', '/api/status').then(r => r.status === 200).catch(() => false), 10000);
  if (!up) throw new Error(`中継サーバーが起動しません: ${server.err}`);
}

async function stop(signal = 'SIGINT') {
  if (!server) return;
  const s = server;
  server = null;
  if (s.exitCode === null && s.signalCode === null) s.kill(signal);
  await s.closed;
  serverErr = s.err;
  serverOut = s.out;
}

// fetch は Host と一部のパスを変えるので、http.request で送る
function req(method, p, {headers = {}, body} = {}) {
  return new Promise((resolve, reject) => {
    const r = http.request({host: '127.0.0.1', port, method, path: p, headers}, res => {
      const chunks = [];
      res.on('data', d => chunks.push(d));
      res.on('end', () => resolve({status: res.statusCode, headers: res.headers, text: Buffer.concat(chunks).toString('utf8')}));
    });
    r.on('error', reject);
    r.setTimeout(5000, () => r.destroy(new Error('時間切れ')));
    if (body !== undefined) r.write(typeof body === 'string' ? body : JSON.stringify(body));
    r.end();
  });
}

const post = (p, body, headers = {}) => req('POST', p, {body, headers: {'Content-Type': 'application/json', Origin: `http://127.0.0.1:${port}`, ...headers}});
const status = async () => JSON.parse((await req('GET', '/api/status')).text);
const works = async () => JSON.parse((await req('GET', '/api/works')).text);
const alive = async () => server && server.exitCode === null && server.signalCode === null && await req('GET', '/api/status').then(r => r.status === 200).catch(() => false);
const idle = () => until(async () => (await status().catch(() => ({busy: false}))).busy === false, 8000);
const plan = p => fs.writeFileSync(path.join(fake, 'next.json'), JSON.stringify(p));
const calls = () => { const f = path.join(fake, 'log.jsonl'); return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l)) : []; };
const argAfter = (c, n) => { const i = c.args.indexOf(n); return i < 0 ? null : c.args[i + 1]; };
const processGone = pid => { try { process.kill(pid, 0); return false; } catch { return true; } };

const out = (...p) => path.join(sf, 'output', ...p);
function putWork(name, state, session) {
  fs.mkdirSync(out(name, 'ui'), {recursive: true});
  fs.writeFileSync(out(name, 'ui', 'state.json'), typeof state === 'string' ? state : JSON.stringify(state));
  if (session !== undefined) fs.writeFileSync(out(name, 'ui', 'session.json'), typeof session === 'string' ? session : JSON.stringify(session));
}
const conv = name => { const f = out(name, 'ui', 'conversation.md'); return fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : ''; };
const writesWork = (name = 'work-1', state = makeState()) => ({[out(name, 'ui', 'state.json')]: JSON.stringify(state)});
const init = {type: 'system', subtype: 'init', session_id: 'x'};
const say = text => ({type: 'assistant', message: {content: [{type: 'text', text}]}});

// 作業のフォルダが決まるところまで進める
async function startWork(name = 'work-1', state) {
  plan({files: writesWork(name, state)});
  await post('/api/prompt', {text: '依頼'});
  await idle();
  await until(async () => (await status()).workDir === `output/${name}`);
}

const cases = [];
const testCase = (name, fn, env) => cases.push({name, fn, env});

testCase('ポートが使用中のとき', async () => {
  const second = launch();
  const {code} = await second.closed;
  check('2 つ目の中継サーバーは終了コード 1 で終わる', code === 1, code);
  check('要件定義書の章 7 の文を標準エラーに出す', second.err.trim() === `ポート ${port} は使用中です。PORT=<別の番号> node ui/server.mjs で起動してください`, second.err);
  check('1 つ目の中継サーバーは動き続ける', await alive());
});

testCase('起動したときの表示', async () => {
  await until(() => server.out.split('\n').length >= 4, 3000);
  const lines = server.out.split('\n');
  check('1 行目は「中継サーバーを起動しました。」', lines[0] === '中継サーバーを起動しました。', lines[0]);
  check('2 行目は、開くアドレスを案内する文', lines[1] === `ブラウザで http://127.0.0.1:${port}/ を開いてください。`, lines[1]);
  check('3 行目は、止め方を案内する文', lines[2] === '止めるときは Ctrl+C を押してください。', lines[2]);
  check('標準出力は 3 行ちょうどで、標準エラーは空', lines.length === 4 && lines[3] === '' && server.err === '', `${lines.length} 行、標準エラー: ${server.err}`);
  const page = await req('GET', '/');
  check('表示されたアドレスは、ステータス 200 で画面の HTML を返す', page.status === 200 && /^text\/html/.test(page.headers['content-type'] || '') && page.text.includes('<html'), `${page.status} ${page.headers['content-type']}`);
});

testCase('中継サーバーを止めるときの子プロセス', async () => {
  await startWork();
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  plan({hold, lines: [init, say('途中まで書いた返事です。')]});
  await post('/api/prompt', {text: '止める前の文'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  const pid = calls().at(-1).pid;
  const s = server;
  await stop('SIGINT');
  check('SIGINT で SIGTERM に従う子プロセスが止まる', await until(() => processGone(pid), 3000));
  check('ユーザーの行と書き終えた返事が残る', conv('work-1').includes('ユーザー: 止める前の文') && conv('work-1').includes('途中まで書いた返事です。'));
  check('待っている間の返事は残らない', !conv('work-1').includes('待ったあとの返事です。'));
  check('終了コードは 0', s.exitCode === 0, s.exitCode);
  fs.rmSync(hold, {force: true});
  await start();
  plan({});
  await post('/api/prompt', {text: '続き', workDir: 'output/work-1'});
  await idle();
  check('起動し直すと同じ会話を --resume で続ける', !!argAfter(calls().at(-1), '--resume'));
});

testCase('SIGTERM を無視する子プロセス', async () => {
  await startWork();
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  plan({hold, ignoreTerm: true, lines: [init]});
  await post('/api/prompt', {text: '文'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  const pid = calls().at(-1).pid;
  const s = server;
  server = null;
  const begun = Date.now();
  s.kill('SIGINT');
  await s.closed;
  const waited = Date.now() - begun;
  check('中継サーバーは子プロセスが終わるまで待つ', waited >= 4000 || processGone(pid), `${waited} ms`);
  check('5 秒で終わらなければ SIGKILL で止める', await until(() => processGone(pid), 7000));
  if (!processGone(pid)) process.kill(pid, 'SIGKILL');
  fs.rmSync(hold, {force: true});
});

testCase('SIGTERM で中継サーバーを止めたときの子プロセス', async () => {
  await startWork();
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  plan({hold, lines: [init]});
  await post('/api/prompt', {text: '文'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  const pid = calls().at(-1).pid;
  await stop('SIGTERM');
  check('子プロセスが残らない', await until(() => processGone(pid), 3000));
  if (!processGone(pid)) process.kill(pid, 'SIGKILL');
  fs.rmSync(hold, {force: true});
});

testCase('claude の終わり方', async () => {
  await startWork();
  plan({lines: [init], stderr: 'エラーの文', exit: 3});
  await post('/api/prompt', {text: '失敗する文'});
  await idle();
  check('0 でない終了で「(終了コード N) 標準エラー」を書く', conv('work-1').includes('Claude Code: (終了コード 3) エラーの文'), conv('work-1'));
  check('失敗のあとに busy が false に戻る', (await status()).busy === false);
  const stateBefore = fs.statSync(out('work-1', 'ui', 'state.json')).mtimeMs;
  plan({lines: [init, say('次の返事')]});
  await post('/api/prompt', {text: '次の文'});
  await idle();
  check('失敗のあとの次の送信を受ける', conv('work-1').includes('次の返事'));
  check('中継サーバーは state.json を書かない', fs.statSync(out('work-1', 'ui', 'state.json')).mtimeMs === stateBefore);
  plan({lines: [init, {type: 'assistant', message: {content: [{type: 'tool_use', name: 'Bash', id: 't', input: {}}]}}]});
  await post('/api/prompt', {text: 'ツールだけの返事'});
  await idle();
  check('終了コード 0 でツールの呼び出しだけのときは、終了コードの行を書かない', !conv('work-1').includes('(終了コード 0)'), conv('work-1'));
  plan({lines: [init, {type: 'result', subtype: 'success', is_error: false, result: 'x'}, say('result のあとの返事')]});
  await post('/api/prompt', {text: 'result の形'});
  await idle();
  check('普通の result の行で落ちない', await alive() && conv('work-1').includes('result のあとの返事'));
  plan({lines: [init, {type: 'result', is_error: true, errors: ['理由の文']}], exit: 1});
  await post('/api/prompt', {text: 'errors だけの失敗'});
  await idle();
  check('errors だけの失敗は理由を行に書く', conv('work-1').includes('理由の文'), conv('work-1').slice(-200));
});

testCase('GET /files/', async () => {
  check('作業がないときは 404', (await req('GET', '/files/a.md')).status === 404);
  await startWork();
  fs.writeFileSync(out('work-1', 'a b.md'), '中身');
  fs.writeFileSync(out('work-1', 'x.zip'), 'z');
  fs.mkdirSync(out('work-2'), {recursive: true});
  fs.writeFileSync(out('work-2', 'b.md'), '別の作業');
  fs.writeFileSync(path.join(sf, 'secret.txt'), '秘密');
  const a = await req('GET', '/files/a%20b.md');
  check('作業のファイルを返す', a.status === 200 && a.text === '中身', a.status);
  check('ないファイルは 404', (await req('GET', '/files/none.md')).status === 404);
  check('フォルダは 404', (await req('GET', '/files/ui')).status === 404);
  check('外への指定は 403', (await req('GET', '/files/..%2F..%2F..%2Fsecret.txt')).status === 403);
  check('絶対パスは 403', (await req('GET', `/files/${encodeURIComponent(path.join(sf, 'secret.txt'))}`)).status === 403);
  check('別の作業のファイルは 403(要件定義書の章 7)', (await req('GET', '/files/..%2Fwork-2%2Fb.md')).status === 403);
  fs.symlinkSync(path.join(sf, 'secret.txt'), out('work-1', 'link.txt'));
  check('外を指すリンクは 403', (await req('GET', '/files/link.txt')).status === 403);
  const d = await req('GET', '/files/a%20b.md?download=1');
  check('ダウンロードは Content-Disposition を持つ', (d.headers['content-disposition'] || '').startsWith('attachment'));
  check('ダウンロードでない要求は Content-Disposition を持たない', !a.headers['content-disposition']);
  check('表にない拡張子も返す', (await req('GET', '/files/x.zip')).headers['content-type'].startsWith('application/octet-stream'));
  await req('GET', '/files/%ZZ').catch(() => {});
  check('壊れた % で中継サーバーが落ちない', await alive());
});

testCase('POST /api/resume', async () => {
  putWork('work-1', makeState(), {sessionId: 'id-1'});
  fs.writeFileSync(path.join(sf, 'ui', 'state.json'), '{}');
  check('ない作業は 404', (await post('/api/resume', {dir: 'output/none'})).status === 404);
  check('output/ の外は 404', (await post('/api/resume', {dir: '../..'})).status === 404);
  check('ui/ の下を指すパスは 404', (await post('/api/resume', {dir: '.'})).status === 404);
  check('空の dir は 404', (await post('/api/resume', {dir: ''})).status === 404);
  check('本文なしは 404', (await post('/api/resume', '')).status === 404);
  const before = fs.statSync(out('work-1', 'ui', 'session.json')).mtimeMs;
  await sleep(20);
  const r = await post('/api/resume', {dir: 'output/work-1'});
  const j = JSON.parse(r.text);
  check('答えは作業のフォルダと会話の ID を持つ', r.status === 200 && j.workDir === 'output/work-1' && j.sessionId === 'id-1', r.text);
  check('会話の ID が変わらないときは session.json を書かない(要件定義書の章 5)', fs.statSync(out('work-1', 'ui', 'session.json')).mtimeMs === before);
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  plan({hold, lines: [init]});
  await post('/api/prompt', {text: '文'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  check('AI が返事を書いている間は 409', (await post('/api/resume', {dir: 'output/work-1'})).status === 409);
  fs.rmSync(hold);
  await idle();
});

testCase('POST /api/prompt の入力', async () => {
  check('空の文は 400', (await post('/api/prompt', {text: ''})).status === 400);
  check('空白だけの文は 400', (await post('/api/prompt', {text: ' \n '})).status === 400);
  check('本文なしは 400', (await post('/api/prompt', '')).status === 400);
  check('ない作業を添えると 404', (await post('/api/prompt', {text: 'x', workDir: 'output/none'})).status === 404);
  check('どの入力でも claude を呼ばない', calls().length === 0);
  await post('/api/prompt', 'null').catch(() => {});
  check('本文が null でも中継サーバーが落ちない', await alive());
});

testCase('POST /api/resume の本文が null', async () => {
  await post('/api/resume', 'null').catch(() => {});
  check('中継サーバーが落ちない', await alive());
});

testCase('Origin の確認', async () => {
  const send = (origin, host) => post('/api/resume', {dir: 'output/none'}, {Origin: origin, ...(host ? {Host: host} : {})});
  check('http://127.0.0.1:<ポート> を受ける', (await send(`http://127.0.0.1:${port}`)).status === 404);
  check('http://localhost:<ポート> を受ける(Host が 127.0.0.1 のとき)', (await send(`http://localhost:${port}`)).status === 404);
  check('ほかのサイトは 403', (await send('http://evil.example')).status === 403);
  check('Origin が null は 403', (await send('null')).status === 403);
  check('Origin と Host がともに外の名前でも 403', (await send(`http://evil.example:${port}`, `evil.example:${port}`)).status === 403);
  check('https の Origin は 403', (await send(`https://127.0.0.1:${port}`)).status === 403);
  check('待ち受けは 127.0.0.1 だけ', serverListensOnlyOnLoopback());
  const noOrigin = await req('POST', '/api/resume', {body: {dir: 'output/none'}, headers: {'Content-Type': 'application/json'}});
  check('Origin のない POST は 403(要件定義書の章 7)', noOrigin.status === 403, noOrigin.status);
});
function serverListensOnlyOnLoopback() { return /listen\(port, '127\.0\.0\.1'/.test(fs.readFileSync(path.join(sf, 'ui', 'server.mjs'), 'utf8')); }

testCase('仮の会話', async () => {
  plan({lines: [init, say('どのスキルを作りますか')]});
  await post('/api/prompt', {text: '挨拶'});
  await idle();
  const pendingDir = path.join(sf, 'ui', '.pending');
  check('作業が決まる前は仮の会話に書く', fs.readdirSync(pendingDir).length === 1);
  plan({files: writesWork(), lines: [init, say('作業を始めます')]});
  await post('/api/prompt', {text: '依頼'});
  await idle();
  await until(async () => (await status()).workDir === 'output/work-1');
  const c = conv('work-1');
  check('仮の会話が作業の conversation.md に順に移る', c.indexOf('挨拶') >= 0 && c.indexOf('挨拶') < c.indexOf('作業を始めます'), c);
  check('移したあとに仮の会話のファイルが消える', fs.readdirSync(pendingDir).length === 0);
  const [first, second] = calls();
  check('2 回目は「画面: 新規」のまま --resume で続ける', second.stdin === '画面: 新規\n依頼' && argAfter(second, '--resume') === argAfter(first, '--session-id'), JSON.stringify(second));
});

testCase('仮の会話がある状態の「続きから」', async () => {
  putWork('old', makeState(), {sessionId: 'old-id'});
  plan({lines: [init, say('仮の返事')]});
  await post('/api/prompt', {text: '仮の文'});
  await idle();
  await post('/api/resume', {dir: 'output/old'});
  check('仮の会話が作業の conversation.md に移る', conv('old').includes('仮の文'));
});

testCase('claude の呼び方', async () => {
  const text = '1 行目\n2 行目 $(touch p) --resume x';
  plan({lines: [init, say('返事')]});
  await post('/api/prompt', {text});
  await idle();
  plan({lines: [init, say('返事')]});
  await post('/api/prompt', {text: '2 回目'});
  await idle();
  const [a, b] = calls();
  const common = ['--output-format', 'stream-json', '--verbose', '--model', 'test-model', '--permission-mode', 'acceptEdits', '--append-system-prompt', argAfter(a, '--append-system-prompt')];
  // 指示は、リファレンスと規約にある決まりを読ませる文を持つ。読ませる先に決まりがあることも、本物のファイルで確かめる
  const instruction = argAfter(a, '--append-system-prompt') || '';
  const factory = path.dirname(uiDir);
  const ruleText = fs.readFileSync(path.join(factory, '.claude', 'rules', 'skill-making-flow', 'skill-making-flow-rule.md'), 'utf8');
  const ruleName = '確認と承認の画面を使うときに AI が足す動作';
  const ruleBody = (ruleText.match(new RegExp(`^規則 \\d+: ${ruleName}$[\\s\\S]*?(?=^規則 \\d+: |^#|(?![\\s\\S]))`, 'm')) || [''])[0];
  const mapText = fs.readFileSync(path.join(factory, 'output', 'updating-skill-factory-ui-state', 'references', '段階のスキルの表示と state.json の値の対応表.md'), 'utf8');
  const researchMark = 'step 5-1 で調べ始める前に state.json を書く時点';
  const researchRow = mapText.split('\n').find(l => l.startsWith('|') && l.includes(researchMark)) || '';
  check('指示は、段階 1 のあとの動作と照合の時点を、規約の規則を全文読ませて決める', instruction.includes(`規約 skill-making-flow の規則「${ruleName}」を全文読み`), instruction);
  check('読ませる規約の規則は、画面 6 で止まる決まりを持つ', ['キー `screen` を「画面 6」、キー `decision` を `null` にして止まる'].every(k => ruleBody.includes(k)), ruleBody);
  check('指示は、調べ始める前の state.json を、対応表の行を指して書かせる', instruction.includes('段階のスキルの表示と state.json の値の対応表.md') && instruction.includes(researchMark), instruction);
  check('指示が指す対応表の行は、screen を「調査」にし、調査の行のすべてを持たせる', researchRow.includes('`screen` は「調査」') && researchRow.includes('調査の行のすべて'), researchRow);
  check('リファレンスと規約にない決まりは、指示が持つ', ['downloads を、要件定義書と聞き取りの記録のパスにし', '質問を足さずに返事を終える', '「次の作業へ進む」で始まる文を送ったときに始める', '照合を流すかをユーザーに聞かない', '段階 8 が合格したあとに、まとめて 1 回だけ行う'].every(k => instruction.includes(k)), instruction);
  check('指示は、段階 2 から 7 の完了の報告のあと、同じ返事の中で次の段階を始めさせる', instruction.includes('段階 2 から 7 のユーザーへの完了の報告のあとは') && instruction.includes('同じ返事の中で次の段階のスキルを始め'), instruction);
  check('指示は、段階 5 の照合と修正の組を、修正のスキルの完了の報告のあとも同じ返事の中で続けさせ、段階 6 を同時に進めさせる', instruction.includes('修正のスキルの完了の報告のあとも') && instruction.includes('段階 5 の 1 回目の照合と同時に'), instruction);
  check('--resume の呼び出しにも同じ指示を渡す', argAfter(b, '--append-system-prompt') === argAfter(a, '--append-system-prompt'));
  check('1 回目の引数が要件定義書の章 7 と同じ', JSON.stringify(a.args) === JSON.stringify(['-p', '--session-id', argAfter(a, '--session-id'), ...common]), a.args.join(' '));
  check('2 回目の引数が要件定義書の章 7 と同じ', JSON.stringify(b.args) === JSON.stringify(['-p', '--resume', argAfter(a, '--session-id'), ...common]), b.args.join(' '));
  check('複数行の文を標準入力でそのまま渡す', a.stdin === `画面: 新規\n${text}`, a.stdin);
  check('文は引数に入らず、シェルにも解釈されない', !a.args.join(' ').includes('行目') && !fs.existsSync(path.join(sf, 'p')));
  const big = 'あ'.repeat(350000);
  plan({lines: [init, say('大きな文の返事')]});
  await post('/api/prompt', {text: big});
  await idle();
  const bigCall = calls().at(-1);
  check('1 MB の文を渡す', bigCall.stdin.endsWith(big), `${bigCall.stdin.length} 文字: ${bigCall.stdin.slice(0, 30)}`);
}, {CLAUDE_MODEL: 'test-model'});

testCase('モデルの既定の値', async () => {
  plan({lines: [init, say('返事')]});
  await post('/api/prompt', {text: '文'});
  await idle();
  check('CLAUDE_MODEL がないときは sonnet', argAfter(calls()[0], '--model') === 'sonnet');
}, {CLAUDE_MODEL: ''});

testCase('スキルとサブエージェントの数え方', async () => {
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  const use = (name, id, input = {}) => ({type: 'tool_use', name, id, input});
  plan({hold, lines: [init,
    {type: 'assistant', message: {content: [use('Skill', 'a', {skill: 'first-skill'}), use('Skill', 'b', {skill: 'second-skill'}), use('Skill', 'c', {}), use('Agent', 'd'), use('Task', 'e'), use('Agent', 'f')]}},
    {type: 'user', message: {content: [{type: 'tool_result', tool_use_id: 'd'}]}},
  ]});
  await post('/api/prompt', {text: '文'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  await until(async () => (await status()).subagents === 2, 3000);
  const s = await status();
  check('スキルの名前を呼んだ順に出す', JSON.stringify(s.skillCalls) === '["first-skill","second-skill"]', JSON.stringify(s.skillCalls));
  check('Agent と Task を数え、tool_result で減らす', s.subagents === 2, s.subagents);
  check('busy は true', s.busy === true);
  fs.rmSync(hold);
  await idle();
  check('終わるとサブエージェントの数が 0 に戻る', (await status()).subagents === 0);
});

testCase('別の作業への切り替え', async () => {
  putWork('other', makeState(), {sessionId: 'other-id'});
  fs.utimesSync(out('other', 'ui', 'state.json'), new Date(0), new Date(0));
  plan({files: writesWork(), lines: [init, {type: 'assistant', message: {content: [{type: 'tool_use', name: 'Skill', id: 'a', input: {skill: 'a-skill'}}, {type: 'text', text: '返事'}]}}]});
  await post('/api/prompt', {text: '依頼'});
  await idle();
  await until(async () => (await status()).workDir === 'output/work-1');
  plan({lines: [init, say('別の作業の返事')]});
  const r = await post('/api/prompt', {text: '別の作業への文', workDir: 'output/other'});
  await idle();
  check('添えた別の作業に切り替える', r.status === 202 && argAfter(calls().at(-1), '--resume') === 'other-id', calls().at(-1).args.join(' '));
  check('切り替えると前の作業のスキルを持ち越さない', (await status()).skillCalls.length === 0, JSON.stringify((await status()).skillCalls));
});

testCase('壊れた URL と知らない経路', async () => {
  check('知らない経路は 404', (await req('GET', '/api/none')).status === 404);
  check('知らないメソッドは 404', (await req('PUT', '/api/prompt')).status === 404);
  const stages = await req('GET', '/api/stages');
  check('/api/stages はファイルの中身を返す', stages.text === fs.readFileSync(path.join(sf, 'ui', '段階ごとのスキルと規約.json'), 'utf8'));
  const startPage = await req('GET', '/api/start');
  check('/api/start はファイルの中身を返す', startPage.text === fs.readFileSync(path.join(sf, 'ui', 'はじめに.md'), 'utf8'));
  await req('GET', '//').catch(() => {});
  check('パスが // でも中継サーバーが落ちない', await alive());
});

testCase('画面のファイルがないとき', async () => {
  fs.rmSync(path.join(sf, 'ui', 'はじめに.md'));
  await req('GET', '/api/start').catch(() => {});
  check('はじめに.md がなくても中継サーバーが落ちない', await alive());
});

testCase('途中の作業の一覧', async () => {
  fs.writeFileSync(out('a.txt'), '普通のファイル');
  fs.mkdirSync(out('empty'), {recursive: true});
  putWork('broken', '{"workName":');
  const noneStarted = makeState({workName: '未着手の作業'});
  noneStarted.artifacts = noneStarted.artifacts.map(a => ({...a, status: '未着手'}));
  putWork('none', noneStarted);
  const {workName, ...noName} = makeState();
  putWork('noname', noName);
  const allDone = makeState({stage: 8});
  allDone.artifacts = allDone.artifacts.map(a => ({...a, status: '済み'}));
  putWork('done', allDone);
  const lastOnly = makeState({stage: 8});
  lastOnly.artifacts = lastOnly.artifacts.map((a, i) => ({...a, status: i === 7 ? '済み' : '下書き'}));
  putWork('last-only', lastOnly);
  const list = await works();
  const by = d => list.find(w => w.dir === `output/${d}`);
  check('読めない state.json の作業は飛ばす', !by('broken'));
  check('state.json のないフォルダとファイルは出さない', !by('empty') && !by('a.txt'));
  check('全段階が未着手なら artifact は null', by('none').artifact === null);
  check('作業の名前がないときはフォルダの名前を出す', by('noname').workName === 'noname');
  check('全件が済みなら done', by('done').done === true);
  check('8 件目が済みなら done(要件定義書の章 6)', by('last-only').done === true);
  check('最後の保存は日時', !Number.isNaN(Date.parse(by('none').savedAt)));
  const needsState = {...makeState({decision: {question: 'q', choices: ['a'], replies: []}})};
  putWork('decide', needsState);
  check('決めてもらうことがある作業の状態は「承認待ち」(要件定義書の章 6)', (await works()).find(w => w.dir === 'output/decide').state === '承認待ち');
});

testCase('state.json が null の作業', async () => {
  putWork('nullstate', 'null');
  await req('GET', '/api/works').catch(() => {});
  check('中身が null でも中継サーバーが落ちない', await alive());
});

testCase('artifacts に null がある作業', async () => {
  putWork('nullart', {artifacts: [null]});
  await req('GET', '/api/works').catch(() => {});
  check('中継サーバーが落ちない', await alive());
});

testCase('stream-json の読み取り', async () => {
  await startWork();
  plan({lines: [init, '警告の行です', '{壊れた行', say('続きの返事')]});
  await post('/api/prompt', {text: 'a'});
  await idle();
  check('JSON でない行を飛ばす', conv('work-1').includes('続きの返事'));
  plan({lines: [init, {type: 'system', subtype: 'hook'}, {type: 'user', message: {content: 'ふつうの文'}}, say('文字列の content のあと')]});
  await post('/api/prompt', {text: 'b'});
  await idle();
  check('文字列の content でも落ちない', await alive() && conv('work-1').includes('文字列の content のあと'));
  plan({lines: [init, say('改行のない最後の行')], noNewline: true});
  await post('/api/prompt', {text: 'c'});
  await idle();
  check('改行で終わらない最後の行を読む', conv('work-1').includes('改行のない最後の行'));
  const long = '日本語の長い返事です。'.repeat(20000);
  const raw = Buffer.from(JSON.stringify({type: 'assistant', message: {content: [{type: 'text', text: long}]}}) + '\n');
  const head = Buffer.from(JSON.stringify(init) + '\n');
  const cut = 70000 + 1;
  plan({chunks: [Buffer.concat([head, raw.subarray(0, cut)]).toString('base64'), raw.subarray(cut).toString('base64')], lines: []});
  await post('/api/prompt', {text: 'd'});
  await idle();
  check('日本語の途中でチャンクが切れても文字が壊れない', conv('work-1').includes(long) && !conv('work-1').includes('�'));
});

for (const [name, line] of [
  ['1 行が null', 'null'],
  ['message のない assistant', '{"type":"assistant"}'],
  ['text のない text の要素', '{"type":"assistant","message":{"content":[{"type":"text"}]}}'],
  ['文字列でない errors', '{"type":"result","errors":[1]}'],
]) testCase(`stream-json の異常な行: ${name}`, async () => {
  await startWork();
  plan({lines: [init, line, say('そのあとの返事')]});
  await post('/api/prompt', {text: 'a'});
  await idle();
  check('中継サーバーが落ちない', await alive());
});

testCase('会話が見つからないとき', async () => {
  plan({lines: [init, say('返事')]});
  await post('/api/prompt', {text: '1 回目'});
  await idle();
  const id = argAfter(calls()[0], '--session-id');
  plan({lines: [{type: 'result', is_error: true, errors: ['No conversation found with session ID: x']}], exit: 1});
  await post('/api/prompt', {text: '2 回目'});
  await idle();
  plan({lines: [init, say('回復した返事')]});
  await post('/api/prompt', {text: '3 回目'});
  await idle();
  const c = calls().at(-1);
  check('作業が決まる前に会話が失われても、次の送信は新しい ID の --session-id で始める', !!argAfter(c, '--session-id') && argAfter(c, '--session-id') !== id, c.args.join(' '));
});

testCase('会話が見つからず state.json も消えたとき', async () => {
  await startWork();
  plan({remove: [out('work-1', 'ui', 'state.json')], lines: [{type: 'result', is_error: true, errors: ['No conversation found with session ID: x']}], exit: 1});
  await post('/api/prompt', {text: '文'});
  await sleep(500);
  check('中継サーバーが落ちない', await alive());
});

testCase('作業のフォルダの決まり方', async () => {
  check('output/ がなくても動く', await (async () => {
    fs.rmSync(path.join(sf, 'output'), {recursive: true});
    const a = (await req('GET', '/api/status')).status === 200;
    const b = (await req('GET', '/api/works')).status === 200;
    fs.mkdirSync(path.join(sf, 'output'));
    return a && b;
  })());
  putWork('old-before', makeState());
  fs.utimesSync(out('old-before', 'ui', 'state.json'), new Date(0), new Date(0));
  check('起動の前からある作業を選ばない', (await status()).workDir === null);
  putWork('z-first', makeState());
  await sleep(30);
  putWork('a-second', makeState());
  check('先に書かれた作業を選ぶ(名前の順でない)', (await status()).workDir === 'output/z-first', (await status()).workDir);
  await sleep(30);
  putWork('later', makeState());
  check('決まったあとに別の作業が現れても変わらない', (await status()).workDir === 'output/z-first');
});

testCase('起動の前からある作業の state.json が書き直されたとき', async () => {
  putWork('old', makeState(), {sessionId: 'old-id'});
  // 起動の前からある作業にするために、起動し直す
  await stop();
  await start();
  await status();
  fs.writeFileSync(out('old', 'ui', 'state.json'), JSON.stringify(makeState()));
  await status();
  check('前の会話の session.json を上書きしない', JSON.parse(fs.readFileSync(out('old', 'ui', 'session.json'), 'utf8')).sessionId === 'old-id');
});

testCase('作業のフォルダが消えたとき', async () => {
  await startWork();
  fs.rmSync(out('work-1'), {recursive: true});
  check('/api/status は workDir を null に戻す', (await status()).workDir === null);
  const r = await post('/api/prompt', {text: '消えた作業への答え', workDir: 'output/work-1'});
  check('消えた作業への送信は 404', r.status === 404);
  check('中継サーバーが落ちない', await alive());
});

testCase('session.json の形', async () => {
  await startWork();
  const s = JSON.parse(fs.readFileSync(out('work-1', 'ui', 'session.json'), 'utf8'));
  check('会話の ID を持つ', typeof s.sessionId === 'string' && s.sessionId.length > 0);
  check('作業のフォルダのパスと書いた日時を持つ(要件定義書の章 2.1)', 'workDir' in s && 'writtenAt' in s, JSON.stringify(s));
});

testCase('壊れた session.json', async () => {
  putWork('w', makeState(), '{');
  await post('/api/resume', {dir: 'output/w'});
  check('壊れた session.json は新しい会話にする', (await status()).sessionLost === true);
  putWork('w2', makeState(), {});
  await post('/api/resume', {dir: 'output/w2'});
  check('sessionId のない session.json も新しい会話にする', (await status()).sessionLost === true);
  check('続けられないことを会話に書く', conv('w2').includes('前の会話を続けられないので'));
});

testCase('sessionId が文字列でない session.json', async () => {
  putWork('w', makeState(), {sessionId: 123});
  await post('/api/resume', {dir: 'output/w'});
  await post('/api/prompt', {text: '文'}).catch(() => {});
  await sleep(300);
  check('中継サーバーが落ちない', await alive());
});

testCase('claude がなくなったとき', async () => {
  await startWork();
  fs.rmSync(path.join(fake, 'bin', 'claude'));
  const pathBefore = await status();
  check('起動のときの確かめは true のまま', pathBefore.hasClaude === true);
  const r = await post('/api/prompt', {text: '文'}).catch(() => ({status: 0}));
  await sleep(300);
  check('中継サーバーが落ちない', await alive(), r.status);
  check('会話に終了コードの行を書く', conv('work-1').includes('(終了コード'));
  check('busy が false に戻る', (await status()).busy === false);
});

testCase('標準入力を読まない claude', async () => {
  await startWork();
  plan({skipStdin: true, lines: [init, say('読まない返事')]});
  await post('/api/prompt', {text: 'x'.repeat(2000000)});
  await idle();
  check('中継サーバーが落ちない', await alive());
});

testCase('同時の送信', async () => {
  await startWork();
  const before = calls().length;
  const hold = path.join(fake, 'hold');
  fs.writeFileSync(hold, '');
  plan({hold, lines: [init]});
  await post('/api/prompt', {text: '1 つ目'});
  await until(() => fs.existsSync(path.join(fake, 'holding')));
  check('AI が返事を書いている間の送信は 409', (await post('/api/prompt', {text: '2 つ目'})).status === 409);
  check('claude の呼び出しが増えない', calls().length === before + 1);
  check('断った文を会話に書かない', !conv('work-1').includes('2 つ目'));
  fs.rmSync(hold);
  await idle();
});

testCase('あとで続けるとやめるで作業を離れる', async () => {
  const post = (text, leave) => req('POST', '/api/prompt', {headers: {Origin: `http://127.0.0.1:${port}`, 'Content-Type': 'application/json'}, body: {text, leave}});
  const status = async () => JSON.parse((await req('GET', '/api/status')).text);
  const idle = () => until(async () => !(await status()).busy, 5000);
  const w = n => path.join(sf, 'output', n);
  const plan = name => fs.writeFileSync(path.join(fake, 'next.json'), JSON.stringify({files: {[path.join(w(name), 'ui', 'state.json')]: JSON.stringify(makeState({workName: name}))}}));
  plan('w1');
  await post('依頼');
  await idle();
  check('作業のフォルダが決まる', (await status()).workDir === 'output/w1');
  await post('あとで続ける', '知らない語');
  await idle();
  check('知らない語の leave では作業を離れない', (await status()).workDir === 'output/w1');
  await post('あとで続ける', 'あとで続ける');
  await idle();
  check('「あとで続ける」の返事のあとに作業を離れる', (await status()).workDir === null);
  const list1 = JSON.parse((await req('GET', '/api/works')).text);
  check('離れた作業は途中の作業の一覧に残る', list1.some(x => x.dir === 'output/w1'));
  check('離れたあとの会話は元の作業に書かない', (await req('GET', '/files/ui/state.json')).status === 404);
  plan('w2');
  await post('別の依頼');
  await idle();
  check('離れたあとの新しい依頼は別の作業になる', (await status()).workDir === 'output/w2');
  const args = JSON.parse(fs.readFileSync(path.join(fake, 'log.jsonl'), 'utf8').trim().split('\n').at(-1)).args;
  check('離れたあとの新しい依頼は新しい会話で始める', args.includes('--session-id'), args.join(' '));
  await post('やめる', 'やめる');
  await idle();
  check('「やめる」の返事のあとに作業を離れる', (await status()).workDir === null);
  check('「やめる」は ui/stopped.json を置く', fs.existsSync(path.join(w('w2'), 'ui', 'stopped.json')));
  check('「やめる」の作業のファイルは残る', fs.existsSync(path.join(w('w2'), 'ui', 'state.json')));
  check('「やめる」の作業は途中の作業の一覧から外れる', !JSON.parse((await req('GET', '/api/works')).text).some(x => x.dir === 'output/w2'));
  const back = await req('POST', '/api/resume', {headers: {Origin: `http://127.0.0.1:${port}`, 'Content-Type': 'application/json'}, body: {dir: 'output/w1'}});
  check('離れた作業は「続きから」で開ける', back.status === 200 && (await status()).workDir === 'output/w1');
});

// 要件定義書の章 3.2 と章 7 の行「返事の時間の記録」、インターフェース設計書の章 6
testCase('返事のあとに返事の時間.jsonl に 1 行足す', async () => {
  const timeFiles = () => fs.readdirSync(out()).flatMap(n => { const f = out(n, 'ui', '返事の時間.jsonl'); return fs.existsSync(f) ? [f] : []; });
  plan({lines: [init, say('作業が決まる前の返事')]});
  await post('/api/prompt', {text: '作業が決まる前の文'});
  await idle();
  check('作業のフォルダが決まっていないときは書かない', timeFiles().length === 0 && !fs.existsSync(path.join(sf, 'ui', '返事の時間.jsonl')), timeFiles().join('、'));
  await startWork();
  const file = out('work-1', 'ui', '返事の時間.jsonl');
  const rows = () => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l)) : []);
  check('作業のフォルダが決まった返事のあとに 1 行を書く', rows().length === 1 && rows()[0].promptHead === '依頼', JSON.stringify(rows()));
  const long = 'あ'.repeat(45) + '後ろの文';
  plan({lines: [init, say('返事'), {type: 'result', subtype: 'success', is_error: false, duration_ms: 12345, duration_api_ms: 10000, num_turns: 4, result: '返事'}]});
  await post('/api/prompt', {text: long});
  await idle();
  const r = rows().at(-1) || {};
  check('返事ごとに 1 行足す', rows().length === 2, rows().length);
  check('1 行は 6 つのキーを持つ', Object.keys(r).join(',') === 'sentAt,endedAt,duration_ms,duration_api_ms,num_turns,promptHead', Object.keys(r).join(','));
  const iso = v => typeof v === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(v);
  check('送った時刻と終わった時刻は ISO の形で、送った時刻が先', iso(r.sentAt) && iso(r.endedAt) && Date.parse(r.sentAt) <= Date.parse(r.endedAt), `${r.sentAt} ${r.endedAt}`);
  check('stream-json の result の duration_ms と duration_api_ms と num_turns を写す', r.duration_ms === 12345 && r.duration_api_ms === 10000 && r.num_turns === 4, JSON.stringify(r));
  check('送った文の 2 行目からの先頭 40 文字を持ち、1 行目の「画面:」を含まない', r.promptHead === 'あ'.repeat(40) && calls().at(-1).stdin.startsWith('画面: output/work-1\n'), r.promptHead);
  plan({lines: [init, say('result のない返事')]});
  await post('/api/prompt', {text: 'result のない文'});
  await idle();
  const n = rows().at(-1) || {};
  check('result の行がないときは 3 つの値を null にする', rows().length === 3 && n.duration_ms === null && n.duration_api_ms === null && n.num_turns === null, JSON.stringify(n));
  plan({lines: [init], stderr: '失敗', exit: 2});
  await post('/api/prompt', {text: '失敗する文'});
  await idle();
  check('0 でない終了コードで終わった返事も 1 行足す', rows().length === 4 && rows().at(-1).promptHead === '失敗する文', rows().length);
  check('中継サーバーは返事の時間.jsonl を会話の記録に書かない', !conv('work-1').includes('duration_ms'));
});

testCase('API の答えの形', async () => {
  const s = await status();
  const keys = Object.keys(s).sort().join(',');
  check('/api/status は 7 つのキーを持つ', keys === 'agentCalls,busy,hasClaude,sessionLost,skillCalls,subagents,workDir', keys);
  check('/api/status の型', typeof s.busy === 'boolean' && typeof s.hasClaude === 'boolean' && Array.isArray(s.skillCalls) && typeof s.subagents === 'number' && s.workDir === null && typeof s.sessionLost === 'boolean');
  putWork('w', makeState());
  const w = (await works())[0];
  check('/api/works の 1 行は 6 つのキーを持つ', ['artifact', 'dir', 'done', 'savedAt', 'stage', 'workName'].every(k => k in w), Object.keys(w).join(','));
});

async function main() {
  if (process.argv.includes('--list')) { for (const c of cases) console.log(c.name); return; }
  if (only && !cases.some(c => c.name === only)) { setCase('全体'); check(`ケース ${only} がない`, false); }
  for (const c of cases) {
    if (only && c.name !== only) continue;
    console.log(`--- ${c.name}`);
    setCase(c.name);
    makeCopy();
    port = await freePort();
    try {
      await start(c.env);
      await c.fn();
    } catch (e) {
      check('途中で止まらない', false, e.message.split('\n')[0]);
    }
    await stop().catch(() => {});
  }
}

main().catch(e => { setCase('全体'); check('テストの実行', false, e.stack); }).finally(() => {
  fs.rmSync(root, {recursive: true, force: true});
  if (process.argv.includes('--list')) process.exit(0);
  process.exit(finish(cases.map(c => c.name), !only));
});
