#!/usr/bin/env node
// 照合者の返り値の JSON の形を検証する(step 6-6、6-8)。
// 終了コード 0 正常、1 形の崩れたファイルがある、2 呼び出しの誤り。
const fs = require("fs");

const STRINGS = ["rule_file", "rule_viewpoint", "file", "quote", "rule_quote", "problem", "fix_before", "fix_reason"];

function problemOf(item) {
  if (item === null || typeof item !== "object" || Array.isArray(item)) return "指摘がオブジェクトでない";
  for (const k of STRINGS) if (typeof item[k] !== "string") return `${k} が文字列でない`;
  if (!Number.isInteger(item.line) || item.line < 0) return "line が 0 以上の整数でない";
  if (!Number.isInteger(item.occurrence) || item.occurrence < 1) return "occurrence が 1 以上の整数でない";
  if (typeof item.decision_needed !== "boolean") return "decision_needed が真偽値でない";
  if (item.decision_needed) {
    if (!Array.isArray(item.fix_after) || item.fix_after.length < 2 || item.fix_after.some((x) => typeof x !== "string")) return "decision_needed が true なのに fix_after が 2 つ以上の文字列の配列でない";
  } else if (typeof item.fix_after !== "string") {
    return "decision_needed が false なのに fix_after が文字列でない";
  }
  if ("url" in item) {
    if (typeof item.url !== "string" || typeof item.selector !== "string") return "画面の指摘の url か selector が文字列でない";
    const widths = Array.isArray(item.width) ? item.width : [item.width];
    if (widths.length === 0 || widths.some((w) => !Number.isInteger(w))) return "画面の指摘の width が整数か整数の配列でない";
    const photos = Array.isArray(item.photo) ? item.photo : [item.photo];
    if (photos.length === 0 || photos.some((p) => typeof p !== "string")) return "画面の指摘の photo が文字列か文字列の配列でない";
    if (typeof item.file_guessed !== "boolean") return "画面の指摘の file_guessed が真偽値でない";
  }
  return null;
}

function checkFile(file) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    return fs.existsSync(file) ? "JSON として読めない" : "ファイルがない";
  }
  if (!Array.isArray(data)) return "指摘の配列でない";
  for (let i = 0; i < data.length; i++) {
    const p = problemOf(data[i]);
    if (p) return `${i + 1} 件目の ${p}`;
  }
  return null;
}

function main() {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.log("呼び出しの誤り: 返り値のファイルのパスが 1 つ以上要る");
    process.exit(2);
  }
  let broken = 0;
  for (const f of files) {
    const p = checkFile(f);
    if (p) {
      console.log(`${f}: ${p}`);
      broken++;
    }
  }
  if (broken > 0) process.exit(1);
  console.log(`形が合う: ${files.length} 件`);
}

if (require.main === module) main();
module.exports = { problemOf, checkFile };
