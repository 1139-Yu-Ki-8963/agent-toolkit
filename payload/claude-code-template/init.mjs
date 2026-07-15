#!/usr/bin/env node

// claude-code-template 導入・更新スクリプト（init.mjs）
// 使い方:
//   導入: node init.mjs <導入先ディレクトリ>
//   更新: node init.mjs --update <導入先ディレクトリ>
// 設計: 冪等・非破壊。既存ファイルは上書きしない。

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync, copyFileSync } from 'node:fs';
import { join, relative, resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_ROOT = __dirname;

// コピー対象ルート
const INSTALL_ROOTS = ['CLAUDE.md', 'CLAUDE.local.md.example', '.gitattributes', '.claude'];

// 除外（コピーしない）
const SKIP = new Set(['init.mjs', 'CHANGELOG.md', 'README.md', '.git', '.github', '.gitignore']);

// 走査中除外（正規表現）
const SKIP_WITHIN = [
  /\.claude\/hooks\/logs\//,
  /settings\.json\.bak$/,
  /settings\.local\.json$/,
];

// テンプレ管理層（--update で上書き対象）
const MANAGED_PREFIXES = [
  '.claude/hooks/',
  '.claude/skills/adapt/',
  '.claude/skills/safe-commit/',
  '.claude/README.md',
  '.claude/TEMPLATE_VERSION',
];

function isManaged(relPath) {
  const normalized = relPath.replace(/\\/g, '/');
  return MANAGED_PREFIXES.some(prefix => normalized === prefix || normalized.startsWith(prefix));
}

function shouldSkipWithin(relPath) {
  const normalized = relPath.replace(/\\/g, '/');
  return SKIP_WITHIN.some(re => re.test(normalized));
}

function collectFiles(dir, baseDir, files = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return files; }
  for (const entry of entries) {
    if (SKIP.has(entry.name) && dir === TEMPLATE_ROOT) continue;
    const fullPath = join(dir, entry.name);
    const relPath = relative(baseDir, fullPath);
    if (shouldSkipWithin(relPath)) continue;
    if (entry.isDirectory()) {
      collectFiles(fullPath, baseDir, files);
    } else if (entry.isFile()) {
      files.push({ fullPath, relPath });
    }
  }
  return files;
}

function filesEqual(pathA, pathB) {
  try {
    const a = readFileSync(pathA);
    const b = readFileSync(pathB);
    return a.equals(b);
  } catch { return false; }
}

function appendGitignore(targetDir) {
  const templateGitignore = join(TEMPLATE_ROOT, '.gitignore');
  const targetGitignore = join(targetDir, '.gitignore');

  if (!existsSync(templateGitignore)) return { action: 'skip' };

  const MARKER = '# --- claude-code-template ---';

  // 既存の .gitignore を読む（なければ空文字）
  let existing = '';
  try { existing = readFileSync(targetGitignore, 'utf8'); } catch { /* なし */ }

  // マーカーブロックが既にあればスキップ（冪等）
  if (existing.includes(MARKER)) return { action: 'unchanged' };

  // テンプレの .gitignore からコメント行・空行を除いた行を取得
  const templateLines = readFileSync(templateGitignore, 'utf8')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));

  // 導入先に無い行だけを収集
  const existingLines = new Set(existing.split('\n').map(l => l.trim()));
  const newLines = templateLines.filter(l => !existingLines.has(l));

  if (newLines.length === 0) return { action: 'unchanged' };

  // マーカーブロックとして末尾に追記
  const block = `\n${MARKER}\n${newLines.join('\n')}\n`;
  writeFileSync(targetGitignore, existing.trimEnd() + block + '\n');
  return { action: 'appended', lines: newLines.length };
}

function printUsage() {
  console.log(`使い方:
  導入: node init.mjs <導入先ディレクトリ>
  更新: node init.mjs --update <導入先ディレクトリ>

導入:
  テンプレートのファイルを導入先にコピーする（冪等・非破壊）。
  既存ファイルは上書きしない。内容が異なる場合は .template-new を並置する。

更新:
  テンプレ管理層（hooks・skills/adapt・skills/safe-commit・README.md・TEMPLATE_VERSION）
  だけを上書きコピーする。プロジェクト所有層には触れない。`);
}

// --- メイン処理 ---

const args = process.argv.slice(2);
const isUpdate = args.includes('--update');
const targetArg = args.filter(a => a !== '--update')[0];

if (!targetArg) {
  printUsage();
  process.exit(1);
}

const targetDir = resolve(targetArg);

// 導入先が存在しない
if (!existsSync(targetDir)) {
  console.error(`エラー: 導入先ディレクトリが存在しません: ${targetDir}`);
  process.exit(1);
}

// 自己保護: テンプレリポジトリ自身への導入を拒否
if (resolve(TEMPLATE_ROOT) === resolve(targetDir)) {
  console.error('エラー: テンプレートリポジトリ自身に導入することはできません');
  process.exit(1);
}

const stats = { created: 0, overwritten: 0, unchanged: 0, conflict: 0 };
const conflicts = [];

// ファイルを収集（INSTALL_ROOTS 内のみ）
const files = [];
for (const root of INSTALL_ROOTS) {
  const rootPath = join(TEMPLATE_ROOT, root);
  if (!existsSync(rootPath)) continue;
  const rootStat = statSync(rootPath);
  if (rootStat.isDirectory()) {
    collectFiles(rootPath, TEMPLATE_ROOT, files);
  } else {
    files.push({ fullPath: rootPath, relPath: root });
  }
}

for (const { fullPath, relPath } of files) {
  const destPath = join(targetDir, relPath);

  // --update モードではテンプレ管理層のみ処理
  if (isUpdate && !isManaged(relPath)) continue;

  // ディレクトリを確保
  mkdirSync(dirname(destPath), { recursive: true });

  if (!existsSync(destPath)) {
    // 新規作成
    copyFileSync(fullPath, destPath);
    stats.created++;
  } else if (isUpdate && isManaged(relPath)) {
    // 更新モード: 管理層は上書き
    if (filesEqual(fullPath, destPath)) {
      stats.unchanged++;
    } else {
      copyFileSync(fullPath, destPath);
      stats.overwritten++;
    }
  } else if (filesEqual(fullPath, destPath)) {
    // 同一内容: unchanged
    stats.unchanged++;
  } else {
    // 内容が異なる: .template-new を並置
    const conflictPath = destPath + '.template-new';
    copyFileSync(fullPath, conflictPath);
    stats.conflict++;
    conflicts.push(relPath);
  }
}

// .gitignore の処理（導入モードのみ）
if (!isUpdate) {
  const gitignoreResult = appendGitignore(targetDir);
  if (gitignoreResult.action === 'appended') {
    console.log(`.gitignore: ${gitignoreResult.lines} 行追記`);
  }
}

// サマリ出力
console.log(`\n作成 ${stats.created} / 上書き ${stats.overwritten} / 変更なし ${stats.unchanged} / 競合 ${stats.conflict}`);

if (conflicts.length > 0) {
  console.log('\n競合ファイル（.template-new を確認してください）:');
  for (const c of conflicts) {
    console.log(`  ${c}`);
  }
}

// 導入時のみ「次のステップ」を表示
if (!isUpdate && stats.created > 0) {
  console.log(`\n次のステップ:
  1. 導入されたファイルを commit する
  2. /adapt を実行してプロジェクトに適応させる
  3. 各メンバーは settings.local.json.example をコピーする`);
}
