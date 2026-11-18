#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, resolve, relative, extname } from "node:path";
const A = process.argv.slice(2), oi = A.indexOf("--out"), OUT = oi >= 0 ? A[oi + 1] : "", DIR = A.find((a, i) => oi < 0 || (i !== oi && i !== oi + 1));
if (!DIR || (oi >= 0 && !OUT) || A.length !== (oi >= 0 ? 3 : 1) || !existsSync(join(DIR, "SKILL.md"))) { console.error("使い方: node check-code-risk.mjs <調べるスキルのフォルダ> [--out <指摘の JSON のパス>]"); process.exit(2); } process.on("uncaughtException", e => { console.error(`調べられない: ${e.message}`); process.exit(2); });
const SEV = { CRITICAL: "重大", HIGH: "重大", MEDIUM: "注意", LOW: "注意", INFO: "参考" }, F = [];
const walk = d => readdirSync(d, { withFileTypes: true }).flatMap(e => [".git", "node_modules", ".tools"].includes(e.name) ? [] : e.isDirectory() ? walk(join(d, e.name)) : e.isFile() ? [join(d, e.name)] : []);
const files = walk(DIR).filter(p => statSync(p).size <= 2e6).map(p => [relative(DIR, p).split("\\").join("/"), readFileSync(p)]).filter(([, b]) => !b.subarray(0, 8192).includes(0)).map(([p, b]) => [p, b.toString("utf8")]);
const add = (src, item, p, n, message, fix) => F.push({ check: "check-code-risk", item, kind: "危険", severity: SEV[src], source_severity: src, dimension: null, deduction: 0, file: p, line: n, message, fix });
const JS = [".mjs", ".js", ".cjs", ".ts"], SH = [".sh", ".bash", ".zsh"], PY = [".py"], DOC = p => p === "SKILL.md" || (p.startsWith("references/") && p.endsWith(".md"));
for (const [p, t] of files) {
  const e = extname(p), L = t.split(/\r?\n/), code = (s) => !/^\s*(\/\/|\*|#)/.test(s);
  if (JS.includes(e)) {
    const names = new Set(), ns = new Set();
    for (const m of t.matchAll(/import\s*\{([^}]*)\}\s*from\s*["'](?:node:)?child_process["']/g)) for (const part of m[1].split(",")) { const [o, a] = part.trim().split(/\s+as\s+/); if (/^exec(Sync)?$/.test(o)) names.add((a || o).trim()); }
    for (const m of t.matchAll(/const\s*\{([^}]*)\}\s*=\s*require\(\s*["'](?:node:)?child_process["']\s*\)/g)) for (const part of m[1].split(",")) { const [o, a] = part.trim().split(/\s*:\s*/); if (/^exec(Sync)?$/.test(o)) names.add((a || o).trim()); }
    for (const m of t.matchAll(/(?:import\s+(?:\*\s+as\s+)?(\w+)\s+from|(?:const|let|var)\s+(\w+)\s*=\s*require\()\s*["'](?:node:)?child_process["']/g)) ns.add(m[1] || m[2]);
    const ex = new RegExp(`(^|[^\\w.$])(${[...names].join("|") || "\\b(?!)"})\\s*\\(|\\b(${[...ns].join("|") || "(?!)"})\\.exec(Sync)?\\s*\\(|require\\(\\s*["'](?:node:)?child_process["']\\s*\\)\\.exec(Sync)?\\s*\\(`);
    L.forEach((s, i) => { if (!code(s)) return;
      if (/(^|[^\w.$])eval\s*\(/.test(s)) add("HIGH", "危ないコード(eval)", p, i + 1, "文字列をコードとして動かす eval を使っている。", "eval を使わずに、値を JSON.parse か決まった処理で扱う。");
      if (/\bnew\s+Function\s*\(/.test(s)) add("HIGH", "危ないコード(new Function)", p, i + 1, "文字列からコードを作る new Function を使っている。", "new Function を使わずに、決まった関数を書く。");
      if (ex.test(s)) add("HIGH", "危ないコード(シェルに渡す実行)", p, i + 1, "child_process の exec か execSync で、文字列のコマンドをシェルに渡している。", "spawnSync か execFileSync に、コマンドと引数の配列を渡す。");
      if (/\b(spawn|spawnSync|execFile|execFileSync|fork)\s*\(.*\bshell\s*:\s*true/.test(s)) add("HIGH", "危ないコード(シェルに渡す実行)", p, i + 1, "子のプロセスを shell: true で動かしている。", "shell: true を外し、引数の配列で渡す。");
    });
  }
  if (PY.includes(e)) L.forEach((s, i) => { if (!code(s)) return;
    if (/(^|[^\w.])(eval|exec)\s*\(/.test(s)) add("HIGH", "危ないコード(eval と exec)", p, i + 1, "文字列をコードとして動かす eval か exec を使っている。", "eval と exec を使わずに、決まった処理を書く。");
    if (/subprocess\.(run|Popen|call|check_call|check_output)\(.*shell\s*=\s*True/.test(s)) add("HIGH", "危ないコード(シェルに渡す実行)", p, i + 1, "subprocess を shell=True で動かしている。", "shell=True を外し、引数の一覧で渡す。");
  });
  if (JS.includes(e) || SH.includes(e) || PY.includes(e) || DOC(p)) L.forEach((s, i) => {
    if (/\b(curl|wget)\b[^|\n]*\|\s*(sudo\s+)?(sh|bash|zsh)\b/.test(s)) add("HIGH", "危ないコード(取得したものをシェルに渡す)", p, i + 1, "取得した中身を、そのままシェルに渡している。", "パッケージマネージャで入れる。");
    else if (/(^|[\s`"'(])(curl|wget|Invoke-WebRequest|Invoke-RestMethod|iwr|irm)\s+\S/.test(s) && !/localhost|127\.0\.0\.1/.test(s)) add("MEDIUM", "外部からの取得", p, i + 1, "パッケージマネージャと git clone の外のコマンドで、外部から取得している。", "パッケージマネージャのコマンドか、公式の配布元への git clone にする。");
  });
  if (!DOC(p)) continue;
  let lang = null, blk = [];
  L.forEach((s, i) => {
    const f = s.match(/^\s*(`{3,}|~{3,})\s*([\w-]*)/);
    if (f && lang === null) { lang = f[2].toLowerCase(); blk = []; return; }
    if (f && lang !== null) { if (/^(sh|bash|zsh|shell|console|powershell|pwsh|ps1|cmd|bat)$/.test(lang) && blk.filter(([x]) => x.trim() && !/^\s*#/.test(x)).length > 1) add("MEDIUM", "1 行のコマンドでない実行", p, blk[0][1], `コマンドのコードブロックが ${blk.filter(([x]) => x.trim() && !/^\s*#/.test(x)).length} 行のコマンドを持つ。`, "コマンドを 1 行ずつに分けるか、同梱したスクリプトにする。"); lang = null; return; }
    if (lang !== null) blk.push([s, i + 1]);
    const cmds = lang !== null ? [s] : [...s.matchAll(/`([^`]+)`/g)].map(m => m[1]);
    for (const c of cmds) { const m = c.match(/^\s*(node|bash|sh|zsh|python3?|pwsh|powershell)\s+(?:-\S+\s+)*["']?([^\s"']+\.(?:mjs|cjs|js|sh|py|ps1))/); if (m && !(m[1] === "node" && /(^|\/|>)scripts\/|\.tools\//.test(m[2]))) add("MEDIUM", "同梱していないスクリプトの実行", p, i + 1, `同梱した scripts/ の外のスクリプト「${m[2]}」を、${m[1]} で動かしている。`, "動かすスクリプトを scripts/ に置き、node で動かす。"); }
  });
}
try { const R = JSON.stringify({ script: "check-code-risk", target: resolve(DIR), status: "済み", findings: F }, null, 2) + "\n"; if (OUT) writeFileSync(OUT, R); else process.stdout.write(R); } catch (e) { console.error(`指摘の JSON を書けない: ${e.message}`); process.exit(2); }
process.exitCode = F.length ? 1 : 0;
