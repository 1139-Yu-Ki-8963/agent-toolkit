#!/usr/bin/env node
// ゼロ依存インストーラ。node:fs/path/os/process/child_process のみ使用。
// 使い方: node scripts/install.mjs [--doctor|--diff|--apply] [--target <dir>]

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const PAYLOAD = path.join(REPO_ROOT, "payload");

// ── 引数パース ───────────────────────────────────────────────────

const args = process.argv.slice(2);
const flag = args.find((a) => a.startsWith("--") && !a.startsWith("--target"));
const targetIdx = args.indexOf("--target");
const TARGET = path.resolve(targetIdx !== -1 ? args[targetIdx + 1] : os.homedir());

// ── マッピング定義 ───────────────────────────────────────────────

// { src: 絶対パス, dst: 絶対パス, mode: "copy" | "skip-if-exists" | "merge-json" }
function buildMappings() {
  const mappings = [];

  // payload/agent-home/** → <TARGET>/agent-home/**
  const agentHomeSrc = path.join(PAYLOAD, "agent-home");
  for (const rel of walkFiles(agentHomeSrc)) {
    mappings.push({
      src: path.join(agentHomeSrc, rel),
      dst: path.join(TARGET, "agent-home", rel),
      mode: "copy",
    });
  }

  // payload/claude-config/** → <TARGET>/.claude/**（CLAUDE.md・settings-hooks.json は特殊挙動）
  const claudeConfigSrc = path.join(PAYLOAD, "claude-config");
  for (const rel of walkFiles(claudeConfigSrc)) {
    const src = path.join(claudeConfigSrc, rel);

    if (rel === "CLAUDE.md") {
      // payload/claude-config/CLAUDE.md → <TARGET>/.claude/CLAUDE.md（上書きしない）
      mappings.push({
        src,
        dst: path.join(TARGET, ".claude", "CLAUDE.md"),
        mode: "skip-if-exists",
      });
      continue;
    }

    if (rel === "settings-hooks.json") {
      // payload/claude-config/settings-hooks.json → <TARGET>/.claude/settings.json（merge）
      mappings.push({
        src,
        dst: path.join(TARGET, ".claude", "settings.json"),
        mode: "merge-json",
      });
      continue;
    }

    // それ以外（agents/** 等）→ <TARGET>/.claude/<相対パス> にそのままコピー
    mappings.push({
      src,
      dst: path.join(TARGET, ".claude", rel),
      mode: "copy",
    });
  }

  return mappings;
}

// ── ファイル列挙 ─────────────────────────────────────────────────

function walkFiles(dir) {
  const results = [];
  function recurse(cur) {
    for (const entry of fs.readdirSync(cur, { withFileTypes: true })) {
      const full = path.join(cur, entry.name);
      if (entry.isDirectory()) {
        recurse(full);
      } else {
        results.push(path.relative(dir, full));
      }
    }
  }
  recurse(dir);
  return results;
}

// ── コマンドパス正規化（~ と $HOME を統一） ──────────────────────

function normalizeCmd(cmd) {
  const home = os.homedir();
  return cmd.replace(/^\$HOME(?=\/|$)/, home).replace(/^~(?=\/|$)/, home);
}

// ── settings.json merge ─────────────────────────────────────────

function mergeSettings(srcPath, dstPath) {
  const srcText = fs.readFileSync(srcPath, "utf8");
  let srcJson;
  try {
    srcJson = JSON.parse(srcText);
  } catch (e) {
    return { ok: false, reason: `断片側 settings-hooks.json のパースに失敗: ${e.message}` };
  }

  let dstJson = { hooks: {} };
  if (fs.existsSync(dstPath)) {
    const dstText = fs.readFileSync(dstPath, "utf8");
    try {
      dstJson = JSON.parse(dstText);
    } catch (e) {
      return { ok: false, reason: `設置先 settings.json のパースに失敗（壊れている可能性あり）: ${e.message}` };
    }
  }

  if (!dstJson.hooks) dstJson.hooks = {};
  const srcHooks = srcJson.hooks || {};

  let added = 0;
  let skipped = 0;

  for (const [event, entries] of Object.entries(srcHooks)) {
    if (!dstJson.hooks[event]) dstJson.hooks[event] = [];
    const dstEntries = dstJson.hooks[event];

    for (const entry of entries) {
      const entryCommands = (entry.hooks || []).map((h) => normalizeCmd(h.command));
      const alreadyExists = dstEntries.some((dstEntry) => {
        const dstCommands = (dstEntry.hooks || []).map((h) => normalizeCmd(h.command));
        return entryCommands.every((cmd) => dstCommands.includes(cmd));
      });
      if (alreadyExists) {
        skipped++;
      } else {
        dstEntries.push(entry);
        added++;
      }
    }
  }

  return { ok: true, json: dstJson, added, skipped };
}

