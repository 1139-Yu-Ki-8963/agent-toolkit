// テストの合否の出力と、既知の不合格の扱い。
// 既知の不合格(known-failures.json)のケースは、不合格でも全体の合否に数えない。合格したら、一覧の消し忘れとして不合格にする。
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const known = JSON.parse(fs.readFileSync(path.join(here, '..', 'known-failures.json'), 'utf8'));
export const seen = new Set();
export const totals = {pass: 0, fail: 0, known: 0};

// 項目の名前は「ケースの名前: 項目の名前」とする
let currentCase = '';
export const setCase = name => { currentCase = name; };

export function check(name, cond, detail) {
  const label = `${currentCase}: ${name}`;
  seen.add(label);
  if (label in known) {
    if (cond) { totals.fail++; console.log(`不合格: ${label}: 直ったので known-failures.json から消す`); }
    else { totals.known++; console.log(`既知の不合格: ${label}`); }
    return;
  }
  if (cond) { totals.pass++; console.log(`合格: ${label}`); return; }
  totals.fail++;
  console.log(`不合格: ${label}${detail === undefined ? '' : `: ${detail}`}`);
}

// 全部流したときだけ、一覧にあるのに流れなかった番号を不合格にする
export function finish(caseNames, full) {
  if (full) for (const key of Object.keys(known)) {
    if (caseNames.some(c => key.startsWith(`${c}: `)) && !seen.has(key)) { totals.fail++; console.log(`不合格: ${key}: known-failures.json にあるのに、テストにない`); }
  }
  console.log(`集計: 合格 ${totals.pass}、不合格 ${totals.fail}、既知の不合格 ${totals.known}`);
  console.log(totals.fail ? '不合格あり' : totals.known ? `新しい不合格なし(既知の不合格 ${totals.known} 項目)` : '全件合格');
  return totals.fail ? 1 : 0;
}

export const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function until(fn, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await fn()) return true;
    await sleep(50);
  }
  return false;
}

// 空いているポートを取る(前の回の中継サーバーに当たって合格しないように、固定のポートを使わない)
export function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => { const {port} = s.address(); s.close(() => resolve(port)); });
  });
}

export const artifacts = stage => ['要件定義書', '分割設計書', '構成の案', 'SKILL.md', '照合の指摘の一覧', 'テスト計画書', 'シナリオテストの表', '判定の記録']
  .map((name, i) => ({stage: i + 1, name, status: i + 1 < stage ? '済み' : i + 1 === stage ? '下書き' : '未着手'}));

// 画面の状態のファイルの形(スキル updating-skill-factory-ui-state のリファレンス)の 16 のキーを持つ state.json の中身。回の一覧 rounds は、問いの回がまだないときの null とする
export const makeState = (over = {}) => ({workName: 'テストの作業', currentSkill: null, stage: 1, artifacts: artifacts(over.stage || 1), figures: [], documentPath: '要件定義書.md', decision: null, questions: null, rounds: null, downloads: [], screen: null, summary: null, research: null, factCheck: null, approvalSheet: null, draftReview: null, ...over});

// 問い 1 は選択肢あり、問い 2 と問い 3 は文で答える。要素はリファレンスの questions.items の欄をすべて持つ
// previous は、「戻る」で未回答に戻した問いの前の回答(問いの番号ごと)。ほかの問いの previousAnswer は null
// category は、画面 4 の問いのカテゴリーの名前(インターフェース設計書の章 2)。この 3 問は画面 4 に限らずに使うので null
const questionItem = (number, text, choices, answer, previousAnswer = null) => ({number, text, choices, answer, reason: null, example: null, results: [], previousAnswer, category: null, multiple: false, parts: [], files: []});
export const threeQuestions = (answers = {}, extra = {}, previous = {}) => ({title: '要件定義の質問', added: 0, removed: 0, notice: null, items: [
  questionItem(1, '必須にしますか', ['必須', '任意'], answers[1] ?? null, previous[1] ?? null),
  questionItem(2, '入力は何ですか', [], answers[2] ?? null, previous[2] ?? null),
  questionItem(3, '出力は何ですか', [], answers[3] ?? null, previous[3] ?? null),
], ...extra});
