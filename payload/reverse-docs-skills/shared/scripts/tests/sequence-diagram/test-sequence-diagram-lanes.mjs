import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, '../../../..');
const fixturePath = join(scriptDir, 'fixtures/lane-boundaries.json');
const templatePath = join(repoRoot, 'shared/templates/screen-sequence-template.html');
const samplesRoot = join(repoRoot, 'shared/samples/画面');
const DEFAULT_LANES = [
  { key: 'user', label: '利用者' },
  { key: 'screen', label: '画面' },
  { key: 'api', label: 'API' },
  { key: 'table', label: 'テーブル' }
];
const EXPECTED_SAMPLE_FILES = 5;
const EXPECTED_SAMPLE_OPERATIONS = 10;
const EXPECTED_FIXTURE_CASES = 5;
const EXPECTED_TARGETS = 15;
const EXPECTED_ARTIFACTS = 5;
const failures = [];
let dataChecks = 0;
let domChecks = 0;
let svgChecks = 0;
let artifactChecks = 0;

function fail(subject, message) {
  failures.push(`${subject}: ${message}`);
}

function normalizeSourcePath(sourceRef) {
  return String(sourceRef)
    .replace(/#L\d+(?:-L?\d+)?$/i, '')
    .replace(/:\d+(?:-\d+)?$/, '');
}

function sourcePaths(operation) {
  const derivedSteps = (operation.steps || []).filter((step) => step.kind !== 'trigger');
  return new Set(
    derivedSteps
      .map((step) => step.sourceRef)
      .filter(Boolean)
      .map(normalizeSourcePath)
  );
}

function effectiveLanes(pageData, operation) {
  if ((operation.lanes || []).length) {
    return { source: 'operation', definitions: operation.lanes };
  }
  if ((pageData.lanes || []).length) {
    return { source: 'page', definitions: pageData.lanes };
  }
  return { source: 'default', definitions: DEFAULT_LANES };
}

function boundaryName(operation) {
  const count = sourcePaths(operation).size;
  if (count === 1) return 'single';
  if (count > 1) return 'multiple';
  return 'none';
}

function validateData(subject, pageData, operation, expected) {
  dataChecks += 1;
  const steps = operation.steps || [];
  const first = steps[0];
  const effective = effectiveLanes(pageData, operation);
  const lanes = new Map(effective.definitions.map((lane) => [lane.key, lane.label]));
  const endpoints = new Set(steps.flatMap((step) => [step.from, step.to]));

  if (
    !first ||
    first.from !== 'user' ||
    first.to !== 'screen' ||
    first.label !== '操作開始' ||
    first.kind !== 'trigger' ||
    first.sourceRef != null
  ) {
    fail(subject, '先頭stepが user → screen の「操作開始」ではない');
  }
  if (!steps.some((step) => step.from === 'user')) {
    fail(subject, '利用者起点stepがない');
  }
  for (const endpoint of endpoints) {
    if (!lanes.has(endpoint)) fail(subject, `有効レーンにendpoint ${endpoint} がない`);
  }

  const pathCount = sourcePaths(operation).size;
  if (pathCount === 1) {
    if (endpoints.has('api')) {
      fail(subject, '単一sourceRefのstep endpointsにapiがある');
    }
    if (lanes.has('api')) {
      fail(subject, '単一sourceRefの有効レーンにapiがある');
    }
    if (!lanes.has('internal') || lanes.get('internal') !== '内部処理') {
      fail(subject, '単一sourceRefの有効レーンに内部処理がない');
    }
  } else if (pathCount > 1) {
    if (!endpoints.has('api')) fail(subject, '複数sourceRefのstep endpointsにapiがない');
    if (!lanes.has('api')) fail(subject, '複数sourceRefの有効レーンにapiがない');
  }

  if (expected) {
    if (boundaryName(operation) !== expected.boundary) {
      fail(subject, `境界がexpectedと不一致 (${boundaryName(operation)}/${expected.boundary})`);
    }
    if (effective.source !== expected.laneSource) {
      fail(subject, `laneSourceがexpectedと不一致 (${effective.source}/${expected.laneSource})`);
    }
    if (endpoints.has('api') !== expected.api || lanes.has('api') !== expected.api) {
      fail(subject, `dataのAPI有無がexpectedと不一致 (${expected.api})`);
    }
    if (endpoints.has('internal') !== expected.internal || lanes.has('internal') !== expected.internal) {
      fail(subject, `dataの内部処理有無がexpectedと不一致 (${expected.internal})`);
    }
    const labels = effective.definitions.map((lane) => lane.label);
    if (JSON.stringify(labels) !== JSON.stringify(expected.laneLabels)) {
      fail(subject, `有効レーンlabelがexpectedと不一致 (${labels.join('/')})`);
    }
  }
}

function sequenceRuntime(html) {
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/gi)]
    .map((match) => match[1].trim())
    .filter((script) => script.includes('var DEFAULT_LANES'));
  return scripts[0] || '';
}

