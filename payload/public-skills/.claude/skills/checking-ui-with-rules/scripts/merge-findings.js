#!/usr/bin/env node
// 2 人の指摘を鍵でまとめ、1 人だけの印と重さと通し番号を付け、件数を数える(step 6-9)。
// 終了コード 0 正常、2 呼び出しの誤り。
const fs = require("fs");
const path = require("path");

const WEIGHT_ORDER = ["直す", "できれば直す"];

function keyOf(f) {
  if ("url" in f) return JSON.stringify(["screen", f.rule_file, f.rule_viewpoint, f.url, f.width, f.selector]);
  return JSON.stringify(["code", f.rule_file, f.rule_viewpoint, f.file, String(f.quote ?? "").replace(/[ \t\r\n]+/g, " ").trim(), f.occurrence]);
}

function readRules(rulePaths) {
  const rules = [];
  for (const p of rulePaths) {
    let section = "";
    let current = null;
    for (const raw of fs.readFileSync(p, "utf8").split("\n")) {
      const line = raw.trim();
      const sec = line.match(/^###\s+(.+)$/);
      if (sec) section = sec[1];
      const rule = line.replace(/^#+\s*/, "").match(/^規則\s*\d+:\s*(.+)$/);
      if (rule) {
        current = { path: p, viewpoint: rule[1].trim(), section, weight: "直す" };
        rules.push(current);
      }
      const w = line.match(/^-\s*重さ:\s*(直す|できれば直す)/);
      if (w && current) current.weight = w[1];
    }
  }
  return rules;
}

function samePath(a, b) {
  const x = String(a).split(path.sep).join("/");
  const y = String(b).split(path.sep).join("/");
  return x === y || x.endsWith("/" + y) || y.endsWith("/" + x);
}

function merge(lists, rules) {
  const byKey = new Map();
  lists.forEach((list, who) => {
    for (const f of list) {
      const k = keyOf(f);
      if (!byKey.has(k)) byKey.set(k, { finding: f, who: new Set() });
      byKey.get(k).who.add(who);
    }
  });
  const merged = [...byKey.values()].map(({ finding, who }) => {
    const rule = rules.find((r) => samePath(r.path, finding.rule_file) && r.viewpoint === finding.rule_viewpoint);
    return { ...finding, weight: rule ? rule.weight : "直す", single: who.size < 2, section: rule ? rule.section : "" };
  });
  merged.sort((a, b) =>
    WEIGHT_ORDER.indexOf(a.weight) - WEIGHT_ORDER.indexOf(b.weight) ||
    a.rule_file.localeCompare(b.rule_file) ||
    a.rule_viewpoint.localeCompare(b.rule_viewpoint) ||
    a.file.localeCompare(b.file) ||
    a.line - b.line);
  const counts = { total: merged.length, by_weight: {}, by_section: {} };
  for (const w of WEIGHT_ORDER) counts.by_weight[w] = 0;
  const findings = merged.map((f, i) => {
    const { section, ...rest } = f;
    counts.by_weight[f.weight]++;
    const s = `${path.basename(f.rule_file)} ${section}`.trim();
    counts.by_section[s] = (counts.by_section[s] || 0) + 1;
    return { number: i + 1, ...rest };
  });
  return { findings, counts };
}

function parseArgs(argv) {
  const a = { rules: [], out: null, files: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--rules") {
      while (i + 1 < argv.length && !argv[i + 1].startsWith("--")) a.rules.push(argv[++i]);
    } else if (argv[i] === "--out") {
      a.out = argv[++i];
    } else {
      a.files.push(argv[i]);
    }
  }
  if (a.rules.length === 0 || !a.out || a.files.length === 0) throw new Error("--rules、--out と、照合者の返り値のファイルが 1 つ以上要る");
  return a;
}

function main() {
  try {
    const a = parseArgs(process.argv.slice(2));
    const rules = readRules(a.rules);
    const lists = a.files.map((f) => {
      const data = JSON.parse(fs.readFileSync(f, "utf8"));
      if (!Array.isArray(data)) throw new Error(`${f} が指摘の配列でない`);
      return data;
    });
    const { findings, counts } = merge(lists, rules);
    fs.writeFileSync(a.out, JSON.stringify(findings, null, 2));
    console.log(JSON.stringify(counts));
  } catch (e) {
    console.log(`呼び出しの誤り: ${e.message}`);
    process.exit(2);
  }
}

if (require.main === module) main();
module.exports = { keyOf, readRules, merge };
