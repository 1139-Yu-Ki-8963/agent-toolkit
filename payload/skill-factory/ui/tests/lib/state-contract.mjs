// state.json の値の組が、画面の状態のファイルのインターフェース設計書(docs/スキル作成の確認と承認の画面/画面の状態のファイルのインターフェース設計書.md)の
// 章 2 の表(screen ごとにキーが持ってよい値の組)と、章 3 の聞き返しの decision の形に合うかを見る。
// 表は、設計書の章 2 の 2 つの表(段階 1 の聞き取りの画面の 10 行と、段階 2 から 8 の画面の 23 行)をここに写したもの。test-mutants.mjs の写しは docs/ を持たないので、実行のときに設計書を読まない。
// 1 つの state.json だけを見る。章 3 の「聞き返しの間、screen と questions と必須のキーを変えない」と、章 5 の「rounds の回を消さない」は、前後の 2 つの値が要るので、ここでは見ない。
// rounds(章 2 の回の一覧)は持ってよいキーなので、ないときと null のときは見ない。あるときは、形だけを見る。
// 段階 2 から 8 で足すキー(report、panels、checkRound など)は、欠けたときと null のときは null として扱い、値を持つときは型を見る。

// 章 2 の表の語: req は「必須」、reqItems は「必須(items は 1 件以上)」、null は「null」、nullOrReq は「null か必須」、askBack は「聞き返し」、choice は「選択肢」
const KEYS = ['summary', 'research', 'factCheck', 'questions', 'approvalSheet', 'draftReview', 'decision'];
const row = (summary, research, factCheck, questions, approvalSheet, draftReview, decision) => ({summary, research, factCheck, questions, approvalSheet, draftReview, decision});
export const CONTRACT_TABLE = new Map([
  [null, row('null', 'null', 'null', 'nullOrReq', 'null', 'null', 'nullOrReq')],
  ['AI が読む', row('null', 'null', 'null', 'null', 'null', 'null', 'null')],
  ['画面 2', row('req', 'null', 'null', 'null', 'null', 'null', 'choice')],
  ['調べるための問い', row('null', 'null', 'null', 'reqItems', 'null', 'null', 'askBack')],
  ['調査', row('null', 'req', 'null', 'null', 'null', 'null', 'null')],
  ['画面 3', row('null', 'null', 'req', 'null', 'null', 'null', 'choice')],
  ['画面 4', row('null', 'null', 'null', 'reqItems', 'null', 'null', 'askBack')],
  ['AI の案', row('null', 'null', 'null', 'null', 'req', 'null', 'choice')],
  // draftReview の null は、下書きを作っている間と、下書きがまだないとき
  ['画面 5', row('null', 'null', 'null', 'null', 'null', 'nullOrReq', 'choice')],
  ['画面 6', row('null', 'null', 'null', 'null', 'null', 'null', 'null')],
]);

