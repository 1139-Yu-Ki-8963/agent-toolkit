#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const temporaryRoot = fs.realpathSync(fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'generated-introduction-guidance.')));

function run(script, args) {
  const result = spawnSync('bash', [path.join(repoRoot, script), ...args], { encoding: 'utf8' });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout);
    throw new Error(`${script} failed with exit ${result.status}`);
  }
}

function countLines(source, predicate) {
  return source.split(/\r?\n/).filter(predicate).length;
}

function checkDocument(file, expectedSections) {
  const source = fs.readFileSync(file, 'utf8');
  const headings = source.match(/^## .+$/gm) || [];
  const numbered = headings.filter((heading) => heading.startsWith('## §'));
  const sections = numbered.length > 0 ? numbered.length : headings.length;
  const headers = countLines(source, (line) => line === '| 節 | 内容 | 読み手へのお願い |');
  const tableStart = source.indexOf('| 節 | 内容 | 読み手へのお願い |');
  const afterHeader = source.slice(tableStart).split(/\r?\n/).slice(2);
  const rows = afterHeader.findIndex((line) => !line.startsWith('|'));
  if (sections !== expectedSections || rows !== sections || headers !== 1) {
    throw new Error(`FAIL: ${file} (sections=${sections} rows=${rows} headers=${headers})`);
  }
  process.stdout.write(`PASS: ${file} (sections=${sections} rows=${rows} headers=${headers})\n`);
}

try {
  const screenRoot = path.join(temporaryRoot, 'screen');
  const apiRoot = path.join(temporaryRoot, 'api');
  fs.mkdirSync(screenRoot);
  fs.mkdirSync(apiRoot);
  run('generation-engine/scripts/scaffold-screen.sh', [screenRoot, 'acceptance-four', '検収四試験画面']);
  run('generation-engine/scripts/scaffold-design-unit.sh', ['api', 'detail', apiRoot, 'acceptance-four', '検収四試験API']);

  const screenUnit = path.join(screenRoot, 'docs/design/screens/screen-acceptance-four');
  const common = path.join(screenRoot, 'docs/design/common');
  const apiUnit = path.join(apiRoot, 'docs/design/apis/api-acceptance-four/detail-design');
  checkDocument(path.join(screenUnit, '詳細設計/画面詳細設計書.md'), 19);
  checkDocument(path.join(apiUnit, 'API詳細設計書.md'), 13);
  checkDocument(path.join(screenUnit, '詳細設計/DESIGN.md'), 7);
  checkDocument(path.join(screenUnit, 'テスト設計/操作シナリオ仕様書.md'), 5);
  checkDocument(path.join(common, 'DESIGN.md'), 6);
  checkDocument(path.join(common, 'メッセージ定義書.md'), 4);
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
