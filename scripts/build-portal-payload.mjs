#!/usr/bin/env node
// 公開済み portal を基底に、公開承認済みの Skill・Rule 表示だけを再生成する。

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const SCRIPT_DIR = path.dirname(new URL(import.meta.url).pathname);
const REPO_ROOT = path.resolve(SCRIPT_DIR, "..");
const DEFAULT_DST = path.join(
  REPO_ROOT,
  "payload",
  "claudecode-global-setup",
  "agent-home",
  "ai-management-portal"
);
const PUBLIC_PORTAL_PREFIX =
  "payload/claudecode-global-setup/agent-home/ai-management-portal";

function countFiles(dir) {
  let n = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) n += countFiles(path.join(dir, e.name));
    else n++;
  }
  return n;
}

function copyTrackedPublicPortalBase(outputDir) {
  const files = execFileSync(
    "git",
    ["ls-tree", "-r", "--name-only", "HEAD", PUBLIC_PORTAL_PREFIX],
    { cwd: REPO_ROOT, encoding: "utf8" }
  ).trim().split("\n").filter(Boolean);
  for (const trackedPath of files) {
    const rel = path.posix.relative(PUBLIC_PORTAL_PREFIX, trackedPath);
    const dst = path.join(outputDir, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    const content = execFileSync("git", ["show", `HEAD:${trackedPath}`], {
      cwd: REPO_ROOT,
      encoding: "buffer",
      maxBuffer: 50 * 1024 * 1024,
    });
    fs.writeFileSync(dst, content);
  }
}

function trackedFile(trackedPath) {
  return execFileSync("git", ["show", `HEAD:${trackedPath}`], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    maxBuffer: 50 * 1024 * 1024,
  });
}

function restoreUnrelatedGeneratedPortalSections(outputDir) {
  const flowFiles = execFileSync(
    "git",
    ["ls-tree", "-r", "--name-only", "HEAD", `${PUBLIC_PORTAL_PREFIX}/flow`],
    { cwd: REPO_ROOT, encoding: "utf8" }
  ).trim().split("\n").filter(Boolean);
  for (const trackedPath of flowFiles) {
    const rel = path.posix.relative(PUBLIC_PORTAL_PREFIX, trackedPath);
    fs.writeFileSync(path.join(outputDir, rel), trackedFile(trackedPath), "utf8");
  }

  const dictionariesPath = `${PUBLIC_PORTAL_PREFIX}/catalog/dictionaries.html`;
  fs.writeFileSync(
    path.join(outputDir, "catalog", "dictionaries.html"),
    trackedFile(dictionariesPath),
    "utf8"
  );

  const generatedIndex = fs.readFileSync(path.join(outputDir, "index.html"), "utf8");
  let scopedIndex = trackedFile(`${PUBLIC_PORTAL_PREFIX}/index.html`);
  for (const key of ["skills", "public-set"]) {
    const pattern = new RegExp(
      `<!-- GEN:COUNT:${key} -->([^<]+)<!-- /GEN:COUNT:${key} -->`
    );
    const generated = generatedIndex.match(pattern);
    if (!generated) throw new Error(`Generated portal count missing: ${key}`);
    scopedIndex = scopedIndex.replace(
      pattern,
      `<!-- GEN:COUNT:${key} -->${generated[1]}<!-- /GEN:COUNT:${key} -->`
    );
  }
  fs.writeFileSync(path.join(outputDir, "index.html"), scopedIndex, "utf8");
}

