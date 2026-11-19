#!/usr/bin/env node
import { rmSync, realpathSync } from "node:fs";
import { dirname, basename, resolve } from "node:path";
import { tmpdir } from "node:os";
const A = process.argv.slice(2), PREFIX = "scoring-skill-structure-and-danger-", real = p => { try { return realpathSync(p); } catch { return resolve(p); } };
const P = A.length === 1 && A[0] ? resolve(A[0]) : "", name = basename(P);
if (!P || !name.startsWith(PREFIX) || name.length === PREFIX.length || ![resolve(tmpdir()), real(tmpdir())].includes(real(dirname(P)))) { console.error(`使い方: node remove-temp-dir.mjs <OS の一時フォルダの直下の、名前が ${PREFIX} で始まるフォルダ>`); process.exit(2); }
try { rmSync(P, { recursive: true, force: true }); } catch (e) { console.error(`一時フォルダを消せない: ${e.message}`); process.exit(2); }
process.exitCode = 0;
