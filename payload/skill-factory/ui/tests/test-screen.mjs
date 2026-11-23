#!/usr/bin/env node
// 画面(ui/index.html)を本物のブラウザで操作するテスト。
// 使い方: skill-factory/ で `npm install --prefix ui/tests` と `npx --prefix ui/tests playwright install chromium` のあと、`node ui/tests/test-screen.mjs`。終了コード 0 が全件合格。
// AI はモック(claude の代わりに決まった応答を返すスクリプト)を使う。本物の claude は test-real.mjs が使う。
// `--case "質問の一覧に答える"` のようにケースの名前で 1 件だけ流す。`--list` でケースの名前を出す。不合格のケースの画面の写真を ARTIFACT_DIR に残す。
// 一時フォルダの skill-factory の写しで動き、ui/ と output/ を変えない。
import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {artifacts, check, finish, freePort, makeState, setCase, threeQuestions, totals} from './lib/report.mjs';
import {stateContractGaps} from './lib/state-contract.mjs';

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const uiDir = path.dirname(testsDir);
const only = process.argv.includes('--case') ? process.argv[process.argv.indexOf('--case') + 1] : null;
const port = Number(process.env.PORT) || (process.argv.includes('--list') ? 0 : await freePort());
const url = `http://127.0.0.1:${port}/`;
const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'sf-screen.'));
const sf = path.join(tmp, 'sf');
const fake = path.join(tmp, 'fake');
const log = path.join(fake, 'log.jsonl');
const next = path.join(fake, 'next.json');
const hold = path.join(fake, 'hold');
const noConversation = path.join(fake, 'no-conversation');
const noVersion = path.join(fake, 'no-version');
const work = 'output/work-1';
const workPath = path.join(sf, work);
const statePath = path.join(workPath, 'ui', 'state.json');
const sessionPath = path.join(workPath, 'ui', 'session.json');

let server = null;
let browser = null;
const ng = (name, detail) => check(name, false, detail);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// fn が真を返すまで待つ。時間を超えたら false を返す
async function until(fn, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await fn()) return true;
    await sleep(100);
  }
  return false;
}

// claude の代わりのスクリプト: 引数と標準入力を記録し、next.json があれば作業のフォルダにファイルを書き、stream-json の返事を出す
const fakeScript = `#!/usr/bin/env node
const fs = require('fs'), path = require('path');
const [log, next, hold, noConversation, noVersion, sf] = ${JSON.stringify([log, next, hold, noConversation, noVersion, sf])};
const args = process.argv.slice(2);
if (args[0] === '--version') process.exit(fs.existsSync(noVersion) ? 1 : 0);
const out = o => console.log(JSON.stringify(o));
let input = '';
process.stdin.on('data', d => { input += d; });
process.stdin.on('end', async () => {
  fs.appendFileSync(log, JSON.stringify({args, stdin: input}) + '\\n');
  while (fs.existsSync(hold)) await new Promise(r => setTimeout(r, 50));
  if (fs.existsSync(noConversation)) {
    fs.rmSync(noConversation);
    out({type: 'result', is_error: true, errors: ['No conversation found with session ID: x']});
    process.exit(1);
  }
  out({type: 'system', subtype: 'init', session_id: 'x'});
  let plan = {};
  if (fs.existsSync(next)) { plan = JSON.parse(fs.readFileSync(next, 'utf8')); fs.rmSync(next); }
  for (const [p, body] of Object.entries(plan.files || {})) {
    const f = path.join(sf, p);
    fs.mkdirSync(path.dirname(f), {recursive: true});
    fs.writeFileSync(f, body);
  }
  if (plan.lines) {
    for (const l of plan.lines) out(l);
    if (plan.holdAfter) while (fs.existsSync(hold + '-after')) await new Promise(r => setTimeout(r, 50));
    if (plan.reply) out({type: 'assistant', message: {content: [{type: 'text', text: plan.reply}]}});
    return;
  }
  if (plan.stderr) process.stderr.write(plan.stderr);
  if (plan.exit) { process.exitCode = plan.exit; return; }
  const content = [];
  if (plan.skill) content.push({type: 'tool_use', name: 'Skill', id: 't1', input: {skill: plan.skill}});
  content.push({type: 'text', text: plan.reply || '決まった返事です。'});
  out({type: 'assistant', message: {content}});
});
`;

const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l)) : []);
const lastCall = () => calls().at(-1);
const argAfter = (call, name) => { const i = call.args.indexOf(name); return i < 0 ? null : call.args[i + 1]; };

function startServer() {
  // 本物の claude を呼ばないように、PATH を偽の claude と node とシステムのコマンドだけにする
  const env = {...process.env, PORT: String(port), PATH: `${path.join(fake, 'bin')}:/usr/bin:/bin`};
  server = spawn('node', ['ui/server.mjs'], {cwd: sf, env, stdio: 'ignore'});
  return until(() => fetch(url + 'api/status').then(r => r.ok).catch(() => false), 20000);
}

async function stopServer() {
  if (!server) return;
  const s = server;
  server = null;
  const closed = new Promise(r => s.on('close', r));
  s.kill('SIGINT');
  await closed;
}

// ケースごとに、作業のない状態の中継サーバーと新しいブラウザの画面で始める
async function freshCase(opts = {}) {
  await stopServer();
  for (const f of [next, hold, noConversation, noVersion, log]) fs.rmSync(f, {force: true});
  fs.rmSync(path.join(sf, 'output'), {recursive: true, force: true});
  fs.rmSync(path.join(sf, 'ui', '.pending'), {recursive: true, force: true});
  fs.mkdirSync(path.join(sf, 'output'), {recursive: true});
  await startServer();
  const context = await browser.newContext({acceptDownloads: true});
  // 同じ版の marked を手元から返し、ネットワークがなくても同じ結果にする。CDN のケースだけは要求を失敗させる
  await context.route('https://cdnjs.cloudflare.com/**', route => (opts.noCdn ? route.abort() : route.fulfill({contentType: 'application/javascript', body: markedScript})));
  const page = await context.newPage();
  page.caseErrors = [];
  page.on('pageerror', e => page.caseErrors.push(e.message));
  await page.goto(url);
  return {context, page};
}

// 次の claude の呼び出しが書くファイルを決める
function planNext(state, plan = {}) {
  const files = {...(plan.files || {})};
  if (state) files[`${work}/ui/state.json`] = JSON.stringify(state);
  fs.writeFileSync(next, JSON.stringify({...plan, files}));
}

// 最初の依頼を画面の入力欄から送り、作業のフォルダが決まるまで進める
async function startWork(page, state, plan) {
  planNext(state, plan);
  await page.fill('#input', 'テストのスキルを作って');
  await page.press('#input', 'Enter');
  return until(() => page.evaluate(() => !!state));
}

const visible = (page, sel) => page.locator(sel).first().isVisible();
const waitVisible = (page, sel, ms) => until(() => visible(page, sel), ms);
const waitHidden = (page, sel, ms) => until(async () => !(await visible(page, sel)), ms);
const text = (page, sel) => page.locator(sel).first().innerText();
const waitIdle = page => until(async () => (await page.evaluate(() => fetch('/api/status').then(r => r.json()))).busy === false);
const messages = async page => (await page.locator('#messages').innerText());

// 問いの番号に当たる答えの欄
const answerBox = (page, n) => page.getByLabel(`質問 ${n} の答え`);
const sendAnswers = page => page.locator('#qform .qfoot button').click();
// 試作の画面 1: 途中の作業の一覧は「途中の作業 N 件」を押すと開く
const openWorks = async page => { await waitVisible(page, '#works > summary'); await page.locator('#works > summary').click(); };
// 聞き取りの画面の会話は、下の 1 行の「会話の記録」を押すと開く
const openRecord = page => page.locator('#recordopen').click();

const cases = [];
const testCase = (name, fn, opts = {}) => cases.push({name, fn, opts});
const markedScript = fs.readFileSync(path.join(testsDir, 'node_modules', 'marked', 'marked.min.js'), 'utf8');

testCase('開いた直後の画面', async page => {
  check('開いた直後の文が出る', await until(async () => (await text(page, '#welcome')).includes('作成したいスキルについて、自由に書いてください')));
  check('右の欄は出ない', !(await visible(page, '#preview')));
  check('途中の作業の一覧は 0 件のとき出ない', !(await visible(page, '#works')));
  check('接続の状態は「AI に接続中」', (await text(page, '#conn')) === 'AI に接続中');
  check('段階の帯は 8 段階を出す', await until(async () => (await page.locator('#stages .pill').count()) === 8));
});

testCase('入力欄の送信', async page => {
  await page.fill('#input', '1 行目');
  await page.press('#input', 'Shift+Enter');
  await page.type('#input', '2 行目');
  check('Shift+Enter は改行し、送らない', (await page.inputValue('#input')) === '1 行目\n2 行目' && calls().length === 0);
  await page.fill('#input', 'テストのスキルを作って');
  fs.writeFileSync(hold, '');
  planNext(makeState(), {reply: '**太字**の返事です。'});
  await page.press('#input', 'Enter');
  check('Enter で送り、入力欄が空になる', (await page.inputValue('#input')) === '');
  await waitVisible(page, '#recordopen');
  await openRecord(page);
  check('返事を書いている間は点の吹き出しが出る', await waitVisible(page, '#messages .typing'));
  check('ユーザーの文が右寄せの吹き出しに出る', await until(async () => (await page.locator('.msg.user').count()) === 1 && (await text(page, '.msg.user')) === 'テストのスキルを作って'));
  fs.rmSync(hold);
  check('AI の返事が吹き出しに md の形で出る', await until(async () => (await page.locator('.msg.ai strong').count()) === 1));
  check('点の吹き出しが消える', await waitHidden(page, '#messages .typing'));
  const c = calls()[0];
  check('claude に「画面: 新規」と依頼の文が渡る', c.stdin === '画面: 新規\nテストのスキルを作って', c.stdin);
  check('1 回目は --session-id で呼ぶ', !!argAfter(c, '--session-id'), c.args.join(' '));
});

testCase('質問の一覧に答える', async page => {
  check('依頼のあとに作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  check('右の欄に質問の一覧が出る', await waitVisible(page, '#qform'));
  const first = calls()[0];
  const id = argAfter(first, '--session-id');
  const head = () => text(page, '#qform .qhead .c');
  check('全体と回答済みと残りの問数が出る', (await head()) === '全 3 問(回答済み 0 問、残り 3 問)', await head());
  const go = page.locator('#qform .qfoot button');
  check('答えが 0 問の間は送るボタンを押せない', await go.isDisabled());
  await page.locator('#qform .chip', {hasText: '必須'}).click();
  check('選択肢を押すと問数が増える', await until(async () => (await head()) === '全 3 問(回答済み 1 問、残り 2 問)'));
  await page.locator('#qform .chip', {hasText: '任意'}).click();
  await page.locator('#qform .chip', {hasText: '必須'}).click();
  await answerBox(page, 3).fill('請求書の一覧');
  check('文の答えで問数が増える', await until(async () => (await head()) === '全 3 問(回答済み 2 問、残り 1 問)'));
  check('答えると送るボタンを押せる', await go.isEnabled());
  fs.writeFileSync(hold, '');
  planNext(makeState({questions: threeQuestions({1: '必須', 3: '請求書の一覧'}), }));
  await sendAnswers(page);
  check('送ると、返事を書いている間は質問の一覧が隠れる', await waitHidden(page, '#qform'));
  check('AI に渡る', await until(() => calls().length === 2));
  const c = lastCall();
  check('claude に作業のフォルダと、答えた問いだけの「番号: 答え」が渡る', c.stdin === `画面: ${work}\n1: 必須\n3: 請求書の一覧`, c.stdin);
  check('元の会話の ID を --resume で渡す', argAfter(c, '--resume') === id, c.args.join(' '));
  fs.rmSync(hold);
  await waitIdle(page);
  check('答えのない問いだけが再び出る', await until(async () => (await page.locator('#qform .qi').count()) === 1 && (await text(page, '#qform .qi')).includes('入力は何ですか')));
  check('問数は state.json の回答済みを数える', (await head()) === '全 3 問(回答済み 2 問、残り 1 問)', await head());
  check('会話の欄には「画面:」の行が出ない', !(await messages(page)).includes('画面:'));
  planNext(null);
  await answerBox(page, 2).fill('請求書');
  await sendAnswers(page);
  await until(() => calls().length === 3);
  await waitIdle(page);
  await sleep(2500);
  check('state.json が変わらないうちは、同じ質問の一覧を再び出さない', !(await visible(page, '#qform')));
  fs.writeFileSync(statePath, JSON.stringify(makeState({questions: threeQuestions({1: '必須', 3: '請求書の一覧'}, {added: 2, removed: 1})})));
  check('問いが増減すると増減の文が出る', await until(async () => (await visible(page, '#qform .qnote')) && (await text(page, '#qform .qnote')) === '前の答えで、質問が 2 問増え、1 問減りました。'));
});

testCase('承認の選択と返答の候補', async page => {
  const decision = {question: '要件定義書を承認しますか', choices: ['承認する', '直す'], replies: []};
  check('作業が決まる', await startWork(page, makeState({decision})));
  check('選択肢の数だけボタンが出る', await until(async () => (await page.locator('.decision .choice').count()) === 2));
  check('最初の選択肢を推奨として塗る', (await page.locator('.decision .choice').first().getAttribute('class')).includes('main'));
  planNext(null);
  await page.locator('.decision .choice', {hasText: '承認する'}).click();
  check('押した選択肢の文が claude に渡る', await until(() => calls().length === 2 && lastCall().stdin === `画面: ${work}\n承認する`));
  await waitIdle(page);
  await sleep(2500);
  check('決めてもらうことが変わるまでボタンを押せない', await page.locator('.decision .choice').first().isDisabled());
  check('押したボタンにチェックが付く', (await text(page, '.decision .choice.picked')).includes('✓'));
  fs.writeFileSync(statePath, JSON.stringify(makeState({decision: {question: '次に進みますか', choices: [], replies: ['進む', '止める']}})));
  check('返答の候補が問いの下に出る', await until(async () => (await page.locator('#messages .chips .chip').count()) === 2));
  await page.locator('#messages .chips .chip', {hasText: '進む'}).click();
  check('候補を押すと入力欄に入り、送らない', (await page.inputValue('#input')) === '進む' && calls().length === 2);
  planNext(null);
  await page.press('#input', 'Enter');
  check('候補の文が claude に渡る', await until(() => calls().length === 3 && lastCall().stdin === `画面: ${work}\n進む`));
  await waitIdle(page);
  await sleep(2500);
  check('送ったあとは候補を出さない', (await page.locator('#messages .chips .chip').count()) === 0);
  fs.writeFileSync(statePath, JSON.stringify(makeState({decision: {question: '名前を教えてください', choices: [], replies: []}})));
  check('選択肢も候補もない問いは入力欄を案内する', await until(async () => (await messages(page)).includes('答えを入力欄に書いて送ってください。')));
});

testCase('段階の帯と文書と図とダウンロード', async page => {
  const svg = name => `<svg xmlns="http://www.w3.org/2000/svg" id="${name}" width="10" height="10"></svg>`;
  // 段階 2 で decision がない state.json は、中央のカードの待つの画面(K1)。文書のタブは、panels の open で開いて置く(画面遷移設計書の章 4.4)
  const docPanel = {kind: '文書', name: '分割設計書', path: '分割設計書.md', key: null, open: true, isNew: false};
  const k1 = (over = {}) => makeState({stage: 2, documentPath: '分割設計書.md', panels: [docPanel], ...over});
  fs.writeFileSync(hold, '');
  planNext(k1(), {files: {}});
  await page.fill('#input', 'テストのスキルを作って');
  await page.press('#input', 'Enter');
  // 依頼の返事を待たせたまま、作業のフォルダだけを先に決める
  fs.mkdirSync(path.join(workPath, 'ui'), {recursive: true});
  fs.writeFileSync(statePath, JSON.stringify(k1()));
  check('ファイルがなく AI が書いているときは「書いています」', await until(async () => (await visible(page, '#hear')) && (await hearBody(page)).includes('分割設計書を書いています')));
  fs.writeFileSync(path.join(workPath, '分割設計書.md'), '# 見出し\n\n| 列 |\n|---|\n| 値 |\n');
  // 「書き直しています」は、report.start.rewrite が true のときだけ(state.json の約束の章 6)
  fs.writeFileSync(statePath, JSON.stringify(k1({report: {start: {rewrite: true}}})));
  check('ファイルがあり AI が書いているときは「書き直しています」', await until(async () => (await hearBody(page)).includes('書き直しています')));
  fs.rmSync(hold);
  await waitIdle(page);
  check('ファイルがあり AI が待っているときは md を表の形で出す', await until(async () => (await page.locator('#hearbody .lpane table').count()) === 1 && !(await hearBody(page)).includes('書き直しています')));
  check('いまの段階と済んだ段階を帯に出す', (await text(page, '#stages .pill.now')).includes('2') && (await text(page, '#stages .pill.done')).includes('✓'));
  check('作業の名前を出す', (await text(page, '#work')) === 'テストの作業');
  fs.rmSync(path.join(workPath, '分割設計書.md'));
  check('ファイルがなく AI も書いていないときは「まだありません」', await until(async () => (await hearBody(page)).includes('分割設計書はまだありません')));
  fs.mkdirSync(path.join(workPath, 'ui', 'figures'), {recursive: true});
  fs.writeFileSync(path.join(workPath, 'ui', 'figures', 'a.svg'), svg('fig-a'));
  fs.writeFileSync(path.join(workPath, 'ui', 'figures', 'b.svg'), svg('fig-b'));
  fs.writeFileSync(path.join(workPath, '成果物.txt'), '中身');
  // panels のない前の形の state.json では、figures の最後の図のタブを開く(state.json の約束の章 1)。段階 2 は図のタブを出さないので、段階 3 で確かめる
  fs.writeFileSync(statePath, JSON.stringify(makeState({stage: 3, documentPath: '分割設計書.md', figures: [{tab: '図 A', path: 'ui/figures/a.svg'}, {tab: '図 B', path: 'ui/figures/b.svg'}], downloads: ['成果物.txt']})));
  check('新しい図を読み直しなしで出す(最後の図)', await until(async () => (await page.locator('#hearbody .lpane #fig-b').count()) === 1));
  const tabA = page.locator('#hearbody .ltab', {hasText: '図: 図 A'});
  await tabA.click();
  check('タブで図を切り替える', await until(async () => (await page.locator('#hearbody .lpane #fig-a').count()) === 1));
  await tabA.click();
  check('開いているタブをもう一度押すと図を畳む', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0 && (await hearBody(page)).includes('タブを押すと開き')));
  await tabA.click();
  check('畳んだタブを押すと図を開く', await until(async () => (await page.locator('#hearbody .lpane #fig-a').count()) === 1));
  await page.locator('#hearbody .ldl').click();
  check('ダウンロードの一覧を出す', await waitVisible(page, '#hearbody .ldlmenu a'));
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#hearbody .ldlmenu a', {hasText: '成果物.txt'}).click()]);
  check('ファイルをダウンロードする', download.suggestedFilename() === '成果物.txt' && fs.readFileSync(await download.path(), 'utf8') === '中身', download.suggestedFilename());
});

testCase('実行中のスキルと一覧', async page => {
  check('作業が決まる', await startWork(page, makeState(), {skill: 'defining-skill-requirements'}));
  check('実行中のスキルの名前を出す', await until(async () => (await visible(page, '#running')) && (await text(page, '#running')).includes('defining-skill-requirements')));
  await page.click('#running');
  check('押すと段階のスキルと規約の一覧を開く', await waitVisible(page, '#stack'));
  check('一覧にスキルの状態を出す', (await text(page, '#stack')).includes('呼んだ(1 番目)'));
  await page.click('#welcome', {force: true}).catch(() => {});
  await page.click('#work');
  check('ほかの場所を押すと閉じる', await waitHidden(page, '#stack'));
});

testCase('中継サーバーだけを起動し直し、画面を読み直さずに答える', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  const id = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  await answerBox(page, 2).fill('起動し直す前に書いた答え');
  await stopServer();
  check('止まると「中継サーバーにつながりません」を出す', await until(async () => (await text(page, '#conn')) === '中継サーバーにつながりません'));
  check('止まっている間は直し方を出す', await waitVisible(page, '#banner'));
  await startServer();
  check('起動し直すと「接続中」に戻る', await until(async () => (await text(page, '#conn')) === '接続中'));
  check('質問の一覧と書いた答えが残る', (await visible(page, '#qform')) && (await answerBox(page, 2).inputValue()) === '起動し直す前に書いた答え');
  planNext(makeState({questions: threeQuestions({2: '起動し直す前に書いた答え'})}));
  await sendAnswers(page);
  check('答えが claude に渡る', await until(() => calls().length === 2));
  const c = lastCall();
  check('claude に「画面: 新規」ではなく作業のフォルダが渡る', c.stdin === `画面: ${work}\n2: 起動し直す前に書いた答え`, c.stdin);
  check('元の会話の ID を --resume で渡す', argAfter(c, '--resume') === id, c.args.join(' '));
  check('残りの問いが出る', await until(async () => (await page.locator('#qform .qi').count()) === 2));
});

testCase('中継サーバーを起動し直して画面を読み直してから答える', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  const id = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  check('読み直すと開いた直後の画面に途中の作業が出る', await waitVisible(page, '#works .wk'));
  check('右の欄は出ない', !(await visible(page, '#preview')));
  await page.locator('#works .wk button', {hasText: '続きから'}).click();
  check('「続きから」で質問の一覧が出る', await waitVisible(page, '#qform'));
  planNext(null);
  await answerBox(page, 2).fill('答え');
  await sendAnswers(page);
  check('元の会話の ID を --resume で渡す', await until(() => calls().length === 2 && argAfter(lastCall(), '--resume') === id));
  check('claude に作業のフォルダが渡る', lastCall().stdin === `画面: ${work}\n2: 答え`, lastCall().stdin);
});

testCase('session.json がない作業で、読み直さずに答える', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  const oldId = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  await stopServer();
  fs.rmSync(sessionPath);
  await startServer();
  await until(async () => (await text(page, '#conn')) === '接続中');
  const before = calls().length;
  await answerBox(page, 2).fill('行き場のない答え');
  await sendAnswers(page);
  check('理由を入力欄の上に出す', await until(async () => (await visible(page, '#err')) && (await text(page, '#err')).includes('前の会話を続けられない')));
  check('claude を呼ばない', calls().length === before);
  check('会話に続けられないことを出す', await until(async () => (await messages(page)).includes('前の会話を続けられないので')));
  check('質問の一覧を隠す', await waitHidden(page, '#qform'));
  check('送れなかった答えを入力欄に戻さない(そのまま送ると新しい会話に届くため)', (await page.inputValue('#input')) === '', await page.inputValue('#input'));
  planNext(makeState({questions: threeQuestions()}));
  await page.fill('#input', 'output/work-1/要件定義書.md');
  await page.press('#input', 'Enter');
  check('次の送信は新しい会話の ID を --session-id で渡す', await until(() => calls().length === before + 1));
  const c = lastCall();
  const newId = argAfter(c, '--session-id');
  check('新しい会話の ID は前の ID と違う', !!newId && newId !== oldId, c.args.join(' '));
  check('state.json が書き直されると質問の一覧が戻る', await waitVisible(page, '#qform'));
  check('入力欄の上の理由が消える', !(await visible(page, '#err')));
});

