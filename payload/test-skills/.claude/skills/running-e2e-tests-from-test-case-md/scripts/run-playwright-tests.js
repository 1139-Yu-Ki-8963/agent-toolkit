#!/usr/bin/env node
// 出力先のフォルダの Playwright でテストのファイルを流し、報告とトレースを e2e-results/<実行日時>/ に書き、テストごとの状態を標準出力に書く。
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function fail(message, code) {
  process.stderr.write('失敗: ' + message + '\n');
  process.exit(code);
}

const [projectDir, runName, ...testFiles] = process.argv.slice(2);
if (!projectDir || !runName || testFiles.length === 0) fail('引数が足りない(<出力先のフォルダ> <実行日時> <テストのファイルのパス>...)', 2);
const root = path.resolve(projectDir);
const cli = path.join(root, 'node_modules', '@playwright', 'test', 'cli.js');
if (!fs.existsSync(cli)) fail(cli + ' がない', 1);
const runDir = path.join(root, 'e2e-results', runName);
if (fs.existsSync(runDir)) fail(runDir + ' が既にある', 2);
fs.mkdirSync(runDir, { recursive: true });
const jsonFile = path.join(runDir, 'results.json');

const env = Object.assign({}, process.env, {
  PLAYWRIGHT_HTML_OUTPUT_DIR: path.join(runDir, 'report'),
  PLAYWRIGHT_HTML_OPEN: 'never',
  PLAYWRIGHT_JSON_OUTPUT_FILE: jsonFile,
});
const args = [cli, 'test', ...testFiles, '--trace=on', '--output=' + path.join(runDir, 'trace'), '--reporter=html,json'];
spawnSync(process.execPath, args, { cwd: root, env, stdio: ['ignore', 2, 2] });
if (!fs.existsSync(jsonFile)) fail(jsonFile + ' ができない', 1);

const report = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
const lines = [];
function walk(suite) {
  for (const spec of suite.specs || []) {
    for (const test of spec.tests || []) {
      lines.push([spec.file, test.projectName, test.status, spec.title].join('\t'));
    }
  }
  for (const child of suite.suites || []) walk(child);
}
for (const suite of report.suites || []) walk(suite);
process.stdout.write(lines.join('\n') + (lines.length ? '\n' : ''));
const allPassed = lines.every((line) => ['expected', 'flaky'].includes(line.split('\t')[2]));
process.exit(allPassed ? 0 : 1);
