import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const skillDir = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(skillDir, '../../..');
const policyPath = path.join(skillDir, 'references/sequence-kind-policy.json');
const skillPath = path.join(skillDir, 'SKILL.md');
const templatePath = path.join(repoRoot, 'delivery-payload/templates/screen-sequence-template.html');
const rendererPath = path.join(repoRoot, 'generation-engine/scripts/render-template.sh');
const manifestValidatorPath = path.join(repoRoot, 'generation-engine/scripts/unit-list/validate-manifest.sh');
const listTemplatePath = path.join(repoRoot, 'delivery-payload/templates/unit-list/unit-list-template.html');
const policy = JSON.parse(readFileSync(policyPath, 'utf8'));
const work = mkdtempSync(path.join(tmpdir(), 'sequence-kind-policy-'));
const execFileAsync = promisify(execFile);

function makeApiData() {
  const rows = [
    { order: 1, process: '入力検証', ref: 'API詳細設計書.md#§4.1-row-1' },
    { order: 2, process: '注文取得', ref: 'API詳細設計書.md#§4.1-row-2' }
  ];
  return {
    unitKind: 'api', unitId: 'api-orders-get', unitLabel: '注文取得',
    screenId: 'api-orders-get', screenLabel: '注文取得', generatedAt: '2026-08-19T00:00:00Z',
    operations: [{
      key: 'request', label: 'リクエスト処理', lanes: [
        { key: 'caller', label: '呼び出し元' },
        { key: 'api', label: 'API' },
        { key: 'internal', label: '内部処理' }
      ],
      steps: [
        { seq: 1, from: 'caller', to: 'api', label: 'リクエスト受信', kind: 'trigger' },
        ...rows.map((row, index) => ({ seq: index + 2, from: 'api', to: 'internal', label: row.process, kind: 'call', sourceRef: row.ref })),
        { seq: rows.length + 2, from: 'api', to: 'caller', label: 'レスポンス返却', kind: 'return', sourceRef: rows.at(-1).ref }
      ]
    }]
  };
}

function makeFeatureData() {
  const rows = [
    { actor: '利用者', component: '注文サービス', process: '注文を依頼', ref: '機能設計書.md#§3.1-row-1' },
    { actor: '注文サービス', component: '決済サービス', process: '決済を依頼', ref: '機能設計書.md#§3.1-row-2' }
  ];
  return {
    unitKind: 'feature', unitId: 'feat-order', unitLabel: '注文機能',
    screenId: 'feat-order', screenLabel: '注文機能', generatedAt: '2026-08-19T00:00:00Z',
    operations: [{
      key: 'normal-flow', label: '正常系フロー', lanes: [
        { key: 'user', label: '利用者' },
        { key: '注文サービス', label: '注文サービス' },
        { key: '決済サービス', label: '決済サービス' }
      ],
      steps: rows.map((row, index) => ({
        seq: index + 1,
        from: index === 0 ? 'user' : rows[index - 1].component,
        to: row.component,
        label: row.process,
        kind: index === 0 ? 'trigger' : 'call',
        sourceRef: row.ref
      }))
    }]
  };
}

function validateWithDocumentedJq(data) {
  const skill = readFileSync(skillPath, 'utf8');
  const match = skill.match(/jq -e '\n([\s\S]*?)\n' "<対象単位のシーケンス図-data\.json>"/);
  assert.ok(match, 'SKILL.mdのjq検証式を抽出できること');
  execFileSync('jq', ['-e', match[1]], { input: JSON.stringify(data), stdio: ['pipe', 'ignore', 'pipe'] });
}

async function render(kind, data, outputPath) {
  const dataPath = path.join(path.dirname(outputPath), 'シーケンス図-data.json');
  const preparedTemplatePath = path.join(path.dirname(outputPath), 'sequence-template.prepared.html');
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(dataPath, `${JSON.stringify(data, null, 2)}\n`);
  const preparedTemplate = readFileSync(templatePath, 'utf8')
    .replaceAll('{{PORTAL_INDEX_HREF}}', '../../../project-portal/index.html')
    .replaceAll('{{SCREEN_LABEL}}', data.unitLabel)
    .replaceAll('{{ACTIVE_CATEGORY_LABEL}}', '一覧')
    .replaceAll('/* TOKENS_CSS */', '');
  writeFileSync(preparedTemplatePath, preparedTemplate);
  const shell = `
    source "$1"
    template="$(cat "$2")"
    page_data="$(cat "$3")"
    out="$(render_template "$template" "{{PAGE_DATA_JSON}}" "$page_data")"
    printf '%s\n' "$out" > "$4"
  `;
  await execFileAsync('bash', ['-c', shell, 'sequence-self-test', rendererPath, preparedTemplatePath, dataPath, outputPath]);
  const html = readFileSync(outputPath, 'utf8');
  assert.ok(statSync(outputPath).size > 0, `${kind} HTMLが0バイト超であること`);
  assert.ok(html.includes(`"unitKind": "${kind}"`), `${kind}のunitKindが埋め込まれること`);
  assert.doesNotMatch(html, /\{\{(?:PORTAL_INDEX_HREF|SCREEN_LABEL|PAGE_DATA_JSON|ACTIVE_CATEGORY_LABEL)\}\}/);
}