testCase('--resume の会話が見つからない作業で答える', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  const oldId = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  fs.writeFileSync(noConversation, '');
  await answerBox(page, 2).fill('答え');
  await sendAnswers(page);
  check('会話に続けられないことを出す', await until(async () => (await messages(page)).includes('前の会話を続けられないので')));
  check('質問の一覧を隠す', !(await visible(page, '#qform')));
  const newId = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  check('session.json の会話の ID が替わる', newId !== oldId);
  planNext(makeState({questions: threeQuestions()}));
  await page.fill('#input', 'output/work-1/要件定義書.md');
  await page.press('#input', 'Enter');
  check('次の送信は新しい会話の ID を --session-id で渡す', await until(() => argAfter(lastCall(), '--session-id') === newId));
  check('state.json が書き直されると質問の一覧が戻る', await waitVisible(page, '#qform'));
});

testCase('送れないときの答えの扱い', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  const id = JSON.parse(fs.readFileSync(sessionPath, 'utf8')).sessionId;
  await stopServer();
  await answerBox(page, 2).fill('止まっている間の答え');
  await sendAnswers(page);
  check('中継サーバーが止まっていると理由を出す', await until(async () => (await visible(page, '#err')) && (await text(page, '#err')).includes('中継サーバーにつながりません')));
  check('答えを「番号: 答え」の形で入力欄に戻す', await until(async () => (await page.inputValue('#input')) === '2: 止まっている間の答え', 3000), await page.inputValue('#input'));
  await startServer();
  await until(async () => (await text(page, '#conn')) === '接続中');
  planNext(null);
  await page.press('#input', 'Enter');
  check('起動し直したあとに送り直すと元の会話に渡る', await until(() => calls().length === 2 && argAfter(lastCall(), '--resume') === id && lastCall().stdin === `画面: ${work}\n2: 止まっている間の答え`));
});

testCase('AI が返事を書いている間の送信と 2 つ目のタブ', async (page, context) => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  const other = await context.newPage();
  await other.goto(url);
  check('2 つ目のタブに同じ作業が出る', await until(async () => (await other.evaluate(() => state && state.workName)) === 'テストの作業'));
  fs.writeFileSync(hold, '');
  await page.fill('#input', '1 つ目のタブの文');
  await page.press('#input', 'Enter');
  await until(() => calls().length === 2);
  await other.fill('#input', '2 つ目のタブの文');
  await other.press('#input', 'Enter');
  check('返事を書いている間の送信は理由を出す', await until(async () => (await visible(other, '#err')) && (await text(other, '#err')).includes('返事を書いています')));
  check('断られた文を入力欄に戻す', await until(async () => (await other.inputValue('#input')) === '2 つ目のタブの文', 3000));
  check('claude を 2 つ同時に動かさない', calls().length === 2);
  fs.rmSync(hold);
  await waitIdle(page);
});

testCase('途中の作業の一覧と「続きから」', async page => {
  check('作業が決まる', await startWork(page, makeState({stage: 2, decision: {question: '承認しますか', choices: ['承認する'], replies: []}})));
  const done = path.join(sf, 'output', 'work-done', 'ui');
  fs.mkdirSync(done, {recursive: true});
  fs.writeFileSync(path.join(done, 'state.json'), JSON.stringify(makeState({workName: '終わった作業', stage: 8, artifacts: artifacts(9)})));
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  check('途中の作業の名前を出す', await until(async () => (await visible(page, '#works')) && (await text(page, '#works')).includes('テストの作業')));
  check('途中の作業の数を見出しに出す', (await text(page, '#works > summary')) === '途中の作業 1 件');
  check('段階と成果物の状態を出す', (await text(page, '#works .wk')).includes('段階 2'));
  check('終わった作業を折りたたみに出す', (await text(page, '#works details summary')) === '終わった作業 1 件');
  await page.locator('#works > .wk button', {hasText: '続きから'}).click();
  // 段階 2 で choices のある decision は、中央のカードの承認の画面。選択肢は下の段のボタン
  check('「続きから」で作業の状態を出す', await until(async () => (await visible(page, '#hear')) && (await text(page, '#work')) === 'テストの作業'));
  check('決めてもらうことを出す', await until(async () => (await page.locator('#hearfoot button', {hasText: '承認する'}).count()) === 1));
  fs.rmSync(sessionPath);
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  await page.locator('#works > .wk button', {hasText: '続きから'}).click();
  check('session.json がない作業では続けられないことを出す', await until(async () => (await messages(page)).includes('前の会話を続けられないので')));
  check('session.json がない作業では決めてもらうことを出さない', (await page.locator('#hearfoot button', {hasText: '承認する'}).count()) === 0);
});

testCase('書き直しの途中の state.json と、claude がない環境', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  await answerBox(page, 2).fill('書いている途中の答え');
  fs.writeFileSync(statePath, '');
  await sleep(2500);
  check('state.json が空でも質問の一覧と書いた答えが残る', (await visible(page, '#qform')) && (await answerBox(page, 2).inputValue()) === '書いている途中の答え');
  fs.writeFileSync(statePath, '{"workName":');
  await sleep(2500);
  check('state.json が読めなくても質問の一覧が残る', await visible(page, '#qform'));
  await stopServer();
  fs.writeFileSync(noVersion, '');
  await startServer();
  check('claude がないとヘッダーと直し方に出す', await until(async () => (await text(page, '#conn')) === 'claude のコマンドがありません' && (await visible(page, '#banner'))));
});

const init = {type: 'system', subtype: 'init', session_id: 'x'};
const toolUse = (name, id, input = {}) => ({type: 'tool_use', name, id, input});
const assistant = (...content) => ({type: 'assistant', message: {content}});
const fileExists = f => fs.existsSync(path.join(workPath, f));
const putFile = (f, body) => { fs.mkdirSync(path.dirname(path.join(workPath, f)), {recursive: true}); fs.writeFileSync(path.join(workPath, f), body); };
const writeState = s => fs.writeFileSync(statePath, typeof s === 'string' ? s : JSON.stringify(s));

testCase('段階 1 から 8 の帯と文書', async page => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  const artifactNames = artifacts(1).map(a => a.name);
  let allOk = true;
  for (let s = 1; s <= 8; s++) {
    const doc = `${artifactNames[s - 1]}.md`;
    putFile(doc, `# 段階 ${s} の文書\n\n- 箇条書き\n`);
    // 段階 1 は前の形(右の欄の文書)。段階 2 から 8 は中央のカードの待つの画面で、状態の語は「作っています」(段階 4 は「書いています」)、文書は開いたタブの中
    const later = s >= 2;
    writeState(makeState({stage: s, documentPath: doc, panels: later ? [{kind: '文書', name: artifactNames[s - 1], path: doc, key: null, open: true, isNew: false}] : null}));
    const docSel = later ? '#hearbody .lpane.doc' : '#doc';
    const good = await until(async () => (await page.locator('#stages .pill.done').count()) === s - 1 && (await text(page, '#stages .pill.now .num')) === String(s) && (await text(page, '#stages .pill.now')).includes(later ? (s === 4 ? '書いています' : '作っています') : '下書き') && (await text(page, `${docSel} h1`)) === `段階 ${s} の文書` && (await page.locator(`${docSel} li`).count()) === 1, 5000);
    if (!good) { allOk = false; console.log(`段階 ${s} の表示が違う: ${await text(page, '#stages')}`); }
  }
  check('段階ごとに、済んだ段階の数、いまの段階の番号、状態の文、文書の見出しと箇条書きを出す', allOk);
  const blue = await page.locator('#stages .pill.now').evaluate(e => getComputedStyle(e).backgroundColor);
  const other = await page.locator('#stages .pill.done').first().evaluate(e => getComputedStyle(e).backgroundColor);
  check('いまの段階を、済んだ段階と違う色で塗る', blue !== other, `${blue} / ${other}`);
  // 全段階が済んだ状態は、screen「スキルができた」と install を持つ state.json(画面 8-8)
  const allDone = makeState({stage: 8, screen: 'スキルができた', currentSkill: {name: 'a-skill', order: 1, total: 1, done: 1}, install: {folder: 'skills/a-skill/', contents: 'SKILL.md', tests: '合格', run: '2 件', left: null, commands: [], next: null}});
  allDone.artifacts = allDone.artifacts.map(a => ({...a, status: '済み'}));
  writeState(allDone);
  check('全段階が済むと 8 段階すべてにチェックの記号を付ける', await until(async () => (await page.locator('#stages .pill .num', {hasText: '✓'}).count()) === 8, 5000));
  // 8-8 の最後のスキルのとき、文章を整える誘いの行を出す(画面遷移設計書の 8-8。2026-11-12)
  check('最後のスキルのときは、文章を整える誘いの行を出す', await until(async () => (await hearBody(page)).includes('「文章を整えて」と送ってください'), 5000));
  // 段階 5 の間に段階 6 のテスト計画書を作っているとき、帯の段階 6 の下に「作っている」を出す(画面遷移設計書の章 4.1 の段階の帯。2026-11-12)
  const making = makeState({stage: 5, screen: null, currentSkill: {name: 'a-skill', order: 1, total: 1, done: 0}});
  making.artifacts = making.artifacts.map(a => ({...a, status: a.stage < 5 ? '済み' : a.stage === 5 || a.stage === 6 ? '下書き' : '未着手'}));
  writeState(making);
  check('段階 5 の間に段階 6 を作っているときは、帯の段階 6 の下に「作っている」を出す', await until(async () => (await page.locator('#stages .pill').nth(5).locator('.status').innerText().catch(() => '')) === '作っている', 5000));
});

// 段階 2 から 8 の見本の state.json(ui/example/ui/stages/)
const stageSample = (name, over = {}) => ({...JSON.parse(fs.readFileSync(path.join(uiDir, 'example', 'ui', 'stages', name + '.json'), 'utf8')), ...over});

