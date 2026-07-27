#!/usr/bin/env node
// ゼロ依存インストーラ。node:fs/path/os/process/child_process のみ使用。
// 使い方: node scripts/install.mjs [--doctor|--diff|--apply] [--target <dir>] [--runtime claude|codex|all]

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import readline from "node:readline";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const PAYLOAD = path.join(REPO_ROOT, "payload");
const GLOBAL_SETUP = path.join(PAYLOAD, "claudecode-global-setup");

// ── 引数パース ───────────────────────────────────────────────────

const args = process.argv.slice(2);
const actions = new Set(["--doctor", "--diff", "--apply"]);
const flag = args.find((a) => actions.has(a));
const targetIdx = args.indexOf("--target");
const TARGET = path.resolve(targetIdx !== -1 ? args[targetIdx + 1] : os.homedir());
const runtimeIdx = args.indexOf("--runtime");
const RUNTIME = runtimeIdx !== -1 ? args[runtimeIdx + 1] : "claude";
if (!["claude", "codex", "all"].includes(RUNTIME)) {
  console.error(`不正な runtime: ${RUNTIME || "(未指定)"}。claude / codex / all を指定してください。`);
  process.exit(1);
}

// ── マッピング定義 ───────────────────────────────────────────────

// { src: 絶対パス, dst: 絶対パス, mode: "copy" | "skip-if-exists" | "merge-json" | "merge-hooks-json" }
function buildMappings() {
  const mappings = [];

  // payload/claudecode-global-setup/agent-home/** → <TARGET>/agent-home/**
  const agentHomeSrc = path.join(GLOBAL_SETUP, "agent-home");
  for (const rel of walkFiles(agentHomeSrc)) {
    mappings.push({
      src: path.join(agentHomeSrc, rel),
      dst: path.join(TARGET, "agent-home", rel),
      mode: "copy",
    });
  }

  // payload/reverse-docs-skills/** → <TARGET>/reverse-docs-skills/**
  const reverseDocsSkillsSrc = path.join(PAYLOAD, "reverse-docs-skills");
  for (const rel of walkFiles(reverseDocsSkillsSrc)) {
    mappings.push({
      src: path.join(reverseDocsSkillsSrc, rel),
      dst: path.join(TARGET, "reverse-docs-skills", rel),
      mode: "copy",
    });
  }

  // payload/claudecode-global-setup/claude-config/** → <TARGET>/.claude/**（CLAUDE.md・settings-hooks.json は特殊挙動）
  if (RUNTIME === "claude" || RUNTIME === "all") {
    const claudeConfigSrc = path.join(GLOBAL_SETUP, "claude-config");
    for (const rel of walkFiles(claudeConfigSrc)) {
      const src = path.join(claudeConfigSrc, rel);

      if (rel === "CLAUDE.md") {
        mappings.push({
          src,
          dst: path.join(TARGET, ".claude", "CLAUDE.md"),
          mode: "skip-if-exists",
        });
        continue;
      }

      if (rel === "settings-hooks.json") {
        mappings.push({
          src,
          dst: path.join(TARGET, ".claude", "settings.json"),
          mode: "merge-json",
        });
        continue;
      }

      mappings.push({
        src,
        dst: path.join(TARGET, ".claude", rel),
        mode: "copy",
      });
    }
  }

  if (RUNTIME === "codex" || RUNTIME === "all") {
    mappings.push({
      src: path.join(GLOBAL_SETUP, "codex-config", "hooks.json"),
      dst: path.join(TARGET, ".codex", "hooks.json"),
      mode: "merge-hooks-json",
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

  // outputStyle: src にあり dst になければコピー
  if (srcJson.outputStyle && !dstJson.outputStyle) {
    dstJson.outputStyle = srcJson.outputStyle;
  }

  // permissions: 配列フィールドをマージ、スカラーは src 優先で補完
  if (srcJson.permissions) {
    if (!dstJson.permissions) dstJson.permissions = {};
    for (const key of ["allow", "deny", "ask"]) {
      if (srcJson.permissions[key]) {
        if (!dstJson.permissions[key]) dstJson.permissions[key] = [];
        for (const item of srcJson.permissions[key]) {
          if (!dstJson.permissions[key].includes(item)) {
            dstJson.permissions[key].push(item);
          }
        }
      }
    }
    if (srcJson.permissions.defaultMode && !dstJson.permissions.defaultMode) {
      dstJson.permissions.defaultMode = srcJson.permissions.defaultMode;
    }
    if (srcJson.permissions.additionalDirectories) {
      if (!dstJson.permissions.additionalDirectories) dstJson.permissions.additionalDirectories = [];
      for (let dir of srcJson.permissions.additionalDirectories) {
        dir = dir.replace(/__HOME__/g, TARGET);
        if (!dstJson.permissions.additionalDirectories.includes(dir)) {
          dstJson.permissions.additionalDirectories.push(dir);
        }
      }
    }
  }

  return { ok: true, json: dstJson, added, skipped };
}

function mergeCodexHooks(srcPath, dstPath) {
  let srcJson;
  try {
    srcJson = JSON.parse(fs.readFileSync(srcPath, "utf8"));
  } catch (e) {
    return { ok: false, reason: `配布側 hooks.json のパースに失敗: ${e.message}` };
  }

  let dstJson = { hooks: {} };
  if (fs.existsSync(dstPath)) {
    try {
      dstJson = JSON.parse(fs.readFileSync(dstPath, "utf8"));
    } catch (e) {
      return { ok: false, reason: `設置先 hooks.json のパースに失敗（変更せず停止）: ${e.message}` };
    }
  }
  if (!dstJson || typeof dstJson !== "object" || Array.isArray(dstJson)) {
    return { ok: false, reason: "設置先 hooks.json は JSON object ではありません（変更せず停止）" };
  }
  if (!dstJson.hooks) dstJson.hooks = {};
  if (typeof dstJson.hooks !== "object" || Array.isArray(dstJson.hooks)) {
    return { ok: false, reason: "設置先 hooks.json の hooks は object ではありません（変更せず停止）" };
  }

  let added = 0;
  let skipped = 0;
  for (const [event, entries] of Object.entries(srcJson.hooks || {})) {
    if (!Array.isArray(entries)) {
      return { ok: false, reason: `配布側 hooks.${event} は配列ではありません` };
    }
    if (!dstJson.hooks[event]) dstJson.hooks[event] = [];
    if (!Array.isArray(dstJson.hooks[event])) {
      return { ok: false, reason: `設置先 hooks.${event} は配列ではありません（変更せず停止）` };
    }
    for (const entry of entries) {
      const entryCommands = (entry.hooks || []).map((h) => normalizeCmd(h.command || ""));
      const alreadyExists = dstJson.hooks[event].some((dstEntry) => {
        const dstCommands = (dstEntry.hooks || []).map((h) => normalizeCmd(h.command || ""));
        return entryCommands.length > 0 && entryCommands.every((cmd) => dstCommands.includes(cmd));
      });
      if (alreadyExists) {
        skipped++;
      } else {
        dstJson.hooks[event].push(entry);
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
  if (mode === "merge-hooks-json") {
    if (!fs.existsSync(dst)) return { kind: "新規" };
    const result = mergeCodexHooks(src, dst);
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
  rows.push({ 項目: "runtime", 状態: "OK", 値: RUNTIME });

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

  for (const runtimeDir of [
    ...(RUNTIME === "claude" || RUNTIME === "all" ? [".claude"] : []),
    ...(RUNTIME === "codex" || RUNTIME === "all" ? [".codex"] : []),
  ]) {
    const configDir = path.join(TARGET, runtimeDir);
    const configExists = fs.existsSync(configDir);
    let configWritable = false;
    if (configExists) {
      try { fs.accessSync(configDir, fs.constants.W_OK); configWritable = true; } catch {}
    } else {
      configWritable = targetWritable;
    }
    rows.push({ 項目: `${configDir} 書き込み`, 状態: configWritable ? "OK" : "FAIL（致命）", 値: configExists ? (configWritable ? "書き込み可" : "書き込み不可") : "未作成（作成可）" });
    if (!configWritable) hasFatal = true;
  }

  // 既存 agent-home の有無
  const agentHomeExists = fs.existsSync(path.join(TARGET, "agent-home"));
  rows.push({ 項目: "既存 agent-home", 状態: agentHomeExists ? "あり（上書き対象）" : "なし（新規）", 値: "" });

  if (RUNTIME === "claude" || RUNTIME === "all") {
    const settingsExists = fs.existsSync(path.join(TARGET, ".claude", "settings.json"));
    rows.push({ 項目: "既存 Claude settings.json", 状態: settingsExists ? "あり（merge 対象）" : "なし（新規）", 値: "" });
  }
  if (RUNTIME === "codex" || RUNTIME === "all") {
    const hooksPath = path.join(TARGET, ".codex", "hooks.json");
    if (!fs.existsSync(hooksPath)) {
      rows.push({ 項目: "既存 Codex hooks.json", 状態: "なし（新規）", 値: "" });
    } else {
      const result = mergeCodexHooks(path.join(GLOBAL_SETUP, "codex-config", "hooks.json"), hooksPath);
      rows.push({ 項目: "既存 Codex hooks.json", 状態: result.ok ? "あり（merge 対象）" : "FAIL（致命）", 値: result.ok ? "" : result.reason });
      if (!result.ok) hasFatal = true;
    }
  }

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
  for (const mergeItem of classified.filter((c) => c.mode === "merge-json" || c.mode === "merge-hooks-json")) {
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
  console.log(`  runtime: ${RUNTIME}  新規: ${counts["新規"] || 0}  更新: ${counts["更新"] || 0}  同一: ${counts["同一"] || 0}  skip: ${counts["skip"] || 0}  merge: ${counts["merge"] || 0}  エラー: ${counts["エラー"] || 0}`);
}

// ── --apply ─────────────────────────────────────────────────────

async function cmdApply() {
  // diff サマリを先に表示
  cmdDiff();
  console.log("\n設置を開始します...\n");

  const mappings = buildMappings();
  const preflightErrors = mappings
    .map((m) => ({ mapping: m, result: classifyFile(m.src, m.dst, m.mode) }))
    .filter(({ result }) => result.kind === "エラー");
  if (preflightErrors.length > 0) {
    for (const { mapping, result } of preflightErrors) {
      console.error(`  [エラー] ${path.relative(TARGET, mapping.dst)} — ${result.reason}`);
    }
    console.error("設定ファイルが不正なため、変更せず停止しました。");
    process.exit(1);
  }

  // ① ディレクトリ作成
  const dirs = new Set(mappings.map((m) => path.dirname(m.dst)));
  for (const d of dirs) fs.mkdirSync(d, { recursive: true });

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

    if (m.mode === "merge-json" || m.mode === "merge-hooks-json") {
      // バックアップ
      if (fs.existsSync(m.dst)) {
        const iso = new Date().toISOString().replace(/:/g, "-").replace(/\..+/, "");
        const bak = `${m.dst}.bak.${iso}`;
        fs.copyFileSync(m.dst, bak);
        console.log(`  [backup] ${path.relative(TARGET, bak)}`);
      }

      const result = m.mode === "merge-json"
        ? mergeSettings(m.src, m.dst)
        : mergeCodexHooks(m.src, m.dst);
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

  // symlink: <TARGET>/.claude/rules → <TARGET>/agent-home/rules
  //          <TARGET>/.claude/skills → <TARGET>/agent-home/skills
  const symlinks = RUNTIME === "claude" || RUNTIME === "all"
    ? [
        { link: path.join(TARGET, ".claude", "rules"), target: path.join(TARGET, "agent-home", "rules") },
        { link: path.join(TARGET, ".claude", "skills"), target: path.join(TARGET, "agent-home", "skills") },
        { link: path.join(TARGET, ".claude", "agents"), target: path.join(TARGET, "agent-home", "agents") },
      ]
    : [];
  for (const { link, target: linkTarget } of symlinks) {
    const relTarget = path.relative(path.dirname(link), linkTarget);
    if (fs.existsSync(link)) {
      const stat = fs.lstatSync(link);
      if (stat.isSymbolicLink()) {
        const existing = fs.readlinkSync(link);
        if (existing === relTarget) {
          console.log(`  [skip] ${path.relative(TARGET, link)} → 既存 symlink（正常）`);
          continue;
        }
        fs.unlinkSync(link);
      } else {
        console.log(`  [skip] ${path.relative(TARGET, link)} — 実体のため symlink 作成スキップ`);
        continue;
      }
    }
    fs.symlinkSync(relTarget, link);
    console.log(`  [symlink] ${path.relative(TARGET, link)} → ${relTarget}`);
  }

  console.log(`\n設置完了: 新規 ${copied} / 更新 ${updated} / skip ${skipped}${errors > 0 ? ` / エラー ${errors}` : ""}\n`);

  if (errors > 0) {
    console.error("エラーが発生しました。上記を確認してください。");
    process.exit(1);
  }

  // ⑥ 未登録スキル検出 → 確認 → generate → verify
  const agentHome = path.join(TARGET, "agent-home");
  const manageScript = path.join(agentHome, "skills", "managing-agent-configs", "scripts", "manage-portal.mjs");

  if (!fs.existsSync(manageScript)) {
    console.error(`[エラー] manage-portal.mjs が見つかりません: ${manageScript}`);
    process.exit(1);
  }

  const portalRuntimeHome = fs.mkdtempSync(path.join(os.tmpdir(), "agent-toolkit-portal-"));
  fs.mkdirSync(path.join(portalRuntimeHome, ".claude"), { recursive: true });
  fs.symlinkSync(agentHome, path.join(portalRuntimeHome, "agent-home"));
  fs.symlinkSync(path.join(agentHome, "rules"), path.join(portalRuntimeHome, ".claude", "rules"));
  fs.symlinkSync(path.join(agentHome, "agents"), path.join(portalRuntimeHome, ".claude", "agents"));
  const installedClaudeSettings = path.join(TARGET, ".claude", "settings.json");
  const runtimeClaudeSettings = path.join(portalRuntimeHome, ".claude", "settings.json");
  if (fs.existsSync(installedClaudeSettings)) {
    fs.symlinkSync(installedClaudeSettings, runtimeClaudeSettings);
  } else {
    fs.writeFileSync(runtimeClaudeSettings, "{}\n");
  }
  const portalEnv = { ...process.env, HOME: portalRuntimeHome };
  let compatibilityAliasLink;

  try {
  console.log("未登録スキルを検出中...");
  const checkResult = spawnSync("node", [manageScript, "check-unregistered"], {
    cwd: agentHome,
    encoding: "utf8",
    env: portalEnv,
  });
  const unregistered = JSON.parse(checkResult.stdout || "[]");

  let skipVerify = false;

  if (unregistered.length > 0) {
    console.log(`\n未登録スキルが ${unregistered.length} 件見つかりました:`);
    for (const id of unregistered) {
      console.log(`  - ${id}`);
    }
    console.log(`\n(A) 全て登録して続行（カテゴリ "other" で登録 + ガイドスタブ生成）`);
    console.log(`(B) 登録せず verify をスキップして続行`);
    console.log(`(C) 中止`);

    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = await new Promise((resolve) => {
      rl.question("\n選択 [A/B/C]: ", (ans) => { rl.close(); resolve(ans.trim().toUpperCase()); });
    });

    if (answer === "C") {
      throw new Error("インストールを中止しました。");
    }

    if (answer === "A") {
      console.log("\n未登録スキルを登録中...");
      const regResult = spawnSync("node", [manageScript, "register-skills", unregistered.join(",")], {
        cwd: agentHome,
        stdio: "inherit",
        encoding: "utf8",
        env: portalEnv,
      });
      if (regResult.status !== 0) {
        throw new Error("register-skills が失敗しました。");
      }
    } else {
      skipVerify = true;
    }
  }

  if (!skipVerify) {
    console.log("\nポータル generate を実行中...");
    const genResult = spawnSync("node", [manageScript, "generate"], {
      cwd: agentHome,
      stdio: "inherit",
      encoding: "utf8",
      env: portalEnv,
    });
    if (genResult.status !== 0) {
      throw new Error("generate が失敗しました。");
    }
  }

  console.log("\n" + "─".repeat(70));
  if (skipVerify) {
    console.log("verify をスキップしました（未登録スキルは未登録のままです）。");
    console.log("インストール完了（verify スキップ）。");
  } else {
    console.log("\nポータル verify を実行中...");
    const reverseAliasTarget = path.join(
      TARGET,
      "reverse-docs-skills",
      ".claude",
      "skills",
      "generating-screen-list-for-reverse-docs"
    );
    compatibilityAliasLink = path.join(
      agentHome,
      "skills",
      "generating-screen-list-for-reverse-docs"
    );
    if (fs.existsSync(reverseAliasTarget) && !fs.existsSync(compatibilityAliasLink)) {
      fs.symlinkSync(reverseAliasTarget, compatibilityAliasLink);
    } else {
      compatibilityAliasLink = undefined;
    }
    const verResult = spawnSync("node", [manageScript, "verify"], {
      cwd: agentHome,
      stdio: "inherit",
      encoding: "utf8",
      env: portalEnv,
    });
    if (compatibilityAliasLink) {
      fs.unlinkSync(compatibilityAliasLink);
      compatibilityAliasLink = undefined;
    }
    if (verResult.status !== 0) {
      throw new Error("verify が失敗しました。インストールは不完全な状態です。");
    }
    console.log("インストール完了。verify PASS。");
  }
  } finally {
    if (compatibilityAliasLink && fs.existsSync(compatibilityAliasLink)) {
      fs.unlinkSync(compatibilityAliasLink);
    }
    fs.rmSync(portalRuntimeHome, { recursive: true, force: true });
  }
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
    await cmdApply();
    break;
  default:
    console.error("使い方: node scripts/install.mjs [--doctor|--diff|--apply] [--target <dir>] [--runtime claude|codex|all]");
    process.exit(1);
}
