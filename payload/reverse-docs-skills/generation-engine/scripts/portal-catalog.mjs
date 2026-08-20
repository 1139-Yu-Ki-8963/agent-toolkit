#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const KEY_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ROOT_KEY_RE = /^[a-z][a-zA-Z0-9]*$/;
const CATEGORY_KEYS = new Set(["key", "label", "group", "icon", "sub", "blueprints"]);
const BLUEPRINT_KEYS = new Set(["kind", "label", "icon", "desc", "dir", "generator", "unit", "countFormat", "group", "disabledWhenEmpty", "discovery", "status"]);
const DISCOVERY_KEYS = new Set([
  "artifactType", "root", "roots", "glob", "matchKind", "titleSource", "dirSource",
  "instanceKeySource", "sort", "embeddedScriptId", "countJsonPointer",
]);

function fail(message) {
  throw new Error(message);
}

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`);
}

function assertExactKeys(value, allowed, required, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(`${label} has unknown key: ${key}`);
  }
  for (const key of required) {
    if (!(key in value)) fail(`${label} is missing key: ${key}`);
  }
}

function assertString(value, label, allowEmpty = false) {
  if (typeof value !== "string" || (!allowEmpty && value.length === 0)) fail(`${label} must be a ${allowEmpty ? "" : "non-empty "}string`);
}

function validateDefaultRoots(value) {
  assertObject(value, "catalog.defaultRoots");
  for (const [key, rootValue] of Object.entries(value)) {
    if (!ROOT_KEY_RE.test(key)) fail(`catalog.defaultRoots has invalid key: ${key}`);
    assertString(rootValue, `catalog.defaultRoots.${key}`);
    if (path.posix.isAbsolute(rootValue) || rootValue.split("/").includes("..")) {
      fail(`catalog.defaultRoots.${key} must be a safe relative path`);
    }
  }
}

function isUnsafeRoot(root) {
  const normalized = root.replaceAll("\\", "/");
  return path.posix.isAbsolute(normalized)
    || path.win32.isAbsolute(root)
    || /^[A-Za-z]:/.test(root)
    || normalized.split("/").includes("..");
}

function validateDiscoveryRoots(value, label) {
  if (!Array.isArray(value) || value.length === 0) fail(`${label} must be a non-empty array`);
  const seen = new Set();
  for (const [index, root] of value.entries()) {
    assertString(root, `${label}[${index}]`);
    if (root !== "output-dir" && isUnsafeRoot(root)) {
      fail(`${label}[${index}] must be output-dir or a safe relative path`);
    }
    if (seen.has(root)) fail(`${label} has a duplicate root: ${root}`);
    seen.add(root);
  }
}

function validateDiscoveryMergePolicy(value) {
  assertObject(value, "catalog.discoveryMergePolicy");
  assertExactKeys(
    value,
    new Set(["order", "duplicateInstanceKey"]),
    ["order", "duplicateInstanceKey"],
    "catalog.discoveryMergePolicy",
  );
  if (value.order !== "root-declaration-then-relative-path-bytewise") {
    fail("catalog.discoveryMergePolicy.order is invalid");
  }
  if (value.duplicateInstanceKey !== "first-root-wins") {
    fail("catalog.discoveryMergePolicy.duplicateInstanceKey is invalid");
  }
}

function resolveDefaultRootPrefix(value, defaultRoots, outputLayout) {
  if (!outputLayout) return value;
  for (const [key, prefix] of Object.entries(defaultRoots || {})) {
    if (value === prefix || value.startsWith(`${prefix}/`)) {
      const override = outputLayout[key];
      if (typeof override === "string" && override.length > 0) {
        return override + value.slice(prefix.length);
      }
      return value;
    }
  }
  return value;
}

export function validateCatalog(catalog) {
  assertObject(catalog, "catalog");
  assertExactKeys(catalog, new Set(["schemaVersion", "categories", "defaultRoots", "discoveryRoots", "discoveryMergePolicy"]), ["schemaVersion", "categories"], "catalog");
  if (catalog.schemaVersion !== 1) fail("catalog.schemaVersion must be 1");
  if ("defaultRoots" in catalog) validateDefaultRoots(catalog.defaultRoots);
  if ("discoveryRoots" in catalog) validateDiscoveryRoots(catalog.discoveryRoots, "catalog.discoveryRoots");
  if ("discoveryMergePolicy" in catalog) validateDiscoveryMergePolicy(catalog.discoveryMergePolicy);
  if (!Array.isArray(catalog.categories)) fail("catalog.categories must be an array");
  const categoryKeys = new Set();
  const artifactTypes = new Set();
  for (const [categoryIndex, category] of catalog.categories.entries()) {
    const categoryLabel = `categories[${categoryIndex}]`;
    assertObject(category, categoryLabel);
    assertExactKeys(category, CATEGORY_KEYS, [...CATEGORY_KEYS], categoryLabel);
    for (const key of ["key", "label", "group", "icon", "sub"]) assertString(category[key], `${categoryLabel}.${key}`);
    if (!KEY_RE.test(category.key)) fail(`${categoryLabel}.key must be lower kebab case`);
    if (categoryKeys.has(category.key)) fail(`duplicate category key: ${category.key}`);
    categoryKeys.add(category.key);
    if (!Array.isArray(category.blueprints)) fail(`${categoryLabel}.blueprints must be an array`);
    const kinds = new Set();
    for (const [blueprintIndex, blueprint] of category.blueprints.entries()) {
      const blueprintLabel = `${categoryLabel}.blueprints[${blueprintIndex}]`;
      assertObject(blueprint, blueprintLabel);
      assertExactKeys(
        blueprint,
        BLUEPRINT_KEYS,
        ["kind", "label", "icon", "desc", "dir", "generator", "unit", "countFormat", "discovery"],
        blueprintLabel,
      );
      for (const key of ["kind", "label", "icon", "desc", "generator", "unit", "countFormat"]) {
        assertString(blueprint[key], `${blueprintLabel}.${key}`);
      }
      assertString(blueprint.dir, `${blueprintLabel}.dir`, true);
      if (!KEY_RE.test(blueprint.kind)) fail(`${blueprintLabel}.kind must be lower kebab case`);
      if (kinds.has(blueprint.kind)) fail(`duplicate kind in ${category.key}: ${blueprint.kind}`);
      kinds.add(blueprint.kind);
      if ("group" in blueprint) assertString(blueprint.group, `${blueprintLabel}.group`);
      if ("disabledWhenEmpty" in blueprint && typeof blueprint.disabledWhenEmpty !== "boolean") {
        fail(`${blueprintLabel}.disabledWhenEmpty must be a boolean`);
      }
      if ("status" in blueprint) assertString(blueprint.status, `${blueprintLabel}.status`);
      if (!["unit-count", "detail"].includes(blueprint.countFormat)) fail(`${blueprintLabel}.countFormat is invalid`);
      const discovery = blueprint.discovery;
      assertObject(discovery, `${blueprintLabel}.discovery`);
      const countKeys = ["embeddedScriptId", "countJsonPointer"];
      const requiredDiscovery = ["artifactType", "root", "glob", "matchKind", "titleSource", "dirSource", "instanceKeySource", "sort"];
      assertExactKeys(discovery, DISCOVERY_KEYS, requiredDiscovery, `${blueprintLabel}.discovery`);
      for (const key of requiredDiscovery) assertString(discovery[key], `${blueprintLabel}.discovery.${key}`);
      if (!KEY_RE.test(discovery.artifactType)) fail(`${blueprintLabel}.discovery.artifactType must be lower kebab case`);
      if (artifactTypes.has(discovery.artifactType)) fail(`duplicate artifactType: ${discovery.artifactType}`);
      artifactTypes.add(discovery.artifactType);
      if (discovery.root !== "output-dir" && isUnsafeRoot(discovery.root)) {
        fail(`${blueprintLabel}.discovery.root must be output-dir or a safe relative path`);
      }
      if ("roots" in discovery) validateDiscoveryRoots(discovery.roots, `${blueprintLabel}.discovery.roots`);
      if (path.posix.isAbsolute(discovery.glob) || discovery.glob.split("/").includes("..")) fail(`${blueprintLabel}.discovery.glob must be a safe relative path`);
      if (discovery.matchKind !== "file") fail(`${blueprintLabel}.discovery.matchKind must be file`);
      if (!["blueprint-label", "html-h1", "markdown-h1"].includes(discovery.titleSource)) fail(`${blueprintLabel}.discovery.titleSource is invalid`);
      if (!["blueprint", "match-parent"].includes(discovery.dirSource)) fail(`${blueprintLabel}.discovery.dirSource is invalid`);
      if (discovery.instanceKeySource !== "relative-path") fail(`${blueprintLabel}.discovery.instanceKeySource must be relative-path`);
      if (discovery.sort !== "relative-path-bytewise") fail(`${blueprintLabel}.discovery.sort must be relative-path-bytewise`);
      const presentCountKeys = countKeys.filter((key) => key in discovery);
      if (blueprint.countFormat === "unit-count" && presentCountKeys.length !== 2) fail(`${blueprintLabel}.discovery requires both count keys`);
      if (blueprint.countFormat === "detail" && presentCountKeys.length !== 0) fail(`${blueprintLabel}.discovery forbids count keys`);
      for (const key of presentCountKeys) assertString(discovery[key], `${blueprintLabel}.discovery.${key}`);
    }
    if (category.blueprints.length >= 4) {
      const withoutGroup = category.blueprints.filter((blueprint) => !("group" in blueprint) || blueprint.group.length === 0);
      if (withoutGroup.length > 0) fail(`${categoryLabel} has 4 or more blueprints, so every blueprint requires a non-empty group`);
    }
    discoveryRootOrderForCategory(catalog, category);
  }
  return catalog;
}

function decodeEntities(value) {
  return value
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", "\"")
    .replaceAll("&#39;", "'")
    .replaceAll("&#x27;", "'")
    .replaceAll("&amp;", "&");
}

function globRegex(glob) {
  let out = "^";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    if (char === "*" && glob[index + 1] === "*") {
      if (glob[index + 2] === "/") {
        out += "(?:.*/)?";
        index += 2;
      } else {
        out += ".*";
        index += 1;
      }
    } else if (char === "*") {
      out += "[^/]*";
    } else if (char === "?") {
      out += "[^/]";
    } else {
      out += char.replace(/[\\^$.[\]{}()+|]/g, "\\$&");
    }
  }
  return new RegExp(`${out}$`);
}

function bytewise(a, b) {
  return Buffer.from(a).compare(Buffer.from(b));
}

function walkFiles(root) {
  const files = [];
  function walk(current, relative) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      const childRelative = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isSymbolicLink()) fail(`symbolic link is not allowed: ${childRelative}`);
      if (entry.isDirectory()) walk(absolute, childRelative);
      else if (entry.isFile()) files.push(childRelative);
      else fail(`non-regular artifact is not allowed: ${childRelative}`);
    }
  }
  walk(root, "");
  return files.sort(bytewise);
}

function discoveryRootsFor(catalog, discovery) {
  return discovery.roots || catalog.discoveryRoots || [discovery.root];
}

function discoveryRootOrderForCategory(catalog, category) {
  const declarations = [];
  if (catalog.discoveryRoots) declarations.push(catalog.discoveryRoots);
  for (const blueprint of category.blueprints) {
    declarations.push(discoveryRootsFor(catalog, blueprint.discovery));
  }
  const roots = [];
  const edges = new Map();
  const indegree = new Map();
  for (const declaration of declarations) {
    for (const root of declaration) {
      if (!indegree.has(root)) {
        roots.push(root);
        edges.set(root, new Set());
        indegree.set(root, 0);
      }
    }
    for (let index = 1; index < declaration.length; index += 1) {
      const before = declaration[index - 1];
      const after = declaration[index];
      if (!edges.get(before).has(after)) {
        edges.get(before).add(after);
        indegree.set(after, indegree.get(after) + 1);
      }
    }
  }
  const remaining = new Set(roots);
  const order = [];
  while (remaining.size > 0) {
    const next = roots.find((root) => remaining.has(root) && indegree.get(root) === 0);
    if (!next) fail(`category ${category.key} has conflicting discovery root order`);
    remaining.delete(next);
    order.push(next);
    for (const after of edges.get(next)) indegree.set(after, indegree.get(after) - 1);
  }
  return order;
}

function resolveDiscoveryRoot(outputRoot, declaredRoot) {
  const resolved = declaredRoot === "output-dir" ? outputRoot : path.resolve(outputRoot, declaredRoot);
  if (resolved !== outputRoot && !resolved.startsWith(`${outputRoot}${path.sep}`)) {
    fail(`discovery root escapes output root: ${declaredRoot}`);
  }
  if (!fs.existsSync(resolved)) {
    fail(`discovery root is not a directory: ${declaredRoot}`);
  }
  const stats = fs.lstatSync(resolved);
  if (stats.isSymbolicLink()) fail(`discovery root must not be a symbolic link: ${declaredRoot}`);
  if (!stats.isDirectory()) fail(`discovery root is not a directory: ${declaredRoot}`);
  const realOutputRoot = fs.realpathSync(outputRoot);
  const realResolved = fs.realpathSync(resolved);
  if (realResolved !== realOutputRoot && !realResolved.startsWith(`${realOutputRoot}${path.sep}`)) {
    fail(`discovery root escapes output root: ${declaredRoot}`);
  }
  return resolved;
}

function titleFromArtifact(source, content, fallback) {
  if (source === "blueprint-label") return fallback;
  if (source === "html-h1") {
    const match = content.match(/<h1(?:\s[^>]*)?>([\s\S]*?)<\/h1>/i);
    if (!match) fail("HTML artifact has no h1");
    const title = decodeEntities(match[1].replace(/<[^>]+>/g, "").trim());
    if (!title) fail("HTML artifact has an empty h1");
    return title;
  }
  const match = content.replace(/^\uFEFF/, "").match(/^#\s+(.+)$/m);
  if (!match || !match[1].trim()) fail("Markdown artifact has no h1");
  return match[1].trim();
}

function jsonPointer(value, pointer) {
  if (pointer === "") return value;
  if (!pointer.startsWith("/")) fail(`invalid JSON pointer: ${pointer}`);
  let current = value;
  for (const token of pointer.slice(1).split("/").map((part) => part.replaceAll("~1", "/").replaceAll("~0", "~"))) {
    if (current === null || typeof current !== "object" || !(token in current)) fail(`JSON pointer does not exist: ${pointer}`);
    current = current[token];
  }
  return current;
}

function extractEmbeddedJson(content, id) {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(`<script(?=[^>]*type=["']application/json["'])(?=[^>]*id=["']${escaped}["'])[^>]*>([\\s\\S]*?)<\\/script>`, "gi");
  const matches = [...content.matchAll(regex)];
  if (matches.length !== 1) fail(`expected exactly one application/json script#${id}, got ${matches.length}`);
  try {
    return JSON.parse(decodeEntities(matches[0][1]));
  } catch (error) {
    fail(`invalid JSON in script#${id}: ${error.message}`);
  }
}

export function renderCatalog(catalog, outputRoot, portalDir, outputLayout = null) {
  validateCatalog(catalog);
  const root = path.resolve(outputRoot);
  const portal = path.resolve(portalDir);
  if (!fs.statSync(root).isDirectory()) fail(`output root is not a directory: ${outputRoot}`);
  const claimed = new Map();
  const instanceKeys = new Set();
  const filesByRoot = new Map();
  const categories = [];
  const kinds = [];
  for (const category of catalog.categories) {
    const tools = [];
    const entries = [];
    const categoryRoots = discoveryRootOrderForCategory(catalog, category);
    const categoryRootOrder = new Map(categoryRoots.map((declaredRoot, index) => [declaredRoot, index]));
    const hasMultipleRoots = categoryRoots.length > 1;
    for (const [blueprintIndex, blueprint] of category.blueprints.entries()) {
      const effectiveGlob = resolveDefaultRootPrefix(blueprint.discovery.glob, catalog.defaultRoots, outputLayout);
      const matcher = globRegex(effectiveGlob);
      const matches = [];
      const discoveryRoots = discoveryRootsFor(catalog, blueprint.discovery);
      for (const declaredRoot of discoveryRoots) {
        const rootIndex = categoryRootOrder.get(declaredRoot);
        const discoveryRoot = resolveDiscoveryRoot(root, declaredRoot);
        if (!filesByRoot.has(discoveryRoot)) filesByRoot.set(discoveryRoot, walkFiles(discoveryRoot));
        for (const relative of filesByRoot.get(discoveryRoot).filter((file) => matcher.test(file))) {
          matches.push({ rootIndex, declaredRoot, discoveryRoot, relative, blueprint, blueprintIndex });
        }
      }
      matches.sort((a, b) => a.rootIndex - b.rootIndex || bytewise(a.relative, b.relative));
      for (const match of matches) entries.push({ type: "match", ...match });
      if (matches.length === 0 && blueprint.disabledWhenEmpty === true) {
        entries.push({ type: "disabled", blueprint, blueprintIndex });
      }
    }
    let orderedEntries = entries;
    if (hasMultipleRoots) {
      const orderedMatches = entries
        .filter((entry) => entry.type === "match")
        .sort((a, b) => a.rootIndex - b.rootIndex
          || bytewise(a.relative, b.relative)
          || a.blueprintIndex - b.blueprintIndex);
      let matchIndex = 0;
      orderedEntries = entries.map((entry) => (
        entry.type === "disabled" ? entry : orderedMatches[matchIndex++]
      ));
    }
    const acceptedTools = new Map();
    for (const entry of orderedEntries) {
      const { blueprint } = entry;
      if (entry.type === "disabled") {
        const tool = {
          title: blueprint.label,
          icon: blueprint.icon,
          href: null,
          desc: blueprint.desc,
          count: "該当なし",
          disabled: true,
        };
        if ("group" in blueprint) tool.group = blueprint.group;
        if ("status" in blueprint) tool.status = blueprint.status;
        tools.push(tool);
        continue;
      }
      const { discoveryRoot, relative } = entry;
      if (instanceKeys.has(relative)) continue;
      const artifactIdentity = `${discoveryRoot}\u0000${relative}`;
      if (claimed.has(artifactIdentity)) {
        fail(`artifact matches multiple blueprints: ${relative} (${claimed.get(artifactIdentity)}, ${blueprint.discovery.artifactType})`);
      }
      claimed.set(artifactIdentity, blueprint.discovery.artifactType);
      instanceKeys.add(relative);
      const absolute = path.resolve(discoveryRoot, relative);
      if (absolute !== discoveryRoot && !absolute.startsWith(`${discoveryRoot}${path.sep}`)) fail(`artifact escapes discovery root: ${relative}`);
      const content = fs.readFileSync(absolute, "utf8");
      const title = titleFromArtifact(blueprint.discovery.titleSource, content, blueprint.label);
      let count = "詳細を見る";
      if (blueprint.countFormat === "unit-count") {
        const data = extractEmbeddedJson(content, blueprint.discovery.embeddedScriptId);
        const items = jsonPointer(data, blueprint.discovery.countJsonPointer);
        if (!Array.isArray(items)) fail(`${blueprint.discovery.countJsonPointer} must point to an array in ${relative}`);
        count = `${items.length} ${blueprint.unit} →`;
      }
      const hrefRelative = path.relative(portal, absolute).split(path.sep).join("/");
      const tool = {
        title,
        icon: blueprint.icon,
        href: hrefRelative.startsWith(".") ? hrefRelative : `./${hrefRelative}`,
        desc: blueprint.desc,
        count,
      };
      if ("group" in blueprint) tool.group = blueprint.group;
      if ("status" in blueprint) tool.status = blueprint.status;
      tools.push(tool);
      if (!acceptedTools.has(entry.blueprintIndex)) acceptedTools.set(entry.blueprintIndex, []);
      acceptedTools.get(entry.blueprintIndex).push(tool);
    }
    for (const [blueprintIndex, blueprint] of category.blueprints.entries()) {
      const blueprintTools = acceptedTools.get(blueprintIndex) || [];
      if (blueprintTools.length > 0 && blueprint.countFormat === "unit-count") {
        const tool = blueprintTools.at(-1);
        kinds.push({
          kind: blueprint.kind,
          label: blueprint.label.replace(/一覧$/, ""),
          count: Number(tool.count.split(" ", 1)[0]),
          unit: blueprint.unit,
          href: tool.href,
        });
      }
    }
    const renderedCategory = {
      id: category.key,
      group: category.group,
      title: category.label,
      icon: category.icon,
      sub: category.sub,
      tools,
    };
    if (tools.length === 0) {
      renderedCategory.empty = {
        title: "生成済み資料はありません",
        desc: `${category.label}の資料はまだ生成されていません。`,
        count: "0 件",
      };
    }
    categories.push(renderedCategory);
  }
  return { categories, kinds };
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`cannot read JSON ${file}: ${error.message}`);
  }
}

