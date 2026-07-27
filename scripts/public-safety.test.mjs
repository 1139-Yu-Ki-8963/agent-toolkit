#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const payloadRoot = path.join(repoRoot, "payload");
const privateCatalogName = ["link", "keeper"].join("-");
const designNote = fs.readFileSync(
  path.join(
    payloadRoot,
    "claudecode-global-setup",
    "agent-home",
    "rules",
    "scoped",
    "review-checklist",
    "code",
    "catalog-site",
    "design-notes.txt"
  ),
  "utf8"
);
assert.ok(!designNote.includes(privateCatalogName));

for (const rel of [
  "claudecode-global-setup/codex-config/hooks.json",
  "claudecode-global-setup/agent-home/config/codex/hooks-registry.json",
]) {
  const content = fs.readFileSync(path.join(payloadRoot, rel), "utf8");
  assert.ok(!content.includes("/Users/"), `${rel} contains a machine-specific path`);
}

const forbiddenIssueArtifact = path.join(
  payloadRoot,
  "claudecode-global-setup",
  "agent-home",
  "skills",
  "orchestrating-dev-flow",
  "references",
  "creating-screen-mock-examples-issue-1588-mockup.html"
);
assert.ok(!fs.existsSync(forbiddenIssueArtifact));

const publicSkillsRoot = path.join(
  payloadRoot,
  "claudecode-global-setup",
  "agent-home",
  "skills"
);
const actualSkills = fs.readdirSync(publicSkillsRoot, { withFileTypes: true })
  .filter((entry) =>
    entry.isDirectory() &&
    fs.existsSync(path.join(publicSkillsRoot, entry.name, "SKILL.md"))
  )
  .map((entry) => entry.name)
  .sort();
const readme = fs.readFileSync(path.join(repoRoot, "README.md"), "utf8");
const readmeSkills = [...readme.matchAll(
  /\[`([^`]+)`\]\((payload\/claudecode-global-setup\/agent-home\/skills\/([^/]+)\/SKILL\.md)\)/g
)];
for (const [, , rel] of readmeSkills) {
  assert.ok(fs.existsSync(path.join(repoRoot, rel)), `README link is missing: ${rel}`);
}
assert.deepEqual(
  [...new Set(readmeSkills.map((match) => match[3]))].sort(),
  actualSkills,
  "README bundled-skill table must match the public payload"
);

const ledger = fs.readFileSync(
  path.join(repoRoot, "scripts", "public-approval-ledger.md"),
  "utf8"
).split("## ルール（agent-home/rules/）")[0];
const ledgerSkills = [...ledger.matchAll(
  /^\| ([^|]+?) \| (承認済み|除外（未承認）) \|/gm
)].map((match) => ({ id: match[1].trim(), status: match[2] }));
const approvedSkills = ledgerSkills
  .filter(({ status }) => status === "承認済み")
  .map(({ id }) => id)
  .sort();
assert.deepEqual(approvedSkills, actualSkills);

const publicSet = fs.readFileSync(
  path.join(
    payloadRoot,
    "claudecode-global-setup",
    "agent-home",
    "ai-management-portal",
    "catalog",
    "public-set.html"
  ),
  "utf8"
);
for (const { id, status } of ledgerSkills) {
  const line = publicSet.split("\n").find((item) => item.includes(`id: "${id}"`));
  if (status === "除外（未承認）") {
    assert.ok(!actualSkills.includes(id), `excluded ledger skill is bundled: ${id}`);
    if (line) assert.match(line, /verdict: "exclude"/);
  } else {
    assert.ok(line, `approved ledger skill is missing from public-set: ${id}`);
    assert.match(line, /verdict: "bundle"/);
  }
}

console.log("PASS public safety regression");