// ── diff 分類 ───────────────────────────────────────────────────

function classifyFile(src, dst, mode) {
  if (mode === "merge-json") {
    if (!fs.existsSync(dst)) return { kind: "新規" };
    const result = mergeSettings(src, dst);
    if (!result.ok) return { kind: "エラー", reason: result.reason };
    return { kind: "merge", added: result.added, skipped: result.skipped };
  }
  if (mode === "skip-if-exists") {
    if (!fs.existsSync(src)) return { kind: "skip", reason: "ソースなし（別途配置予定）" };
    if (!fs.existsSync(dst)) return { kind: "新規" };
    return { kind: "skip", reason: "既存のため上書きしない" };
  }
  // copy
  if (!fs.existsSync(dst)) return { kind: "新規" };
  const srcContent = fs.readFileSync(src);
  const dstContent = fs.readFileSync(dst);
  if (srcContent.equals(dstContent)) return { kind: "同一" };
  return { kind: "更新" };
}

// ── --doctor ────────────────────────────────────────────────────

function cmdDoctor() {
  const rows = [];
  let hasFatal = false;

  // Node バージョン
  const nodeVer = process.version;
  const nodeMajor = parseInt(nodeVer.slice(1).split(".")[0], 10);
  const nodeOk = nodeMajor >= 18;
  rows.push({ 項目: "Node >= 18", 状態: nodeOk ? "OK" : "FAIL（致命）", 値: nodeVer });
  if (!nodeOk) hasFatal = true;

  // git --version
  const gitVer = spawnSync("git", ["--version"], { encoding: "utf8" });
  const gitOk = gitVer.status === 0;
  rows.push({ 項目: "git インストール", 状態: gitOk ? "OK" : "警告", 値: gitOk ? gitVer.stdout.trim() : "git が見つからない" });

  // git author 設定
  const gitIdent = spawnSync("git", ["var", "GIT_AUTHOR_IDENT"], { encoding: "utf8" });
  const identOk = gitIdent.status === 0 && gitIdent.stdout.trim().length > 0;
  rows.push({ 項目: "git author 設定", 状態: identOk ? "OK" : "警告", 値: identOk ? gitIdent.stdout.trim() : "未設定" });

  // <TARGET> 書き込み可否
  const targetExists = fs.existsSync(TARGET);
  let targetWritable = false;
  if (targetExists) {
    try { fs.accessSync(TARGET, fs.constants.W_OK); targetWritable = true; } catch {}
  }
  rows.push({ 項目: `${TARGET} 書き込み`, 状態: targetWritable ? "OK" : "FAIL（致命）", 値: targetExists ? (targetWritable ? "書き込み可" : "書き込み不可") : "存在しない" });
  if (!targetWritable) hasFatal = true;

  // <TARGET>/.claude 書き込み可否
  const claudeDir = path.join(TARGET, ".claude");
  const claudeExists = fs.existsSync(claudeDir);
  let claudeWritable = false;
  if (claudeExists) {
    try { fs.accessSync(claudeDir, fs.constants.W_OK); claudeWritable = true; } catch {}
  } else {
    claudeWritable = targetWritable; // 親が書き込み可なら作成可能
  }
  rows.push({ 項目: `${claudeDir} 書き込み`, 状態: claudeWritable ? "OK" : "FAIL（致命）", 値: claudeExists ? (claudeWritable ? "書き込み可" : "書き込み不可") : "未作成（作成可）" });
  if (!claudeWritable) hasFatal = true;

  // 既存 agent-home の有無
  const agentHomeExists = fs.existsSync(path.join(TARGET, "agent-home"));
  rows.push({ 項目: "既存 agent-home", 状態: agentHomeExists ? "あり（上書き対象）" : "なし（新規）", 値: "" });

  // 既存 settings.json の有無
  const settingsExists = fs.existsSync(path.join(TARGET, ".claude", "settings.json"));
  rows.push({ 項目: "既存 settings.json", 状態: settingsExists ? "あり（merge 対象）" : "なし（新規）", 値: "" });

  // 表示
  console.log("\n前提診断");
  console.log("─".repeat(70));
  const col1 = Math.max(...rows.map((r) => r["項目"].length)) + 2;
  const col2 = Math.max(...rows.map((r) => r["状態"].length)) + 2;
  for (const row of rows) {
    const p1 = row["項目"].padEnd(col1);
    const p2 = row["状態"].padEnd(col2);
    console.log(`  ${p1}${p2}${row["値"]}`);
  }
  console.log("─".repeat(70));
  if (hasFatal) {
    console.log("致命的な問題があります。解消してから --apply を実行してください。");
    process.exit(1);
  } else {
    console.log("問題なし。--apply で設置できます。");
  }
}

