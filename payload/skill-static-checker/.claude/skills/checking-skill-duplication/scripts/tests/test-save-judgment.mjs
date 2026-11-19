#!/usr/bin/env node
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const S = join(dirname(fileURLToPath(import.meta.url)), "..", "save-judgment.mjs");
const D = mkdtempSync(join(process.env.TMPDIR || "/tmp", "test-save-judgment-"));
process.on("exit", () => rmSync(D, { recursive: true, force: true }));
let fail = 0;
const t = (name, cond) => { console.log(`${cond ? "成功" : "失敗"}: ${name}`); if (!cond) fail = 1; };
const run = args => spawnSync(process.execPath, [S, ...args], { encoding: "utf8" });
const F = "```";
const good = `判定しました。\n\n${F}json\n{ "sections": [{ "id": "組1", "category": "重複", "reason": "同じ", "extra": 1 }], "skills": [] }\n${F}\n`;
const c = (name, t1, t2) => { const d = join(D, name); mkdirSync(d); if (t1 !== null) writeFileSync(join(d, "judge-1.txt"), t1); if (t2 !== null) writeFileSync(join(d, "judge-2.txt"), t2); return d; };
const J = (d, n) => JSON.parse(readFileSync(join(d, `judge-${n}.json`), "utf8"));
let d = c("good", good, good.replace(/\n/g, "\r\n")), r = run([d]);
t("返り値の文の json のコードブロックを取り出し、judge-1.json と judge-2.json に書いて、終了コード 0", r.status === 0 && J(d, 1).sections[0].category === "重複" && J(d, 2).sections.length === 1 && r.stdout === "judge-1.json: 形のとおり\njudge-2.json: 形のとおり\n");
t("項目は、id、category、reason だけを書く", JSON.stringify(Object.keys(J(d, 1).sections[0])) === JSON.stringify(["id", "category", "reason"]));
const cases = [["none", "判定しました。", "json のコードブロックがない"], ["two", good + good, "json のコードブロックが 2 つ以上ある"], ["bad", `${F}json\n{ 壊れた\n${F}\n`, "JSON として読めない"], ["noarr", `${F}json\n{ "sections": [] }\n${F}\n`, "配列でない"], ["noreason", `${F}json\n{ "sections": [{ "id": "組1", "category": "重複" }], "skills": [] }\n${F}\n`, "配列でない"]];
for (const [name, text, why] of cases) { d = c(name, text, good); r = run([d]); t(`形の違う返り値(${name})は、理由だけを持つ judge-1.json を書き、終了コード 1`, r.status === 1 && J(d, 1).error.includes(why) && !("sections" in J(d, 1)) && J(d, 2).sections.length === 1 && r.stdout.startsWith("judge-1.json: 形と違う(")); }
t("返り値の文のファイルがないときは、終了コード 2", run([c("missing", good, null)]).status === 2);
t("引数がないときは、終了コード 2", run([]).status === 2);
process.exit(fail);
