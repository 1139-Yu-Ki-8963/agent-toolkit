#!/usr/bin/env node

// 非画面の設計単位を単独配布可能な形へ整形・検査する。
// Usage:
//   node generation-engine/scripts/prepare-standalone-units.mjs --prepare <docs-root>
//   node generation-engine/scripts/prepare-standalone-units.mjs --verify <docs-root>
//   node generation-engine/scripts/prepare-standalone-units.mjs --self-test

import childProcess from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const repoRoot = path.resolve(scriptDir, '../..');
const layoutPath = path.join(repoRoot, 'delivery-payload/references/output-layout.json');
const unitLayoutPath = path.join(repoRoot, 'delivery-payload/references/design-unit-layout.json');
const kinds = ['api', 'table', 'batch', 'report', 'external', 'feature'];
const rootKeys = {
  api: 'apiUnitRoot', table: 'tableUnitRoot', batch: 'batchUnitRoot',
  report: 'reportUnitRoot', external: 'externalUnitRoot', feature: 'featureUnitRoot'
};
const oldPortalFallback = "var portalHref = side.getAttribute('data-portal-href') || 'index.html';";
const standalonePortalGuard = "var portalHref = side.getAttribute('data-portal-href');\n  if (!portalHref) return;";

function usage() {
  process.stderr.write(`Usage: ${scriptPath} --prepare <docs-root> | --verify <docs-root> | --self-test\n`);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    throw new Error(`JSONを読めません: ${file}: ${error.message}`);
  }
}

function inside(root, target) {
  const relative = path.relative(root, target);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function assertNotSymlink(target, label) {
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink()) throw new Error(`${label}にシンボリックリンクは使えません: ${target}`);
  return stat;
}

function assertNoSymlinkComponents(boundary, target, label) {
  const relative = path.relative(boundary, target);
  if (!inside(boundary, target)) throw new Error(`${label}が境界外です: ${target}`);
  let current = boundary;
  assertNotSymlink(current, label);
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    assertNotSymlink(current, label);
  }
}

function assertExistingInside(boundary, target, label, type) {
  assertNoSymlinkComponents(boundary, target, label);
  const realBoundary = fs.realpathSync(boundary);
  const realTarget = fs.realpathSync(target);
  if (!inside(realBoundary, realTarget)) throw new Error(`${label}の実体が境界外です: ${target}`);
  const stat = fs.statSync(target);
  if (type === 'directory' && !stat.isDirectory()) throw new Error(`${label}がディレクトリではありません: ${target}`);
  if (type === 'file' && !stat.isFile()) throw new Error(`${label}がファイルではありません: ${target}`);
}

function resolveInside(root, relative, label) {
  if (typeof relative !== 'string' || !relative) throw new Error(`${label}は空でないパスで指定してください`);
  const resolved = path.resolve(root, relative);
  if (!inside(root, resolved)) throw new Error(`${label}がdocs rootの外へ出ています: ${relative}`);
  return resolved;
}

function effectiveLayout(root) {
  const base = readJson(layoutPath);
  const overridePath = path.join(root, 'output-layout.json');
  if (fs.existsSync(overridePath)) assertExistingInside(root, overridePath, 'output-layout.json', 'file');
  const override = fs.existsSync(overridePath) ? readJson(overridePath) : {};
  return Object.assign({}, base.layout || {}, override.layout || {});
}

function requiredFiles(kind, unitLayout) {
  const definition = unitLayout.kinds?.[kind];
  if (!definition?.phases) throw new Error(`design-unit-layoutに${kind}のphasesがありません`);
  return Object.values(definition.phases).flat().filter((file) => typeof file === 'string' && file.endsWith('.md'));
}

function collectFiles(root, errors) {
  const files = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const target = path.join(root, entry.name);
    if (entry.isSymbolicLink()) {
      errors.push(`${target}: 設計単位内にシンボリックリンクがあります`);
    } else if (entry.isDirectory()) {
      files.push(...collectFiles(target, errors));
    } else if (entry.isFile()) {
      files.push(target);
    }
  }
  return files;
}

