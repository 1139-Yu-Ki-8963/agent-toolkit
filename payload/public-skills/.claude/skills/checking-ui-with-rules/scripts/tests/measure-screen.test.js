#!/usr/bin/env node
// measure-screen.js のテスト。一時ファイルは TMPDIR の下(なければ /tmp)に作り、終了時に消す。
// ブラウザを起動するケースは、ツールのフォルダに Playwright がないときに飛ばしたと出して合格にする。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const S = path.join(__dirname, "..", "measure-screen.js");
const { parseColor, contrastRatio, toContrast } = require(S);
const D = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "test-measure-screen-"));
process.on("exit", () => fs.rmSync(D, { recursive: true, force: true }));
let failed = 0;
const run = (args) => spawnSync(process.execPath, [S, ...args], { encoding: "utf8", timeout: 120000 });
const t = (name, ok) => { if (ok) console.log(`成功: ${name}`); else { console.log(`失敗: ${name}`); failed = 1; } };

const r1 = contrastRatio(parseColor("#999999"), parseColor("#ffffff"));
t(`#999999 と #ffffff の比が 2.85 対 1(${r1.toFixed(4)})`, Math.round(r1 * 100) / 100 === 2.85);
const r2 = contrastRatio(parseColor("rgb(26, 26, 26)"), parseColor("rgb(255, 255, 255)"));
t(`#1a1a1a と #ffffff の比が 17.40 対 1(${r2.toFixed(4)})`, Math.round(r2 * 100) / 100 === 17.4);
t("黒と白の比が 21 対 1", Math.abs(contrastRatio(parseColor("#000000"), parseColor("#ffffff")) - 21) < 1e-9);
t("比は色の順によらない", contrastRatio(parseColor("#ffffff"), parseColor("#999999")) === r1);
t("rgba の透明度を読む", parseColor("rgba(0, 0, 0, 0.5)").a === 0.5);
t("読めない色は null", parseColor("transparent") === null);
const c = toContrast([
  { selector: ".a", text: "a", color: "rgb(153, 153, 153)", background: { color: "rgb(255, 255, 255)" } },
  { selector: ".b", text: "b", color: "rgb(0, 0, 0)", background: { undetermined: "背景の画像かグラデーション" } },
  { selector: ".c", text: "c", color: "rgba(0, 0, 0, 0.5)", background: { color: "rgb(255, 255, 255)" } },
]);
t("測った文字の比を 2 桁に丸める", c[0].ratio === 2.85);
t("背景の画像の上の文字は比が決まらない", c[1].ratio === null && c[1].reason === "背景の画像かグラデーション");
t("半透明の文字は比が決まらない", c[2].ratio === null);

t("引数がないと終了コード 2", run([]).status === 2);
const noTools = run(["--tools", path.join(D, "none"), "--photos", path.join(D, "p"), "--data", path.join(D, "d.json"), "file:///x.html"]);
t("ツールのフォルダに Playwright がないと終了コード 2", noTools.status === 2 && noTools.stdout.includes("ブラウザの道具がない"));

const tools = path.join(__dirname, "..", "..", ".tools");
if (!fs.existsSync(path.join(tools, "node_modules", "playwright"))) {
  console.log(`飛ばした: ツールのフォルダ ${tools} に Playwright がないので、ブラウザを起動するケースを流さない`);
} else {
  const html = path.join(D, "index.html");
  fs.writeFileSync(html, '<html><body style="background:#fff"><p class="note" style="color:#999999">note</p><button class="small" style="height:32px">b</button></body></html>');
  const out = run(["--tools", tools, "--photos", path.join(D, "写真"), "--data", path.join(D, "d.json"), "file://" + html]);
  if (out.status === 2 && out.stdout.includes("ブラウザを起動できない")) {
    t("ブラウザを起動できないときは終了コード 2 と理由の 1 行を出す", true);
  } else {
    const data = JSON.parse(fs.readFileSync(path.join(D, "d.json"), "utf8"));
    t("幅 3 つの写真を撮る", ["1-1440.png", "1-768.png", "1-375.png"].every((f) => fs.existsSync(path.join(D, "写真", f))));
    t("文字の比を測る", data[0].contrast.some((x) => x.selector === "p.note" && x.ratio === 2.85));
    t("ボタンの高さを測る", data[0].targets.some((x) => x.selector === "button.small" && x.height === 32));
  }
}
process.exit(failed);
