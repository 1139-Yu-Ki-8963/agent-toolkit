#!/usr/bin/env node
// 本物の claude を使うテスト。時間と利用料がかかるので、ユーザーが実行を指示したときだけ流す。毎回自動の run-auto.sh は、このプログラムを呼ばない。
// 使い方: skill-factory/ で `node ui/tests/test-real.mjs <contract か hearing-screens か hearing-to-written か until-stage-3 か until-stage-8 か check-skill か session-lost> --yes`。`--yes` がないと、上限を出して終了コード 2 で止まる。
// contract は claude の入出力の形だけを確かめる。ほかの 6 つは画面と中継サーバーと本物の AI で流れを通す。`--list` でケースの名前を出す。
// 一時フォルダの skill-factory の写し(.claude のリンクをたどった実体)で動く。写しは終わったあとに確かめられるように残す。
// hearing-to-written は、環境変数 SF_REAL_CONTINUE に前の回の写しのパスと ARTIFACT_DIR に前の回の記録のフォルダを渡すと、前の回の会話の続きから流す。途中で止まった回の原因を直したあとに、初めから流す費用をかけずに確かめるためのもので、合格の判定は初めから流した回で行う。
import {spawn, spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {check, finish, freePort, setCase, sleep, totals, until} from './lib/report.mjs';
import {stateContractGaps} from './lib/state-contract.mjs';

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const uiDir = path.dirname(testsDir);
const factory = path.dirname(uiDir);
const scenario = process.argv[2];
const scenarioNames = {'hearing-screens': '依頼から画面 3 までの聞き取りの通し', 'hearing-to-written': '依頼から画面 6 までの聞き取りの通し', 'until-stage-3': '依頼から段階 3 まで', 'until-stage-8': '依頼から段階 8 の判定の記録まで', 'check-skill': '「<スキルの名前> を照合して」の流れ', 'session-lost': 'session.json を消して続きから始める流れ'};
const contractNames = ["claude --version","--session-id の呼び出しの形","--resume が同じ会話を続ける","ない会話の --resume の形","Skill のツールの呼び出しの形","サブエージェントの呼び出しと結果の形","acceptEdits でファイルを書ける"];
if (scenario === '--list') { for (const n of [...contractNames, ...Object.values(scenarioNames)]) console.log(n); process.exit(0); }
const limits = {
  contract: {minutes: 10, usd: 0.5, note: 'モデル haiku と sonnet。合わせて 7 回の呼び出し'},
  'hearing-screens': {minutes: 60, usd: 5, note: '依頼「コミットをまとめるskillを作る」から画面 3 の次の画面まで。モデル sonnet'},
  'hearing-to-written': {minutes: 180, usd: 5, totalUsd: 12, note: '依頼「コミットをまとめるskillを作る」から、全カテゴリーの問い、画面 5 の修正と承認、画面 6 まで。モデル sonnet。1 回の通しの費用の上限は 12 ドル'},
  'until-stage-3': {minutes: 60, usd: 5, note: '依頼から段階 3 に入るまで。モデル sonnet'},
  'until-stage-8': {minutes: 360, usd: 30, note: '依頼から段階 8 の判定の記録まで。モデル sonnet。最も時間と利用料がかかる'},
  'check-skill': {minutes: 30, usd: 3, note: '「<スキルの名前> を照合して」の流れ。モデル sonnet'},
  'session-lost': {minutes: 30, usd: 3, note: 'session.json を消して続きから始める流れ。モデル sonnet'},
};
if (!limits[scenario]) { console.log(`流すものを ${Object.keys(limits).join('、')} から選んでください`); process.exit(2); }
if (!process.argv.includes('--yes')) {
  console.log(`本物の claude を使います。${limits[scenario].note}。時間の上限は ${limits[scenario].minutes} 分、呼び出し 1 回の費用の上限は ${limits[scenario].usd} ドルです。`);
  console.log('ユーザーの指示があるときだけ、--yes を付けて流してください。');
  process.exit(2);
}
const deadline = Date.now() + limits[scenario].minutes * 60 * 1000;
const timer = setTimeout(() => { console.log(`時間の上限 ${limits[scenario].minutes} 分を超えたので止めます(判定できない)`); if (server) server.kill('SIGTERM'); process.exit(2); }, limits[scenario].minutes * 60 * 1000);
timer.unref();

const continuing = scenario === 'hearing-to-written' && !!process.env.SF_REAL_CONTINUE;
const tmp = continuing ? process.env.SF_REAL_CONTINUE : fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'sf-real.'));
console.log(`写し: ${tmp}`);

// claude を 1 回呼び、stream-json の行の配列を返す
function callClaude(args, input, cwd) {
  // spawnSync の間はタイマーが動かないので、呼び出しの前に時間の上限を確かめる
  if (Date.now() > deadline) { console.log('時間の上限を超えたので止めます(判定できない)'); process.exit(2); }
  const r = spawnSync('claude', ['-p', ...args, '--output-format', 'stream-json', '--verbose', '--permission-mode', 'acceptEdits', '--max-budget-usd', String(limits.contract.usd)], {cwd, input, encoding: 'utf8', timeout: 5 * 60 * 1000, maxBuffer: 64 * 1024 * 1024});
  const lines = (r.stdout || '').split('\n').filter(Boolean).flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } });
  return {code: r.status, lines, stderr: r.stderr};
}
const contents = lines => lines.filter(l => l.type === 'assistant').flatMap(l => (l.message && l.message.content) || []);

// 契約のテスト: モック(fake-claude.mjs)が真似ている形が、本物と同じかを確かめる
async function contract() {
  const cwd = path.join(tmp, 'contract');
  const skill = path.join(cwd, '.claude', 'skills', 'contract-skill');
  fs.mkdirSync(skill, {recursive: true});
  fs.writeFileSync(path.join(skill, 'SKILL.md'), '---\nname: contract-skill\ndescription: 契約のテストで呼ぶスキル\n---\n\n「スキルを呼びました」とだけ返す。\n');
  const version = spawnSync('claude', ['--version'], {encoding: 'utf8'});
  setCase('claude --version');
  check('claude --version は終了コード 0', version.status === 0, version.stderr);
  const id = randomUUID();
  // 語の意味を持つ部分を外す。「目印abc123」では、AI が語の部分だけを答えることがあった(2026-11-02 の実行で「abc123」を返した)
  const marker = `zq-${id.slice(0, 6)}`;
  const first = callClaude(['--session-id', id, '--model', 'haiku'], `${marker} を覚えて、はいとだけ答えて`, cwd);
  const init = first.lines.find(l => l.type === 'system' && l.subtype === 'init');
  setCase('--session-id の呼び出しの形');
  check('--session-id の呼び出しは system の init を出す', !!init, JSON.stringify(first.lines.slice(0, 2)));
  check('assistant の content に text がある', contents(first.lines).some(c => c.type === 'text' && typeof c.text === 'string'));
  check('result の行を出す', first.lines.some(l => l.type === 'result'));
  check('終了コードは 0', first.code === 0, first.stderr);
  const second = callClaude(['--resume', id, '--model', 'haiku'], '覚えた語をそのまま答えて', cwd);
  setCase('--resume が同じ会話を続ける');
  check('--resume は同じ会話を続ける(テストが決めた目印の語を答える)', contents(second.lines).some(c => c.type === 'text' && c.text.includes(marker)));
  const missing = callClaude(['--resume', randomUUID(), '--model', 'haiku'], 'x', cwd);
  const errors = missing.lines.find(l => l.type === 'result');
  setCase('ない会話の --resume の形');
  check('ない会話の --resume は 0 でない終了コード', missing.code !== 0, missing.code);
  check('result の errors の要素が「No conversation found」で始まる', !!errors && (errors.errors || []).some(e => typeof e === 'string' && e.startsWith('No conversation found')), JSON.stringify(errors));
  const skillCall = callClaude(['--session-id', randomUUID(), '--model', 'sonnet'], 'スキル contract-skill を Skill のツールで呼んで', cwd);
  const skillUse = contents(skillCall.lines).find(c => c.type === 'tool_use' && c.name === 'Skill');
  setCase('Skill のツールの呼び出しの形');
  check('Skill のツールの呼び出しは input.skill を持つ', !!skillUse && skillUse.input && typeof skillUse.input.skill === 'string', JSON.stringify(skillUse));
  const agentCall = callClaude(['--session-id', randomUUID(), '--model', 'sonnet'], 'サブエージェントを 1 つ起動して、1+1 の答えを聞いて', cwd);
  const agentUse = contents(agentCall.lines).find(c => c.type === 'tool_use' && (c.name === 'Agent' || c.name === 'Task'));
  setCase('サブエージェントの呼び出しと結果の形');
  check('サブエージェントの呼び出しは Agent か Task の名前と id を持つ', !!agentUse && typeof agentUse.id === 'string', JSON.stringify(agentUse));
  const results = agentCall.lines.filter(l => l.type === 'user').flatMap(l => (l.message && Array.isArray(l.message.content) && l.message.content) || []);
  check('tool_result は同じ id の tool_use_id を持つ', !!agentUse && results.some(c => c.type === 'tool_result' && c.tool_use_id === agentUse.id));
  const written = path.join(cwd, '書いた.txt');
  callClaude(['--session-id', randomUUID(), '--model', 'haiku'], `${written} に「中身」と書いて`, cwd);
  setCase('acceptEdits でファイルを書ける');
  check('acceptEdits でファイルを書ける', fs.existsSync(written));
  if (totals.fail === 0) fs.writeFileSync(path.join(testsDir, 'contract-baseline.json'), JSON.stringify({version: (version.stdout || '').trim(), checkedAt: new Date().toISOString()}, null, 2) + '\n');
}