// 章 2 の段階 2 から 8 の画面の表。段階 1 の聞き取りの画面のキー 5 つ(summary、research、factCheck、approvalSheet、draftReview)は、すべての行で null。
// questions と decision の語は、上の表と同じ。decision の語 free は「自由に答える問い(choices が 0 件の decision)」、nullOrFree は「null か自由に答える問い」。
// required は、null でない値を持つキー。stage の値で変わるキーは、byStage に段階の番号ごとに持つ。
const stageRow = (questions, decision, required, byStage = {}) => ({questions, decision, required, byStage});
export const STAGE_TABLE = new Map([
  ['始める段階の知らせ', stageRow('null', 'null', ['report.start'])],
  ['直す内容の一覧', stageRow('null', 'null', ['panels'])],
  ['依頼のファイルがない', stageRow('null', 'free', ['decision.notice'])],
  ['依頼の形を聞く', stageRow('null', 'free', ['forms'])],
  ['上書きの確認', stageRow('null', 'choice', ['decision.files'])],
  // 2026-11-09 のレビュー後の改訂: K3 の 4 行(足りないツール、確かめたコマンド、実行するコマンド、管理者の権限)は decision.detail
  ['インストールの確認', stageRow('null', 'choice', ['decision.detail'])],
  ['進展がないときの確認', stageRow('null', 'choice', ['decision.detail'])],
  ['開始時の入力の質問', stageRow('reqItems', 'nullOrFree', [])],
  ['中止', stageRow('null', 'null', ['abort'])],
  ['AI から決めてもらうこと', stageRow('null', 'choice', ['decision.detail'])],
  ['分割で生まれた値の質問', stageRow('reqItems', 'nullOrFree', [])],
  // 2026-11-10 の 6-1 のデザイン: 段階 6 はタブを panels(テスト計画書の章ごとの欄)で出す
  ['成果物の承認', stageRow('null', 'choice', ['summaryCard'], {2: ['skills'], 3: ['aiValues'], 6: ['panels'], 7: ['ranges', 'scenarios']})],
  ['却下の理由', stageRow('null', 'free', [])],
  ['指摘の一覧', stageRow('null', 'null', ['findings', 'checkRound'])],
  ['直しの承認', stageRow('null', 'choice', ['fixRecord', 'checkRound'])],
  ['修正の結果', stageRow('null', 'null', ['fixResult'], {5: ['checkRound']})],
  ['テストの実行', stageRow('null', 'null', [])],
  // 2026-11-10 に確定した 8 章の仕様: 8-2 は、判定の記録の md を panels の section で出す(図 1 つと、section を持つ文書 3 つと、全文 1 つ)
  ['テストの結果', stageRow('null', 'null', ['result', 'panels'])],
  ['不合格の仕分けの結果', stageRow('null', 'null', ['triage'])],
  ['規約か雛形が原因', stageRow('null', 'null', ['triage', 'fixResult'])],
  ['テスト計画書の直しの承認', stageRow('null', 'choice', ['planFix'])],
  ['文書の照合の結果', stageRow('null', 'null', ['docCheck'])],
  ['スキルができた', stageRow('null', 'null', ['install', 'currentSkill.done'])],
]);

const isObj = v => !!v && typeof v === 'object' && !Array.isArray(v);
const strings = v => Array.isArray(v) && v.every(x => typeof x === 'string');
const isInt = v => Number.isInteger(v);