function extractCategoriesFromHtml(file) {
  const content = fs.readFileSync(file, "utf8");
  return extractEmbeddedJson(content, "portal-categories");
}

function readOutputLayout(file) {
  if (!file) return null;
  const json = readJson(file);
  if (!json || typeof json !== "object" || typeof json.layout !== "object" || json.layout === null) {
    fail(`output-layout JSON must have a layout object: ${file}`);
  }
  return json.layout;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith("--")) fail(`unexpected argument: ${key}`);
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) fail(`missing value for ${key}`);
    args[key.slice(2)] = value;
    index += 1;
  }
  return args;
}

function selfTestCatalog(discoveryRoots = null, glob = "**/*.html") {
  const discovery = {
    artifactType: "self-test-page",
    root: "output-dir",
    glob,
    matchKind: "file",
    titleSource: "html-h1",
    dirSource: "match-parent",
    instanceKeySource: "relative-path",
    sort: "relative-path-bytewise",
  };
  const catalog = {
    schemaVersion: 1,
    categories: [{
      key: "self-test",
      label: "Self test",
      group: "Self test",
      icon: "science",
      sub: "Portal catalog self-test fixture",
      blueprints: [{
        kind: "self-test-page",
        label: "Self test page",
        icon: "science",
        desc: "Self-test fixture.",
        dir: "",
        generator: "portal-catalog-self-test",
        unit: "件",
        countFormat: "detail",
        discovery,
      }],
    }],
  };
  if (discoveryRoots !== null) {
    catalog.discoveryRoots = discoveryRoots;
    catalog.discoveryMergePolicy = {
      order: "root-declaration-then-relative-path-bytewise",
      duplicateInstanceKey: "first-root-wins",
    };
  }
  return catalog;
}

