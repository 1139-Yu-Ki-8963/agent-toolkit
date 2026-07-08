#!/usr/bin/env node
// 正本（~/agent-home・~/.claude）→ payload/ の乖離検知・同期スクリプト。
// ゼロ依存。node:fs/path/os/process のみ使用。
// 使い方: node scripts/sync-payload.mjs [--list|--check|--apply] [--only <dst-prefix>]
//   --only <dst-prefix>: dst が指定 prefix で始まる mapping だけを対象に絞り込む
//   （例: --only payload/reverse-docs-skills）

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const MANIFEST_PATH = path.join(__dirname, "sync-manifest.json");

const args = process.argv.slice(2);
const flag = args.find((a) => ["--list", "--check", "--apply"].includes(a));

const onlyIndex = args.indexOf("--only");
let onlyPrefix = null;
if (onlyIndex !== -1) {
  onlyPrefix = args[onlyIndex + 1];
  if (!onlyPrefix || onlyPrefix.startsWith("--")) {
    console.error("--only には dst prefix を指定してください（例: --only payload/reverse-docs-skills）");
    process.exit(1);
  }
}

// ── パス解決（~ を os.homedir() で解決。/Users/... のリテラルは書かない） ──

function resolveHome(p) {
  const home = os.homedir();
  if (p === "~") return home;
  if (p.startsWith("~/")) return path.join(home, p.slice(2));
  return p;
}

function loadManifest() {
  const text = fs.readFileSync(MANIFEST_PATH, "utf8");
  const json = JSON.parse(text);
  let mappings = json.mappings;
  if (onlyPrefix !== null) {
    mappings = mappings.filter((m) => m.dst.startsWith(onlyPrefix));
    if (mappings.length === 0) {
      console.error(`--only ${onlyPrefix} に一致する mapping がありません`);
    }
  }
  return mappings.map((m) => ({
    ...m,
    srcAbs: resolveHome(m.src),
    dstAbs: path.join(REPO_ROOT, m.dst),
  }));
}

// ── ファイル列挙（mirror 用。node_modules・.DS_Store を除外） ──

const EXCLUDE_NAMES = new Set(["node_modules", ".DS_Store"]);
const EXCLUDE_SUFFIXES = [".local.yml"];

function isExcluded(name) {
  return EXCLUDE_NAMES.has(name) || EXCLUDE_SUFFIXES.some((suffix) => name.endsWith(suffix));
}

