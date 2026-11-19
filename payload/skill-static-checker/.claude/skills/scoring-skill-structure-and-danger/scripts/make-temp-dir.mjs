#!/usr/bin/env node
import { mkdtempSync, mkdirSync } from "node:fs";
import { join, basename, sep } from "node:path";
import { tmpdir } from "node:os";
const A = process.argv.slice(2), PREFIX = "scoring-skill-structure-and-danger-";
if (A.some(a => !a || a !== basename(a) || a === "." || a === "..")) { console.error("使い方: node make-temp-dir.mjs [<作る下のフォルダの名前>...]"); process.exit(2); }
try { const d = mkdtempSync(join(tmpdir(), PREFIX)); A.forEach(a => mkdirSync(join(d, a))); console.log(d.split(sep).join("/")); } catch (e) { console.error(`一時フォルダを作れない: ${e.message}`); process.exit(2); }
process.exitCode = 0;