function writeSelfTestArtifact(root, relative, title) {
  const file = path.join(root, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `<!doctype html><h1>${title}</h1>\n`, "utf8");
}

function selfTestTitles(catalog, outputRoot) {
  return renderCatalog(catalog, outputRoot, path.join(outputRoot, "portal"))
    .categories[0].tools.map((tool) => tool.title);
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(process.cwd(), ".portal-catalog-self-test-"));
  const check = (name, callback) => {
    callback();
    process.stdout.write(`PASS: ${name}\n`);
  };
  try {
    check("two roots discover documents from both", () => {
      const root = path.join(tempRoot, "two-roots");
      writeSelfTestArtifact(root, "first/alpha.html", "First root");
      writeSelfTestArtifact(root, "second/beta.html", "Second root");
      assert.deepStrictEqual(
        selfTestTitles(selfTestCatalog(["first", "second"]), root),
        ["First root", "Second root"],
      );
    });

    check("one root matches legacy v1 output", () => {
      const root = path.join(tempRoot, "legacy");
      writeSelfTestArtifact(root, "documents/legacy.html", "Legacy document");
      const legacy = selfTestTitles(selfTestCatalog(null, "documents/**/*.html"), root);
      const oneRoot = selfTestTitles(selfTestCatalog(["output-dir"], "documents/**/*.html"), root);
      assert.deepStrictEqual(oneRoot, legacy);
    });

    check("adding a declared root adds its document", () => {
      const root = path.join(tempRoot, "append-root");
      writeSelfTestArtifact(root, "first/one.html", "First document");
      writeSelfTestArtifact(root, "second/two.html", "Second document");
      writeSelfTestArtifact(root, "third/three.html", "Third document");
      const catalog = selfTestCatalog(["first", "second"]);
      catalog.discoveryRoots.push("third");
      assert.deepStrictEqual(
        selfTestTitles(catalog, root),
        ["First document", "Second document", "Third document"],
      );
    });

    check("duplicate instance key keeps first root", () => {
      const root = path.join(tempRoot, "duplicate");
      writeSelfTestArtifact(root, "first/shared.html", "First root wins");
      writeSelfTestArtifact(root, "second/shared.html", "Second root loses");
      const catalog = selfTestCatalog(["first", "second"]);
      const overlappingBlueprint = structuredClone(catalog.categories[0].blueprints[0]);
      overlappingBlueprint.kind = "overlapping-self-test-page";
      overlappingBlueprint.discovery.artifactType = "overlapping-self-test-page";
      catalog.categories[0].blueprints.push(overlappingBlueprint);
      assert.deepStrictEqual(
        selfTestTitles(catalog, root),
        ["First root wins"],
      );
    });

    check("one root keeps the first overlapping blueprint", () => {
      const root = path.join(tempRoot, "legacy-overlap");
      writeSelfTestArtifact(root, "shared.html", "Legacy first blueprint");
      const catalog = selfTestCatalog(["output-dir"]);
      const overlappingBlueprint = structuredClone(catalog.categories[0].blueprints[0]);
      overlappingBlueprint.kind = "legacy-overlapping-self-test-page";
      overlappingBlueprint.discovery.artifactType = "legacy-overlapping-self-test-page";
      catalog.categories[0].blueprints.push(overlappingBlueprint);
      assert.deepStrictEqual(
        selfTestTitles(catalog, root),
        ["Legacy first blueprint"],
      );
    });

    check("root order applies across blueprints", () => {
      const root = path.join(tempRoot, "cross-blueprint-order");
      writeSelfTestArtifact(root, "first/b.html", "First root b");
      writeSelfTestArtifact(root, "second/a.html", "Second root a");
      const catalog = selfTestCatalog(["first", "second"], "a.html");
      const secondBlueprint = structuredClone(catalog.categories[0].blueprints[0]);
      secondBlueprint.kind = "second-self-test-page";
      secondBlueprint.discovery.artifactType = "second-self-test-page";
      secondBlueprint.discovery.glob = "b.html";
      catalog.categories[0].blueprints.push(secondBlueprint);
      assert.deepStrictEqual(
        selfTestTitles(catalog, root),
        ["First root b", "Second root a"],
      );
    });

    check("conflicting root declarations are rejected", () => {
      const catalog = selfTestCatalog(["first", "second"]);
      catalog.categories[0].blueprints[0].discovery.roots = ["second", "first"];
      assert.throws(() => validateCatalog(catalog));
    });

    check("disabled card keeps its blueprint position with multiple roots", () => {
      const root = path.join(tempRoot, "disabled-position");
      fs.mkdirSync(path.join(root, "empty"), { recursive: true });
      writeSelfTestArtifact(root, "live.html", "Live document");
      const catalog = selfTestCatalog(["output-dir", "empty"], "missing.html");
      catalog.categories[0].blueprints[0].disabledWhenEmpty = true;
      const liveBlueprint = structuredClone(catalog.categories[0].blueprints[0]);
      liveBlueprint.kind = "live-self-test-page";
      liveBlueprint.label = "Live self test page";
      liveBlueprint.disabledWhenEmpty = false;
      liveBlueprint.discovery.artifactType = "live-self-test-page";
      liveBlueprint.discovery.glob = "live.html";
      catalog.categories[0].blueprints.push(liveBlueprint);
      assert.deepStrictEqual(
        selfTestTitles(catalog, root),
        ["Self test page", "Live document"],
      );
    });

    check("absolute and parent roots are rejected", () => {
      const unsafeRoots = [
        "/unsafe",
        "../unsafe",
        "C:\\unsafe",
        "C:unsafe",
        "\\\\server\\share",
        "..\\unsafe",
        "safe\\../unsafe",
      ];
      for (const unsafeRoot of unsafeRoots) {
        assert.throws(() => validateCatalog(selfTestCatalog([unsafeRoot])));
        const legacyCatalog = selfTestCatalog();
        legacyCatalog.categories[0].blueprints[0].discovery.root = unsafeRoot;
        assert.throws(() => validateCatalog(legacyCatalog));
      }
    });

    check("dot root resolves to output root", () => {
      const root = path.join(tempRoot, "dot-root");
      writeSelfTestArtifact(root, "document.html", "Dot root document");
      assert.deepStrictEqual(
        selfTestTitles(selfTestCatalog(["."]), root),
        ["Dot root document"],
      );
    });

    check("equivalent output roots keep the first declaration", () => {
      const root = path.join(tempRoot, "equivalent-roots");
      writeSelfTestArtifact(root, "document.html", "Equivalent root document");
      assert.deepStrictEqual(
        selfTestTitles(selfTestCatalog([".", "output-dir"]), root),
        ["Equivalent root document"],
      );
    });

    check("symbolic-link root is rejected", () => {
      const base = path.join(tempRoot, "symbolic-link-root");
      const root = path.join(base, "output");
      const outside = path.join(base, "outside");
      fs.mkdirSync(root, { recursive: true });
      writeSelfTestArtifact(outside, "escaped.html", "Outside document");
      fs.symlinkSync(outside, path.join(root, "linked"), process.platform === "win32" ? "junction" : "dir");
      assert.throws(() => selfTestTitles(selfTestCatalog(["linked"]), root));
      const linkedOutput = path.join(base, "linked-output");
      fs.symlinkSync(outside, linkedOutput, process.platform === "win32" ? "junction" : "dir");
      assert.throws(() => selfTestTitles(selfTestCatalog(), linkedOutput));
    });

    check("output order is declaration order then relative path bytewise", () => {
      const root = path.join(tempRoot, "ordered");
      writeSelfTestArtifact(root, "first/z.html", "First z");
      writeSelfTestArtifact(root, "first/a.html", "First a");
      writeSelfTestArtifact(root, "second/b.html", "Second b");
      assert.deepStrictEqual(
        selfTestTitles(selfTestCatalog(["first", "second"]), root),
        ["First a", "First z", "Second b"],
      );
    });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  if (command === "self-test") {
    if (Object.keys(args).length > 0) fail("self-test accepts no options");
    runSelfTest();
    return;
  }
  if (command === "validate") {
    validateCatalog(readJson(args.catalog));
    process.stdout.write("PASS: portal catalog schema\n");
    return;
  }
  if (command === "render") {
    if (!args.catalog || !args["output-root"] || !args["portal-dir"]) fail("render requires --catalog, --output-root, and --portal-dir");
    const outputLayout = readOutputLayout(args["output-layout"]);
    process.stdout.write(`${JSON.stringify(renderCatalog(readJson(args.catalog), args["output-root"], args["portal-dir"], outputLayout))}\n`);
    return;
  }
  if (command === "extract") {
    if (!args.html) fail("extract requires --html");
    process.stdout.write(`${JSON.stringify(extractCategoriesFromHtml(args.html), null, 2)}\n`);
    return;
  }
  if (command === "compare") {
    if (!args.catalog || !args["output-root"] || !args["portal-dir"] || !args.golden) {
      fail("compare requires --catalog, --output-root, --portal-dir, and --golden");
    }
    const outputLayout = readOutputLayout(args["output-layout"]);
    const actual = renderCatalog(readJson(args.catalog), args["output-root"], args["portal-dir"], outputLayout).categories;
    const expected = readJson(args.golden);
    try {
      assert.deepStrictEqual(actual, expected);
    } catch {
      fail("catalog rendering differs from legacy golden");
    }
    process.stdout.write(`PASS: ${actual.length} categories, ${actual.reduce((sum, category) => sum + category.tools.length, 0)} cards match legacy golden\n`);
    return;
  }
  fail(`unknown command: ${command || "(none)"}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
