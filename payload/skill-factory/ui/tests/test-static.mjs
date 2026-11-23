#!/usr/bin/env node
// 実行せずに確かめる検査。AI もブラウザも使わない。
// 使い方: skill-factory/ で `node ui/tests/test-static.mjs`。`--list` でケースの名前を出す。終了コード 0 は、すべての項目が合格か既知の不合格であることを指す。
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import {check, finish, makeState, setCase, threeQuestions} from './lib/report.mjs';
import {ADDED_KEYS, CONTRACT_TABLE, ROUND_KINDS, STAGE_TABLE, roundsGaps, roundsQuestionsGaps, stateContractGaps} from './lib/state-contract.mjs';

const caseNames = ['プログラムの構文', 'index.html のスクリプトと外部のライブラリ', '段階の表', 'state.json のキー', '画面の状態の組の照合: 画面 4 で前へを押したあとの state.json', '画面の状態の組の照合: 章 2 の表の行ごとの見本', '画面の状態の組の照合: 回の一覧', '画面の状態の組の照合: 最後の回の問いと問いの一覧の選択肢', '画面の状態の組の照合: 段階 2 から 8 の画面', '計画書とプログラムの同期', 'README の手順', 'モックの層が本物の claude を呼ばない'];
if (process.argv.includes('--list')) { for (const n of caseNames) console.log(n); process.exit(0); }

const testsDir = path.dirname(fileURLToPath(import.meta.url));
const uiDir = path.dirname(testsDir);
const factory = path.dirname(uiDir);
const read = f => fs.readFileSync(f, 'utf8');
const html = read(path.join(uiDir, 'index.html'));

setCase('プログラムの構文');
const nodeFiles = [path.join(uiDir, 'server.mjs'), ...fs.readdirSync(testsDir).filter(f => f.endsWith('.mjs')).map(f => path.join(testsDir, f))];
check('server.mjs とテストのプログラムの構文', nodeFiles.every(f => spawnSync('node', ['--check', f]).status === 0));
check('シェルのテストの構文', spawnSync('bash', ['-n', path.join(testsDir, 'test-relay.sh')]).status === 0 && spawnSync('bash', ['-n', path.join(testsDir, 'run-auto.sh')]).status === 0);

