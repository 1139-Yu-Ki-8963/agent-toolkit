#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const ACTIVE_STATUSES = new Set(['未確認', '確認中', '回答済み']);
const CLOSED_STATUSES = new Set(['反映済み', '対象外']);
const ALLOWED_STATUSES = new Set([...ACTIVE_STATUSES, ...CLOSED_STATUSES]);

function usage() {
  return 'Usage: node check-confirmation-ledger.mjs --ledger <要確認事項台帳.json> [--design-doc <画面詳細設計書.md>]';
}

function parseArgs(argv) {
  let ledgerPath = '';
  let designDocPath = '';

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--ledger') {
      ledgerPath = argv[index + 1] ?? '';
      index += 1;
    } else if (arg === '--design-doc') {
      designDocPath = argv[index + 1] ?? '';
      index += 1;
    } else {
      throw new Error(`不明な引数です: ${arg}\n${usage()}`);
    }
  }

  if (!ledgerPath) {
    throw new Error(`--ledger は必須です\n${usage()}`);
  }
  return { ledgerPath: path.resolve(ledgerPath), designDocPath };
}

function parseFrontmatterStatus(markdown) {
  const match = markdown.match(/^---\s*\n([\s\S]*?)\n---(?:\s*\n|$)/);
  if (!match) return '';
  const statusLine = match[1].match(/^status:\s*([^#\n]+?)(?:\s+#.*)?$/m);
  return statusLine ? statusLine[1].trim().replace(/^['"]|['"]$/g, '') : '';
}

function cleanCell(value) {
  return value.trim().replace(/^`|`$/g, '').trim();
}

function extractConfirmationKeys(markdown) {
  const lines = markdown.split(/\r?\n/);
  const headingIndex = lines.findIndex((line) => /^##\s+(?:§\d+\s+)?要確認事項一覧\s*$/.test(line));
  if (headingIndex < 0) {
    throw new Error('設計書に「要確認事項一覧」章がありません');
  }

  const keys = [];
  for (const line of lines.slice(headingIndex + 1)) {
    if (/^##\s+/.test(line)) break;
    if (!/^\s*\|/.test(line)) continue;
    const cells = line.trim().replace(/^\||\|$/g, '').split('|').map(cleanCell);
    const key = cells[0] ?? '';
    if (!key || key === 'キー' || /^:?-{3,}:?$/.test(key)) continue;
    keys.push(key);
  }
  return keys;
}

function duplicates(values) {
  const seen = new Set();
  const duplicateValues = new Set();
  for (const value of values) {
    if (seen.has(value)) duplicateValues.add(value);
    seen.add(value);
  }
  return [...duplicateValues];
}

function validateLedgerShape(ledger) {
  if (!ledger || typeof ledger !== 'object' || Array.isArray(ledger)) {
    throw new Error('台帳はJSONオブジェクトでなければなりません');
  }
  if (typeof ledger.unitKey !== 'string' || !ledger.unitKey.trim()) {
    throw new Error('台帳の unitKey は空でない文字列でなければなりません');
  }
  if (typeof ledger.designDocument !== 'string' || !ledger.designDocument.trim()) {
    throw new Error('台帳の designDocument は空でない文字列でなければなりません');
  }
  if (!Array.isArray(ledger.items)) {
    throw new Error('台帳の items は配列でなければなりません');
  }

  ledger.items.forEach((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error(`台帳 items[${index}] はオブジェクトでなければなりません`);
    }
    for (const field of ['key', 'question', 'status', 'answer']) {
      if (typeof item[field] !== 'string') {
        throw new Error(`台帳 items[${index}].${field} は文字列でなければなりません`);
      }
    }
    if (!item.key.trim()) {
      throw new Error(`台帳 items[${index}].key は空にできません`);
    }
    if (!ALLOWED_STATUSES.has(item.status)) {
      throw new Error(`台帳 items[${index}].status が許可値ではありません: ${item.status}`);
    }
  });
}

function reportFailure(label, rows) {
  if (rows.length === 0) {
    console.log(`PASS: ${label}`);
    return false;
  }
  console.error(`FAIL: ${label}`);
  rows.forEach((row) => console.error(`  - ${row}`));
  return true;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const ledger = JSON.parse(await readFile(args.ledgerPath, 'utf8'));
  validateLedgerShape(ledger);

  const designDocPath = path.resolve(
    args.designDocPath || path.join(path.dirname(args.ledgerPath), ledger.designDocument),
  );
  const markdown = await readFile(designDocPath, 'utf8');
  const designStatus = parseFrontmatterStatus(markdown);
  const designKeys = extractConfirmationKeys(markdown);
  const ledgerKeys = ledger.items.map((item) => item.key);
  const designKeySet = new Set(designKeys);
  const ledgerKeySet = new Set(ledgerKeys);

  const consistencyFailures = [
    ...duplicates(designKeys).map((key) => `設計書でキーが重複: ${key}`),
    ...duplicates(ledgerKeys).map((key) => `台帳でキーが重複: ${key}`),
    ...designKeys.filter((key) => !ledgerKeySet.has(key)).map((key) => `設計書にだけ存在: ${key}`),
    ...ledger.items
      .filter((item) => !CLOSED_STATUSES.has(item.status) && !designKeySet.has(item.key))
      .map((item) => `台帳の未完了行が設計書に存在しない: ${item.key}（${item.status}）`),
  ];
  const answerFailures = ledger.items
    .filter((item) => item.status === '回答済み')
    .map((item) => `反映待ち: ${item.key}（回答: ${item.answer || '空欄'}）`);
  const approvalFailures = designStatus === 'approved'
    ? ledger.items
      .filter((item) => ACTIVE_STATUSES.has(item.status))
      .map((item) => `承認済み設計書に未解消行: ${item.key}（${item.status}）`)
    : [];

  let failed = false;
  failed = reportFailure('設計書と台帳のキー整合', consistencyFailures) || failed;
  failed = reportFailure('台帳の回答済み行が0件', answerFailures) || failed;
  failed = reportFailure('承認済み設計書の未解消行が0件', approvalFailures) || failed;

  if (failed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`ERROR: ${error.message}`);
  process.exitCode = 2;
});