// ── --diff ──────────────────────────────────────────────────────

function cmdDiff() {
  const mappings = buildMappings();
  const classified = mappings.map((m) => ({ ...m, result: classifyFile(m.src, m.dst, m.mode) }));

  const counts = { 新規: 0, 更新: 0, 同一: 0, skip: 0, merge: 0, エラー: 0 };
  for (const c of classified) counts[c.result.kind] = (counts[c.result.kind] || 0) + 1;

  console.log("\nDiff プレビュー");
  console.log("─".repeat(70));

  // merge プレビュー
  const mergeItem = classified.find((c) => c.mode === "merge-json");
  if (mergeItem) {
    const r = mergeItem.result;
    if (r.kind === "新規") {
      console.log(`  [merge] ${path.relative(TARGET, mergeItem.dst)} → 新規作成`);
    } else if (r.kind === "merge") {
      console.log(`  [merge] ${path.relative(TARGET, mergeItem.dst)} → 追加 ${r.added} エントリ / 登録済み ${r.skipped} エントリ`);
    } else if (r.kind === "エラー") {
      console.log(`  [エラー] ${path.relative(TARGET, mergeItem.dst)} → ${r.reason}`);
    }
  }

  // ファイル一覧（merge と skip 以外）
  const fileItems = classified.filter((c) => c.mode === "copy" || c.mode === "skip-if-exists");
  const interesting = fileItems.filter((c) => c.result.kind !== "同一");
  const shown = interesting.slice(0, 20);
  for (const item of shown) {
    const rel = path.relative(TARGET, item.dst);
    console.log(`  [${item.result.kind}] ${rel}${item.result.reason ? " — " + item.result.reason : ""}`);
  }
  if (interesting.length > 20) {
    console.log(`  ... 他 ${interesting.length - 20} 件`);
  }

  console.log("─".repeat(70));
  console.log(`  新規: ${counts["新規"] || 0}  更新: ${counts["更新"] || 0}  同一: ${counts["同一"] || 0}  skip: ${counts["skip"] || 0}`);
}

// ── --apply ─────────────────────────────────────────────────────

