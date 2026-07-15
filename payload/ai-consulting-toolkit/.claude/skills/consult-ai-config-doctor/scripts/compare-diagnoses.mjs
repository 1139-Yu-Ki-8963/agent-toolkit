#!/usr/bin/env node
// compare-diagnoses.mjs
//
// 2 つの集計 JSON（aggregate-findings.mjs の出力）を比較し、ドメイン別・総合の
// グレード変化を Markdown 表で stdout に出力する。ファイル書き出しは行わない。
// Node.js 標準ライブラリのみで動作する（npm 依存なし）。
//
// Usage:
//   node compare-diagnoses.mjs <前回json> <今回json>
//
// 前回・今回いずれの JSON も崩れている可能性を考慮し、必要なキーが欠けていても
// 「不明」として扱い、比較処理自体は落ちないようにする。

import fs from 'node:fs';

const GRADE_VALUE = { S: 5, A: 4, B: 3, C: 2, D: 1 };

function readJson(filePath, label) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    console.error(`${label} を読めません: ${filePath} (${err.message})`);
    process.exit(1);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error(`${label} の JSON 解析に失敗しました: ${filePath} (${err.message})`);
    process.exit(1);
  }
}

function normalizeGrade(value) {
  return typeof value === 'string' && GRADE_VALUE[value] !== undefined ? value : null;
}

function changeLabel(fromGrade, toGrade) {
  if (fromGrade === null || toGrade === null) return '不明';
  if (fromGrade === toGrade) return '変化なし';
  const delta = GRADE_VALUE[toGrade] - GRADE_VALUE[fromGrade];
  return delta > 0 ? `改善 (${fromGrade}→${toGrade})` : `悪化 (${fromGrade}→${toGrade})`;
}

function main() {
  const [, , prevPath, currentPath] = process.argv;
  if (!prevPath || !currentPath) {
    console.error('Usage: compare-diagnoses.mjs <前回json> <今回json>');
    process.exit(1);
  }

  const prevData = readJson(prevPath, '前回json');
  const currentData = readJson(currentPath, '今回json');

  const prevDomains = Array.isArray(prevData.domains) ? prevData.domains : [];
  const currentDomains = Array.isArray(currentData.domains) ? currentData.domains : [];

  const prevMap = new Map(prevDomains.map((d) => [d.id, d]));
  const currentMap = new Map(currentDomains.map((d) => [d.id, d]));

  const allIds = Array.from(new Set([...prevMap.keys(), ...currentMap.keys()]));

  const lines = [];
  lines.push('# 診断比較レポート');
  lines.push('');
  lines.push(`前回: ${prevData.meta && prevData.meta.date ? prevData.meta.date : '不明'}`);
  lines.push(`今回: ${currentData.meta && currentData.meta.date ? currentData.meta.date : '不明'}`);
  lines.push('');
  lines.push('## ドメイン別グレード変化');
  lines.push('');
  lines.push('| ドメイン | 前回グレード | 今回グレード | 変化 |');
  lines.push('|---|---|---|---|');

  for (const id of allIds) {
    const prevDomain = prevMap.get(id);
    const currentDomain = currentMap.get(id);
    const label = (currentDomain && currentDomain.label) || (prevDomain && prevDomain.label) || id;
    const fromGrade = prevDomain ? normalizeGrade(prevDomain.grade) : null;
    const toGrade = currentDomain ? normalizeGrade(currentDomain.grade) : null;
    const fromCell = fromGrade ?? (prevDomain ? '不明' : '(前回未診断)');
    const toCell = toGrade ?? (currentDomain ? '不明' : '(今回未診断)');
    const change =
      !prevDomain && currentDomain
        ? '新規ドメイン'
        : prevDomain && !currentDomain
          ? '診断対象から除外'
          : changeLabel(fromGrade, toGrade);
    lines.push(`| ${label} | ${fromCell} | ${toCell} | ${change} |`);
  }

  lines.push('');
  lines.push('## 総合グレード変化');
  lines.push('');
  lines.push('| 前回 | 今回 | 変化 |');
  lines.push('|---|---|---|');

  const prevOverall = normalizeGrade(prevData.overall && prevData.overall.grade);
  const currentOverall = normalizeGrade(currentData.overall && currentData.overall.grade);
  lines.push(
    `| ${prevOverall ?? '不明'} | ${currentOverall ?? '不明'} | ${changeLabel(prevOverall, currentOverall)} |`
  );

  console.log(lines.join('\n'));
}

main();
