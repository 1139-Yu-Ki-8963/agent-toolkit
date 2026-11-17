#!/usr/bin/env node
// list-ui-files.js のテスト。一時ファイルは TMPDIR の下(なければ /tmp)に作り、終了時に消す。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const S = path.join(__dirname, "..", "list-ui-files.js");
const D = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "test-list-ui-files-"));
process.on("exit", () => fs.rmSync(D, { recursive: true, force: true }));
let failed = 0;
const run = (args) => spawnSync(process.execPath, [S, ...args], { encoding: "utf8" });
const t = (name, ok) => { if (ok) console.log(`成功: ${name}`); else { console.log(`失敗: ${name}`); failed = 1; } };
const w = (rel, body = "x") => { const p = path.join(D, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, body); return p; };

["src/index.html", "src/a.tsx", "src/b.vue", "src/style.css", "src/c.scss", "src/tokens.json", "tailwind.config.js",
 "src/data.json", "src/readme.md", "node_modules/x/y.js", "dist/out.js", ".env.local", "src/secret.pem", "id_rsa", "credentials.json", "ui-check-results/2026-11-17-1200/theme.json"].forEach((f) => w(f));

const all = run(["--root", D]);
const lines = all.stdout.trim().split("\n").map((l) => path.relative(D, l));
t("プロジェクト全体で終了コード 0", all.status === 0);
t("画面のファイルを列挙する", ["src/index.html", "src/a.tsx", "src/b.vue", "src/style.css", "src/c.scss", "src/tokens.json", "tailwind.config.js"].every((f) => lines.includes(f)));
t("名前に token か theme のない .json と .md を出さない", !lines.includes("src/data.json") && !lines.includes("src/readme.md"));
t("飛ばすフォルダの下を出さない", !lines.some((l) => l.startsWith("node_modules") || l.startsWith("dist") || l.startsWith("ui-check-results")));
t("秘密の情報のファイルを出さない", !lines.some((l) => /\.env|\.pem|id_rsa|credentials/.test(l)));
t("パスの名前の順に並ぶ", JSON.stringify(lines) === JSON.stringify([...lines].sort()));

const one = run(["--root", D, "--range", "src/a.tsx"]);
t("入口のファイルは 1 本だけ出す", one.status === 0 && one.stdout.trim().split("\n").length === 1 && one.stdout.includes("a.tsx"));

const dir = run(["--root", D, "--range", "src"]);
t("フォルダの範囲はその下だけを出す", dir.status === 0 && !dir.stdout.includes("tailwind.config.js") && dir.stdout.includes("index.html"));

const none = run(["--root", D, "--range", "src/readme.md"]);
t("画面のファイルでない範囲は 0 件で終了コード 0", none.status === 0 && none.stdout.trim() === "");

t("引数がないと終了コード 2", run([]).status === 2);
t("ない範囲は終了コード 2", run(["--root", D, "--range", "nothing"]).status === 2);
t("知らない引数は終了コード 2", run(["--root", D, "--oops"]).status === 2);

const G = path.join(D, "repo");
fs.mkdirSync(G);
const git = (...a) => spawnSync("git", ["-C", G, ...a], { encoding: "utf8" });
if (git("init", "-q").status !== 0) {
  console.log("飛ばした: git がないので、--changed のケースを流さない");
} else {
  git("config", "user.email", "t@example.com"); git("config", "user.name", "t");
  fs.writeFileSync(path.join(G, "old.css"), "a"); fs.writeFileSync(path.join(G, "keep.css"), "a");
  git("add", "."); git("commit", "-qm", "init");
  fs.writeFileSync(path.join(G, "old.css"), "b");
  fs.mkdirSync(path.join(G, "new")); fs.writeFileSync(path.join(G, "new", "n.tsx"), "c");
  fs.writeFileSync(path.join(G, "staged.html"), "d"); git("add", "staged.html");
  fs.writeFileSync(path.join(G, ".env"), "SECRET");
  fs.mkdirSync(path.join(G, "ui-check-results", "r"), { recursive: true }); fs.writeFileSync(path.join(G, "ui-check-results", "r", "theme.json"), "{}");
  const ch = run(["--root", G, "--changed"]);
  const c = ch.stdout.trim().split("\n").map((l) => path.relative(G, l));
  t("--changed は変えたファイルとステージ済みと新しいファイルを出す", ch.status === 0 && ["old.css", "new/n.tsx", "staged.html"].every((f) => c.includes(f)));
  t("--changed は変えていないファイルと秘密の情報のファイルと結果のフォルダのファイルを出さない", !c.includes("keep.css") && !c.includes(".env") && !c.some((l) => l.startsWith("ui-check-results")));
  t("--changed は git のないフォルダで終了コード 2", run(["--root", path.join(D, "src"), "--changed"]).status === 2);
}
process.exit(failed);