setCase('index.html のスクリプトと外部のライブラリ');
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(m => m[1]).filter(s => s.trim());
let scriptOk = scripts.length > 0;
for (const s of scripts) { try { new vm.Script(s); } catch { scriptOk = false; } }
check('index.html のスクリプトの構文', scriptOk);
const external = [...html.matchAll(/<script\s[^>]*src="([^"]+)"/g)].map(m => m[1]);
check('外部のライブラリは md の表示用の 1 本だけ(要件定義書の章 3.1)', external.length === 1 && external[0].includes('marked'), external.join(' '));
const pkg = JSON.parse(read(path.join(testsDir, 'package.json')));
check('テストが使う marked の版は画面と同じ', external[0].includes(`/marked/${pkg.devDependencies.marked}/`));
// 2026-11-10 のデザイン(2-2b、2-2c): 図と文書の欄は高さの上限を持たず、段階 2 から 8 の下の段は 1 段で「あとで続ける」を出さない。CSS の値はデザイントークンの変数で書く
const tokens = read(path.join(uiDir, 'デザイントークン.css'));
const tokenNames = new Set([...tokens.matchAll(/--([\w-]+):/g)].map(m => m[1]));
const usedTokens = [...html.matchAll(/var\(--([\w-]+)\)/g)].map(m => m[1]);
const unknownTokens = [...new Set(usedTokens.filter(n => !tokenNames.has(n)))];
check('index.html が使う変数はすべてデザイントークンにある', unknownTokens.length === 0, unknownTokens.join('、'));
check('図と文書の欄(.lpane)は高さの上限を持たない', !/\.lpane\{[^}]*max-height/.test(html) && !tokenNames.has('height-pane-max'));
const laterScript = html.slice(html.indexOf('function laterNow()'));
check('段階 2 から 8 の画面は、下の段に「あとで続ける」のボタンを作らない', !/ghost\('あとで続ける'/.test(laterScript.replace(/function laterLeave\(\)[\s\S]*?\n\}\n/, '')) && laterScript.includes("'/api/leave'"));
const twoSkills = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '2-2本.json')));
check('段階 2 の見本に、スキルが 2 本の例がある(箱の間の受け渡しの行の見本)', twoSkills.stage === 2 && twoSkills.screen === '成果物の承認' && twoSkills.skills.length === 2 && twoSkills.skills[1].handoffMatch === true);
// 2026-11-10 のデザイン(3-1b から 3-1f): 段階 3 の見本は、要点 5 行、aiValues 7 件(name、value、source)、タブ 3 つ(図: 流れ図を開く、ラベル「新しい」)、カードの幅のトークン
const stage3 = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '3.json')));
check('段階 3 の見本は、要点 5 行と aiValues 7 件(name、value、source)と、図: 流れ図を開いたタブ 3 つを持つ', stage3.summaryCard.length === 5 && stage3.aiValues.length === 7 && stage3.aiValues.every(v => ['name', 'value', 'source'].every(k => typeof v[k] === 'string') && !('step' in v)) && stage3.panels.length === 3 && stage3.panels[0].kind === '図' && stage3.panels[0].open === true && stage3.panels[0].isNew === true && stage3.panels[1].key === 'aiValues' && stage3.panels[2].path === '構成の案.md');
check('段階 3 の見本の図のファイルは ui/example にある', fs.existsSync(path.join(uiDir, 'example', stage3.panels[0].path)) && stage3.figures[0].path === stage3.panels[0].path, stage3.panels[0].path);
check('カードの幅と、図のタブを開いたときの幅と、流れ図の幅はトークンにある', ['width-card', 'width-card-wide', 'width-figure'].every(n => tokenNames.has(n)) && html.includes('.zw.wide{max-width:var(--width-card-wide)}'));
// 2026-11-10 に確定したテスト計画書の形(6-1 テストケースの承認): 段階 6 の見本は、summaryCard 3 行、panels 4 つ(section で章を指す文書のタブ。1 つ目を開き、ラベル「新しい」)、図なし。見本の文書 ui/example/tests/テスト計画書.md は、panels の section が指す章をすべて持つ
const stage6 = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '6.json')));
const planMd = read(path.join(uiDir, 'example', 'tests', 'テスト計画書.md'));
const planHeads = new Set([...planMd.matchAll(/^## (?:\d+\.\s*)?(.+?)\s*$/gm)].map(m => m[1]));
const stage6Sections = stage6.panels.flatMap(p => (typeof p.section === 'string' ? [p.section] : Array.isArray(p.section) ? p.section : []));
check('段階 6 の見本は、成果物の承認で、summaryCard 3 行と、文書のタブ 4 つ(1 つ目を開き、ラベル「新しい」。4 つ目は全文)を持ち、図を持たない', stage6.stage === 6 && stage6.screen === '成果物の承認' && stage6.summaryCard.length === 3 && stage6.figures.length === 0 && stage6.panels.length === 4 && stage6.panels.every(p => p.kind === '文書' && p.path === 'tests/テスト計画書.md') && stage6.panels[0].open === true && stage6.panels[0].isNew === true && Array.isArray(stage6.panels[0].section) && stage6.panels[0].section.length === 2 && typeof stage6.panels[1].section === 'string' && typeof stage6.panels[2].section === 'string' && stage6.panels[3].section === null);
check('段階 6 の見本の panels の section は、すべて見本のテスト計画書の「## 」の章にある', stage6Sections.length === 4 && stage6Sections.every(s => planHeads.has(s)), stage6Sections.filter(s => !planHeads.has(s)).join('、'));
check('見本のテスト計画書は、2026-11-10 に確定した形の章 1 から 9 を持つ', ['対象と環境', 'テストの対象の一覧', 'テスト観点の一覧', '使わなかった技法と理由', 'テストケースの一覧', '前提の状況として置くファイルとコマンド', '網羅の証明', '合否と中断の基準', 'テストの成果物'].every(s => planHeads.has(s)), [...planHeads].join('、'));
check('段階 6 の K1(上書きの確認)の見本は 6-K1.json にある', JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '6-K1.json'))).screen === '上書きの確認');
// 2026-11-10 のデザイン(7-1v から 7-1f): 段階 7 の見本は、ranges 3 行(cases を持つ)、summaryCard 2 行(実施しないケース、静的なテスト)、scenarios 12 本(11 列を出す欄)、タブ 3 つ(図: 受け持つテストケースを開く、ラベル「新しい」)
const stage7 = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '7.json')));
const stage7Reason = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '7-reason.json')));
check('段階 7 の見本は、ranges 3 行(cases を持つ)と summaryCard 2 行と scenarios 12 本と、図: 受け持つテストケースを開いたタブ 3 つを持つ', stage7.ranges.length === 3 && stage7.ranges.every(r => Number.isInteger(r.cases)) && stage7.ranges[0].recommend === true && stage7.summaryCard.map(r => r.name).join(',') === '流さないケース,スクリプトで確かめるテスト' && stage7.scenarios.length === 12 && stage7.scenarios.every(s => Number.isInteger(s.order) && typeof s.phases === 'string' && typeof s.setup === 'string' && (s.reason === null || typeof s.reason === 'string')) && stage7.panels.length === 3 && stage7.panels[0].kind === '図' && stage7.panels[0].open === true && stage7.panels[0].isNew === true && stage7.panels[1].key === 'scenarios' && stage7.panels[2].path === 'tests/テスト計画書.md');
check('段階 7 の見本の図のファイルは ui/example にある', fs.existsSync(path.join(uiDir, 'example', stage7.panels[0].path)) && stage7.figures[0].path === stage7.panels[0].path && /7-1-シナリオテストが受け持つテストケース\.svg$/.test(stage7.panels[0].path), stage7.panels[0].path);
check('段階 7 の却下の理由の見本は、承認の見本と同じ ranges、summaryCard、scenarios を持つ', ['ranges', 'summaryCard', 'scenarios'].every(k => JSON.stringify(stage7[k]) === JSON.stringify(stage7Reason[k])) && stage7Reason.screen === '却下の理由');
// 2026-11-10 に確定した 8 章の仕様(8-2 テストの結果): 段階 8 の見本は、result と、panels 5 つ(図を開き、ラベル「新しい」。section を持つ文書 3 つと、全文 1 つ)。見本の文書 ui/example/tests/判定の記録.md は、判定の記録の雛形の章と列を持ち、ケースごとの判定が 12 件
const stage8 = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '8.json')));
const recordMd = read(path.join(uiDir, 'example', 'tests', '判定の記録.md'));
const recordHeads = [...recordMd.matchAll(/^## (.+?)\s*$/gm)].map(m => m[1]);
const stage8Sections = stage8.panels.map(p => p.section).filter(s => typeof s === 'string');
check('段階 8 の見本は、テストの結果で、図: 判定の結果の図を開いたタブ(ラベル「新しい」)と、判定の記録の章を指す文書のタブ 3 つと、全文のタブ 1 つを持つ', stage8.stage === 8 && stage8.screen === 'テストの結果' && stage8.panels.length === 5 && stage8.panels[0].kind === '図' && stage8.panels[0].open === true && stage8.panels[0].isNew === true && /8-1-判定の結果の図\.svg$/.test(stage8.panels[0].path) && stage8.panels.slice(1).every(p => p.kind === '文書' && p.path === 'tests/判定の記録.md' && p.open === false) && stage8Sections.join(',') === 'ケースごとの判定,実行時の網羅の証明,未実施の実行' && stage8.panels[4].section === null && stage8.panels.map(p => p.name).join(',') === '判定の結果の図,1. ケースごとの判定,2. 実行時の網羅の証明,3. 未実施の実行,判定の記録(全文)', stage8.panels.map(p => p.name).join(','));
check('段階 8 の見本の図のファイルは ui/example にあり、判定の結果の図の雛形の合計の箱 4 つとケースの箱 12 個を持つ', (() => { const p = path.join(uiDir, 'example', stage8.panels[0].path); if (!fs.existsSync(p)) return false; const svg = read(p); return (svg.match(/<rect [^>]*width="216"/g) || []).length === 4 && (svg.match(/<rect [^>]*width="81"/g) || []).length === 12; })(), stage8.panels[0].path);
check('段階 8 の見本の documentPath は、panels の文書と同じ判定の記録を指し、result.cases は 12 件で、要点の数と合う', stage8.documentPath === 'tests/判定の記録.md' && stage8.result.cases.length === 12 && stage8.result.cases.filter(c => c.status === '合格').length === stage8.result.pass && stage8.result.cases.filter(c => c.status === '不合格').length === stage8.result.fail && stage8.result.cases.filter(c => c.status === '判定できない').length === stage8.result.undecidable && stage8.result.cases.filter(c => c.status === '未実施').length === stage8.result.skipped);
const recordRows = (recordMd.split(/^## /m).find(s => s.startsWith('ケースごとの判定')) || '').split('\n').filter(l => /^\| TC-/.test(l));
const recordHead = ((recordMd.match(/^\| ケースの番号 .*$/m) || [''])[0]).split('|').map(c => c.trim()).filter(Boolean);
check('見本の判定の記録は、雛形の章 5 つ(対象、ケースごとの判定、合計、実行時の網羅の証明、未実施の実行)を持ち、panels の section がすべて章にある', recordHeads.join(',') === '対象,ケースごとの判定,合計,実行時の網羅の証明,未実施の実行' && stage8Sections.every(s => recordHeads.includes(s)), recordHeads.join(','));
check('見本の判定の記録のケースごとの判定は、雛形の 8 列で、result.cases と同じ 12 件をケースの番号の順に持ち、判定の仕方が「値を比べる」か「AI が読んで判定する」', recordHead.join(',') === 'ケースの番号,判定の仕方,実施したか,実行ごとの合否,1 回目,2 回目,合否,根拠か未実施の理由' && recordRows.length === 12 && recordRows.map(l => l.split('|')[1].trim()).join(',') === stage8.result.cases.map(c => c.id).sort().join(',') && recordRows.every(l => ['値を比べる', 'AI が読んで判定する'].includes(l.split('|')[2].trim())), recordHead.join(','));
check('見本の判定の記録の合否は、result.cases の status と一致する(未実施は合否が空で、実施したかが「未実施」)', recordRows.every(l => { const c = l.split('|').map(x => x.trim()); const found = stage8.result.cases.find(x => x.id === c[1]); const st = found ? found.status : ''; return st === '未実施' ? c[3] === '未実施' && c[7] === '' : c[7] === st; }));
check('画面の 1 件 1 塊にする章の名前は、「テストケースの一覧」と「ケースごとの判定」の 2 つ', html.includes("const BLOCK_SECTIONS = new Set(['テストケースの一覧', 'ケースごとの判定']);"));
check('合否で変わる左の縁の色は、デザイントークンの変数(危険、注目、薄い文字、縁の太さ)で書く', ['.lbox.lng{border-left:var(--width-edge-accent) solid var(--color-danger)}', '.lbox.lat{border-left:var(--width-edge-accent) solid var(--color-attention)}', '.lbox.lskip{border-left:var(--width-edge-accent) solid var(--color-text-faint)}'].every(c => html.includes(c)) && tokenNames.has('width-edge-accent'));
// 8 章の仕様の章 1(語の置き換え): 画面に出る文字列と、段階 8 の見本の AI の文に、言い直しが要る語がない。コメントとキー名(staticPass など)は見ない
const OLD_WORDS = ['静的', '仕様の行', '前提の状態', '着眼点'];
const htmlCode = html.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '').replace(/(^|\s)\/\/.*$/gm, '');
const htmlOld = OLD_WORDS.filter(w => htmlCode.includes(w));
check('index.html の画面に出る文字列に、言い直しが要る語(静的、仕様の行、前提の状態、着眼点)がない', htmlOld.length === 0, htmlOld.join('、'));
const stage8Files = fs.readdirSync(path.join(uiDir, 'example', 'ui', 'stages')).filter(f => /^8/.test(f));
const stage8Old = stage8Files.flatMap(f => OLD_WORDS.filter(w => read(path.join(uiDir, 'example', 'ui', 'stages', f)).includes(w)).map(w => `${f}: ${w}`));
check('段階 8 の見本(8*.json)と見本の判定の記録の文に、言い直しが要る語がない', stage8Files.length >= 8 && stage8Old.length === 0 && !OLD_WORDS.some(w => recordMd.includes(w)), stage8Old.join('、'));
check('8-8 の見本のテストの結果の行は、「スクリプト 6 件 合格 · シナリオ 10 件 合格」で始まる', JSON.parse(read(path.join(uiDir, 'example', 'ui', 'stages', '8-8.json'))).install.tests.startsWith('スクリプト 6 件 合格 · シナリオ 10 件 合格'));

setCase('段階の表');
const stages = JSON.parse(read(path.join(uiDir, '段階ごとのスキルと規約.json')));
check('段階の表は 1 から 8 の順の 8 行', JSON.stringify(stages.map(r => r.stage)) === '[1,2,3,4,5,6,7,8]');
const skillNames = [...new Set(stages.flatMap(r => r.skills.map(s => s.name)))];
const missingSkills = skillNames.filter(n => ![factory, os.homedir()].some(dir => fs.existsSync(path.join(dir, '.claude', 'skills', n))));
check('段階の表のスキルは .claude/skills/ か ~/.claude/skills/ にある', missingSkills.length === 0, missingSkills.join('、'));
const flow = read(path.join(factory, '.claude', 'rules', 'skill-making-flow', 'skill-making-flow-rule.md'));
const flowRows = [...flow.matchAll(/^\| (\d) \| ([^|]+) \|.*\| ([^|]+) \|$/gm)].map(m => ({stage: Number(m[1]), skills: m[2], rules: m[3]}));
check('規約 skill-making-flow の表の 8 段階を読める', flowRows.length === 8, flowRows.length);
const skillGaps = flowRows.flatMap(r => [...r.skills.matchAll(/[a-z]+(?:-[a-z]+)+/g)].map(m => m[0]).filter(n => !stages[r.stage - 1].skills.some(s => s.name === n)).map(n => `段階 ${r.stage}: ${n}`));
check('規約の表のスキルは段階の表にある', skillGaps.length === 0, skillGaps.join('、'));
const common = ['text-writing-rule', 'skill-or-rule', 'behavior-rule', 'thinking-rule'];
const ruleGaps = flowRows.flatMap(r => [...common, ...[...r.rules.matchAll(/[a-z]+(?:-[a-z]+)+/g)].map(m => m[0])].filter(n => !stages[r.stage - 1].rules.some(x => x.name.includes(n))).map(n => `段階 ${r.stage}: ${n}`));
check('規約の表の規約と共通の規約は段階の表にある(要件定義書の章 2.1)', ruleGaps.length === 0, ruleGaps.join('、'));

setCase('state.json のキー');
// リファレンスは、スキルのフォルダ(.claude/skills/ の下)から読む。worktree の output/ の写しは、スキルの変更を持たないことがある
const refPath = path.join(factory, 'output', 'updating-skill-factory-ui-state', 'references', '画面の状態のファイルの形.md');
// キーは、章「キーの名前と型の対応表」の表だけから取る。章「画面ごとのキーの値の組」の表の見出しの行も、同じ形の行を持つ
const typeTable = read(refPath).split(/^## /m).find(s => s.startsWith('キーの名前と型の対応表')) || '';
const refKeys = [...typeTable.matchAll(/^\| [^|]+ \| `(\w+)` \|/gm)].map(m => m[1]);
// 16 のキーは、2026-11-07 に回の一覧のキー rounds を questions の次に足した数(インターフェース設計書の章 2)
check('リファレンスの表は 16 のキーを持つ', refKeys.length === 16, refKeys.join('、'));
// 段階 2 から 8 で足すキーは、章「段階 2 から 8 で足すキー」の表にある。画面は欠けたキーを null として扱うので、段階 1 の見本はこのキーを持たない
const addedTable = read(refPath).split(/^## /m).find(s => s.startsWith('段階 2 から 8 で足すキー')) || '';
const addedKeys = [...addedTable.matchAll(/^\| [^|]+ \| `(\w+)` \|/gm)].map(m => m[1]);
check('リファレンスの段階 2 から 8 で足すキーの表は、照合の関数と同じキーを同じ順に持つ', addedKeys.join() === ADDED_KEYS.join(), `表: ${addedKeys.join('、')} / 関数: ${ADDED_KEYS.join('、')}`);
const allKeys = [...refKeys, ...addedKeys];
const refScreenRow = (read(refPath).match(/^\| いまの聞き取りの画面 .*$/m) || [''])[0];
const refStageScreens = [...(refScreenRow.split('段階 2 から 8')[1] || '').matchAll(/「([^」]+)」/g)].map(m => m[1]);
check('リファレンスの screen の段階 2 から 8 の値は、照合の関数の表と同じ', refStageScreens.join() === [...STAGE_TABLE.keys()].join(), `表: ${refStageScreens.join('、')} / 関数: ${[...STAGE_TABLE.keys()].join('、')}`);
check('テストの state.json はリファレンスと同じキーを持つ', Object.keys(makeState()).sort().join() === [...refKeys].sort().join(), Object.keys(makeState()).join('、'));
const example = JSON.parse(read(path.join(uiDir, 'example', 'ui', 'state.json')));
check('ui/example の state.json はリファレンスと同じキーを持つ', Object.keys(example).sort().join() === [...refKeys].sort().join(), Object.keys(example).join('、'));
const screensDir = path.join(uiDir, 'example', 'ui', 'screens');
const screenFiles = fs.readdirSync(screensDir);
const screenGaps = screenFiles.filter(f => Object.keys(JSON.parse(read(path.join(screensDir, f)))).sort().join() !== [...refKeys].sort().join());
check('ui/example の聞き取りの画面の見本はリファレンスと同じキーを持つ', screenFiles.length > 0 && screenGaps.length === 0, screenGaps.join('、'));
const refScreens = refScreenRow.split('段階 2 から 8')[0];
const screenValues = new Set(screenFiles.map(f => JSON.parse(read(path.join(screensDir, f))).screen));
const missingScreens = [...refScreens.matchAll(/「([^」]+)」/g)].map(m => m[1]).filter(n => !screenValues.has(n));
check('ui/example の見本は、リファレンスの screen の 9 つの値をすべて持つ', screenValues.size === 9 && missingScreens.length === 0, missingScreens.join('、'));

// リファレンスの雛形の JSON を、見本と比べる形にする。山かっこだけの値は、「か」で終わるものを真偽値、ほかを数とする。
// rounds の items の「questions.items の要素と同じ欄に … を足した要素」は、questions.items の要素に replaced を足した要素とする
const refText = read(refPath);
const SAME_AS_ITEMS = '{"sameAsQuestionItems": true}';
const template = JSON.parse((refText.match(/^````json\n([\s\S]*?)\n````$/m) || ['', '{}'])[1].replace(/("[^"]+":\s*)<([^>]*)>/g, (_, key, name) => key + (name.endsWith('か') ? 'true' : '0')).replace(/\[<questions\.items の要素と同じ欄に[^\]]*>\]/g, '[' + SAME_AS_ITEMS + ']'));
for (const r of Array.isArray(template.rounds) ? template.rounds : []) if (Array.isArray(r.items) && r.items[0] && r.items[0].sameAsQuestionItems) r.items = [{...template.questions.items[0], replaced: true}];
check('リファレンスの雛形は、表の 16 のキーと段階 2 から 8 で足すキーを表の順に持つ', Object.keys(template).join() === allKeys.join(), Object.keys(template).join('、'));
const refRowOnly = key => (refText.match(new RegExp('^\\| [^|]+ \\| `' + key + '` \\|.*$', 'm')) || [''])[0];
// rounds の行は、items の要素の欄を「questions.items の要素と同じ欄」と書くので、questions の行の欄も rounds の欄とする
const refRow = key => (key === 'rounds' ? refRowOnly('rounds') + refRowOnly('questions') : refRowOnly(key));
const innerKeys = (o, found = new Set()) => {
  if (Array.isArray(o)) o.forEach(x => innerKeys(x, found));
  else if (o && typeof o === 'object') for (const [k, v] of Object.entries(o)) { found.add(k); innerKeys(v, found); }
  return found;
};
const rowGaps = allKeys.flatMap(key => [...innerKeys(template[key])].filter(k => !refRow(key).includes(`"${k}"`)).map(k => `${key}.${k}`));
check('リファレンスの雛形の中の欄は、すべて表の行にある', rowGaps.length === 0, rowGaps.join('、'));
const templateGaps = allKeys.flatMap(key => [...refRowOnly(key).matchAll(/"(\w+)"/g)].map(m => m[1]).filter(k => !innerKeys(template[key]).has(k)).map(k => `${key}.${k}`));
check('リファレンスの表の行の中の欄は、すべて雛形にある', templateGaps.length === 0, templateGaps.join('、'));
// 1 つの値ごとに、雛形と同じ欄を同じ順に持つかを見る。配列は、要素を 1 つずつ雛形の要素と比べる
const shapeGaps = (value, shape, where) => {
  if (Array.isArray(shape)) return Array.isArray(value) ? value.flatMap((x, i) => shapeGaps(x, shape[0], `${where}[${i}]`)) : [`${where} が配列でない`];
  if (shape && typeof shape === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return [`${where} がオブジェクトでない`];
    const sameKeys = Object.keys(value).join() === Object.keys(shape).join();
    return [...(sameKeys ? [] : [`${where} の欄が ${Object.keys(value).join('、')}`]), ...Object.keys(shape).filter(k => k in value).flatMap(k => shapeGaps(value[k], shape[k], `${where}.${k}`))];
  }
  if (value === null) return nullable.has(where.split('.').pop().replace(/\[\d+\]$/, '')) ? [] : [`${where} が null`];
  return typeof value === typeof shape ? [] : [`${where} の型が ${typeof value}`];
};
// 中の欄で null を許すのは、リファレンスの表が「文字列か null」と書く欄だけとする
const nullable = new Set([...refText.matchAll(/"(\w+)": 文字列か null/g)].map(m => m[1]));
const stateGaps = (state, name) => [...(Object.keys(state).join() === refKeys.join() ? [] : [`${name} のキーの順が表と違う`]), ...refKeys.flatMap(key => (state[key] === null && refRow(key).includes('`null`') ? [] : shapeGaps(state[key], template[key], `${name} の ${key}`)))];
const sampleGaps = [...screenFiles.map(f => [JSON.parse(read(path.join(screensDir, f))), f]), [example, 'state.json'], [makeState(), 'makeState'], [makeState({questions: threeQuestions()}), 'threeQuestions']].flatMap(([state, name]) => stateGaps(state, name));
check('ui/example の見本とテストの state.json は、要素ごとにリファレンスの雛形と同じ欄を持つ', sampleGaps.length === 0, sampleGaps.join('、'));
// 対応表のキーの列と値の作り方の列で、段階 1 の中の欄を作る行を見る
const mapPath = path.join(factory, 'output', 'updating-skill-factory-ui-state', 'references', '段階のスキルの表示と state.json の値の対応表.md');
const mapRows = read(mapPath).split('\n').filter(l => l.startsWith('| ')).map(l => l.split(' | ').map(c => c.trim()));
const mapRow = (keyCell, ...words) => mapRows.some(c => c.length >= 4 && c[2].includes(keyCell) && words.every(w => c.slice(3).join(' ').includes(w)));
check('対応表は、questions.items[] の行で multiple と parts と files を作る', mapRow('`questions.items[]`', '`multiple` が', '`parts` と `files` が空の配列'));
check('対応表は、questions.items[].parts と questions.items[].files の行で欄の形を決める', mapRow('`questions.items[].parts`、`questions.items[].files`', '`parts` は', '`files` は', '`mainParts`', '`selected`'));
check('対応表は、draftReview.checks[] の行で checks を作る', mapRow('`draftReview.checks[]`', '`checks` に', '`candidates`'));
const inner = {'questions.items の multiple と parts と files': JSON.stringify(JSON.parse(read(path.join(screensDir, '画面 4 の語の定義.json'))).questions), 'draftReview の checks と candidates': JSON.stringify(JSON.parse(read(path.join(screensDir, '画面 5 の確かめる点.json'))).draftReview)};
const server = read(path.join(uiDir, 'server.mjs'));
const promptText = server.slice(server.indexOf('const screenPrompt'), server.indexOf("].join(' ');"));
check('見本と画面は、段階 1 の中の欄を同じ名前で持つ', ['multiple', 'parts', 'files', 'mainParts', 'selected'].every(k => inner['questions.items の multiple と parts と files'].includes(`"${k}"`)) && ['checks', 'candidates'].every(k => inner['draftReview の checks と candidates'].includes(`"${k}"`) && html.includes(k)) && ['.multiple', '.mainParts', '.selected', "'parts'", "'files'"].every(k => html.includes(k)));
// 要件定義書の章 3.2 と規約 skill-making-flow の規則「確認と承認の画面を使うときに AI が足す動作」: スキルは会話の中で 1 回だけ呼び、2 回目からは 2 つのリファレンスのとおりに直接書く
check('中継サーバーの指示は、スキル updating-skill-factory-ui-state と 2 つのリファレンスを指し、中の欄の形をリファレンスに任せる', ['updating-skill-factory-ui-state を会話の中で 1 回だけ呼び', 'Write で直接書く', '会話の要約のあとは、もう一度 updating-skill-factory-ui-state を呼ぶ', '画面の状態のファイルの形.md', '段階のスキルの表示と state.json の値の対応表.md'].every(k => promptText.includes(k)) && !['multiple', 'parts', 'files', 'mainParts', 'selected', 'checks', 'candidates'].some(k => promptText.includes(k)));
check('中継サーバーの指示は、1 回の返事の中で聞き取りの記録.md を 1 回の Write で書かせる(要件定義書の章 3.2)', promptText.includes('次の 7 つを足す') && promptText.includes('7. AI は、1 回の返事の中で、聞き取りの記録.md を 1 回の Write で書く。'));

// インターフェース設計書の章 2 の表と章 3 の聞き返しの形(ui/tests/lib/state-contract.mjs)
setCase('画面の状態の組の照合: 画面 4 で前へを押したあとの state.json');
// 2026-11-06 に画面 4 で「前へ」を押したあと、AI が書いた state.json(output/2026-11-06-0839/ui/state.json の写し。output/ のその作業は git の管理の外なので、写しを ui/tests/fixtures/ に置く)
const backFixture = JSON.parse(read(path.join(testsDir, 'fixtures', '画面 4 で前へを押したあとの state.json')));
const backGaps = stateContractGaps(backFixture);
check('不具合の実物は screen が「画面 4」', backFixture.screen === '画面 4', backFixture.screen);
check('照合の関数は、不具合の実物を不合格にする', backGaps.length > 0);
check('questions が null であることを、必須(items は 1 件以上)に合わない点として出す', backGaps.some(g => g.includes('questions は必須')), backGaps.join(' / '));
check('decision が聞き返しでない自由に答える問いであることを、聞き返しに合わない点として出す', backGaps.some(g => g.includes('decision は null か聞き返し')), backGaps.join(' / '));
const emptyItems = stateContractGaps({...backFixture, decision: null, questions: {...threeQuestions(), items: []}});
check('questions.items が 0 件の組も不合格にする', emptyItems.some(g => g.includes('items が 0 件')), emptyItems.join(' / '));

setCase('画面の状態の組の照合: 章 2 の表の行ごとの見本');
// 章 2 の表は 9 行である
check('照合の関数は章 2 の表の 9 行を持つ', CONTRACT_TABLE.size === 9, CONTRACT_TABLE.size);
// 必須のキーの値は ui/example の見本から取る。聞き返しの decision は章 3 の形とする
const screenSample = name => JSON.parse(read(path.join(screensDir, name + '.json')));
const filled = {summary: screenSample('画面 2').summary, research: screenSample('調査').research, factCheck: screenSample('画面 3').factCheck, draftReview: screenSample('画面 5').draftReview};
const pick = {question: '承認しますか', choices: ['承認する', '直す'], replies: []};
const askBack = n => ({question: '直し方を変えて続けますか', choices: n ? ['直し方を変えて続ける', '中止する'] : [], replies: [], askBack: true});
const rowSamples = {
  null: [['questions と decision が null', {stage: 2}], ['questions と decision がある', {stage: 2, questions: threeQuestions(), decision: pick}]],
  'AI が読む': [['すべて null', {}]],
  '画面 2': [['選択肢', {summary: filled.summary, decision: pick}], ['聞き返し', {summary: filled.summary, decision: askBack(2)}]],
  '調べるための問い': [['decision が null', {questions: threeQuestions()}], ['選択肢 0 件の聞き返し', {questions: threeQuestions(), decision: askBack(0)}]],
  '調査': [['調査の状態', {research: filled.research}]],
  '画面 3': [['選択肢', {factCheck: filled.factCheck, decision: pick}], ['聞き返し', {factCheck: filled.factCheck, decision: askBack(2)}]],
  '画面 4': [['decision が null', {questions: threeQuestions()}], ['選択肢 2 件の聞き返し', {questions: threeQuestions(), decision: askBack(2)}]],
  '画面 5': [['選択肢', {draftReview: filled.draftReview, decision: pick}], ['聞き返し', {draftReview: filled.draftReview, decision: askBack(2)}], ['下書きを作っている間か、まだないとき(draftReview が null)', {decision: pick}]],
  '画面 6': [['すべて null', {}]],
};
check('見本は、章 2 の表のすべての行にある', [...CONTRACT_TABLE.keys()].every(k => rowSamples[String(k)]), Object.keys(rowSamples).join('、'));
for (const [screen, samples] of Object.entries(rowSamples)) {
  for (const [label, over] of samples) {
    const gaps = stateContractGaps(makeState({screen: screen === 'null' ? null : screen, ...over}));
    check(`screen「${screen}」の見本(${label})を合格にする`, gaps.length === 0, gaps.join(' / '));
  }
}

// インターフェース設計書の章 2 の回の一覧(rounds)
setCase('画面の状態の組の照合: 回の一覧');
check('照合の関数は回の種類の 6 つの値を持つ', ROUND_KINDS.join('、') === '調べるための問い、既にあるものとの関係の問い、1 段目、2 段目、追加の回、聞き直しの回', ROUND_KINDS.join('、'));
// 回の問いは、questions.items の同じ番号の問いと同じ欄を持つ(questions.items にない番号の問いは、問い 1 の欄を使う)
const roundItem = (number, answer = null, replaced = false) => ({...(threeQuestions().items.find(i => i.number === number) || threeQuestions().items[0]), number, answer, replaced});
const goodRounds = [{kind: '調べるための問い', items: [roundItem(1, '必須')]}, {kind: '2 段目', items: [roundItem(2, '任意', true), roundItem(3)]}];
for (const [label, st] of [
  ['rounds がない古い形', (({rounds, ...r}) => r)(makeState({screen: '画面 4', questions: threeQuestions()}))],
  ['rounds が null', makeState({screen: '画面 2', summary: filled.summary, decision: pick, rounds: null})],
  ['2 つの回', makeState({screen: '画面 4', questions: threeQuestions(), rounds: goodRounds})],
  ['questions が null の画面の回', makeState({screen: '画面 5', draftReview: filled.draftReview, decision: pick, rounds: goodRounds})],
]) check(`回の一覧の見本(${label})を合格にする`, stateContractGaps(st).length === 0, stateContractGaps(st).join(' / '));
for (const [label, rounds, word] of [
  ['配列でない', {kind: '2 段目'}, '配列でない'],
  ['回がオブジェクトでない', ['2 段目'], 'オブジェクトでない'],
  ['回の種類が 6 つの値のどれでもない', [{kind: '3 段目', items: []}], '回の種類'],
  ['items が配列でない', [{kind: '2 段目', items: null}], 'items が配列でない'],
  ['replaced が真偽値でない', [{kind: '2 段目', items: [{...roundItem(1), replaced: 'はい'}]}], 'replaced'],
]) {
  const gaps = stateContractGaps(makeState({screen: '画面 4', questions: threeQuestions(), rounds}));
  check(`回の一覧の形が違う組(${label})を不合格にする`, gaps.some(g => g.includes(word)), gaps.join(' / '));
}
check('回の一覧の照合は、rounds がないときと null のときに空の一覧を返す', roundsGaps(undefined).length === 0 && roundsGaps(null).length === 0);

// 画面は rounds の問いで描くので、rounds の最後の回のまだ答えていない問いは、questions.items の同じ番号の問いと同じ choices と results を持つ(リファレンス「画面の状態のファイルの形」の行 rounds)
setCase('画面の状態の組の照合: 最後の回の問いと問いの一覧の選択肢');
// 2026-11-21 の本物の AI のテストで AI が書いた state.json(ui/tests/2026-11-21-093443-通し/state/11.json の写し。テストの記録のフォルダは git の管理の外なので、写しを ui/tests/fixtures/ に置く)
const splitFixture = JSON.parse(read(path.join(testsDir, 'fixtures', '最後の回の問いが問いの一覧と違う選択肢を持つ state.json')));
const splitGaps = stateContractGaps(splitFixture);
check('不具合の実物は screen が「画面 4」で、最後の回の問い 2 から 5 が選択肢を持たない', splitFixture.screen === '画面 4' && [1, 2, 3, 4].every(j => splitFixture.rounds.at(-1).items[j].choices.length === 0), splitFixture.screen);
check('照合の関数は、不具合の実物の、最後の回の問い 2 から 5 の choices の食い違いを出す', [2, 3, 4, 5].every(n => splitGaps.some(g => g.includes(`番号 ${n} の問いの choices と違う`))), splitGaps.join(' / '));
check('照合の関数は、不具合の実物の、最後の回の問い 1 の results の食い違いを出す', splitGaps.some(g => g.includes('番号 1 の問いの results と違う')), splitGaps.join(' / '));
const nowRound = (over = {}) => threeQuestions().items.map(i => ({...i, replaced: false, ...(over[i.number] || {})}));
for (const [label, rounds] of [
  ['最後の回が questions.items と同じ問いを持つ', [{kind: '1 段目', items: nowRound()}]],
  ['前の回の同じ番号の問いは違う選択肢を持つ', [{kind: '1 段目', items: nowRound({1: {choices: ['前の回の選択肢'], results: [], answer: '前の回の選択肢'}})}, {kind: '2 段目', items: nowRound()}]],
  ['最後の回の答えた問いは違う選択肢を持つ', [{kind: '2 段目', items: nowRound({1: {choices: [], results: [], answer: '必須'}})}]],
  ['最後の回が questions.items にない番号の問いを持つ', [{kind: '2 段目', items: [...nowRound(), {...threeQuestions().items[0], number: 9, choices: [], results: [], replaced: false}]}]],
]) {
  const gaps = stateContractGaps(makeState({screen: '画面 4', questions: threeQuestions(), rounds}));
  check(`最後の回と問いの一覧の組(${label})を合格にする`, gaps.length === 0, gaps.join(' / '));
}
for (const [label, over, word] of [
  ['最後の回のまだ答えていない問いが choices を持たない', {1: {choices: []}}, '番号 1 の問いの choices と違う'],
  ['最後の回のまだ答えていない問いが、questions.items の同じ問いにない results を持つ', {1: {results: ['「必須」を選ぶと、AI は、必須の値にします']}}, '番号 1 の問いの results と違う'],
  ['最後の回のまだ答えていない問いが違う選択肢を持つ', {1: {choices: ['必須', '任意', '分からない']}}, '番号 1 の問いの choices と違う'],
]) {
  const gaps = stateContractGaps(makeState({screen: '画面 4', questions: threeQuestions(), rounds: [{kind: '1 段目', items: nowRound(over)}]}));
  check(`最後の回と問いの一覧の組(${label})を不合格にする`, gaps.some(g => g.includes(word)), gaps.join(' / '));
}
check('最後の回と問いの一覧の照合は、questions か rounds が null のときと、回が 0 件のときに空の一覧を返す', roundsQuestionsGaps(null, [{kind: '1 段目', items: nowRound({1: {choices: []}})}]).length === 0 && roundsQuestionsGaps(threeQuestions(), null).length === 0 && roundsQuestionsGaps(threeQuestions(), []).length === 0);

// インターフェース設計書の章 2 の段階 2 から 8 の画面の表と、段階 2 から 8 で足すキーの型(ui/tests/lib/state-contract.mjs)
setCase('画面の状態の組の照合: 段階 2 から 8 の画面');
check('照合の関数は章 2 の段階 2 から 8 の画面の表の 23 行を持つ', STAGE_TABLE.size === 23, STAGE_TABLE.size);
// 見本の値。decision.choices の要素は、文字列(今の形)とオブジェクト(新しい形)の両方を置く
const objChoices = {question: '承認しますか', choices: [{label: '承認する(推奨)', result: '次の段階へ進む', recommend: true, recommendReason: '指摘がない', confirm: false}, {label: 'やめる', result: 'スキルを中止する', recommend: false, recommendReason: null, confirm: true}], replies: []};
const strChoices = {question: '承認しますか', choices: ['承認する(推奨)', '却下する'], replies: []};
const free = (replies = []) => ({question: '教えてください', choices: [], replies});
const panels = [{kind: '図', name: '分割の比較図', path: 'ui/figures/2-1-分割の比較図.svg', key: null, open: true, isNew: true}, {kind: '文書', name: 'AI が決めた値', path: null, key: 'aiValues', open: false, isNew: false}];
const recordPanels = [{kind: '図', name: '判定の結果の図', path: 'ui/figures/8-1-判定の結果の図.svg', key: null, open: true, isNew: true}, {kind: '文書', name: '1. ケースごとの判定', path: 'tests/判定の記録.md', key: null, open: false, isNew: false, section: 'ケースごとの判定'}, {kind: '文書', name: '2. 実行時の網羅の証明', path: 'tests/判定の記録.md', key: null, open: false, isNew: false, section: '実行時の網羅の証明'}, {kind: '文書', name: '3. 未実施の実行', path: 'tests/判定の記録.md', key: null, open: false, isNew: false, section: '未実施の実行'}, {kind: '文書', name: '判定の記録(全文)', path: 'tests/判定の記録.md', key: null, open: false, isNew: false, section: null}];
const report = {start: {stage: 2, skill: 'designing-skill-structure', purpose: '分割設計書を書く。', inputs: [{name: '要件定義書のパス', value: 'output/x/要件定義書.md', kind: 'ユーザーのチャット入力'}], outputs: ['分割設計書']}, done: null};
const stageSamples = {
  '始める段階の知らせ': [['report.start', {stage: 2, report}], ['report.start の 5 欄(2026-11-09)', {stage: 5, report: {...report, start: {...report.start, stage: 5, request: 'foo の形を直して', form: '「<スキルの名前> の <直す内容> を直して」', folder: 'output/x/skills/foo/', next: 'AI は、依頼の一覧ができたら、fixing-skill を始めます。', rewrite: false}}}]],
  '直す内容の一覧': [['panels', {stage: 5, panels}]],
  '依頼のファイルがない': [['notice と replies', {stage: 2, decision: {...free([{text: 'output/x/要件定義書.md', recommend: true, reason: '最新の作業'}]), notice: 'output/y/要件定義書.md がない'}}]],
  '依頼の形を聞く': [['forms', {stage: 1, decision: free(), forms: [{form: '「<作業>をするスキルを作って」', stage: 1, skill: 'defining-skill-requirements'}]}]],
  '上書きの確認': [['files と notice', {stage: 4, decision: {...strChoices, files: ['output/x/skills/foo/SKILL.md'], notice: '前の下書きが消える'}}], ['files のオブジェクト(2026-11-09)', {stage: 6, decision: {...objChoices, files: [{path: 'output/x/skills/foo/tests/テスト計画書.md', writtenAt: '2026-11-07 18:42', diff: 'TC-07 の期待が違う'}], notice: '章「シナリオテストの表」が消える'}}]],
  'インストールの確認': [['detail と notice(2026-11-09)', {stage: 4, decision: {...objChoices, detail: [{name: '足りないツール', value: 'node'}, {name: '管理者の権限', value: '求めない'}], notice: 'brew は管理者の権限を求める'}}]],
  '進展がないときの確認': [['detail', {stage: 5, decision: {...objChoices, detail: [{name: '残っている問題', value: '指摘 3 件'}]}}]],
  '開始時の入力の質問': [['questions だけ', {stage: 3, questions: threeQuestions()}], ['questions と replies', {stage: 3, questions: threeQuestions(), decision: free(['候補 1'])}]],
  '中止': [['abort', {stage: 2, abort: {skill: 'designing-skill-structure', step: '9-8', reason: '要件定義書の値が変わる', next: '要件定義書を直す', artifacts: ['output/x/分割設計書.md']}}]],
  'AI から決めてもらうこと': [['detail と panels', {stage: 8, decision: {...objChoices, detail: [{name: 'どちらを選ぶ場合も知っておくこと', value: '規約の変更は別の作業'}]}, panels}], ['prompt と freeText(2026-11-09)', {stage: 5, decision: {...objChoices, prompt: '指摘 6 件の扱いを選んでください。', freeText: 'AI は、選択肢にない回答として受け、同じ質問をもう一度出します。', detail: [{name: '1 回目の照合', value: '指摘 6 件'}]}}]],
  '分割で生まれた値の質問': [['questions', {stage: 2, questions: threeQuestions()}]],
  '成果物の承認': [['段階 2 の skills', {stage: 2, decision: objChoices, summaryCard: [{name: '本数', value: '1 本'}], skills: [{order: 1, name: 'foo', role: '作る', works: '作業 1', handoff: null}], panels}], ['段階 3 の aiValues', {stage: 3, decision: strChoices, summaryCard: [{name: 'phase の数', value: '5'}], aiValues: [{name: '上限', value: '3 回', source: 'AI の案'}]}], ['段階 7 の ranges と scenarios', {stage: 7, decision: objChoices, summaryCard: [{name: '範囲', value: '1 回の実行で終わるすべて'}], ranges: [{name: '1 回の実行で終わるすべて', count: 3, runs: 3, recommend: true, reason: '全件', skipped: []}], scenarios: [{number: 'S1', cases: ['TC-1'], request: 'foo を作って', answers: 'なし', end: '完了の報告', runs: 1, included: true}]}], ['段階 6 の panels の section(2026-11-10)', {stage: 6, decision: objChoices, summaryCard: [{name: '1. テスト観点', value: '3 件'}], panels: [{kind: '文書', name: '1. テスト観点', path: 'tests/テスト計画書.md', section: ['テスト観点の一覧', '使わなかった技法と理由'], key: null, open: true, isNew: true}, {kind: '文書', name: '2. テストケース(3 件)', path: 'tests/テスト計画書.md', section: 'テストケースの一覧', key: null, open: false, isNew: false}, {kind: '文書', name: 'テスト計画書', path: 'tests/テスト計画書.md', section: null, key: null, open: false, isNew: false}]}], ['段階 7 の ranges[].cases と scenarios の 4 欄(2026-11-10)', {stage: 7, decision: objChoices, summaryCard: [{name: '流さないケース', value: 'なし'}], ranges: [{name: '全件', count: 1, cases: 1, runs: 1, recommend: true, reason: null, skipped: []}], scenarios: [{number: 'S1', order: 1, included: true, reason: null, cases: ['TC-01'], phases: '1、2', end: '最終出力まで', setup: 'git のリポジトリ', request: 'foo を作って', answers: 'なし', runs: 1}]}]],
  '却下の理由': [['choices 0 件', {stage: 2, decision: free(), summaryCard: [{name: '本数', value: '1 本'}]}]],
  '指摘の一覧': [['findings と checkRound', {stage: 5, findings: {total: 1, byKind: [{name: '雛形の違反', count: 1}], items: [{file: 'SKILL.md', line: 3, rule: '規則 1', text: '違反', fix: '直し方', held: false}], ending: null}, checkRound: {round: 1, limit: 3}}], ['byKind[].files(2026-11-09)', {stage: 5, findings: {total: 1, byKind: [{name: '雛形の違反', count: 1, files: ['SKILL.md']}], items: [], ending: null}, checkRound: {round: 1, limit: 3}}]],
  '直しの承認': [['fixRecord', {stage: 5, decision: objChoices, fixRecord: {fixes: [{file: 'SKILL.md', line: 3, before: '前', after: '後', reason: '規則 1', behaviorChanges: true}], held: [], afterApproval: ['照合し直す']}, checkRound: {round: 1, limit: 3}}], ['rows と fixes の 3 欄(2026-11-09)', {stage: 5, decision: objChoices, fixRecord: {rows: [{name: '止まっていること', value: '直す指摘 5 件の承認'}], fixes: [{file: 'SKILL.md', line: 3, before: '前', after: '後', reason: '規則 1', behaviorChanges: true, happened: '行き先が 2 文', behavior: '書き場所が移る', stepChange: '6-3 と 5-1'}], held: [], afterApproval: ['照合し直す']}, checkRound: {round: 1, limit: 3}}]],
  '修正の結果': [['段階 5', {stage: 5, fixResult: {source: '照合の指摘の一覧', counts: [{name: '直した', count: 1}], fixed: [{file: 'SKILL.md', before: '前', after: '後'}], reverted: [], rows: [], next: '照合し直す'}, checkRound: {round: 2, limit: 3}}], ['段階 8', {stage: 8, fixResult: {source: '判定の記録', counts: [], fixed: [], reverted: [{file: 'SKILL.md', before: '前', after: '後', reason: '意味が変わる'}], rows: [{name: '残り', value: '0'}], next: 'テストを流し直す'}}]],
  'テストの実行': [['report なし', {stage: 8}], ['report', {stage: 8, report: {...report, start: {...report.start, stage: 8}}}]],
  // 2026-11-10 に確定した 8 章の仕様: 8-2 は panels(図 1 つと、section を持つ文書 3 つと、全文 1 つ)を必須に持つ
  'テストの結果': [['result と panels', {stage: 8, result: {total: 3, pass: 2, fail: 1, undecidable: 0, skipped: 0, cases: [{id: 'TC-1', status: '不合格', run: 'S1 の 1 回目', reason: '期待と違う'}], staticFail: [], interrupted: null, next: '仕分ける'}, panels: recordPanels}], ['staticPass と stopped(2026-11-09)', {stage: 8, result: {total: 3, pass: 2, fail: 1, undecidable: 0, skipped: 0, staticPass: 6, stopped: '不合格 1 件の仕分け', cases: [], staticFail: [], interrupted: null, next: '仕分ける'}, panels: recordPanels}]],
  '不合格の仕分けの結果': [['triage', {stage: 8, triage: [{id: 'TC-1', kind: 'スキルの誤り', cause: '手順の抜け', target: 'SKILL.md'}]}]],
  '規約か雛形が原因': [['triage と fixResult', {stage: 8, triage: [{id: 'TC-1', kind: '規約か雛形が原因', cause: '雛形の欄', target: '雛形'}], fixResult: {source: '判定の記録', counts: [], fixed: [], reverted: [], rows: [], next: '規約を直す'}}]],
  'テスト計画書の直しの承認': [['planFix', {stage: 8, decision: objChoices, planFix: {cases: [{id: 'TC-1', name: '正常系', kind: 'テストの期待の誤り', before: '前', after: '後', source: '判定の記録'}], files: [], unfixable: []}}]],
  '文書の照合の結果': [['docCheck', {stage: 8, docCheck: {files: 3, findings: 2, wording: 2, changed: 1, changes: [{file: '要件定義書.md', line: 5, before: '前', after: '後', rule: '規則 1', meaningChanges: false}], next: '完了'}}]],
  'スキルができた': [['install と done', {stage: 8, currentSkill: {name: 'foo', order: 1, total: 1, done: 1}, install: {folder: 'output/x/skills/foo', contents: 'SKILL.md と references/', tests: '3 件合格', run: '1 回', left: null, commands: [{when: '1 つのプロジェクトで使うとき', command: 'ln -s a b'}], next: 'なし'}}]],
};
// 2026-11-09 のレビュー後の改訂: skills の output と handoffMatch、currentSkill.done の null
stageSamples['成果物の承認'].push(['段階 2 の skills の 2 欄(2026-11-09)', {stage: 2, decision: objChoices, summaryCard: [{name: '本数', value: '1 本'}], skills: [{order: 1, name: 'foo', role: '作る', works: '作業 1', handoff: '直近の N 件のコミット', output: '1 つのコミット', handoffMatch: true}], currentSkill: {name: 'foo', order: 1, total: 1, done: null}}]);
check('見本は、章 2 の段階 2 から 8 の画面の表のすべての行にある', [...STAGE_TABLE.keys()].every(k => stageSamples[k]), Object.keys(stageSamples).join('、'));
for (const [screen, samples] of Object.entries(stageSamples)) {
  for (const [label, over] of samples) {
    const gaps = stateContractGaps(makeState({screen, ...over}));
    check(`screen「${screen}」の見本(${label})を合格にする`, gaps.length === 0, gaps.join(' / '));
  }
}
for (const [label, st, word] of [
  ['始める段階の知らせで report が null', makeState({screen: '始める段階の知らせ', stage: 2}), 'report.start は必須'],
  ['上書きの確認で choices が 0 件', makeState({screen: '上書きの確認', stage: 4, decision: {...free(), files: ['a']}}), 'choices が 0 件'],
  ['却下の理由で choices がある', makeState({screen: '却下の理由', stage: 2, decision: strChoices}), 'choices が 2 件'],
  ['段階 2 から 8 の画面の聞き返し', makeState({screen: '進展がないときの確認', stage: 5, decision: {...objChoices, askBack: true, detail: [{name: 'a', value: 'b'}]}}), '聞き返しを持てない'],
  ['choices の要素に label がない', makeState({screen: '成果物の承認', stage: 2, decision: {question: 'q', choices: [{result: 'r'}], replies: []}, summaryCard: [{name: 'a', value: 'b'}], skills: [{order: 1, name: 'a', role: 'b', works: 'c', handoff: null}]}), 'choices[0].label がない'],
  ['replies の要素が数', makeState({screen: '依頼のファイルがない', stage: 2, decision: {...free([1]), notice: 'n'}}), 'replies[0] が文字列でもオブジェクトでもない'],
  ['panels の kind が図でも文書でもない', makeState({screen: '直す内容の一覧', stage: 5, panels: [{kind: '表', name: 'a', path: 'a.md', key: null, open: true, isNew: false}]}), 'panels[0].kind'],
  ['panels の section が文字列でも文字列の並びでもない(2026-11-10: 章の見出しの文)', makeState({screen: '直す内容の一覧', stage: 5, panels: [{kind: '文書', name: 'a', path: 'a.md', key: null, open: true, isNew: false, section: 3}]}), 'section が'],
  ['成果物の承認で段階 6 の panels がない(2026-11-10)', makeState({screen: '成果物の承認', stage: 6, decision: objChoices, summaryCard: [{name: 'a', value: 'b'}]}), 'panels は必須'],
  ['panels の open が真偽値でない', makeState({screen: '直す内容の一覧', stage: 5, panels: [{kind: '文書', name: 'a', path: 'a.md', key: null, open: 'はい', isNew: false}]}), 'open が真偽値でない'],
  ['checkRound の round が整数でない', makeState({screen: '指摘の一覧', stage: 5, findings: {total: 0, byKind: [], items: [], ending: '段階 6 へ'}, checkRound: {round: '1', limit: 3}}), 'checkRound.round が整数でない'],
  ['成果物の承認で段階 2 の skills がない', makeState({screen: '成果物の承認', stage: 2, decision: objChoices, summaryCard: [{name: 'a', value: 'b'}]}), 'skills は必須'],
  ['result の status が 4 つの値にない', makeState({screen: 'テストの結果', stage: 8, result: {total: 1, pass: 0, fail: 0, undecidable: 0, skipped: 0, cases: [{id: 'a', status: '保留', run: null, reason: null}], staticFail: [], interrupted: null, next: 'n'}}), 'cases[0].status'],
  ['段階 1 のキー summary が null でない', makeState({screen: '中止', stage: 2, abort: {skill: 'a', step: '1-1', reason: 'r', next: 'n', artifacts: []}, summary: {lines: ['a'], readings: []}}), 'summary は null'],
  ['段階 1 の画面で足したキーの型が違う', makeState({screen: '画面 6', panels: 'なし'}), 'panels が配列でない'],
  ['choices の要素に result がない(2026-11-09: result は必須)', makeState({screen: '成果物の承認', stage: 3, decision: {question: 'q', choices: [{label: '承認する(推奨)', recommend: true}], replies: []}, summaryCard: [{name: 'a', value: 'b'}], aiValues: [{name: 'a', value: 'b', source: 'c'}]}), 'choices[0].result がない'],
  ['ranges の要素の cases が整数でない(2026-11-10: 列「テストケース」)', makeState({screen: '成果物の承認', stage: 7, decision: objChoices, summaryCard: [{name: 'a', value: 'b'}], ranges: [{name: '全件', count: 1, cases: '1', runs: 1, recommend: true, reason: null, skipped: []}], scenarios: [{number: 'S1', cases: ['TC-01'], request: 'r', answers: 'a', end: 'e', runs: 1, included: true}]}), 'ranges[0].cases が整数でない'],
  ['scenarios の要素の order が整数でない(2026-11-10: 列「流す順」)', makeState({screen: '成果物の承認', stage: 7, decision: objChoices, summaryCard: [{name: 'a', value: 'b'}], ranges: [{name: '全件', count: 1, runs: 1, recommend: true, reason: null, skipped: []}], scenarios: [{number: 'S1', order: '1', cases: ['TC-01'], request: 'r', answers: 'a', end: 'e', runs: 1, included: true}]}), 'scenarios[0].order が整数でない'],
  ['aiValues の要素に source がない(2026-11-10: 列「どう決めたか」)', makeState({screen: '成果物の承認', stage: 3, decision: objChoices, summaryCard: [{name: 'a', value: 'b'}], aiValues: [{name: 'a', value: 'b'}]}), 'aiValues[0].source がない'],
  ['files の要素が数(2026-11-09)', makeState({screen: '上書きの確認', stage: 4, decision: {...strChoices, files: [1]}}), 'files[0] が'],
  ['インストールの確認で detail がない(2026-11-09)', makeState({screen: 'インストールの確認', stage: 4, decision: {...objChoices, notice: 'n'}}), 'decision.detail は必須'],
  ['result の staticPass が整数でない(2026-11-09)', makeState({screen: 'テストの結果', stage: 8, result: {total: 1, pass: 1, fail: 0, undecidable: 0, skipped: 0, staticPass: '6', cases: [], staticFail: [], interrupted: null, next: 'n'}, panels: recordPanels}), 'staticPass が整数でない'],
  ['テストの結果で panels がない(2026-11-10: 判定の記録の章のタブ)', makeState({screen: 'テストの結果', stage: 8, result: {total: 1, pass: 1, fail: 0, undecidable: 0, skipped: 0, cases: [], staticFail: [], interrupted: null, next: 'n'}}), 'panels は必須'],
]) {
  const gaps = stateContractGaps(st);
  check(`形が違う組(${label})を不合格にする`, gaps.some(g => g.includes(word)), gaps.join(' / '));
}
check('段階 1 の画面の decision.choices もオブジェクトの要素を持てる', stateContractGaps(makeState({screen: '画面 2', summary: filled.summary, decision: objChoices})).length === 0, stateContractGaps(makeState({screen: '画面 2', summary: filled.summary, decision: objChoices})).join(' / '));

setCase('計画書とプログラムの同期');
const plan = read(path.join(testsDir, 'テスト計画書.md'));
const section4 = plan.slice(plan.indexOf('## 4. '), plan.indexOf('## 5. '));
const planRows = [...section4.matchAll(/^\| ([^|]+) \| [^|]+ \| (合格|既知の不合格あり|未実施[^|]*) \|$/gm)].map(m => ({name: m[1].trim(), status: m[2].trim()}));
const planNames = new Set(planRows.map(r => r.name));
const list = (cmd, args) => spawnSync(cmd, args, {encoding: 'utf8'}).stdout.split('\n').filter(Boolean);
const programNames = new Set([
  ...[...read(path.join(testsDir, 'test-relay.sh')).matchAll(/^# ケース: (.+)$/gm)].map(m => m[1]),
  ...list('node', [path.join(testsDir, 'test-relay-edge.mjs'), '--list']),
  ...list('node', [path.join(testsDir, 'test-screen.mjs'), '--list']),
  ...list('node', [path.join(testsDir, 'test-real.mjs'), '--list']),
  ...caseNames,
]);
const notInPlan = [...programNames].filter(n => !planNames.has(n));
const notInProgram = [...planNames].filter(n => !programNames.has(n));
check('プログラムのケースはすべて計画書にある', notInPlan.length === 0, notInPlan.join('、'));
check('計画書のケースはすべてプログラムにある', notInProgram.length === 0, notInProgram.join('、'));
const known = JSON.parse(read(path.join(testsDir, 'known-failures.json')));
const statusGaps = planRows.filter(r => !r.status.startsWith('未実施') && (r.status === '既知の不合格あり') !== Object.keys(known).some(k => k.startsWith(`${r.name}: `))).map(r => r.name);
check('計画書の状態は known-failures.json と同じ', statusGaps.length === 0, statusGaps.join('、'));
const trace = plan.slice(plan.indexOf('## 5. '), plan.indexOf('## 6. '));
const untraced = [...planNames].filter(n => !trace.includes(`「${n}」`));
check('章 4 のすべてのケースは章 5 の要件に当たる', untraced.length === 0, untraced.join('、'));
const paths = [...plan.matchAll(/`((?:ui\/tests\/)[\w./-]+\.(?:mjs|sh|json))`/g)].map(m => m[1]);
const gonePaths = paths.filter(p => !fs.existsSync(path.join(factory, p)));
check('計画書が書くプログラムのパスはすべてある', paths.length > 0 && gonePaths.length === 0, gonePaths.join('、'));
const bareIds = [...plan.matchAll(/(?<![A-Za-z0-9_./-])(?:T[a-i]|R\d+[a-z]?|G\d+|S\d+|E\d+|U\d+)(?![A-Za-z0-9_])/g)].map(m => m[0]);
check('計画書は、アルファベットと数字だけの名前を自分で付けない', bareIds.length === 0, bareIds.join('、'));

setCase('README の手順');
const readme = read(path.join(factory, 'README.md'));
check('README は停止の手順を持つ(要件定義書の章 8)', readme.includes('Ctrl+C'));
check('README は存在しない起動の引数を書かない(要件定義書の章 7)', !readme.includes('node ui/server.mjs ui/example'));
check('README は画面のテストの流し方を持つ', readme.includes('ui/tests/run-auto.sh'));

setCase('モックの層が本物の claude を呼ばない');
for (const f of ['test-screen.mjs', 'test-relay-edge.mjs']) check(`${f} は PATH を偽の claude とシステムのコマンドだけにする`, read(path.join(testsDir, f)).includes(':/usr/bin:/bin`'));
check('run-auto.sh は本物のテストを呼ばない', !/^\s*(run|node|bash)\b.*test-real/m.test(read(path.join(testsDir, 'run-auto.sh'))));
check('test-relay.sh は偽の claude を PATH の先頭に置く', read(path.join(testsDir, 'test-relay.sh')).includes('export PATH="$tmp/bin:$PATH"'));

process.exit(finish(caseNames, true));
