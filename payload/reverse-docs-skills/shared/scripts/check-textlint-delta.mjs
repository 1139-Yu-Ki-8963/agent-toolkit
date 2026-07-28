#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const baseline = "97f9812";
const agentHome = process.env.REVERSE_DOCS_AGENT_HOME ?? join(homedir(), "agent-home");
const textlint = join(agentHome, "tools/linter/node_modules/.bin/textlint");
const config = join(agentHome, "tools/linter/.textlintrc.json");
const textlintIdentity = "agent-home/tools/linter/node_modules/.bin/textlint";
const configIdentity = "agent-home/tools/linter/.textlintrc.json";
const excluded = new Set(
  existsSync(".investigation-checklist.md") ? [".investigation-checklist.md"] : [],
);
const discoveryPolicy = {
  version: 2,
  tracked: "git diff --name-only --diff-filter=AM -z <baseline> -- *.md",
  untracked: "git ls-files --others --exclude-standard -z -- *.md",
  merge: "UTF-8 NUL records; set union; en locale sort",
};
const exclusionReasons = {
  ".investigation-checklist.md": "local workflow-only; not a repository deliverable",
};

function gitPaths(args) {
  const run = spawnSync("git", args, { encoding: null });
  if (run.status !== 0) throw new Error(`git ${args.join(" ")} failed`);
  return run.stdout.toString("utf8").split("\0").filter(Boolean);
}

function discover() {
  const tracked = gitPaths([
    "diff", "--name-only", "--diff-filter=AM", "-z", baseline, "--", "*.md",
  ]);
  const untracked = gitPaths([
    "ls-files", "--others", "--exclude-standard", "-z", "--", "*.md",
  ]);
  const untrackedSet = new Set(untracked);
  const files = [...new Set([...tracked, ...untracked])]
    .filter((file) => !excluded.has(file))
    .sort((a, b) => a.localeCompare(b, "en"));
  return { files, untrackedSet };
}

function addedLines(file, isNew) {
  if (isNew) return null;
  const run = spawnSync(
    "git", ["diff", "-U0", baseline, "--", file], { encoding: "utf8" },
  );
  if (run.status !== 0) throw new Error(`git diff failed for ${file}`);
  const lines = new Set();
  for (const line of run.stdout.split("\n")) {
    const match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/);
    if (!match) continue;
    const start = Number(match[1]);
    const count = Number(match[2] ?? 1);
    for (let value = start; value < start + count; value += 1) lines.add(value);
  }
  return lines;
}

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function requireRuntimeFile(file, label) {
  if (!existsSync(file)) {
    throw new Error(`${label} is missing: ${file}`);
  }
}

function fullBaseline() {
  const run = spawnSync("git", ["rev-parse", `${baseline}^{commit}`], { encoding: "utf8" });
  if (run.status !== 0) throw new Error("baseline commit cannot be resolved");
  return run.stdout.trim();
}

function executionContext() {
  return {
    baseline: { requested: baseline, commit: fullBaseline() },
    textlint: { path: textlintIdentity },
    config: { path: configIdentity, sha256: sha256(config) },
    discovery_policy: discoveryPolicy,
    explicit_exclusions: [...excluded].sort().map((path) => ({
      path,
      reason: exclusionReasons[path],
      content_sha256: existsSync(path) ? sha256(path) : null,
    })),
  };
}

function evaluate() {
  requireRuntimeFile(textlint, "textlint executable");
  requireRuntimeFile(config, "textlint config");
  const { files, untrackedSet } = discover();
  const rawExitCodes = {};
  const contentSha256 = {};
  const filteredCountByFile = {};
  const violations = [];
  for (const file of files) {
    contentSha256[file] = sha256(file);
    const run = spawnSync(
      textlint, ["--config", config, "--format", "json", "--", file],
      { encoding: "utf8" },
    );
    rawExitCodes[file] = run.status;
    let reports = [];
    try {
      reports = JSON.parse(run.stdout || "[]");
    } catch {
      throw new Error(`invalid textlint JSON: ${file}`);
    }
    const added = addedLines(file, untrackedSet.has(file));
    const before = violations.length;
    for (const report of reports) {
      for (const message of report.messages ?? []) {
        if (added === null || added.has(message.line)) {
          violations.push({
            file, line: message.line, ruleId: message.ruleId, message: message.message,
          });
        }
      }
    }
    filteredCountByFile[file] = violations.length - before;
  }
  return {
    execution_context: executionContext(),
    target_files: files,
    file_count: files.length,
    content_sha256: contentSha256,
    raw_exit_codes: rawExitCodes,
    filtered_count_by_file: filteredCountByFile,
    filtered_violation_count: violations.length,
    violations,
    status: violations.length === 0 ? "PASS" : "FAIL",
  };
}

function sealedEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

const args = process.argv.slice(2);
if (args[0] === "--self-test") {
  const candidate = ".textlint-dynamic-self-test.md";
  if (existsSync(candidate)) throw new Error(`${candidate} already exists`);
  try {
    writeFileSync(candidate, "# dynamic discovery self-test\n");
    const { files } = discover();
    if (!files.includes(candidate)) throw new Error("new Markdown was not dynamically discovered");
  } finally {
    if (existsSync(candidate)) unlinkSync(candidate);
  }
  const sample = {
    execution_context: {
      baseline: { requested: baseline, commit: "a".repeat(40) },
      textlint: { path: textlintIdentity },
      config: { path: configIdentity, sha256: "b".repeat(64) },
      discovery_policy: discoveryPolicy,
      explicit_exclusions: [{
        path: ".investigation-checklist.md",
        reason: exclusionReasons[".investigation-checklist.md"],
        content_sha256: "c".repeat(64),
      }],
    },
  };
  for (const mutate of [
    (value) => { value.execution_context.baseline.commit = "d".repeat(40); },
    (value) => { value.execution_context.textlint.path = "other/textlint"; },
    (value) => { value.execution_context.config.path = "other/config"; },
    (value) => { value.execution_context.config.sha256 = "d".repeat(64); },
    (value) => { value.execution_context.discovery_policy.version += 1; },
    (value) => { value.execution_context.explicit_exclusions[0].path = "other.md"; },
    (value) => { value.execution_context.explicit_exclusions[0].reason = "changed"; },
    (value) => { value.execution_context.explicit_exclusions[0].content_sha256 = "d".repeat(64); },
  ]) {
    const candidate = structuredClone(sample);
    mutate(candidate);
    if (sealedEqual(sample, candidate)) throw new Error("execution-context tamper was not rejected");
  }
  process.stdout.write("PASS: dynamically discovered a newly added Markdown file\n");
  process.stdout.write("PASS: baseline/config/discovery/exclusion tampering rejected\n");
  process.exit(0);
}

const evidence = evaluate();
if (args[0] === "--write-evidence") {
  if (!args[1]) throw new Error("--write-evidence requires a path");
  writeFileSync(args[1], JSON.stringify(evidence, null, 2) + "\n");
}
if (args[0] === "--verify-evidence") {
  if (!args[1]) throw new Error("--verify-evidence requires a path");
  const recorded = JSON.parse(readFileSync(args[1], "utf8"));
  if (!sealedEqual(recorded, evidence)) {
    throw new Error("textlint evidence set/hash/result mismatch");
  }
}
process.stdout.write(JSON.stringify(evidence, null, 2) + "\n");
process.exit(evidence.filtered_violation_count === 0 ? 0 : 1);