// 段階 2 から 8 で足すキーの型(インターフェース設計書の章 2 の「段階 2 から 8 で足すキー」の表)。
// 型の書き方: 'str' 文字列、'str?' 文字列か null、'int' 整数、'int?' 整数か null、'bool' 真偽値、{enum: [...]} 決まった値の 1 つ、[型] その型の要素の配列、{...} その欄を持つオブジェクト(欄 _nullable が true なら null でもよい)、
// {_optionalArray: 型} 欠けてもよく、あるときはその型の要素の配列か null、{_oneOf: [型, 型]} どれかの型に合う値
const nameValue = {name: 'str', value: 'str'};
const nameCount = {name: 'str', count: 'int'};
const optArr = t => ({_optionalArray: t});
export const ADDED_KEY_TYPES = {
  report: {
    // 2026-11-09 のレビュー後の改訂: request(依頼の文)、form(当たった形)、folder(スキルのフォルダ)、next(K1 の知らせの行)、rewrite(却下のあとの書き直しか)
    start: {_nullable: true, stage: 'int', skill: 'str', purpose: 'str', inputs: [{name: 'str', value: 'str', kind: 'str'}], outputs: ['str'], request: 'str?', form: 'str?', folder: 'str?', next: 'str?', rewrite: 'bool?'},
    done: {_nullable: true, title: 'str', outputs: [{path: 'str', unchanged: 'bool'}]},
  },
  // 2026-11-10 の 6-1 のデザイン: section(path の md の「## 」の章の見出しの文。文字列か、その並び。欠けるか null のときは全文)。画面は、その章だけを HTML にして出す
  panels: [{kind: {enum: ['図', '文書']}, name: 'str', path: 'str?', key: 'str?', open: 'bool', isNew: 'bool', section: {_oneOf: ['str?', ['str']], _optional: true}}],
  checkRound: {round: 'int', limit: 'int'},
  forms: [{form: 'str', stage: 'int', skill: 'str'}],
  abort: {skill: 'str', step: 'str', reason: 'str', next: 'str', artifacts: ['str']},
  summaryCard: [nameValue],
  // 2026-11-09: output(最終出力)、handoffMatch(受け渡しの名前が一致するか)
  skills: [{order: 'int', name: 'str', role: 'str', works: 'str', handoff: 'str?', output: 'str?', handoffMatch: 'bool?'}],
  // 2026-11-10 の 3-1 のデザイン: aiValues は {name(AI が決めたこと), value(決めた値), source(どう決めたか)} で、step を持たない
  aiValues: [{name: 'str', value: 'str', source: 'str'}],
  // 2026-11-10 の 7-1 のデザイン: ranges[].cases(その範囲のテストケースの数。表の列「テストケース」の「<件数> / <動的の総数>」の件数)
  ranges: [{name: 'str', count: 'int', runs: 'int', recommend: 'bool', reason: 'str?', skipped: ['str'], cases: 'int?'}],
  // 2026-11-10 の 7-1 のデザイン: order(流す順)、reason(流さない理由)、phases(通す phase)、setup(前提の状況)。シナリオテストの表の 11 列を出すための 4 欄
  scenarios: [{number: 'str', cases: ['str'], request: 'str', answers: 'str', end: 'str', runs: 'int', included: 'bool', order: 'int?', reason: 'str?', phases: 'str?', setup: 'str?'}],
  // 2026-11-09: byKind[].files(種類ごとのファイルの一覧)
  findings: {total: 'int', byKind: [{name: 'str', count: 'int', files: optArr('str')}], items: [{file: 'str', line: 'int?', rule: 'str', text: 'str', fix: 'str', held: 'bool'}], ending: 'str?'},
  // 2026-11-09: rows(見出しの下の行)、fixes[] の happened、behavior、stepChange
  fixRecord: {fixes: [{file: 'str', line: 'int?', before: 'str', after: 'str', reason: 'str', behaviorChanges: 'bool', happened: 'str?', behavior: 'str?', stepChange: 'str?'}], held: [{file: 'str', line: 'int?', text: 'str', reason: 'str'}], afterApproval: ['str'], rows: optArr(nameValue)},
  fixResult: {source: 'str', counts: [nameCount], fixed: [{file: 'str', before: 'str', after: 'str'}], reverted: [{file: 'str', before: 'str', after: 'str', reason: 'str'}], rows: [nameValue], next: 'str'},
  // 2026-11-09: staticPass(スクリプトで確かめるテストの合格の数)、stopped(止まっていることの文)
  result: {total: 'int', pass: 'int', fail: 'int', undecidable: 'int', skipped: 'int', cases: [{id: 'str', status: {enum: ['合格', '不合格', '判定できない', '未実施']}, run: 'str?', reason: 'str?'}], staticFail: [{name: 'str', reason: 'str'}], interrupted: 'str?', next: 'str', staticPass: 'int?', stopped: 'str?'},
  triage: [{id: 'str', kind: {enum: ['スキルの誤り', 'テストの期待の誤り', '規約か雛形が原因']}, cause: 'str', target: 'str'}],
  planFix: {cases: [{id: 'str', name: 'str', kind: 'str', before: 'str', after: 'str', source: 'str'}], files: [{path: 'str', text: 'str'}], unfixable: [{id: 'str', kind: 'str', reason: 'str'}]},
  docCheck: {files: 'int', findings: 'int', wording: 'int', changed: 'int', changes: [{file: 'str', line: 'int', before: 'str', after: 'str', rule: 'str', meaningChanges: 'bool'}], next: 'str'},
  install: {folder: 'str', contents: 'str', tests: 'str', run: 'str', left: 'str?', commands: [{when: 'str', command: 'str'}], next: 'str'},
};
export const ADDED_KEYS = Object.keys(ADDED_KEY_TYPES);

// decision.choices の要素(文字列か、label を持つオブジェクト)と decision.replies の要素(文字列か、text を持つオブジェクト)の型
// 2026-11-09 のレビュー後の改訂: result は文字列(必須)。input は「直す点を伝える」のように、スキルが同じ step で文を受ける選択肢にだけ付ける(「却下する」には付けない。画面は無視する)
const CHOICE_TYPE = {label: 'str', result: 'str', recommend: 'bool?', recommendReason: 'str?', confirm: 'bool?', input: {_nullable: true, _optional: true, placeholder: 'str', sendLabel: 'str'}};
const REPLY_TYPE = {text: 'str', recommend: 'bool?', reason: 'str?'};
// 2026-11-09: files の要素は文字列か {path, writtenAt, diff}。prompt(問いの塊の文)、freeText(「下の 1 行に書いた文」の段落)
const DECISION_EXTRA_TYPES = {notice: 'str?', detail: [nameValue], files: [{_oneOf: ['str', {path: 'str', writtenAt: 'str?', diff: 'str?'}]}], prompt: 'str?', freeText: 'str?'};

