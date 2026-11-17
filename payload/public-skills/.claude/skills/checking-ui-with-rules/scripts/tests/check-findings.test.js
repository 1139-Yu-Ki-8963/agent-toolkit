#!/usr/bin/env node
// check-findings.js のテスト。一時ファイルは TMPDIR の下(なければ /tmp)に作り、終了時に消す。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const S = path.join(__dirname, "..", "check-findings.js");
const D = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "test-check-findings-"));
process.on("exit", () => fs.rmSync(D, { recursive: true, force: true }));
let failed = 0;
const run = (args) => spawnSync(process.execPath, [S, ...args], { encoding: "utf8" });
const t = (name, ok) => { if (ok) console.log(`成功: ${name}`); else { console.log(`失敗: ${name}`); failed = 1; } };
const w = (name, body) => { const p = path.join(D, name); fs.writeFileSync(p, typeof body === "string" ? body : JSON.stringify(body)); return p; };
const code = { rule_file: "r/button-rule.md", rule_viewpoint: "代替テキスト", file: "index.html", line: 12, quote: "<button>", occurrence: 1,
  rule_quote: "必ず代替テキストを指定します。", problem: "名前がない。", fix_before: "<button>", fix_after: '<button aria-label="x">', fix_reason: "読み上げのため。", decision_needed: false };
const screen = { ...code, url: "file:///a.html", width: [1440, 768, 375], selector: ".note", photo: ["写真/1-1440.png"], file_guessed: true };
const choice = { ...code, decision_needed: true, fix_after: ["a", "b"] };

const ok = run([w("ok.json", [code, screen, choice]), w("empty.json", [])]);
t("形の合うファイルと空の配列は終了コード 0", ok.status === 0);
const missing = { ...code }; delete missing.quote;
const bad = run([w("ok2.json", [code]), w("bad.json", [missing])]);
t("項目が欠けると終了コード 1", bad.status === 1);
t("崩れたファイルのパスと理由を 1 行に出す", bad.stdout.includes("bad.json: 1 件目の quote が文字列でない") && !bad.stdout.includes("ok2.json"));
t("JSON として読めないと終了コード 1", run([w("broken.json", "[{")]).status === 1);
t("配列でないと終了コード 1", run([w("obj.json", { unreadable: ["a"] })]).status === 1);
t("ないファイルは終了コード 1", run([path.join(D, "none.json")]).stdout.includes("ファイルがない"));
t("decision_needed が true で fix_after が文字列だと終了コード 1", run([w("c.json", [{ ...code, decision_needed: true }])]).status === 1);
t("画面の指摘で selector がないと終了コード 1", run([w("s.json", [{ ...screen, selector: undefined }])]).status === 1);
t("line が整数でないと終了コード 1", run([w("l.json", [{ ...code, line: "12" }])]).status === 1);
t("引数がないと終了コード 2", run([]).status === 2);
process.exit(failed);
