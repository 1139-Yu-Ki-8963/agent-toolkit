#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const skillsRoot = path.join(repoRoot, ".claude", "skills");
const failures = [];
const warnings = [];
const strictWarnings = process.argv.includes("--strict-warnings");
const toolNames = [
  "Agent",
  "AskUserQuestion",
  "Bash",
  "Edit",
  "Glob",
  "Grep",
  "Read",
  "SendUserFile",
  "Skill",
  "TaskCreate",
  "TaskUpdate",
  "Write",
];

const skillFiles = fs
  .readdirSync(skillsRoot)
  .map((name) => path.join(skillsRoot, name, "SKILL.md"))
  .filter((file) => fs.existsSync(file))
  .sort();

function fail(file, line, message, code = "E_STRUCTURE") {
  failures.push(`[${code}] ${path.relative(repoRoot, file)}:${line}: ${message}`);
}

function warn(file, line, message, code) {
  warnings.push(`[${code}] ${path.relative(repoRoot, file)}:${line}: ${message}`);
}

for (const file of skillFiles) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  const allowedToolsLine = lines.find((line) => line.startsWith("allowed-tools:"));
  const allowedTools = new Set(
    allowedToolsLine
      ?.match(/\[([^\]]*)\]/)?.[1]
      .split(",")
      .map((tool) => tool.trim())
      .filter(Boolean) ?? [],
  );
  const phases = [];
  let currentPhase = null;
  let currentStep = null;
  let stepHasCompletion = false;
  let stepMentionedTools = new Set();
  let stepDeclaredTools = new Set();
  let stepHasToolDeclaration = false;
  const usedTools = new Set();
  let expectedStep = 1;
  let phaseHasStep = false;

  const closeStep = () => {
    if (currentStep === null) {
      return;
    }
    if (!stepHasCompletion) {
      fail(
        file,
        currentStep.line,
        `Step ${currentStep.id} に **完了**: 行がない`,
        "E_STEP_COMPLETION",
      );
    }
    if (stepMentionedTools.size === 0) {
      warn(
        file,
        currentStep.line,
        `Step ${currentStep.id} に使用ツールの明示がない`,
        "W_STEP_TOOL",
      );
    }
    const effectiveTools = stepHasToolDeclaration
      ? stepDeclaredTools
      : stepMentionedTools;
    for (const tool of effectiveTools) {
      usedTools.add(tool);
      if (!allowedTools.has(tool)) {
        warn(
          file,
          currentStep.line,
          `Step ${currentStep.id} の使用ツール ${tool} がallowed-toolsにない`,
          "W_ALLOWED_TOOLS",
        );
      }
    }
  };
  const closePhase = () => {
    closeStep();
    if (currentPhase !== null && !phaseHasStep) {
      fail(file, currentPhase.line, `Phase ${currentPhase.number} にStepがない`);
    }
  };

  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    const phase = line.match(/^## Phase ([1-9]\d*):\s+\S/);
    const step = line.match(/^## Step ([1-9]\d*)-([1-9]\d*):\s+\S/);

    if (/^#{2,4}\s+Phase\b/.test(line) && !phase) {
      fail(file, lineNumber, `不正なPhase見出し: ${line}`);
      return;
    }
    if (/^#{2,4}\s+P[1-9]\d*:/.test(line)) {
      fail(file, lineNumber, `旧P見出しは禁止: ${line}`);
      return;
    }
    if (/^#{2,4}\s+Step\b/.test(line) && !step) {
      fail(file, lineNumber, `不正なStep見出し: ${line}`);
      return;
    }
    if (phase) {
      closePhase();
      const number = Number(phase[1]);
      const expectedPhase = phases.length + 1;
      if (number !== expectedPhase) {
        fail(file, lineNumber, `Phase ${number} は連番ではない（期待: ${expectedPhase}）`);
      }
      phases.push(number);
      currentPhase = { number, line: lineNumber };
      currentStep = null;
      expectedStep = 1;
      phaseHasStep = false;
      return;
    }
    if (step) {
      closeStep();
      if (currentPhase === null) {
        fail(file, lineNumber, "親PhaseがないStep");
        return;
      }
      const parent = Number(step[1]);
      const sequence = Number(step[2]);
      if (parent !== currentPhase.number) {
        fail(file, lineNumber, `Step親 ${parent} がPhase ${currentPhase.number} と不一致`);
      }
      if (sequence !== expectedStep) {
        fail(file, lineNumber, `Step ${parent}-${sequence} は連番ではない（期待: ${parent}-${expectedStep}）`);
      }
      expectedStep += 1;
      phaseHasStep = true;
      currentStep = { id: `${parent}-${sequence}`, line: lineNumber };
      stepHasCompletion = false;
      stepMentionedTools = new Set();
      stepDeclaredTools = new Set();
      stepHasToolDeclaration = false;
      return;
    }
    if (currentStep !== null && /^\*\*完了\*\*:/.test(line)) {
      stepHasCompletion = true;
    }
    if (currentStep !== null) {
      for (const tool of toolNames) {
        if (new RegExp(`\\b${tool}\\b`).test(line)) {
          stepMentionedTools.add(tool);
          if (/^(?:\*\*使用ツール\*\*:|- tool:)/.test(line)) {
            stepDeclaredTools.add(tool);
            stepHasToolDeclaration = true;
          }
        }
      }
    }
  });
  closePhase();
  for (const tool of allowedTools) {
    if (!usedTools.has(tool)) {
      warn(
        file,
        1,
        `allowed-toolsの ${tool} がどのStepにも明記されていない`,
        "W_ALLOWED_TOOLS",
      );
    }
  }
  if (phases.length === 0) {
    fail(file, 1, "Phase/Step構造がない");
  }
}