// 値が型に合わない点の一覧。欠けた欄は、型が「か null」(末尾の ?)のときと、_optional の欄と _optionalArray の欄のときだけ許す
export function typeGaps(v, type, where) {
  if (isObj(type) && type._oneOf) {
    const results = type._oneOf.map(t => typeGaps(v, t, where));
    return results.some(r => r.length === 0) ? [] : [`${where} が、${type._oneOf.map(t => (typeof t === 'string' ? t : 'オブジェクト')).join('か')}のどれにも合わない`];
  }
  if (isObj(type) && type._optionalArray) {
    if (v === null || v === undefined) return [];
    return typeGaps(v, [type._optionalArray], where);
  }
  if (typeof type === 'string') {
    const nullable = type.endsWith('?');
    const base = nullable ? type.slice(0, -1) : type;
    if (v === null || v === undefined) return nullable ? [] : [`${where} が null`];
    if (base === 'str') return typeof v === 'string' ? [] : [`${where} が文字列でない`];
    if (base === 'int') return isInt(v) ? [] : [`${where} が整数でない`];
    if (base === 'bool') return typeof v === 'boolean' ? [] : [`${where} が真偽値でない`];
    return [`${where} の型「${type}」を知らない`];
  }
  if (Array.isArray(type)) {
    if (!Array.isArray(v)) return [`${where} が配列でない`];
    return v.flatMap((x, i) => typeGaps(x, type[0], `${where}[${i}]`));
  }
  if (type.enum) return type.enum.includes(v) ? [] : [`${where}「${v}」は ${type.enum.join('、')} のどれでもない`];
  if (v === null || v === undefined) return type._nullable ? [] : [`${where} が null`];
  if (!isObj(v)) return [`${where} がオブジェクトでない`];
  const gaps = [];
  for (const [k, t] of Object.entries(type)) {
    if (k.startsWith('_')) continue;
    if (!(k in v)) {
      const optional = (typeof t === 'string' && t.endsWith('?')) || (isObj(t) && (t._optional || t._optionalArray));
      if (!optional) gaps.push(`${where}.${k} がない`);
      continue;
    }
    gaps.push(...typeGaps(v[k], t, `${where}.${k}`));
  }
  return gaps;
}

// choices の要素 1 つの形に合わない点。文字列は label だけを持つものとして扱う
function choiceGaps(c, where) {
  if (typeof c === 'string') return [];
  if (!isObj(c)) return [`${where} が文字列でもオブジェクトでもない`];
  return typeGaps(c, CHOICE_TYPE, where);
}
function replyGaps(r, where) {
  if (typeof r === 'string') return [];
  if (!isObj(r)) return [`${where} が文字列でもオブジェクトでもない`];
  return typeGaps(r, REPLY_TYPE, where);
}
const choicesGaps = (d, where) => Array.isArray(d.choices) ? d.choices.flatMap((c, i) => choiceGaps(c, `${where}.choices[${i}]`)) : [`${where}.choices が配列でない`];
const repliesGaps = (d, where) => Array.isArray(d.replies) ? d.replies.flatMap((r, i) => replyGaps(r, `${where}.replies[${i}]`)) : [`${where}.replies が配列でない`];
// notice、detail、files は、あるときだけ型を見る
const decisionExtraGaps = (d, where) => Object.entries(DECISION_EXTRA_TYPES).flatMap(([k, t]) => (k in d && d[k] !== null ? typeGaps(d[k], t, `${where}.${k}`) : []));

// 章 2 の回の一覧(rounds)の、回の種類の 6 つの値
export const ROUND_KINDS = ['調べるための問い', '既にあるものとの関係の問い', '1 段目', '2 段目', '追加の回', '聞き直しの回'];

