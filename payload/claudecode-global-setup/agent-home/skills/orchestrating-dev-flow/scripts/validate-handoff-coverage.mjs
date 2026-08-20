#!/usr/bin/env node

import fs from "node:fs";

const modes = ["schema", "implementation", "coverage-completion", "publication"];
const [mode = "implementation", inputPath] = process.argv.slice(2);
if (!inputPath || !modes.includes(mode)) {
  console.error(`usage: validate-handoff-coverage.mjs <${modes.join("|")}> <input.json>`);
  process.exit(2);
}

let document;
try {
  document = JSON.parse(fs.readFileSync(inputPath, "utf8"));
} catch (error) {
  console.error(`invalid input: ${error.message}`);
  process.exit(2);
}

const errors = [];
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const nonEmpty = (value) => typeof value === "string" && value.trim() !== "";
const handoff = document.handoff;

if (!isObject(handoff)) {
  errors.push("handoff must be an object");
} else {
  const requiredKeys = [
    "goal",
    "purpose",
    "completionCriteria",
    "constraints",
    "userCorrections",
    "inputs",
    "publication",
  ];
  for (const key of requiredKeys) {
    if (!Object.hasOwn(handoff, key)) errors.push(`handoff.${key} missing`);
  }
  if (!(handoff.goal === null || nonEmpty(handoff.goal))) {
    errors.push("handoff.goal must be null or a non-empty string");
  }
  if (!nonEmpty(handoff.purpose)) errors.push("handoff.purpose must be a non-empty string");
  for (const key of ["completionCriteria", "constraints", "userCorrections", "inputs"]) {
    if (!Array.isArray(handoff[key])) errors.push(`handoff.${key} must be an array`);
  }
  if (!isObject(handoff.publication)) {
    errors.push("handoff.publication must be an object");
  } else if (typeof handoff.publication.required !== "boolean") {
    errors.push("handoff.publication.required must be boolean");
  }
}

const requiredIds = new Set();
if (isObject(handoff)) {
  for (const correction of handoff.userCorrections ?? []) {
    const sourceId = correction?.sourceId ?? correction?.id;
    if (!nonEmpty(sourceId)) errors.push("userCorrection sourceId/id missing");
    else requiredIds.add(sourceId);
    for (const key of ["original", "normalized", "target"]) {
      if (!nonEmpty(correction?.[key])) errors.push(`userCorrection ${key} missing`);
    }
  }
  for (const input of handoff.inputs ?? []) {
    if (input?.type === "priorFailure") {
      const sourceId = input.sourceId ?? input.id;
      if (!nonEmpty(sourceId)) errors.push("priorFailure sourceId/id missing");
      else requiredIds.add(sourceId);
    }
    if (input?.actionable === true) {
      for (const key of ["expectedChange", "verification"]) {
        if (!Object.hasOwn(input, key)) {
          errors.push(`actionable input ${key} missing`);
        } else if (!Array.isArray(input[key])) {
          errors.push(`actionable input ${key} must be an array`);
        }
      }
      const confirmation = input.scopeConfirmation;
      if (!isObject(confirmation)) {
        errors.push("actionable input scopeConfirmation missing");
      } else {
        const implementationDecision = confirmation.investigationAndImplementation;
        if (!["proceed", "transcription-only"].includes(implementationDecision)) {
          errors.push("actionable input investigationAndImplementation invalid");
        }
        if (
          implementationDecision === "proceed" &&
          !["publication", "local"].includes(confirmation.goalScope)
        ) {
          errors.push("actionable input goalScope invalid");
        }
        if (
          mode !== "schema" &&
          implementationDecision === "transcription-only"
        ) {
          errors.push("actionable input does not authorize implementation");
        }
      }
      if (!Array.isArray(input.findings)) {
        errors.push("actionable input findings must be an array");
        continue;
      }
      for (const finding of input.findings) {
        for (const key of ["id", "source", "observation"]) {
          if (!nonEmpty(finding?.[key])) errors.push(`actionable finding ${key} missing`);
        }
        if (nonEmpty(finding?.id)) requiredIds.add(finding.id);
      }
    }
  }
}

const publication = isObject(handoff?.publication) ? handoff.publication : {};
if (publication.required === true) {
  for (const key of ["target", "verification"]) {
    if (!nonEmpty(publication[key])) errors.push(`publication.${key} missing`);
  }
}

if (mode !== "schema") {
  const coverage = Array.isArray(document.coverage) ? document.coverage : [];
  if (!Array.isArray(document.coverage)) errors.push("coverage must be an array");
  for (const sourceId of requiredIds) {
    const row = coverage.find((candidate) => candidate?.sourceId === sourceId);
    if (!row) {
      errors.push(`${sourceId}: coverage row missing`);
      continue;
    }
    for (const key of ["source", "target", "implementation", "verification", "status"]) {
      if (!nonEmpty(row[key])) errors.push(`${sourceId}: ${key} missing`);
    }
    if (["coverage-completion", "publication"].includes(mode) && row.status !== "verified") {
      errors.push(`${sourceId}: status must be verified`);
    }
  }
}

if (mode === "publication" && publication.required === true) {
  const evidence = document.publicationEvidence;
  if (!isObject(evidence)) {
    errors.push("publicationEvidence must be an object");
  } else {
    const { commit, push, sync, remoteFetch } = evidence;
    if (!isObject(commit) || !nonEmpty(commit.sha) || !nonEmpty(commit.repository)) {
      errors.push("publicationEvidence.commit requires sha and repository");
    } else if (nonEmpty(publication.target) && commit.repository !== publication.target) {
      errors.push("publicationEvidence.commit.repository must match publication.target");
    }
    if (!isObject(push) || !nonEmpty(push.sha) || !nonEmpty(push.remote) || !nonEmpty(push.ref)) {
      errors.push("publicationEvidence.push requires sha, remote, and ref");
    }
    if (!isObject(sync) || !nonEmpty(sync.command) || sync.exitCode !== 0) {
      errors.push("publicationEvidence.sync requires command and exitCode 0");
    }
    if (
      !isObject(remoteFetch) ||
      !nonEmpty(remoteFetch.remote) ||
      !nonEmpty(remoteFetch.ref) ||
      !nonEmpty(remoteFetch.sha) ||
      remoteFetch.contentVerified !== true
    ) {
      errors.push("publicationEvidence.remoteFetch requires remote, ref, sha, and contentVerified true");
    }
    const shas = [commit?.sha, push?.sha, remoteFetch?.sha];
    if (shas.every(nonEmpty) && new Set(shas).size !== 1) {
      errors.push("publication evidence SHA mismatch");
    }
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`PASS ${mode}: ${requiredIds.size} source(s) covered`);