function unitDirectories(root, layout, errors) {
  const units = [];
  for (const kind of kinds) {
    const unitRoot = resolveInside(root, layout[rootKeys[kind]], `${kind} unit root`);
    if (!fs.existsSync(unitRoot)) continue;
    try {
      assertExistingInside(root, unitRoot, `${kind} unit root`, 'directory');
    } catch (error) {
      errors.push(error.message);
      continue;
    }
    for (const entry of fs.readdirSync(unitRoot, { withFileTypes: true })) {
      const unit = path.join(unitRoot, entry.name);
      if (entry.isSymbolicLink()) {
        errors.push(`${unit}: 設計単位にシンボリックリンクは使えません`);
      } else if (entry.isDirectory()) {
        try {
          assertExistingInside(unitRoot, unit, `${kind}設計単位`, 'directory');
          units.push({ kind, path: unit });
        } catch (error) {
          errors.push(error.message);
        }
      }
    }
  }
  return units;
}

function stripTags(value) {
  return value.replace(/<[^>]*>/g, ' ').replace(/&(?:#\d+|#x[0-9a-f]+|[a-z]+);/gi, ' ').replace(/\s+/g, ' ').trim();
}

function isPortalReturn(text) {
  return /ポータル[\s\S]{0,30}戻|戻[\s\S]{0,30}ポータル/.test(text);
}

function scriptById(html, id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = html.match(new RegExp(`<script\\b(?=[^>]*\\bid=["']${escaped}["'])[^>]*>([\\s\\S]*?)<\\/script>`, 'i'));
  return match ? { whole: match[0], content: match[1] } : null;
}

function replaceScriptContent(html, id, replacement) {
  const found = scriptById(html, id);
  if (!found) return { html, count: 0 };
  return { html: html.replace(found.whole, found.whole.replace(found.content, replacement)), count: 1 };
}

function localHrefError(href, sourceFile, unitRoot, sourceLabel) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('#')) return null;
  if (href.startsWith('//')) return `${sourceFile}: ${sourceLabel}が外部のprotocol-relative URLです (${href})`;
  const localPath = href.split(/[?#]/, 1)[0];
  if (!localPath) return null;
  let decoded;
  try {
    decoded = decodeURI(localPath);
  } catch (_) {
    return `${sourceFile}: ${sourceLabel}のURLエンコードが不正です (${href})`;
  }
  const destination = path.resolve(path.dirname(sourceFile), decoded);
  if (!inside(unitRoot, destination)) return `${sourceFile}: ${sourceLabel}が設計単位の外へ出ています (${href})`;
  if (!fs.existsSync(destination)) return `${sourceFile}: ${sourceLabel}の参照先がありません (${href})`;
  try {
    assertExistingInside(unitRoot, destination, `${sourceLabel}の参照先`, undefined);
  } catch (error) {
    return `${sourceFile}: ${error.message}`;
  }
  return null;
}

function staticHrefs(html) {
  const withoutScripts = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '');
  const hrefs = [];
  const anchor = /<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = anchor.exec(withoutScripts)) !== null) hrefs.push({ href: match[1] ?? match[2] ?? match[3] ?? '', text: stripTags(match[4]) });
  return hrefs;
}

function maskMarkdownCode(markdown) {
  const characters = [...markdown];
  const mask = (start, end) => {
    for (let index = start; index < end; index += 1) if (characters[index] !== '\n' && characters[index] !== '\r') characters[index] = ' ';
  };
  let fence = null;
  let offset = 0;
  for (const line of markdown.match(/.*(?:\r?\n|$)/g) ?? []) {
    if (!line) continue;
    const content = line.replace(/\r?\n$/, '');
    if (fence) {
      mask(offset, offset + line.length);
      const closing = content.match(/^ {0,3}(`+|~+)[ \t]*$/);
      if (closing && closing[1][0] === fence.marker && closing[1].length >= fence.length) fence = null;
    } else {
      const opening = content.match(/^ {0,3}(`{3,}|~{3,})/);
      if (opening) {
        fence = { marker: opening[1][0], length: opening[1].length };
        mask(offset, offset + line.length);
      }
    }
    offset += line.length;
  }
  const withoutFences = characters.join('');
  for (let index = 0; index < withoutFences.length;) {
    if (withoutFences[index] !== '`') {
      index += 1;
      continue;
    }
    let openerEnd = index;
    while (withoutFences[openerEnd] === '`') openerEnd += 1;
    const width = openerEnd - index;
    let cursor = openerEnd;
    let closingEnd = -1;
    while (cursor < withoutFences.length) {
      if (withoutFences[cursor] !== '`') {
        cursor += 1;
        continue;
      }
      let runEnd = cursor;
      while (withoutFences[runEnd] === '`') runEnd += 1;
      if (runEnd - cursor === width) {
        closingEnd = runEnd;
        break;
      }
      cursor = runEnd;
    }
    if (closingEnd < 0) {
      index = openerEnd;
      continue;
    }
    mask(index, closingEnd);
    index = closingEnd;
  }
  return characters.join('');
}