// 章 2 の回の一覧(rounds)の形に合わない点の一覧。rounds がないときと null のときは空の配列
export function roundsGaps(rounds) {
  if (rounds === undefined || rounds === null) return [];
  if (!Array.isArray(rounds)) return ['rounds が配列でない'];
  const gaps = [];
  rounds.forEach((r, i) => {
    const at = `rounds[${i}]`;
    if (!isObj(r)) { gaps.push(`${at} がオブジェクトでない`); return; }
    if (!ROUND_KINDS.includes(r.kind)) gaps.push(`${at}.kind「${r.kind}」は回の種類の 6 つの値のどれでもない`);
    if (!Array.isArray(r.items)) { gaps.push(`${at}.items が配列でない`); return; }
    r.items.forEach((it, j) => {
      if (!isObj(it)) { gaps.push(`${at}.items[${j}] がオブジェクトでない`); return; }
      if ('replaced' in it && typeof it.replaced !== 'boolean') gaps.push(`${at}.items[${j}].replaced が真偽値でない`);
    });
  });
  return gaps;
}

// 章 3 の聞き返しの decision の形に合わない点の一覧
export function askBackGaps(d) {
  const gaps = [];
  if (!isObj(d)) return ['decision がオブジェクトでない'];
  if (d.askBack !== true) gaps.push('decision.askBack が true でない');
  if (typeof d.question !== 'string' || !d.question.trim()) gaps.push('decision.question が 1 文字以上の文字列でない');
  if (!Array.isArray(d.choices)) gaps.push('decision.choices が配列でない');
  else if (d.choices.length > 4) gaps.push(`decision.choices が ${d.choices.length} 件(0 件から 4 件)`);
  gaps.push(...choicesGaps(d, 'decision'), ...repliesGaps(d, 'decision'), ...decisionExtraGaps(d, 'decision'));
  return gaps;
}

// 聞き返しでない decision(章 3: askBack を持たないか false)の形に合わない点の一覧
function plainDecisionGaps(d) {
  const gaps = [];
  if (!isObj(d)) return ['decision がオブジェクトでない'];
  if ('askBack' in d && d.askBack !== false) gaps.push('聞き返しでない decision の askBack が false でない');
  if (typeof d.question !== 'string' || !d.question.trim()) gaps.push('decision.question が 1 文字以上の文字列でない');
  gaps.push(...choicesGaps(d, 'decision'), ...repliesGaps(d, 'decision'), ...decisionExtraGaps(d, 'decision'));
  return gaps;
}

function keyGaps(key, rule, v, where) {
  const name = `${where}の ${key}`;
  if (rule === 'null') return v === null ? [] : [`${name} は null(章 2 の表)だが、null でない`];
  if (rule === 'req') return v !== null && v !== undefined ? [] : [`${name} は必須(章 2 の表)だが、null`];
  if (rule === 'reqItems') {
    if (v === null || v === undefined) return [`${name} は必須(items は 1 件以上)(章 2 の表)だが、null`];
    if (!isObj(v) || !Array.isArray(v.items)) return [`${name} の items が配列でない`];
    return v.items.length ? [] : [`${name} の items が 0 件(1 件以上が要る)`];
  }
  if (rule === 'nullOrReq') return [];
  if (rule === 'askBack') {
    if (v === null) return [];
    if (!isObj(v) || v.askBack !== true) return [`${name} は null か聞き返し(章 2 の表)だが、askBack が true の decision でない`];
    return askBackGaps(v).map(g => `${where}の ${g}`);
  }
  if (rule === 'choice') {
    if (v === null || v === undefined) return [`${name} は選択肢(章 2 の表)だが、null`];
    if (isObj(v) && v.askBack === true) return askBackGaps(v).map(g => `${where}の ${g}`);
    const gaps = plainDecisionGaps(v).map(g => `${where}の ${g}`);
    if (isObj(v) && Array.isArray(v.choices) && !v.choices.length) gaps.push(`${name} は選択肢(章 2 の表)だが、choices が 0 件で、聞き返しでもない`);
    return gaps;
  }
  return [`${name} の決まりが表にない`];
}

