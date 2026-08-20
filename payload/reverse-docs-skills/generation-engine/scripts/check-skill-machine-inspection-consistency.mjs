#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DECLARATION_RE = /次の\s*(\d+)\s*つを実行する/;
const DEFINITION_RE = /^-\s+(?:\*\*)?(?:検査(\d+)\s+)?([^:\n*]+?)(?:\*\*)?:/gm;
const COUNT_REFERENCE_RES = [/(\d+)\s*検査/g, /(\d+)\s*つの機械検査/g];
const NUMBER_REFERENCE_RE = /検査(\d+)/g;
const BUSINESS_VOCABULARY_REFERENCE_RE = /業務語彙の検査(?:(?!\n\s*\n)[\s\S])*?検査(\d+)/g;

function lineNumber(text, offset) {
  return text.slice(0, offset).split('\n').length;
}

function machineInspectionSection(text) {
  const step = text.match(/^## Step \d+-\d+: 機械検査\s*$/m);
  if (!step) return null;
  const start = step.index;
  const rest = text.slice(start + step[0].length);
  const nextHeading = rest.search(/^## /m);
  const end = nextHeading < 0 ? text.length : start + step[0].length + nextHeading;
  return { start, text: text.slice(start, end) };
}

export function inspectSkill(file) {
  const text = fs.readFileSync(file, 'utf8');
  const section = machineInspectionSection(text);
  if (!section) return { skipped: true, failures: [] };

  const declaration = section.text.match(DECLARATION_RE);
  if (!declaration) {
    return {
      skipped: false,
      declared: null,
      definitions: 0,
      failures: ['機械検査Stepに「次の N つを実行する」の件数宣言がない'],
    };
  }

  const declared = Number(declaration[1]);
  const definitions = [...section.text.matchAll(DEFINITION_RE)];
  const failures = [];

  if (definitions.length !== declared) {
    failures.push(`宣言 ${declared} 件に対して検査定義が ${definitions.length} 件`);
  }

  const actualNumbers = definitions.map((match) => match[1] ? Number(match[1]) : null);
  const expectedNumbers = Array.from({ length: declared }, (_, index) => index + 1);
  if (actualNumbers.some((number) => number === null)) {
    const missing = definitions
      .filter((match) => !match[1])
      .map((match) => `${lineNumber(text, section.start + match.index)}行目「${match[2]}」`);
    failures.push(`番号のない検査定義: ${missing.join('、')}`);
  }
  if (actualNumbers.length === declared && actualNumbers.some((number, index) => number !== expectedNumbers[index])) {
    failures.push(`検査番号が連番 1-${declared} ではない（実測: ${actualNumbers.join(',')}）`);
  }

  for (const countRe of COUNT_REFERENCE_RES) {
    for (const match of text.matchAll(new RegExp(countRe.source, 'g'))) {
      const count = Number(match[1]);
      if (count !== declared) {
        failures.push(`${lineNumber(text, match.index)}行目の件数 ${count} が宣言 ${declared} と不一致`);
      }
    }
  }

  const definedNumbers = new Set(actualNumbers.filter((number) => number !== null));
  for (const match of text.matchAll(NUMBER_REFERENCE_RE)) {
    const number = Number(match[1]);
    if (!definedNumbers.has(number)) {
      failures.push(`${lineNumber(text, match.index)}行目の検査${number}に対応する定義がない`);
    }
  }

  const definitionNames = new Map(
    definitions
      .filter((match) => match[1])
      .map((match) => [Number(match[1]), match[2].trim()]),
  );
  for (const match of text.matchAll(BUSINESS_VOCABULARY_REFERENCE_RE)) {
    const number = Number(match[1]);
    if (!definitionNames.get(number)?.includes('業務語彙の検査')) {
      failures.push(`${lineNumber(text, match.index)}行目の業務語彙の検査は検査${number}を参照しているが、同番号の定義名と一致しない`);
    }
  }

  return { skipped: false, declared, definitions: definitions.length, failures };
}

function collectTargets(root) {
  const skillsRoot = path.join(root, '.claude', 'skills');
  if (!fs.existsSync(skillsRoot)) throw new Error(`生成スキル配置が見つかりません: ${skillsRoot}`);
  return fs.readdirSync(skillsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith('generating-'))
    .map((entry) => path.join(skillsRoot, entry.name, 'SKILL.md'))
    .filter((file) => fs.existsSync(file))
    .sort();
}

function run(files) {
  let checked = 0;
  let failed = 0;
  for (const file of files) {
    const result = inspectSkill(file);
    if (result.skipped) continue;
    checked += 1;
    if (result.failures.length === 0) {
      console.log(`[PASS] ${file}: ${result.declared}件・連番1-${result.declared}・参照先実在・業務語彙参照一致`);
      continue;
    }
    failed += 1;
    console.error(`[FAIL] ${file}`);
    for (const failure of result.failures) console.error(`  - ${failure}`);
  }
  console.log(`生成スキル機械検査整合: 対象${checked}件 / 不合格${failed}件`);
  return failed === 0 ? 0 : 1;
}

function fixture(count, definitions, tail = '') {
  return [
    '# fixture', '', '## Step 5-1: 機械検査', '', `次の ${count} つを実行する。`, '',
    ...definitions, '', `**完了**: ${count} 検査すべてが合格している`, tail, '', '## 返却',
  ].join('\n');
}

function selfTest() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'skill-machine-inspection-'));
  try {
    const cases = [
      ['正常な2検査を合格にする', fixture(2, ['- **検査1 一致検査**: A', '- **検査2 配置の検査**: B']), true],
      ['宣言件数と定義数の食い違いを不合格にする', fixture(3, ['- **検査1 一致検査**: A', '- **検査2 配置の検査**: B']), false],
      ['番号のない検査を不合格にする', fixture(2, ['- **検査1 一致検査**: A', '- **配置の検査**: B']), false],
      ['存在しない検査番号の参照を不合格にする', fixture(2, ['- **検査1 一致検査**: A', '- **検査2 配置の検査**: B'], '検査3へ戻る。'), false],
      ['件数参照の食い違いを不合格にする', fixture(2, ['- **検査1 一致検査**: A', '- **検査2 配置の検査**: B'], '反復条件: 3 検査が揃うまで繰り返す。'), false],
      ['業務語彙の検査の意味上の誤参照を不合格にする', fixture(2, ['- **検査1 業務語彙の検査**: A', '- **検査2 配置の検査**: B'], '業務語彙の検査で不合格なら検査2へ戻る。'), false],
      ['機械検査Stepの件数宣言欠落を不合格にする', fixture(2, ['- **検査1 一致検査**: A', '- **検査2 配置の検査**: B']).replace('次の 2 つを実行する。', '以下を実行する。'), false],
      ['インデントした補足箇条書きを検査定義に数えない', fixture(2, ['- **検査1 一致検査**: A\n  - 補足: C', '- **検査2 配置の検査**: B']), true],
      ['段落内改行後の業務語彙の誤参照を不合格にする', fixture(2, ['- **検査1 業務語彙の検査**: A', '- **検査2 配置の検査**: B'], '業務語彙の検査で不合格なら、\n検査2へ戻る。'), false],
    ];
    let failed = 0;
    for (const [index, [name, content, expected]] of cases.entries()) {
      const file = path.join(temp, `case-${index + 1}.md`);
      fs.writeFileSync(file, content);
      const passed = inspectSkill(file).failures.length === 0;
      if (passed === expected) console.log(`[PASS] ${name}`);
      else { console.error(`[FAIL] ${name}`); failed += 1; }
    }
    console.log(`self-test: ${cases.length - failed}/${cases.length} PASS`);
    return failed === 0 ? 0 : 1;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

const args = process.argv.slice(2);
if (args.includes('--self-test')) process.exitCode = selfTest();
else process.exitCode = run(args.length > 0 ? args.map((file) => path.resolve(file)) : collectTargets(process.cwd()));