testCase('段階 2 の成果物の承認の画面', async page => {
  const files = {[`${work}/分割設計書.md`]: '# 分割設計書\n\n| 列 |\n|---|\n| 値 |\n', [`${work}/要件定義書.md`]: '# 要件定義書\n'};
  check('作業が決まる', await startWork(page, stageSample('2'), {files}));
  check('見出しは、段階のスキルの質問の文', await waitHear(page, 'この分割設計書で、次の内部設計(designing-skill-phases)へ進んでよいですか？'));
  check('見出しの上の 1 行に段階の番号と段階の名前を出す', (await text(page, '#hearbody .lover')).includes('段階 2') && (await text(page, '#hearbody .lover')).includes('分割設計書'), await text(page, '#hearbody .lover'));
  const main = page.locator('#hearfoot button.pri');
  check('下の段の主なボタンは「承認する」で、ラベル「推奨」を持つ', (await main.count()) === 1 && (await main.innerText()).includes('承認する') && (await main.locator('.lrec').innerText()) === '推奨', await main.innerText().catch(() => ''));
  // デザインの 2-2b: 下の段は 1 段(左から「やめる」、書き足す入力欄、「会話の記録」、右に主なボタン)。「あとで続ける」は出さない
  const footOrder = await page.evaluate(() => [...document.querySelectorAll('#hearfoot > *')].map(e => e.id || e.className.split(' ')[0]));
  check('下の段は 1 段で、左から「やめる」、書き足す入力欄、「会話の記録」、右に主なボタンの順', footOrder.join(',') === 'pleave,form,recordopen,lsp,lsay,btn,btn', footOrder.join(','));
  check('下の段に「あとで続ける」を出さない', (await hearButton(page, 'あとで続ける').count()) === 0 && (await visible(page, '#input')) && !(await visible(page, '#zcf')));
  check('段階 2 の承認の画面は、図のタブを出さない', (await page.locator('#hearbody .ltab', {hasText: '図:'}).count()) === 0 && (await page.locator('#hearbody .ltab').count()) === 2);
  check('「切り方」と「作るスキル(1 本)」の箱を出し、箱は最終出力と受け持つ作業を持つ', (await hearBody(page)).includes('切り方') && (await hearBody(page)).includes('作るスキル(1 本)') && (await page.locator('#hearbody .lskills .lbox').count()) === 1 && (await text(page, '#hearbody .lskills .lbox')).includes('最終出力') && (await page.locator('#hearbody .lhand').count()) === 0);
  const docTab = page.locator('#hearbody .ltab', {hasText: '文書: 分割設計書'});
  await docTab.click();
  check('文書のタブを押すと全文を md の形で出す', await until(async () => (await page.locator('#hearbody .lpane.doc table').count()) === 1));
  check('文書の欄は高さの上限を持たず、ページがスクロールする', (await page.locator('#hearbody .lpane.doc').evaluate(e => getComputedStyle(e).maxHeight)) === 'none' && (await page.locator('#hearscroll').evaluate(e => getComputedStyle(e).overflowY)) === 'auto');
  await docTab.click();
  check('開いているタブをもう一度押すと畳む', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0));
  // デザインの 2-2c: 2 本のときは箱を作る順に並べ、箱の間に「前の最終出力 → 次の入力」の行とラベル「名前が一致」
  writeState(stageSample('2-2本'));
  check('2 本のときは「作るスキル(2 本。作る順)」の箱 2 つと、箱の間の受け渡しの行を出す', await until(async () => (await page.locator('#hearbody .lskills .lbox').count()) === 2 && (await page.locator('#hearbody .lhand').count()) === 1));
  check('受け渡しの行は、前の最終出力と次の入力と「名前が一致」を持つ', (await text(page, '#hearbody .lhand')).includes('1 本目の最終出力「まとめた変更の差分」') && (await text(page, '#hearbody .lhand')).includes('2 本目の入力') && (await text(page, '#hearbody .lhand .ltag')) === '名前が一致', await text(page, '#hearbody .lhand'));
  check('2 本のときも図のタブを出さない', (await page.locator('#hearbody .ltab', {hasText: '図:'}).count()) === 0);
  writeState(stageSample('2'));
  await until(async () => (await page.locator('#hearbody .lskills .lbox').count()) === 1);
  await hearButton(page, 'やめる').click();
  check('「やめる」で「スキルを中止しますか？」を出す', await waitHear(page, 'スキルを中止しますか？'));
  await page.locator('#hearbody .ldlg button', {hasText: '続ける'}).click();
  check('「続ける」で確かめを閉じ、送らない', await until(async () => !(await hearBody(page)).includes('スキルを中止しますか？')) && calls().length === 1);
  planNext(stageSample('2', {workName: '承認のあとの作業'}));
  await main.click();
  check('主なボタンは選択肢の文「承認する(推奨)」を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n承認する(推奨)`, lastCall().stdin);
  await waitIdle(page);
  check('返事のあとに承認の画面に戻る', await until(async () => (await text(page, '#work')) === '承認のあとの作業' && (await hearButton(page, 'やめる').count()) === 1 && (await hearButton(page, 'やめる').isEnabled())));
  planNext(null);
  await hearButton(page, 'やめる').click();
  await page.locator('#hearbody .ldlg button', {hasText: '中止する'}).click();
  check('「中止する」で選択肢の文「やめる」を送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\nやめる`, lastCall().stdin);
});

testCase('段階 3 の成果物の承認の画面', async page => {
  // 2026-11-10 に確定したデザイン(3-1b から 3-1f)。見本 ui/example/ui/stages/3.json と、図は ui/example/ui/figures の流れ図
  const sample = stageSample('3');
  const figPath = sample.panels[0].path;
  const figSvg = fs.readFileSync(path.join(uiDir, 'example', figPath), 'utf8');
  const files = {[`${work}/構成の案.md`]: '# squashing-commits の構成の案\n\n## 11. 値の出どころ\n\n| 章 | 値 |\n|---|---|\n| 2 | git |\n', [`${work}/${figPath}`]: figSvg};
  check('作業が決まる', await startWork(page, sample, {files}));
  check('見出しは、段階のスキルの質問の文', await waitHear(page, 'この構成の案で、次の下書き(drafting-skill-with-template)へ進んでよいですか？'));
  check('見出しの上の 1 行に、段階 3、スキルの名前、作る順を出す', (await text(page, '#hearbody .lover')).includes('段階 3') && (await text(page, '#hearbody .lover')).includes('squashing-commits(1 本目 / 全 1 本)'), await text(page, '#hearbody .lover'));
  check('節「構成の案の要点(step 9-4 がユーザーに見せる 5 行)」に summaryCard の 5 行を出す', (await hearBody(page)).includes('構成の案の要点(step 9-4 がユーザーに見せる 5 行)') && (await page.locator('#hearbody .lkv dt').count()) === 5 && (await hearBody(page)).includes('AI が自分で決めた値'));
  const tabs = page.locator('#hearbody .ltab');
  check('タブは「図: 流れ図」「文書: AI が決めた 7 件」「文書: 構成の案」の 3 つで、右端にダウンロード', (await tabs.count()) === 3 && (await tabs.nth(0).innerText()).includes('図: 流れ図') && (await tabs.nth(1).innerText()).includes('文書: AI が決めた 7 件') && (await tabs.nth(2).innerText()).includes('文書: 構成の案') && (await page.locator('#hearbody .ldl').count()) === 1);
  check('図のタブは初めに開き、ラベル「新しい」を持ち、流れ図の全体を出す', await until(async () => (await tabs.nth(0).getAttribute('class')).includes('on') && (await tabs.nth(0).locator('.ltag.lnew').innerText()) === '新しい' && (await page.locator('#hearbody .lpane.fig svg').count()) === 1));
  const cardWidth = () => page.locator('#hearbody').evaluate(e => getComputedStyle(e).maxWidth);
  const figWidth = () => page.locator('#hearbody .lpane.fig svg').evaluate(e => e.getBoundingClientRect().width);
  check('図のタブを開いている間はカードが 988px に広がり、流れ図は 900px で出る', (await cardWidth()) === '988px' && Math.round(await figWidth()) === 900, `${await cardWidth()} / ${await figWidth()}`);
  check('図の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.fig').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(1).click();
  check('「文書: AI が決めた 7 件」を押すと、上の 1 文と 3 列の表(7 行)を出す', await until(async () => (await page.locator('#hearbody .lpane .ltbl th').count()) === 3 && (await page.locator('#hearbody .lpane .ltbl tr').count()) === 8));
  const ths = await page.locator('#hearbody .lpane .ltbl th').allInnerTexts();
  check('表の列は「AI が決めたこと」「決めた値」「どう決めたか」', ths.join(',') === 'AI が決めたこと,決めた値,どう決めたか', ths.join(','));
  check('表の上の 1 文は、件数と章 11 を持つ', (await text(page, '#hearbody .lpane .cap')).startsWith('要件定義書にも分割設計書にも書かれておらず、AI が自分で決めた値の 7 件。') && (await text(page, '#hearbody .lpane .cap')).includes('章 11「値の出どころ」'));
  check('文書のタブに切り替えるとカードは 640px に戻る', (await cardWidth()) === '640px', await cardWidth());
  await tabs.nth(2).click();
  check('「文書: 構成の案」を押すと md の全文を出す', await until(async () => (await text(page, '#hearbody .lpane.doc h1')) === 'squashing-commits の構成の案' && (await page.locator('#hearbody .lpane.doc table').count()) === 1));
  check('文書の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.doc').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(2).click();
  check('開いているタブをもう一度押すと畳む', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0));
  await tabs.nth(0).click();
  check('畳んだあとに図のタブを押すと、また 988px に広がる', await until(async () => (await page.locator('#hearbody .lpane.fig').count()) === 1 && (await cardWidth()) === '988px'));
  const main = page.locator('#hearfoot button.pri');
  check('下の段の主なボタンは「承認する」で、ラベル「推奨」を持ち、横の 1 文を出す', (await main.innerText()).includes('承認する') && (await main.locator('.lrec').innerText()) === '推奨' && (await text(page, '#hearfoot .lsay')) === 'AI は、構成の案を確定し、SKILL.md とリファレンス 3 本の下書きを書きます(段階 4 は承認がなく、続けて段階 5 の照合に進みます)。', await text(page, '#hearfoot .lsay'));
  await hearButton(page, 'やめる').click();
  check('「やめる」で「スキルを中止しますか？」と、中止の文を出す', await waitHear(page, 'スキルを中止しますか？') && (await hearBody(page)).includes('もう一度始めるときは、分割設計書のパスを送ります。'));
  await page.locator('#hearbody .ldlg button', {hasText: '続ける'}).click();
  check('「続ける」で確かめを閉じ、送らない', await until(async () => !(await hearBody(page)).includes('スキルを中止しますか？')) && calls().length === 1);
  // 「却下する」は label を送り、AI が screen「却下の理由」を書くと、同じ画面の状態「却下の理由を書く」になる(タブを出さず、要点の下に入力欄)
  planNext(stageSample('3', {screen: '却下の理由', decision: {question: '却下の理由を 1 文で書いてください。', choices: [], replies: []}}));
  await hearButton(page, '却下する').click();
  check('「却下する」は選択肢の文「却下する」を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n却下する`, lastCall().stdin);
  await waitIdle(page);
  check('却下の理由を書く状態は、要点の 5 行と入力欄を出し、タブを出さない', await until(async () => (await page.locator('#hearbody textarea.linp').count()) === 1 && (await page.locator('#hearbody .lkv dt').count()) === 5 && (await page.locator('#hearbody .ltab').count()) === 0 && (await hearBody(page)).includes('却下の理由を 1 文で書いてください。')));
  check('却下の理由を書く状態のカードは 640px', (await cardWidth()) === '640px', await cardWidth());
  check('下の段は「やめる」と 1 文「AI は、この理由で phase と step を切り直します。」と「理由を送る」', (await hearButton(page, 'やめる').count()) === 1 && (await text(page, '#hearfoot .lsay')) === 'AI は、この理由で phase と step を切り直します。' && (await hearButton(page, '理由を送る').count()) === 1 && (await hearButton(page, '理由を送る').isDisabled()));
  planNext(null);
  await page.locator('#hearbody textarea.linp').fill('履歴の書き換えの確認(4-1)を、まとめの結果の確認(6-3)と 1 つにしたい');
  await hearButton(page, '理由を送る').click();
  check('「理由を送る」は書いた理由を送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\n履歴の書き換えの確認(4-1)を、まとめの結果の確認(6-3)と 1 つにしたい`, lastCall().stdin);
});

testCase('段階 6 の成果物の承認の画面', async page => {
  // 2026-11-10 に確定したテスト計画書の形(6-1 テストケースの承認)。見本 ui/example/ui/stages/6.json と、文書は ui/example/tests/テスト計画書.md(章 1 から 9)。画面は md の章を HTML にして出すだけで、表や数を組み立てない
  const sample = stageSample('6');
  const planMd = fs.readFileSync(path.join(uiDir, 'example', 'tests', 'テスト計画書.md'), 'utf8');
  const files = {[`${work}/tests/テスト計画書.md`]: planMd};
  check('作業が決まる', await startWork(page, sample, {files}));
  check('見出しは、段階のスキルの質問の文(decision.question)', await waitHear(page, 'テストケース 31 件を作りました。この計画で、テストのシナリオを決めてよいですか？'));
  check('見出しの上の 1 行に、段階 6、スキルの名前、作る順を出す', (await text(page, '#hearbody .lover')).includes('段階 6') && (await text(page, '#hearbody .lover')).includes('squashing-commits(1 本目 / 全 1 本)'), await text(page, '#hearbody .lover'));
  check('節「要点」に summaryCard の 3 行(行の名前は AI が書く)を出す', (await hearBody(page)).includes('要点') && (await page.locator('#hearbody .lkv dt').allInnerTexts()).join(',') === '1. テスト観点,2. テストケース,3. 網羅の証明' && (await hearBody(page)).includes('対象 61 のうち、ケースあり 38'), (await page.locator('#hearbody .lkv dt').allInnerTexts()).join(','));
  const tabs = page.locator('#hearbody .ltab');
  check('タブは「文書: 1. テスト観点」「文書: 2. テストケース(31 件)」「文書: 3. 網羅の証明」「文書: テスト計画書」の 4 つで、右端にダウンロード', (await tabs.count()) === 4 && (await tabs.nth(0).innerText()).includes('文書: 1. テスト観点') && (await tabs.nth(1).innerText()).includes('文書: 2. テストケース(31 件)') && (await tabs.nth(2).innerText()).includes('文書: 3. 網羅の証明') && (await tabs.nth(3).innerText()).includes('文書: テスト計画書') && (await page.locator('#hearbody .ldl').count()) === 1, await tabs.allInnerTexts().then(a => a.join('|')));
  check('図のタブはない', (await page.locator('#hearbody .ltab', {hasText: '図:'}).count()) === 0);
  const cardWidth = () => page.locator('#hearbody').evaluate(e => getComputedStyle(e).maxWidth);
  check('「1. テスト観点」のタブは初めに開き、ラベル「新しい」を持ち、章「テスト観点の一覧」と章「使わなかった技法と理由」の 2 つを md のまま出す', await until(async () => (await tabs.nth(0).getAttribute('class')).includes('on') && (await tabs.nth(0).locator('.ltag.lnew').innerText()) === '新しい' && (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === 'テスト観点の一覧,使わなかった技法と理由' && (await page.locator('#hearbody .lpane.doc table').count()) === 2), (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(','));
  check('テスト観点の表は md の 7 列(観点の番号から当てない理由まで)で、V-20 の行を持つ', (await page.locator('#hearbody .lpane.doc table').nth(0).locator('th').allInnerTexts()).join(',') === '観点の番号,分類,何を疑うか,見る対象,使う技法,作ったケースの番号,この観点を当てない理由' && (await page.locator('#hearbody .lpane.doc table').nth(0).locator('tr').count()) === 21, (await page.locator('#hearbody .lpane.doc table').nth(0).locator('th').allInnerTexts()).join(','));
  check('ほかの章(対象と環境、テストケースの一覧)は、このタブに出さない', !(await text(page, '#hearbody .lpane.doc')).includes('照合のスクリプトの置き場') && !(await text(page, '#hearbody .lpane.doc')).includes('期待の根拠'));
  check('どのタブを開いている間もカードは 988px(表の列が多いため)', (await cardWidth()) === '988px', await cardWidth());
  check('文書の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.doc').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(1).click();
  const boxes = page.locator('#hearbody .lpane.doc .lbox');
  check('「2. テストケース(31 件)」を押すと、章「テストケースの一覧」の表を 1 件 1 塊で出す(31 塊)', await until(async () => (await boxes.count()) === 31 && (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === 'テストケースの一覧'), String(await boxes.count()));
  check('塊の 1 行目は、番号、観点の番号、確かめ方、種別の 4 つ', (await boxes.nth(4).locator('.lt span').allInnerTexts()).join(',') === '5,V-2,スキルを流して確かめる,正常', (await boxes.nth(4).locator('.lt span').allInnerTexts()).join(','));
  check('塊の下は、残りの 9 列を md の表の列の名前と順のまま出す', (await boxes.nth(4).locator('dt').allInnerTexts()).join(',') === '対象の番号,前提の状況,依頼の文,回答,実行の回数,期待する結果,期待の根拠,判定,phase' && (await boxes.nth(4).locator('dd').nth(2).innerText()) === '直近の 3 件のコミットをまとめて', (await boxes.nth(4).locator('dt').allInnerTexts()).join(','));
  check('カードは 988px のまま', (await cardWidth()) === '988px', await cardWidth());
  await tabs.nth(2).click();
  check('「3. 網羅の証明」を押すと、1 行の結論と表 1 と表 2 を md のまま出す', await until(async () => (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === '網羅の証明' && (await page.locator('#hearbody .lpane.doc table').count()) === 2 && (await text(page, '#hearbody .lpane.doc p')) === '対象 61 のうち、ケースあり 38、実行環境で作れない 23、未対応 0'), await text(page, '#hearbody .lpane.doc').then(t => t.slice(0, 80)));
  check('表 1 は分類 7 行、表 2 は 12 行', (await page.locator('#hearbody .lpane.doc table').nth(0).locator('tr').count()) === 8 && (await page.locator('#hearbody .lpane.doc table').nth(1).locator('tr').count()) === 13);
  await tabs.nth(3).click();
  check('「文書: テスト計画書」を押すと md の全文を出し、カードは 988px のまま', await until(async () => (await text(page, '#hearbody .lpane.doc h1')) === 'テスト計画書: squashing-commits' && (await page.locator('#hearbody .lpane.doc h2').count()) === 9) && (await cardWidth()) === '988px', await cardWidth());
  await tabs.nth(3).click();
  check('開いているタブをもう一度押すと畳み、カードは 640px に戻る', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0 && (await cardWidth()) === '640px'), await cardWidth());
  const main = page.locator('#hearfoot button.pri');
  check('下の段の主なボタンは「承認する」で、ラベル「推奨」を持ち、横の 1 文は decision の choices の result', (await main.innerText()).includes('承認する') && (await main.locator('.lrec').innerText()) === '推奨' && (await text(page, '#hearfoot .lsay')) === 'AI は、テスト計画書を skills/squashing-commits/tests/ に確定し、続けてテストのシナリオを決めます(段階 7)。', await text(page, '#hearfoot .lsay'));
  await hearButton(page, 'やめる').click();
  check('「やめる」で「スキルを中止しますか？」と、中止の文を出す', await waitHear(page, 'スキルを中止しますか？') && (await hearBody(page)).includes('もう一度始めるときは、スキルのフォルダのパスと「テストを作って」を送ります。'));
  await page.locator('#hearbody .ldlg button', {hasText: '続ける'}).click();
  check('「続ける」で確かめを閉じ、送らない', await until(async () => !(await hearBody(page)).includes('スキルを中止しますか？')) && calls().length === 1);
  planNext(stageSample('6', {screen: '却下の理由', decision: {question: '却下の理由を 1 文で書いてください。', choices: [], replies: []}}));
  await hearButton(page, '却下する').click();
  check('「却下する」は選択肢の文「却下する」を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n却下する`, lastCall().stdin);
  await waitIdle(page);
  check('却下の理由を書く状態は、要点の 3 行と入力欄を出し、タブを出さない', await until(async () => (await page.locator('#hearbody textarea.linp').count()) === 1 && (await page.locator('#hearbody .lkv dt').count()) === 3 && (await page.locator('#hearbody .ltab').count()) === 0 && (await hearBody(page)).includes('却下の理由を 1 文で書いてください。')));
  check('却下の理由を書く状態のカードは 640px', (await cardWidth()) === '640px', await cardWidth());
  check('下の段は「やめる」と 1 文「AI は、この理由でテストケースを作り直します。」と「理由を送る」', (await hearButton(page, 'やめる').count()) === 1 && (await text(page, '#hearfoot .lsay')) === 'AI は、この理由でテストケースを作り直します。' && (await hearButton(page, '理由を送る').count()) === 1 && (await hearButton(page, '理由を送る').isDisabled()));
  planNext(null);
  await page.locator('#hearbody textarea.linp').fill('V-19 並行と時間の観点にも、ケースを 1 件作りたい');
  await hearButton(page, '理由を送る').click();
  check('「理由を送る」は書いた理由を送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\nV-19 並行と時間の観点にも、ケースを 1 件作りたい`, lastCall().stdin);
});

testCase('段階 7 の成果物の承認の画面', async page => {
  // 2026-11-10 に確定したデザイン(7-1v から 7-1f)。見本 ui/example/ui/stages/7.json と、図は ui/example/ui/figures のシナリオテストが受け持つテストケースの図
  const sample = stageSample('7');
  const figPath = sample.panels[0].path;
  const figSvg = fs.readFileSync(path.join(uiDir, 'example', figPath), 'utf8');
  const files = {[`${work}/tests/テスト計画書.md`]: '# テスト計画書: squashing-commits\n\n## 対象\n\n- 版: 7d9c4ed6c307\n\n## テストケース\n\n| 番号 | 確かめ方 |\n|---|---|\n| 1 | スクリプトで確かめる |\n', [`${work}/${figPath}`]: figSvg};
  check('作業が決まる', await startWork(page, sample, {files}));
  check('見出しは、段階のスキルの質問の文', await waitHear(page, '実施する範囲を「1 回の実行で終わるすべて」にして、シナリオテストの表を書いてよいですか？'));
  check('見出しの上の 1 行に、段階 7、スキルの名前、作る順を出す', (await text(page, '#hearbody .lover')).includes('段階 7') && (await text(page, '#hearbody .lover')).includes('squashing-commits(1 本目 / 全 1 本)'), await text(page, '#hearbody .lover'));
  const rangeRows = page.locator('#hearbody .lcard > .ltbl tr');
  check('節「範囲ごとの件数」に、列「実施する範囲」「シナリオ数」「テストケース」「実行の回数の和」の表(3 行)を出す', (await hearBody(page)).includes('範囲ごとの件数') && (await page.locator('#hearbody .lcard > .ltbl th').allInnerTexts()).join(',') === '実施する範囲,シナリオ数,テストケース,実行の回数の和' && (await rangeRows.count()) === 4, (await page.locator('#hearbody .lcard > .ltbl th').allInnerTexts()).join(','));
  check('AI が決めた範囲の行は、ラベル「AI が決めた範囲(既定の値)」と、テストケース「22 / 23」を持つ', (await rangeRows.nth(1).locator('.ltag.lreco').innerText()) === 'AI が決めた範囲(既定の値)' && (await rangeRows.nth(1).locator('td').nth(2).innerText()) === '22 / 23' && (await rangeRows.nth(2).locator('td').nth(2).innerText()) === '23 / 23' && (await rangeRows.nth(3).locator('td').nth(2).innerText()) === '8 / 23', await rangeRows.nth(1).innerText());
  check('表の下に summaryCard の 2 行(行の名前は AI が書く。見本は流さないケース、スクリプトで確かめるテスト)を出す', (await page.locator('#hearbody .lkv dt').allInnerTexts()).join(',') === '流さないケース,スクリプトで確かめるテスト' && (await hearBody(page)).includes('TC-27(S12。'));
  const tabs = page.locator('#hearbody .ltab');
  check('タブは「図: 受け持つテストケース」「文書: シナリオの一覧」「文書: テスト計画書」の 3 つで、右端にダウンロード', (await tabs.count()) === 3 && (await tabs.nth(0).innerText()).includes('図: 受け持つテストケース') && (await tabs.nth(1).innerText()).includes('文書: シナリオの一覧') && (await tabs.nth(2).innerText()).includes('文書: テスト計画書') && (await page.locator('#hearbody .ldl').count()) === 1);
  check('図のタブは初めに開き、ラベル「新しい」を持ち、図の全体を出す', await until(async () => (await tabs.nth(0).getAttribute('class')).includes('on') && (await tabs.nth(0).locator('.ltag.lnew').innerText()) === '新しい' && (await page.locator('#hearbody .lpane.fig svg').count()) === 1));
  const cardWidth = () => page.locator('#hearbody').evaluate(e => getComputedStyle(e).maxWidth);
  const figWidth = () => page.locator('#hearbody .lpane.fig svg').evaluate(e => e.getBoundingClientRect().width);
  check('図のタブを開いている間はカードが 988px に広がり、図は 900px で出る', (await cardWidth()) === '988px' && Math.round(await figWidth()) === 900, `${await cardWidth()} / ${await figWidth()}`);
  check('図の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.fig').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(1).click();
  check('「文書: シナリオの一覧」を押すと、上の 1 文と 11 列の表(12 行)を出す', await until(async () => (await page.locator('#hearbody .lpane .ltbl th').count()) === 11 && (await page.locator('#hearbody .lpane .ltbl tr').count()) === 13));
  const ths = await page.locator('#hearbody .lpane .ltbl th').allInnerTexts();
  check('表の列は、テスト計画書の章「シナリオテストの表」の 11 列(シナリオの番号から実行の回数まで)', ths.join(',') === 'シナリオの番号,流す順,流すか,流さない理由,含むケース,通す phase,終わり方,前提の状況,依頼の文,回答,実行の回数', ths.join(','));
  const s12 = page.locator('#hearbody .lpane .ltbl tr').nth(12).locator('td');
  check('S12 の行は、流さない、流さない理由、含むケース 27、実行の回数 2 を出す', (await s12.nth(0).innerText()) === 'S12' && (await s12.nth(2).innerText()) === '流さない' && (await s12.nth(3).innerText()).includes('入っていない') && (await s12.nth(4).innerText()) === '27' && (await s12.nth(10).innerText()) === '2', await s12.allInnerTexts().then(a => a.join('|')));
  check('表の上の 1 文は、本数を持つ', (await text(page, '#hearbody .lpane .cap')) === 'テスト計画書の章「シナリオテストの表」(この承認で足す章)の全 12 行。', await text(page, '#hearbody .lpane .cap'));
  check('文書: シナリオの一覧でもカードは 988px のまま(表の列が多いため)', (await cardWidth()) === '988px', await cardWidth());
  await tabs.nth(2).click();
  check('「文書: テスト計画書」を押すと md の全文を出し、カードは 988px のまま', await until(async () => (await text(page, '#hearbody .lpane.doc h1')) === 'テスト計画書: squashing-commits' && (await page.locator('#hearbody .lpane.doc table').count()) === 1) && (await cardWidth()) === '988px', await cardWidth());
  check('文書の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.doc').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(2).click();
  check('開いているタブをもう一度押すと畳み、カードは 640px に戻る', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0 && (await cardWidth()) === '640px'), await cardWidth());
  const main = page.locator('#hearfoot button.pri');
  check('下の段の主なボタンは「承認する」で、ラベル「推奨」を持ち、横の 1 文を出す', (await main.innerText()).includes('承認する') && (await main.locator('.lrec').innerText()) === '推奨' && (await text(page, '#hearfoot .lsay')) === 'AI は、章「シナリオテストの表」をテスト計画書に足し、続けてテストを流します(段階 8)。', await text(page, '#hearfoot .lsay'));
  await hearButton(page, 'やめる').click();
  check('「やめる」で「スキルを中止しますか？」と、中止の文を出す', await waitHear(page, 'スキルを中止しますか？') && (await hearBody(page)).includes('もう一度始めるときは、テスト計画書のパスと実施する範囲を送ります。'));
  await page.locator('#hearbody .ldlg button', {hasText: '続ける'}).click();
  check('「続ける」で確かめを閉じ、送らない', await until(async () => !(await hearBody(page)).includes('スキルを中止しますか？')) && calls().length === 1);
  planNext(stageSample('7-reason'));
  await hearButton(page, '却下する').click();
  check('「却下する」は選択肢の文「却下する」を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n却下する`, lastCall().stdin);
  await waitIdle(page);
  check('却下の理由を書く状態は、範囲ごとの件数の表と 2 行と入力欄を出し、タブを出さない', await until(async () => (await page.locator('#hearbody textarea.linp').count()) === 1 && (await page.locator('#hearbody .lcard > .ltbl tr').count()) === 4 && (await page.locator('#hearbody .lkv dt').count()) === 2 && (await page.locator('#hearbody .ltab').count()) === 0 && (await hearBody(page)).includes('却下の理由を 1 文で書いてください。')));
  check('却下の理由を書く状態のカードは 640px', (await cardWidth()) === '640px', await cardWidth());
  check('下の段は「やめる」と 1 文「AI は、この理由で範囲を決め直します。」と「理由を送る」', (await hearButton(page, 'やめる').count()) === 1 && (await text(page, '#hearfoot .lsay')) === 'AI は、この理由で範囲を決め直します。' && (await hearButton(page, '理由を送る').count()) === 1 && (await hearButton(page, '理由を送る').isDisabled()));
  planNext(null);
  await page.locator('#hearbody textarea.linp').fill('TC-27 も入れて、全件を流したい');
  await hearButton(page, '理由を送る').click();
  check('「理由を送る」は書いた理由を送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\nTC-27 も入れて、全件を流したい`, lastCall().stdin);
});

testCase('段階 8 のテストの結果の画面', async page => {
  // 2026-11-10 に確定した 8 章の仕様(8-2 テストの結果)。見本 ui/example/ui/stages/8.json と、文書は ui/example/tests/判定の記録.md(判定の記録の雛形の章と列)。画面は md の章を HTML にして出すだけで、ケースのカードを result.cases から組まない。図は、見本 ui/example/ui/figures/8-1-判定の結果の図.svg(判定の結果の図の雛形で描いたもの)
  const sample = stageSample('8');
  const figPath = sample.panels[0].path;
  const figSvg = fs.readFileSync(path.join(uiDir, 'example', figPath), 'utf8');
  const recordMd = fs.readFileSync(path.join(uiDir, 'example', 'tests', '判定の記録.md'), 'utf8');
  const files = {[`${work}/tests/判定の記録.md`]: recordMd, [`${work}/${figPath}`]: figSvg};
  check('作業が決まる', await startWork(page, sample, {files}));
  check('見出しは、不合格と判定できないの数を持つ結果の文', await waitHear(page, 'squashing-commits のシナリオテストを実行しました。不合格 2 件、判定できない 1 件です。'));
  check('見出しの上の 1 行に、段階 8、スキルの名前、作る順を出す', (await text(page, '#hearbody .lover')).includes('段階 8') && (await text(page, '#hearbody .lover')).includes('squashing-commits(1 本目 / 全 1 本)'), await text(page, '#hearbody .lover'));
  check('見出しの下の行は、止まっていることと判定の記録のパス', (await page.locator('#hearbody .lcard > .lkv dt').allInnerTexts()).join(',') === '止まっていること,判定の記録' && (await page.locator('#hearbody .lcard > .lkv dd').nth(1).innerText()) === 'tests/判定の記録.md', (await page.locator('#hearbody .lcard > .lkv dt').allInnerTexts()).join(','));
  const tiles = page.locator('#hearbody .lnum');
  check('節「判定の記録の要点」の箱 5 つは、スクリプト 合格 6、シナリオ 合格 8、不合格 2、判定できない 1、未実施 1', (await hearBody(page)).includes('判定の記録の要点') && (await tiles.locator('.l').allInnerTexts()).join(',') === 'スクリプト 合格,シナリオ 合格,不合格,判定できない,未実施' && (await tiles.locator('.v').allInnerTexts()).join(',') === '6,8,2,1,1', (await tiles.locator('.l').allInnerTexts()).join(','));
  check('本文に、不合格と判定できないケースのカードを出さない(判定の記録の md のタブで出す)', (await page.locator('#hearbody .lcard > .lbox').count()) === 0 && !(await text(page, '#hearbody .lcard')).includes('S-06 · 1 回目'));
  const tabs = page.locator('#hearbody .ltab');
  check('タブは「図: 判定の結果の図」「文書: 1. ケースごとの判定」「文書: 2. 実行時の網羅の証明」「文書: 3. 未実施の実行」「文書: 判定の記録(全文)」の 5 つで、右端にダウンロード', (await tabs.count()) === 5 && (await tabs.allInnerTexts()).map(t => t.replace(/新しい$/, '').trim()).join('|') === '図: 判定の結果の図|文書: 1. ケースごとの判定|文書: 2. 実行時の網羅の証明|文書: 3. 未実施の実行|文書: 判定の記録(全文)' && (await page.locator('#hearbody .ldl').count()) === 1, await tabs.allInnerTexts().then(a => a.join('|')));
  check('図のタブは初めに開き、ラベル「新しい」を持ち、図の全体を出す', await until(async () => (await tabs.nth(0).getAttribute('class')).includes('on') && (await tabs.nth(0).locator('.ltag.lnew').innerText()) === '新しい' && (await page.locator('#hearbody .lpane.fig svg').count()) === 1));
  const cardWidth = () => page.locator('#hearbody').evaluate(e => getComputedStyle(e).maxWidth);
  check('図のタブを開いている間はカードが 988px', (await cardWidth()) === '988px', await cardWidth());
  await tabs.nth(1).click();
  const boxes = page.locator('#hearbody .lpane.doc .lbox');
  check('「1. ケースごとの判定」を押すと、章「ケースごとの判定」の表を 1 件 1 塊で出す(12 塊)、ほかの章を出さない', await until(async () => (await boxes.count()) === 12 && (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === 'ケースごとの判定'), String(await boxes.count()));
  check('塊の 1 行目は、ケースの番号、判定の仕方、実施したか、合否の 4 つ', (await boxes.nth(6).locator('.lt span').allInnerTexts()).join(',') === 'TC-07,AI が読んで判定する,実施した,不合格' && (await boxes.nth(0).locator('.lt span').allInnerTexts()).join(',') === 'TC-01,値を比べる,実施した,合格', (await boxes.nth(6).locator('.lt span').allInnerTexts()).join(','));
  check('塊の下は、残りの列(実行ごとの合否、1 回目、2 回目、根拠か未実施の理由)を md の表の列の名前と順のまま出す', (await boxes.nth(6).locator('dt').allInnerTexts()).join(',') === '実行ごとの合否,1 回目,2 回目,根拠か未実施の理由' && (await boxes.nth(6).locator('dd').nth(0).innerText()) === 'S-06-1: 不合格', (await boxes.nth(6).locator('dt').allInnerTexts()).join(','));
  const edge = i => boxes.nth(i).evaluate(e => [getComputedStyle(e).borderLeftColor, getComputedStyle(e).borderLeftWidth].join(' '));
  check('合否が不合格の塊は赤、判定できないは黄、未実施は灰の左の縁(4px)を持ち、合格の塊は持たない', (await edge(6)) === 'rgb(207, 34, 46) 4px' && (await edge(7)) === 'rgb(207, 34, 46) 4px' && (await edge(10)) === 'rgb(201, 151, 0) 4px' && (await edge(11)) === 'rgb(140, 149, 159) 4px' && (await edge(0)) === 'rgb(230, 233, 238) 1px', `${await edge(6)} / ${await edge(10)} / ${await edge(11)} / ${await edge(0)}`);
  check('文書のタブでもカードは 988px', (await cardWidth()) === '988px', await cardWidth());
  await tabs.nth(2).click();
  check('「2. 実行時の網羅の証明」を押すと、1 行と表を md のまま出す', await until(async () => (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === '実行時の網羅の証明' && (await page.locator('#hearbody .lpane.doc table').count()) === 1 && (await text(page, '#hearbody .lpane.doc li')) === '合格のケースを持つテストの対象: 9 / 12'), await text(page, '#hearbody .lpane.doc').then(t => t.slice(0, 80)));
  await tabs.nth(3).click();
  check('「3. 未実施の実行」を押すと、表を md のまま出す', await until(async () => (await page.locator('#hearbody .lpane.doc h2').allInnerTexts()).join(',') === '未実施の実行' && (await page.locator('#hearbody .lpane.doc table th').allInnerTexts()).join(',') === 'シナリオの番号,何回目か,理由'));
  await tabs.nth(4).click();
  check('「文書: 判定の記録(全文)」を押すと md の全文(章 5 つ)を出す', await until(async () => (await text(page, '#hearbody .lpane.doc h1')) === '判定の記録: squashing-commits' && (await page.locator('#hearbody .lpane.doc h2').count()) === 5));
  check('文書の欄は高さの上限を持たない', (await page.locator('#hearbody .lpane.doc').evaluate(e => getComputedStyle(e).maxHeight)) === 'none');
  await tabs.nth(4).click();
  check('開いているタブをもう一度押すと畳み、カードは 640px に戻る', await until(async () => (await page.locator('#hearbody .lpane').count()) === 0 && (await cardWidth()) === '640px'), await cardWidth());
  check('知らせの行は result.next で、下の段の 1 文は「AI は、続けて原因を仕分けます。」', (await hearBody(page)).includes('AI は、続けて不合格と判定できないケースの原因を仕分けます(8-3)。') && (await text(page, '#hearfoot .lsay')) === 'AI は、続けて原因を仕分けます。', await text(page, '#hearfoot .lsay'));
  await tabs.nth(1).click();
  await until(async () => (await boxes.count()) === 12);
  const shown = (await hearBody(page)) + (await text(page, '#hearfoot'));
  const left = ['静的', '仕様の行', '前提の状態', '着眼点'].filter(w => shown.includes(w));
  check('画面に出る文に、言い直しが要る語(静的、仕様の行、前提の状態、着眼点)がない', left.length === 0, left.join('、'));
  // 8-4 テスト計画書の直しの承認: planFix の列の名前は fixing-test-plan の修正の結果の語
  writeState(stageSample('8-4'));
  check('8-4 の塊の下の列は「前の期待する結果」「後の期待する結果」「期待の根拠」', await until(async () => (await page.locator('#hearbody .lcard > .lbox').first().locator('dt').allInnerTexts()).join(',') === '前の期待する結果,後の期待する結果,期待の根拠', 6000) && (await hearBody(page)).includes('ケースごとの直し(前の期待する結果と後の期待する結果)'), (await page.locator('#hearbody .lcard > .lbox').first().locator('dt').allInnerTexts().catch(() => [])).join(','));
});

testCase('スキルが 2 本のときの表示と下のフォルダのファイル', async page => {
  check('作業が決まる', await startWork(page, makeState({currentSkill: {name: 'a-skill', order: 1, total: 1}, documentPath: 'skills/a-skill/SKILL.md', downloads: ['skills/a-skill/SKILL.md', '要件定義書.md']}), {files: {[`${work}/skills/a-skill/SKILL.md`]: '# スキルの本文\n', [`${work}/要件定義書.md`]: '要件'}}));
  check('スキルが 1 本のときは作る順を出さない', await until(async () => (await text(page, '#work')) === 'テストの作業') && (await text(page, '#skill').catch(() => '')) === '');
  check('下のフォルダの文書を出す', await until(async () => (await text(page, '#doc')).includes('スキルの本文')));
  check('下のフォルダの文書のパスを出す', (await text(page, '#docpath')) === `${work}/skills/a-skill/SKILL.md`, await text(page, '#docpath'));
  await page.click('#dl');
  check('ダウンロードの一覧に 2 件を出す', (await page.locator('#dlmenu a').count()) === 2);
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#dlmenu a').first().click()]);
  check('下のフォルダのファイルをダウンロードする', download.suggestedFilename() === 'SKILL.md');
  writeState(makeState({currentSkill: {name: 'b-skill', order: 2, total: 2}}));
  check('スキルが 2 本のときは作る順と名前を出す', await until(async () => (await text(page, '#skill')) === '2 / 2 b-skill'));
  writeState(makeState({workName: '変えた名前'}));
  check('作業の名前を変えても同じ作業のフォルダのまま表示を変える', await until(async () => (await text(page, '#work')) === '変えた名前') && (await page.evaluate(() => seenWorkDir)) === work);
});

testCase('途中の作業の一覧の 1 行', async page => {
  const put = (name, st) => { const d = path.join(sf, 'output', name, 'ui'); fs.mkdirSync(d, {recursive: true}); fs.writeFileSync(path.join(d, 'state.json'), JSON.stringify(st)); return path.join(d, 'state.json'); };
  const yesterday = new Date(Date.now() - 2 * 86400000);
  const f = put('w-decide', makeState({workName: '承認の作業', stage: 2, decision: {question: 'q', choices: ['a'], replies: []}}));
  fs.utimesSync(f, yesterday, yesterday);
  put('w-question', makeState({workName: '質問の作業', questions: threeQuestions({1: '必須'})}));
  put('w-working', makeState({workName: '作業中の作業', stage: 4}));
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  check('3 行を出す', await until(async () => (await page.locator('#works > .wk').count()) === 3));
  const row = name => page.locator('#works > .wk', {hasText: name}).innerText();
  const decide = await row('承認の作業');
  check('段階の番号と成果物の名前と状態を出す', decide.includes('段階 2') && decide.includes('分割設計書') && decide.includes('下書き'), decide);
  check('作業のフォルダのパスを出す', decide.includes('output/w-decide/'), decide);
  check('別の日の最後の保存は月日と時刻で出す', /最後の保存 \d\d-\d\d \d\d:\d\d/.test(decide), decide);
  check('同じ日の最後の保存は時刻だけで出す', /最後の保存 \d\d:\d\d ・/.test(await row('作業中の作業')));
  check('決めてもらうことがある作業は「承認待ち」を出す', decide.includes('承認待ち'), decide);
  check('答えのない問いがある作業は「質問中(N 問のうち A 問に回答)」を出す', (await row('質問の作業')).includes('質問中(3 問のうち 1 問に回答)'));
  check('それ以外の作業は「作業中」を出す', (await row('作業中の作業')).includes('作業中 ') || (await row('作業中の作業')).endsWith('作業中'));
});

testCase('実行中のスキルの表示', async page => {
  fs.writeFileSync(hold + '-after', '');
  planNext(makeState(), {holdAfter: true, reply: '返事', lines: [init, assistant(toolUse('Skill', 'a', {skill: 'defining-skill-requirements'}), toolUse('Skill', 'b', {skill: 'updating-skill-factory-ui-state'}), toolUse('Agent', 'c'))]});
  await page.fill('#input', '依頼');
  await page.press('#input', 'Enter');
  check('サブエージェントの数を添える', await until(async () => (await visible(page, '#running')) && (await text(page, '#running')).includes('サブエージェント 1 体')));
  check('段階のスキルの名前を出す', (await text(page, '#running')).includes('defining-skill-requirements'));
  check('書いている間は回る印を出す', (await page.locator('#running .spin').count()) === 1);
  fs.rmSync(hold + '-after');
  await waitIdle(page);
  check('あとに呼んだ補助のスキルを添える', await until(async () => (await text(page, '#running')).includes('+ updating-skill-factory-ui-state')));
  check('書き終えると回る印を消す', (await page.locator('#running .spin').count()) === 0);
  check('AI が待っている間は「実行中」と出さない', !(await text(page, '#running')).includes('実行中'), await text(page, '#running'));
  await page.click('#running');
  const stack = await text(page, '#stack');
  check('呼んだスキルを呼んだ順の番号で出す', stack.includes('呼んだ(2 番目)'), stack);
  check('まだ呼んでいないスキルを出す', stack.includes('まだ呼んでいない'), stack);
  check('規約の一覧を出す', stack.includes('規約') && (await page.locator('#stack .rl').count()) > 0);
  await page.locator('#stack .h').click();
  check('一覧の中を押しても閉じない', await visible(page, '#stack'));
  await page.click('#running');
  check('もう一度押すと閉じる', await waitHidden(page, '#stack'));
  writeState(makeState({stage: 2}));
  await sleep(2500);
  check('段階が進んでも、前の段階のスキルを「補助」と取り違えない', (await text(page, '#running')).includes('defining-skill-requirements') && !(await text(page, '#running')).startsWith('updating'), await text(page, '#running'));
});

testCase('claude が失敗したとき', async page => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  planNext(null, {exit: 3, stderr: 'エラーの文'});
  await page.fill('#input', '失敗する文');
  await page.press('#input', 'Enter');
  check('終了コードの行を会話に出す', await until(async () => (await messages(page)).includes('(終了コード 3) エラーの文')));
  check('点の吹き出しが消える', await waitHidden(page, '#messages .typing'));
  check('state.json を変えず、作業の表示が残る', (await text(page, '#work')) === 'テストの作業');
  planNext(null, {reply: '次の返事'});
  await page.fill('#input', '次の文');
  await page.press('#input', 'Enter');
  check('失敗のあとに続けて送れる', await until(async () => (await messages(page)).includes('次の返事')));
});

testCase('複数行の文と本文の区切りの語', async page => {
  planNext(makeState(), {reply: '1 段落目\n\n- 箇条書き\n\n| 列 |\n|---|\n| 値 |'});
  await page.fill('#input', 'ユーザーの 1 行目\n2 行目');
  await page.press('#input', 'Enter');
  check('AI の返事の見出しや表を md の形で出す', await until(async () => (await page.locator('.msg.ai li').count()) === 1 && (await page.locator('.msg.ai table').count()) === 1));
  check('ユーザーの複数行を 1 つの吹き出しに出す', (await page.locator('.msg.user').count()) === 1 && (await text(page, '.msg.user')).includes('2 行目'));
  const align = sel => page.locator(sel).first().evaluate(e => getComputedStyle(e).alignSelf);
  check('ユーザーの文を右寄せにする', (await align('.msg.user')) === 'flex-end', await align('.msg.user'));
  check('AI の文を左寄せにする', (await align('.msg.ai')) === 'flex-start', await align('.msg.ai'));
  await waitIdle(page);
  planNext(null, {reply: '説明です。\nユーザー: この行も AI の本文です'});
  await page.fill('#input', '次の文');
  await page.press('#input', 'Enter');
  await until(async () => (await messages(page)).includes('この行も AI の本文です'));
  check('AI の本文の行頭の「ユーザー:」で吹き出しを分けない', (await page.locator('.msg.user').count()) === 2, await page.locator('.msg.user').count());
});

for (const [name, st] of [
  ['artifacts と figures のキーがない', {workName: 'x', stage: 1}],
  ['decision が question だけ', makeState({decision: {question: 'x'}})],
  ['questions が title だけ', makeState({questions: {title: 'x'}})],
  ['documentPath がない', (({documentPath, ...r}) => r)(makeState())],
]) testCase(`形の違う state.json: ${name}`, async page => {
  check(`作業が決まる`, await startWork(page, makeState()));
  await waitIdle(page);
  writeState(st);
  await sleep(2500);
  check('画面のスクリプトのエラーが出ない', page.caseErrors.length === 0, page.caseErrors[0]);
  writeState(makeState({workName: '直した作業'}));
  check('正しい state.json に戻ると表示が直る', await until(async () => (await text(page, '#work')) === '直した作業', 5000));
}, {errorsChecked: true});

testCase('最初から読めない state.json', async page => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  writeState('{"workName":');
  await page.reload();
  await sleep(1500);
  const shown = (await text(page, '#welcome').catch(() => '')) || '';
  check('読み直した画面が空にならず、開いた直後の文を出す', shown.includes('作成したいスキル'), shown);
  writeState(makeState({workName: '直った作業'}));
  check('正しい state.json に戻ると作業を出す(次の読み直しで直る)', await until(async () => (await text(page, '#work')) === '直った作業', 5000));
});

testCase('AI が同じ問いをもう一度書いたとき', async page => {
  const decision = {question: '承認しますか', choices: ['承認する', '直す'], replies: []};
  check('作業が決まる', await startWork(page, makeState({decision})));
  await until(async () => (await page.locator('.decision .choice').count()) === 2);
  planNext(makeState({decision, stage: 1, workName: 'テストの作業 '}));
  await page.locator('.decision .choice', {hasText: '直す'}).click();
  await until(() => calls().length === 2);
  await waitIdle(page);
  await sleep(2500);
  check('直したあとに同じ承認の問いが来ると、ボタンをまた押せる', await page.locator('.decision .choice').first().isEnabled());
});

testCase('前の会話を続けられなかった答えのあとの質問の一覧', async page => {
  check('作業が決まる', await startWork(page, makeState({questions: threeQuestions()})));
  await waitVisible(page, '#qform');
  await stopServer();
  fs.rmSync(sessionPath);
  await startServer();
  await until(async () => (await text(page, '#conn')) === '接続中');
  await answerBox(page, 2).fill('行き場のない答え');
  await sendAnswers(page);
  await until(() => page.evaluate(() => status.sessionLost));
  await sleep(300);
  planNext(makeState({questions: threeQuestions()}));
  await page.fill('#input', '要件定義書.md');
  await page.press('#input', 'Enter');
  await waitVisible(page, '#qform');
  const kept = await answerBox(page, 2).inputValue();
  const disabled = await page.locator('#qform .qfoot button').isDisabled();
  check('欄に答えが見えているのに送るボタンを押せない形にならない', !(kept.trim() && disabled), `欄: ${kept} / 無効: ${disabled}`);
});

testCase('承認の答えが新しい会話に届かなかったとき', async page => {
  const decision = {question: '承認しますか', choices: ['承認する'], replies: []};
  check('作業が決まる', await startWork(page, makeState({decision})));
  await until(async () => (await page.locator('.decision .choice').count()) === 1);
  await waitIdle(page);
  fs.writeFileSync(noConversation, '');
  await page.locator('.decision .choice').click();
  await until(async () => (await messages(page)).includes('前の会話を続けられないので'));
  check('続けられない間は決めてもらうことを出さない', await until(async () => (await page.locator('.decision .choice').count()) === 0));
  planNext(makeState({decision}));
  await page.fill('#input', '要件定義書.md');
  await page.press('#input', 'Enter');
  check('state.json が書き直されると決めてもらうことを出す', await until(async () => (await page.locator('.decision .choice').count()) === 1));
  await waitIdle(page);
  await sleep(2500);
  check('AI に届かなかった承認のボタンをまた押せる', await page.locator('.decision .choice').isEnabled());
});

testCase('入力欄の操作', async page => {
  await page.fill('#input', '変換中の文');
  await page.evaluate(() => $('input').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', isComposing: true, bubbles: true})));
  await sleep(300);
  check('日本語の変換中の Enter は送らない', (await page.inputValue('#input')) === '変換中の文' && calls().length === 0);
  await page.fill('#input', '   \n ');
  await page.press('#input', 'Enter');
  await sleep(300);
  check('空白だけの文は送らない', calls().length === 0);
  planNext(makeState());
  await page.fill('#input', 'ボタンの文');
  await page.click('#form button[type=submit]');
  check('送るボタンで送る', await until(() => calls().length === 1 && calls()[0].stdin === '画面: 新規\nボタンの文'));
  await until(() => page.evaluate(() => !!state));
  check('作業が決まると開いた直後の文を消す', !(await visible(page, '#welcome')));
});

testCase('読み直しの間隔', async page => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  await sleep(300);
  const begun = Date.now();
  writeState(makeState({workName: '読み直しの確認'}));
  fs.appendFileSync(path.join(workPath, 'ui', 'conversation.md'), 'Claude Code: 外から足した文\n\n');
  const shown = await until(async () => (await text(page, '#work')) === '読み直しの確認' && (await messages(page)).includes('外から足した文'), 8000);
  check('2 秒ごとの読み直しで state.json と conversation.md を出す(3 秒以内)', shown && Date.now() - begun <= 3000, `${Date.now() - begun} ms`);
});

testCase('送れなかったときのボタンと候補', async page => {
  check('作業が決まる', await startWork(page, makeState({decision: {question: '承認しますか', choices: ['承認する'], replies: []}})));
  await until(async () => (await page.locator('.decision .choice').count()) === 1);
  await waitIdle(page);
  await stopServer();
  await page.locator('.decision .choice').click();
  check('選択肢が送れないと理由を出す', await until(async () => (await visible(page, '#err')) && (await text(page, '#err')).includes('つながりません')));
  check('送れなかった選択肢のボタンをまた押せる', await until(() => page.locator('.decision .choice').isEnabled()));
  check('送れなかったときは入力欄を赤くする', (await page.locator('#input').getAttribute('class') || '').includes('ng'));
  await startServer();
  await until(async () => (await text(page, '#conn')) === '接続中');
  // 起動し直した中継サーバーは、起動の前からある作業を自分では選ばないので、続きからの要求で作業を決める
  await page.evaluate(dir => fetch('/api/resume', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({dir})}), work);
  writeState(makeState({decision: {question: '次に進みますか', choices: [], replies: ['進む']}}));
  await until(async () => (await page.locator('#messages .chips .chip').count()) === 1);
  await page.locator('#messages .chips .chip').click();
  check('押した候補を押した形で出す', await until(async () => (await page.locator('#messages .chips .chip.on').count()) === 1));
  await stopServer();
  await page.press('#input', 'Enter');
  await until(async () => (await visible(page, '#err')) && (await text(page, '#err')).includes('つながりません'));
  await startServer();
  await until(async () => (await text(page, '#conn')) === '接続中');
  await sleep(2500);
  check('送れなかった候補をまた出す', (await page.locator('#messages .chips .chip').count()) === 1);
});

testCase('タブを閉じても AI が動き続ける', async (page, context) => {
  check('作業が決まる', await startWork(page, makeState()));
  await waitIdle(page);
  fs.writeFileSync(hold, '');
  planNext(makeState({workName: '閉じたあとの作業'}), {reply: '閉じたあとの返事'});
  await page.fill('#input', '閉じる前の文');
  await page.press('#input', 'Enter');
  await until(() => calls().length === 2);
  await page.close();
  fs.rmSync(hold);
  const conv = path.join(workPath, 'ui', 'conversation.md');
  check('タブを閉じたあとも返事が conversation.md に書かれる', await until(() => fs.readFileSync(conv, 'utf8').includes('閉じたあとの返事')));
  const reopened = await context.newPage();
  await reopened.goto(url);
  check('開き直すと続きと state.json の表示が出る', await until(async () => (await messages(reopened)).includes('閉じたあとの返事') && (await text(reopened, '#work')) === '閉じたあとの作業'));
}, {errorsChecked: true});

testCase('外部のライブラリが読めないとき', async page => {
  planNext(makeState(), {reply: '読めないときの返事'});
  await page.fill('#input', '依頼');
  await page.press('#input', 'Enter');
  await until(() => calls().length === 1);
  await sleep(3000);
  check('md の表示のライブラリが読めなくても会話を文で出す', (await messages(page)).includes('読めないときの返事'), await messages(page));
}, {noCdn: true, errorsChecked: true});

testCase('図とダウンロードの欄の条件', async page => {
  check('図が 0 件で作業が決まる', await startWork(page, makeState()));
  await waitVisible(page, '#preview');
  check('図が 0 件のときは図の欄を出さない', !(await visible(page, '#figbox')));
  check('ダウンロードが 0 件のときはボタンを出さない', !(await visible(page, '#dl')));
  const svg = name => `<svg xmlns="http://www.w3.org/2000/svg" id="${name}" width="10" height="10"></svg>`;
  putFile('ui/figures/3-phase と step の流れ図.svg', svg('fig-jp'));
  putFile('成果物 1.txt', '中身');
  writeState(makeState({figures: [{tab: 'phase と step の流れ図', path: 'ui/figures/3-phase と step の流れ図.svg'}], downloads: ['成果物 1.txt']}));
  check('空白と日本語の名前の図を出す', await until(async () => (await page.locator('#figure #fig-jp').count()) === 1));
  check('図が 1 つのときはタブを出さない', (await page.locator('#tabs .tab').count()) === 0);
  await page.click('#dl');
  await page.click('#dl');
  check('ダウンロードの一覧はボタンでも閉じる', !(await visible(page, '#dlmenu')));
  await page.click('#dl');
  await page.click('#docpath');
  check('ダウンロードの一覧は外を押すと閉じる', !(await visible(page, '#dlmenu')));
  writeState(makeState({figures: [{tab: 'ない図', path: 'ui/figures/none.svg'}]}));
  check('ない図のファイルでエラーにならず図の欄を空にする', await until(async () => (await page.locator('#figure svg').count()) === 0));
  writeState(makeState({figures: [{tab: '図 A', path: 'ui/figures/3-phase と step の流れ図.svg'}], downloads: ['成果物 1.txt'], questions: threeQuestions()}));
  check('質問の一覧を出している間は図を隠す', await waitVisible(page, '#qform') && !(await visible(page, '#figbox')));
  check('質問の一覧を出している間はダウンロードのボタンを隠す', !(await visible(page, '#dl')));
  await page.locator('#qform .chip', {hasText: '必須'}).click();
  await page.locator('#qform .chip', {hasText: '必須'}).click();
  check('同じ選択肢をもう一度押すと取り消す', (await text(page, '#qform .qhead .c')) === '全 3 問(回答済み 0 問、残り 3 問)', await text(page, '#qform .qhead .c'));
  await answerBox(page, 2).fill('   ');
  check('空白だけの答えを回答済みに数えない', (await text(page, '#qform .qhead .c')) === '全 3 問(回答済み 0 問、残り 3 問)');
  writeState(makeState({questions: threeQuestions({1: 'a', 2: 'b', 3: 'c'})}));
  check('全問に答えがあると文書に戻る', await waitHidden(page, '#qform'));
});

testCase('「続きから」の失敗', async page => {
  check('作業が決まる', await startWork(page, makeState()));
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  await waitVisible(page, '#works .wk');
  const btn = page.locator('#works .wk button', {hasText: '続きから'});
  await stopServer();
  await btn.click();
  check('中継サーバーが止まっていると理由を出す', await until(async () => (await visible(page, '#err')) && (await text(page, '#err')).startsWith('続けられませんでした')));
  check('ボタンをまた押せる', await btn.isEnabled());
  await startServer();
  fs.rmSync(workPath, {recursive: true});
  await btn.click();
  check('作業のフォルダがないと理由を出す', await until(async () => (await text(page, '#err')).includes('state.json がありません')));
  check('ボタンをまた押せる(作業がないとき)', await btn.isEnabled());
});

testCase('返事を書いている間の操作', async page => {
  check('作業が決まる', await startWork(page, makeState({decision: {question: '承認しますか', choices: ['承認する'], replies: []}})));
  await until(async () => (await page.locator('.decision .choice').count()) === 1);
  await waitIdle(page);
  fs.writeFileSync(hold, '');
  planNext(null);
  await page.fill('#input', '文');
  await page.press('#input', 'Enter');
  check('AI が書いている間は承認のボタンを押せない', await until(() => page.locator('.decision .choice').isDisabled()));
  fs.rmSync(hold);
  await waitIdle(page);
  writeState(makeState({decision: {question: '次に進みますか', choices: [], replies: ['進む']}}));
  await until(async () => (await page.locator('#messages .chips .chip').count()) === 1);
  fs.writeFileSync(hold, '');
  planNext(null);
  await page.fill('#input', '別の文');
  await page.press('#input', 'Enter');
  check('AI が書いている間は候補を出さない', await until(async () => (await page.locator('#messages .chips .chip').count()) === 0));
  fs.rmSync(hold);
  await waitIdle(page);
});

testCase('段階の表が読めないとき', async (page, context) => {
  let broken = true;
  await context.route('**/api/stages', route => (broken ? route.fulfill({status: 404, body: 'ない'}) : route.continue()));
  await page.reload();
  await sleep(2500);
  check('段階の表が読めない間は帯を出さない', (await page.locator('#stages .pill').count()) === 0);
  broken = false;
  check('読めるようになると帯を出す', await until(async () => (await page.locator('#stages .pill').count()) === 8, 5000));
});

testCase('接続の状態と直し方の文', async page => {
  check('問い合わせのあとに「AI に接続中」を出す', await until(() => page.evaluate(() => stagesTable !== null)) && (await text(page, '#conn')) === 'AI に接続中');
  check('つながっている間は直し方を出さない', !(await visible(page, '#banner')));
  const right = await page.locator('#conn').evaluate(e => e.getBoundingClientRect().right > document.querySelector('.brand').getBoundingClientRect().right);
  check('状態はヘッダーの右側に出す', right);
  await stopServer();
  await waitVisible(page, '#banner');
  check('止まっているときの直し方に起動のコマンドを出す', (await text(page, '#banner')).includes('node ui/server.mjs'));
  await startServer();
  check('つながると直し方を消す', await waitHidden(page, '#banner'));
  await stopServer();
  fs.writeFileSync(noVersion, '');
  await startServer();
  await waitVisible(page, '#banner');
  check('claude がないときの直し方を出す', (await text(page, '#banner')).includes('Claude Code を入れて'));
});

testCase('更新の手順と開くアドレス', async (page, context) => {
  const index = path.join(sf, 'ui', 'index.html');
  const original = fs.readFileSync(index, 'utf8');
  fs.writeFileSync(index, original.replace('<div class="brand">skill-factory</div>', '<div class="brand">skill-factory-updated</div>'));
  await stopServer();
  await startServer();
  await page.reload();
  check('起動し直して読み直すと直した画面を出す', await until(async () => (await text(page, '.brand')) === 'skill-factory-updated'));
  fs.writeFileSync(index, original);
  const local = await context.newPage();
  await local.goto(`http://localhost:${port}/`);
  planNext(makeState());
  await local.fill('#input', 'localhost からの依頼');
  await local.press('#input', 'Enter');
  check('localhost で開いた画面から送れる', await until(() => calls().length === 1 && calls()[0].stdin.endsWith('localhost からの依頼')));
});


// 聞き取りの画面の見本(ui/example/ui/screens/)
// 見本の問いの一覧(questions)だけを替えたときは、回の一覧(rounds)の最後の回(いまの回)の問いも同じ問いにする(インターフェース設計書の章 2)
const sample = (name, over = {}) => {
  const base = JSON.parse(fs.readFileSync(path.join(uiDir, 'example', 'ui', 'screens', name + '.json'), 'utf8'));
  const st = {...base, ...over};
  if (over.questions && !('rounds' in over) && Array.isArray(base.rounds) && base.rounds.length) st.rounds = [...base.rounds.slice(0, -1), {...base.rounds.at(-1), items: over.questions.items.map(i => ({...i, replaced: false}))}];
  return st;
};
const hearBody = page => text(page, '#hearbody');
const hearButton = (page, label) => page.locator('#hearfoot button', {hasText: label});
const waitHear = (page, word, ms) => until(async () => (await visible(page, '#hear')) && (await hearBody(page)).includes(word), ms);
const nextCall = n => until(() => calls().length === n);

testCase('画面 1 の文面と途中の作業', async page => {
  check('見出しを出す', await until(async () => (await text(page, '#welcome h1')) === '作成したいスキルについて、自由に書いてください'));
  check('説明の文を 2 行で出す', (await text(page, '#welcome p')) === '何を渡すと、何をして、何を出してほしいかを、思いつくままに書いてください。\n決まっていないことは、このあと一緒に決めます。', await text(page, '#welcome p'));
  check('入力欄は 5 行', (await page.getAttribute('#input', 'rows')) === '5');
  check('段階の帯に画面の言葉.md の語を出す', await until(async () => (await text(page, '#stages')).includes('スキルの構成の案')));
  check('作業がないときは聞き取りの欄を出さない', !(await visible(page, '#hear')));
  const d = path.join(sf, 'output', 'w-rest', 'ui');
  fs.mkdirSync(d, {recursive: true});
  fs.writeFileSync(path.join(d, 'state.json'), JSON.stringify(makeState({workName: '途中の作業の見本', stage: 3})));
  await stopServer();
  await startServer();
  await page.reload();
  check('途中の作業は「途中の作業 1 件」の見出しで出す', await until(async () => (await visible(page, '#works > summary')) && (await text(page, '#works > summary')) === '途中の作業 1 件'));
  check('初めは閉じている', !(await visible(page, '#works .wk')));
  await page.locator('#works > summary').click();
  check('押すと行が開く', await waitVisible(page, '#works .wk') && (await text(page, '#works .wk')).includes('途中の作業の見本'));
});

testCase('AI が読む画面', async page => {
  fs.writeFileSync(hold, '');
  planNext(sample('画面 2'));
  await page.fill('#input', '議事録を要約して');
  await page.press('#input', 'Enter');
  check('送ると「AI があなたの文章を読んでいます」を出す', await waitHear(page, 'AI があなたの文章を読んでいます'));
  check('読み終わったあとの文を出す', (await hearBody(page)).includes('読み終わると、AI がまとめた内容を見せます。'));
  check('会話の記録は初め閉じている', !(await visible(page, '#messages')));
  check('下の 1 行を出す', await visible(page, '#input') && (await page.getAttribute('#input', 'placeholder')) === '足りないことを、ここに書いてください。AI がもう一度整理します。');
  check('段階の帯に「文章を読んでいる」を添える', (await text(page, '#stages .pill.now')).includes('文章を読んでいる'));
  check('実行中の表示は「要件定義書を作っています」', (await text(page, '#running')).includes('要件定義書を作っています'));
  check('接続の状態は「AI に接続中」', (await text(page, '#conn')) === 'AI に接続中');
  check('待っている間は「あとで続ける」を押せない', await hearButton(page, 'あとで続ける').isDisabled());
  fs.rmSync(hold);
  check('AI が state.json を書くと自動で画面 2 へ進む', await waitHear(page, 'というスキルですね？'));
  writeState(sample('AI が読む'));
  check('state.json の screen が「AI が読む」で AI が止まっているときは、会話の記録へ案内する', await waitHear(page, 'AI は止まっています。'));
});

testCase('最初の依頼が段階 2 から 8 のスキルを呼ぶとき', async page => {
  fs.writeFileSync(hold + '-after', '');
  planNext(null, {holdAfter: true, reply: '返事', lines: [{type: 'system', subtype: 'init', session_id: 'x'}, {type: 'assistant', message: {content: [{type: 'tool_use', name: 'Skill', id: 't1', input: {skill: 'checking-skill-with-template'}}]}}]});
  await page.fill('#input', 'あるスキルを照合して');
  await page.press('#input', 'Enter');
  check('聞き取りの欄を消す', await waitHidden(page, '#hear'));
  check('会話の欄に戻る', await waitVisible(page, '#chat #messages .typing'));
  check('実行中の表示はスキルの名前', (await text(page, '#running')).includes('checking-skill-with-template を実行中'), await text(page, '#running'));
  fs.rmSync(hold + '-after');
});

testCase('画面 2 のまとめと、はい', async page => {
  check('作業が決まる', await startWork(page, sample('画面 2')));
  check('見出しとまとめを、見出しの順で出す', await waitHear(page, 'というスキルですね？'));
  const body = await hearBody(page);
  check('まとめの 3 行を改行して出す', body.includes('あなたの作成したいスキルは') && body.includes('「議事録を渡すと、\n決定事項と宿題を抜き出して、\n300 字以内の要約を書く」'), body);
  check('前の形の右の欄と会話の欄を出さない', !(await visible(page, '#preview')) && !(await visible(page, '#chat')));
  check('選択肢を会話の欄に出さない', (await page.locator('.decision').count()) === 0);
  check('下の段の左に「あとで続ける」と「やめる」を出す', (await text(page, '#hearfoot .pleave')).replace(/\s+/g, '') === 'あとで続けるやめる');
  check('段階の帯に「まとめの確認」を添える', (await text(page, '#stages .pill.now')).includes('まとめの確認'));
  fs.writeFileSync(hold, '');
  planNext(sample('調べるための問い'));
  await hearButton(page, 'はい').click();
  check('AI が書いた選択肢の文のまま送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\nはい(推奨)`, lastCall().stdin);
  check('元の会話を --resume で続ける', !!argAfter(lastCall(), '--resume'));
  check('送ったあとはボタンを押せない', await until(() => hearButton(page, 'はい').isDisabled()));
  check('AI が読んでいることを出す', (await hearBody(page)).includes('AI があなたの答えを読んでいます'));
  fs.rmSync(hold);
  check('AI の返事で次の画面へ進む', await waitHear(page, 'このスキルを作るために、調べる前に教えてください'));
});

testCase('画面 2 の選択肢がオブジェクトの形', async page => {
  // 2026-11-11 の実行で、AI が decision.choices を {label, result, ...} の形で書き、画面が「画面の状態が設計と合いません」とボタン「[object Object]」を出した
  const base = sample('画面 2');
  const choices = base.decision.choices.map(c => ({label: c, result: '次へ進む。', recommend: false, recommendReason: null, confirm: false}));
  check('作業が決まる', await startWork(page, {...base, decision: {...base.decision, choices}}));
  check('まとめの画面を出す', await waitHear(page, 'というスキルですね？'));
  const body = await hearBody(page);
  check('設計と合わないという見出しを出さない', !body.includes('画面の状態が設計と合いません') && !(await text(page, 'body')).includes('[object Object]'), body);
  check('ボタンは label の文を出す', await hearButton(page, 'はい').count() === 1);
  fs.writeFileSync(hold, '');
  planNext(sample('調べるための問い'));
  await hearButton(page, 'はい').click();
  check('label の文のまま送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\nはい(推奨)`, lastCall().stdin);
  fs.rmSync(hold);
  check('AI の返事で次の画面へ進む', await waitHear(page, 'このスキルを作るために、調べる前に教えてください'));
  // 画面 3 と画面 5 も、choices の label で主なボタンを決める
  const objChoices = s => ({...s, decision: {...s.decision, choices: s.decision.choices.map(c => ({label: c, result: '次へ進む。', recommend: false, recommendReason: null, confirm: false}))}});
  writeState(objChoices(sample('画面 3')));
  check('画面 3 で主なボタンに label を出す', await waitHear(page, '個を確かめます') && (await hearButton(page, '合っています。質問へ進む').count()) === 1 && !(await text(page, 'body')).includes('[object Object]'), await text(page, '#hearfoot'));
  writeState(objChoices(sample('画面 5')));
  check('画面 5 で主なボタンに label を出す', await waitHear(page, 'この内容で要件定義書を書いてよいですか？') && (await hearButton(page, '承認する').count()) === 1 && !(await text(page, 'body')).includes('[object Object]'));
});

testCase('画面 2 の違うところを直す', async page => {
  check('作業が決まる', await startWork(page, sample('画面 2')));
  await waitHear(page, 'というスキルですね？');
  await hearButton(page, '違うところを直す').click();
  check('同じ画面で入力欄を開く', await waitHear(page, '違うところを、その場で直してください。'));
  check('入力欄にまとめの全行が入る', (await page.inputValue('#hearbody textarea')) === '議事録を渡すと、\n決定事項と宿題を抜き出して、\n300 字以内の要約を書く');
  check('説明の文を出す', (await hearBody(page)).includes('直した文だけを AI が読み直します。あなたの文章は、そのまま残ります。'));
  await hearButton(page, 'この文に直す').click();
  check('何も変えずに押すと AI に送らず、確認の画面に戻す', await waitHear(page, 'というスキルですね？') && calls().length === 1);
  await hearButton(page, '違うところを直す').click();
  await page.fill('#hearbody textarea', '捨てる文');
  await hearButton(page, '直すのをやめる').click();
  check('「直すのをやめる」で入力を捨てる', await waitHear(page, '「議事録を渡すと、') && calls().length === 1);
  await hearButton(page, '違うところを直す').click();
  check('やめたあとに開くと元の文に戻る', (await page.inputValue('#hearbody textarea')).startsWith('議事録を渡すと、'));
  await page.fill('#hearbody textarea', '議事録を渡すと、\n宿題だけを抜き出す');
  fs.writeFileSync(hold, '');
  planNext(sample('画面 2', {summary: {lines: ['議事録を渡すと、', '宿題だけを抜き出す'], readings: []}}));
  await hearButton(page, 'この文に直す').click();
  check('AI の選択肢の語と、前の文と後の文を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n違う\nまとめた文\n前の値: 議事録を渡すと、\n決定事項と宿題を抜き出して、\n300 字以内の要約を書く\n後の値: 議事録を渡すと、\n宿題だけを抜き出す`, lastCall().stdin);
  check('読み直している間の表示を出す', await waitHear(page, 'AI がまとめを読み直しています'));
  fs.rmSync(hold);
  check('直した文と知らせを出す', await waitHear(page, 'まとめを直しました。') && (await hearBody(page)).includes('宿題だけを抜き出す'));
  check('ボタンは「もう一度直す」になる', await until(async () => (await hearButton(page, 'もう一度直す').count()) === 1));
});

testCase('画面 2 の 2 通りに読める依頼', async page => {
  planNext(sample('画面 2 の短い依頼'));
  await page.fill('#input', 'コミットをまとめるskillを作る');
  await page.press('#input', 'Enter');
  check('読みの見出しを出す', await waitHear(page, 'あなたの作成したいスキルは、次のどれですか？'));
  const body = await hearBody(page);
  check('依頼の文を添えて 2 通りに読めたことを出す', body.includes('「コミットをまとめるskillを作る」は、2 通りに読めました。'), body);
  check('読みの候補と「その他」を出す', (await page.locator('#hearbody .zop').count()) === 3 && body.includes('複数のコミットを 1 つにする') && body.includes('コミットの内容を文章に要約する') && body.includes('その他'), body);
  const go = hearButton(page, 'これで合っています');
  check('選ぶまで押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: 'その他'}).click();
  check('「その他」を選ぶと押せる', await go.isEnabled());
  await go.click();
  check('「その他」で下の 1 行が空のときは送らない', calls().length === 1);
  await page.locator('#hearbody .zop', {hasText: 'コミットの内容を文章に要約する'}).click();
  planNext(sample('画面 2'));
  await go.click();
  check('選んだ読みの文を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\nコミットの内容を文章に要約する`, lastCall().stdin);
  check('AI の返事のあとにまとめを出す', await waitHear(page, 'というスキルですね？'));
});

testCase('調べるための問いと答えの送信', async page => {
  check('作業が決まる', await startWork(page, sample('調べるための問い')));
  check('見出しを出す', await waitHear(page, 'このスキルを作るために、調べる前に教えてください'));
  const body = await hearBody(page);
  check('問いの数と役目の文を出す', body.includes('次の 2 問です。答えで、AI が調べる場所が決まります。'), body);
  check('すべての結果の文を出す', await visible(page, '#hearbody .zop small'));
  check('聞く理由を出す', body.includes('調べるフォルダと、スキルを置く場所が決まります。'));
  const go = hearButton(page, '回答を送る');
  check('回が 1 ページのときは、「次へ」の代わりに「回答を送る」と、その横の文を出す', (await hearButton(page, '次へ').count()) === 0 && (await go.count()) === 1 && (await text(page, '#hearfoot .fq')) === 'AI は、回答を読んで、次の画面を作ります。');
  check('すべて答えるまで「回答を送る」を押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: 'すべてのプロジェクト'}).click();
  check('1 問だけでは押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: 'フォルダかリポジトリのパスを書く'}).click();
  await page.locator('#hearbody fieldset').nth(1).locator('summary').click();
  await answerBox(page, 2).fill('docs/議事録/');
  check('答えると押せる', await go.isEnabled());
  fs.writeFileSync(hold, '');
  planNext(sample('調査'));
  await go.click();
  check('「番号: 答え」を 1 行ずつ送り、補足を添える', await nextCall(2) && lastCall().stdin === `画面: ${work}\n1: すべてのプロジェクト\n2: フォルダかリポジトリのパスを書く(補足: docs/議事録/)`, lastCall().stdin);
  check('次の質問を書いている間の表示と、受け取った答えを出す', await waitHear(page, '次の質問を書いています') && (await hearBody(page)).includes('受け取った答え') && (await hearBody(page)).includes('すべてのプロジェクト'));
  fs.rmSync(hold);
  check('AI の返事で調査の画面へ進む', await waitHear(page, 'AI が調べています'));
});

testCase('調査の画面', async page => {
  fs.writeFileSync(hold + '-after', '');
  planNext(sample('調査'), {holdAfter: true, reply: '返事', lines: [{type: 'system', subtype: 'init', session_id: 'x'}]});
  await page.fill('#input', '依頼');
  await page.press('#input', 'Enter');
  check('見出しと役目の文を出す', await waitHear(page, 'AI が調べています') && (await hearBody(page)).includes('あなたの文章を、実際のファイルと環境に照らしています。終わると、自動で次へ進みます。'));
  const body = await hearBody(page);
  check('調べた行は名前と結果の文を出す', body.includes('議事録のファイル 3 件') && body.includes('読みました'), body);
  check('語の行を出す', body.includes('「要約」が指すもの') && body.includes('「要約」が指すものが決まりました'), body);
  check('調べている行は「AI が調べています:」で出す', body.includes('AI が調べています: 既にあるスキル'), body);
  check('調べられなかった行は理由を出す', body.includes('「まだない」と答えたので調べていません。場所が分かったら調べます'), body);
  check('調べている間は回る表示を出す', await visible(page, '#hearbody .zspin'));
  check('段階の帯に「調査中」を添える', (await text(page, '#stages .pill.now')).includes('調査中'));
  fs.rmSync(hold + '-after');
  check('AI が止まったら、会話の記録へ案内する', await waitHear(page, 'AI は止まっています。'));
});

testCase('画面 3 の事実確認と修正', async page => {
  check('作業が決まる', await startWork(page, sample('画面 3')));
  check('見出しの文を出す', await waitHear(page, 'あなたの文章と調べた結果から 10 個決まりました。ここでは 3 個を確かめます。'));
  const body = await hearBody(page);
  check('残りの数とこのあとの量の文を 2 行で出す', body.includes('残りの 7 個は、前の画面か要件定義書の下書きに、あなたの文章と調べた結果のまま出します。\nこのあと、質問 5 問と、下書きの承認で決めます。'), body);
  check('調べた事実と出どころを出す', body.includes('AI が調べて分かったこと') && body.includes('Markdown の議事録が 9 件あります') && body.includes('出どころ: 調査: docs/議事録/'), body);
  check('確かめる項目の名前と値を出す', body.includes('作業を繰り返す頻度') && body.includes('週 1 回'), body);
  check('「修正しました」と「追加」のラベルを出す', (await page.locator('#hearbody .zmk', {hasText: '修正しました'}).count()) === 1 && (await page.locator('#hearbody .zmk', {hasText: '追加'}).count()) === 1);
  await hearButton(page, '内容を修正する').click();
  check('行の値が入力欄に変わる', await waitHear(page, '違うところを、その場で直してください。') && (await page.locator('#hearbody .ze textarea').count()) === 3);
  // 書いて元の値に戻した行も、変えていない行として扱う
  await page.getByLabel('作業を繰り返す頻度').fill('週 1 回');
  await hearButton(page, 'この内容に直す').click();
  check('何も変えずに押すと AI に送らない', await waitHear(page, 'ここでは 3 個を確かめます。') && calls().length === 1);
  await hearButton(page, '内容を修正する').click();
  await page.getByLabel('作業を繰り返す頻度').fill('毎日');
  await page.fill('#input', '下の 1 行の文');
  await page.press('#input', 'Enter');
  check('修正中に下の 1 行へ書くと、入力を残して案内する', await until(async () => (await text(page, '#err')).includes('修正の途中です。')) && (await page.inputValue('#input')) === '下の 1 行の文' && (await page.getByLabel('作業を繰り返す頻度').inputValue()) === '毎日' && calls().length === 1);
  await page.fill('#input', '');
  fs.writeFileSync(hold, '');
  const nextState = sample('画面 3');
  nextState.factCheck.items[0] = {name: '作業を繰り返す頻度', value: '毎日', label: '修正しました'};
  planNext(nextState);
  await hearButton(page, 'この内容に直す').click();
  check('変えた行の名前と前の値と後の値だけを送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n内容を修正する\n作業を繰り返す頻度\n前の値: 週 1 回\n後の値: 毎日`, lastCall().stdin);
  check('読み直している間の表示を出す', await waitHear(page, 'AI が「作業を繰り返す頻度」を読み直しています'));
  fs.rmSync(hold);
  check('直した値と知らせを出す', await waitHear(page, '「作業を繰り返す頻度」を直しました。') && (await hearBody(page)).includes('毎日'));
  fs.writeFileSync(hold, '');
  planNext(sample('画面 4'));
  await hearButton(page, '合っています。質問へ進む').click();
  check('AI が書いた選択肢の文のまま送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\n合っています。質問へ進む(推奨)`, lastCall().stdin);
  fs.rmSync(hold);
  check('AI の返事で画面 4 へ進む', await waitHear(page, '作業の範囲'));
  // 画面 3 の decision は、インターフェース設計書の章 2 の表で「選択肢」なので、選択肢を 1 件以上持つ
  fs.writeFileSync(statePath, JSON.stringify(sample('画面 3', {factCheck: {heading: 'あなたの文章と調べた結果から 0 個決まりました。', note: '', facts: [{text: '事実', source: '出どころ'}], items: []}, decision: {question: '質問へ進みますか。', choices: ['質問へ進む(推奨)'], replies: []}})));
  check('決まった内容が 0 個のときは書き足す道と「質問へ進む」を出す', await waitHear(page, '0 個決まりました') && await until(async () => (await hearButton(page, 'あなたの文章に書き足す').count()) === 1 && (await hearButton(page, '質問へ進む').count()) === 1));
});

testCase('画面 4 の問いと選択肢', async page => {
  check('作業が決まる', await startWork(page, sample('画面 3')));
  await waitHear(page, '質問 5 問');
  writeState(sample('画面 4'));
  check('見出しはカテゴリーの名前', await waitHear(page, '作業の範囲') && (await text(page, '#hearbody .zt1')) === '作業の範囲');
  const body = await hearBody(page);
  check('問いの番号と残りの問数を出す', body.includes('質問 1 から 3。残り約 1 問です。'), body);
  check('細い棒を出す', (await page.locator('#hearbody .zbar i').count()) >= 1);
  check('質問の数が変わった知らせを出す', body.includes('前の答えで、質問が 1 問減りました。'), body);
  check('「(推奨)」を文から分けてラベルにし、初めから選ぶ', (await page.locator('#hearbody .zop', {hasText: 'ない'}).first().locator('.zmk').innerText()) === '推奨' && await page.locator('#hearbody .zop', {hasText: 'ない'}).first().locator('input').isChecked());
  check('結果の文は選んだ選択肢にだけ出す', await page.locator('#hearbody .zop', {hasText: 'ない'}).first().locator('small').isVisible() && !(await page.locator('#hearbody .zop', {hasText: '書く前'}).locator('small').isVisible()));
  const go = hearButton(page, '回答を送る');
  check('答えていない問いがある間は「回答を送る」を押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: '書く前'}).click();
  check('選んだ選択肢の結果の文を出す', await page.locator('#hearbody .zop', {hasText: '書く前'}).locator('small').isVisible());
  await page.locator('#hearbody fieldset').first().locator('summary').click();
  check('「理由と補足」で聞く理由と回答例を出す', (await text(page, '#hearbody fieldset >> nth=0')).includes('元に戻せない操作の前の確認が決まります。 例: 「読むだけ」'));
  const free = page.locator('#hearbody fieldset').nth(2);
  check('選択肢のない問いは「答えを書く」を開いて出す', await free.locator('textarea').isVisible() && (await free.locator('summary').innerText()).includes('答えを書く'));
  await free.getByRole('button', {name: '分からない'}).click();
  check('「分からない」を答えに入れる', (await free.locator('textarea').inputValue()) === '分からない' && await go.isEnabled());
  fs.writeFileSync(hold, '');
  planNext(sample('画面 5'));
  await go.click();
  check('「番号: 答え」を 1 行ずつ送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n1: ない(推奨)\n2: 書く前\n3: 分からない`, lastCall().stdin);
  check('次の質問を書いている間の表示を出す', await waitHear(page, '次の質問を書いています'));
  fs.rmSync(hold);
  // 段階 1 は、問いのあとに下書きの承認(画面 5)へ進む
  check('AI の返事で下書きの画面へ進む', await waitHear(page, 'この内容で要件定義書を書いてよいですか？'));
  writeState(sample('画面 4', {questions: {...sample('画面 4').questions, notice: '調べ直した結果: docs/議事録/ の 12 件は、どれも見出しを持ちます。'}}));
  check('調べ直した結果を問いの上に出す', await waitHear(page, '調べ直した結果: docs/議事録/ の 12 件は、どれも見出しを持ちます。'));
  check('前のページがないときは「前へ」を出さない', (await hearButton(page, '前へ').count()) === 0);
});

testCase('これまでの答えの一覧', async page => {
  check('作業が決まる', await startWork(page, sample('調べるための問い')));
  await waitHear(page, '調べる前に教えてください');
  await page.locator('#hearbody .zop', {hasText: 'すべてのプロジェクト'}).click();
  await page.locator('#hearbody .zop', {hasText: 'まだない'}).click();
  // モックの AI は、答えを書いた調べるための問いの回の後ろに、画面 4 の回を足す(インターフェース設計書の章 2)
  const pre = sample('調べるための問い').questions.items;
  const q4 = sample('画面 4').questions;
  const items4 = q4.items.map((i, k) => ({...i, number: pre.length + k + 1}));
  const next4 = sample('画面 4', {questions: {...q4, items: items4}, rounds: [{kind: '調べるための問い', items: [{...pre[0], answer: 'すべてのプロジェクト', replaced: false}, {...pre[1], answer: 'まだない', replaced: false}]}, {kind: '2 段目', items: items4.map(i => ({...i, replaced: false}))}]});
  check('モックの AI が書く組は state-contract に合う', stateContractGaps(next4).length === 0, stateContractGaps(next4).join(' / '));
  planNext(next4);
  await hearButton(page, '回答を送る').click();
  check('画面 4 へ進む', await waitHear(page, '作業の範囲'));
  await waitIdle(page);
  await page.locator('#hearfoot button', {hasText: 'これまでの答えの一覧'}).click();
  check('見出しと役目の文を出す', await waitHear(page, 'これまでの答え') && (await hearBody(page)).includes('直す質問を選んでください。ほかの答えは、そのまま残ります。'));
  const body = await hearBody(page);
  check('送った回の答えを、回の一覧から出す', body.includes('質問 1 ・ このスキルを、どのプロジェクトで使いますか。') && body.includes('すべてのプロジェクト') && body.includes('まだない'), body);
  await hearButton(page, '質問に戻る').click();
  check('「質問に戻る」で問いへ戻る', await waitHear(page, '作業の範囲'));
  await page.locator('#hearfoot button', {hasText: 'これまでの答えの一覧'}).click();
  await waitHear(page, '直す質問を選んでください。');
  const sent = calls().length;
  await page.locator('#hearbody button', {hasText: 'この質問に戻る'}).first().click();
  check('送った問いの「この質問に戻る」で、その問いのページを出す', await waitHear(page, '調べる前に教えてください'));
  check('「この質問に戻る」は AI に送らない', calls().length === sent, calls().length);
  check('送った選択肢の問いは、送った答えの選択肢を選んだ状態で出す', await page.locator('#hearbody .zop', {hasText: 'すべてのプロジェクト'}).locator('input').isChecked() && !(await page.locator('#hearbody .zop', {hasText: 'このプロジェクトだけ'}).locator('input').isChecked()));
  check('送った回のページは、直した答えを次に送ることを知らせる 1 文を出す', (await hearBody(page)).includes('この画面で直した答えは、次に AI に送るときに一緒に送ります。'));
  check('送った回のページは、「回答を送る」を出さず、「次へ」を出す', (await hearButton(page, '回答を送る').count()) === 0 && (await hearButton(page, '次へ').count()) === 1);
});

testCase('あとで続けるとやめる', async page => {
  check('作業が決まる', await startWork(page, sample('画面 4')));
  await waitHear(page, '作業の範囲');
  await hearButton(page, 'あとで続ける').click();
  check('見出しと 2 つの動きの違いを出す', await waitHear(page, 'ここで質問を止めますか？'));
  const body = await hearBody(page);
  check('あとで続けるは聞き取りの記録の場所を出す', body.includes(`あなたの文章と答えは ${work}/聞き取りの記録.md に残ります。画面 1 の「途中の作業」の「続きから」で続けられます。`), body);
  check('やめるの動きを出す', body.includes('要件定義書を書かずに終えます。ファイルは残し、「途中の作業」の一覧から外します。'), body);
  await hearButton(page, '質問に戻る').click();
  check('「質問に戻る」で問いへ戻る', await waitHear(page, '作業の範囲') && calls().length === 1);
  await hearButton(page, 'あとで続ける').click();
  fs.writeFileSync(hold, '');
  planNext(null);
  await page.locator('#hearbody button', {hasText: 'あとで続ける'}).click();
  check('「あとで続ける」の語を AI に送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\nあとで続ける`, lastCall().stdin);
  fs.rmSync(hold);
  check('AI の返事のあとに画面 1 へ戻る', await until(async () => (await visible(page, '#welcome')) && (await text(page, '#welcome')).includes('作成したいスキル')));
  await openWorks(page);
  check('途中の作業の一覧に残る', await waitVisible(page, '#works .wk') && (await text(page, '#works .wk')).includes('議事録の要約'));
  await page.locator('#works .wk button', {hasText: '続きから'}).click();
  check('「続きから」で同じ画面を出す', await waitHear(page, '作業の範囲'));
  await hearButton(page, 'やめる').click();
  planNext(null);
  await page.locator('#hearbody button', {hasText: 'やめる'}).click();
  check('「やめる」の語を AI に送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\nやめる`, lastCall().stdin);
  check('AI の返事のあとに画面 1 へ戻る(やめる)', await until(async () => (await visible(page, '#welcome')) && (await text(page, '#welcome')).includes('作成したいスキル')));
  await sleep(500);
  check('やめた作業は途中の作業の一覧に出ない', !(await visible(page, '#works')));
  check('やめた作業のファイルは残る', fs.existsSync(statePath));
});

testCase('画面 5 の下書きと承認', async page => {
  fs.writeFileSync(hold + '-after', '');
  planNext(sample('画面 5', {draftReview: null}), {holdAfter: true, reply: '返事', lines: [{type: 'system', subtype: 'init', session_id: 'x'}]});
  await page.fill('#input', '依頼');
  await page.press('#input', 'Enter');
  // 画面 5 の draftReview の null は、インターフェース設計書の章 2 の表で、下書きを作っている間と、下書きがまだないとき
  check('draftReview が null の組は state-contract に合う', stateContractGaps(sample('画面 5', {draftReview: null})).length === 0);
  check('下書きを作っている間の表示を出す', await waitHear(page, '要件定義書を書いています') && (await hearBody(page)).includes('defining-skill-requirements が書いています。書き終わると、ここに出ます。'));
  fs.rmSync(hold + '-after');
  check('下書きがまだないときの表示を出す', await waitHear(page, '要件定義書はまだありません'));
  writeState(sample('画面 5'));
  check('見出しの文を出す', await waitHear(page, 'この内容で要件定義書を書いてよいですか？'));
  const body = await hearBody(page);
  check('数の文を出す', body.includes('あなたの文章から 1 個、質問の答えで 1 個、AI の調査で 1 個です。'), body);
  check('先に確かめる行を先頭に出す', body.indexOf('先に確かめる行') < body.indexOf('あなたの文章から決まった内容') && body.includes('終わったことの見分け方'), body);
  check('4 つの見出しでカードを分ける', ['あなたの文章から決まった内容', '質問で答えた内容', 'AI の案で決まった内容', 'AI が調べた内容'].every(t => body.includes(t)), body);
  check('値を開かずに読める', body.includes('summarizing-meeting-minutes'), body);
  check('承認の下の文を出す', (await text(page, '#hearfoot .fq')) === '先に確かめる行を見て、承認してください。\n全文はその下に続きます。', await text(page, '#hearfoot .fq'));
  // ボタン「この項目の画面へ」は、見出し「あなたの文章から決まった内容」と「質問で答えた内容」にだけ出る
  const backOf = t => page.locator('#hearbody section.zsec', {has: page.locator('h3', {hasText: t})}).locator('button', {hasText: 'この項目の画面へ'}).count();
  check('「AI の案で決まった内容」と「AI が調べた内容」に「この項目の画面へ」を出さない', (await backOf('AI の案で決まった内容')) === 0 && (await backOf('AI が調べた内容')) === 0 && (await page.locator('#hearbody button', {hasText: 'この項目の画面へ'}).count()) === 2);
  check('段階の帯に「承認待ち」を添える', (await text(page, '#stages .pill.now')).includes('承認待ち'));
  await hearButton(page, '内容を修正する').click();
  check('調べた内容のほかの値が入力欄に変わる', await waitHear(page, '違うところを、その場で直してください。') && (await page.locator('#hearbody .ze textarea').count()) === 3);
  await page.getByLabel('あなたが確かめる時点').fill('書いたあと');
  fs.writeFileSync(hold, '');
  planNext(sample('画面 5'));
  await hearButton(page, 'この内容に直す').click();
  check('AI の選択肢の語と、変えた行だけを送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n直す\nあなたが確かめる時点\n前の値: 書く前\n後の値: 書いたあと`, lastCall().stdin);
  check('読み直している間の表示を出す', await waitHear(page, 'AI が「あなたが確かめる時点」を読み直しています'));
  fs.rmSync(hold);
  check('もう一度修正するを出す', await until(async () => (await hearButton(page, 'もう一度修正する').count()) === 1));
  await until(() => hearButton(page, '承認する').isEnabled());
  // T20: 見出し「質問で答えた内容」は、AI に送らず、画面の中で「これまでの答えの一覧」を出す
  await page.locator('#hearbody button', {hasText: 'この項目の画面へ'}).nth(1).click();
  check('見出し「質問で答えた内容」の「この項目の画面へ」は、AI に送らず、これまでの答えの一覧を出す', await waitHear(page, 'これまでの答え') && calls().length === 2, String(calls().length));
  await hearButton(page, '下書きに戻る').click();
  await waitHear(page, 'この内容で要件定義書を書いてよいですか？');
  planNext(null);
  await page.locator('#hearbody button', {hasText: 'この項目の画面へ'}).first().click();
  check('ほかの見出しの「この項目の画面へ」は、見出しを添えて送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\n直す\n「あなたの文章から決まった内容」の画面へ戻る`, lastCall().stdin);
  await waitIdle(page);
  await until(() => hearButton(page, '承認する').isEnabled());
  fs.writeFileSync(hold, '');
  planNext(null);
  await hearButton(page, '承認する').click();
  check('承認の文を送る', await nextCall(4) && lastCall().stdin === `画面: ${work}\n承認する(推奨)`, lastCall().stdin);
  fs.rmSync(hold);
});

testCase('画面 4 の複数を選べる問い', async page => {
  check('作業が決まる', await startWork(page, sample('画面 4 の語の定義')));
  await waitHear(page, 'スキルが読むものを');
  const multi = page.locator('#hearbody fieldset').nth(1);
  const box = name => multi.locator('.zop', {hasText: name}).locator('input');
  check('multiple が true の問いはチェックにする', (await multi.locator('input[type=checkbox]').count()) === 3);
  check('multiple が false の問いは 1 つだけ選ぶ形にする', (await page.locator('#hearbody fieldset').first().locator('.zops input[type=radio]').count()) === 3);
  check('推奨を初めから選ぶ', await box('議事録').isChecked());
  await box('メモ').click();
  check('2 つを選べる', await box('議事録').isChecked() && await box('メモ').isChecked());
  await multi.locator('.zop', {hasText: 'ない'}).click();
  check('「ない」を選ぶと、ほかを選べない', await box('ない').isChecked() && !(await box('議事録').isChecked()) && !(await box('メモ').isChecked()));
  await box('メモ').click();
  check('ほかを選ぶと、「ない」を外す', await box('メモ').isChecked() && !(await box('ない').isChecked()));
  await box('議事録').click();
  await page.locator('#hearbody fieldset').first().locator('.zop', {hasText: '1 つのファイルにまとめる'}).click();
  planNext(null);
  await hearButton(page, '回答を送る').click();
  check('選んだ選択肢を読点で連ねて送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n1: 1 つのファイルにまとめる(必ず入れる部分: 画面の一覧、画面の遷移)\n2: メモ、議事録(推奨)`, lastCall().stdin);
  await waitIdle(page);
});

testCase('画面 4 の語の定義の欄', async page => {
  check('作業が決まる', await startWork(page, sample('画面 4 の語の定義')));
  await waitHear(page, '基本設計書');
  const first = page.locator('#hearbody fieldset').first();
  const parts = first.locator('[data-field=parts]');
  const files = first.locator('[data-field=files]');
  check('選ぶ前は、どちらの欄も出さない', !(await parts.isVisible()) && !(await files.isVisible()));
  await first.locator('.zop', {hasText: '1 つのファイルにまとめる'}).click();
  check('「1 つのファイルにまとめる」で必ず入れる部分の欄を出し、初めからすべて選ぶ', await parts.isVisible() && !(await files.isVisible()) && (await parts.locator('input:checked').count()) === 2);
  check('必ず入れる部分の欄に名前と出典を出す', (await parts.innerText()).includes('画面の一覧') && (await parts.innerText()).includes('docs/設計/基本設計書.md(3 行目)') && (await parts.innerText()).includes('AI の案'));
  await first.locator('.zop', {hasText: '分けて、いつも一緒に作る'}).click();
  check('分ける選択肢で要るファイルの欄を出す', await files.isVisible() && !(await parts.isVisible()));
  check('要るファイルの欄に主な部分を出す', (await files.innerText()).includes('主な部分: 画面の遷移'));
  // 回の最後のページなので、「次へ」の代わりに「回答を送る」を出す(画面遷移設計書の章 5.1)
  const go = hearButton(page, '回答を送る');
  check('要るファイルが 1 件以下の間は、知らせを出し、「回答を送る」を押せない', await go.isDisabled() && await files.locator('.zfw').isVisible());
  await files.locator('.zfr', {hasText: '画面遷移.md'}).locator('input').click();
  check('要るファイルが 2 件になると、「回答を送る」を押せる', await go.isEnabled() && !(await files.locator('.zfw').isVisible()));
  await first.locator('.zop', {hasText: '1 つのファイルにまとめる'}).click();
  await parts.locator('.zfr', {hasText: '画面の遷移'}).locator('input').click();
  await parts.locator('textarea').fill('用語集');
  planNext(null);
  await go.click();
  check('欄の答えを問いの答えの後ろの括弧で送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n1: 1 つのファイルにまとめる(必ず入れる部分: 画面の一覧、用語集)\n2: 議事録(推奨)`, lastCall().stdin);
  await waitIdle(page);
});

testCase('画面 5 の確かめる点', async page => {
  check('作業が決まる', await startWork(page, sample('画面 5 の確かめる点')));
  check('確かめる点を先に確かめる行の前に出す', await waitHear(page, '確かめる点') && (await hearBody(page)).indexOf('確かめる点') < (await hearBody(page)).indexOf('先に確かめる行'));
  check('読みの候補を、読点で分けずに選択肢にする', (await page.locator('#hearbody .zop').count()) === 2 && (await hearBody(page)).includes('担当者と期限を持つ、決まったものだけ'));
  check('「承認する」の代わりに「読みを選んで続ける」を出す', (await hearButton(page, '承認する').count()) === 0);
  check('ボタンの横の文は、確かめる点の読みを選ぶことを言う', (await text(page, '#hearfoot .fq')) === '確かめる点の読みを選んでください。');
  const go = hearButton(page, '読みを選んで続ける');
  check('選ぶまで押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: '決まっていない項目もすべて'}).click();
  check('選ぶと押せる', await go.isEnabled());
  planNext(null);
  await go.click();
  check('語と項目の組と選んだ読みを送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n読みを選んで続ける(推奨)\n確かめる点: 宿題(スキルが出すもの): 決まっていない項目もすべて`, lastCall().stdin);
  await waitIdle(page);
  // 本物の AI は、確かめる点を state.json に書かず、選択肢と会話の文だけで出した(2026-11-02 の通し)。「承認する」は AI の選択肢にないので出さない
  const noRows = sample('画面 5');
  noRows.decision = {question: 'この内容で要件定義書を書いてよいですか？', choices: ['読みを選んで続ける(推奨)', '直す', 'やめる'], replies: []};
  fs.appendFileSync(path.join(workPath, 'ui', 'conversation.md'), 'Claude Code: **確かめる点: 宿題(部分)**\n- 読みの候補: 期限を書き、担当者も書く、期限だけを書く\n\n');
  writeState(noRows);
  check('state.json に確かめる点がないときも、AI の文の確かめる点を出す', await waitHear(page, '確かめる点: 宿題(部分)') && (await hearBody(page)).includes('読みの候補: 期限を書き、担当者も書く、期限だけを書く'));
  check('AI の選択肢にない「承認する」を出さない', (await hearButton(page, '承認する').count()) === 0);
  check('AI の文の確かめる点でも、ボタンの横の文は読みを選ぶことを言う', (await text(page, '#hearfoot .fq')) === '確かめる点の読みを選んでください。');
  const go2 = hearButton(page, '読みを選んで続ける');
  check('読みを書くまで押せない', await go2.isDisabled());
  await page.getByLabel('確かめる点: 宿題(部分) の読み').fill('期限だけを書く');
  check('読みを書くと押せる', await go2.isEnabled());
  planNext(null);
  await go2.click();
  check('語と項目の組と書いた読みを送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\n読みを選んで続ける(推奨)\n確かめる点: 宿題(部分): 期限だけを書く`, lastCall().stdin);
});

// 2026-11-20: defining-skill-requirements の step 9-1 は、「追加」の行が問いを持つとき、その塊に問いの文と選択肢を出し、答えを受け取る。
// 画面は、draftReview.checkFirst の要素の question と choices で問いを出し、承認の文に「<行の名前>: <選んだ値>」の行を添える
testCase('画面 5 の先に確かめる行の問い', async page => {
  const base = sample('画面 5');
  const asked = sample('画面 5', {draftReview: {...base.draftReview, checkFirst: [
    {name: 'うまくいかなかったときの終わり方(変更)', value: '議事録を読めないときは、場所を示して止まる'},
    {name: '終わったことの見分け方(追加)', value: '見出し「決定事項」を持つ Markdown のファイル', question: '見分け方に、見出し「宿題」も入れますか？', choices: ['入れる(推奨)', '入れない']},
  ]}});
  check('問いを持つ checkFirst の組は state-contract に合う', stateContractGaps(asked).length === 0, stateContractGaps(asked).join(' / '));
  check('作業が決まる', await startWork(page, asked));
  check('「追加」の行に問いの文を出す', await waitHear(page, '見分け方に、見出し「宿題」も入れますか？') && (await hearBody(page)).includes('終わったことの見分け方(追加)'));
  check('問いの選択肢を出す', (await page.locator('#hearbody .zop').count()) === 2);
  check('ボタンの横の文は、問いに答えることを言う', (await text(page, '#hearfoot .fq')) === '先に確かめる行の問いに答えてから、承認してください。\n全文はその下に続きます。', await text(page, '#hearfoot .fq'));
  await waitIdle(page);
  const go = hearButton(page, '承認する');
  check('問いに答えるまで「承認する」を押せない', await go.isDisabled());
  await page.locator('#hearbody .zop', {hasText: '入れない'}).click();
  check('答えると「承認する」を押せる', await until(() => go.isEnabled(), 3000));
  planNext(sample('画面 5', {draftReview: {...base.draftReview, checkFirst: []}}));
  await go.click();
  check('承認の文に、ラベルを除いた行の名前と選んだ値の行を添えて送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n承認する(推奨)\n終わったことの見分け方: 入れない`, lastCall().stdin);
  // 先に確かめる行の塊は、その行が 1 件以上のときに出る。0 件のときのボタンの横の文は「下書きの全文を見て、承認してください。」である
  check('先に確かめる行が 0 件のときは、その塊を出さない', await until(async () => !(await hearBody(page)).includes('先に確かめる行')) && (await hearBody(page)).includes('この内容で要件定義書を書いてよいですか？'), await hearBody(page));
  check('先に確かめる行が 0 件のときの、ボタンの横の文', (await text(page, '#hearfoot .fq')) === '下書きの全文を見て、承認してください。', await text(page, '#hearfoot .fq'));
  await waitIdle(page);
});

testCase('画面 6 の全文とダウンロード', async page => {
  check('作業が決まる', await startWork(page, sample('画面 6'), {skill: 'defining-skill-requirements', files: {[`${work}/要件定義書.md`]: '# 議事録の要約の要件定義書\n\n| 列 |\n|---|\n| 値 |\n', [`${work}/聞き取りの記録.md`]: '# 聞き取りの記録\n'}}));
  check('見出しを出す', await waitHear(page, '要件定義書を書きました。'));
  check('スキルを呼んだあとでも、AI が待っている間のヘッダーは「要件定義書を書き終えました」', await until(async () => (await visible(page, '#running')) && (await text(page, '#running')) === '要件定義書を書き終えました'), await text(page, '#running').catch(() => ''));
  check('書き終えたヘッダーに回る印を出さない', (await page.locator('#running .spin').count()) === 0);
  const body = await hearBody(page);
  check('役目の文と書き終えた知らせを出す', body.includes('次の作業へ進む前に、全文を読めます。') && body.includes('書き終えました。'), body);
  check('要件定義書の全文を md の形で出す', (await page.locator('#hearbody .zdoc h1').innerText()) === '議事録の要約の要件定義書' && (await page.locator('#hearbody .zdoc table').count()) === 1);
  check('文書の場所を出す', (await text(page, '#hearfoot .zpth')) === `${work}/要件定義書.md`);
  check('downloads のすべてをボタンに出す', (await page.locator('#hearfoot a').count()) === 2, await page.locator('#hearfoot a').count());
  for (const [name, body] of [['要件定義書.md', '# 議事録の要約の要件定義書'], ['聞き取りの記録.md', '# 聞き取りの記録']]) {
    const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#hearfoot a', {hasText: name}).click()]);
    check(`${name} をダウンロードする`, download.suggestedFilename() === name && fs.readFileSync(await download.path(), 'utf8').startsWith(body), download.suggestedFilename());
  }
  fs.writeFileSync(hold, '');
  planNext(makeState({stage: 2, documentPath: '分割設計書.md'}));
  await hearButton(page, '次の作業へ進む(分割設計書)').click();
  check('次の作業へ進む文を送る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n次の作業へ進む(分割設計書)`, lastCall().stdin);
  check('AI が返事を書いている間のヘッダーは、回る印と「要件定義書を作っています」', await until(async () => (await text(page, '#running')) === '要件定義書を作っています' && (await page.locator('#running .spin').count()) === 1), await text(page, '#running'));
  fs.rmSync(hold);
  // 段階 2 で decision がない state.json は、中央のカードの待つの画面(K1)。画面 1 と同じ形で、会話は下の 1 行(画面遷移設計書の章 4.1)
  check('段階 2 の state.json で K1(中央のカードの待つの画面)になる', await until(async () => (await visible(page, '#hear')) && !(await visible(page, '#preview')) && (await hearBody(page)).includes('AI は、分割設計書を作っています')));
  check('下の 1 行に入力欄と「会話の記録」が残る', await visible(page, '#input') && await visible(page, '#recordopen'));
  check('段階 2 の帯は段階の表の語を出す', (await text(page, '#stages .pill.now')).includes('分割設計書'));
  check('段階 2 の接続の状態は「AI に接続中」', await until(async () => (await text(page, '#conn')) === 'AI に接続中'));
});

testCase('下の 1 行と会話の記録', async page => {
  // 画面遷移設計書の章 12 の行「聞き取りの画面で、選択肢を持たない問いを受けたとき」: 選択肢が 0 件の問いは、聞き返し(askBack が true)として置き、返答の候補は聞き返しの文の下に出る
  check('作業が決まる', await startWork(page, sample('画面 2', {decision: {question: '部長も読む人に入れますか？', choices: [], replies: ['入れる', '入れない'], askBack: true}})));
  await waitHear(page, 'というスキルですね？');
  check('選択肢のない聞き返しを本文の先頭に出し、下の 1 行の上に同じ問いを出さない', await until(async () => (await page.locator('#hearbody > *').first().innerText()).includes('部長も読む人に入れますか？')) && !(await visible(page, '#replies')));
  await page.locator('#hearbody .zchip', {hasText: '入れない'}).click();
  check('候補を押すと聞き返しの入力欄に入り、送らない', (await page.getByLabel('AI の問いの答え').inputValue()) === '入れない' && calls().length === 1);
  await page.fill('#input', '足りないことを書き足す');
  planNext(null, {reply: 'AI は、あなたの文を読みました。決まった内容と質問の数は変わりません。'});
  await page.press('#input', 'Enter');
  check('下の 1 行の文が AI に渡る', await nextCall(2) && lastCall().stdin === `画面: ${work}\n足りないことを書き足す`, lastCall().stdin);
  check('送ると入力欄が空になる', (await page.inputValue('#input')) === '');
  check('AI の返事を下の 1 行の上に出す', await until(async () => (await visible(page, '#strip')) && (await text(page, '#strip')).includes('決まった内容と質問の数は変わりません。')));
  check('会話の記録は閉じたまま', !(await visible(page, '#messages')));
  await openRecord(page);
  check('「会話の記録」で記録を開く', await waitVisible(page, '#messages .msg.user') && (await text(page, '#messages')).includes('足りないことを書き足す'));
  await page.click('#recordclose');
  check('「閉じる」で記録を閉じる', await waitHidden(page, '#messages'));
  await page.click('#recordopen');
  await page.click('#recordopen');
  check('「会話の記録」をもう一度押すと閉じる', await waitHidden(page, '#messages'));
  writeState(sample('画面 2'));
  await until(() => page.evaluate(() => state.decision.choices.length === 2));
  await until(() => hearButton(page, 'はい').isEnabled());
  await stopServer();
  await until(async () => (await text(page, '#conn')) === '中継サーバーにつながりません');
  await hearButton(page, 'はい').click();
  check('送れないときは「読み直せませんでした」と「もう一度送る」を出す', await until(async () => (await visible(page, '#strip')) && (await text(page, '#strip')).includes('読み直せませんでした') && (await page.locator('#strip button', {hasText: 'もう一度送る'}).count()) === 1));
  await startServer();
  await until(async () => (await text(page, '#conn')).endsWith('接続中'));
  planNext(null);
  await page.locator('#strip button', {hasText: 'もう一度送る'}).click();
  check('「もう一度送る」で同じ文を送る', await nextCall(3) && lastCall().stdin === `画面: ${work}\nはい(推奨)`, lastCall().stdin);
});

testCase('形の違う state.json: 聞き取りのキー', async page => {
  // キーの組はインターフェース設計書の章 2 の表に合わせ(必須のキーだけが null でなく、選択肢の画面は選択肢を 1 件以上持つ)、必須のキーの中の形だけを壊す。
  // 組が表に合わないときは、ケース「画面の状態の組が表に合わないとき」で確かめる
  const pick = choices => ({question: '問い', choices, replies: []});
  check('作業が決まる', await startWork(page, makeState({screen: '画面 2', summary: 'こわれた値', decision: pick(['はい(推奨)', '違う'])})));
  check('画面 2 はまとめがないときの文を出す', await waitHear(page, 'AI は、あなたの文章だけでは、スキルをまとめられませんでした。'));
  check('「あなたの文章に書き足す」を出す', (await hearButton(page, 'あなたの文章に書き足す').count()) === 1);
  for (const [screen, word, over] of [
    ['調査', 'AI が調べています', {research: {rows: 'x'}}],
    ['画面 3', '質問へ進む', {factCheck: 'x', decision: pick(['合っています。質問へ進む(推奨)', '内容を修正する'])}],
    ['画面 5', '要件定義書はまだありません', {draftReview: 5, decision: pick(['承認する(推奨)', '直す'])}],
  ]) {
    const st = makeState({screen, ...over});
    check(`${screen}: 置いた組は state-contract に合う`, stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
    writeState(st);
    const shown = await until(async () => ((await hearBody(page)) + (await text(page, '#hearfoot').catch(() => ''))).includes(word));
    check(`${screen} は値が欠けていても止まらない`, shown);
  }
  writeState(makeState({screen: '知らない画面', documentPath: '要件定義書.md'}));
  check('知らない screen は前の形の画面を出す', await until(async () => (await visible(page, '#preview')) && !(await visible(page, '#hear'))));
  writeState(makeState({screen: null}));
  check('screen が null は前の形の画面を出す', await until(async () => (await visible(page, '#preview')) && !(await visible(page, '#hear'))));
});

testCase('聞き取りの画面の続きからと、前の会話を続けられないとき', async page => {
  check('作業が決まる', await startWork(page, sample('画面 3')));
  await waitHear(page, 'ここでは 3 個を確かめます。');
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  await page.locator('#works .wk button', {hasText: '続きから'}).click();
  check('「続きから」で同じ聞き取りの画面を出す', await waitHear(page, 'ここでは 3 個を確かめます。'));
  fs.rmSync(sessionPath);
  await stopServer();
  await startServer();
  await page.reload();
  await openWorks(page);
  await page.locator('#works .wk button', {hasText: '続きから'}).click();
  check('前の会話を続けられない文を出す', await waitHear(page, '前の会話を続けられないので、新しい会話で始めます。') && (await hearBody(page)).includes('成果物のパス(要件定義書、分割設計書、構成の案、テスト計画書、判定の記録のどれか)を、下の 1 行で送ってください。'));
  check('確かめる一覧と主なボタンを出さない', !(await hearBody(page)).includes('ここでは 3 個を確かめます。') && (await page.locator('#hearfoot .btn.pri').count()) === 0);
});

// 画面が、書いた state.json を読み、その screen の画面を描き終えるまで待つ。描く前に「出さない」を確かめて合格にしないため
const drawn = (page, screen, body) => until(async () => (await page.evaluate(() => last.state)) === body && (await page.locator('#hearbody').getAttribute('data-screen')) === screen, 6000);
// 2026-11-06 に画面 4 で「前へ」を押したあと、AI が書いた state.json(output/2026-11-06-0839/ui/state.json の写し)
const backFixture = JSON.parse(fs.readFileSync(path.join(testsDir, 'fixtures', '画面 4 で前へを押したあとの state.json'), 'utf8'));

// 画面遷移設計書の章 12 の表の行「インターフェース設計書の章 2 の表に合わない組を受けたとき」
testCase('画面の状態の組が表に合わないとき', async page => {
  check('作業が決まる', await startWork(page, sample('画面 4')));
  await waitHear(page, '作業の範囲');
  const noItems = {...threeQuestions(), items: []};
  for (const [name, st, word] of [
    ['調べるための問い(questions が null)', makeState({screen: '調べるための問い', questions: null}), '調べる前に聞くことはありません'],
    ['調べるための問い(items が 0 件)', makeState({screen: '調べるための問い', questions: noItems}), '調べる前に聞くことはありません'],
    ['画面 4(questions が null)', makeState({screen: '画面 4', questions: null}), '質問はありません'],
    ['画面 4(items が 0 件)', makeState({screen: '画面 4', questions: noItems}), '質問はありません'],
    ['画面 4(前へを押したあとの実物)', backFixture, '質問はありません'],
  ]) {
    check(`${name}: 置いた組は state-contract に合わない`, stateContractGaps(st).length > 0);
    const body = JSON.stringify(st);
    writeState(body);
    check(`${name}: 画面が置いた組を読み終える`, await drawn(page, st.screen, body));
    const shown = (await hearBody(page)) + '\n' + (await page.locator('#hearfoot').innerText());
    check(`${name}: 組から推した文を出さない`, !shown.includes(word), shown.slice(0, 200));
    check(`${name}: 「画面の状態が設計と合いません」の 1 文を出す`, shown.includes('画面の状態が設計と合いません'), shown.slice(0, 200));
    const leaveOn = await page.evaluate(() => [...document.querySelectorAll('#hearfoot button')].filter(b => !b.disabled).map(b => b.innerText.trim()));
    check(`${name}: 下の段は「あとで続ける」と「やめる」だけを出し、押せる`, leaveOn.join('、') === 'あとで続ける、やめる' && (await page.locator('#hearfoot button').count()) === 2, leaveOn.join('、'));
    if (st.decision) {
      const asked = st.decision.question.split('\n').at(-1);
      check(`${name}: decision の問いを本文に出す`, (await hearBody(page)).includes(asked), asked);
    }
  }
});

// 画面遷移設計書の章 12 の表の行「聞き返しの出し方」と、K2、K5、K6、K7(インターフェース設計書の章 3 の decision)
testCase('聞き返しの出し方', async page => {
  check('作業が決まる', await startWork(page, sample('画面 4')));
  await waitHear(page, '作業の範囲');
  // 聞き返しの下に残る、いまの画面の本文の語
  const own = {'画面 4': '作業の範囲', '調べるための問い': '調べる前に教えてください', '画面 3': 'ここでは 3 個を確かめます', '画面 5': 'この内容で要件定義書を書いてよいですか？'};
  for (const [screen, word] of Object.entries(own)) for (const n of [0, 2]) {
    const name = `${screen}、選択肢 ${n} 件`;
    const decision = {question: `聞き返しの文(${name})`, choices: n ? ['直し方を変えて続ける', '中止する'] : [], replies: [], askBack: true};
    // 聞き返しの間は、screen と questions と必須のキーを聞き返しの前の値のまま置く(インターフェース設計書の章 3)
    const st = sample(screen, {decision});
    check(`${name}: 置いた組は state-contract に合う`, stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
    const body = JSON.stringify(st);
    writeState(body);
    check(`${name}: 画面が置いた組を読み終える`, await drawn(page, screen, body));
    const top = await page.evaluate(() => {
      const kids = [...document.getElementById('hearbody').children];
      const first = kids[0];
      const rest = kids.slice(1).flatMap(k => [...k.querySelectorAll('input, textarea, button')]);
      return {text: first ? first.innerText : '', buttons: first ? [...first.querySelectorAll('button, input[type=radio]')].map(b => (b.innerText || b.closest('label')?.innerText || '').trim()) : [], fields: first ? first.querySelectorAll('textarea, input[type=text]').length : 0, restOn: rest.filter(x => !x.disabled).length, footOn: [...document.querySelectorAll('#hearfoot .btn')].filter(b => !b.disabled).map(b => b.innerText), leaveOn: [...document.querySelectorAll('#hearfoot .pleave button')].filter(b => !b.disabled).map(b => b.innerText.trim())};
    });
    check(`${name}: 本文の先頭に聞き返しの文を出す`, top.text.includes(decision.question), top.text.slice(0, 120));
    if (n) check(`${name}: 本文の先頭に選択肢のボタンを出す`, decision.choices.every(c => top.buttons.some(b => b.includes(c))), top.buttons.join('、'));
    else check(`${name}: 本文の先頭に入力欄を出す`, top.fields > 0, top.fields);
    const all = await hearBody(page);
    check(`${name}: いまの画面の本文を聞き返しの下に残す`, all.includes(word) && all.indexOf(decision.question) >= 0 && all.indexOf(decision.question) < all.indexOf(word), all.slice(0, 120));
    check(`${name}: いまの画面の本文の入力とボタンを押せない`, top.restOn === 0, top.restOn);
    check(`${name}: いまの画面の下の段のボタンを押せない`, top.footOn.length === 0, top.footOn.join('、'));
    // 画面遷移設計書の章 11 の T22 と章 12: 下の段の「あとで続ける」と「やめる」は押せるまま残す
    check(`${name}: 下の段の「あとで続ける」と「やめる」だけを押せる`, top.leaveOn.join('、') === 'あとで続ける、やめる', top.leaveOn.join('、'));
  }
});

// 画面遷移設計書の章 5 の行「問いを作る回」の 2 段目: 3 カテゴリーの問いを 1 つの questions.items にカテゴリーの順に並べ、要素ごとに category を持つ(インターフェース設計書の章 2)
const stage2Item = (number, text, category, choices = []) => ({...sample('画面 4').questions.items[2], number, text, category, choices, results: choices.map(c => `これを選ぶと、スキルは、${c}を減らします。`), reason: '理由の文です。', example: null, answer: null, previousAnswer: null, multiple: false});
const stage2 = () => sample('画面 4', {questions: {title: '目的とすること', added: 0, removed: 0, notice: '調べ直した結果: docs/議事録/ の 12 件は、どれも見出しを持ちます。', items: [
  stage2Item(4, 'このスキルで楽にしたいことは何ですか。', '目的とすること', ['要約を書く手間', '読み返す手間']),
  stage2Item(5, 'スキルを使う人は誰ですか。', '目的とすること'),
  stage2Item(6, 'スキルが扱う範囲はどこまでですか。', '作業の範囲', ['1 つの議事録', '複数の議事録']),
  stage2Item(7, 'スキルが終わったことを、何で見分けますか。', '合格と優先'),
]}});
const heading = page => text(page, '#hearbody .zt1');
const waitHead = (page, t, ms) => until(async () => (await visible(page, '#hearbody .zt1')) && (await heading(page)) === t, ms);
const legends = page => page.locator('#hearbody fieldset legend').allInnerTexts();
const pick = (page, label) => page.locator('#hearbody .zop', {hasText: label}).click();
const pickedOn = (page, label) => page.locator('#hearbody .zop', {hasText: label}).locator('input').isChecked();
const unknown = async (page, qText) => { const f = page.locator('#hearbody fieldset', {hasText: qText}); if (!(await f.locator('textarea').isVisible())) await f.locator('summary').click(); await f.getByRole('button', {name: '分からない'}).click(); };
// 1 つ目の回(画面 4 の見本、作業の範囲)の答えを書いた回と、2 段目の回を持つ回の一覧
const round1Answered = () => sample('画面 4').questions.items.map((i, k) => ({...i, answer: ['ない(推奨)', '書く前', 'なし'][k], replaced: false}));
const stage2After1 = () => { const st = stage2(); return {...st, rounds: [{kind: '1 段目', items: round1Answered()}, st.rounds.at(-1)]}; };
// 1 つ目の回(画面 4 の見本、作業の範囲)に答えて送り、2 段目の回の問いを出す
async function toStage2(page) {
  check('作業が決まる', await startWork(page, sample('画面 4')));
  await waitHear(page, '作業の範囲');
  await pick(page, '書く前');
  await page.getByLabel('質問 3 の答え').fill('なし');
  check('モックの AI が書く 2 つの回の組は state-contract に合う', stateContractGaps(stage2After1()).length === 0, stateContractGaps(stage2After1()).join(' / '));
  planNext(stage2After1());
  await hearButton(page, '回答を送る').click();
  check('2 段目の 1 つ目のカテゴリーを出す', await waitHead(page, '目的とすること'));
  await waitIdle(page);
}

// T10-2 と T10、章 5 の表の下の段落、要件定義書の章 3.2(待っている表示)
testCase('画面 4 の 2 段目の 3 カテゴリーを送らずに切り替え、最後にまとめて送る', async page => {
  const st = stage2();
  check('モックの AI が書く 2 段目の組は state-contract に合う', stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
  check('作業が決まる', await startWork(page, st));
  check('見出しは、1 つ目のカテゴリーの名前', await waitHead(page, '目的とすること'));
  await waitIdle(page);
  const sent = calls().length;
  check('1 つ目のカテゴリーの問いだけを出す', JSON.stringify(await legends(page)) === JSON.stringify([st.questions.items[0].text, st.questions.items[1].text]), (await legends(page)).join(' / '));
  check('問いの番号は、いまのカテゴリーの問いで数える', (await hearBody(page)).includes('質問 1 から 2。'), await hearBody(page));
  check('1 つ目のカテゴリーには、知らせの行を出す', (await hearBody(page)).includes('調べ直した結果: docs/議事録/'));
  check('答えた問いがないときは「前へ」を出さない', (await hearButton(page, '前へ').count()) === 0);
  check('いまのカテゴリーに答えるまで「次へ」を押せない', await hearButton(page, '次へ').isDisabled());
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('議事録を書く人');
  check('いまのカテゴリーに答えると「次へ」を押せる', await until(() => hearButton(page, '次へ').isEnabled(), 3000));
  await hearButton(page, '次へ').click();
  check('最後でないカテゴリーの「次へ」で、次のカテゴリーを出す', await waitHead(page, '作業の範囲', 3000));
  check('2 つ目のカテゴリーの問いだけを出す', JSON.stringify(await legends(page)) === JSON.stringify([st.questions.items[2].text]), (await legends(page)).join(' / '));
  check('2 つ目のカテゴリーの番号は、前のカテゴリーの続きから数える', (await hearBody(page)).includes('質問 3。'), await hearBody(page));
  check('2 段目のカテゴリーの間では、知らせの行を出さない', !(await hearBody(page)).includes('調べ直した結果'));
  check('2 つ目のカテゴリーで「前へ」を出す', (await hearButton(page, '前へ').count()) === 1);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  check('3 つ目のカテゴリーを出す', await waitHead(page, '合格と優先', 3000));
  check('3 つ目のカテゴリーの番号', (await hearBody(page)).includes('質問 4。'), await hearBody(page));
  check('最後でないカテゴリーの「次へ」は AI に送らない', calls().length === sent, calls().length);
  await page.getByLabel('質問 7 の答え').fill('要約が保存された');
  // 中継サーバーの答えを 1.5 秒遅らせ、答えを待たずに待っている表示を出すことを確かめる
  await page.route('**/api/prompt', async route => { await sleep(1500); await route.continue(); });
  fs.writeFileSync(hold, '');
  planNext(sample('画面 5'));
  await hearButton(page, '回答を送る').click();
  check('送ったときに、中継サーバーの答えを待たずに待っている表示を出す', await waitHear(page, '次の質問を書いています', 1000) && calls().length === sent);
  check('最後のカテゴリーの「回答を送る」で、3 カテゴリーの答えを「番号: 答え」の行でまとめて送る', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n4: 要約を書く手間\n5: 議事録を書く人\n6: 1 つの議事録\n7: 要約が保存された`, lastCall().stdin);
  const body = await hearBody(page);
  check('受け取った答えに、すべてのカテゴリーの答えを出す', ['要約を書く手間', '議事録を書く人', '1 つの議事録', '要約が保存された'].every(a => body.includes(a)), body);
  await page.unroute('**/api/prompt');
  fs.rmSync(hold);
  check('AI の返事で下書きの画面へ進む', await waitHear(page, 'この内容で要件定義書を書いてよいですか？'));
});

// T11
testCase('画面 4 の 2 段目の 2 つ目のカテゴリーの前へ', async page => {
  await toStage2(page);
  const st = stage2();
  check('2 段目の 1 つ目のカテゴリーは、1 段目の答えのあとの番号から数える', (await hearBody(page)).includes('質問 4 から 5。'), await hearBody(page));
  await pick(page, '読み返す手間');
  await page.getByLabel('質問 5 の答え').fill('司会');
  await hearButton(page, '次へ').click();
  check('2 つ目のカテゴリーを出す', await waitHead(page, '作業の範囲', 3000) && (await legends(page)).includes(st.questions.items[2].text));
  await pick(page, '複数の議事録');
  const sent = calls().length;
  await hearButton(page, '前へ').click();
  check('2 つ目のカテゴリーの「前へ」で、前のカテゴリーを出す', await waitHead(page, '目的とすること', 3000));
  check('2 つ目のカテゴリーの「前へ」は AI に送らない', calls().length === sent, calls().length);
  check('前のカテゴリーの答えを入れたまま出す', await pickedOn(page, '読み返す手間') && (await page.getByLabel('質問 5 の答え').inputValue()) === '司会');
  await hearButton(page, '次へ').click();
  check('もう一度進むと、2 つ目のカテゴリーの答えも残る', await waitHead(page, '作業の範囲', 3000) && await pickedOn(page, '複数の議事録'));
  check('カテゴリーの間の「前へ」と「次へ」は AI に送らない', calls().length === sent, calls().length);
});

// T13 と、これまでの答えの一覧に送っていない 2 段目の答えを出すこと
testCase('画面 4 の 2 段目の「この質問に戻る」', async page => {
  await toStage2(page);
  const st = stage2();
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('議事録を書く人');
  await hearButton(page, '次へ').click();
  await waitHead(page, '作業の範囲', 3000);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  check('3 つ目のカテゴリーを出す', await waitHead(page, '合格と優先', 3000));
  const sent = calls().length;
  await page.locator('#hearfoot button', {hasText: 'これまでの答えの一覧'}).click();
  check('これまでの答えの一覧を出す', await waitHear(page, '直す質問を選んでください。'));
  const body = await hearBody(page);
  check('送った答えと、まだ送っていない 2 段目の答えを出す', body.includes('質問 1 ・ スキルが書き換えるか消すファイルはありますか。') && body.includes('質問 4 ・ このスキルで楽にしたいことは何ですか。') && body.includes('質問 6 ・ スキルが扱う範囲はどこまでですか。') && body.includes('議事録を書く人') && body.includes('1 つの議事録'), body);
  check('答えていない 2 段目の問いは一覧に出さない', !body.includes(st.questions.items[3].text), body);
  check('答えの一覧に 6 問を出す', (await page.locator('#hearbody button', {hasText: 'この質問に戻る'}).count()) === 6);
  await page.locator('#hearbody button', {hasText: 'この質問に戻る'}).nth(4).click();
  check('まだ送っていないカテゴリーの問いの「この質問に戻る」で、そのカテゴリーを出す', await waitHead(page, '目的とすること', 3000) && (await legends(page)).includes(st.questions.items[1].text));
  check('まだ送っていないカテゴリーの問いの「この質問に戻る」は AI に送らない', calls().length === sent, calls().length);
  check('戻ったカテゴリーの答えを入れたまま出す', await pickedOn(page, '要約を書く手間') && (await page.getByLabel('質問 5 の答え').inputValue()) === '議事録を書く人');
  await page.locator('#hearfoot button', {hasText: 'これまでの答えの一覧'}).click();
  await waitHear(page, '直す質問を選んでください。');
  await page.locator('#hearbody button', {hasText: 'この質問に戻る'}).first().click();
  check('送った回の問いの「この質問に戻る」で、その回のページを出す', await until(async () => (await legends(page)).includes(sample('画面 4').questions.items[0].text), 3000));
  check('送った回の問いの「この質問に戻る」も AI に送らない', calls().length === sent, calls().length);
});

// T25-2
testCase('画面 4 の 2 段目の「分からない」をまとめて送る', async page => {
  const st = stage2();
  check('作業が決まる', await startWork(page, st));
  await waitHead(page, '目的とすること');
  await waitIdle(page);
  const sent = calls().length;
  await unknown(page, st.questions.items[0].text);
  await page.getByLabel('質問 5 の答え').fill('司会');
  check('「分からない」を答えに入れると「次へ」を押せる', await until(() => hearButton(page, '次へ').isEnabled(), 3000));
  await hearButton(page, '次へ').click();
  check('「分からない」を書いたカテゴリーの「次へ」で、次のカテゴリーを出す', await waitHead(page, '作業の範囲', 3000));
  await unknown(page, st.questions.items[2].text);
  await hearButton(page, '次へ').click();
  await waitHead(page, '合格と優先', 3000);
  await unknown(page, st.questions.items[3].text);
  check('「分からない」は、まとめて送るまで AI に送らない', calls().length === sent, calls().length);
  planNext(null);
  await hearButton(page, '回答を送る').click();
  check('まとめて送るときに、ほかの答えと一緒に「番号: 分からない」を送る', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n4: 分からない\n5: 司会\n6: 分からない\n7: 分からない`, lastCall().stdin);
});

// 承認された設計の 3 と 5、画面遷移設計書の章 11 の T10-2 と T11: 「前へ」「次へ」は、回をまたいでも AI に送らずにページを切り替え、AI を待つ間も前のページを読める
testCase('回をまたぐ前へ', async page => {
  await toStage2(page);
  const first = sample('画面 4').questions.items;
  const sent = calls().length;
  check('2 段目の回の最初のページに「前へ」を出す', (await hearButton(page, '前へ').count()) === 1);
  await hearButton(page, '前へ').click();
  check('回の最初のページの「前へ」で、前の回のページを出す', await until(async () => (await legends(page)).includes(first[0].text), 3000));
  check('回をまたぐ「前へ」は AI に送らない', calls().length === sent, calls().length);
  check('前の回のページに、送った答えを入れたまま出す', (await page.getByLabel('質問 3 の答え').inputValue()) === 'なし' && await pickedOn(page, '書く前'));
  check('前の回のページの「次へ」は主でないボタン', (await hearButton(page, '次へ').count()) === 1 && !((await hearButton(page, '次へ').getAttribute('class')) || '').includes('pri'));
  await hearButton(page, '次へ').click();
  check('「次へ」で、次の回のページに戻る', await waitHead(page, '目的とすること', 3000) && calls().length === sent);
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('司会');
  await hearButton(page, '次へ').click();
  await waitHead(page, '作業の範囲', 3000);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  await waitHead(page, '合格と優先', 3000);
  await page.getByLabel('質問 7 の答え').fill('要約が保存された');
  fs.writeFileSync(hold, '');
  planNext(sample('画面 5'));
  await hearButton(page, '回答を送る').click();
  check('送ると待っている表示を出す', await waitHear(page, '次の質問を書いています'));
  check('待っている間も「前へ」を押せる', await until(() => hearButton(page, '前へ').isEnabled(), 3000));
  await hearButton(page, '前へ').click();
  check('待っている間に「前へ」で前のページを読める', await waitHead(page, '作業の範囲', 3000) && await pickedOn(page, '1 つの議事録'));
  check('待っている間は、答えの欄に書き込めない', await page.locator('#hearbody .zop input').first().isDisabled());
  fs.rmSync(hold);
  check('AI の返事で下書きの画面へ進む', await waitHear(page, 'この内容で要件定義書を書いてよいですか？'));
});

// 回の一覧の回は、どれも問いの番号 1 から始まる。画面の中の答えは、回の番号と問いの番号の組で持ち、「前へ」で前の回を開いても、前の回の答えを今の回の同じ番号の問いに入れない
testCase('回をまたぐ前へのあとに今の回の答えだけを送る', async page => {
  const items = [stage2Item(1, 'スキルを使う人は誰ですか。', '使う人と終わり'), stage2Item(3, 'スキルが終わったことを、何で見分けますか。', '使う人と終わり')];
  const st = sample('画面 4', {questions: {title: '使う人と終わり', added: 0, removed: 0, notice: null, items},
    rounds: [{kind: '1 段目', items: round1Answered()}, {kind: '2 段目', items: items.map(i => ({...i, replaced: false}))}]});
  check('モックの AI が書く 2 つの回の組は state-contract に合う', stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
  check('作業が決まる', await startWork(page, st));
  check('今の回のページを出す', await waitHead(page, '使う人と終わり'));
  await waitIdle(page);
  const sent = calls().length;
  await page.getByLabel('質問 3 の答え').fill('今の回の答え');
  await hearButton(page, '前へ').click();
  check('「前へ」で、前の回のページを出す', await waitHead(page, '作業の範囲', 3000));
  check('前の回の問い 3 には、前の回の答えだけを入れる', (await page.getByLabel('質問 3 の答え').inputValue()) === 'なし', await page.getByLabel('質問 3 の答え').inputValue());
  check('前の回の問い 2 には、前の回の答えを入れる', await pickedOn(page, '書く前'));
  await hearButton(page, '次へ').click();
  check('「次へ」で、今の回のページに戻る', await waitHead(page, '使う人と終わり', 3000));
  check('今の回の問い 3 には、今の回の答えを残す', (await page.getByLabel('質問 3 の答え').inputValue()) === '今の回の答え', await page.getByLabel('質問 3 の答え').inputValue());
  check('今の回の問い 1 には、前の回の答えを入れない', (await page.getByLabel('質問 1 の答え').inputValue()) === '', await page.getByLabel('質問 1 の答え').inputValue());
  await unknown(page, items[0].text);
  check('回をまたぐ「前へ」と「次へ」は AI に送らない', calls().length === sent, calls().length);
  planNext(null);
  await until(() => hearButton(page, '回答を送る').isEnabled(), 3000);
  await hearButton(page, '回答を送る').click();
  check('送る文は、今の回の答えだけを持つ', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n1: 分からない\n3: 今の回の答え`, lastCall().stdin);
});

// 画面遷移設計書の章 11 の T27: 「前へ」で開いた前の回の問いに書いた補足は、その問いの直した答えとして「直した答え <記録の番号>: <答え>」の行で送り、今の回の同じ番号の問いの答えに入れない。
// 画面の見本の問いは記録の番号(recordNumber)を持たない古い形なので、このケースは、記録の番号の代わりに回の中の問いの番号を送ることを確かめる。
// 本物の claude を使うテスト hearing-to-written は、「この質問に戻る」で開いた前の回の問い 1 に補足を書き、この形の送る文を受け取る
testCase('前の回の同じ番号の問いに書いた補足を、直した答えの行で送る', async page => {
  const prev = sample('画面 4').questions.items[0];
  const items = [stage2Item(1, 'スキルを使う人は誰ですか。', '使う人と終わり')];
  const st = sample('画面 4', {questions: {title: '使う人と終わり', added: 0, removed: 0, notice: null, items},
    rounds: [{kind: '1 段目', items: round1Answered()}, {kind: '2 段目', items: items.map(i => ({...i, replaced: false}))}]});
  check('モックの AI が書く 2 つの回の組は state-contract に合う', stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
  check('作業が決まる', await startWork(page, st));
  check('今の回のページを出す', await waitHead(page, '使う人と終わり'));
  await waitIdle(page);
  const sent = calls().length;
  await page.getByLabel('質問 1 の答え').fill('今の回の答え');
  await hearButton(page, '前へ').click();
  check('「前へ」で、前の回のページを出す', await waitHead(page, '作業の範囲', 3000));
  const f = page.locator('#hearbody fieldset', {hasText: prev.text});
  if (!(await f.locator('textarea').isVisible())) await f.locator('summary').click();
  await f.locator('textarea').fill('前の回の補足');
  await hearButton(page, '次へ').click();
  check('「次へ」で、今の回のページに戻る', await waitHead(page, '使う人と終わり', 3000));
  check('今の回の問い 1 には、前の回の問い 1 の補足を入れない', (await page.getByLabel('質問 1 の答え').inputValue()) === '今の回の答え', await page.getByLabel('質問 1 の答え').inputValue());
  check('前の回の問いに補足を書いても AI に送らない', calls().length === sent, calls().length);
  planNext(null);
  await until(() => hearButton(page, '回答を送る').isEnabled(), 3000);
  await hearButton(page, '回答を送る').click();
  check('送る文は、今の回の答えの行のあとに、前の回の問い 1 の直した答えの行を、記録の番号を持たない問いなので回の中の番号で持つ', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n1: 今の回の答え\n直した答え 1: ない(推奨)(補足: 前の回の補足)`, lastCall().stdin);
});

// 画面遷移設計書の章 11 の T27: 直した答えの行は、聞き取りの記録の番号(recordNumber)で問いを指す。
// どの回も問い 1 を持つので、段階 1 のスキルは、記録の番号で、直された問いを見分ける
testCase('2 つの回の同じ番号の問いを直すと、直した答えの行がそれぞれの記録の番号を持つ', async page => {
  const recItem = (category, text, recordNumber, answer) => ({...stage2Item(1, text, category), recordNumber, answer, replaced: false});
  const r1 = recItem('渡すものと出すもの', 'スキルが読むものを、すべて挙げてください。', '6-1', '議事録のファイル 1 つ');
  const r2 = recItem('目的とすること', 'このスキルで、何を楽にしたいですか。', '24', '要約を書く手間');
  const now = recItem('作業の範囲', 'スキルが書き換えるか消すファイルはありますか。', '22', null);
  const {replaced, ...nowItem} = now;
  const st = sample('画面 4', {questions: {title: '作業の範囲', added: 0, removed: 0, notice: null, items: [nowItem]},
    rounds: [{kind: '1 段目', items: [r1]}, {kind: '2 段目', items: [r2]}, {kind: '追加の回', items: [now]}]});
  check('モックの AI が書く 3 つの回の組は state-contract に合う', stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
  check('作業が決まる', await startWork(page, st));
  check('今の回のページを出す', await waitHead(page, '作業の範囲'));
  await waitIdle(page);
  const sent = calls().length;
  await hearButton(page, '前へ').click();
  check('「前へ」で、1 つ前の回のページを出す', await waitHead(page, '目的とすること', 3000));
  await page.getByLabel('質問 1 の答え').fill('読み返す手間');
  await hearButton(page, '前へ').click();
  check('もう一度「前へ」で、最初の回のページを出す', await waitHead(page, '渡すものと出すもの', 3000));
  await page.getByLabel('質問 1 の答え').fill('議事録のフォルダ');
  check('2 つの回の問い 1 を直しても AI に送らない', calls().length === sent, calls().length);
  planNext(null);
  await page.fill('#input', '書き足す文');
  await page.press('#input', 'Enter');
  check('送る文は、2 つの直した答えの行を、回の順に、それぞれの記録の番号で持つ', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n書き足す文\n直した答え 6-1: 議事録のフォルダ\n直した答え 24: 読み返す手間`, lastCall().stdin);
});

// 承認された設計の 7:回の途中のページは主でない「次へ」、回の最後のページだけ主なボタン「回答を送る」とその横の文
testCase('回の最後のページの回答を送る', async page => {
  check('作業が決まる', await startWork(page, stage2()));
  await waitHead(page, '目的とすること');
  await waitIdle(page);
  const cls = async label => (await hearButton(page, label).getAttribute('class')) || '';
  check('回の途中のページは、「回答を送る」を出さず、主でない「次へ」を出す', (await hearButton(page, '回答を送る').count()) === 0 && (await hearButton(page, '次へ').count()) === 1 && !(await cls('次へ')).includes('pri'));
  check('回の途中のページは、ボタンの横の文を出さない', (await page.locator('#hearfoot .fq').count()) === 0);
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('議事録を書く人');
  await hearButton(page, '次へ').click();
  await waitHead(page, '作業の範囲', 3000);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  check('回の最後のページを出す', await waitHead(page, '合格と優先', 3000));
  check('回の最後のページは、「次へ」の代わりに主なボタン「回答を送る」を出す', (await hearButton(page, '次へ').count()) === 0 && (await hearButton(page, '回答を送る').count()) === 1 && (await cls('回答を送る')).includes('pri'));
  check('「回答を送る」の横に文を出す', (await text(page, '#hearfoot .fq')) === 'AI は、回答を読んで、次の画面を作ります。', await text(page, '#hearfoot .fq'));
  check('回の答えがそろうまで「回答を送る」を押せない', await hearButton(page, '回答を送る').isDisabled());
  await page.getByLabel('質問 7 の答え').fill('要約が保存された');
  check('回の答えがそろうと「回答を送る」を押せる', await until(() => hearButton(page, '回答を送る').isEnabled(), 3000));
  const sent = calls().length;
  planNext(null);
  await hearButton(page, '回答を送る').click();
  check('「回答を送る」で、回の答えを送る', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n4: 要約を書く手間\n5: 議事録を書く人\n6: 1 つの議事録\n7: 要約が保存された`, lastCall().stdin);
});

// 承認された設計の 1 と 4、画面遷移設計書の章 11 の T26 と T27: 送ったあとに直した答えをためて、次に AI を呼ぶ送信に添える
testCase('直した答えを次の送信に添える', async page => {
  await toStage2(page);
  const sent = calls().length;
  const q3 = sample('画面 4').questions.items[2];
  await hearButton(page, '前へ').click();
  await until(() => page.getByLabel('質問 3 の答え').isVisible(), 3000);
  await page.getByLabel('質問 3 の答え').fill('書き出すファイルの名前');
  check('答えを直しても AI に送らない', calls().length === sent, calls().length);
  const stored = JSON.parse((await page.evaluate(k => localStorage.getItem(k), `sf-hear:${work}`)) || '{}');
  check('直した答えを、作業のフォルダと、回の番号と問いの番号の組の鍵と、問いの文の組で localStorage に持つ', !!stored['0:3'] && stored['0:3'].text === q3.text && stored['0:3'].answer === '書き出すファイルの名前', JSON.stringify(stored));
  await hearButton(page, '次へ').click();
  await waitHead(page, '目的とすること', 3000);
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('司会');
  await hearButton(page, '次へ').click();
  await waitHead(page, '作業の範囲', 3000);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  await waitHead(page, '合格と優先', 3000);
  await page.getByLabel('質問 7 の答え').fill('要約が保存された');
  // AI は回を後ろに足すだけで、前の回の問いを書き換えない
  planNext(stage2After1());
  await hearButton(page, '回答を送る').click();
  check('回の答えのあとに、直した答えを、記録の番号を持たない古い形の問いなので「直した答え <回の中の問いの番号>: <答え>」の行で添える', await nextCall(sent + 1) && lastCall().stdin === `画面: ${work}\n4: 要約を書く手間\n5: 司会\n6: 1 つの議事録\n7: 要約が保存された\n直した答え 3: 書き出すファイルの名前`, lastCall().stdin);
  await waitIdle(page);
  await sleep(2500);
  planNext(null);
  await page.fill('#input', '書き足す文');
  await page.press('#input', 'Enter');
  check('送った直した答えは、次の送信に添えない', await nextCall(sent + 2) && lastCall().stdin === `画面: ${work}\n書き足す文`, lastCall().stdin);
  await waitIdle(page);
  await page.locator('#hearfoot button', {hasText: 'これまでの答えの一覧'}).click();
  await waitHear(page, '直す質問を選んでください。');
  await page.locator('#hearbody button', {hasText: 'この質問に戻る'}).first().click();
  await until(() => page.getByLabel('質問 3 の答え').isVisible(), 3000);
  check('送った直した答えを、答えの欄に残す', (await page.getByLabel('質問 3 の答え').inputValue()) === '書き出すファイルの名前', await page.getByLabel('質問 3 の答え').inputValue());
  await page.getByLabel('質問 3 の答え').fill('なしと書き直す');
  planNext(null);
  await page.fill('#input', '2 回目の書き足し');
  await page.press('#input', 'Enter');
  check('下の 1 行からの送信にも、たまった直した答えを添える', await nextCall(sent + 3) && lastCall().stdin === `画面: ${work}\n2 回目の書き足し\n直した答え 3: なしと書き直す`, lastCall().stdin);
});

// 承認された設計の 4: 開き直したときは、最後の回の、送る前の答えでも埋まっていない最初のカテゴリーを出す。すべて埋まっているときは最後のカテゴリー。2 つのタブは storage のイベントで読み直す
testCase('開き直したときに出すページ', async (page, context) => {
  check('作業が決まる', await startWork(page, stage2After1()));
  check('最初は、最後の回の、答えが埋まっていない最初のカテゴリーのページを出す', await waitHead(page, '目的とすること'));
  await waitIdle(page);
  await pick(page, '要約を書く手間');
  await page.getByLabel('質問 5 の答え').fill('議事録を書く人');
  await page.reload();
  check('開き直すと、送る前の答えで埋まったカテゴリーの次のページを出す', await waitHead(page, '作業の範囲', 8000));
  await hearButton(page, '前へ').click();
  check('開き直したあとも、送る前の答えを答えの欄に入れて出す', await waitHead(page, '目的とすること', 3000) && await pickedOn(page, '要約を書く手間') && (await page.getByLabel('質問 5 の答え').inputValue()) === '議事録を書く人');
  const other = await context.newPage();
  await other.goto(url);
  check('2 つ目のタブも、同じ決まりでページを出す', await until(async () => (await visible(other, '#hearbody .zt1')) && (await text(other, '#hearbody .zt1')) === '作業の範囲', 8000));
  await other.locator('#hearfoot button', {hasText: '前へ'}).click();
  await until(async () => (await text(other, '#hearbody .zt1')) === '目的とすること', 3000);
  await page.getByLabel('質問 5 の答え').fill('司会');
  check('もう 1 つのタブで書いた答えを、storage のイベントで読み直す', await until(async () => (await other.getByLabel('質問 5 の答え').inputValue()) === '司会', 5000));
  await other.close();
  await hearButton(page, '次へ').click();
  await waitHead(page, '作業の範囲', 3000);
  await pick(page, '1 つの議事録');
  await hearButton(page, '次へ').click();
  await waitHead(page, '合格と優先', 3000);
  await page.getByLabel('質問 7 の答え').fill('要約が保存された');
  await page.reload();
  check('すべて埋まっているときは、最後のカテゴリーのページを出す', await waitHead(page, '合格と優先', 8000));
  check('開き直したあとも、回の答えがそろっていれば「回答を送る」を押せる', await until(() => hearButton(page, '回答を送る').isEnabled(), 5000));
});

// 承認された設計の 2 と 3: 画面 5 の、これまでの答えの一覧の「直した答えを送る」
testCase('画面 5 の直した答えを送る', async page => {
  check('作業が決まる', await startWork(page, sample('画面 5')));
  await waitHear(page, 'この内容で要件定義書を書いてよいですか？');
  await waitIdle(page);
  await hearButton(page, 'これまでの答えの一覧').click();
  await waitHear(page, 'これまでの答え');
  const go = hearButton(page, '直した答えを送る');
  check('直した答えがないときは「直した答えを送る」を押せない', (await go.count()) === 1 && await go.isDisabled());
  await page.getByLabel('質問 5 の答え').fill('画面 5 で直した答え');
  check('答えを直すと「直した答えを送る」を押せる', await until(() => go.isEnabled(), 3000));
  planNext(null);
  await go.click();
  check('選択肢「直す」の文と、直した答えの行を送る(記録の番号を持たない古い形の問いなので、回の中の番号)', await nextCall(2) && lastCall().stdin === `画面: ${work}\n直す\n直した答え 5: 画面 5 で直した答え`, lastCall().stdin);
  await waitIdle(page);
  check('送ったあとは、直した答えがないので押せない', await until(() => go.isDisabled(), 5000));
});

async function main() {
  if (process.argv.includes('--list')) { for (const c of cases) console.log(c.name); return; }
  fs.mkdirSync(path.join(fake, 'bin'), {recursive: true});
  fs.writeFileSync(path.join(fake, 'bin', 'claude'), fakeScript, {mode: 0o755});
  fs.symlinkSync(process.execPath, path.join(fake, 'bin', 'node'));
  fs.mkdirSync(path.join(sf, 'ui'), {recursive: true});
  for (const f of ['server.mjs', 'index.html', 'デザイントークン.css', 'はじめに.md', '段階ごとのスキルと規約.json']) fs.copyFileSync(path.join(uiDir, f), path.join(sf, 'ui', f));
  browser = await chromium.launch();
  if (only && !cases.some(c => c.name === only)) { setCase('全体'); ng(`ケース ${only} がない`); }
  for (const c of cases) {
    if (only && only !== c.name) continue;
    console.log(`--- ${c.name}`);
    setCase(c.name);
    const failsBefore = totals.fail;
    const {context, page} = await freshCase(c.opts);
    try { await c.fn(page, context); }
    catch (e) { ng('途中で止まらない', e.message.split('\n')[0]); }
    // スクリプトのエラーを番号付きで確かめるケース(opts.errorsChecked)は、ここで確かめない
    if (!c.opts.errorsChecked) check('画面のスクリプトのエラーがない', page.caseErrors.length === 0, page.caseErrors.join(' / '));
    if (totals.fail > failsBefore && process.env.ARTIFACT_DIR) {
      fs.mkdirSync(process.env.ARTIFACT_DIR, {recursive: true});
      await page.screenshot({path: path.join(process.env.ARTIFACT_DIR, `${c.name.replace(/[^\p{L}\p{N}]+/gu, '-')}.png`)}).catch(() => {});
    }
    await context.close();
  }
}

main().catch(e => { setCase('全体'); ng('テストの実行', e.stack); }).finally(async () => {
  await stopServer();
  if (browser) await browser.close();
  fs.rmSync(tmp, {recursive: true, force: true});
  if (process.argv.includes('--list')) process.exit(0);
  process.exit(finish(cases.map(c => c.name), !only));
});
