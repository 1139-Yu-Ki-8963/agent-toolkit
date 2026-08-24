#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const builder = path.join(root, 'generation-engine/scripts/detail-pages/build-detail-page.sh');
const validator = path.join(root, 'generation-engine/scripts/detail-pages/validate-page-data.sh');
const projector = path.join(root, 'generation-engine/scripts/detail-pages/project-semantic-glossary.py');
const glossaryFixtures = path.join(root, 'generation-engine/scripts/glossary/fixtures');
const canonicalRegistry = path.join(glossaryFixtures, 'canonical-registry');
const template = path.join(root, 'delivery-payload/templates/detail-pages/detail-t2-dictionary.html');
const portalCatalog = path.join(root, 'delivery-payload/references/portal-catalog.json');
const sampleFixture = path.join(root, 'generation-engine/scripts/detail-pages/fixtures/semantic-glossary-sample-page-data.json');
const sampleRegenerator = path.join(root, 'generation-engine/scripts/detail-pages/regenerate-semantic-glossary-sample.sh');
const samplesDir = path.join(root, 'generation-engine/samples');
// 改善課題1-29（一覧の置き場が三者三様になっている問題を直す指示書.mdで解消済み）:
// output-layout.json の unitsRoot は "project-portal/lists"（対象プロジェクト向けの
// 英字ディレクトリ規約）だったため、portal-catalog.json の semantic-glossary
// blueprint が宣言する物理配置（日本語の "project-portal/一覧/用語辞書"）と食い違い、
// output_layout_get 経由の解決は samplesDir に対して ENOENT を起こしていた。現在は
// unitsRoot 自体が "project-portal/一覧" へ揃ったため両者は一致するが、実体の唯一の
// 正本である portal-catalog.json の blueprint.dir を直接読む形はそのまま維持する。
const semanticGlossaryBlueprint = JSON.parse(fs.readFileSync(portalCatalog, 'utf8'))
  .categories.flatMap(category => category.blueprints || [])
  .find(blueprint => blueprint.kind === 'semantic-glossary');
assert.ok(semanticGlossaryBlueprint, 'portal-catalog.json must declare a semantic-glossary blueprint');
const sampleHtml = path.join(samplesDir, semanticGlossaryBlueprint.dir, '用語辞書.html');
const glossaryPython = path.join(root, 'generation-engine/scripts/glossary/.venv/bin/python');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'semantic-glossary-page-'));

const newTerms = [
  {key:'customer',term_ja:'顧客',term_en:'Customer',definition:'商品またはサービスを購入する組織または個人。',scope:'sales.customer',category:'entity',code_name:'customer',type_name:'Customer',db_name:'customers',api_name:'customer',ui_label:'顧客',allowed_values:[],status:'active',notes:'顧客概念の標準名',representations:[{channel:'database',value:'customers.customer_id',location:'db/customers.sql:12'},{channel:'api',value:'customerId',location:'openapi/customer.yaml#/Customer'}],sourceRefs:['docs/domain/customer.md#顧客'],aliases:['取引先'],forbiddenTerms:[{term:'顧客マスタ',reason:'テーブル名を概念名にしない'}],relations:['order'],examples:['法人顧客'],counterExamples:['匿名閲覧者'],constraints:['個人・法人を分割しない'],securityClassification:'internal'},
  {key:'legacy_customer_code',term_ja:'旧顧客コード',term_en:'Legacy Customer Code',definition:'旧CRMの識別子。',scope:'sales.customer',category:'attribute',code_name:'legacyCustomerCode',type_name:'LegacyCustomerCode',db_name:'legacy_customer_code',api_name:'legacyCustomerCode',ui_label:'旧顧客コード',allowed_values:[],status:'deprecated',notes:'参照専用',representations:[{channel:'database',value:'legacy_customer_code',location:'db/import.sql:31'}],sourceRefs:['migration/legacy.md'],aliases:[],forbiddenTerms:[],relations:['customer'],examples:['旧CRM取込'],counterExamples:['新規主キー'],constraints:['参照のみ'],securityClassification:'confidential',replacementKey:'customer'},
  {key:'old_customer_type',term_ja:'旧顧客種別',term_en:'Legacy Customer Type',definition:'廃止済みの分類。',scope:'sales.customer',category:'value',code_name:'oldCustomerType',type_name:'OldCustomerType',db_name:'old_customer_type',api_name:'oldCustomerType',ui_label:'旧顧客種別',allowed_values:[],status:'retired',notes:'新規利用禁止',representations:[],sourceRefs:['archive/customers.sql'],aliases:[],forbiddenTerms:[],relations:['customer'],examples:[],counterExamples:[],constraints:['新規利用禁止'],securityClassification:'internal'}
];

