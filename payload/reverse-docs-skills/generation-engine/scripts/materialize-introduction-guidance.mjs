#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const MARKER = '<!-- INTRODUCTION_GUIDANCE:';
const HEADER = '| 節 | 内容 | 読み手へのお願い |';

function markdownFiles(root) {
  const files = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const target = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...markdownFiles(target));
    if (entry.isFile() && entry.name.endsWith('.md')) files.push(target);
  }
  return files;
}

function materialize(file) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes(MARKER) || source.includes(HEADER)) return false;

  const headings = [...source.matchAll(/^## ([^\r\n]+)$/gm)].map((match) => match[1].trim());
  const numberedSections = headings.filter((heading) => heading.startsWith('§'));
  const sections = numberedSections.length > 0 ? numberedSections : headings;
  if (sections.length === 0) return false;

  const markerEnd = source.indexOf('-->', source.indexOf(MARKER));
  if (markerEnd < 0) throw new Error(`INTRODUCTION_GUIDANCE comment is not closed: ${file}`);

  const rows = sections.map((section) => {
    const escaped = section.replaceAll('|', '\\|');
    return `| ${escaped} | ${escaped}に関する設計内容 | 記載内容を確認し、認識相違や不足があれば指摘してください。 |`;
  });
  const table = `\n\n${HEADER}\n|---|---|---|\n${rows.join('\n')}`;
  const output = `${source.slice(0, markerEnd + 3)}${table}${source.slice(markerEnd + 3)}`;
  const temporary = `${file}.introduction-guidance.${process.pid}`;
  fs.writeFileSync(temporary, output);
  fs.renameSync(temporary, file);
  return true;
}

function run(root) {
  if (!fs.statSync(root).isDirectory()) throw new Error(`directory is required: ${root}`);
  let changed = 0;
  for (const file of markdownFiles(root)) {
    if (materialize(file)) changed += 1;
  }
  return changed;
}

function selfTest() {
  const root = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'introduction-guidance.'));
  try {
    const numbered = path.join(root, '番号付き設計書.md');
    const unnumbered = path.join(root, '番号なし設計書.md');
    fs.writeFileSync(numbered, '# 合成設計書\n\n<!-- INTRODUCTION_GUIDANCE: 規則 -->\n\n## §1 概要\n\n本文\n\n## 付録\n');
    fs.writeFileSync(unnumbered, '# 合成設計書\n\n<!-- INTRODUCTION_GUIDANCE: 規則 -->\n\n## 概要\n\n本文\n\n## 契約\n');
    const first = run(root);
    const numberedOnce = fs.readFileSync(numbered, 'utf8');
    const unnumberedOnce = fs.readFileSync(unnumbered, 'utf8');
    const second = run(root);
    const count = (source, pattern) => source.split('\n').filter((line) => pattern.test(line)).length;
    const numberedHeaders = count(numberedOnce, /^\| 節 \| 内容 \| 読み手へのお願い \|$/);
    const unnumberedHeaders = count(unnumberedOnce, /^\| 節 \| 内容 \| 読み手へのお願い \|$/);
    const numberedRows = count(numberedOnce, /^\| (?!節 |---)[^|]+ \|[^|]+\|[^|]+\|$/);
    const unnumberedRows = count(unnumberedOnce, /^\| (?!節 |---)[^|]+ \|[^|]+\|[^|]+\|$/);
    if (first !== 2 || second !== 0 || numberedHeaders !== 1 || unnumberedHeaders !== 1 || numberedRows !== 1 || unnumberedRows !== 2) {
      throw new Error(`expected changes=2,0 headers=1,1 rows=1,2; actual ${first},${second},${numberedHeaders},${unnumberedHeaders},${numberedRows},${unnumberedRows}`);
    }
    process.stderr.write('self-test: 1 PASS, 0 FAIL\n');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

if (process.argv[2] === '--self-test') {
  selfTest();
} else {
  const root = process.argv[2];
  if (!root) throw new Error('usage: materialize-introduction-guidance.mjs <directory>');
  process.stderr.write(`冒頭案内を本文へ展開: ${run(root)}件\n`);
}