function applyPublicationApprovals(outputDir) {
  const ledger = fs.readFileSync(
    path.join(SCRIPT_DIR, "public-approval-ledger.md"),
    "utf8"
  );
  const skillLedger = ledger.split("## ルール（agent-home/rules/）")[0];
  const ledgerRows = [...skillLedger.matchAll(
    /^\| ([^|]+?) \| (承認済み|除外（未承認）) \|/gm
  )].map((match) => ({ id: match[1].trim(), status: match[2] }));
  const requiredApprovals = [
    "managing-session-workflow",
    "transcribing-images",
    "orchestrating-dev-flow",
  ];
  for (const name of requiredApprovals) {
    if (!ledger.includes(`| ${name} | 承認済み |`)) {
      throw new Error(`Public approval ledger is missing approval for ${name}`);
    }
  }

  const publicSetPath = path.join(outputDir, "catalog", "public-set.html");
  let publicSet = fs.readFileSync(publicSetPath, "utf8");
  if (!publicSet.includes('id: "managing-session-workflow"')) {
    publicSet = publicSet.replace(
      '      { id: "orchestrating-dev-flow",       type: "skill", verdict: "bundle", reason: "統合開発フローの全体設計は普遍的。初期判定・本監査未実施。",                        cond: "", href: "skills.html" },',
      [
        '      { id: "managing-session-workflow",   type: "skill", verdict: "bundle", reason: "毎ターンの目的・完了条件・制約・引き継ぎを管理する公開承認済みの共通フロー。", cond: "", href: "skills.html" },',
        '      { id: "transcribing-images",         type: "skill", verdict: "bundle", reason: "画像の構造化 findings を専門実装フローへ渡す公開承認済みの境界スキル。", cond: "", href: "skills.html" },',
        '      { id: "orchestrating-dev-flow",      type: "skill", verdict: "bundle", reason: "指摘対応表・回帰・公開証拠までを扱う公開承認済みの統合開発フロー。", cond: "", href: "skills.html" },',
      ].join("\n")
    );
  }
  if (!publicSet.includes('id: "session/workflow-gate"')) {
    publicSet = publicSet.replace(
      '      { id: "session/infra",              type: "rule", verdict: "bundle",   reason: "スキル発火ログ記録とセルフ設定削除はセッション基盤として普遍的。",                                          cond: "", href: "rules.html" },',
      [
        '      { id: "session/infra",              type: "rule", verdict: "bundle",   reason: "スキル発火ログ記録とセルフ設定削除はセッション基盤として普遍的。",                                          cond: "", href: "rules.html" },',
        '      { id: "session/workflow-gate",      type: "rule", verdict: "bundle",   reason: "毎ターンの workflow 本文供給と完了証拠確認を担う公開承認済みゲート。",                                      cond: "", href: "rules.html" },',
      ].join("\n")
    );
  }
  for (const id of [...requiredApprovals, "session/workflow-gate"]) {
    if (!publicSet.includes(`id: "${id}"`)) {
      throw new Error(`Public portal insertion failed: ${id}`);
    }
  }

  const skillsDir = path.join(
    REPO_ROOT,
    "payload",
    "claudecode-global-setup",
    "agent-home",
    "skills"
  );
  for (const { id, status } of ledgerRows) {
    const expectedVerdict = status === "承認済み" ? "bundle" : "exclude";
    const linePattern = new RegExp(
      `^(\\s*\\{ id: "${id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}".*?verdict: ")[^"]+(".*)$`,
      "m"
    );
    if (status === "承認済み" && !linePattern.test(publicSet)) {
      const entry =
        `      { id: "${id}", type: "skill", verdict: "bundle", ` +
        `reason: "公開承認台帳で承認済み。", cond: "", href: "skills.html" },`;
      publicSet = publicSet.replace(
        /(\n\s*\/\/ ── Subagents)/,
        `\n${entry}\n$1`
      );
    }
    if (linePattern.test(publicSet)) {
      publicSet = publicSet.replace(linePattern, `$1${expectedVerdict}$2`);
    }
    if (status === "除外（未承認）") {
      const reasonPattern = new RegExp(
        `^(\\s*\\{ id: "${id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}".*?reason: ")[^"]*(".*)$`,
        "m"
      );
      publicSet = publicSet.replace(
        reasonPattern,
        "$1公開承認台帳で除外（未承認）。$2"
      );
    }
    if (status === "除外（未承認）" && fs.existsSync(path.join(skillsDir, id))) {
      throw new Error(`Excluded ledger skill exists in public payload: ${id}`);
    }
  }
  const publicSkillCount = (publicSet.match(/type: "skill"/g) || []).length;
  const bundledSkillCount = (publicSet.match(
    /type: "skill"[^\n]+verdict: "bundle"/g
  ) || []).length;
  publicSet = publicSet.replace(
    /\/\/ ── Skills（\d+件[^）]*）/,
    `// ── Skills（${publicSkillCount}件・bundle ${bundledSkillCount}件）`
  );
  fs.writeFileSync(publicSetPath, publicSet, "utf8");
}

