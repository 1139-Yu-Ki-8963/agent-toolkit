#!/usr/bin/env node
// 前の回の json と鍵で突き合わせて、直った、新しく出た、残っているに分け、番号を付ける(step 7-2)。
// 終了コード 0 正常、2 呼び出しの誤り。
const fs = require("fs");
const path = require("path");
const { keyOf } = require("./merge-findings.js");

function readArray(file) {
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(data)) throw new Error(`${file} が指摘の配列でない`);
  return data;
}

function maxNumber(resultsDir, previous) {
  let max = Math.max(0, ...previous.map((f) => f.number || 0));
  const files = [path.join(resultsDir, "指摘の一覧.json")];
  for (const d of fs.existsSync(resultsDir) ? fs.readdirSync(resultsDir) : []) {
    if (/^調べ直し-\d+$/.test(d)) files.push(path.join(resultsDir, d, "調べ直しの結果.json"));
  }
  for (const f of files) {
    if (fs.existsSync(f)) max = Math.max(max, ...readArray(f).map((x) => x.number || 0));
  }
  return max;
}

function compare(previous, current, startNumber) {
  const prevByKey = new Map(previous.map((f) => [keyOf(f), f]));
  const curKeys = new Set(current.map(keyOf));
  const fixed = previous.filter((f) => !curKeys.has(keyOf(f)));
  let next = startNumber;
  const remaining = [];
  const added = [];
  for (const f of current) {
    const old = prevByKey.get(keyOf(f));
    if (old) remaining.push({ ...f, number: old.number, status: "残っている" });
    else added.push({ ...f, number: ++next, status: "新しく出た" });
  }
  return { fixed, remaining, new: added };
}

function parseArgs(argv) {
  const a = { previous: null, results: null, out: null, current: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--previous") a.previous = argv[++i];
    else if (argv[i] === "--results") a.results = argv[++i];
    else if (argv[i] === "--out") a.out = argv[++i];
    else a.current = argv[i];
  }
  if (!a.previous || !a.results || !a.out || !a.current) throw new Error("--previous、--results、--out と、今の回のまとめた指摘のファイルが要る");
  return a;
}

function main() {
  try {
    const a = parseArgs(process.argv.slice(2));
    const previous = readArray(a.previous);
    const current = readArray(a.current);
    const r = compare(previous, current, maxNumber(a.results, previous));
    fs.writeFileSync(a.out, JSON.stringify(r, null, 2));
    console.log(JSON.stringify({
      fixed: r.fixed.map((f) => f.number),
      new: r.new.map((f) => f.number),
      remaining: r.remaining.map((f) => f.number),
      remaining_count: r.remaining.length + r.new.length,
    }));
  } catch (e) {
    console.log(`呼び出しの誤り: ${e.message}`);
    process.exit(2);
  }
}

if (require.main === module) main();
module.exports = { compare, maxNumber };