const base = {pageKind:'glossary',generatedAt:'2026-08-02T00:00:00Z',title:'用語辞書',description:'承認済みの業務概念と実装名称を対応付けます。',projectionVersion:'0.2',glossarySchemaVersion:'1.0.0',glossaryContentVersion:'1.0.0',categories:[{key:'entity',label:'エンティティ'},{key:'attribute',label:'属性'},{key:'value',label:'値'}],terms:newTerms};
const {projectionVersion: _projection, glossarySchemaVersion: _schema, glossaryContentVersion: _content, ...legacyBase} = base;
const legacy = {...legacyBase, categories:[{key:'domain',label:'業務用語'}], terms:[{term:'ユーザー',definition:'システムを利用する人物。',codeRefs:['User','user_id'],category:'domain',sourceRef:'models/user.py'}]};

function write(name, value) {
  const file = path.join(tmp, name);
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
  return file;
}
function run(command, args, options={}) { return cp.spawnSync(command, args, {encoding:'utf8', ...options}); }
function build(name, value) {
  const input = write(name + '.json', value);
  const out = path.join(tmp, name);
  const result = run('bash', [builder, input, out, '--page', 'glossary']);
  assert.equal(result.status, 0, result.stderr);
  const htmlPath = path.join(out, '用語辞書.html');
  return {input, htmlPath, html:fs.readFileSync(htmlPath, 'utf8')};
}
function embedded(html) {
  const match = html.match(/<script type="application\/json" id="page-data">\n([\s\S]*?)\n<\/script>/);
  assert.ok(match, 'page-data JSON block must exist');
  return JSON.parse(match[1]);
}
function runtimeCheck(htmlPath, options={}) {
  const expectHistory = options.expectHistory === true;
  const program = String.raw`
    let chromium;
    try { ({chromium} = require('playwright')); }
    catch (error) { console.error('runtime: FAIL (playwright unavailable; run npm ci at the repository root)'); process.exit(2); }
    const {pathToFileURL} = require('node:url');
    const assert = require('node:assert/strict');
    (async () => {
      const browser = await chromium.launch({headless:true});
      try {
        const page = await browser.newPage({viewport:{width:1280,height:720}});
        await page.goto(pathToFileURL(process.argv[1]).href, {waitUntil:'load'});
        const initialRowCount = await page.locator('#dict-table-body tr[data-interactive="true"]').count();
        const entityChip = page.getByRole('button', {name:'エンティティ', exact:true});
        assert.equal(await entityChip.getAttribute('aria-pressed'), 'false');
        await entityChip.click();
        assert.equal(await page.getByRole('button', {name:'エンティティ', exact:true}).getAttribute('aria-pressed'), 'true');
        const filteredRowCount = await page.locator('#dict-table-body tr[data-interactive="true"]').count();
        assert.ok(filteredRowCount <= initialRowCount, 'category filter must not add visible rows');
        const filteredCategories = await page.locator('#dict-table-body tr[data-interactive="true"] td:nth-child(6)').allTextContents();
        assert.ok(filteredCategories.every(value => value === 'エンティティ'), 'selected category must constrain every visible row');
        await page.getByRole('button', {name:'エンティティ', exact:true}).click();
        assert.equal(await page.getByRole('button', {name:'エンティティ', exact:true}).getAttribute('aria-pressed'), 'false');
        assert.equal(await page.locator('#dict-table-body tr[data-interactive="true"]').count(), initialRowCount);
        if (${expectHistory ? 'true' : 'false'}) {
          const historyChip = page.getByRole('button', {name:'履歴', exact:true});
          assert.equal(await historyChip.getAttribute('aria-pressed'), 'false');
          await historyChip.click();
          assert.equal(await historyChip.getAttribute('aria-pressed'), 'true');
          assert.equal(await page.locator('#dict-table-body tr[data-interactive="true"]').count(), 1, 'history filter must show only retired terms');
          assert.equal(await page.locator('#dict-table-body tr[data-interactive="true"] td:nth-child(13) .state').first().innerText(), '履歴');
          await historyChip.click();
          assert.equal(await historyChip.getAttribute('aria-pressed'), 'false');
          assert.equal(await page.locator('#dict-table-body tr[data-interactive="true"]').count(), initialRowCount);
        }
        const row = page.locator('#dict-table-body tr[data-interactive="true"]').first();
        await row.focus();
        await page.keyboard.press('Enter');
        assert.equal(await row.getAttribute('aria-expanded'), 'true');
        assert.equal(await page.locator('#term-drawer').getAttribute('aria-hidden'), 'false');
        assert.equal(await page.evaluate(() => document.activeElement && document.activeElement.id), 'drawer-close');
        await page.keyboard.press('Escape');
        assert.equal(await row.getAttribute('aria-expanded'), 'false');
        assert.equal(await page.locator('#term-drawer').getAttribute('aria-hidden'), 'true');
        assert.equal(await page.evaluate(() => document.activeElement === document.querySelector('#dict-table-body tr[data-interactive="true"]')), true);

        await page.setViewportSize({width:390,height:844});
        await page.reload({waitUntil:'load'});
        const overflow = await page.locator('.dp-tablewrap').evaluate(node => node.scrollWidth > node.clientWidth);
        assert.equal(overflow, true, 'mobile table must scroll horizontally');
        const mobileRow = page.locator('#dict-table-body tr[data-interactive="true"]').first();
        await mobileRow.press('Enter');
        const widths = await page.locator('#term-drawer').evaluate(node => ({drawer:node.getBoundingClientRect().width, viewport:window.innerWidth}));
        assert.ok(Math.abs(widths.drawer - widths.viewport) <= 1, 'mobile drawer must use viewport width');
        console.log('semantic glossary page runtime: PASS (filter toggle/aria-pressed/Enter/Escape/focus/aria-expanded/mobile overflow)');
      } finally { await browser.close(); }
    })().catch(error => { console.error(error.stack || error); process.exit(1); });
  `;
  const result = run(process.execPath, ['-e', program, htmlPath], {timeout:60000});
  assert.equal(result.status, 0, result.stderr || result.error);
  process.stdout.write(result.stdout);
  return true;
}
function project(name, inputPath, expectedStatus=0, registryPath=canonicalRegistry) {
  const output = path.join(tmp, name + '-page-data.json');
  const before = fs.readFileSync(inputPath);
  const result = run('python3', [projector, '--input', inputPath, '--registry', registryPath, '--output', output]);
  assert.equal(result.status, expectedStatus, result.stderr);
  assert.deepEqual(fs.readFileSync(inputPath), before, 'projection must not modify source YAML');
  assert.equal(fs.existsSync(output), expectedStatus === 0, 'failed projection must not create output');
  return {result, output, data:expectedStatus === 0 ? JSON.parse(fs.readFileSync(output, 'utf8')) : null};
}