// 段階 2 から 8 の画面の decision の決まり。聞き返し(askBack が true)は、段階 1 の 9 つの値のときだけ使う(章 3)
function stageDecisionGaps(rule, v, where) {
  const name = `${where}の decision`;
  if (rule === 'null') return v === null ? [] : [`${name} は null(章 2 の表)だが、null でない`];
  if (v === null || v === undefined) return rule === 'nullOrFree' ? [] : [`${name} は${rule === 'free' ? '自由に答える問い' : '選択肢'}(章 2 の表)だが、null`];
  const gaps = plainDecisionGaps(v).map(g => `${where}の ${g}`);
  if (isObj(v) && v.askBack === true) gaps.push(`${name} は聞き返しを持てない(章 3: 聞き返しは段階 1 の画面だけ)`);
  if (!isObj(v) || !Array.isArray(v.choices)) return gaps;
  if ((rule === 'free' || rule === 'nullOrFree') && v.choices.length) gaps.push(`${name} は自由に答える問い(章 2 の表)だが、choices が ${v.choices.length} 件`);
  if (rule === 'choice' && !v.choices.length) gaps.push(`${name} は選択肢(章 2 の表)だが、choices が 0 件`);
  return gaps;
}

// 「report.start」「decision.notice」「currentSkill.done」のような点で区切った名前の値
const dig = (state, name) => name.split('.').reduce((o, k) => (isObj(o) ? o[k] : undefined), state);

// 段階 2 から 8 の画面の行に合わない点の一覧
function stageScreenGaps(state, screen, where) {
  const rule = STAGE_TABLE.get(screen);
  const gaps = [];
  for (const key of ['summary', 'research', 'factCheck', 'approvalSheet', 'draftReview']) {
    if (key in state && state[key] !== null) gaps.push(`${where}の ${key} は null(章 2 の表)だが、null でない`);
  }
  gaps.push(...keyGaps('questions', rule.questions, state.questions ?? null, where));
  gaps.push(...stageDecisionGaps(rule.decision, state.decision ?? null, where));
  const required = [...rule.required, ...(rule.byStage[state.stage] || [])];
  for (const name of required) {
    const v = dig(state, name);
    if (v === null || v === undefined) gaps.push(`${where}の ${name} は必須(章 2 の表)だが、null`);
    else if (Array.isArray(v) && !v.length) gaps.push(`${where}の ${name} は必須(章 2 の表)だが、0 件`);
  }
  if (required.includes('currentSkill.done') && isInt(dig(state, 'currentSkill.done')) === false && dig(state, 'currentSkill.done') != null) gaps.push(`${where}の currentSkill.done が整数でない`);
  return gaps;
}

// 段階 2 から 8 で足すキーの型に合わない点の一覧。欠けたキーと null は見ない
export function addedKeyGaps(state) {
  const gaps = [];
  for (const [key, type] of Object.entries(ADDED_KEY_TYPES)) {
    if (!(key in state) || state[key] === null) continue;
    gaps.push(...typeGaps(state[key], type, key));
  }
  if (isObj(state.currentSkill) && 'done' in state.currentSkill && state.currentSkill.done !== null && !isInt(state.currentSkill.done)) gaps.push('currentSkill.done が整数でない');
  return gaps;
}

// state.json の値を受け取り、章 2 の表と章 3 の聞き返しの形に合わない点の一覧を返す。合うときは空の配列
export function stateContractGaps(state) {
  if (!isObj(state)) return ['state.json の値がオブジェクトでない'];
  const screen = state.screen ?? null;
  const where = `screen「${screen ?? 'null'}」`;
  if (STAGE_TABLE.has(screen)) {
    return [...stageScreenGaps(state, screen, where), ...addedKeyGaps(state).map(g => `${where}の ${g}`), ...roundsGaps(state.rounds).map(g => `${where}の ${g}`)];
  }
  if (!CONTRACT_TABLE.has(screen)) return [`screen「${screen}」は章 2 の表にない`];
  const rule = CONTRACT_TABLE.get(screen);
  const gaps = [];
  for (const key of KEYS) {
    if (!(key in state)) { gaps.push(`${where}の ${key} がない`); continue; }
    gaps.push(...keyGaps(key, rule[key], state[key], where));
  }
  // 聞き返しの値は、章 2 の表で「聞き返し」か「選択肢」の画面にだけ置ける
  if (isObj(state.decision) && state.decision.askBack === true && !['askBack', 'choice'].includes(rule.decision)) gaps.push(`${where}の decision は聞き返しを持てない(章 2 の表)`);
  gaps.push(...roundsGaps(state.rounds).map(g => `${where}の ${g}`));
  gaps.push(...addedKeyGaps(state).map(g => `${where}の ${g}`));
  return gaps;
}
