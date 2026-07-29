#!/usr/bin/env node

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { chromium } = require("playwright");

const scriptDir = __dirname;
const repositoryRoot = path.resolve(scriptDir, "../..");
const templatePath = path.join(
  repositoryRoot,
  "shared/templates/リバース検証/画面/詳細設計/画面詳細設計書.md",
);
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "screen-doc-order-"));
const docsRoot = path.join(temporaryRoot, "docs");
const detailDir = path.join(docsRoot, "画面/screen-order-test/詳細設計");
const outputPath = path.join(detailDir, "画面詳細設計書.html");

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with exit ${result.status}\n${result.stdout}\n${result.stderr}`,
    );
  }
}

async function main() {
  fs.mkdirSync(detailDir, { recursive: true });
  fs.copyFileSync(templatePath, path.join(detailDir, "画面詳細設計書.md"));
  run("bash", [
    path.join(scriptDir, "build-portal.sh"),
    temporaryRoot,
    docsRoot,
    docsRoot,
    "--generated-at",
    "2026-07-29T00:00:00Z",
  ]);

  assert.ok(fs.existsSync(outputPath), "画面詳細設計書.html が生成されていない");

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(outputPath).href);
    await page.waitForSelector("#doc-content > .sec-block > .sec-label", {
      state: "attached",
    });

    const headings = await page.$$eval(
      "#doc-content > .sec-block > .sec-label",
      (elements) =>
        elements.map((element) => element.textContent.trim()),
    );
    const relatedHeading = "関連資料（正の宣言・付録A）";
    const chapterMapHeading = "章マップ（付録B）";

    assert.equal(
      headings[0],
      "§1 画面概要",
      `最初の本文セクションが画面概要ではない: ${headings[0]}`,
    );
    assert.deepEqual(
      headings.slice(-2),
      [relatedHeading, chapterMapHeading],
      `管理・索引表が末尾付録ではない: ${headings.slice(-2).join(" / ")}`,
    );
    assert.equal(
      headings.filter((heading) => heading === relatedHeading).length,
      1,
      `${relatedHeading} が重複している`,
    );
    assert.equal(
      headings.filter((heading) => heading === chapterMapHeading).length,
      1,
      `${chapterMapHeading} が重複している`,
    );
    console.log(`PASS: DOM見出し順序 ${headings[0]} → … → ${headings.slice(-2).join(" → ")}`);
  } finally {
    await browser.close();
  }
}

main()
  .catch((error) => {
    console.error(`FAIL: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(() => {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  });
