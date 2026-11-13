#!/usr/bin/env node
// claude の代わりに決まった応答を返すスクリプト。FAKE_DIR の next.json を 1 回の呼び出しの計画として読む。
// 計画のキー: files(書くファイル)、remove(消すファイル)、lines(そのまま出す行)、chunks(base64 で分けて出す塊)、
// noNewline(最後の行の改行を省く)、hold(このファイルがある間、途中の返事のあとで待つ)、ignoreTerm(SIGTERM を無視する)、skipStdin(標準入力を読まない)、exit(終了コード)、stderr(標準エラーの文)
import fs from 'node:fs';
import path from 'node:path';

const dir = process.env.FAKE_DIR;
const args = process.argv.slice(2);
if (args[0] === '--version') { console.log('fake 0.0.0'); process.exit(0); }
const nextFile = path.join(dir, 'next.json');
let plan = {};
if (fs.existsSync(nextFile)) { plan = JSON.parse(fs.readFileSync(nextFile, 'utf8')); fs.rmSync(nextFile); }
if (plan.ignoreTerm) process.on('SIGTERM', () => {});
const sleep = ms => new Promise(r => setTimeout(r, ms));
const write = s => new Promise(r => process.stdout.write(s, r));

async function run(input) {
  fs.appendFileSync(path.join(dir, 'log.jsonl'), JSON.stringify({args, stdin: input, pid: process.pid}) + '\n');
  for (const [p, body] of Object.entries(plan.files || {})) {
    fs.mkdirSync(path.dirname(p), {recursive: true});
    fs.writeFileSync(p, body);
  }
  for (const p of plan.remove || []) fs.rmSync(p, {force: true});
  if (plan.stderr) process.stderr.write(plan.stderr);
  const lines = plan.lines || [{type: 'system', subtype: 'init', session_id: 'x'}, {type: 'assistant', message: {content: [{type: 'text', text: '決まった返事です。'}]}}];
  for (let i = 0; i < lines.length; i++) {
    const line = typeof lines[i] === 'string' ? lines[i] : JSON.stringify(lines[i]);
    await write(line + (plan.noNewline && i === lines.length - 1 ? '' : '\n'));
  }
  for (const c of plan.chunks || []) { await write(Buffer.from(c, 'base64')); await sleep(30); }
  if (plan.hold) {
    fs.writeFileSync(path.join(dir, 'holding'), '');
    while (fs.existsSync(plan.hold)) await sleep(30);
    await write(JSON.stringify({type: 'assistant', message: {content: [{type: 'text', text: '待ったあとの返事です。'}]}}) + '\n');
  }
  process.exit(plan.exit || 0);
}

if (plan.skipStdin) run('');
else {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', d => { input += d; });
  process.stdin.on('end', () => run(input));
}