function unitDir(kind, unit) {
  if (typeof unit.unitId === 'string' && unit.unitId.length > 0) {
    const unitIdPattern = new RegExp(policy.unitDirectory.unitIdPattern);
    assert.match(unit.unitId, unitIdPattern, `${kind}: unitIdは安全な単一pathセグメントであること`);
    return unit.unitId;
  }
  assert.equal(typeof unit.unitKey, 'string', `${kind}: unitIdが空ならunitKeyが必要`);
  assert.ok(unit.unitKey.length > 0, `${kind}: unitKeyが空でないこと`);
  assert.doesNotMatch(unit.unitKey, /[\\/\x00-\x1f\x7f]/, `${kind}: unitKeyにpath区切り・制御文字がないこと`);
  return `${policy.unitDirectory.fallbackPrefixes[kind]}${unit.unitKey}`;
}

function selectManifestUnit(units, target) {
  const key = typeof target.unitId === 'string' && target.unitId.length > 0 ? 'unitId' : 'unitKey';
  const value = target[key];
  const matches = units.filter((unit) => unit[key] === value);
  assert.equal(matches.length, 1, `${key}完全一致で対象が1件であること`);
  return matches[0];
}

async function validateNonGeneratingManifest() {
  const sourceDir = path.join(work, 'source');
  const sourceFile = path.join(sourceDir, '001_create_orders.sql');
  const manifestPath = path.join(work, 'table-manifest.json');
  mkdirSync(sourceDir, { recursive: true });
  writeFileSync(sourceFile, 'CREATE TABLE orders (id INTEGER PRIMARY KEY);\n');
  const unit = {
    unitId: 'table-orders', unitKey: 'orders', kind: 'table', unitNameGuess: '注文', identifier: 'orders',
    detectionMethod: 'migration', confidence: 'HIGH', fileCount: 1, sourceFile: path.basename(sourceFile),
    designDocPath: '../../テーブル/table-orders/基本設計書.html', sequencePath: '../../テーブル/table-orders/シーケンス図.html'
  };
  delete unit[policy.kinds.table.omitListField];
  const manifest = {
    generatedAt: '2026-08-19T00:00:00Z', sourceDir, unitKind: 'table',
    strategy: { extractionMethod: 'static-analysis', approvedByUser: true, unitIdRegex: null },
    detectionSummary: { unitCount: 1, unresolvedCount: 0 }, units: [unit]
  };
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  await execFileAsync('bash', [manifestValidatorPath, manifestPath, '--unit-kind', 'table']);
  const validatedUnit = JSON.parse(readFileSync(manifestPath, 'utf8')).units[0];
  assert.equal(validatedUnit.designDocPath, unit.designDocPath, '他の関連資料pathを維持すること');
  assert.ok(!Object.hasOwn(validatedUnit, policy.linkField), '検証済み一覧データにsequencePathがないこと');
  return validatedUnit;
}

function isSafeRelativeUrl(value) {
  return typeof value === 'string' && value.length > 0 && value === value.trim() &&
    !/[\x00-\x1f\x7f]/.test(value) && !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(value) &&
    !/^[\\/]/.test(value) && !value.includes('\\');
}

function runActualListRelatedDocs(unit) {
  const listTemplate = readFileSync(listTemplatePath, 'utf8');
  const script = listTemplate.match(/\/\* 1-65:[\s\S]*?(\(function \(\) \{[\s\S]*?\n    \}\)\(\);)/)?.[1];
  assert.ok(script, '一覧テンプレートの関連資料表示処理を抽出できること');

  function element() {
    return {
      children: [], textContent: '', className: '', style: {}, attributes: {},
      appendChild(child) { this.children.push(child); return child; },
      setAttribute(name, value) { this.attributes[name] = value; },
      getAttribute(name) { return this.attributes[name] ?? null; }
    };
  }

  const headRow = element();
  const row = element();
  row.attributes['data-unit-id'] = String(unit.unitId);
  row.attributes['data-unit-key'] = String(unit.unitKey);
  const table = { querySelector(selector) { return selector === 'thead tr' ? headRow : null; } };
  const document = { createElement() { return element(); } };
  Function('document', 'table', 'manifest', 'allRows', script)(document, table, { units: [unit] }, [row]);

  const cell = row.children.at(-1);
  assert.ok(cell, '関連資料セルが生成されること');
  return cell.children[0].children.map((link) => ({ label: link.textContent, href: link.href }));
}

