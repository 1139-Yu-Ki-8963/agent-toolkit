import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { parseImprovementLedger, splitMarkdownTableRow } from './check-improvement-ledger.mjs';

function ledger(...rows) {
  return [
    '| 項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果 |',
    '|---|---|---|---|---|---|',
    ...rows,
  ].join('\n');
}

function outerlessLedger(...rows) {
  return [
    '項目 | 項目名 | 反映先資産 | 反映箇所 | 配線した呼び出し箇所 | 検証方法と結果',
    '--- | --- | --- | --- | --- | ---',
    ...rows,
  ].join('\n');
}

test('escaped pipes remain within one table cell', () => {
  const parsed = splitMarkdownTableRow('| 1 | name | asset | location | route \\| detail | 未検証 |');
  assert.equal(parsed.cells.length, 6);
  assert.equal(parsed.cells[4], 'route \\| detail');
});

test('an unescaped pipe is reported as a column and raw-pipe anomaly', () => {
  const result = parseImprovementLedger(ledger('| 1 | name | asset | location | route | detail | 未検証 |'));
  assert.deepEqual(result.columnCountHistogram, { 7: 1 });
  assert.deepEqual(result.nonSixColumnRows, [{ lineNumber: 3, itemId: '1' }]);
  assert.deepEqual(result.rawUnescapedPipeAnomalies, [{ lineNumber: 3, itemId: '1' }]);
  assert.equal(result.passed, false);
});

test('an outer-pipe-free GFM table is parsed', () => {
  const result = parseImprovementLedger(outerlessLedger(
    '1 | name | asset | location | route | 未検証',
  ));
  assert.equal(result.totalDataRows, 1);
  assert.deepEqual(result.columnCountHistogram, { 6: 1 });
  assert.equal(result.passed, true);
});

