#!/usr/bin/env node
import { existsSync } from "node:fs";
const A = process.argv.slice(2);
if (!A.length || A.some(a => !a)) { console.error("使い方: node check-outputs.mjs <あるはずのパス>..."); process.exit(2); }
const miss = A.filter(p => !existsSync(p));
if (miss.length) console.log(miss.join("\n"));
process.exitCode = miss.length ? 1 : 0;
