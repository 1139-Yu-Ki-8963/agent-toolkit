#!/usr/bin/env node
// Portal 正本 → 匿名化 payload のビルドスクリプト
// 正本を再帰コピーし、禁止コンテンツをプレースホルダに置換して payload を生成する。

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const SCRIPT_DIR = path.dirname(new URL(import.meta.url).pathname);
const REPO_ROOT = path.resolve(SCRIPT_DIR, "..");
const HOME = process.env.HOME || process.env.USERPROFILE;

const PORTAL_SRC = path.join(HOME, "agent-home", "ai-management-portal");
const DEFAULT_DST = path.join(
  REPO_ROOT,
  "payload",
  "claudecode-global-setup",
  "agent-home",
  "ai-management-portal"
);

const FORBIDDEN_CONTENT_PATH = path.join(
  HOME,
  "agent-home",
  "state",
  "payload-forbidden-content.json"
);
const ARTIFACTS_PATH = path.join(SCRIPT_DIR, "payload-artifacts.json");

const TEXT_EXTS = new Set([
  ".html",
  ".js",
  ".css",
  ".md",
  ".json",
  ".yml",
  ".yaml",
  ".txt",
]);

function loadForbiddenWords() {
  if (!fs.existsSync(FORBIDDEN_CONTENT_PATH)) return [];
  const data = JSON.parse(fs.readFileSync(FORBIDDEN_CONTENT_PATH, "utf8"));
  const words = data.forbiddenContent || [];
  return words.sort((a, b) => b.length - a.length);
}

function loadArtifacts() {
  if (!fs.existsSync(ARTIFACTS_PATH))
    return { names: [], pathSuffixes: [] };
  return JSON.parse(fs.readFileSync(ARTIFACTS_PATH, "utf8"));
}

function isExcluded(relPath, artifacts) {
  const basename = path.basename(relPath);
  for (const n of artifacts.names) {
    if (basename === n) return true;
    if (relPath.includes(`/${n}/`) || relPath.startsWith(`${n}/`)) return true;
  }
  for (const s of artifacts.pathSuffixes) {
    if (
      relPath.endsWith(s) ||
      relPath.endsWith(`/${s}`) ||
      relPath.includes(`${s}/`)
    )
      return true;
  }
  return false;
}

function replaceForbidden(content, words) {
  let result = content;
  for (const word of words) {
    result = result.split(word).join("<project>");
  }
  return result;
}

function copyDir(src, dst, words, artifacts, relBase = "") {
  if (!fs.existsSync(dst)) fs.mkdirSync(dst, { recursive: true });

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const dstPath = path.join(dst, entry.name);
    const relPath = relBase ? `${relBase}/${entry.name}` : entry.name;

    if (isExcluded(relPath, artifacts)) continue;

    if (entry.isDirectory()) {
      copyDir(srcPath, dstPath, words, artifacts, relPath);
    } else {
      const ext = path.extname(entry.name).toLowerCase();
      if (TEXT_EXTS.has(ext)) {
        let content = fs.readFileSync(srcPath, "utf8");
        content = replaceForbidden(content, words);
        fs.writeFileSync(dstPath, content, "utf8");
      } else {
        fs.copyFileSync(srcPath, dstPath);
      }
    }
  }
}

function countFiles(dir) {
  let n = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) n += countFiles(path.join(dir, e.name));
    else n++;
  }
  return n;
}

// --- Main ---
const outputDir = process.argv[2] || DEFAULT_DST;
const forbiddenWords = loadForbiddenWords();
const artifacts = loadArtifacts();

if (!fs.existsSync(PORTAL_SRC)) {
  console.error(`Portal source not found: ${PORTAL_SRC}`);
  process.exit(1);
}

if (fs.existsSync(outputDir)) {
  fs.rmSync(outputDir, { recursive: true });
}

console.log("Building portal payload...");
console.log(`  Source: ${PORTAL_SRC}`);
console.log(`  Destination: ${outputDir}`);
console.log(`  Forbidden words: ${forbiddenWords.length}`);

copyDir(PORTAL_SRC, outputDir, forbiddenWords, artifacts);

const total = countFiles(outputDir);
console.log(`  Generated: ${total} files`);
