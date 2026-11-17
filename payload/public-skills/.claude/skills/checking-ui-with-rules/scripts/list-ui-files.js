#!/usr/bin/env node
// 調べる範囲の画面のファイルを列挙する(step 5-1)。終了コード 0 正常、2 呼び出しの誤り。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const EXTS = new Set([".html", ".htm", ".jsx", ".tsx", ".vue", ".svelte", ".js", ".ts", ".css", ".scss"]);
const SKIP_DIRS = new Set(["node_modules", ".git", "dist", "build", "__pycache__", ".next", ".nuxt", "vendor", "coverage", "ui-check-results"]);

function isSecret(name) {
  return /^\.env/.test(name) || /\.(pem|key|p12|pfx)$/i.test(name) || /^id_(rsa|ed25519|ecdsa|dsa)/.test(name) || /^credentials/i.test(name);
}

function isUiFile(file) {
  const name = path.basename(file);
  if (isSecret(name)) return false;
  if (/^tailwind\.config\./.test(name)) return true;
  const ext = path.extname(name).toLowerCase();
  if (ext === ".json") return /token|theme/i.test(name);
  return EXTS.has(ext);
}

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(full, out);
    } else if (entry.isFile() && isUiFile(full)) {
      out.push(full);
    }
  }
  return out;
}

function changedFiles(root) {
  const r = spawnSync("git", ["-C", root, "status", "--porcelain", "--untracked-files=all"], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`git status を実行できない(${root})`);
  const files = [];
  for (const line of r.stdout.split("\n")) {
    if (line.length < 4 || line[0] === "D" || line[1] === "D") continue;
    let p = line.slice(3);
    if (p.includes(" -> ")) p = p.split(" -> ")[1];
    p = p.replace(/^"(.*)"$/, "$1");
    const full = path.join(root, p);
    if (SKIP_DIRS.has(p.split("/")[0])) continue;
    if (fs.existsSync(full) && fs.statSync(full).isFile() && isUiFile(full)) files.push(full);
  }
  return files;
}

function parseArgs(argv) {
  const a = { root: null, range: "プロジェクト全体", changed: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root") a.root = argv[++i];
    else if (argv[i] === "--range") a.range = argv[++i];
    else if (argv[i] === "--changed") a.changed = true;
    else throw new Error(`知らない引数: ${argv[i]}`);
  }
  if (!a.root) throw new Error("--root がない");
  return a;
}

function main() {
  let a;
  try {
    a = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.log(`呼び出しの誤り: ${e.message}`);
    process.exit(2);
  }
  const root = path.resolve(a.root);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    console.log(`プロジェクトのフォルダがない: ${root}`);
    process.exit(2);
  }
  let files;
  try {
    if (a.changed) {
      files = changedFiles(root);
    } else {
      const target = a.range === "プロジェクト全体" ? root : path.resolve(root, a.range);
      if (!fs.existsSync(target)) {
        console.log(`調べる範囲がない: ${target}`);
        process.exit(2);
      }
      files = fs.statSync(target).isDirectory() ? walk(target, []) : (isUiFile(target) ? [target] : []);
    }
  } catch (e) {
    console.log(e.message);
    process.exit(2);
  }
  for (const f of [...new Set(files)].sort()) console.log(f);
}

if (require.main === module) main();
module.exports = { isUiFile, isSecret };
