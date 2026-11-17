#!/usr/bin/env node
// compare-findings.js のテスト。一時ファイルは TMPDIR の下(なければ /tmp)に作り、終了時に消す。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const S = path.join(__dirname, "..", "compare-findings.js");
const D = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "test-compare-findings-"));
process.on("exit", () => fs.rmSync(D, { recursive: true, force: true }));
let failed = 0;
const run = (args) => spawnSync(process.execPath, [S, ...args], { encoding: "utf8" });
const t = (name, ok) => { if (ok) console.log(`成功: ${name}`); else { console.log(`失敗: ${name}`); failed = 1; } };
const w = (rel, body) => { const p = path.join(D, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, JSON.stringify(body)); return p; };
const f = (n, viewpoint, quote) => ({ number: n, weight: "直す", single: false, rule_file: "r.md", rule_viewpoint: viewpoint, file: "a.css", line: n, quote, occurrence: 1,
  rule_quote: "q", problem: "p", fix_before: "b", fix_after: "a", fix_reason: "r", decision_needed: false });
const R = path.join(D, "results");
const prev = w("results/指摘の一覧.json", [f(1, "枠", "outline: none;"), f(2, "色", "color: #999;"), f(3, "高さ", "height: 32px;")]);
w("results/調べ直し-2/調べ直しの結果.json", [f(7, "古い", "x")]);
const cur = w("cur.json", [{ ...f(1, "色", "color: #999;"), line: 30 }, f(2, "新しい", "transition: all;"), f(3, "別", "outline: 0;")]);
const out = path.join(D, "突き合わせた結果.json");
const r = run(["--previous", prev, "--results", R, "--out", out, cur]);
t("終了コード 0", r.status === 0);
const x = JSON.parse(fs.readFileSync(out, "utf8"));
t("前にあって今ない指摘は直った", x.fixed.map((v) => v.number).join() === "1,3");
t("両方にある指摘は残っているで、番号を前のまま変えない", x.remaining.length === 1 && x.remaining[0].number === 2 && x.remaining[0].status === "残っている");
t("前になくて今ある指摘は新しく出たで、すべての回の最も大きい番号の続きを付ける", x.new.map((v) => v.number).join() === "8,9" && x.new.every((v) => v.status === "新しく出た"));
const s = JSON.parse(r.stdout);
t("番号と残りの件数を標準出力に出す", s.fixed.join() === "1,3" && s.remaining_count === 3);
const e = run(["--previous", w("e/p.json", []), "--results", path.join(D, "e"), "--out", path.join(D, "e.json"), w("e/c.json", [])]);
const ex = JSON.parse(fs.readFileSync(path.join(D, "e.json"), "utf8"));
t("両方が 0 件なら、すべて 0 件", e.status === 0 && ex.fixed.length === 0 && ex.new.length === 0 && ex.remaining.length === 0);
t("前の回の json がないと終了コード 2", run(["--previous", path.join(D, "none.json"), "--results", R, "--out", out, cur]).status === 2);
t("引数が足りないと終了コード 2", run(["--previous", prev, cur]).status === 2);
process.exit(failed);