function walkFiles(dir) {
  const results = [];
  function recurse(cur) {
    let entries;
    try {
      entries = fs.readdirSync(cur, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (isExcluded(entry.name)) continue;
      const full = path.join(cur, entry.name);
      if (entry.isDirectory()) {
        recurse(full);
      } else if (entry.isFile()) {
        results.push(path.relative(dir, full));
      }
    }
  }
  recurse(dir);
  return results;
}

// ── mirror mapping の overlay 解決 ──
// 同じ dst ディレクトリ配下を指す file mapping は「期待されるファイル」として
// mirror の削除対象・内容比較対象から除外し、file mapping 側の src と比較する。

function buildOverlayIndex(mappings) {
  // key: mirror mapping の dstAbs, value: Map<relPathFromMirrorDst, fileMapping>
  const overlays = new Map();
  const mirrorMappings = mappings.filter((m) => m.mode === "mirror");
  const fileMappings = mappings.filter((m) => m.mode === "file");

  for (const mirror of mirrorMappings) {
    const overlayMap = new Map();
    for (const file of fileMappings) {
      const rel = path.relative(mirror.dstAbs, file.dstAbs);
      // rel が ".." で始まらない = mirror.dstAbs 配下
      if (!rel.startsWith("..") && !path.isAbsolute(rel)) {
        overlayMap.set(rel, file);
      }
    }
    overlays.set(mirror.dstAbs, overlayMap);
  }
  return overlays;
}

// ── --check / --apply 共通のドリフト計算 ──

function compareFiles(srcAbs, dstAbs) {
  const srcExists = fs.existsSync(srcAbs);
  const dstExists = fs.existsSync(dstAbs);
  if (!srcExists && !dstExists) return "same";
  if (!srcExists || !dstExists) return "drift";
  const srcBuf = fs.readFileSync(srcAbs);
  const dstBuf = fs.readFileSync(dstAbs);
  return srcBuf.equals(dstBuf) ? "same" : "drift";
}

function computeMirrorDrift(mirror, overlayMap) {
  const drifts = [];
  if (!fs.existsSync(mirror.srcAbs)) {
    return { skip: true, drifts };
  }

  const srcFiles = new Set(walkFiles(mirror.srcAbs));
  const dstFiles = fs.existsSync(mirror.dstAbs) ? new Set(walkFiles(mirror.dstAbs)) : new Set();

  // src に存在するファイル: overlay があればその file mapping の src と比較、
  // なければ mirror.srcAbs 側と比較
  for (const rel of srcFiles) {
    if (overlayMap.has(rel)) continue; // overlay 側の file mapping が別途担当する
    const srcAbs = path.join(mirror.srcAbs, rel);
    const dstAbs = path.join(mirror.dstAbs, rel);
    if (compareFiles(srcAbs, dstAbs) === "drift") {
      drifts.push({ type: dstFiles.has(rel) ? "modified" : "missing", rel, srcAbs, dstAbs });
    }
  }

  // dst にのみ存在するファイル（overlay 期待ファイルは除外）→ 削除対象
  for (const rel of dstFiles) {
    if (overlayMap.has(rel)) continue;
    if (!srcFiles.has(rel)) {
      drifts.push({ type: "extra", rel, srcAbs: path.join(mirror.srcAbs, rel), dstAbs: path.join(mirror.dstAbs, rel) });
    }
  }

  return { skip: false, drifts };
}

// ── --list ──

function cmdList() {
  const mappings = loadManifest();
  console.log("\nsync-manifest.json マッピング一覧");
  console.log("─".repeat(70));
  for (const m of mappings) {
    console.log(`  [${m.mode}] ${m.src} -> ${m.dst}`);
    if (m.note) console.log(`      note: ${m.note}`);
  }
  console.log("─".repeat(70));
  console.log(`  合計 ${mappings.length} 件`);
}

// ── --check ──

function cmdCheck() {
  const mappings = loadManifest();
  const overlays = buildOverlayIndex(mappings);
  let hasDrift = false;

  console.log("\n乖離チェック");
  console.log("─".repeat(70));

  for (const m of mappings) {
    if (m.mode === "manual") {
      if (!fs.existsSync(m.srcAbs)) {
        console.log(`  SKIP (source missing) ${m.dst}`);
        continue;
      }
      let differs = "no";
      if (fs.statSync(m.srcAbs).isDirectory()) {
        // ディレクトリの manual は情報表示のみ（差分内容の詳細比較はしない）
        differs = "unknown（ディレクトリ）";
      } else {
        differs = compareFiles(m.srcAbs, m.dstAbs) === "drift" ? "yes" : "no";
      }
      console.log(`  MANUAL ${m.dst} (differs: ${differs})`);
      continue;
    }

    if (m.mode === "file") {
      if (!fs.existsSync(m.srcAbs)) {
        console.log(`  SKIP (source missing) ${m.dst}`);
        continue;
      }
      const result = compareFiles(m.srcAbs, m.dstAbs);
      if (result === "drift") {
        console.log(`  DRIFT file ${m.dst}`);
        hasDrift = true;
      }
      continue;
    }

    if (m.mode === "mirror") {
      const { skip, drifts } = computeMirrorDrift(m, overlays.get(m.dstAbs) || new Map());
      if (skip) {
        console.log(`  SKIP (source missing) ${m.dst}`);
        continue;
      }
      for (const d of drifts) {
        console.log(`  DRIFT mirror ${path.join(m.dst, d.rel)} (${d.type})`);
        hasDrift = true;
      }
      continue;
    }
  }

  console.log("─".repeat(70));
  if (hasDrift) {
    console.log("乖離あり。node scripts/sync-payload.mjs --apply で同期してください。");
    process.exit(1);
  } else {
    console.log("乖離なし（manual は対象外）。");
  }
}

// ── --apply ──

function cmdApply() {
  const mappings = loadManifest();
  const overlays = buildOverlayIndex(mappings);
  let applied = 0;
  let skippedNoSrc = 0;

  console.log("\n同期を適用します（mirror / file のみ。manual は書き込みません）");
  console.log("─".repeat(70));

  for (const m of mappings) {
    if (m.mode === "manual") {
      console.log(`  SKIP (manual) ${m.dst}`);
      continue;
    }

    if (m.mode === "file") {
      if (!fs.existsSync(m.srcAbs)) {
        console.log(`  SKIP (source missing) ${m.dst}`);
        skippedNoSrc++;
        continue;
      }
      const result = compareFiles(m.srcAbs, m.dstAbs);
      if (result === "drift") {
        fs.mkdirSync(path.dirname(m.dstAbs), { recursive: true });
        fs.copyFileSync(m.srcAbs, m.dstAbs);
        console.log(`  APPLIED file ${m.dst}`);
        applied++;
      } else {
        console.log(`  OK file ${m.dst}`);
      }
      continue;
    }

    if (m.mode === "mirror") {
      const overlayMap = overlays.get(m.dstAbs) || new Map();
      const { skip, drifts } = computeMirrorDrift(m, overlayMap);
      if (skip) {
        console.log(`  SKIP (source missing) ${m.dst}`);
        skippedNoSrc++;
        continue;
      }
      for (const d of drifts) {
        if (d.type === "extra") {
          fs.rmSync(d.dstAbs, { force: true });
          console.log(`  REMOVED mirror ${path.join(m.dst, d.rel)}`);
        } else {
          fs.mkdirSync(path.dirname(d.dstAbs), { recursive: true });
          fs.copyFileSync(d.srcAbs, d.dstAbs);
          console.log(`  APPLIED mirror ${path.join(m.dst, d.rel)}`);
        }
        applied++;
      }
      if (drifts.length === 0) {
        console.log(`  OK mirror ${m.dst}`);
      }
      continue;
    }
  }

  console.log("─".repeat(70));
  console.log(`適用完了: ${applied} 件反映 / ${skippedNoSrc} 件ソースなし skip`);
}

// ── エントリポイント ──

switch (flag) {
  case "--list":
    cmdList();
    break;
  case "--check":
    cmdCheck();
    break;
  case "--apply":
    cmdApply();
    break;
  default:
    console.error("使い方: node scripts/sync-payload.mjs [--list|--check|--apply] [--only <dst-prefix>]");
    process.exit(1);
}
