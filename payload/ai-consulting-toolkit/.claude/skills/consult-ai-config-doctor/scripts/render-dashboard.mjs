#!/usr/bin/env node
// render-dashboard.mjs
//
// aggregate-findings.mjs の出力 JSON を assets/dashboard-template.html に差し込み、
// 自己完結（外部リソース読み込みなし）の診断ダッシュボード HTML を書き出す。
// Node.js 標準ライブラリのみで動作する（npm 依存なし）。
//
// Usage:
//   node render-dashboard.mjs <集計json> <出力html>

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PLACEHOLDER = '/*__DIAGNOSIS_DATA__*/';

function toNumber(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

// aggregate-findings.mjs の出力が壊れている状態で渡された場合でも
// レンダリングを落とさないよう最低限の形を保証する。
function normalizeAggregatedData(raw) {
  const data = raw && typeof raw === 'object' ? raw : {};
  const meta = data.meta && typeof data.meta === 'object' ? data.meta : {};
  const domains = Array.isArray(data.domains) ? data.domains : [];
  const overall = data.overall && typeof data.overall === 'object' ? data.overall : {};
  const prescriptions = Array.isArray(data.prescriptions) ? data.prescriptions : [];
  const diff = data.diff && typeof data.diff === 'object' ? data.diff : null;

  const GRADE_LETTERS = new Set(['S', 'A', 'B', 'C', 'D']);
  const GRADE_VALUE = { S: 5, A: 4, B: 3, C: 2, D: 1 };

  const normalizedDomains = domains.map((d) => {
    const grade = GRADE_LETTERS.has(d.grade) ? d.grade : 'D';
    return {
      id: typeof d.id === 'string' ? d.id : 'unknown',
      label: typeof d.label === 'string' ? d.label : String(d.id || 'unknown'),
      grade,
      stars: toNumber(d.stars, GRADE_VALUE[grade]),
      critical: toNumber(d.critical, 0),
      warn: toNumber(d.warn, 0),
      info: toNumber(d.info, 0),
      top_finding: typeof d.top_finding === 'string' ? d.top_finding : '',
      findings: Array.isArray(d.findings) ? d.findings : [],
    };
  });

  const overallGrade = GRADE_LETTERS.has(overall.grade) ? overall.grade : 'D';
  const normalizedOverall = {
    grade: overallGrade,
    stars: toNumber(overall.stars, GRADE_VALUE[overallGrade]),
    ai_level: toNumber(overall.ai_level, GRADE_VALUE[overallGrade]),
    ai_level_label: typeof overall.ai_level_label === 'string' ? overall.ai_level_label : '',
  };

  const normalizedPrescriptions = prescriptions.map((p) => ({
    key: typeof p.key === 'string' ? p.key : '',
    domain: typeof p.domain === 'string' ? p.domain : '',
    risk: ['safe', 'careful', 'surgery'].includes(p.risk) ? p.risk : 'careful',
    time_min: toNumber(p.time_min, 15),
    expected: typeof p.expected === 'string' ? p.expected : '',
    prompt: typeof p.prompt === 'string' ? p.prompt : '',
  }));

  return {
    meta: {
      project: typeof meta.project === 'string' ? meta.project : '',
      date: typeof meta.date === 'string' ? meta.date : '',
      target_root: typeof meta.target_root === 'string' ? meta.target_root : '',
    },
    domains: normalizedDomains,
    overall: normalizedOverall,
    prescriptions: normalizedPrescriptions,
    diff,
  };
}

function main() {
  const [, , inputPath, outputPath] = process.argv;
  if (!inputPath || !outputPath) {
    console.error('Usage: render-dashboard.mjs <集計json> <出力html>');
    process.exit(1);
  }

  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  } catch (err) {
    console.error(`集計jsonの読み込みに失敗しました: ${inputPath} (${err.message})`);
    process.exit(1);
  }

  const data = normalizeAggregatedData(raw);

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const templatePath = path.join(scriptDir, '..', 'assets', 'dashboard-template.html');
  let template;
  try {
    template = fs.readFileSync(templatePath, 'utf8');
  } catch (err) {
    console.error(`テンプレートを読み込めません: ${templatePath} (${err.message})`);
    process.exit(1);
  }

  if (!template.includes(PLACEHOLDER)) {
    console.error(`テンプレートにプレースホルダ ${PLACEHOLDER} が見つかりません: ${templatePath}`);
    process.exit(1);
  }

  // JSON 文字列内に "</script" 等が含まれていても script タグが途中で
  // 閉じられないよう "<" を unicode エスケープする。
  const jsonLiteral = JSON.stringify(data).replace(/</g, '\\u003c');
  const injection = `window.__DIAGNOSIS_DATA__ = ${jsonLiteral};`;
  const html = template.replace(PLACEHOLDER, injection);

  const resolvedOutput = path.resolve(outputPath);
  fs.mkdirSync(path.dirname(resolvedOutput), { recursive: true });
  fs.writeFileSync(resolvedOutput, html, 'utf8');
  console.log(`ダッシュボードを書き出しました: ${resolvedOutput}`);
}

main();