function cmdApply() {
  // diff サマリを先に表示
  cmdDiff();
  console.log("\n設置を開始します...\n");

  const mappings = buildMappings();

  // ① ディレクトリ作成
  const dirs = new Set(mappings.map((m) => path.dirname(m.dst)));
  for (const d of dirs) fs.mkdirSync(d, { recursive: true });
  fs.mkdirSync(path.join(TARGET, ".claude"), { recursive: true });

  let copied = 0, updated = 0, skipped = 0, errors = 0;

  for (const m of mappings) {
    const rel = path.relative(TARGET, m.dst);

    if (m.mode === "copy") {
      const result = classifyFile(m.src, m.dst, m.mode);
      if (result.kind === "新規") {
        fs.mkdirSync(path.dirname(m.dst), { recursive: true });
        fs.copyFileSync(m.src, m.dst);
        console.log(`  [新規] ${rel}`);
        copied++;
      } else if (result.kind === "更新") {
        fs.copyFileSync(m.src, m.dst);
        console.log(`  [更新] ${rel}`);
        updated++;
      } else {
        skipped++;
      }
      continue;
    }

    if (m.mode === "skip-if-exists") {
      if (!fs.existsSync(m.src)) {
        console.log(`  [skip] ${rel} — ソースなし（別途配置予定）`);
        skipped++;
        continue;
      }
      if (fs.existsSync(m.dst)) {
        console.log(`  [skip] ${rel} — 既存のため上書きしない`);
        skipped++;
      } else {
        fs.mkdirSync(path.dirname(m.dst), { recursive: true });
        fs.copyFileSync(m.src, m.dst);
        console.log(`  [新規] ${rel}`);
        copied++;
      }
      continue;
    }

    if (m.mode === "merge-json") {
      // バックアップ
      if (fs.existsSync(m.dst)) {
        const iso = new Date().toISOString().replace(/:/g, "-").replace(/\..+/, "");
        const bak = `${m.dst}.bak.${iso}`;
        fs.copyFileSync(m.dst, bak);
        console.log(`  [backup] ${path.relative(TARGET, bak)}`);
      }

      const result = mergeSettings(m.src, m.dst);
      if (!result.ok) {
        console.error(`  [エラー] ${rel} — ${result.reason}`);
        errors++;
        continue;
      }

      fs.mkdirSync(path.dirname(m.dst), { recursive: true });
      fs.writeFileSync(m.dst, JSON.stringify(result.json, null, 2) + "\n");
      if (result.added > 0) {
        console.log(`  [merge] ${rel} — ${result.added} エントリ追加`);
        copied++;
      } else {
        console.log(`  [skip] ${rel} — 全エントリ登録済み（${result.skipped} 件）`);
        skipped++;
      }
      continue;
    }
  }

  // ⑤ sessions/.skill-log を mkdir -p
  const skillLogDir = path.join(TARGET, "agent-home", "sessions", ".skill-log");
  fs.mkdirSync(skillLogDir, { recursive: true });
  console.log(`  [mkdir] agent-home/sessions/.skill-log/`);

  console.log(`\n設置完了: 新規 ${copied} / 更新 ${updated} / skip ${skipped}${errors > 0 ? ` / エラー ${errors}` : ""}\n`);

  if (errors > 0) {
    console.error("エラーが発生しました。上記を確認してください。");
    process.exit(1);
  }

  // ⑥ generate → verify（ポータルが完全同梱されている環境のみ）
  const agentHome = path.join(TARGET, "agent-home");
  const manageScript = path.join(agentHome, "skills", "managing-agent-configs", "scripts", "manage-portal.mjs");

  if (!fs.existsSync(manageScript)) {
    console.error(`[エラー] manage-portal.mjs が見つかりません: ${manageScript}`);
    process.exit(1);
  }

  // ai-management-portal は縮小同梱版であり、generate は catalog 群を readFileSync
  // する（新規作成しない）。前提ファイルが無い環境では generate/verify をスキップし、
  // 設置自体は成功として扱う。
  const portalProbe = path.join(agentHome, "ai-management-portal", "catalog", "dictionaries.html");
  if (!fs.existsSync(portalProbe)) {
    console.log("\n" + "─".repeat(70));
    console.log("ポータルが完全同梱されていないため generate/verify をスキップしました。設置は完了しています。");
    return;
  }

  console.log("ポータル generate を実行中...");
  const genResult = spawnSync("node", [manageScript, "generate"], {
    cwd: agentHome,
    stdio: "inherit",
    encoding: "utf8",
  });
  if (genResult.status !== 0) {
    console.error("generate が失敗しました。");
    process.exit(1);
  }

  console.log("\nポータル verify を実行中...");
  const verResult = spawnSync("node", [manageScript, "verify"], {
    cwd: agentHome,
    stdio: "inherit",
    encoding: "utf8",
  });

  // ⑦ 最終サマリ
  console.log("\n" + "─".repeat(70));
  if (verResult.status !== 0) {
    console.error("verify が失敗しました。インストールは不完全な状態です。");
    process.exit(1);
  }
  console.log("インストール完了。verify PASS。");
}

// ── エントリポイント ─────────────────────────────────────────────

switch (flag) {
  case "--doctor":
    cmdDoctor();
    break;
  case "--diff":
    cmdDiff();
    break;
  case "--apply":
    cmdApply();
    break;
  default:
    console.error("使い方: node scripts/install.mjs [--doctor|--diff|--apply] [--target <dir>]");
    process.exit(1);
}
