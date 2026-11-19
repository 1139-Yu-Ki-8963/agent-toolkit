#!/usr/bin/env node
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const S = join(dirname(fileURLToPath(import.meta.url)), "..", "check-outputs.mjs");
const D = mkdtempSync(join(process.env.TMPDIR || "/tmp", "test-check-outputs-"));
process.on("exit", () => rmSync(D, { recursive: true, force: true }));
let fail = 0;
const t = (name, cond) => { console.log(`${cond ? "成功" : "失敗"}: ${name}`); if (!cond) fail = 1; };
const run = args => spawnSync(process.execPath, [S, ...args], { encoding: "utf8" });
const f = join(D, "report.html"); writeFileSync(f, "x"); mkdirSync(join(D, "dir"));
let r = run([f, join(D, "dir")]);
t("渡したパスがすべてあれば、何も出さずに終了コード 0", r.status === 0 && r.stdout === "");
r = run([f, join(D, "none1.html"), join(D, "none2.html")]);
t("ないパスがあれば、ないパスを 1 行に 1 つ出して終了コード 1", r.status === 1 && r.stdout === join(D, "none1.html") + "\n" + join(D, "none2.html") + "\n");
t("引数がないときは、終了コード 2", run([]).status === 2);
process.exit(fail);