// ここから、画面と中継サーバーと本物の AI を通すテスト
let server = null;
let browser = null;
let port = null;
let sf = null;
let url = null;
let streamLog = null;

function makeCopy() {
  sf = path.join(tmp, 'sf');
  // 続きから流すときは、作業のフォルダと .claude をそのまま使い、直した画面と中継サーバーだけを写す
  if (continuing) { for (const f of ['server.mjs', 'index.html', 'デザイントークン.css']) fs.copyFileSync(path.join(uiDir, f), path.join(sf, 'ui', f)); return; }
  fs.mkdirSync(path.join(sf, 'ui'), {recursive: true});
  fs.mkdirSync(path.join(sf, 'output'), {recursive: true});
  for (const f of ['server.mjs', 'index.html', 'デザイントークン.css', 'はじめに.md', '段階ごとのスキルと規約.json']) fs.copyFileSync(path.join(uiDir, f), path.join(sf, 'ui', f));
  // hook post-tool-use-any-tool は、state.json の検査を <プロジェクト>/ui/tests/lib/state-contract.mjs から読むので、本物の使い方と同じに写す
  fs.mkdirSync(path.join(sf, 'ui', 'tests', 'lib'), {recursive: true});
  fs.copyFileSync(path.join(uiDir, 'tests', 'lib', 'state-contract.mjs'), path.join(sf, 'ui', 'tests', 'lib', 'state-contract.mjs'));
  // リンクをたどって実体を写し、本物の規約とスキルと output/ に書かないようにする
  // .claude/skills/tests は、スキルのテストの記録で、読み取りだけのファイルを持ち、AI の実行に要らない
  const skipTests = path.join(factory, '.claude', 'skills', 'tests');
  fs.cpSync(path.join(factory, '.claude'), path.join(sf, '.claude'), {recursive: true, dereference: true, filter: p => p !== skipTests && !p.startsWith(skipTests + path.sep)});
}
// 中継サーバーを変えずに費用の上限を付けるため、PATH の先頭に本物の claude を包むスクリプトを置く
function budgetWrapper() {
  // Superset の包むスクリプトは PATH の先頭の claude を探すので、それを指すとこのスクリプトと呼び合って止まらない。本体のパスを使う
  const real = spawnSync('which', ['-a', 'claude'], {encoding: 'utf8'}).stdout.split('\n').find(p => p && !p.includes('/.superset')) || 'claude';
  const bin = path.join(tmp, 'bin');
  fs.mkdirSync(bin, {recursive: true});
  // 通しの実行は、原因を調べられるように stream-json の全行を残す
  // exec で置き換えて、中継サーバーの SIGTERM を本物の claude に届ける
  const run = streamLog ? `exec ${JSON.stringify(real)} "$@" --include-hook-events --max-budget-usd ${limits[scenario].usd} > >(tee -a ${JSON.stringify(streamLog)})` : `exec ${JSON.stringify(real)} "$@" --max-budget-usd ${limits[scenario].usd}`;
  fs.writeFileSync(path.join(bin, 'claude'), `#!/bin/bash\nif [ "$1" = "--version" ]; then exec ${JSON.stringify(real)} "$@"; fi\n${run}\n`, {mode: 0o755});
  return bin;
}
function startServer() {
  server = spawn('node', ['ui/server.mjs'], {cwd: sf, env: {...process.env, PORT: String(port), PATH: `${budgetWrapper()}:${process.env.PATH}`}, stdio: 'ignore'});
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
async function openPage() {
  const {chromium} = await import('playwright');
  browser = await chromium.launch();
  const page = await (await browser.newContext()).newPage();
  await page.goto(url);
  return page;
}
const visible = (page, sel) => page.locator(sel).first().isVisible();
const busyOf = page => page.evaluate(() => fetch('/api/status').then(r => r.json()).then(b => b.busy).catch(() => true));
const formOpen = page => visible(page, '#qform');
const sendAnswers = page => page.locator('#qform .qfoot button').click();
const stateOf = rel => JSON.parse(fs.readFileSync(path.join(sf, rel, 'ui', 'state.json'), 'utf8'));
const sessionOf = rel => JSON.parse(fs.readFileSync(path.join(sf, rel, 'ui', 'session.json'), 'utf8')).sessionId;
const conversationOf = rel => fs.readFileSync(path.join(sf, rel, 'ui', 'conversation.md'), 'utf8');

// 本物の AI が書いた state.json が、スキル updating-skill-factory-ui-state のリファレンスの 16 のキーを持つこと
const stateKeys = ['workName', 'currentSkill', 'stage', 'artifacts', 'figures', 'documentPath', 'decision', 'questions', 'rounds', 'downloads', 'screen', 'summary', 'research', 'factCheck', 'approvalSheet', 'draftReview'];
const stateProblems = s => stateKeys.filter(k => !(k in s));

// 段階 stopStage に入るまで、質問の一覧には答え、承認のボタンは最初の選択肢を押す。段階 7 の実施する範囲は最初の選択肢(推奨)を選ぶ
async function drive(page, rel, stopStage, onRow, onText) {
  const rows = page.locator('#qform .qi');
  let idleSince = 0;
  const seen = {form: new Set(), choice: new Set()};
  while (Date.now() < deadline) {
    const s = stateOf(rel);
    if (s.stage >= stopStage && (stopStage < 8 || s.artifacts.at(-1).status === '済み')) break;
    if (await busyOf(page)) { idleSince = 0; await sleep(2000); continue; }
    if (await hearingStep(page, onText)) {
      seen.choice.add(s.stage);
    } else if (await formOpen(page)) {
      seen.form.add(s.stage);
      for (const row of await rows.all()) await onRow(row, s);
      await sendAnswers(page);
    } else if (await page.locator('.decision .choice:not([disabled])').count()) {
      seen.choice.add(s.stage);
      await page.locator('.decision .choice').first().click();
    } else if (await page.locator('#messages .chips .chip').count()) {
      await page.locator('#messages .chips .chip').first().click();
      await page.press('#input', 'Enter');
    } else {
      idleSince ||= Date.now();
      // AI が動いていないのに押すものがない状態は、時間の上限まで待たずに不合格にする
      if (Date.now() - idleSince > 3 * 60 * 1000) {
        check('AI の返事のあとに押せるものがある', false, `stage=${s.stage} screen=${s.screen} decision=${JSON.stringify(s.decision)}`);
        break;
      }
      await sleep(5000);
      continue;
    }
    idleSince = 0;
    await until(() => busyOf(page), 10000);
  }
  return seen;
}
// 選ぶと要件定義書を書かずに終わる選択肢(リファレンス「聞き取りの項目と問い」の章「答えで終える条件」)。テストの利用者は選ばない
// 選択肢の見出し(最初の「:」より前)で見分ける。「書く前: 案を見せて待ち、直すかやめる」のように、説明の中の語は見ない
const ENDING_HEAD = /そのまま使う|毎回|1 回だけ|やめる|中止/;
const ENDING = {test: text => ENDING_HEAD.test(String(text).split(/[::]/)[0])};
// 「次へ」でページを送るたびに呼ぶ関数(hearingFlow が、送ったページに AI の問いが届くかを確かめる)
let onPageTurn = null;
// 聞き取りの画面の 1 回分の操作。出ている画面の選択肢を選び、主なボタンを押す。押したら true を返す。onText は、選択肢のない問いの答えの文か、問いの文から答えを返す関数
// skip は、答えを入れない問いの塊の番号(0 から)
async function hearingStep(page, onText, skip = new Set()) {
  if (!(await visible(page, '#hear'))) return false;
  const screen = await page.locator('#hearbody').getAttribute('data-screen');
  const blocks = await page.locator('#hearbody fieldset.zqs').all();
  for (const [i, f] of blocks.entries()) {
    if (skip.has(i)) continue;
    const options = f.locator('.zop');
    if (await options.count()) {
      const checked = f.locator('.zop:has(input:checked) .zopt');
      // 複数を選べる問い(チェックボックス)は、選んだ選択肢があれば選び直さない。押し直すとチェックが外れる
      if ((await checked.count()) && (await f.locator('.zop input[type="checkbox"]').count())) continue;
      if ((await checked.count()) && !ENDING.test(await checked.first().innerText())) continue;
      const labels = await f.locator('.zop .zopt').allInnerTexts();
      const preferred = labels.findIndex(l => /新しく作る|要約|まだない/.test(l));
      const usable = labels.findIndex(l => !ENDING.test(l));
      await options.nth(preferred >= 0 ? preferred : usable >= 0 ? usable : 0).click();
    } else {
      const area = f.locator('textarea');
      if (await area.inputValue()) continue;
      const question = await f.locator('legend').innerText();
      const answer = typeof onText === 'function' ? onText(question) : onText || 'テストの答えです';
      await area.fill(answer);
    }
  }
  // 画面「AI から決めてもらうこと」は、選択肢をラジオボタン(名前 lpick)で出す。選ばれた選択肢がないときは、推奨の選択肢か 1 つ目を選ぶ
  const picks = page.locator('#hearbody input[name="lpick"]');
  if ((await picks.count()) && !(await page.locator('#hearbody input[name="lpick"]:checked').count())) {
    const reco = page.locator('#hearbody label.lopt:has(.lreco) input[name="lpick"]');
    await ((await reco.count()) ? reco.first() : picks.first()).click();
    console.log(`操作: ${screen} で推奨の選択肢を選ぶ`);
  }
  const main = page.locator('#hearfoot .btn.pri:not([disabled])').last();
  if (!(await main.count())) {
    // 回の途中のページは、主なボタンの代わりに主でない「次へ」でページを送る(AI に送らない)。回の最後のページまで進めて、主なボタンを押す
    const next = page.locator('#hearfoot .btn:not(.pri):not([disabled])', {hasText: /^次へ$/});
    if (!(await next.count())) return false;
    console.log(`操作: ${screen} で「次へ」を押す`);
    await next.click();
    await sleep(300);
    if (onPageTurn) await onPageTurn(page);
    return hearingStep(page, onText);
  }
  console.log(`操作: ${screen} で「${await main.innerText()}」を押す`);
  await main.click();
  return true;
}
// 画面 4 で、画面遷移設計書の T11(前へ)、T13(この質問に戻る)、T25 と T25-2(分からない)の道を 1 回押す。押せないときは false を返す。
// 「前へ」と「この質問に戻る」は、AI に送らずにページを切り替える。「分からない」は、回の最後のページの「回答を送る」で、ほかの答えと一緒に送る
async function backStep(page, name) {
  if (name === '前へ') {
    const b = page.locator('#hearfoot .btn', {hasText: '前へ'});
    if (!(await b.count()) || await b.isDisabled()) return false;
    await b.click();
    return true;
  }
  if (name === 'この質問に戻る') {
    await page.locator('#hearfoot .ghost', {hasText: 'これまでの答えの一覧'}).click();
    const b = page.locator('#hearbody button', {hasText: 'この質問に戻る'});
    if (!(await b.count())) { await page.locator('#hearfoot .btn.pri', {hasText: '質問に戻る'}).click(); return false; }
    await b.last().click();
    return true;
  }
  // 分からない: 選んだ選択肢のない問いの「理由と補足」か「答えを書く」を開いて「分からない」を押し、ほかの問いに答えて「回答を送る」まで進める
  const blocks = await page.locator('#hearbody fieldset.zqs').all();
  for (const [i, f] of blocks.entries()) {
    if ((await f.locator('.zop').count()) && (await f.locator('.zop input:checked').count())) continue;
    const more = f.locator('details.zmore');
    if (!(await more.count())) continue;
    if (!(await more.evaluate(e => e.open))) await more.locator('summary').click();
    await more.getByRole('button', {name: '分からない'}).click();
    return hearingStep(page, textAnswer, new Set([i]));
  }
  return false;
}
const answerer = (marker, sent = []) => async (row, s) => {
  let answer = marker;
  if (await row.locator('textarea').count()) await row.locator('textarea').fill(answer);
  else {
    answer = await row.locator('.chip').first().innerText();
    await row.locator('.chip').first().click();
  }
  if (s.stage === 1) sent.push(answer);
};

// 段階まで通す流れと続きからの流れの共通: 依頼から最初の質問の一覧までと、中継サーバーの起動し直し
async function untilFirstQuestion() {
  await startServer();
  const page = await openPage();
  await page.fill('#input', '請求書の受領を記録するスキルを作って');
  await page.press('#input', 'Enter');
  // 段階 1 は聞き取りの画面で問う。state.json の screen があるときは、問いの一覧の代わりに聞き取りの画面の主なボタンを待つ
  check('依頼のあとに質問の一覧か、押せる主なボタンを持つ聞き取りの画面が出る', await until(async () => (await formOpen(page)) || (await page.locator('#hearbody fieldset.zqs').count()) > 0 || (await page.locator('#hearfoot .btn.pri:not([disabled])').count()) > 0, 20 * 60 * 1000));
  const rel = await page.evaluate(() => seenWorkDir);
  check('作業のフォルダは output/<開始日時> の形', /^output\/\d{4}-\d\d-\d\d-\d{4}$/.test(rel), rel);
  check('仮の会話が作業のフォルダに移る', fs.readdirSync(path.join(sf, 'ui', '.pending')).length === 0 && conversationOf(rel).includes('請求書の受領'));
  check('本物の AI が書いた state.json は 16 のキーを持つ', stateProblems(stateOf(rel)).length === 0, stateProblems(stateOf(rel)).join('、'));
  return {page, rel};
}

async function stageFlow(stopStage) {
  const {page, rel} = await untilFirstQuestion();
  const firstId = sessionOf(rel);
  const stageBefore = stateOf(rel).stage;
  await stopServer();
  await startServer();
  await until(async () => (await page.locator('#conn').innerText()).endsWith('接続中'));
  const sent = [];
  const onRow = answerer('受領台帳ZQ7', sent);
  const startAnswer = Date.now();
  const screenBefore = stateOf(rel).screen;
  const usersBefore = conversationOf(rel).split('\n').filter(l => l.startsWith('ユーザー:')).length;
  // 中継サーバーを起動し直したあとの答えも AI に届き、AI が state.json を書き直す
  if (await hearingStep(page, '受領台帳ZQ7')) {
    await until(() => busyOf(page), 10000);
    await until(async () => !(await busyOf(page)), 20 * 60 * 1000);
    check('起動し直したあとの答えが「ユーザー:」の行で会話に残る', conversationOf(rel).split('\n').filter(l => l.startsWith('ユーザー:')).length === usersBefore + 1);
    check('起動し直したあとの答えで AI が次の画面へ進むか、同じ画面を書き直す', stateOf(rel).screen !== screenBefore || fs.statSync(path.join(sf, rel, 'ui', 'state.json')).mtimeMs > startAnswer, stateOf(rel).screen);
  } else {
    const firstRow = page.locator('#qform .qi').first();
    const firstNumber = Number((await firstRow.locator('.no').innerText()).replace(/\D/g, ''));
    await onRow(firstRow, stateOf(rel));
    await sendAnswers(page);
    await until(() => busyOf(page), 10000);
    await until(async () => !(await busyOf(page)), 20 * 60 * 1000);
    const item = stateOf(rel).questions && stateOf(rel).questions.items.find(i => i.number === firstNumber);
    check('起動し直したあとの答えを AI が state.json に書く', !!item && item.answer != null, JSON.stringify(item));
  }
  check('会話の ID が変わらない', sessionOf(rel) === firstId);
  check('答えのあとに段階が戻らない', stateOf(rel).stage >= stageBefore, stateOf(rel).stage);
  const seen = await drive(page, rel, stopStage, onRow, '受領台帳ZQ7');
  const final = stateOf(rel);
  check(`段階 ${stopStage} まで進む`, final.stage >= stopStage, `段階 ${final.stage}`);
  check('承認のボタンで段階が進む', seen.choice.size > 0);
  // 2026-11-20: 答えの正本は聞き取りの記録の章「答え」。要件定義書の章 5「質問への答えの一覧」は、質問の番号と反映した章だけを持つ
  const recordPath = path.join(sf, rel, '聞き取りの記録.md');
  const record = fs.existsSync(recordPath) ? fs.readFileSync(recordPath, 'utf8') : '';
  sent.push(...hearingAnswers(conversationOf(rel)));
  const missing = sent.filter(a => !includesText(record, recordedWord(a)));
  check(`画面で送った答えの ${sent.length} 問のすべてが聞き取りの記録に書かれる`, sent.length > 0 && missing.length === 0, missing.join(' / '));
  check('要件定義書ができる', fs.existsSync(path.join(sf, rel, '要件定義書.md')));
  check('最後まで同じ会話の ID を使う', sessionOf(rel) === firstId);
  check('分割設計書ができる', fs.existsSync(path.join(sf, rel, '分割設計書.md')));
  const figures = fs.existsSync(path.join(sf, rel, 'ui', 'figures')) ? fs.readdirSync(path.join(sf, rel, 'ui', 'figures')) : [];
  if (stopStage >= 8) {
    for (const [stage, kind] of [[3, 'phase と step の流れ図'], [7, 'シナリオテストが受け持つテストケース'], [8, '判定の結果の図']]) {
      check(`段階 ${stage} の${kind}がある(規約 skill-making-flow の規則 6)`, figures.some(f => f.startsWith(`${stage}-`) && f.includes(kind)), figures.join('、'));
    }
    // 2026-11-22: 段階 7 の承認の前に、業務フローと正常系のシナリオの一致の図(シナリオの経路の図)を描く(規約 skill-making-flow の規則 6 の表)
    const route = figures.filter(f => /^7-.*シナリオの経路の図\.svg$/.test(f));
    check('段階 7 のシナリオの経路の図がある', route.length > 0, figures.join('、'));
    const svg = route.length ? fs.readFileSync(path.join(sf, rel, 'ui', 'figures', route[0]), 'utf8') : '';
    check('段階 7 のシナリオの経路の図が、正常系の判定の帯を持つ', /正常系 S\d+ は、\d+ つの phase/.test(svg), svg.slice(0, 200));
  }
  check('最後の state.json も 16 のキーを持つ', stateProblems(final).length === 0);
  if (stopStage >= 8) {
    const skillsDir = path.join(sf, rel, 'skills');
    const records = fs.existsSync(skillsDir) ? spawnSync('find', [skillsDir, '-name', '判定の記録.md'], {encoding: 'utf8'}).stdout.trim() : '';
    check('判定の記録ができる', records.length > 0);
    check('8 件の成果物がすべて済み', final.artifacts.every(a => a.status === '済み'), JSON.stringify(final.artifacts.map(a => a.status)));
    console.log(`conversation.md の大きさ: ${fs.statSync(path.join(sf, rel, 'ui', 'conversation.md')).size} バイト`);
  }
  console.log(`作業のフォルダ: ${path.join(sf, rel)}`);
}

// 「<スキルの名前> を照合して」の流れ
async function checkFlow() {
  const skillName = 'updating-skill-factory-ui-state';
  fs.cpSync(path.join(factory, 'output', skillName), path.join(sf, 'output', skillName), {recursive: true, dereference: true, filter: p => !p.includes(`${path.sep}tests${path.sep}`)});
  await startServer();
  const page = await openPage();
  await page.fill('#input', `${skillName} を照合して`);
  await page.press('#input', 'Enter');
  await until(() => busyOf(page), 10000);
  await until(async () => !(await busyOf(page)), 25 * 60 * 1000);
  const rel = await page.evaluate(() => seenWorkDir);
  check('段階 5 で止まる', !!rel && stateOf(rel).stage === 5, rel && stateOf(rel).stage);
  const conv = rel ? conversationOf(rel) : '';
  check('照合のスクリプトが権限で止まらない(終了コードの行がない)', !conv.includes('(終了コード 1'));
}

// session.json を消して続きから始め、成果物のパスの送信で段階が決まる
async function lostFlow() {
  const {page, rel} = await untilFirstQuestion();
  const reqPath = path.join(rel, '要件定義書.md');
  fs.mkdirSync(path.join(sf, rel), {recursive: true});
  if (!fs.existsSync(path.join(sf, reqPath))) fs.writeFileSync(path.join(sf, reqPath), '# 要件定義書\n\n請求書の受領を記録するスキル。\n');
  await stopServer();
  fs.rmSync(path.join(sf, rel, 'ui', 'session.json'));
  await startServer();
  await page.reload();
  await page.locator('#works > summary').click();
  await page.locator('#works .wk button', {hasText: '続きから'}).click();
  await page.locator('#recordopen').click();
  check('続けられないことを会話に出す', await until(async () => (await page.locator('#messages').innerText()).includes('前の会話を続けられないので'), 15000));
  await page.fill('#input', `${reqPath} ができたから続きをやって`);
  await page.press('#input', 'Enter');
  await until(() => busyOf(page), 10000);
  await until(async () => !(await busyOf(page)), 25 * 60 * 1000);
  check('成果物のパスで AI が段階を決め、state.json を書き直す(段階 2)', stateOf(rel).stage === 2, stateOf(rel).stage);
}

// 文字の並びだけを比べる。pre-line と md の表示は空白と改行を変える
const squeeze = text => String(text).replace(/\s+/g, '');
const includesText = (body, text) => squeeze(body).includes(squeeze(text));
// 選択肢の後ろの(推奨)と(AI の推測)を外す。選択肢は、文字列か、label を持つオブジェクト(画面の状態のファイルの形の行 decision.choices[])。オブジェクトのときは label を使う
const plainChoice = c => String(c && typeof c === 'object' ? c.label ?? '' : c).replace(/[((](推奨|AI の推測)[))]$/, '');
// 聞き取りの記録と比べる語。AI は選択肢の後ろの括弧の説明(例: (値を聞く))を省いて書くことがある
const recordedWord = a => String(a).replace(/[((][^()()]*[))]$/, '');
// 選択肢のない問いへの、テストの利用者の答え
const textAnswer = question => (/確かめる点/.test(question) ? '読みの候補の 1 つ目' : /パス|どこ|場所/.test(question) ? 'まだない' : /字数|数|件/.test(question) ? '1 件' : /語/.test(question) ? '件名' : 'AI の案のとおりでよいです');

// 画面(index.html の questionGroups)と同じ分け方で、問いの一覧をカテゴリーの組に分ける。category がない要素は、前の要素のカテゴリーに入れる
const catOf = it => (typeof it.category === 'string' && it.category.trim() ? it.category.trim() : null);
function questionGroups(items) {
  const names = [...new Set(items.map(catOf).filter(Boolean))];
  if (names.length < 2) return [{name: names[0] || null, items}];
  const groups = names.map(name => ({name, items: []}));
  let now = groups[0];
  for (const it of items) {
    if (catOf(it)) now = groups.find(g => g.name === catOf(it));
    now.items.push(it);
  }
  return groups;
}
// 画面にいま出ているページの問いの組を返す。画面は、2 つ以上のカテゴリーを持つ回を、カテゴリーごとのページに分けて出す。
// ページは、見出し(カテゴリーの名前)と最初の問いの文の両方が合う組を、今の回(questions.items)から前の回(rounds)の順に探し、ないときは最初の問いの文だけで探す。
// 前の回と今の回が同じカテゴリーの名前を持つとき(「前へ」で前の回のページを出したとき)も、見出しと最初の問いの文の両方で組を選ぶ。
// first は、今の回の最初の組か(知らせの行は、回の最初のページにだけ出る)。見つからないときは、今の回のすべての問いを 1 つの組とする
async function shownGroup(page, s) {
  const heading = await page.locator('#hearbody .zt1').first().innerText().catch(() => '');
  const legend = await page.locator('#hearbody fieldset.zqs legend').first().innerText().catch(() => '');
  const now = s.questions ? s.questions.items : [];
  const lists = [now, ...(Array.isArray(s.rounds) ? [...s.rounds].reverse().map(r => (r.items || []).filter(i => i.replaced !== true)) : [])];
  const byLegend = g => !!legend && g.items.length > 0 && squeeze(g.items[0].text) === squeeze(legend);
  for (const match of [g => byLegend(g) && !!g.name && squeeze(g.name) === squeeze(heading), byLegend]) {
    for (const [li, items] of lists.entries()) {
      const groups = questionGroups(items);
      const gi = groups.findIndex(match);
      if (gi >= 0) return {...groups[gi], first: li === 0 && gi === 0};
    }
  }
  return {name: null, items: now, first: true};
}

// 画面に出ていない、AI が state.json に書いた値の一覧を返す。shown は、問いの画面で、いま出ているページの問いの組(shownGroup)
function missingOnScreen(s, screen, body, shown = null) {
  const want = [];
  const items = shown ? shown.items : s.questions ? s.questions.items : [];
  if (screen === '画面 2' && s.summary) want.push(...s.summary.lines, ...s.summary.readings);
  if (screen === '調べるための問い' && s.questions) want.push(...items.map(i => i.text));
  if (screen === '画面 3' && s.factCheck) want.push(s.factCheck.heading, ...s.factCheck.facts.map(x => x.text), ...s.factCheck.items.flatMap(x => [x.name, x.value]));
  if (screen === '画面 4' && s.questions) {
    // 見出しは、ページのカテゴリーの名前(ないときは questions.title)
    want.push((shown && shown.name) || s.questions.title);
    if (s.questions.notice && (!shown || shown.first)) want.push(s.questions.notice);
    for (const i of items) want.push(i.text, ...(i.choices || []).map(plainChoice));
  }
  if (screen === '画面 5' && s.draftReview) {
    for (const x of s.draftReview.checkFirst) want.push(x.name, x.value);
    for (const x of s.draftReview.checks || []) want.push(x.name, ...x.candidates);
    for (const sec of s.draftReview.sections) want.push(sec.title, ...sec.items.flatMap(x => [x.name, x.value]));
  }
  return want.filter(w => w && !includesText(body, w));
}

// 依頼から stopScreen(省略時は画面 3 の次の画面)までを、画面と中継サーバーと本物の AI で通す。AI が書いた state.json の screen の順と、画面の写真と文と、stream-json の全行を残す
async function hearingFlow(stopScreen = null) {
  const stamp = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 19).replace('T', '-').replace(/:/g, '');
  const dir = process.env.ARTIFACT_DIR || path.join(testsDir, `${stamp}-通し`);
  fs.mkdirSync(path.join(dir, 'state'), {recursive: true});
  fs.mkdirSync(path.join(dir, 'text'), {recursive: true});
  streamLog = path.join(dir, 'stream.jsonl');
  console.log(`実行の記録: ${dir}`);
  await startServer();
  const page = await openPage();
  await page.setViewportSize({width: 1280, height: 800});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const readJson = (name, empty) => { try { return JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8')); } catch { return empty; } };
  // state.json を 250 ミリ秒ごとに読み、中身が変わるたびに screen の順を記録する
  const screens = continuing ? readJson('screens.json', []) : [];
  let lastText = null;
  const workRel = () => {
    const names = fs.existsSync(path.join(sf, 'output')) ? fs.readdirSync(path.join(sf, 'output')).filter(n => fs.existsSync(path.join(sf, 'output', n, 'ui', 'state.json'))) : [];
    return names.length ? path.join('output', names[0]) : null;
  };
  const stateTextOf = rel => fs.readFileSync(path.join(sf, rel, 'ui', 'state.json'), 'utf8');
  const watch = setInterval(() => {
    const rel = workRel();
    if (!rel) return;
    let text;
    try { text = stateTextOf(rel); } catch { return; }
    if (text === lastText) return;
    let parsed;
    try { parsed = JSON.parse(text); } catch { return; }
    lastText = text;
    const n = screens.length + 1;
    screens.push({n, at: new Date().toISOString(), screen: parsed.screen ?? null, stage: parsed.stage, decision: parsed.decision ? parsed.decision.question : null, keys: stateProblems(parsed)});
    fs.writeFileSync(path.join(dir, 'state', `${String(n).padStart(2, '0')}.json`), text);
    fs.writeFileSync(path.join(dir, 'screens.json'), JSON.stringify(screens, null, 2) + '\n');
    console.log(`state.json ${n}: screen=${parsed.screen ?? null} stage=${parsed.stage}`);
  }, 250);
  let shot = fs.readdirSync(dir).filter(n => n.endsWith('.png')).length;
  // 画面の写真と、画面に出ている文を残す。スクロールする画面は、一番下の写真も残す
  const photo = async name => {
    const base = `${String(++shot).padStart(2, '0')}-${name.replace(/\s/g, '_')}`;
    await page.screenshot({path: path.join(dir, `${base}.png`)});
    fs.writeFileSync(path.join(dir, 'text', `${base}.txt`), await page.locator('#hearbody').innerText().catch(() => ''));
    const scroll = page.locator('#hearscroll');
    if (stopScreen && await scroll.isVisible() && await scroll.evaluate(e => e.scrollHeight > e.clientHeight + 8)) {
      const top = await scroll.evaluate(e => { const v = e.scrollTop; e.scrollTop = e.scrollHeight; return v; });
      await page.screenshot({path: path.join(dir, `${base}-一番下.png`)});
      await scroll.evaluate((e, v) => { e.scrollTop = v; }, top);
    }
  };
  const reachRecord = rel => { const p = path.join(sf, rel, '聞き取りの記録.md'); return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : ''; };
  // 最後の呼び出しの結果が失敗か(費用の上限に当たったときを含む)を返す
  const lastResult = () => {
    if (!fs.existsSync(streamLog)) return null;
    const lines = fs.readFileSync(streamLog, 'utf8').split('\n').filter(Boolean).flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } });
    return lines.filter(l => l.type === 'result').at(-1) || null;
  };
  await photo(continuing ? '続きからの画面1' : '画面1');
  if (continuing) {
    const rel = workRel();
    const res = await page.evaluate(d => fetch('/api/resume', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({dir: d})}).then(r => r.status), rel);
    check('続きから開ける', res === 200, res);
    await page.reload();
  } else {
    await page.fill('#input', 'コミットをまとめるskillを作る');
    await page.press('#input', 'Enter');
    check('送ったあとに「AI が読む」の画面が出る', await until(async () => (await page.locator('#hearbody').innerText()).includes('AI があなたの文章を読んでいます'), 10000));
    await photo('AI が読む');
  }
  const visited = continuing ? readJson('visited.json', []) : [];
  const domChecks = {};
  let after3 = 0;
  let reached = false;
  // 画面 4 のカテゴリーごとの答えと、次の返事のあとに聞き取りの記録で確かめる文
  const sentAnswers = [];
  let waitingAnswers = null;
  let carriedAnswers = [];
  let hosokuSent = false;
  let answersViewed = false;
  // 画面 5 の確かめる点で選んだ読みと、複数を選べる問いと項目 7-1 の欄が届いた数
  const pickedReadings = [];
  const reached4 = {multiple: 0, parts: 0, files: 0};
  let waitingChecks = false;
  const fix = {marker: '確認の語 ZQ5直し', sent: false, seen: false};
  // 画面 4 でまだ押していない道。押したあとに、AI が書いた state.json を state-contract で確かめる。送った文の形は画面遷移設計書の章 11 の列「送る文」
  const backs = stopScreen === '画面 6' ? ['前へ', 'この質問に戻る', '分からない'] : [];
  // 「前へ」と「この質問に戻る」は AI に送らない(章 11 の T11、T13)。「分からない」は「<問いの番号>: 分からない」の行を送る(T25-2)
  const backSent = {'分からない': t => t.split('\n').some(l => /^\d+: 分からない$/.test(l))};
  const navBacks = ['前へ', 'この質問に戻る'];
  // 同じ state.json のまま続けて操作した回数
  let actedText = null;
  let stuck = 0;
  const end = Date.now() + (limits[scenario].minutes - 5) * 60 * 1000;
  let busySince = null;
  // 「次へ」で送ったページ(2 つ以上のカテゴリーを持つ回の 2 つ目からのカテゴリー)にも、AI の問いと複数を選べる問いのチェックが出るかを確かめる
  onPageTurn = async p => {
    const r = workRel();
    let st = null;
    // AI が書いている途中の state.json は読めないので、そのときは確かめない
    try { st = r ? stateOf(r) : null; } catch { return; }
    const sc = await p.locator('#hearbody').getAttribute('data-screen').catch(() => null);
    if (!st || !st.questions || !['調べるための問い', '画面 4'].includes(sc)) return;
    const shown = await shownGroup(p, st);
    const gaps = missingOnScreen(st, sc, await p.locator('#hearbody').innerText().catch(() => ''), shown);
    check(`${sc} の「次へ」で出したページに AI の問いが届く(${shown.name || st.questions.title})`, gaps.length === 0, gaps.join(' / '));
    if (sc !== '画面 4') return;
    const shownMulti = shown.items.filter(i => i.multiple === true && (i.choices || []).length).length;
    check(`画面 4 の「次へ」で出したページの複数を選べる問いがチェックで出る(${shown.name || st.questions.title})`, (await p.locator('#hearbody fieldset.zqs:has(.zops input[type=checkbox])').count()) === shownMulti, String(shownMulti));
  };
  while (Date.now() < end) {
    if (await busyOf(page)) {
      busySince = busySince || Date.now();
      if (Date.now() - busySince > 25 * 60 * 1000) { check('1 回の呼び出しが 25 分で終わる', false, `screen=${screens.at(-1)?.screen}`); break; }
      // 調査の間の表示を写真に残す
      const shown = await page.locator('#hearbody').getAttribute('data-screen').catch(() => null);
      if (shown === '調査' && !domChecks['調査']) { await photo('調査'); domChecks['調査'] = true; check('調査の画面に見出しが出る', (await page.locator('#hearbody').innerText()).includes('AI が調べています')); }
      if (shown === '画面 5' && fix.sent && !fix.waited) { fix.waited = true; check('画面 5 の直しを送った間は、読み直している知らせが出る', (await page.locator('#hearbody').innerText()).includes('読み直しています')); await photo('画面5の読み直し'); }
      await sleep(1000);
      continue;
    }
    busySince = null;
    await sleep(2500); // 画面の読み直しを待つ
    if (await busyOf(page)) continue;
    const failed = lastResult();
    if (failed && (failed.is_error || String(failed.subtype).startsWith('error'))) { check('claude の呼び出しが成功する(費用の上限に当たっていない)', false, `${failed.subtype} ${JSON.stringify(failed.errors || failed.result || '').slice(0, 300)}`); break; }
    if (failed && limits[scenario].totalUsd && failed.total_cost_usd > limits[scenario].totalUsd) { check(`1 回の通しの費用が ${limits[scenario].totalUsd} ドル以内`, false, String(failed.total_cost_usd)); break; }
    const rel = workRel();
    const s = rel ? stateOf(rel) : null;
    if (!s) { check('AI が state.json を書く', false, '最初の返事のあとに state.json がない'); break; }
    const screen = s.screen ?? null;
    if (visited.at(-1) !== screen) visited.push(screen);
    const body = await page.locator('#hearbody').innerText().catch(() => '');
    // スキルの step 7-3 は、同じカテゴリーの問いを分けて出したとき(合格の 1 問の 2 回目と続けて出す 1 問など)、すべての答えを受けてから step 7-6 で記録に書く。同じカテゴリーの画面 4 が続く間は確かめず、最後の答えと合わせて確かめる
    if (waitingAnswers && screen === '画面 4' && s.questions?.title === waitingAnswers.title) { carriedAnswers = waitingAnswers.answers; waitingAnswers = null; }
    if (waitingAnswers) {
      const record = reachRecord(rel);
      const lost = waitingAnswers.answers.filter(a => !includesText(record, recordedWord(a)));
      check(`画面 4 の答えが聞き取りの記録に書かれる(${waitingAnswers.title})`, record.length > 0 && lost.length === 0, lost.join(' / '));
      waitingAnswers = null;
    }
    const text = stateTextOf(rel);
    const lastDrawn = await page.evaluate(() => last.state);
    if (lastDrawn !== text) { await sleep(2500); }
    const bodyNow = await page.locator('#hearbody').innerText().catch(() => body);
    const shown = ['調べるための問い', '画面 4'].includes(screen) && s.questions ? await shownGroup(page, s) : null;
    if (text !== domChecks.lastState) {
      domChecks.lastState = text;
      const gaps = missingOnScreen(s, screen, bodyNow, shown);
      if (screen === '画面 2' && s.summary && !domChecks['画面 2']) { domChecks['画面 2'] = true; check('画面 2 に AI のまとめか読みの候補が届く', gaps.length === 0, gaps.join(' / ')); }
      else if (screen === '調べるための問い' && s.questions && !domChecks[screen]) { domChecks[screen] = true; check('調べるための問いに AI の問いが届く', gaps.length === 0, gaps.join(' / ')); }
      else if (screen === '画面 3' && s.factCheck && !domChecks[screen]) { domChecks[screen] = true; check('画面 3 に AI の見出しと事実が届く', gaps.length === 0, gaps.join(' / ')); }
      else if (screen === '画面 4' && s.questions) check(`画面 4 に AI の問いが届く(${s.questions.title})`, gaps.length === 0, gaps.join(' / '));
      else if (screen === '画面 5' && s.draftReview) check('画面 5 に、AI が書いた下書きの項目が届く', s.draftReview.sections.length > 0 && gaps.length === 0, gaps.join(' / '));
    }
    await photo(screen || `旧い形-段階${s.stage}`);
    if (!stopScreen && domChecks['画面 3'] && screen !== '画面 3') { after3 = 1; break; }
    // 画面 6 で止まる。主なボタンは次の段階へ進み、費用がかかるので押さない
    if (screen === stopScreen) { reached = true; break; }
    if (text === actedText) {
      if (++stuck >= 2) { check('AI の返事のあとに state.json が変わる', false, `screen=${screen}`); break; }
    } else stuck = 0;
    actedText = text;
    let acted = false;
    // 画面 4 の中に AI の聞き返し(decision.askBack が true)が出たときは、画面は、聞き返しの選択肢のほかの、いまの画面の入力と主なボタンを押せなくする(index.html の hearGates と lockBelowAsk)。
    // 画面 4 のほかの操作より先に、聞き返しの選択肢のうち推奨(オブジェクトの recommend が true か、末尾が「(推奨)」の文。index.html の normChoice と同じ)を押し、推奨がなければ 1 つ目を押す
    if (screen === '画面 4' && s.decision && s.decision.askBack === true && (s.decision.choices || []).length) {
      const asks = page.locator('#hearbody .decision[data-ask="true"] .choices button.choice');
      if ((await asks.count()) && !(await asks.first().isDisabled())) {
        const askLabel = c => String(c && typeof c === 'object' ? c.label ?? '' : c);
        const recommended = s.decision.choices.findIndex(c => (c && typeof c === 'object' && c.recommend === true) || /[((]推奨[))]$/.test(askLabel(c)));
        const index = recommended >= 0 ? recommended : 0;
        const label = askLabel(s.decision.choices[index]);
        const usersBefore = parseUsers(conversationOf(rel)).length;
        console.log(`操作: 画面 4 の聞き返し「${s.decision.question}」で「${label}」を押す`);
        await asks.nth(index).click();
        await until(() => busyOf(page), 10000);
        await until(async () => !(await busyOf(page)), 25 * 60 * 1000);
        await sleep(2500);
        const users = parseUsers(conversationOf(rel));
        // 画面は、聞き返しの選択肢の文をそのまま送る。直した答えがたまっているときは、2 行目から「直した答え」の行を添える(index.html の send)
        check('画面 4 の聞き返しの選択肢を押すと、送る文の 1 行目が、押した選択肢の文(聞き返しの答え)になる', users.length > usersBefore && (users.at(-1) || '').split('\n')[0].trim() === label.trim(), users.at(-1));
        actedText = null;
        stuck = 0;
        continue;
      }
    }
    if (screen === '画面 4' && s.questions && backs.length) {
      let pressed = null;
      const usersBefore = parseUsers(conversationOf(rel)).length;
      for (const name of backs) if (await backStep(page, name)) { pressed = name; break; }
      if (pressed) {
        backs.splice(backs.indexOf(pressed), 1);
        console.log(`操作: 画面 4 で「${pressed}」を押す`);
        if (navBacks.includes(pressed)) {
          await sleep(2500);
          check(`画面 4 の「${pressed}」は AI に送らない(画面遷移設計書の章 11)`, parseUsers(conversationOf(rel)).length === usersBefore && !(await busyOf(page)), String(parseUsers(conversationOf(rel)).length - usersBefore));
          actedText = null;
          stuck = 0;
          continue;
        }
        await until(() => busyOf(page), 10000);
        await until(async () => !(await busyOf(page)), 25 * 60 * 1000);
        await sleep(2500);
        const users = parseUsers(conversationOf(rel));
        check(`画面 4 の「${pressed}」は画面遷移設計書の章 11 の送る文を送る`, backSent[pressed](users.at(-1) || ''), users.at(-1));
        const after = stateOf(rel);
        const gaps = stateContractGaps(after);
        check(`画面 4 で「${pressed}」を押したあとの state.json は state-contract に合う`, gaps.length === 0, gaps.join(' / '));
        // 次の回で、ほかの画面と同じく「AI の返事のあとに押せるものがある」を確かめる
        actedText = null;
        stuck = 0;
        continue;
      }
    }
    if (screen === '画面 5' && stopScreen && s.draftReview) {
      const draftText = JSON.stringify(s.draftReview);
      if (fix.sent && !fix.seen) {
        fix.seen = true;
        check('画面 5 の直しが AI に届き、下書きの値が変わる', draftText.includes(fix.marker), draftText.slice(0, 300));
        check('画面 5 の直したあとの値が画面に出る', includesText(bodyNow, fix.marker), bodyNow.slice(0, 300));
        check('画面 5 に、直した知らせが出る', bodyNow.includes('を直しました'), bodyNow.slice(0, 300));
      }
      if (!fix.sent) {
        fix.sent = true;
        await page.locator('#hearfoot .btn', {hasText: '内容を修正する'}).click();
        const area = page.locator('#hearbody .ze textarea').last();
        const label = await area.getAttribute('aria-label');
        const before = await area.inputValue();
        await area.fill(`${before}(${fix.marker})`);
        fix.label = label;
        await photo('画面5の修正の入力');
        console.log(`操作: 画面 5 の「${label}」を直して「この内容に直す」を押す`);
        await page.locator('#hearfoot .btn.pri', {hasText: 'この内容に直す'}).click();
        acted = true;
      }
    }
    if (screen === '画面 4' && stopScreen && s.questions && !acted) {
      const multi = s.questions.items.filter(i => i.multiple === true && (i.choices || []).length).length;
      reached4.multiple += multi;
      reached4.parts += s.questions.items.filter(i => (i.parts || []).length).length;
      reached4.files += s.questions.items.filter(i => (i.files || []).length).length;
      // 画面は、いま出ているページのカテゴリーの問いだけを出すので、比べる数もそのページの問いで数える
      const shownMulti = shown.items.filter(i => i.multiple === true && (i.choices || []).length).length;
      check(`画面 4 の複数を選べる問いがチェックで出る(${shown.name || s.questions.title})`, (await page.locator('#hearbody fieldset.zqs:has(.zops input[type=checkbox])').count()) === shownMulti, String(shownMulti));
      if (sentAnswers.length && !answersViewed) {
        answersViewed = true;
        await page.locator('#hearfoot .ghost', {hasText: 'これまでの答えの一覧'}).click();
        const list = await page.locator('#hearbody').innerText();
        check('これまでの答えの一覧に、前のカテゴリーの答えが出る', sentAnswers.every(a => includesText(list, a)), list.slice(0, 300));
        await photo('これまでの答え');
        await page.locator('#hearfoot .btn.pri', {hasText: '質問に戻る'}).click();
      }
      if (!hosokuSent) {
        // 補足の文も AI に届くことを、最初の問いで確かめる
        hosokuSent = true;
        const first = page.locator('#hearbody fieldset.zqs').first();
        const more = first.locator('details.zmore');
        if (!(await more.evaluate(e => e.open))) await more.locator('summary').click();
        await first.locator('details.zmore textarea').fill('確認の語 ZQ4補足');
      }
    }
    if (screen === '画面 5' && stopScreen && !acted && s.decision) {
      const main = page.locator('#hearfoot .btn.pri').last();
      const label = await main.innerText();
      check(`画面 5 の主なボタン「${label}」は、AI の選択肢にある`, s.decision.choices.some(c => plainChoice(c) === label), JSON.stringify(s.decision.choices));
    }
    // 段階 1 が終わったのに画面 6 を書かなかったときは、次の段階へ進めず、費用をかけずに止まる
    if (stopScreen && !screen && !acted && s.artifacts[0] && s.artifacts[0].status === '済み') {
      check('段階 1 の完了のあとに AI が screen を「画面 6」と書く', false, `screen=null decision=${JSON.stringify(s.decision)}`);
      break;
    }
    if (screen === '画面 5' && stopScreen && !acted && (s.draftReview?.checks || []).length) {
      check('画面 5 の確かめる点が選択肢で出る', (await page.locator('#hearbody fieldset.zqs .zop').count()) >= s.draftReview.checks.length);
      await photo('画面5の確かめる点');
      waitingChecks = true;
    }
    if (screen && !acted) acted = await hearingStep(page, stopScreen ? textAnswer : '今はまだない');
    else if (!acted && await formOpen(page)) { for (const row of await page.locator('#qform .qi').all()) await answerer('今はまだない')(row, s); await sendAnswers(page); acted = true; }
    else if (!acted && await page.locator('.decision .choice:not([disabled])').count()) { console.log(`操作: 前の形の選択肢「${await page.locator('.decision .choice').first().innerText()}」を押す`); await page.locator('.decision .choice').first().click(); acted = true; }
    else if (!acted && await page.locator('#messages .chips .chip').count()) { await page.locator('#messages .chips .chip').first().click(); await page.press('#input', 'Enter'); acted = true; }
    // 選択肢のない問いは、下の 1 行の上の候補か自由な文で答える
    if (!acted && screen && await page.locator('#replies:not([hidden])').count()) {
      const chip = page.locator('#replies .zchip').first();
      if (await chip.count()) await chip.click(); else await page.fill('#input', textAnswer(s.decision ? s.decision.question : ''));
      console.log(`操作: AI からの問いに下の 1 行で答える: ${await page.inputValue('#input')}`);
      await page.press('#input', 'Enter');
      acted = true;
    }
    if (!acted) { check('AI の返事のあとに押せるものがある', false, `screen=${screen} decision=${JSON.stringify(s.decision)}`); break; }
    await until(() => busyOf(page), 10000);
    if (waitingChecks) {
      waitingChecks = false;
      const lines = parseUsers(conversationOf(rel)).at(-1).split('\n').filter(l => l.startsWith('確かめる点'));
      check('確かめる点で選んだ読みが「ユーザー:」の行で AI へ送られる', lines.length > 0, parseUsers(conversationOf(rel)).at(-1));
      pickedReadings.push(...lines.map(l => l.slice(l.lastIndexOf('): ') + 3)));
    }
    if (screen === '画面 4' && stopScreen && s.questions) {
      // 画面が送った「番号: 答え」の行と、前の回の答えを直したときに添える「直した答え <記録の番号>: 答え」の行(画面遷移設計書の T27)から、選択肢の文と補足の文を取り出す。
      // <記録の番号> は「6-1」「16」「深掘り 1」のような聞き取りの記録の番号で、記録の番号を持たない古い形の state.json では回の中の番号。どちらも最初の「: 」までとする
      // 今の回の問いの数と比べるのは「番号: 答え」の行だけ。直した答えの行は、前の回の問いの答えなので、数えない
      const users = parseUsers(conversationOf(rel));
      const rows = users.at(-1).split('\n');
      const lines = rows.filter(l => /^\d+:/.test(l)).map(l => l.replace(/^\d+:\s*/, ''));
      const edits = rows.filter(l => /^直した答え .+?:\s/.test(l)).map(l => l.replace(/^直した答え .+?:\s*/, ''));
      const answers = [...lines, ...edits].flatMap(l => { const m = l.match(/^(.*)[((]補足: (.*)[))]$/); return m ? [plainChoice(m[1]), m[2]] : [plainChoice(l)]; }).filter(Boolean);
      sentAnswers.push(...answers);
      waitingAnswers = {title: s.questions.title, answers: [...carriedAnswers, ...answers]};
      carriedAnswers = [];
      const sentText = s.questions.items.filter(i => i.answer == null).length;
      check(`画面 4 の答えが「ユーザー:」の行で AI へ送られる(${s.questions.title})`, lines.length === sentText, users.at(-1));
    }
  }
  onPageTurn = null;
  clearInterval(watch);
  const rel = workRel();
  fs.writeFileSync(path.join(dir, 'visited.json'), JSON.stringify(visited, null, 2) + '\n');
  if (rel) fs.cpSync(path.join(sf, rel, 'ui', 'conversation.md'), path.join(dir, 'conversation.md'));
  console.log(`通った画面の順: ${visited.join(' → ')}`);
  const hasInOrder = list => { let i = 0; for (const v of visited) if (v === list[i]) i++; return i === list.length; };
  check('画面 2 に届く', visited.includes('画面 2'));
  check('調査を通って画面 3 に届く', hasInOrder(['画面 2', '画面 3']) && screens.some(x => x.screen === '調査'), screens.map(x => x.screen).join(' → '));
  if (!stopScreen) check('画面 3 の答えのあとに次の画面へ進む', after3 === 1, visited.join(' → '));
  check('AI が書いたすべての state.json は 16 のキーを持つ', screens.every(x => x.keys.length === 0), JSON.stringify(screens.filter(x => x.keys.length)));
  check('画面のスクリプトのエラーがない', errors.length === 0, errors.join(' / '));
  if (stopScreen) {
    // 段階 1 は、問いのあとに下書きの承認(画面 5)へ進む
    check('画面 4、画面 5 の順に通って画面 6 に届く', reached && hasInOrder(['画面 3', '画面 4', '画面 5', '画面 6']), visited.join(' → '));
    check('画面 5 の「内容を修正する」を 1 回使い、直しが下書きへ戻る', fix.sent && fix.seen, JSON.stringify(fix));
    check('画面 4 で「前へ」「この質問に戻る」「分からない」を 1 回ずつ押す', backs.length === 0, `押せなかった道: ${backs.join('、')}`);
    const files = {'要件定義書.md': rel ? path.join(sf, rel, '要件定義書.md') : '', '聞き取りの記録.md': rel ? path.join(sf, rel, '聞き取りの記録.md') : ''};
    for (const [name, p] of Object.entries(files)) {
      const has = !!p && fs.existsSync(p) && fs.statSync(p).size > 0;
      check(`${name} が書かれる`, has, p);
      if (has) fs.cpSync(p, path.join(dir, name));
    }
    if (reached && fs.existsSync(files['要件定義書.md'])) {
      const doc = fs.readFileSync(files['要件定義書.md'], 'utf8');
      const record = fs.readFileSync(files['聞き取りの記録.md'], 'utf8');
      const shown = await page.locator('#hearbody').innerText();
      // md の表示の後の文と比べる。見出しと表の記号を外した行が、画面の全文にある
      const docLines = doc.split('\n').filter(l => /^#+ /.test(l)).map(l => l.replace(/^#+\s*/, '').replace(/[`*]/g, ''));
      const notShown = docLines.filter(l => !includesText(shown, l));
      check('画面 6 に、要件定義書の全文の見出しが出る', docLines.length > 0 && notShown.length === 0, notShown.join(' / '));
      check('画面 6 に、書いた先のパスが出る', (await page.locator('#hearfoot .zpth').innerText()).includes('要件定義書.md'));
      check('画面 6 のダウンロードは、書いた要件定義書を返す', (await page.evaluate(() => fetch(document.querySelector('#hearfoot a.btn').href).then(r => r.text()))) === doc);
      check('画面 6 に、次の作業へ進むボタンがあり、押せる', await page.locator('#hearfoot .btn.pri:not([disabled])', {hasText: '次の作業へ進む'}).count() === 1);
      check('画面 4 で送ったすべての答えが聞き取りの記録にある', sentAnswers.length > 0 && sentAnswers.every(a => includesText(record, recordedWord(a))), sentAnswers.filter(a => !includesText(record, recordedWord(a))).join(' / '));
      check('補足の文が聞き取りの記録にある', record.includes('ZQ4補足'));
      console.log(`通った道: 確かめる点で選んだ読み ${pickedReadings.length} 件、複数を選べる問い ${reached4.multiple} 問、必ず入れる部分の欄 ${reached4.parts} 問、要るファイルの欄 ${reached4.files} 問`);
      if (pickedReadings.length) check('確かめる点で選んだ読みが聞き取りの記録にある', pickedReadings.every(a => includesText(record, a)), pickedReadings.filter(a => !includesText(record, a)).join(' / '));
      if (pickedReadings.length) check('確かめる点で選んだ読みが要件定義書にある', pickedReadings.every(a => includesText(doc, a)), pickedReadings.filter(a => !includesText(doc, a)).join(' / '));
      fs.writeFileSync(path.join(dir, '画面6の全文.txt'), shown);
      check('画面 5 の直しが要件定義書にある', doc.includes(fix.marker));
      check('画面 5 の直しが聞き取りの記録にある', record.includes(fix.marker));
      check('作業の state.json の documentPath は要件定義書を指す', stateOf(rel).documentPath.endsWith('要件定義書.md'), stateOf(rel).documentPath);
    }
  }
  if (fs.existsSync(streamLog)) {
    const lines = fs.readFileSync(streamLog, 'utf8').split('\n').filter(Boolean).flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } });
    const results = lines.filter(l => l.type === 'result');
    const costs = results.map(l => l.total_cost_usd || 0);
    // total_cost_usd は、同じ会話の --resume で足し上がる値なので、最後の値が会話の合計である。差が呼び出しごとの費用である
    console.log(`呼び出し ${costs.length} 回、費用の合計 ${(costs.at(-1) || 0).toFixed(2)} ドル、呼び出しごとの費用 ${costs.map((c, i) => (c - (costs[i - 1] || 0)).toFixed(2)).join('、')}`);
    console.log(`呼び出しごとの秒: ${results.map(r => Math.round((r.duration_ms || 0) / 1000)).join('、')}`);
    const asks = contents(lines).filter(c => c.type === 'tool_use' && c.name === 'AskUserQuestion').length;
    console.log(`AskUserQuestion の呼び出し: ${asks} 回`);
  }
}
// conversation.md の「ユーザー:」の件の本文を、順に返す
// 聞き取りの画面が送った答え。「<番号>: <答え>」の行のうち、段階 2 を始める文より前のもの
function hearingAnswers(text) {
  const users = parseUsers(text);
  const next = users.findIndex(u => u.startsWith('次の作業へ進む'));
  return users.slice(0, next < 0 ? users.length : next).flatMap(u => u.split('\n')).map(l => (l.match(/^\d+: (.+)$/) || [])[1]).filter(Boolean).map(plainChoice);
}
function parseUsers(text) {
  const list = [];
  let current = null;
  for (const line of text.split('\n')) {
    const m = line.match(/^(ユーザー|Claude Code): ?(.*)$/);
    if (m) { current = m[1] === 'ユーザー' ? [m[2]] : null; if (current) list.push(current); }
    else if (current) current.push(line);
  }
  return list.map(l => l.join('\n').trim());
}