function removeUnpublishedSkillCategories(outputDir) {
  const skillsDir = path.join(
    REPO_ROOT,
    "payload",
    "claudecode-global-setup",
    "agent-home",
    "skills"
  );
  const publishedSkills = new Set(
    fs.readdirSync(skillsDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
  );
  const categoriesPath = path.join(outputDir, "data", "skill-categories.js");
  let categories = fs.readFileSync(categoriesPath, "utf8")
    .split("\n")
    .filter((line) => {
      const match = line.match(/^  "([^"]+)":/);
      return !match || publishedSkills.has(match[1]);
    })
    .join("\n");
  const additions = [
    '  "managing-session-workflow": "manage",',
    '  "transcribing-images": "content",',
    '  "orchestrating-dev-flow": { cat: "build", sub: "pr" },',
  ];
  for (const addition of additions) {
    const id = addition.match(/"([^"]+)"/)[1];
    if (!categories.includes(`"${id}"`)) {
      categories = categories.replace(/\n};\s*$/, `\n${addition}\n};\n`);
    }
  }
  fs.writeFileSync(categoriesPath, categories, "utf8");
}

function generatePublicPortal(outputDir) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "agent-toolkit-portal-"));
  const publicAgentHome = path.join(
    REPO_ROOT,
    "payload",
    "claudecode-global-setup",
    "agent-home"
  );
  const scratchAgentHome = path.join(scratch, "agent-home");
  const scratchHome = path.join(scratch, "home");
  try {
    fs.mkdirSync(scratchAgentHome, { recursive: true });
    fs.cpSync(path.join(publicAgentHome, "skills"), path.join(scratchAgentHome, "skills"), {
      recursive: true,
    });
    fs.symlinkSync(outputDir, path.join(scratchAgentHome, "ai-management-portal"));
    fs.mkdirSync(path.join(scratchHome, ".claude"), { recursive: true });
    fs.symlinkSync(
      path.join(publicAgentHome, "rules"),
      path.join(scratchHome, ".claude", "rules")
    );
    fs.symlinkSync(
      path.join(publicAgentHome, "agents"),
      path.join(scratchHome, ".claude", "agents")
    );
    execFileSync(
      "node",
      [
        path.join(
          scratchAgentHome,
          "skills",
          "managing-agent-configs",
          "scripts",
          "manage-portal.mjs"
        ),
        "generate",
      ],
      {
        cwd: scratchAgentHome,
        env: { ...process.env, HOME: scratchHome },
        stdio: "inherit",
      }
    );
    restoreUnrelatedGeneratedPortalSections(outputDir);
    fs.rmSync(path.join(outputDir, "data", "build-meta.js"), { force: true });
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

// --- Main ---
const outputDir = process.argv[2] || DEFAULT_DST;

if (fs.existsSync(outputDir)) {
  fs.rmSync(outputDir, { recursive: true });
}

console.log("Building portal payload...");
console.log(`  Source: HEAD:${PUBLIC_PORTAL_PREFIX}`);
console.log(`  Destination: ${outputDir}`);

copyTrackedPublicPortalBase(outputDir);
removeUnpublishedSkillCategories(outputDir);
applyPublicationApprovals(outputDir);
generatePublicPortal(outputDir);

const total = countFiles(outputDir);
console.log(`  Generated: ${total} files`);
