#!/usr/bin/env node
// テスト自体の検証。不具合を 1 件ずつ ui/ の写しに入れ、指定のケースが不合格になることを確かめる。AI はモックだけを使う。
// 使い方: skill-factory/ で `node ui/tests/test-mutants.mjs`。終了コード 0 が、すべての不具合を見つけられたことを指す。
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const uiDir = path.dirname(testsDir);
const factory = path.dirname(uiDir);
const mapRef = '../output/updating-skill-factory-ui-state/references/段階のスキルの表示と state.json の値の対応表.md';
const shapeRef = '../output/updating-skill-factory-ui-state/references/画面の状態のファイルの形.md';

// file: 変えるファイル(ui/ からの相対パス)、from: 変える前の文、to: 変えた後の文、program と kase: 不合格になるはずのケース
const mutants = [
  {name: '--resume と --session-id の入れ替え', file: 'server.mjs', from: "sessionStarted ? '--resume' : '--session-id'", to: "sessionStarted ? '--session-id' : '--resume'", program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: 'Origin の確認を消す', file: 'server.mjs', from: "if (req.method === 'POST' && crossOrigin(req)) return send(res, 403, 'ほかのサイトからの送信です');", to: '', program: 'test-relay-edge.mjs', kase: "Origin の確認"},
  {name: '「画面:」の行を変える', file: 'server.mjs', from: '`画面: ${dir', to: '`画: ${dir', program: 'test-relay-edge.mjs', kase: "仮の会話"},
  {name: '同時の送信の 409 を消す', file: 'server.mjs', from: "if (busy) return send(res, 409, 'Claude Code が前の文の返事を書いています。返事のあとに送ってください。');", to: '', program: 'test-relay-edge.mjs', kase: "同時の送信"},
  {name: '/files/ の範囲の確認を消す', file: 'server.mjs', from: "if (!file.startsWith(dir + path.sep)) return send(res, 403, '作業のフォルダの外のファイルです');", to: '', program: 'test-relay-edge.mjs', kase: "GET /files/"},
  {name: 'sessionLost を常に false にする', file: 'server.mjs', from: 'function sessionLost() {', to: 'function sessionLost() {\n  return false;', program: 'test-relay-edge.mjs', kase: "壊れた session.json"},
  {name: 'サブエージェントの数を減らさない', file: 'server.mjs', from: 'openAgents.delete(c.tool_use_id)', to: 'void c.tool_use_id', program: 'test-relay-edge.mjs', kase: "スキルとサブエージェントの数え方"},
  {name: '仮の会話を消さない', file: 'server.mjs', from: '      fs.rmSync(pending);\n', to: '', program: 'test-relay-edge.mjs', kase: "仮の会話"},
  {name: 'SIGINT で子プロセスを止めない', file: 'server.mjs', from: "process.on('SIGINT', shutdown);\nprocess.on('SIGTERM', shutdown);\nprocess.on('SIGHUP', shutdown);\nprocess.on('exit', killChild);", to: "process.on('SIGINT', () => { process.exit(0); });", program: 'test-relay-edge.mjs', kase: "中継サーバーを止めるときの子プロセス"},
  {name: '終了コードの行を書かない', file: 'server.mjs', from: "if (code !== 0) append('Claude Code', `(終了コード ${code ?? signal})", to: "if (false) append('Claude Code', `(終了コード ${code ?? signal})", program: 'test-relay-edge.mjs', kase: "claude の終わり方"},
  {name: '画面から動かす claude への指示を消す', file: 'server.mjs', from: "'--append-system-prompt', screenPrompt", to: '', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '複数を選べる問いをチェックにしない', file: 'index.html', from: "input.type = many ? 'checkbox' : 'radio';", to: "input.type = 'radio';", program: 'test-screen.mjs', kase: "画面 4 の複数を選べる問い"},
  {name: 'モデルの引数を消す', file: 'server.mjs', from: "'--model', model,", to: '', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '会話が見つからないときの処理を消す', file: 'server.mjs', from: 'if (noConversation) {', to: 'if (false) {', program: 'test-screen.mjs', kase: "--resume の会話が見つからない作業で答える"},
  {name: '読み直しの間隔を 20 秒にする', file: 'index.html', from: 'setInterval(load, 2000);', to: 'setInterval(load, 20000);', program: 'test-screen.mjs', kase: "読み直しの間隔"},
  {name: '変換中の Enter を送る', file: 'index.html', from: " && !e.isComposing", to: '', program: 'test-screen.mjs', kase: "入力欄の操作"},
  {name: '答えていない問いも送る', file: 'index.html', from: "const lines = rest.filter(i => (qAnswers[i.number] || '').trim()).map(", to: 'const lines = rest.map(', program: 'test-screen.mjs', kase: "質問の一覧に答える"},
  {name: '元の不具合: 送信に作業のフォルダを添えない', file: 'index.html', from: 'workDir: state ? seenWorkDir : null', to: 'workDir: null', program: 'test-screen.mjs', kase: "中継サーバーだけを起動し直し、画面を読み直さずに答える"},
  {name: '送れなかった答えを入力欄に戻す(続けられないときも)', file: 'index.html', from: 'else if (!status.sessionLost) {', to: 'else {', program: 'test-screen.mjs', kase: "session.json がない作業で、読み直さずに答える"},
  {name: '「続きから」の失敗でボタンを戻さない', file: 'index.html', from: "$('err').textContent = '続けられませんでした。' + error; b.disabled = false; return;", to: "$('err').textContent = '続けられませんでした。' + error; return;", program: 'test-screen.mjs', kase: "「続きから」の失敗"},
  {name: '聞き取りの画面を出さない', file: 'index.html', from: "if (state) return state.screen in HEAR_LABEL ? state.screen : null;", to: 'if (state) return null;', program: 'test-screen.mjs', kase: "画面 2 のまとめと、はい"},
  {name: '画面 2 の「はい」で AI の選択肢の文を使わない', file: 'index.html', from: "on: () => hearSend(choiceText('はい'))", to: "on: () => hearSend('はい')", program: 'test-screen.mjs', kase: "画面 2 のまとめと、はい"},
  {name: '変えていない行も送る', file: 'index.html', from: "return list.filter(x => hear.drafts[x.key] !== undefined && hear.drafts[x.key].trim() !== String(x.value).trim());", to: "return list.filter(x => hear.drafts[x.key] !== undefined);", program: 'test-screen.mjs', kase: "画面 3 の事実確認と修正"},
  {name: '案を最後まで見なくても進める', file: 'index.html', from: "if (sc.scrollTop + sc.clientHeight >= sc.scrollHeight - 8) hear.gate = true;", to: "hear.gate = true;", program: 'test-screen.mjs', kase: "AI の案の承認"},
  {name: '「出し方」の外部への書き込みを消す', file: 'index.html', from: "'チャットへの表示', '外部への書き込み(コミット、投稿、Issue)'];", to: "'チャットへの表示'];", program: 'test-screen.mjs', kase: "AI の案の承認"},
  {name: '確かめる点があるときも承認を頼む文を出す', file: 'index.html', from: "hasChecks ? '確かめる点の読みを選んでください。' : ", to: '', program: 'test-screen.mjs', kase: "画面 5 の確かめる点"},
  {name: '「やめる」の作業を一覧から外さない', file: 'server.mjs', from: "if (fs.existsSync(path.join(outputDir, name, 'ui', 'stopped.json'))) continue;", to: '', program: 'test-relay-edge.mjs', kase: "あとで続けるとやめるで作業を離れる"},
  {name: '画面 6 の書き終えた表示を出さない', file: 'index.html', from: "const written = hearNow() === '画面 6' && !busy;", to: 'const written = false;', program: 'test-screen.mjs', kase: "画面 6 の全文とダウンロード"},
  {name: '画面 6 のダウンロードを先頭の 1 件だけにする', file: 'index.html', from: 'const files = state.downloads.length ? state.downloads : [state.documentPath];', to: 'const files = [state.downloads[0] || state.documentPath];', program: 'test-screen.mjs', kase: "画面 6 の全文とダウンロード"},
  {name: '承認の下の文を改行しない', file: 'index.html', from: "承認してください。\\n全文は", to: '承認してください。全文は', program: 'test-screen.mjs', kase: "画面 5 の下書きと承認"},
  {name: '指示から規約を全文読ませる文を消す', file: 'server.mjs', from: "を全文読み、そのとおりに行う。", to: 'のとおりに行う。', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '指示から対応表の行を指す文を消す', file: 'server.mjs', from: "の「step 5-1 で調べ始める前に state.json を書く時点」の行のとおりに書く。", to: 'のとおりに書く。', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '読ませる規約から画面 6 で止まる決まりを消す', file: '../.claude/rules/skill-making-flow/skill-making-flow-rule.md', from: "キー `screen` を「画面 6」、キー `decision` を `null` にして止まる", to: '止まる', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '指す対応表の行から調査の値を消す', file: mapRef, from: "`screen` は「調査」。`rows` は、調査の行のすべて", to: '`rows` は、調査の行', program: 'test-relay-edge.mjs', kase: "claude の呼び方"},
  {name: '対応表から multiple の決まりを消す', file: mapRef, from: "`multiple` が問いの雛形の表の列「数」が「複数」の問いで true、ほかの問いで false、", to: '', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: '対応表から parts と files の行を消す', file: mapRef, from: "| `questions.items[].parts`、`questions.items[].files` |", to: '| `questions.items[]` |', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: '対応表から checks の行を消す', file: mapRef, from: "| `draftReview.checks[]` |", to: '| `draftReview` |', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: '型の表にある欄を雛形から消す', file: shapeRef, from: '"reason": "<聞く理由の文>", ', to: '', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: '雛形にある欄を型の表から消す', file: shapeRef, from: '"example": 文字列か null, ', to: '', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: 'テストの makeState からキーを消す', file: 'tests/lib/report.mjs', from: "screen: null, ", to: '', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: 'テストの threeQuestions の要素から欄を消す', file: 'tests/lib/report.mjs', from: "multiple: false, ", to: '', program: 'test-static.mjs', kase: "state.json のキー"},
  {name: 'state.json の更新で図の欄を畳んだままにする', file: 'index.html', from: '  $(\'figbox\').hidden = !state.figures.length || questionsOpen();', to: '  $(\'figbox\').hidden = true;', program: 'test-screen.mjs', kase: "段階の帯と文書と図とダウンロード"},
];