try {
  const source = fs.readFileSync(template, 'utf8');
  assert.match(source, /<th>意味キー<\/th>[\s\S]*<th>日本語名<\/th>[\s\S]*<th>英語名<\/th>[\s\S]*<th>定義<\/th>[\s\S]*<th>適用範囲<\/th>[\s\S]*<th>分類<\/th>[\s\S]*<th>コード名<\/th>[\s\S]*<th>型名<\/th>[\s\S]*<th>DB名<\/th>[\s\S]*<th>API名<\/th>[\s\S]*<th>UI表示名<\/th>[\s\S]*<th>許容値<\/th>[\s\S]*<th>状態<\/th>[\s\S]*<th>備考<\/th>/);
  assert.doesNotMatch(source, /責任者|\bowner\b/);
  assert.match(source, /TOP<\/a> ／ \{\{ACTIVE_CATEGORY_LABEL\}\} ／/, 'template breadcrumb must resolve the middle segment from the active category label placeholder (改善課題1-35)');
  ['aliases','forbidden','representations','relations','examples','constraints','security','evidence'].forEach(group => assert.match(source, new RegExp("key:'" + group + "'")));
  assert.match(source, /'data-group':detail\.key/);
  assert.match(source, /event\.key === 'Enter' \|\| event\.key === ' '/);
  assert.match(source, /event\.key === 'Escape'/);
  assert.match(source, /trapDrawerFocus/);
  assert.match(source, /@media \(max-width:\s*760px\)/);
  assert.match(source, /overflow-x:\s*auto/);
  assert.doesNotMatch(source, /\.innerHTML\s*=/);
  const executableScripts = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.ok(executableScripts.length > 0, 'client script must exist');
  assert.doesNotThrow(() => new Function(executableScripts.at(-1)[1]), 'client script syntax');

  const sampleData = JSON.parse(fs.readFileSync(sampleFixture, 'utf8'));
  const sampleSource = fs.readFileSync(sampleHtml, 'utf8');
  assert.deepEqual(embedded(sampleSource), sampleData, 'real sample must embed the canonical C fixture');
  assert.equal(run('bash', [validator, sampleFixture]).status, 0, 'real sample fixture must validate');

  const pyYamlAvailable = run('python3', ['-c', 'import yaml']).status === 0
    || fs.existsSync(path.join(root, 'generation-engine/scripts/glossary/.venv/bin/python'));
  if (!pyYamlAvailable) {
    console.log('SKIP: PyYAML が無いため用語辞書の再生成・投影(YAML→ページデータ変換)検査のみを省略した。PyYAML に依存しない検査（テンプレート静的検査・legacy/semantic 検証・XSS 等）は続けて実行する。有効化するには `python3 -m pip install pyyaml` を実行すること。');
  }

  if (pyYamlAvailable) {
    const reproducedSampleDir = path.join(tmp, 'reproduced-real-sample');
    const reproducedSample = run('bash', [sampleRegenerator, reproducedSampleDir]);
    assert.equal(reproducedSample.status, 0, reproducedSample.stderr);
    assert.deepEqual(fs.readFileSync(path.join(reproducedSampleDir, '一覧/用語辞書/用語辞書.html')), fs.readFileSync(sampleHtml), 'real sample must be byte-identical to canonical builder output');
  }
  assert.equal(fs.existsSync(path.join(root, 'generation-engine/samples/用語辞書.html')), false, 'obsolete root-level glossary page must not exist');
  runtimeCheck(sampleHtml);

  const builtNew = build('new', base);
  assert.deepEqual(embedded(builtNew.html), base, 'new page-data semantic equality');
  assert.match(builtNew.html, /meaning-key/);
  assert.match(builtNew.html, /履歴/);

  if (pyYamlAvailable) {
    const explicitFixture = path.join(glossaryFixtures, 'valid-explicit-columns-glossary.yaml');
    const explicitProjectionProgram = [
      'import importlib.util, json, pathlib, sys, yaml',
      'projector_path, fixture_path = map(pathlib.Path, sys.argv[1:])',
      'spec = importlib.util.spec_from_file_location("semantic_glossary_projector", projector_path)',
      'module = importlib.util.module_from_spec(spec)',
      'spec.loader.exec_module(module)',
      'source = yaml.safe_load(fixture_path.read_text(encoding="utf-8"))',
      'page = {"pageKind":"glossary","generatedAt":"2026-08-02T00:00:00Z","title":source["title"],"description":"明示14列fixture","projectName":source["glossary_key"],"projectionVersion":module.PROJECTION_VERSION,"glossarySchemaVersion":source["schema_version"],"glossaryContentVersion":source["content_version"],"categories":list(module.CATEGORIES),"terms":[module.project_term(term) for term in source["terms"]]}',
      'print(json.dumps(page, ensure_ascii=False))'
    ].join(';');
    const explicitProjection = run(glossaryPython, ['-c', explicitProjectionProgram, projector, explicitFixture]);
    assert.equal(explicitProjection.status, 0, explicitProjection.stderr);
    const explicitPageData = JSON.parse(explicitProjection.stdout);
    assert.deepEqual(Object.keys(explicitPageData.terms[0]).slice(0, 14), ['key','term_ja','term_en','definition','scope','category','code_name','type_name','db_name','api_name','ui_label','allowed_values','status','notes']);
    assert.equal(explicitPageData.terms[0].db_name, 'order_status');
    assert.equal(explicitPageData.terms[0].api_name, 'orderStatus');
    const builtExplicit = build('explicit-fourteen-columns', explicitPageData);
    assert.equal(run('bash', [validator, builtExplicit.input]).status, 0, 'explicit 14-column projection must validate');
    assert.match(builtExplicit.html, /<th>DB名<\/th>[\s\S]*<th>API名<\/th>/);
    assert.deepEqual(embedded(builtExplicit.html), explicitPageData, 'explicit 14-column projection must survive the HTML build');
  }

  const builtLegacy = build('legacy', legacy);
  assert.deepEqual(embedded(builtLegacy.html), legacy, 'legacy page-data semantic equality');
  assert.match(builtLegacy.html, /未移行/);
  const legacyValidation = run('bash', [validator, builtLegacy.input]);
  assert.equal(legacyValidation.status, 0, legacyValidation.stderr);
  assert.match(legacyValidation.stderr, /^\[WARN\].*legacy.*次major/m, 'legacy acceptance must emit migration warning');
  const legacyUnknownRoot = structuredClone(legacy);
  legacyUnknownRoot.unknownRootKey = 'must-be-rejected';
  const legacyUnknownRootResult = run('bash', [validator, write('legacy-unknown-root.json', legacyUnknownRoot)]);
  assert.equal(legacyUnknownRootResult.status, 1, 'legacy glossary root keys outside the compatibility allowlist must be rejected');
  assert.match(legacyUnknownRootResult.stderr, /glossary page root key.*legacy.*unknownRootKey/);

  const semanticValidation = run('bash', [validator, builtNew.input]);
  assert.equal(semanticValidation.status, 0, semanticValidation.stderr);
  assert.doesNotMatch(semanticValidation.stderr, /^\[WARN\].*legacy/m, 'semantic page-data must not emit legacy warning');

  const validFixtureText = fs.readFileSync(path.join(glossaryFixtures, 'valid-glossary.yaml'), 'utf8');
  const richFixtureText = validFixtureText.replace(
    '    relations:\n      - type: has_identifier',
    '    forbidden_terms:\n      - {value: 顧客コード, reason: 識別子概念を用いるため, replacement_key: customer_id}\n    examples: [法人顧客]\n    counter_examples: [匿名閲覧者]\n    constraints: [顧客IDと概念を混同しない]\n    security_classification: internal\n    notes: ポータル投影確認\n    relations:\n      - type: has_identifier'
  );
  const richFixturePath = path.join(tmp, 'valid-rich-glossary.yaml');
  fs.writeFileSync(richFixturePath, richFixtureText);
  if (pyYamlAvailable) {
    project('projected-unapproved-semantic-drift', richFixturePath, 1);
    const projected = project('projected-valid', path.join(glossaryFixtures, 'valid-glossary.yaml'));
    assert.equal(projected.data.projectionVersion, '0.2');
    assert.equal(projected.data.glossarySchemaVersion, '1.0.0');
    assert.equal(projected.data.glossaryContentVersion, '2.0.0');
    assert.deepEqual(projected.data.terms[0].sourceRefs, ['docs/domain/customer.md#customer']);
    assert.equal(Object.prototype.hasOwnProperty.call(projected.data.terms[0], 'owner'), false);
    assert.equal(projected.data.terms[0].status, 'active');
    assert.equal(projected.data.terms[0].changeRef, 'changes/update_customer_from_proposal');
    assert.equal(projected.data.terms[0].aliases[0], 'お客様');
    assert.deepEqual(projected.data.terms[0].relations[0], {type:'has_identifier',targetKey:'customer_id'});
    assert.equal(run('bash', [validator, projected.output]).status, 0, 'projected page-data must validate');
    const projectedOut = path.join(tmp, 'projected-html');
    const projectedBuild = run('bash', [builder, projected.output, projectedOut, '--page', 'glossary']);
    assert.equal(projectedBuild.status, 0, projectedBuild.stderr);
    const projectedHtml = fs.readFileSync(path.join(projectedOut, '用語辞書.html'), 'utf8');
    const glossaryCategoryLabel = JSON.parse(fs.readFileSync(portalCatalog, 'utf8'))
      .categories.find(category => category.key === 'project').label;
    assert.match(
      projectedHtml,
      new RegExp('TOP</a> ／ ' + glossaryCategoryLabel + ' ／'),
      'built glossary page breadcrumb must resolve the "project" category label from portal-catalog.json (改善課題1-35)'
    );
    assert.match(projectedHtml, /<th>意味キー<\/th>[\s\S]*<th>DB名<\/th>[\s\S]*<th>API名<\/th>[\s\S]*<th>備考<\/th>/);
    assert.deepEqual(Object.keys(projected.data.terms[0]).slice(0, 14), ['key','term_ja','term_en','definition','scope','category','code_name','type_name','db_name','api_name','ui_label','allowed_values','status','notes']);
    ['aliases','forbidden','representations','relations','examples','constraints','security','evidence'].forEach(group => assert.match(projectedHtml, new RegExp("key:'" + group + "'")));
    runtimeCheck(path.join(projectedOut, '用語辞書.html'));
    const deterministicProjection = project('projected-valid-second', path.join(glossaryFixtures, 'valid-glossary.yaml'));
    assert.deepEqual(fs.readFileSync(deterministicProjection.output), fs.readFileSync(projected.output), 'projection must be deterministic');

    const raceOriginal = path.join(tmp, 'race-original.yaml');
    const raceReplacement = path.join(tmp, 'race-replacement.yaml');
    const raceOutput = path.join(tmp, 'race-output.json');
    fs.copyFileSync(path.join(glossaryFixtures, 'valid-glossary.yaml'), raceOriginal);
    fs.writeFileSync(
      raceReplacement,
      validFixtureText.replace('title: Commerce platform glossary', 'title: RACE_REPLACEMENT')
    );
    const racePython = glossaryPython;
    const raceWrapper = path.join(tmp, 'swap-original-before-validation.sh');
    fs.writeFileSync(raceWrapper, [
      '#!/usr/bin/env bash',
      'set -euo pipefail',
      'cp "$RACE_REPLACEMENT" "$RACE_ORIGINAL"',
      'exec "$REAL_PYTHON" "$@"',
      ''
    ].join('\n'));
    fs.chmodSync(raceWrapper, 0o700);
    const raceResult = run('python3', [projector, '--input', raceOriginal, '--registry', canonicalRegistry, '--output', raceOutput], {
      env: {...process.env, GLOSSARY_PYTHON:raceWrapper, REAL_PYTHON:racePython, RACE_ORIGINAL:raceOriginal, RACE_REPLACEMENT:raceReplacement}
    });
    assert.equal(raceResult.status, 0, raceResult.stderr);
    assert.equal(JSON.parse(fs.readFileSync(raceOutput, 'utf8')).title, 'Commerce platform glossary', 'projection must use the exact bytes passed to validation even when the original path changes');
    assert.match(fs.readFileSync(raceOriginal, 'utf8'), /title: RACE_REPLACEMENT/, 'race fixture must actually replace the original path');

    project('projected-invalid', path.join(glossaryFixtures, 'invalid-glossary.yaml'), 1);
    const preservedOutput = path.join(tmp, 'preserved-existing-page-data.json');
    const preservedBytes = Buffer.from('{"preserved":true}\n');
    fs.writeFileSync(preservedOutput, preservedBytes);
    const preservedFailure = run('python3', [projector, '--input', path.join(glossaryFixtures, 'invalid-glossary.yaml'), '--registry', canonicalRegistry, '--output', preservedOutput]);
    assert.equal(preservedFailure.status, 1, preservedFailure.stderr);
    assert.deepEqual(fs.readFileSync(preservedOutput), preservedBytes, 'failed projection must preserve existing output');
    project('projected-review-required', path.join(glossaryFixtures, 'valid-review-required-glossary.yaml'), 1);
    project('projected-unapproved', path.join(glossaryFixtures, 'valid-unapproved-glossary.yaml'), 1);
    project('projected-self-claimed-publication', path.join(glossaryFixtures, 'invalid-publication-self-claim-glossary.yaml'), 1);
    project('projected-warning-without-attestations', path.join(glossaryFixtures, 'valid-warning-glossary.yaml'), 1);
    project('projected-proposal', path.join(glossaryFixtures, 'valid-proposal.yaml'), 1);
    project('projected-change', path.join(glossaryFixtures, 'valid-change.yaml'), 1);
    const versionMismatch = fs.readFileSync(path.join(glossaryFixtures, 'valid-glossary.yaml'), 'utf8').replace('schema_version: 1.0.0', 'schema_version: 0.9.0');
    const versionMismatchPath = path.join(tmp, 'version-mismatch.yaml');
    fs.writeFileSync(versionMismatchPath, versionMismatch);
    project('projected-version-mismatch', versionMismatchPath, 1);
  }
  const omittedRegistryOutput = path.join(tmp, 'omitted-registry-page-data.json');
  const omittedRegistry = run('python3', [projector, '--input', richFixturePath, '--output', omittedRegistryOutput]);
  assert.equal(omittedRegistry.status, 2, 'projector must require a canonical registry');
  assert.equal(fs.existsSync(omittedRegistryOutput), false);
  if (pyYamlAvailable) {
    const retiredRegistry = path.join(tmp, 'retired-registry');
    fs.cpSync(canonicalRegistry, retiredRegistry, {recursive:true});
    fs.copyFileSync(path.join(glossaryFixtures, 'valid-retire-change.yaml'), path.join(retiredRegistry, 'retire-customer-change.yaml'));
    project(
      'projected-retired',
      path.join(glossaryFixtures, 'valid-lifecycle-applied-glossary.yaml'),
      1,
      retiredRegistry
    );
  }

  const missingOutput = path.join(tmp, 'missing-input-output.json');
  const missingResult = run('python3', [projector, '--input', path.join(tmp, 'missing.yaml'), '--registry', canonicalRegistry, '--output', missingOutput]);
  assert.equal(missingResult.status, 2, missingResult.stderr);
  assert.equal(fs.existsSync(missingOutput), false, 'exit 2 must not create output');

  const mixed = {...base, terms:[newTerms[0], legacy.terms[0]]};
  const mixedResult = run('bash', [validator, write('mixed.json', mixed)]);
  assert.equal(mixedResult.status, 1, 'mixed terms must be rejected');
  assert.match(mixedResult.stderr, /新旧混在/);

  const candidate = {...base, proposals:[]};
  const candidateResult = run('bash', [validator, write('candidate.json', candidate)]);
  assert.equal(candidateResult.status, 1, 'candidate slots must be rejected');

  for (const key of ['proposalAudit','reviewers','approval','confidence','observations','unknownRootKey']) {
    const rootAttack = structuredClone(base);
    rootAttack[key] = key === 'proposalAudit' ? {secret:'must-not-reach-html'} : [];
    const rootAttackResult = run('bash', [validator, write(`root-attack-${key}.json`, rootAttack)]);
    assert.equal(rootAttackResult.status, 1, `semantic glossary root key ${key} must be rejected`);
    assert.match(rootAttackResult.stderr, /glossary.*root.*key|glossary候補分離/);
  }

  const auditAttack = structuredClone(base);
  auditAttack.proposalAudit = {secret:'must-not-reach-html'};
  const auditAttackInput = write('root-attack-proposal-audit-build.json', auditAttack);
  const absentAttackOut = path.join(tmp, 'root-attack-new-output');
  const absentAttackBuild = run('bash', [builder, auditAttackInput, absentAttackOut, '--page', 'glossary']);
  assert.equal(absentAttackBuild.status, 1, 'builder must reject proposalAudit before HTML generation');
  assert.equal(fs.existsSync(path.join(absentAttackOut, '用語辞書.html')), false, 'rejected proposalAudit must not generate HTML');
  const preservedAttackOut = path.join(tmp, 'root-attack-preserved-output');
  const preservedAttackHtml = path.join(preservedAttackOut, '用語辞書.html');
  const preservedAttackBytes = Buffer.from('<!doctype html><p>preserved-existing-output</p>\n');
  fs.mkdirSync(preservedAttackOut, {recursive:true});
  fs.writeFileSync(preservedAttackHtml, preservedAttackBytes);
  const preservedAttackBuild = run('bash', [builder, auditAttackInput, preservedAttackOut, '--page', 'glossary']);
  assert.equal(preservedAttackBuild.status, 1, 'builder must reject proposalAudit when output already exists');
  assert.deepEqual(fs.readFileSync(preservedAttackHtml), preservedAttackBytes, 'failed builder must preserve existing HTML bytes');
  assert.doesNotMatch(fs.readFileSync(preservedAttackHtml, 'utf8'), /must-not-reach-html/);

  const nestedCandidate = structuredClone(base);
  nestedCandidate.terms[0].observations = [{source:'reverse-analysis'}];
  nestedCandidate.terms[0].relations = [{type:'related_to',targetKey:'customer_id',analysis:{approval:{status:'detected'},confidence:{score:0.7},detected_by:{skill:'reverse'},reviewers:[{role:'business'}]}}];
  const nestedCandidateResult = run('bash', [validator, write('nested-candidate.json', nestedCandidate)]);
  assert.equal(nestedCandidateResult.status, 1, 'candidate-only keys nested in semantic terms must be rejected');
  assert.match(nestedCandidateResult.stderr, /候補専用key.*(observations|approval|confidence|detected_by|reviewers)/);

  const nestedUnknownAttacks = [
    ['categories', value => { value.categories[0].candidatePayload = {status:'detected'}; }],
    ['scope', value => { value.terms[0].scope = {level:'application',includes:['portal'],excludes:[],candidatePayload:{status:'detected'}}; }],
    ['representations', value => { value.terms[0].representations[0].candidatePayload = {status:'detected'}; }],
    ['forbiddenTerms', value => { value.terms[0].forbiddenTerms[0].candidatePayload = {status:'detected'}; }],
    ['relations', value => { value.terms[0].relations = [{type:'related_to',targetKey:'customer_id',candidatePayload:{status:'detected'}}]; }],
    ['unresolved', value => { value.unresolved = [{label:'候補',reason:'未承認',candidatePayload:{status:'detected'}}]; }],
    ['diagnostics', value => { value.diagnostics = {missingSource:{count:0,total:1,ratio:0,threshold:0,warning:false,candidatePayload:{status:'detected'}}}; }]
  ];
  for (const [name, mutate] of nestedUnknownAttacks) {
    const value = structuredClone(base);
    mutate(value);
    const result = run('bash', [validator, write(`nested-unknown-${name}.json`, value)]);
    assert.equal(result.status, 1, `${name} nested candidatePayload must be rejected`);
    assert.match(result.stderr, /semantic nested key.*candidatePayload/, `${name} must identify the unknown nested key`);
  }

  const unknownRoot = structuredClone(base);
  unknownRoot.terms[0].reviewers = [{role:'business',actor:'domain-reviewer'}];
  const unknownRootResult = run('bash', [validator, write('unknown-root.json', unknownRoot)]);
  assert.equal(unknownRootResult.status, 1, 'semantic term root keys outside projection v0.1 allowlist must be rejected');
  assert.match(unknownRootResult.stderr, /semantic root key.*reviewers/);

  const badVersion = {...base, projectionVersion:'0.3'};
  const badVersionResult = run('bash', [validator, write('bad-version.json', badVersion)]);
  assert.equal(badVersionResult.status, 1, 'unsupported projection version must be rejected');

  const invalidTerm = {...base, terms:[{definition:'legacyにもsemanticにも分類できない'}]};
  const invalidTermResult = run('bash', [validator, write('invalid-term.json', invalidTerm)]);
  assert.equal(invalidTermResult.status, 1, 'every term must classify as legacy or semantic');
  assert.match(invalidTermResult.stderr, /未分類|invalid/);

  const emptyBadRoot = {...base, projectionVersion:'0.3', terms:[]};
  const emptyBadRootResult = run('bash', [validator, write('empty-bad-root.json', emptyBadRoot)]);
  assert.equal(emptyBadRootResult.status, 1, 'semantic root must be validated when terms is empty');

  const badOptionalType = structuredClone(base);
  badOptionalType.terms[0].aliases = '取引先';
  const badOptionalTypeResult = run('bash', [validator, write('bad-optional-type.json', badOptionalType)]);
  assert.equal(badOptionalTypeResult.status, 1, 'optional semantic field types must be validated');

  const attack = '</script><script>globalThis.__xss = true</script>\u2028line\u2029paragraph';
  const xss = structuredClone(base);
  xss.terms[0].definition = attack;
  const builtXss = build('xss', xss);
  assert.doesNotMatch(builtXss.html, /<script>globalThis\.__xss/);
  assert.match(builtXss.html, /\\u003c\/script>/);
  assert.match(builtXss.html, /\\u2028/);
  assert.match(builtXss.html, /\\u2029/);
  assert.deepEqual(embedded(builtXss.html), xss, 'escaped JSON retains semantic equality');

  console.log('semantic glossary page static: PASS (projection/validation/legacy/XSS/UI contracts)');
} finally {
  fs.rmSync(tmp, {recursive:true, force:true});
}

// 第1層の集約(run-layer-machine-checks.sh)のcount_cases()は「self-test: <N> PASS」
// 形式の要約行を読み取る。上記2件(runtime/static)のPASSは個別の説明文であり
// この形式に一致しないため、ここまで到達した(=両方の検査を例外なく完走した)ことを
// もって機械可読な要約行を1本追加する。個別内訳は上記2行が既に担う。
console.log('self-test: 2 PASS, 0 FAIL');

module.exports = {base};
