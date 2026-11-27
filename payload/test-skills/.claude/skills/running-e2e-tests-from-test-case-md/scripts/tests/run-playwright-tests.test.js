#!/usr/bin/env node
// run-playwright-tests.js を、偽の Playwright の cli.js を置いた一時フォルダで流し、終了コードと標準出力を確かめる。
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const script = path.join(__dirname, '..', 'run-playwright-tests.js');
const base = fs.mkdtempSync(path.join(process.env.TMPDIR || '/tmp', 'run-playwright-tests-'));
let failed = 0;

function check(name, ok) {
  process.stdout.write((ok ? '成功: ' : '失敗: ') + name + '\n');
  if (!ok) failed += 1;
}

function run(args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
}

function makeProject(name, statuses) {
  const dir = path.join(base, name);
  const cliDir = path.join(dir, 'node_modules', '@playwright', 'test');
  fs.mkdirSync(cliDir, { recursive: true });
  const specs = statuses.map((status, i) => ({ title: 'TC-00' + (i + 1) + ' 送る', file: 'テストケース-総合/TC-00' + (i + 1) + '.spec.ts', tests: [{ projectName: 'chromium', status }] }));
  const fake = [
    "const fs = require('fs');",
    "const path = require('path');",
    'const out = process.env.PLAYWRIGHT_JSON_OUTPUT_FILE;',
    'fs.mkdirSync(path.dirname(out), { recursive: true });',
    "fs.mkdirSync(process.env.PLAYWRIGHT_HTML_OUTPUT_DIR, { recursive: true });",
    "fs.writeFileSync(path.join(path.dirname(out), 'args.json'), JSON.stringify({ args: process.argv.slice(2), html: process.env.PLAYWRIGHT_HTML_OUTPUT_DIR }));",
    'fs.writeFileSync(out, ' + JSON.stringify(JSON.stringify({ suites: [{ specs: [], suites: [{ specs }] }] })) + ');',
  ].join('\n');
  fs.writeFileSync(path.join(cliDir, 'cli.js'), fake);
  return dir;
}

try {
  const noArgs = run([]);
  check('引数がないときは終了コードが 2', noArgs.status === 2 && noArgs.stderr.includes('失敗:'));

  const noCli = path.join(base, 'no-cli');
  fs.mkdirSync(noCli);
  const noCliRun = run([noCli, '2026-11-27-1700', 'tests/a.spec.ts']);
  check('cli.js がないときは終了コードが 1 で、標準エラーに「失敗:」の行がある', noCliRun.status === 1 && noCliRun.stderr.includes('失敗:'));

  const noJson = path.join(base, 'no-json');
  fs.mkdirSync(path.join(noJson, 'node_modules', '@playwright', 'test'), { recursive: true });
  fs.writeFileSync(path.join(noJson, 'node_modules', '@playwright', 'test', 'cli.js'), '');
  const noJsonRun = run([noJson, '2026-11-27-1700', 'tests/a.spec.ts']);
  check('results.json ができないときは終了コードが 1 で、標準エラーに「失敗:」の行がある', noJsonRun.status === 1 && noJsonRun.stderr.includes('失敗:'));

  const mixed = makeProject('mixed', ['expected', 'unexpected']);
  const mixedRun = run([mixed, '2026-11-27-1700', 'tests/a.spec.ts', 'tests/b.spec.ts']);
  const lines = mixedRun.stdout.trim().split('\n');
  check('失敗を含むときは終了コードが 1 で、標準エラーに「失敗:」の行がない', mixedRun.status === 1 && !mixedRun.stderr.includes('失敗:'));
  check('テストごとに 1 行を書く', lines.length === 2 && lines[1] === 'テストケース-総合/TC-002.spec.ts\tchromium\tunexpected\tTC-002 送る');
  check('results.json と report/ が実行日時のフォルダにある', fs.existsSync(path.join(mixed, 'e2e-results', '2026-11-27-1700', 'results.json')) && fs.existsSync(path.join(mixed, 'e2e-results', '2026-11-27-1700', 'report')));
  const runDir = path.join(mixed, 'e2e-results', '2026-11-27-1700');
  const recorded = JSON.parse(fs.readFileSync(path.join(runDir, 'args.json'), 'utf8'));
  check('--output と報告の出力先が e2e-results/<実行日時>/ の下を指す', recorded.args.includes('--output=' + path.join(runDir, 'trace')) && recorded.html === path.join(runDir, 'report'));
  check('実行日時のフォルダが既にあるときは終了コードが 2', run([mixed, '2026-11-27-1700', 'tests/a.spec.ts']).status === 2);

  const passed = makeProject('passed', ['expected', 'flaky']);
  check('すべて expected か flaky のときは終了コードが 0', run([passed, '2026-11-27-1701', 'tests/a.spec.ts']).status === 0);
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}

process.exit(failed === 0 ? 0 : 1);