try {
  const generating = Object.entries(policy.kinds).filter(([, value]) => value.generate).map(([kind]) => kind);
  const omitted = Object.entries(policy.kinds).filter(([, value]) => !value.generate && value.omitListField === policy.linkField).map(([kind]) => kind);
  assert.deepEqual(generating, ['screen', 'api', 'feature']);
  assert.deepEqual(omitted, ['table', 'batch', 'report', 'external', 'message']);
  assert.match('screen-order-list', new RegExp(policy.unitDirectory.screenUnitIdPattern));

  const apiData = makeApiData();
  const featureData = makeFeatureData();
  validateWithDocumentedJq(apiData);
  validateWithDocumentedJq(featureData);
  assert.throws(
    () => validateWithDocumentedJq({ ...apiData, operations: [] }),
    'APIの順序表が空ならjq検証を拒否すること'
  );
  assert.throws(
    () => validateWithDocumentedJq({ ...featureData, operations: [] }),
    '機能の順序表が空ならjq検証を拒否すること'
  );
  const invalidApiData = structuredClone(apiData);
  invalidApiData.operations[0].steps.at(-1).kind = 'call';
  assert.throws(() => validateWithDocumentedJq(invalidApiData), 'API終端がreturnでなければjq検証を拒否すること');
  const fallbackFeatureData = { ...featureData, unitId: null, unitKey: 'order-confirm', screenId: null };
  validateWithDocumentedJq(fallbackFeatureData);

  assert.equal(unitDir('api', { unitId: 'api-orders-get', unitKey: 'orders-get' }), 'api-orders-get');
  assert.equal(unitDir('feature', { unitId: null, unitKey: 'order-confirm' }), 'feature-order-confirm');
  assert.throws(() => unitDir('feature', { unitId: null, unitKey: 'order/confirm' }));
  assert.equal(unitDir('feature', { unitId: null, unitKey: '注文管理' }), 'feature-注文管理');
  assert.notEqual(
    unitDir('feature', { unitId: null, unitKey: '注文管理' }),
    unitDir('feature', { unitId: null, unitKey: '利用管理' })
  );
  assert.throws(() => unitDir('api', { unitId: '../escape', unitKey: 'escape' }));
  assert.equal(selectManifestUnit([{ unitId: null, unitKey: 'order-confirm' }], fallbackFeatureData).unitKey, 'order-confirm');
  const apiHtml = path.join(work, 'docs/design/apis', unitDir('api', apiData), 'シーケンス図.html');
  const featureHtml = path.join(work, 'docs/design/features', unitDir('feature', featureData), 'シーケンス図.html');
  const [, , validatedNonGeneratingUnit] = await Promise.all([
    render('api', apiData, apiHtml),
    render('feature', featureData, featureHtml),
    validateNonGeneratingManifest()
  ]);

  const apiList = path.join(work, 'project-portal/lists/API一覧/API一覧.html');
  const featureList = path.join(work, 'project-portal/lists/機能一覧/機能一覧.html');
  const apiSequencePath = path.relative(path.dirname(apiList), apiHtml).split(path.sep).join('/');
  const featureSequencePath = path.relative(path.dirname(featureList), featureHtml).split(path.sep).join('/');
  assert.ok(isSafeRelativeUrl(apiSequencePath));
  assert.ok(isSafeRelativeUrl(featureSequencePath));

  const validatedLabels = runActualListRelatedDocs(validatedNonGeneratingUnit);
  assert.ok(validatedLabels.some((link) => link.label === '基本設計書'));
  assert.ok(!validatedLabels.some((link) => link.label === 'シーケンス図'));

  const generatingLabels = runActualListRelatedDocs({
    unitId: apiData.unitId, unitKey: 'orders-get',
    designDocPath: '../../API/api-orders-get/基本設計書.html', sequencePath: apiSequencePath
  });
  assert.ok(
    generatingLabels.some((link) => link.label === 'シーケンス図' && link.href === apiSequencePath),
    '生成対象では実テンプレート処理がsequencePathと同じhrefを表示すること'
  );
  const featureGeneratingLabels = runActualListRelatedDocs({
    unitId: featureData.unitId, unitKey: 'order',
    designDocPath: '../../機能/feat-order/機能設計書.html', sequencePath: featureSequencePath
  });
  assert.ok(
    featureGeneratingLabels.some((link) => link.label === 'シーケンス図' && link.href === featureSequencePath),
    '機能でも実テンプレート処理がsequencePathと同じhrefを表示すること'
  );

  for (const kind of omitted) {
    const unit = {
      unitId: `${kind}-sample`, unitKey: 'sample',
      designDocPath: `../../${kind}/基本設計書.html`, sequencePath: `../../${kind}/シーケンス図.html`
    };
    delete unit[policy.kinds[kind].omitListField];
    const labels = runActualListRelatedDocs(unit);
    assert.ok(labels.some((link) => link.label === '基本設計書'), `${kind}: 他の関連資料は維持されること`);
    assert.ok(!labels.some((link) => link.label === 'シーケンス図'), `${kind}: シーケンス図欄が現れないこと`);
    assert.ok(!Object.hasOwn(unit, policy.linkField), `${kind}: sequencePathキーを省くこと`);
  }

  console.log(`PASS policy: generate=${generating.join(',')} omit=${omitted.join(',')}`);
  console.log(`PASS generated api: ${path.relative(work, apiHtml)}`);
  console.log(`PASS generated feature: ${path.relative(work, featureHtml)}`);
  console.log(`PASS validated list-related-docs: non-generating kinds expose no sequence slot (${omitted.length})`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
