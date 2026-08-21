#!/usr/bin/env node

import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import process from 'node:process';

const ACTIVE_STATUSES = new Set(['未確認', '確認中', '回答済み']);
const CLOSED_STATUSES = new Set(['反映済み', '対象外']);
const ALLOWED_STATUSES = new Set([...ACTIVE_STATUSES, ...CLOSED_STATUSES]);
const ITEM_FIELDS = [
  'key',
  'raisedDate',
  'question',
  'unresolvedReason',
  'status',
  'answer',
  'answeredDate',
  'target',
];

function usage() {
  return [
    'Usage:',
    '  node apply-confirmation-answers.mjs --ledger <要確認事項台帳.json> [--design-doc <設計書.md>] [--check-only]',
    '  node apply-confirmation-answers.mjs --self-test',
  ].join('\n');
}

function parseArgs(argv) {
  const args = { ledgerPath: '', designDocPath: '', checkOnly: false, selfTest: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--ledger') {
      args.ledgerPath = argv[index + 1] ?? '';
      index += 1;
    } else if (arg === '--design-doc') {
      args.designDocPath = argv[index + 1] ?? '';
      index += 1;
    } else if (arg === '--check-only') {
      args.checkOnly = true;
    } else if (arg === '--self-test') {
      args.selfTest = true;
    } else {
      throw new Error(`不明な引数です: ${arg}\n${usage()}`);
    }
  }
  if (!args.selfTest && !args.ledgerPath) throw new Error(`--ledger は必須です\n${usage()}`);
  return args;
}

function cleanCell(value) {
  return value
    .trim()
    .replace(/^`|`$/g, '')
    .replaceAll('\\|', '|')
    .replaceAll('<br>', '\n')
    .trim();
}

function escapeCell(value) {
  return String(value).replaceAll('|', '\\|').replaceAll('\n', '<br>');
}

function splitRow(line) {
  return line.trim().replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map(cleanCell);
}

function duplicateValues(values) {
  const seen = new Set();
  const duplicates = new Set();
  for (const value of values) {
    if (seen.has(value)) duplicates.add(value);
    seen.add(value);
  }
  return [...duplicates];
}

function isDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function validateLedger(ledger) {
  if (!ledger || typeof ledger !== 'object' || Array.isArray(ledger)) {
    throw new Error('台帳はJSONオブジェクトでなければなりません');
  }
  if (typeof ledger.unitKey !== 'string' || !ledger.unitKey.trim()) {
    throw new Error('unitKey は空でない文字列でなければなりません');
  }
  if (typeof ledger.designDocument !== 'string' || !ledger.designDocument.trim()) {
    throw new Error('designDocument は空でない文字列でなければなりません');
  }
  if (!Array.isArray(ledger.items)) throw new Error('items は配列でなければなりません');

  ledger.items.forEach((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error(`items[${index}] はオブジェクトでなければなりません`);
    }
    const keys = Object.keys(item).sort();
    assert.deepEqual(keys, [...ITEM_FIELDS].sort(), `items[${index}] は8項目だけを持つ必要があります`);
    for (const field of ITEM_FIELDS.slice(0, 7)) {
      if (typeof item[field] !== 'string') throw new Error(`items[${index}].${field} は文字列でなければなりません`);
    }
    if (!item.key.trim() || !item.question.trim() || !item.unresolvedReason.trim()) {
      throw new Error(`items[${index}] の key・question・unresolvedReason は空にできません`);
    }
    if (!isDate(item.raisedDate)) throw new Error(`items[${index}].raisedDate は YYYY-MM-DD 形式でなければなりません`);
    if (!ALLOWED_STATUSES.has(item.status)) throw new Error(`items[${index}].status が許可値ではありません: ${item.status}`);
    if (!item.target || typeof item.target !== 'object' || Array.isArray(item.target)) {
      throw new Error(`items[${index}].target はオブジェクトでなければなりません`);
    }
    assert.deepEqual(Object.keys(item.target).sort(), ['column', 'rowKey', 'section'], `items[${index}].target の項目が不正です`);
    for (const field of ['section', 'rowKey', 'column']) {
      if (typeof item.target[field] !== 'string' || !item.target[field].trim()) {
        throw new Error(`items[${index}].target.${field} は空でない文字列でなければなりません`);
      }
    }
    if (['回答済み', '反映済み'].includes(item.status)) {
      if (!item.answer.trim()) throw new Error(`items[${index}] は ${item.status} ですが回答が空です`);
      if (!isDate(item.answeredDate)) throw new Error(`items[${index}].answeredDate は YYYY-MM-DD 形式でなければなりません`);
    } else if (item.status !== '対象外' && (item.answer || item.answeredDate)) {
      throw new Error(`items[${index}] は未回答状態ですが回答または回答日を持っています`);
    }
  });
}

