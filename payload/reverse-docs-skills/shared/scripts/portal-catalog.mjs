#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import assert from "node:assert/strict";

const KEY_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const CATEGORY_KEYS = new Set(["key", "label", "group", "icon", "sub", "blueprints"]);
const BLUEPRINT_KEYS = new Set(["kind", "label", "icon", "desc", "dir", "generator", "unit", "countFormat", "group", "discovery"]);
const DISCOVERY_KEYS = new Set([
  "artifactType", "root", "glob", "matchKind", "titleSource", "dirSource",
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

export function validateCatalog(catalog) {
  assertObject(catalog, "catalog");
  assertExactKeys(catalog, new Set(["schemaVersion", "categories"]), ["schemaVersion", "categories"], "catalog");
  if (catalog.schemaVersion !== 1) fail("catalog.schemaVersion must be 1");
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
      if (discovery.root !== "output-dir") fail(`${blueprintLabel}.discovery.root must be output-dir`);
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

export function renderCatalog(catalog, outputRoot, portalDir) {
  validateCatalog(catalog);
  const root = path.resolve(outputRoot);
  const portal = path.resolve(portalDir);
  if (!fs.statSync(root).isDirectory()) fail(`output root is not a directory: ${outputRoot}`);
  const files = walkFiles(root);
  const claimed = new Map();
  const instanceKeys = new Set();
  const categories = [];
  const kinds = [];
  for (const category of catalog.categories) {
    const tools = [];
    for (const blueprint of category.blueprints) {
      const matcher = globRegex(blueprint.discovery.glob);
      const matches = files.filter((relative) => matcher.test(relative)).sort(bytewise);
      for (const relative of matches) {
        if (claimed.has(relative)) fail(`artifact matches multiple blueprints: ${relative} (${claimed.get(relative)}, ${blueprint.discovery.artifactType})`);
        claimed.set(relative, blueprint.discovery.artifactType);
        if (instanceKeys.has(relative)) fail(`duplicate instance key: ${relative}`);
        instanceKeys.add(relative);
        const absolute = path.resolve(root, relative);
        if (absolute !== root && !absolute.startsWith(`${root}${path.sep}`)) fail(`artifact escapes output root: ${relative}`);
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
        tools.push(tool);
      }
      if (matches.length > 0 && blueprint.countFormat === "unit-count") {
        kinds.push({
          kind: blueprint.kind,
          label: blueprint.label.replace(/一覧$/, ""),
          count: Number(tools.at(-1).count.split(" ", 1)[0]),
          unit: blueprint.unit,
          href: tools.at(-1).href,
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

function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  if (command === "validate") {
    validateCatalog(readJson(args.catalog));
    process.stdout.write("PASS: portal catalog schema\n");
    return;
  }
  if (command === "render") {
    if (!args.catalog || !args["output-root"] || !args["portal-dir"]) fail("render requires --catalog, --output-root, and --portal-dir");
    process.stdout.write(`${JSON.stringify(renderCatalog(readJson(args.catalog), args["output-root"], args["portal-dir"]))}\n`);
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
    const actual = renderCatalog(readJson(args.catalog), args["output-root"], args["portal-dir"]).categories;
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

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