const referenceFiles = fs
  .readdirSync(skillsRoot, { recursive: true, withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
  .map((entry) => path.join(entry.parentPath, entry.name))
  .filter((file) => file.includes(`${path.sep}references${path.sep}`))
  .sort();

for (const file of referenceFiles) {
  fs.readFileSync(file, "utf8")
    .split("\n")
    .forEach((line, index) => {
      if (/\bP[1-9]\d*\b/.test(line)) {
        fail(file, index + 1, `旧P記法は禁止: ${line}`);
      }
      if (/^#{2,4}\s+(?:Phase [1-9]\d*|Step [1-9]\d*)\b/.test(line)) {
        fail(
          file,
          index + 1,
          `補足資料でPhase/Step定義見出しを再定義している: ${line}`,
        );
      }
    });
}

const orchestrator = path.join(
  skillsRoot,
  "orchestrating-reverse-docs-flow",
  "SKILL.md",
);
const orchestratorText = fs.readFileSync(orchestrator, "utf8");
const orchestratorPhases = [
  ...orchestratorText.matchAll(/^## Phase ([1-9]\d*):/gm),
].map((match) => Number(match[1]));
const globalSteps = [
  ...orchestratorText.matchAll(/^- global_step: ([1-9]\d*)$/gm),
].map((match) => Number(match[1]));

if (orchestratorPhases.join(",") !== "1,2,3,4,5,6,7") {
  fail(orchestrator, 1, `統括Phaseが1〜7ではない: ${orchestratorPhases.join(",")}`);
}
if (globalSteps.join(",") !== Array.from({ length: 30 }, (_, index) => index + 1).join(",")) {
  fail(orchestrator, 1, `global Stepが1〜30の一意順序ではない: ${globalSteps.join(",")}`);
}
for (const required of [
  "## 条件分岐メタデータ",
  "## Back-edgeメタデータ",
  "back_edge_id",
  "from_global_step",
  "to_global_step",
]) {
  if (!orchestratorText.includes(required)) {
    fail(orchestrator, 1, `必須メタデータがない: ${required}`);
  }
}

const canonical = path.join(repoRoot, "shared", "references", "リバース工程設計.md");
const canonicalText = fs.readFileSync(canonical, "utf8");
const canonicalRows = [
  ...canonicalText.matchAll(/^\| Phase ([1-7]) [^|]+ \| Step ([1-9]\d*) \|/gm),
].map((match) => [Number(match[1]), Number(match[2])]);
const canonicalSteps = canonicalRows.map((row) => row[1]);
if (canonicalSteps.join(",") !== Array.from({ length: 30 }, (_, index) => index + 1).join(",")) {
  fail(canonical, 1, `正本Stepが1〜30の一意順序ではない: ${canonicalSteps.join(",")}`);
}
const expectedPhaseByStep = [
  ...Array(2).fill(1),
  ...Array(6).fill(2),
  ...Array(3).fill(3),
  ...Array(5).fill(4),
  ...Array(12).fill(5),
  6,
  7,
];
canonicalRows.forEach(([phase, step], index) => {
  if (phase !== expectedPhaseByStep[index]) {
    fail(canonical, 1, `Step ${step} の親Phaseが${phase}（期待: ${expectedPhaseByStep[index]}）`);
  }
});
for (const required of [
  "## 条件分岐メタデータ",
  "## Back-edgeメタデータ",
  "conditional_step_id",
  "back_edge_id",
  "from_step",
  "to_step",
]) {
  if (!canonicalText.includes(required)) {
    fail(canonical, 1, `正本の必須メタデータがない: ${required}`);
  }
}

function validateBackEdges(file, text) {
  const section = text.match(/## Back-edgeメタデータ\n([\s\S]*?)(?=\n## |\s*$)/);
  if (!section) {
    fail(file, 1, "Back-edgeメタデータ節がない", "E_BACK_EDGE");
    return [];
  }
  const rows = section[1]
    .split("\n")
    .filter((line) => /^\|[^-]/.test(line))
    .map((line) => line.split("|").slice(1, -1).map((cell) => cell.trim()))
    .filter((cells) => cells[0] && cells[0] !== "back_edge_id");
  if (rows.length !== 5) {
    fail(file, 1, `Back-edgeが5件ではない: ${rows.length}`, "E_BACK_EDGE");
  }
  const ids = new Set();
  for (const cells of rows) {
    const [id, from, to, condition, limit, stop] = cells;
    if (
      !id ||
      !/^\d+$/.test(from) ||
      !/^\d+$/.test(to) ||
      !condition ||
      !/^\d+$/.test(limit) ||
      !stop
    ) {
      fail(
        file,
        1,
        `Back-edgeのID/from/to/条件/上限/停止条件が不完全: ${cells.join(" | ")}`,
        "E_BACK_EDGE",
      );
    }
    if (ids.has(id)) {
      fail(file, 1, `Back-edge IDが重複: ${id}`, "E_BACK_EDGE");
    }
    ids.add(id);
    if (/^\d+$/.test(from) && /^\d+$/.test(to) && Number(from) <= Number(to)) {
      fail(file, 1, `Back-edgeは前方へ戻っていない: ${from} -> ${to}`, "E_BACK_EDGE");
    }
    if (/^\d+$/.test(limit) && Number(limit) <= 0) {
      fail(file, 1, `Back-edge上限は1以上が必要: ${id}=${limit}`, "E_BACK_EDGE");
    }
  }
  return rows;
}

const orchestratorBackEdges = validateBackEdges(orchestrator, orchestratorText);
const canonicalBackEdges = validateBackEdges(canonical, canonicalText);
if (JSON.stringify(orchestratorBackEdges) !== JSON.stringify(canonicalBackEdges)) {
  fail(
    orchestrator,
    1,
    "統括と正本のBack-edge表が完全一致していない",
    "E_BACK_EDGE",
  );
}

if (failures.length > 0) {
  console.error(`FAIL phase-step structure (${failures.length})`);
  failures.forEach((message) => console.error(`- ${message}`));
  process.exit(1);
}

if (warnings.length > 0) {
  console.error(`WARN phase-step structure (${warnings.length})`);
  warnings.forEach((message) => console.error(`- ${message}`));
  if (strictWarnings) {
    process.exit(1);
  }
}

console.log(
  `PASS phase-step structure: skills=${skillFiles.length}, references=${referenceFiles.length}, orchestrator_phases=7, global_steps=30, warnings=${warnings.length}`,
);