function findHeadingRange(lines, headingText) {
  const start = lines.findIndex((line) => /^#{1,6}\s+/.test(line) && line.replace(/^#{1,6}\s+/, '').trim() === headingText);
  if (start < 0) throw new Error(`反映先の節が見つかりません: ${headingText}`);
  const level = lines[start].match(/^(#+)/)[1].length;
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    const match = lines[index].match(/^(#+)\s+/);
    if (match && match[1].length <= level) {
      end = index;
      break;
    }
  }
  return { start, end };
}

function findTable(lines, range, item) {
  for (let headerIndex = range.start + 1; headerIndex < range.end - 1; headerIndex += 1) {
    if (!/^\s*\|/.test(lines[headerIndex]) || !/^\s*\|(?:\s*:?-{3,}:?\s*\|)+\s*$/.test(lines[headerIndex + 1])) continue;
    const headers = splitRow(lines[headerIndex]);
    const columnIndex = headers.indexOf(item.target.column);
    if (columnIndex < 0) continue;
    for (let rowIndex = headerIndex + 2; rowIndex < range.end && /^\s*\|/.test(lines[rowIndex]); rowIndex += 1) {
      const cells = splitRow(lines[rowIndex]);
      if (cells[0] === item.target.rowKey) return { rowIndex, columnIndex, cells };
    }
  }
  throw new Error(`反映先のセルが見つかりません: ${item.key}（${item.target.section} / ${item.target.rowKey} / ${item.target.column}）`);
}

function confirmationTable(markdown) {
  const lines = markdown.split(/\r?\n/);
  const headingIndex = lines.findIndex((line) => /^##\s+(?:§\d+\s+)?要確認事項一覧\s*$/.test(line));
  if (headingIndex < 0) throw new Error('設計書に「要確認事項一覧」節がありません');
  for (let headerIndex = headingIndex + 1; headerIndex < lines.length - 1; headerIndex += 1) {
    if (!/^\s*\|/.test(lines[headerIndex]) || !/^\s*\|(?:\s*:?-{3,}:?\s*\|)+\s*$/.test(lines[headerIndex + 1])) continue;
    const headers = splitRow(lines[headerIndex]);
    if (headers.join('|') !== 'キー|確認事項|確認先') {
      throw new Error('要確認事項一覧は「キー・確認事項・確認先」の3列でなければなりません');
    }
    let end = headerIndex + 2;
    while (end < lines.length && /^\s*\|/.test(lines[end])) end += 1;
    return { lines, headerIndex, start: headerIndex + 2, end };
  }
  throw new Error('要確認事項一覧の表が見つかりません');
}

function confirmationKeys(markdown) {
  const table = confirmationTable(markdown);
  return table.lines.slice(table.start, table.end).map((line) => splitRow(line)[0]).filter(Boolean);
}

function applyAnswers(markdown, ledger) {
  const lines = markdown.split(/\r?\n/);
  const answered = ledger.items.filter((item) => item.status === '回答済み');
  for (const item of answered) {
    const range = findHeadingRange(lines, item.target.section);
    const target = findTable(lines, range, item);
    target.cells[target.columnIndex] = escapeCell(item.answer);
    lines[target.rowIndex] = `| ${target.cells.join(' | ')} |`;
  }

  const appliedKeys = new Set(answered.map((item) => item.key));
  const table = confirmationTable(lines.join('\n'));
  const keptRows = table.lines.slice(table.start, table.end).filter((line) => !appliedKeys.has(splitRow(line)[0]));
  table.lines.splice(table.start, table.end - table.start, ...keptRows);
  answered.forEach((item) => { item.status = '反映済み'; });
  return table.lines.join('\n');
}

function assertConsistency(markdown, ledger) {
  validateLedger(ledger);
  const lines = markdown.split(/\r?\n/);
  const designKeys = confirmationKeys(markdown);
  const ledgerKeys = ledger.items.map((item) => item.key);
  const expectedKeys = ledger.items.filter((item) => ACTIVE_STATUSES.has(item.status)).map((item) => item.key);
  const failures = [
    ...duplicateValues(designKeys).map((key) => `設計書でキーが重複: ${key}`),
    ...duplicateValues(ledgerKeys).map((key) => `台帳でキーが重複: ${key}`),
    ...designKeys.filter((key) => !expectedKeys.includes(key)).map((key) => `一覧に完了済みのキーが残存: ${key}`),
    ...expectedKeys.filter((key) => !designKeys.includes(key)).map((key) => `一覧に未完了のキーがない: ${key}`),
    ...ledger.items.filter((item) => item.status === '回答済み').map((item) => `回答済みのまま未反映: ${item.key}`),
  ];
  for (const item of ledger.items.filter(({ status }) => status === '反映済み')) {
    try {
      const range = findHeadingRange(lines, item.target.section);
      const target = findTable(lines, range, item);
      if (target.cells[target.columnIndex] !== item.answer) {
        failures.push(`反映済みの本文セルが回答と不一致: ${item.key}`);
      }
    } catch (error) {
      failures.push(`反映済みの本文セルを確認できない: ${item.key}（${error.message}）`);
    }
  }
  if (failures.length > 0) throw new Error(`設計書と台帳が不整合です:\n- ${failures.join('\n- ')}`);
}

async function processFiles({ ledgerPath, designDocPath, checkOnly }) {
  const resolvedLedgerPath = path.resolve(ledgerPath);
  const ledger = JSON.parse(await readFile(resolvedLedgerPath, 'utf8'));
  validateLedger(ledger);
  const resolvedDesignPath = path.resolve(designDocPath || path.join(path.dirname(resolvedLedgerPath), ledger.designDocument));
  const originalMarkdown = await readFile(resolvedDesignPath, 'utf8');

  if (checkOnly) {
    assertConsistency(originalMarkdown, ledger);
    console.log('PASS: 設計書と要確認事項台帳は整合しています');
    return;
  }

  const nextLedger = structuredClone(ledger);
  const nextMarkdown = applyAnswers(originalMarkdown, nextLedger);
  assertConsistency(nextMarkdown, nextLedger);
  await writeFile(resolvedDesignPath, nextMarkdown, 'utf8');
  await writeFile(resolvedLedgerPath, `${JSON.stringify(nextLedger, null, 2)}\n`, 'utf8');
  nextLedger.items
    .filter((item) => item.status === '未確認' || item.status === '確認中')
    .forEach((item) => console.log(`未回答のため残す: ${item.key}（${item.status}）`));
  console.log(`PASS: 回答${ledger.items.filter((item) => item.status === '回答済み').length}件を本文へ反映しました`);
  console.log('PASS: 設計書と要確認事項台帳は整合しています');
}

async function selfTest() {
  const dir = await mkdtemp(path.join(tmpdir(), 'resolving-confirmation-items-'));
  try {
    const designPath = path.join(dir, '設計書.md');
    const ledgerPath = path.join(dir, '要確認事項台帳.json');
    const design = `# 合成設計書\n\n## §2 業務仕様\n\n| キー | 判定内容 | 根拠 |\n|---|---|---|\n| auth-policy | 未確定 | コードから確定不可 |\n| retry-policy | 未確定 | コードから確定不可 |\n\n## §9 要確認事項一覧\n\n| キー | 確認事項 | 確認先 |\n|---|---|---|\n| auth-policy | 操作権限を確認する | 業務責任者 |\n| retry-policy | 再試行回数を確認する | 運用責任者 |\n| retention | 保存期間を確認する | 法務担当者 |\n`;
    const target = (rowKey, column) => ({ section: '§2 業務仕様', rowKey, column });
    const item = (key, status, answer, answeredDate, reflectionTarget) => ({
      key,
      raisedDate: '2026-08-20',
      question: `${key}を確認する`,
      unresolvedReason: 'コードに判断根拠が存在しないため',
      status,
      answer,
      answeredDate,
      target: reflectionTarget,
    });
    const ledger = {
      unitKey: 'fixture-unit',
      designDocument: '設計書.md',
      items: [
        item('auth-policy', '回答済み', '管理者だけに許可する', '2026-08-20', target('auth-policy', '判定内容')),
        item('retry-policy', '回答済み', '3回まで再試行する', '2026-08-20', target('retry-policy', '判定内容')),
        item('retention', '未確認', '', '', target('retention-policy', '判定内容')),
      ],
    };
    await writeFile(designPath, design, 'utf8');
    await writeFile(ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
    await processFiles({ ledgerPath, designDocPath: designPath, checkOnly: false });
    const actualDesign = await readFile(designPath, 'utf8');
    const actualLedger = JSON.parse(await readFile(ledgerPath, 'utf8'));
    assert.match(actualDesign, /\| auth-policy \| 管理者だけに許可する \|/);
    assert.match(actualDesign, /\| retry-policy \| 3回まで再試行する \|/);
    assert.doesNotMatch(actualDesign, /\| auth-policy \| 操作権限を確認する \|/);
    assert.doesNotMatch(actualDesign, /\| retry-policy \| 再試行回数を確認する \|/);
    assert.match(actualDesign, /\| retention \| 保存期間を確認する \| 法務担当者 \|/);
    assert.deepEqual(actualLedger.items.map(({ status }) => status), ['反映済み', '反映済み', '未確認']);
    await processFiles({ ledgerPath, designDocPath: designPath, checkOnly: true });
    await writeFile(designPath, actualDesign.replace('管理者だけに許可する', '未確定'), 'utf8');
    await assert.rejects(
      processFiles({ ledgerPath, designDocPath: designPath, checkOnly: true }),
      /反映済みの本文セルが回答と不一致: auth-policy/,
    );
    console.log('self-test PASS: 回答済み2件の本文反映と一覧削除、未回答1件の保持、反映後の整合と本文ドリフトの拒否を確認しました');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) await selfTest();
  else await processFiles(args);
}

main().catch((error) => {
  console.error(`ERROR: ${error.message}`);
  process.exitCode = 1;
});