test('pseudo-tables inside code fences are ignored', () => {
  const result = parseImprovementLedger([
    '```markdown',
    ledger('| ignored | name | asset | location | route | 未検証 |'),
    '```',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('pseudo-tables inside list and quote code fences are ignored', () => {
  const result = parseImprovementLedger([
    '- ```markdown',
    ledger('| ignored-list | name | asset | location | route | 未検証 |')
      .split('\n')
      .map((line) => `  ${line}`)
      .join('\n'),
    '  ```',
    '> ```markdown',
    ledger('| ignored-quote | name | asset | location | route | 未検証 |')
      .split('\n')
      .map((line) => `> ${line}`)
      .join('\n'),
    '> ```',
    ' - ```markdown',
    ledger('| ignored-indented-list | name | asset | location | route | extra | 未検証 |')
      .split('\n')
      .map((line) => `   ${line}`)
      .join('\n'),
    '   ```',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('a top-level fence is not closed by a list or quote fence marker', () => {
  const result = parseImprovementLedger([
    '````markdown',
    '- ````',
    '> ````',
    ledger('| ignored | name | asset | location | route | 未検証 |'),
    '````',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('an unclosed container fence ends when its container ends', () => {
  const result = parseImprovementLedger([
    '> ```markdown',
    '> fenced content',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
    '- ```markdown',
    '  fenced content',
    outerlessLedger('2 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 2);
  assert.equal(result.passed, true);
});

test('a fence remains open after a non-whitespace pseudo-closer', () => {
  const result = parseImprovementLedger([
    '```markdown',
    ledger('| ignored-1 | name | asset | location | route | 未検証 |'),
    '```not-a-close',
    ledger('| ignored-2 | name | asset | location | route | 未検証 |'),
    '```',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('a four-space-indented fence-like line does not open a fence', () => {
  const result = parseImprovementLedger([
    '    ```',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('a four-space-indented table is excluded as an indented code block', () => {
  const indentedTable = outerlessLedger('1 | name | asset | location | route | 未検証')
    .split('\n')
    .map((line) => `    ${line}`)
    .join('\n');
  const result = parseImprovementLedger(indentedTable);
  assert.equal(result.totalDataRows, 0);
  assert.equal(result.passed, false);
});

test('a backtick fence candidate with a backtick in its info string does not open a fence', () => {
  const result = parseImprovementLedger([
    '```language`not-a-fence',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('a shorter backtick marker does not close a longer fence', () => {
  const result = parseImprovementLedger([
    '````markdown',
    ledger('| ignored-1 | name | asset | location | route | 未検証 |'),
    '```',
    ledger('| ignored-2 | name | asset | location | route | 未検証 |'),
    '````',
    outerlessLedger('1 | name | asset | location | route | 未検証'),
  ].join('\n'));
  assert.equal(result.totalDataRows, 1);
  assert.equal(result.passed, true);
});

test('a table cell containing an inline fence marker is parsed normally', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | ```abc``` | asset | location | route | 未検証 |',
  ));
  assert.equal(result.totalDataRows, 1);
  assert.deepEqual(result.columnCountHistogram, { 6: 1 });
  assert.equal(result.passed, true);
});

test('classification counts distinguish all three types and unverified exact match', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | name | asset | location | route | 実データ相当: 確認 |',
    '| 2 | name | asset | location | route | 自己テストのみ: PASS |',
    '| 3 | name | asset | location | route | 未検証 |',
  ));
  assert.deepEqual(result.verificationTypeCounts, {
    '実データ相当': 1,
    '自己テストのみ': 1,
    '未検証': 1,
  });
  assert.equal(result.unverifiedExactCount, 1);
  assert.equal(result.unverifiedContainsCount, 1);
  assert.equal(result.passed, true);
});

test('an unmet real-data verification is not classified as real-data-equivalent', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | name | asset | location | route | 未検証（検証種別未記載）: 実データでの実証は未達 |',
  ));
  assert.deepEqual(result.verificationTypeCounts, {
    '実データ相当': 0,
    '自己テストのみ': 0,
    '未検証': 1,
  });
  assert.equal(result.passed, true);
});

test('classification words in explanatory prose are not treated as type labels', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | name | asset | location | route | 実データ相当の検証は未実施 |',
    '| 2 | name | asset | location | route | 説明文に未検証という語を含む |',
  ));
  assert.deepEqual(result.verificationTypeCounts, {
    '実データ相当': 0,
    '自己テストのみ': 0,
    '未検証': 0,
  });
  assert.deepEqual(result.unclassifiableRows, [
    { lineNumber: 3, itemId: '1' },
    { lineNumber: 4, itemId: '2' },
  ]);
  assert.equal(result.passed, false);
});

test('a ledger with no data rows fails closed', () => {
  const result = parseImprovementLedger('');
  assert.equal(result.totalDataRows, 0);
  assert.equal(result.hasDataRows, false);
  assert.equal(result.passed, false);
});

test('blank and ASCII-hyphen fifth and sixth cells are reported', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | name | asset | location |  | 未検証 |',
    '| 2 | name | asset | location | route | - |',
  ));
  assert.deepEqual(result.fifthColumnBlankOrHyphen, [{ lineNumber: 3, itemId: '1' }]);
  assert.deepEqual(result.sixthColumnBlankOrHyphen, [{ lineNumber: 4, itemId: '2' }]);
  assert.equal(result.passed, false);
});

test('unclassifiable classification labels are reported', () => {
  const result = parseImprovementLedger(ledger(
    '| 1 | name | asset | location | route | 確認済み |',
    '| 2 | name | asset | location | route | 未検証・自己テストのみ |',
  ));
  assert.deepEqual(result.unclassifiableRows, [
    { lineNumber: 3, itemId: '1' },
    { lineNumber: 4, itemId: '2' },
  ]);
  assert.deepEqual(result.multipleClassificationRows, []);
  assert.equal(result.passed, false);
});

test('CLI parses stdin and returns JSON for normal and raw-pipe fixtures', () => {
  const scriptPath = fileURLToPath(new URL('./check-improvement-ledger.mjs', import.meta.url));
  const normal = spawnSync(process.execPath, [scriptPath, '/dev/stdin'], {
    input: outerlessLedger('1 | name | asset | location | route | 未検証'),
    encoding: 'utf8',
  });
  assert.equal(normal.status, 0);
  assert.equal(JSON.parse(normal.stdout).passed, true);

  const invalid = spawnSync(process.execPath, [scriptPath, '/dev/stdin'], {
    input: outerlessLedger('1 | name | asset | location | route | extra | 未検証'),
    encoding: 'utf8',
  });
  assert.equal(invalid.status, 1);
  const invalidResult = JSON.parse(invalid.stdout);
  assert.equal(invalidResult.passed, false);
  assert.deepEqual(invalidResult.rawUnescapedPipeAnomalies, [{ lineNumber: 3, itemId: '1' }]);
});

test('the checked-in improvement ledger satisfies every condition', () => {
  const source = readFileSync(new URL('../../docs/ledgers/改善反映台帳.md', import.meta.url), 'utf8');
  const result = parseImprovementLedger(source);
  assert.equal(result.totalDataRows, 259);
  assert.deepEqual(result.columnCountHistogram, { 6: 259 });
  assert.equal(result.unverifiedExactCount, 144);
  assert.equal(result.unverifiedContainsCount, 217);
  assert.deepEqual(result.verificationTypeCounts, {
    '実データ相当': 8,
    '自己テストのみ': 34,
    '未検証': 217,
  });
  assert.deepEqual(result.nonSixColumnRows, []);
  assert.deepEqual(result.rawUnescapedPipeAnomalies, []);
  assert.deepEqual(result.fifthColumnBlankOrHyphen, []);
  assert.deepEqual(result.sixthColumnBlankOrHyphen, []);
  assert.deepEqual(result.unclassifiableRows, []);
  assert.deepEqual(result.multipleClassificationRows, []);
  assert.equal(result.passed, true);
});
