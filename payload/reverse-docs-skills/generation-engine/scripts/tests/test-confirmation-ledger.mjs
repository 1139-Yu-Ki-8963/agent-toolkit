import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(testDir, '../../..');
const checker = path.join(repoRoot, 'generation-engine/scripts/check-confirmation-ledger.mjs');
const surveyBuilder = path.join(repoRoot, 'generation-engine/scripts/extract/build-confirmation-survey-data.sh');

function designDocument(status, rows) {
  return `---\nstatus: ${status}\n---\n\n# 画面詳細設計書\n\n## §19 要確認事項一覧\n\n| キー | 起票日 | 内容 | 暫定扱いにしている § | 解消条件 | 状態 |\n|---|---|---|---|---|---|\n${rows.join('\n')}\n\n---\n\n## 関連資料\n`;
}

function ledger(unitKey, items) {
  return {
    unitKey,
    designDocument: '画面詳細設計書.md',
    items,
  };
}

function item(key, status, answer = '') {
  return {
    key,
    question: `${key}を確認してください`,
    status,
    answer,
  };
}

async function fixture(t, status, rows, items) {
  const dir = await mkdtemp(path.join(tmpdir(), 'confirmation-ledger-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const designPath = path.join(dir, '画面詳細設計書.md');
  await writeFile(designPath, designDocument(status, rows));
  const ledgerPath = await writeLedger(dir, 'screen-login', items);
  return { dir, designPath, ledgerPath };
}

async function writeLedger(dir, unitKey, items, basename = '要確認事項台帳.json') {
  await mkdir(dir, { recursive: true });
  const ledgerPath = path.join(dir, basename);
  await writeFile(ledgerPath, `${JSON.stringify(ledger(unitKey, items), null, 2)}\n`);
  return ledgerPath;
}

function runChecker(ledgerPath, designPath) {
  return spawnSync(process.execPath, [checker, '--ledger', ledgerPath, '--design-doc', designPath], {
    encoding: 'utf8',
  });
}

test('設計書に無い対象外の台帳行を許容し未解消が無ければ3検査に合格する', async (t) => {
  const f = await fixture(
    t,
    'approved',
    [],
    [
      item('permission-policy', '反映済み', '管理者のみ'),
      item('out-of-scope', '対象外'),
    ],
  );
  const result = runChecker(f.ledgerPath, f.designPath);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /PASS: 設計書と台帳のキー整合/);
  assert.match(result.stdout, /PASS: 台帳の回答済み行が0件/);
  assert.match(result.stdout, /PASS: 承認済み設計書の未解消行が0件/);
});

test('設計書と台帳のキーが食い違う場合は該当キーを列挙して異常終了する', async (t) => {
  const f = await fixture(
    t,
    'authored',
    [
      '| `design-only-a` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |',
      '| `design-only-b` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |',
    ],
    [item('ledger-only-a', '未確認'), item('ledger-only-b', '確認中')],
  );
  const result = runChecker(f.ledgerPath, f.designPath);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /設計書にだけ存在: design-only-a/);
  assert.match(result.stderr, /設計書にだけ存在: design-only-b/);
  assert.match(result.stderr, /台帳の未完了行が設計書に存在しない: ledger-only-a（未確認）/);
  assert.match(result.stderr, /台帳の未完了行が設計書に存在しない: ledger-only-b（確認中）/);
});

test('台帳に回答済みの行が残る場合は反映待ちのキーを列挙して異常終了する', async (t) => {
  const f = await fixture(
    t,
    'authored',
    ['| `permission-policy` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |'],
    [item('permission-policy', '回答済み', '管理者のみ')],
  );
  const result = runChecker(f.ledgerPath, f.designPath);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /反映待ち: permission-policy（回答: 管理者のみ）/);
});