const root = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'sf-mutants.'));
// test-static.mjs と test-relay-edge.mjs が読む ui/ の外のファイルも、写しに置く。.claude/ は、変える規約だけを実体にする
const outside = ['README.md', '.claude/rules/skill-making-flow/skill-making-flow-rule.md', 'output/updating-skill-factory-ui-state/references'];
let missed = 0;
const freshCopy = () => {
  const copy = path.join(root, 'ui');
  fs.rmSync(copy, {recursive: true, force: true});
  fs.cpSync(uiDir, copy, {recursive: true, filter: p => {
    const rel = path.relative(uiDir, p);
    return !rel.startsWith(path.join('tests', 'node_modules')) && !/^tests\/20\d\d-/.test(rel);
  }});
  fs.symlinkSync(path.join(testsDir, 'node_modules'), path.join(copy, 'tests', 'node_modules'));
  fs.rmSync(path.join(root, '.claude'), {recursive: true, force: true});
  fs.rmSync(path.join(root, 'output'), {recursive: true, force: true});
  for (const rel of outside) fs.cpSync(path.join(factory, rel), path.join(root, rel), {recursive: true});
  fs.symlinkSync(path.join(factory, '.claude', 'skills'), path.join(root, '.claude', 'skills'));
  return copy;
};
const runCase = (copy, m) => spawnSync('node', [path.join(copy, 'tests', m.program), '--case', m.kase], {encoding: 'utf8', timeout: 180000, maxBuffer: 64 * 1024 * 1024});
// 不具合を入れる前に合格することを確かめる。環境の理由の失敗を「見つけた」と数えないため
const baseline = new Set();
for (const m of mutants) {
  const key = `${m.program} ${m.kase}`;
  if (baseline.has(key)) continue;
  baseline.add(key);
  const r = runCase(freshCopy(), m);
  if (r.status !== 0) { console.log(`不合格: 不具合を入れる前に ${key} が合格しない`); missed++; }
}
for (const m of mutants) {
  const copy = freshCopy();
  const target = path.join(copy, m.file);
  const source = fs.readFileSync(target, 'utf8');
  if (!source.includes(m.from)) { console.log(`不合格: ${m.name}: 変える前の文がファイルにない`); missed++; continue; }
  fs.writeFileSync(target, source.replace(m.from, m.to));
  const r = runCase(copy, m);
  if (r.status !== 1 || !r.stdout.split('\n').some(l => l.startsWith(`不合格: ${m.kase}: `))) { console.log(`不合格: ${m.name}: ${m.program} のケース ${m.kase} が合格のまま`); missed++; }
  else console.log(`合格: ${m.name}: ${m.program} のケース ${m.kase} が不合格になる`);
}
fs.rmSync(root, {recursive: true, force: true});
console.log(`集計: ${mutants.length} 件のうち、見つけられなかった不具合 ${missed} 件`);
process.exit(missed ? 1 : 0);