function embeddedPageData(html) {
  const match = html.match(/<script type="application\/json" id="page-data">\s*([\s\S]*?)\s*<\/script>/i);
  if (!match) throw new Error('page-data scriptがない');
  return JSON.parse(match[1]);
}

function validateSampleArtifacts(template) {
  const templateRuntime = sequenceRuntime(template);
  const templateLead = textContent(
    (template.match(/<p class="lead">([\s\S]*?)<\/p>/i) || [])[1] || ''
  );

  for (const entry of readdirSync(samplesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dataPath = join(samplesRoot, entry.name, 'シーケンス図-data.json');
    const htmlPath = join(samplesRoot, entry.name, 'シーケンス図.html');
    if (!existsSync(dataPath) || !existsSync(htmlPath)) continue;
    artifactChecks += 1;
    const data = JSON.parse(readFileSync(dataPath, 'utf8'));
    const html = readFileSync(htmlPath, 'utf8');
    try {
      if (JSON.stringify(embeddedPageData(html)) !== JSON.stringify(data)) {
        fail(`artifact/${entry.name}`, 'HTML埋込page-dataがdata JSONと一致しない');
      }
    } catch (error) {
      fail(`artifact/${entry.name}`, error.message);
    }
    if (sequenceRuntime(html) !== templateRuntime) {
      fail(`artifact/${entry.name}`, 'sequence runtime scriptがtemplateと一致しない');
    }
    const lead = textContent((html.match(/<p class="lead">([\s\S]*?)<\/p>/i) || [])[1] || '');
    if (lead !== templateLead) {
      fail(`artifact/${entry.name}`, 'リード文がtemplateと一致しない');
    }
  }
  if (artifactChecks !== EXPECTED_ARTIFACTS) {
    fail('artifact count', `${artifactChecks}/${EXPECTED_ARTIFACTS}`);
  }
}

function textContent(html) {
  return html
    .replace(/<[^>]*>/g, '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function hasClass(element, className) {
  return (element.getAttribute('class') || '').split(/\s+/).includes(className);
}

function walk(element, visit) {
  for (const child of element.children) {
    visit(child);
    walk(child, visit);
  }
}

class TestElement {
  constructor(tagName) {
    this.tagName = String(tagName).toLowerCase();
    this.attributes = new Map();
    this.children = [];
    this.parentNode = null;
    this.style = {};
    this.listeners = new Map();
    this._textContent = '';
    this._innerHTML = '';
    this.classList = {
      toggle: (className, force) => {
        const classes = new Set((this.className || '').split(/\s+/).filter(Boolean));
        const enabled = force === undefined ? !classes.has(className) : Boolean(force);
        if (enabled) classes.add(className);
        else classes.delete(className);
        this.className = [...classes].join(' ');
        return enabled;
      }
    };
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  setAttribute(name, value) {
    this.attributes.set(String(name), String(value));
  }

  getAttribute(name) {
    return this.attributes.has(String(name)) ? this.attributes.get(String(name)) : null;
  }

  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(listener);
  }

  querySelectorAll(selector) {
    const matches = [];
    if (selector.startsWith('.')) {
      const className = selector.slice(1);
      walk(this, (element) => {
        if (hasClass(element, className)) matches.push(element);
      });
    }
    return matches;
  }

  get className() {
    return this.getAttribute('class') || '';
  }

  set className(value) {
    this.setAttribute('class', value);
  }

  get textContent() {
    if (this.children.length) {
      return this._textContent + this.children.map((child) => child.textContent).join('');
    }
    return this._textContent;
  }

  set textContent(value) {
    this._textContent = String(value == null ? '' : value);
    this._innerHTML = '';
    this.children = [];
  }

  get innerHTML() {
    return this._innerHTML;
  }

  set innerHTML(value) {
    this._innerHTML = String(value == null ? '' : value);
    this._textContent = '';
    this.children = [];
  }
}

class TestDocument {
  constructor(pageData) {
    this.elements = new Map();
    this.seed('page-data').textContent = JSON.stringify(pageData);
    this.seed('operation-list');
    this.seed('operation-label');
    this.seed('sequence-svg');
    this.seed('steps-table-body');
    this.seed('empty-message');
    this.diagramWrap = this.seed('diagram-wrap');
    this.seed('steps-table-wrap');
  }

  seed(id) {
    const element = new TestElement('div');
    element.setAttribute('id', id);
    this.elements.set(id, element);
    return element;
  }

  getElementById(id) {
    return this.elements.get(id) || null;
  }

  querySelector(selector) {
    return selector === '.diagram-wrap' ? this.diagramWrap : null;
  }

  createElement(tagName) {
    return new TestElement(tagName);
  }

  createElementNS(_namespace, tagName) {
    return new TestElement(tagName);
  }
}

function executeRuntime(templateRuntime, pageData) {
  const document = new TestDocument(pageData);
  vm.runInNewContext(templateRuntime, { document }, { timeout: 1000 });

  const tbody = document.getElementById('steps-table-body');
  const svg = document.getElementById('sequence-svg');
  const laneLabels = [];
  let arrowCount = 0;
  walk(svg, (element) => {
    if (hasClass(element, 'lane-label')) laneLabels.push(element.textContent);
    if (hasClass(element, 'step-arrow')) arrowCount += 1;
  });
  return {
    rowsHtml: tbody.children.map((row) => row.innerHTML).join(''),
    laneLabels,
    arrowCount
  };
}

function validateRendered(subject, operation, expected, rendered) {
  domChecks += 1;
  svgChecks += 1;

  const tableText = textContent(rendered.rowsHtml);
  if (!tableText.includes('利用者 → 画面') || !tableText.includes('操作開始')) {
    fail(subject, 'DOMの操作開始行が「利用者 → 画面」ではない');
  }

  if (!rendered.laneLabels.includes('利用者')) {
    fail(subject, 'SVG lane-labelに利用者がない');
  }

  if (rendered.arrowCount !== (operation.steps || []).length) {
    fail(
      subject,
      `SVG step-arrow数がsteps数と不一致 (${rendered.arrowCount}/${(operation.steps || []).length})`
    );
  }

  const pathCount = sourcePaths(operation).size;
  if (pathCount === 1) {
    if (rendered.laneLabels.includes('API')) {
      fail(subject, '単一sourceRefのSVGにAPIレーンがある');
    }
    if (tableText.includes('API')) {
      fail(subject, '単一sourceRefの表にAPIレーンがある');
    }
    if (!rendered.laneLabels.includes('内部処理') || !tableText.includes('内部処理')) {
      fail(subject, '単一sourceRefのSVGまたは表に内部処理がない');
    }
  } else if (pathCount > 1) {
    if (!rendered.laneLabels.includes('API')) {
      fail(subject, '複数sourceRefのSVGにAPIレーンがない');
    }
    if (!tableText.includes('API')) {
      fail(subject, '複数sourceRefの表にAPIレーンがない');
    }
  }

  if (expected) {
    if (rendered.laneLabels.includes('API') !== expected.api || tableText.includes('API') !== expected.api) {
      fail(subject, `DOM/SVGのAPI有無がexpectedと不一致 (${expected.api})`);
    }
    const svgInternal = rendered.laneLabels.includes('内部処理');
    const domInternal = tableText.includes('内部処理');
    if (svgInternal !== expected.internal || domInternal !== expected.internal) {
      fail(subject, `DOM/SVGの内部処理有無がexpectedと不一致 (${expected.internal})`);
    }
    if (JSON.stringify(rendered.laneLabels) !== JSON.stringify(expected.laneLabels)) {
      fail(subject, `SVG lane-labelがexpectedと不一致 (${rendered.laneLabels.join('/')})`);
    }
    for (const label of expected.laneLabels) {
      if (!tableText.includes(label)) {
        fail(subject, `DOMの表にexpected lane label ${label} がない`);
      }
    }
  }
}

function collectTargets() {
  const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));
  if (fixture.cases.length !== EXPECTED_FIXTURE_CASES) {
    fail('fixture case count', `${fixture.cases.length}/${EXPECTED_FIXTURE_CASES}`);
  }
  const targets = fixture.cases.flatMap((fixtureCase) =>
    fixtureCase.pageData.operations.map((operation) => ({
      subject: `fixture/${fixtureCase.name}/${operation.key}`,
      pageData: fixtureCase.pageData,
      operation,
      expected: fixtureCase.expected
    }))
  );

  let sampleFiles = 0;
  let sampleOperations = 0;
  for (const entry of readdirSync(samplesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const samplePath = join(samplesRoot, entry.name, 'シーケンス図-data.json');
    if (!existsSync(samplePath)) continue;
    sampleFiles += 1;
    const pageData = JSON.parse(readFileSync(samplePath, 'utf8'));
    for (const operation of pageData.operations || []) {
      sampleOperations += 1;
      targets.push({
        subject: `sample/${basename(entry.name)}/${operation.key}`,
        pageData,
        operation,
        expected: null
      });
    }
  }
  if (sampleFiles !== EXPECTED_SAMPLE_FILES) {
    fail('sample data file count', `${sampleFiles}/${EXPECTED_SAMPLE_FILES}`);
  }
  if (sampleOperations !== EXPECTED_SAMPLE_OPERATIONS) {
    fail('sample operation count', `${sampleOperations}/${EXPECTED_SAMPLE_OPERATIONS}`);
  }
  if (targets.length !== EXPECTED_TARGETS) {
    fail('total target count', `${targets.length}/${EXPECTED_TARGETS}`);
  }
  return targets;
}

try {
  const template = readFileSync(templatePath, 'utf8');
  const templateRuntime = sequenceRuntime(template);
  if (!templateRuntime) throw new Error('templateのsequence runtimeがない');
  const targets = collectTargets();
  for (const target of targets) {
    validateData(target.subject, target.pageData, target.operation, target.expected);
  }
  validateSampleArtifacts(template);

  for (const target of targets) {
    const pageData = {
      ...target.pageData,
      operations: [target.operation]
    };
    const rendered = executeRuntime(templateRuntime, pageData);
    validateRendered(target.subject, target.operation, target.expected, rendered);
  }
} catch (error) {
  fail('test runner', error.stack || error.message);
}

if (failures.length) {
  console.error(`FAIL sequence diagram lanes (${failures.length})`);
  for (const failure of failures) console.error(`- ${failure}`);
  console.error(
    `checked data=${dataChecks}, DOM=${domChecks}, SVG=${svgChecks}, artifact=${artifactChecks}`
  );
  process.exit(1);
}

console.log(`PASS data=${dataChecks}`);
console.log(`PASS DOM=${domChecks}`);
console.log(`PASS SVG=${svgChecks}`);
console.log(`PASS artifact=${artifactChecks}`);