test('承認済み設計書に未確認・確認中・回答済みがある場合は全行を状態付きで列挙する', async (t) => {
  const f = await fixture(
    t,
    'approved',
    [
      '| `unconfirmed` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |',
      '| `in-progress` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |',
      '| `answered` | 2026-08-19 | 内容 | §4 | 回答 | 未解消 |',
    ],
    [
      item('unconfirmed', '未確認'),
      item('in-progress', '確認中'),
      item('answered', '回答済み', '管理者のみ'),
    ],
  );
  const result = runChecker(f.ledgerPath, f.designPath);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /承認済み設計書に未解消行: unconfirmed（未確認）/);
  assert.match(result.stderr, /承認済み設計書に未解消行: in-progress（確認中）/);
  assert.match(result.stderr, /承認済み設計書に未解消行: answered（回答済み）/);
});

test('同名台帳・旧形式衝突・予約文字でもanswerTargetが各回答欄を一意に指す', async (t) => {
  const dir = await mkdtemp(path.join(tmpdir(), 'confirmation-survey-answer-target-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const itemKey = 'collision&key';
  const unresolvedPath = path.join(dir, 'unresolved-questions.json');
  await writeFile(unresolvedPath, `${JSON.stringify({
    unitKey: 'screen-login',
    items: [itemKey],
  }, null, 2)}\n`);
  const firstLedgerPath = await writeLedger(
    path.join(dir, 'screen-login'),
    'screen-login',
    [item(itemKey, '未確認')],
  );
  const secondLedgerPath = await writeLedger(
    path.join(dir, 'screen-profile'),
    'screen&profile]#',
    [item(itemKey, '未確認')],
  );
  const outputPath = path.join(dir, 'confirmation-survey.json');
  const result = spawnSync('bash', [
    surveyBuilder,
    outputPath,
    '--unresolved-questions',
    unresolvedPath,
    '--confirmation-ledger',
    firstLedgerPath,
    '--confirmation-ledger',
    secondLedgerPath,
  ], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  const output = JSON.parse(await readFile(outputPath, 'utf8'));
  assert.equal(output.questions.length, 2);
  const collidedQuestion = output.questions.find(({ targetUnit }) => targetUnit === 'screen-login');
  assert.equal(collidedQuestion.mergedCount, 2);
  assert.deepEqual(collidedQuestion.mergedQuestions, [itemKey, `${itemKey}を確認してください`]);
  const answerTargetByUnit = new Map(
    output.questions.map(({ targetUnit, answerTarget }) => [targetUnit, answerTarget]),
  );
  assert.equal(
    answerTargetByUnit.get('screen-login'),
    '要確認事項台帳.json#unitKey=screen-login&items[key=collision%26key].answer',
  );
  assert.equal(
    answerTargetByUnit.get('screen&profile]#'),
    '要確認事項台帳.json#unitKey=screen%26profile%5D%23&items[key=collision%26key].answer',
  );
  assert.notEqual(
    answerTargetByUnit.get('screen-login'),
    answerTargetByUnit.get('screen&profile]#'),
  );

  const conflictUnitKey = 'screen-conflict';
  const conflictItemKey = 'same-key';
  const conflictFirstPath = await writeLedger(
    path.join(dir, 'conflict-first'),
    conflictUnitKey,
    [item(conflictItemKey, '未確認')],
  );
  const conflictSecondPath = await writeLedger(
    path.join(dir, 'conflict-second'),
    conflictUnitKey,
    [item(conflictItemKey, '未確認')],
  );
  const conflictOutputPath = path.join(dir, 'confirmation-survey-conflict.json');
  const conflictResult = spawnSync('bash', [
    surveyBuilder,
    conflictOutputPath,
    '--confirmation-ledger',
    conflictFirstPath,
    '--confirmation-ledger',
    conflictSecondPath,
  ], {
    encoding: 'utf8',
  });
  assert.notEqual(conflictResult.status, 0);
  assert.match(conflictResult.stderr, /要確認事項台帳のunitKeyが重複しています/);
  assert.match(conflictResult.stderr, /unitKey=screen-conflict/);
  assert.match(conflictResult.stderr, /conflict-first.*要確認事項台帳\.json/);
  assert.match(conflictResult.stderr, /conflict-second.*要確認事項台帳\.json/);
  assert.equal(
    conflictResult.stderr.match(/basename=要確認事項台帳\.json/g)?.length,
    2,
  );

  const blankUnitKeyLedgerPath = await writeLedger(
    path.join(dir, 'blank-unit-key'),
    ' \t ',
    [item('permission-policy', '未確認')],
  );
  const blankUnitKeyResult = spawnSync('bash', [
    surveyBuilder,
    path.join(dir, 'confirmation-survey-blank-unit-key.json'),
    '--confirmation-ledger',
    blankUnitKeyLedgerPath,
  ], {
    encoding: 'utf8',
  });
  assert.notEqual(blankUnitKeyResult.status, 0);
  assert.match(blankUnitKeyResult.stderr, /unitKeyは空でない文字列/);

  const feffUnitKeyLedgerPath = await writeLedger(
    path.join(dir, 'feff-unit-key'),
    '\uFEFF',
    [item('permission-policy', '未確認')],
  );
  const feffUnitKeyResult = spawnSync('bash', [
    surveyBuilder,
    path.join(dir, 'confirmation-survey-feff-unit-key.json'),
    '--confirmation-ledger',
    feffUnitKeyLedgerPath,
  ], {
    encoding: 'utf8',
  });
  assert.notEqual(feffUnitKeyResult.status, 0);
  assert.match(feffUnitKeyResult.stderr, /unitKeyは空でない文字列/);

  const paddedUnitKey = ' \t screen-valid \t ';
  const paddedUnitKeyLedgerPath = await writeLedger(
    path.join(dir, 'padded-unit-key'),
    paddedUnitKey,
    [item('permission-policy', '未確認')],
  );
  const paddedOutputPath = path.join(dir, 'confirmation-survey-padded-unit-key.json');
  const paddedUnitKeyResult = spawnSync('bash', [
    surveyBuilder,
    paddedOutputPath,
    '--confirmation-ledger',
    paddedUnitKeyLedgerPath,
  ], {
    encoding: 'utf8',
  });
  assert.equal(paddedUnitKeyResult.status, 0, paddedUnitKeyResult.stderr);
  const paddedOutput = JSON.parse(await readFile(paddedOutputPath, 'utf8'));
  assert.equal(paddedOutput.questions[0].targetUnit, paddedUnitKey);

  const lineUnitKey = 'screen-line';
  const newlineUnitKey = 'screen-line\n';
  const lineLedgerPath = await writeLedger(
    path.join(dir, 'line-unit-key'),
    lineUnitKey,
    [item('permission-policy', '未確認')],
  );
  const newlineLedgerPath = await writeLedger(
    path.join(dir, 'newline-unit-key'),
    newlineUnitKey,
    [item('permission-policy', '未確認')],
  );
  const lineOutputPath = path.join(dir, 'confirmation-survey-line-unit-keys.json');
  const lineResult = spawnSync(
    'bash',
    [
      surveyBuilder,
      lineOutputPath,
      '--confirmation-ledger',
      lineLedgerPath,
      '--confirmation-ledger',
      newlineLedgerPath,
    ],
    { encoding: 'utf8' },
  );
  assert.equal(lineResult.status, 0, lineResult.stderr);

  const lineOutput = JSON.parse(await readFile(lineOutputPath, 'utf8'));
  assert.equal(lineOutput.questions.length, 2);
  const lineAnswerTargetByUnit = new Map(
    lineOutput.questions.map((question) => [question.targetUnit, question.answerTarget]),
  );
  assert.equal(
    lineAnswerTargetByUnit.get(lineUnitKey),
    '要確認事項台帳.json#unitKey=screen-line&items[key=permission-policy].answer',
  );
  assert.equal(
    lineAnswerTargetByUnit.get(newlineUnitKey),
    '要確認事項台帳.json#unitKey=screen-line%0A&items[key=permission-policy].answer',
  );
  assert.notEqual(
    lineAnswerTargetByUnit.get(lineUnitKey),
    lineAnswerTargetByUnit.get(newlineUnitKey),
  );
});