// 本物の ui/ と output/ の一覧と更新日時。テストの前後で同じことを確かめる
function snapshot() {
  return spawnSync('find', ['output', 'ui', '-path', 'ui/tests', '-prune', '-o', '-type', 'f', '-exec', 'stat', '-f', '%N %m', '{}', '+'], {cwd: factory, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024}).stdout;
}

async function main() {
  const settings = path.join(os.homedir(), '.claude', 'settings.json');
  console.log(`claude の版: ${spawnSync('claude', ['--version'], {encoding: 'utf8'}).stdout.trim()}`);
  if (fs.existsSync(settings)) console.log(`~/.claude/settings.json の SHA-256: ${spawnSync('shasum', ['-a', '256', settings], {encoding: 'utf8'}).stdout.split(' ')[0]}`);
  if (scenario === 'contract') return contract();
  port = await freePort();
  url = `http://127.0.0.1:${port}/`;
  makeCopy();
  const before = snapshot();
  try {
    setCase(scenarioNames[scenario]);
    if (scenario === 'hearing-screens') await hearingFlow();
    if (scenario === 'hearing-to-written') await hearingFlow('画面 6');
    if (scenario === 'until-stage-3') await stageFlow(3);
    if (scenario === 'until-stage-8') await stageFlow(8);
    if (scenario === 'check-skill') await checkFlow();
    if (scenario === 'session-lost') await lostFlow();
  } finally {
    check('本物の ui/ と output/ を変えない', snapshot() === before);
  }
}

main().catch(e => { setCase('全体'); check('テストの実行', false, e.stack); }).finally(async () => {
  await stopServer();
  if (browser) await browser.close();
  process.exit(finish([], false));
});