function docMarkdownHrefs(html, file, errors) {
  const doc = scriptById(html, 'doc-md');
  if (!doc) return [];
  let markdown;
  try {
    markdown = JSON.parse(doc.content);
  } catch (error) {
    errors.push(`${file}: doc-mdをJSONとして読めません: ${error.message}`);
    return [];
  }
  if (typeof markdown !== 'string') {
    errors.push(`${file}: doc-mdはMarkdown文字列ではありません`);
    return [];
  }
  const searchable = maskMarkdownCode(markdown);
  const hrefs = [];
  const normalizeReference = (label) => label.trim().replace(/\s+/g, ' ').toLowerCase();
  const definitions = new Map();
  const definitionRanges = [];
  const definition = /^\s{0,3}\[([^\]]+)\]:\s*(\S+).*$/gm;
  let match;
  while ((match = definition.exec(searchable)) !== null) {
    let destination = match[2];
    if (destination.startsWith('<') && destination.endsWith('>')) destination = destination.slice(1, -1);
    definitions.set(normalizeReference(match[1]), destination);
    definitionRanges.push([match.index, match.index + match[0].length]);
  }
  let masked = searchable.split('').map((character, index) => definitionRanges.some(([start, end]) => index >= start && index < end) ? ' ' : character).join('');
  const markdownLink = /(^|[^!])\[([^\]]+)\]\(([^()\s]+)\)/gm;
  while ((match = markdownLink.exec(masked)) !== null) {
    hrefs.push(match[3]);
    const start = match.index + match[1].length;
    masked = `${masked.slice(0, start)}${' '.repeat(match[0].length - match[1].length)}${masked.slice(start + match[0].length - match[1].length)}`;
    markdownLink.lastIndex = start + match[0].length - match[1].length;
  }
  const referenceLink = /(^|[^!])\[([^\]]+)\]\[([^\]]*)\]/gm;
  while ((match = referenceLink.exec(masked)) !== null) {
    const label = match[3] || match[2];
    const destination = definitions.get(normalizeReference(label));
    if (destination) hrefs.push(destination);
    const start = match.index + match[1].length;
    masked = `${masked.slice(0, start)}${' '.repeat(match[0].length - match[1].length)}${masked.slice(start + match[0].length - match[1].length)}`;
    referenceLink.lastIndex = start + match[0].length - match[1].length;
  }
  const shortcutLink = /(^|[^!])\[([^\]\n]+)\](?![\[(])/gm;
  while ((match = shortcutLink.exec(masked)) !== null) {
    const destination = definitions.get(normalizeReference(match[2]));
    if (destination) hrefs.push(destination);
  }
  const rawAnchor = /<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>/gi;
  while ((match = rawAnchor.exec(searchable)) !== null) hrefs.push(match[1] ?? match[2] ?? match[3] ?? '');
  return hrefs;
}

function runtimeErrors(file, html) {
  const errors = [];
  const sidebar = /<aside\b[^>]*(?:class=["'][^"']*\bpt-sidebar\b|id=["']pt-sidebar-aside["'])[^>]*>/i.test(html);
  if (!sidebar) return errors;
  const attributes = [...html.matchAll(/\bdata-portal-href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi)];
  if (attributes.length === 0) errors.push(`${file}: pt-sidebarにdata-portal-hrefがありません`);
  for (const match of attributes) {
    const value = (match[1] ?? match[2] ?? match[3] ?? '').trim();
    if (value) errors.push(`${file}: data-portal-hrefが空ではありません (${value})`);
  }
  if (html.includes(oldPortalFallback)) errors.push(`${file}: sidebar navのindex.html fallbackが残っています`);
  if (!html.includes(standalonePortalGuard)) errors.push(`${file}: sidebar navのstandalone guardがありません`);
  const sites = scriptById(html, 'pt-sites-data');
  if (!sites) {
    errors.push(`${file}: pt-sites-dataがありません`);
  } else {
    try {
      const parsed = JSON.parse(sites.content);
      if (!Array.isArray(parsed) || parsed.length !== 0) errors.push(`${file}: pt-sites-dataが空配列ではありません`);
    } catch (error) {
      errors.push(`${file}: pt-sites-dataをJSONとして読めません: ${error.message}`);
    }
  }
  return errors;
}

function linkErrors(file, unitRoot) {
  const errors = [];
  const html = fs.readFileSync(file, 'utf8');
  for (const entry of staticHrefs(html)) {
    if (isPortalReturn(entry.text)) errors.push(`${file}: ポータルへ戻る静的リンクが残っています (${entry.href})`);
    const error = localHrefError(entry.href, file, unitRoot, '静的href');
    if (error) errors.push(error);
  }
  for (const href of docMarkdownHrefs(html, file, errors)) {
    const error = localHrefError(href, file, unitRoot, 'doc-md内リンク');
    if (error) errors.push(error);
  }
  errors.push(...runtimeErrors(file, html));
  return errors;
}

function structure(unit, unitLayout) {
  const errors = [];
  const allFiles = collectFiles(unit.path, errors);
  const htmlFiles = allFiles.filter((file) => file.endsWith('.html'));
  const targets = [];
  for (const name of requiredFiles(unit.kind, unitLayout)) {
    const matches = allFiles.filter((file) => path.basename(file) === name);
    if (matches.length !== 1) {
      errors.push(`${unit.kind}/${path.basename(unit.path)}: 必須Markdownの件数が1ではありません (${name}: ${matches.length}件)`);
      continue;
    }
    const markdown = matches[0];
    const html = markdown.replace(/\.md$/i, '.html');
    try {
      assertExistingInside(unit.path, markdown, '必須Markdown', 'file');
    } catch (error) {
      errors.push(error.message);
      continue;
    }
    if (!fs.existsSync(html)) {
      errors.push(`${unit.kind}/${path.basename(unit.path)}: 必須HTMLがありません (${path.relative(unit.path, html)})`);
      continue;
    }
    try {
      assertExistingInside(unit.path, html, '必須HTML', 'file');
      targets.push({ markdown, html });
    } catch (error) {
      errors.push(error.message);
    }
  }
  return { errors, targets, htmlFiles };
}

function isPortalIndexHref(file, unitRoot, portalRoot, href) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('#') || href.startsWith('//')) return false;
  const localPath = href.split(/[?#]/, 1)[0];
  if (!localPath) return false;
  const destination = path.resolve(path.dirname(file), localPath);
  return !inside(unitRoot, destination) && destination === path.join(portalRoot, 'index.html');
}

function replaceOutsideScripts(html, replacer) {
  return html.split(/(<script\b[^>]*>[\s\S]*?<\/script>)/gi).map((part) => /^<script\b/i.test(part) ? part : replacer(part)).join('');
}

function prepareHtml(file, unitRoot, portalRoot) {
  let html = fs.readFileSync(file, 'utf8');
  const sidebar = /<aside\b[^>]*(?:class=["'][^"']*\bpt-sidebar\b|id=["']pt-sidebar-aside["'])[^>]*>/i.test(html);
  if (!sidebar) return { html, errors: [] };
  const errors = [];
  html = replaceOutsideScripts(html, (staticHtml) => {
    let updated = staticHtml.replace(/(\bdata-portal-href\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '$1""');
    updated = updated.replace(/<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi, (whole, doubleQuoted, singleQuoted, bare, content) => {
      const href = doubleQuoted ?? singleQuoted ?? bare ?? '';
      return isPortalReturn(stripTags(content)) || isPortalIndexHref(file, unitRoot, portalRoot, href)
        ? `<span class="pt-standalone-portal-label">${content}</span>`
        : whole;
    });
    return updated;
  });
  const oldCount = html.split(oldPortalFallback).length - 1;
  const guardCount = html.split(standalonePortalGuard).length - 1;
  if (oldCount === 1 && guardCount === 0) html = html.replace(oldPortalFallback, standalonePortalGuard);
  else if (oldCount === 0 && guardCount === 1) {
    // 冪等な再実行。
  } else {
    errors.push(`${file}: sidebar nav置換対象が不正です (旧snippet=${oldCount}, guard=${guardCount})`);
  }
  const sites = replaceScriptContent(html, 'pt-sites-data', '[]');
  html = sites.html;
  if (sites.count !== 1) errors.push(`${file}: pt-sites-dataを空配列へ置換できません`);
  if (!/\bdata-portal-href\s*=\s*(["'])\1/i.test(html)) errors.push(`${file}: data-portal-hrefを空にできません`);
  return { html, errors };
}

function validate(root, prepare) {
  assertExistingInside(root, root, 'docs root', 'directory');
  const layout = effectiveLayout(root);
  const unitLayout = readJson(unitLayoutPath);
  const portalRoot = resolveInside(root, layout.portalRoot, 'portal root');
  const errors = [];
  const units = unitDirectories(root, layout, errors);
  if (units.length === 0) errors.push('非画面6種別の設計単位が0件です');
  const structured = units.map((unit) => ({ unit, ...structure(unit, unitLayout) }));
  for (const item of structured) errors.push(...item.errors);
  if (prepare && errors.length === 0) {
    const prepared = [];
    for (const item of structured) {
      for (const htmlFile of item.htmlFiles) {
        const result = prepareHtml(htmlFile, item.unit.path, portalRoot);
        errors.push(...result.errors);
        prepared.push({ file: htmlFile, html: result.html });
      }
    }
    if (errors.length === 0) for (const item of prepared) fs.writeFileSync(item.file, item.html);
  }
  if (errors.length === 0) {
    for (const item of structured) for (const htmlFile of item.htmlFiles) errors.push(...linkErrors(htmlFile, item.unit.path));
  }
  if (errors.length) {
    errors.forEach((error) => process.stderr.write(`FAIL: ${error}\n`));
    return { ok: false, count: units.length };
  }
  process.stdout.write(`PASS: standalone units verified (${units.length} unit(s))\n`);
  return { ok: true, count: units.length };
}

function writeFixture(file, title, extra = '') {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `# ${title}\n\n## 要確認事項\n\n配布前に確認する事項。\n${extra}`);
}

function run(args) {
  return childProcess.spawnSync(process.execPath, [scriptPath, ...args], { encoding: 'utf8' });
}

function build(repo, root, standalone, sitesPath) {
  const args = [path.join(scriptDir, 'build-portal.sh'), repo, root, path.join(root, 'project-portal'), '--generated-at', '2026-08-20T00:00:00Z'];
  if (sitesPath) args.push('--sites', sitesPath, '--site-key', 'main');
  if (standalone) args.push('--standalone');
  return childProcess.spawnSync('bash', args, { encoding: 'utf8' });
}

function requiredHtml(unit) {
  return [
    path.join(unit, '基本設計/API基本設計書.html'), path.join(unit, '詳細設計/API詳細設計書.html'),
    path.join(unit, 'テスト設計/APIテスト設計書.html'), path.join(unit, 'テスト設計/API単体テスト設計書.html')
  ];
}

function updateDocMarkdown(file, update) {
  let html = fs.readFileSync(file, 'utf8');
  const doc = scriptById(html, 'doc-md');
  if (!doc) throw new Error(`doc-mdがありません: ${file}`);
  const markdown = JSON.parse(doc.content);
  html = html.replace(doc.whole, doc.whole.replace(doc.content, JSON.stringify(update(markdown))));
  fs.writeFileSync(file, html);
}

function runtimePortalLinkCount(html) {
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map((match) => match[1]);
  const sidebar = scripts.find((source) => source.includes("var nav = document.getElementById('pt-nav');"));
  if (!sidebar) throw new Error('sidebar nav scriptがありません');
  const start = sidebar.indexOf("  var nav = document.getElementById('pt-nav');");
  const end = sidebar.indexOf('\n})();', start);
  if (start < 0 || end < 0) throw new Error('sidebar nav blockを抽出できません');
  const body = sidebar.slice(start, end);
  let anchors = 0;
  const nav = { appendChild() {} };
  const side = { getAttribute(name) { return name === 'data-portal-href' ? '' : ''; } };
  const data = { textContent: '[{"key":"apis","num":"01","label":"API","count":1}]' };
  const document = {
    getElementById(id) { return id === 'pt-nav' ? nav : id === 'pt-nav-data' ? data : null; },
    querySelector(selector) { return selector === '.pt-sidebar' ? side : null; },
    createElement(tag) { if (tag === 'a') anchors += 1; return { appendChild() {}, set className(_v) {}, set href(_v) {}, set textContent(_v) {} }; },
    createTextNode() { return {}; }
  };
  vm.runInNewContext(`(function () {\n${body}\n})();`, { document, JSON });
  return anchors;
}

function runtimeSiteLinkCount(html) {
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map((match) => match[1]);
  const sidebar = scripts.find((source) => source.includes("var switchWrap = document.getElementById('pt-brand-switch');"));
  if (!sidebar) throw new Error('site-switcher scriptがありません');
  const start = sidebar.indexOf("  var switchWrap = document.getElementById('pt-brand-switch');");
  const end = sidebar.indexOf('\n})();', start);
  if (start < 0 || end < 0) throw new Error('site-switcher blockを抽出できません');
  const body = sidebar.slice(start, end);
  const sites = scriptById(html, 'pt-sites-data');
  if (!sites) throw new Error('pt-sites-dataがありません');
  let anchors = 0;
  const element = (tag) => ({
    tag, hidden: false, textContent: '', parentNode: null,
    appendChild(child) { child.parentNode = this; },
    replaceChild(child) { child.parentNode = this; },
    addEventListener() {}, setAttribute() {}, getAttribute() { return 'false'; }, contains() { return false; },
    set className(_value) {}, set href(_value) {}, set id(_value) {}, set type(_value) {}
  });
  const name = element('div');
  name.textContent = 'Main';
  const switchWrap = element('div');
  switchWrap.querySelector = () => name;
  const sitesElement = { textContent: sites.content };
  const document = {
    getElementById(id) { return id === 'pt-brand-switch' ? switchWrap : id === 'pt-sites-data' ? sitesElement : null; },
    createElement(tag) { if (tag === 'a') anchors += 1; return element(tag); },
    addEventListener() {}
  };
  vm.runInNewContext(`(function () {\n${body}\n})();`, { document, JSON, Array });
  return anchors;
}

function expectFailure(root, label) {
  const result = run(['--verify', root]);
  if (result.status === 0) throw new Error(`${label}を不合格にできませんでした`);
  return result.status;
}

function copyCase(source, parent, name) {
  const target = path.join(parent, name);
  fs.cpSync(source, target, { recursive: true });
  return target;
}

function selfTest() {
  const work = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'standalone-units-self-test-'));
  try {
    const repo = path.join(work, 'repo');
    const root = path.join(work, 'output');
    const unit = path.join(root, 'docs/design/apis/api-standalone');
    const sitesPath = path.join(work, 'sites.json');
    fs.mkdirSync(repo, { recursive: true });
    fs.writeFileSync(sitesPath, JSON.stringify({
      specVersion: 1,
      sites: [
        { key: 'main', label: 'Main', root: 'output/project-portal' },
        { key: 'other', label: 'Other', root: 'other-portal' }
      ]
    }));
    const parsedUnitLayout = readJson(unitLayoutPath);
    for (const kind of kinds) requiredFiles(kind, parsedUnitLayout);
    const templateRoot = path.join(repoRoot, 'delivery-payload/templates/リバース検証/API');
    for (const relative of [
      '基本設計/API基本設計書.md',
      '詳細設計/API詳細設計書.md',
      'テスト設計/APIテスト設計書.md',
      'テスト設計/API単体テスト設計書.md'
    ]) {
      const destination = path.join(unit, relative);
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.copyFileSync(path.join(templateRoot, path.basename(relative)), destination);
    }
    fs.appendFileSync(path.join(unit, '基本設計/API基本設計書.md'), '\n[詳細設計](../詳細設計/API詳細設計書.md)\n\n<a href="../テスト設計/APIテスト設計書.md">通常テスト</a>\n');
    writeFixture(path.join(unit, '補助資料.md'), 'Standalone API 補助資料', '\n[基本設計](基本設計/API基本設計書.md)\n');

    const normal = build(repo, root, false, sitesPath);
    if (normal.status !== 0) throw new Error(`通常生成が失敗しました:\n${normal.stderr}${normal.stdout}`);
    const normalHtml = requiredHtml(unit);
    const auxiliaryHtml = path.join(unit, '補助資料.html');
    if (normalHtml.some((file) => !fs.existsSync(file))) throw new Error('通常生成で必須HTML 4件が生成されません');
    if (!fs.existsSync(auxiliaryHtml)) throw new Error('通常生成で補助HTMLが生成されません');
    const generatedHtml = [...normalHtml, auxiliaryHtml];
    if (generatedHtml.some((file) => !/data-portal-href=["'][^"']+["']/i.test(fs.readFileSync(file, 'utf8')))) throw new Error('通常生成のdata-portal-hrefが非空ではありません');
    const normalSiteLinks = runtimeSiteLinkCount(fs.readFileSync(auxiliaryHtml, 'utf8'));
    if (normalSiteLinks < 1) throw new Error('通常生成のsite-switcherがリンクを生成しません');

    const standalone = build(repo, root, true, sitesPath);
    if (standalone.status !== 0) throw new Error(`--standalone生成が失敗しました:\n${standalone.stderr}${standalone.stdout}`);
    const verified = run(['--verify', root]);
    if (verified.status !== 0) throw new Error(`正常fixtureを検証できません:\n${verified.stderr}${verified.stdout}`);
    const runtimeLinks = generatedHtml.reduce((sum, file) => sum + runtimePortalLinkCount(fs.readFileSync(file, 'utf8')), 0);
    if (runtimeLinks !== 0) throw new Error(`runtime portal linksが0ではありません: ${runtimeLinks}`);
    const siteRuntimeLinks = generatedHtml.reduce((sum, file) => sum + runtimeSiteLinkCount(fs.readFileSync(file, 'utf8')), 0);
    if (siteRuntimeLinks !== 0) throw new Error(`site runtime linksが0ではありません: ${siteRuntimeLinks}`);

    const missingRoot = copyCase(root, work, 'missing');
    fs.unlinkSync(path.join(missingRoot, 'docs/design/apis/api-standalone/テスト設計/API単体テスト設計書.html'));
    const missing = expectFailure(missingRoot, '必須HTML欠落');

    const outsideRoot = copyCase(root, work, 'outside');
    updateDocMarkdown(path.join(outsideRoot, 'docs/design/apis/api-standalone/基本設計/API基本設計書.html'), (markdown) => `${markdown}\n[outside](../../../../outside.html)\n`);
    const outside = expectFailure(outsideRoot, '単位外doc-mdリンク');

    const brokenRoot = copyCase(root, work, 'broken');
    updateDocMarkdown(path.join(brokenRoot, 'docs/design/apis/api-standalone/基本設計/API基本設計書.html'), (markdown) => `${markdown}\n[broken](missing.html)\n`);
    const broken = expectFailure(brokenRoot, '不存在doc-mdリンク');

    const auxiliaryOutsideRoot = copyCase(root, work, 'auxiliary-outside');
    updateDocMarkdown(path.join(auxiliaryOutsideRoot, 'docs/design/apis/api-standalone/補助資料.html'), (markdown) => `${markdown}\n[outside](../../../outside.html)\n`);
    const auxiliaryOutside = expectFailure(auxiliaryOutsideRoot, '補助HTMLの単位外doc-mdリンク');

    const auxiliaryBrokenRoot = copyCase(root, work, 'auxiliary-broken');
    updateDocMarkdown(path.join(auxiliaryBrokenRoot, 'docs/design/apis/api-standalone/補助資料.html'), (markdown) => `${markdown}\n[broken](missing.html)\n`);
    const auxiliaryBroken = expectFailure(auxiliaryBrokenRoot, '補助HTMLの不存在doc-mdリンク');

    const codeExamplesRoot = copyCase(root, work, 'code-examples');
    updateDocMarkdown(path.join(codeExamplesRoot, 'docs/design/apis/api-standalone/補助資料.html'), (markdown) => `${markdown}

\`[inline-code](../../outside-inline.md)\`
\`[inline-reference]: ../../outside-inline-reference.md\`
[inline-reference]

~~~markdown
[fenced-code](../../outside-fenced.md)
<a href="../../outside-fenced-anchor.md">example</a>
[fenced-reference]: ../../outside-fenced-reference.md
~~~
[fenced-reference]
`);
    const codeExamplesResult = run(['--verify', codeExamplesRoot]);
    if (codeExamplesResult.status !== 0) throw new Error(`コード例をリンクとして検出しました:\n${codeExamplesResult.stderr}`);
    const codeExamples = codeExamplesResult.status;

    const emptyRoot = path.join(work, 'empty');
    fs.mkdirSync(emptyRoot);
    const empty = expectFailure(emptyRoot, '0単位');

    const referenceRoot = copyCase(root, work, 'reference-broken');
    const referenceHtml = path.join(referenceRoot, 'docs/design/apis/api-standalone/補助資料.html');
    updateDocMarkdown(referenceHtml, (markdown) => `${markdown}\n[full][full-ref]\n[collapsed][]\n[shortcut]\n\n[full-ref]: missing-full.html\n[collapsed]: missing-collapsed.html\n[shortcut]: missing-shortcut.html\n`);
    const referenceErrors = [];
    const parsedReferences = docMarkdownHrefs(fs.readFileSync(referenceHtml, 'utf8'), referenceHtml, referenceErrors);
    for (const expectedReference of ['missing-full.html', 'missing-collapsed.html', 'missing-shortcut.html']) {
      if (!parsedReferences.includes(expectedReference)) throw new Error(`参照リンクを抽出できません: ${expectedReference}`);
    }
    const referenceBroken = expectFailure(referenceRoot, 'doc-md参照リンクの不存在参照先');

    const symlinkRoot = copyCase(root, work, 'symlink');
    const linked = path.join(symlinkRoot, 'docs/design/apis/api-standalone/基本設計/API基本設計書.md');
    const outsideFile = path.join(work, 'outside-required.md');
    fs.writeFileSync(outsideFile, '# outside\n\n## 要確認事項\n');
    fs.unlinkSync(linked);
    fs.symlinkSync(outsideFile, linked);
    const symlink = expectFailure(symlinkRoot, '必須文書symlink');

    process.stdout.write(`PASS: standalone self-test (runtime portal links=${runtimeLinks}, site runtime links=${siteRuntimeLinks}, local broken links=0, required HTML=${normalHtml.length}, auxiliary HTML=1, unit kinds=${kinds.length}, missing=${missing}, outside=${outside}, broken=${broken}, auxiliary-outside=${auxiliaryOutside}, auxiliary-broken=${auxiliaryBroken}, code-examples=${codeExamples}, empty=${empty}, reference-broken=${referenceBroken}, symlink=${symlink})\n`);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--self-test') return selfTest();
  if (args.length !== 2 || !['--prepare', '--verify'].includes(args[0])) {
    usage();
    process.exitCode = 1;
    return;
  }
  const root = path.resolve(args[1]);
  if (!fs.existsSync(root)) throw new Error(`docs rootがありません: ${root}`);
  assertNotSymlink(root, 'docs root');
  const result = validate(root, args[0] === '--prepare');
  if (!result.ok) process.exitCode = 1;
}

try {
  main();
} catch (error) {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
}
