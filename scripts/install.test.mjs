#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const installer = path.join(scriptDir, "install.mjs");
const roots = [];

function tempTarget(label) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `agent-toolkit-${label}-`));
  roots.push(dir);
  return dir;
}

function run(args, options = {}) {
  return spawnSync("node", [installer, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
    ...options,
  });
}

try {
  const codexTemplate = JSON.parse(fs.readFileSync(
    path.join(
      repoRoot,
      "payload",
      "claudecode-global-setup",
      "codex-config",
      "hooks.json"
    ),
    "utf8"
  ));
  const registry = JSON.parse(fs.readFileSync(
    path.join(
      repoRoot,
      "payload",
      "claudecode-global-setup",
      "agent-home",
      "config",
      "codex",
      "hooks-registry.json"
    ),
    "utf8"
  ));
  const templateCommands = Object.values(codexTemplate.hooks)
    .flat()
    .flatMap((entry) => entry.hooks || [])
    .map((hook) => hook.command);
  for (const id of [
    "session-start-reset",
    "workflow-prompt",
    "workflow-pretool",
    "dev-flow-pretool",
    "phase-entry-pretool",
    "phase-step-posttool",
    "workflow-stop",
  ]) {
    assert.ok(registry.commands[id], `missing registry command: ${id}`);
    assert.ok(templateCommands.some((command) => command.endsWith(` ${id}`)));
  }
  assert.ok(!JSON.stringify(registry).includes("/Users/"));
  assert.ok(!JSON.stringify(codexTemplate).includes("/Users/"));

  const claudeTarget = tempTarget("claude");
  const claude = run(["--apply", "--target", claudeTarget]);
  assert.equal(claude.status, 0, claude.stderr);
  assert.ok(fs.existsSync(path.join(claudeTarget, ".claude", "settings.json")));
  assert.ok(!fs.existsSync(path.join(claudeTarget, ".codex", "hooks.json")));

  const allTarget = tempTarget("all");
  const allDiff = run(["--diff", "--target", allTarget, "--runtime", "all"]);
  assert.equal(allDiff.status, 0, allDiff.stderr);
  assert.match(allDiff.stdout, /\.claude\/settings\.json/);
  assert.match(allDiff.stdout, /\.codex\/hooks\.json/);

  const codexTarget = tempTarget("codex");
  fs.mkdirSync(path.join(codexTarget, ".codex"), { recursive: true });
  fs.writeFileSync(
    path.join(codexTarget, ".codex", "hooks.json"),
    JSON.stringify({
      customSetting: true,
      hooks: {
        PreToolUse: [{
          matcher: "custom",
          hooks: [{ type: "command", command: "printf custom" }],
        }],
      },
    }, null, 2)
  );

  for (const action of ["--doctor", "--diff"]) {
    const result = run([action, "--target", codexTarget, "--runtime", "codex"]);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /codex/);
  }
  const codex = run(["--apply", "--target", codexTarget, "--runtime", "codex"]);
  assert.equal(codex.status, 0, codex.stderr);
  assert.match(`${codex.stdout}\n${codex.stderr}`, /FAIL 0 .* PASS 9/s);
  assert.ok(!fs.existsSync(path.join(codexTarget, ".claude", "settings.json")));
  const installedHooksPath = path.join(codexTarget, ".codex", "hooks.json");
  const installedHooks = JSON.parse(fs.readFileSync(installedHooksPath, "utf8"));
  assert.equal(installedHooks.customSetting, true);
  assert.ok(JSON.stringify(installedHooks).includes("workflow-prompt"));
  assert.ok(fs.readdirSync(path.dirname(installedHooksPath)).some((name) =>
    name.startsWith("hooks.json.bak.")
  ));

  const before = JSON.stringify(installedHooks);
  const second = run(["--apply", "--target", codexTarget, "--runtime", "codex"]);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(
    JSON.stringify(JSON.parse(fs.readFileSync(installedHooksPath, "utf8"))),
    before
  );

  const adapterTest = spawnSync(
    "bash",
    [path.join(codexTarget, "agent-home", "config", "codex", "hook-command-adapter.test.sh")],
    { cwd: codexTarget, encoding: "utf8", maxBuffer: 10 * 1024 * 1024 }
  );
  assert.equal(adapterTest.status, 0, adapterTest.stderr);

  const adapter = path.join(
    codexTarget,
    "agent-home",
    "config",
    "codex",
    "hook-command-adapter.sh"
  );
  const prompt = spawnSync(
    adapter,
    ["UserPromptSubmit", "workflow-prompt"],
    {
      cwd: codexTarget,
      input: JSON.stringify({
        session_id: "public-install-test",
        cwd: codexTarget,
        prompt: "途中の訂正を反映してください",
      }),
      encoding: "utf8",
      env: {
        ...process.env,
        HOME: codexTarget,
        AGENT_HOME_ROOT: path.join(codexTarget, "agent-home"),
        TMPDIR: codexTarget,
      },
    }
  );
  assert.equal(prompt.status, 0, prompt.stderr);
  assert.match(prompt.stdout, /managing-session-workflow/);

  const invalidTarget = tempTarget("invalid");
  fs.mkdirSync(path.join(invalidTarget, ".codex"), { recursive: true });
  const invalidPath = path.join(invalidTarget, ".codex", "hooks.json");
  fs.writeFileSync(invalidPath, "{invalid");
  const invalid = run(["--apply", "--target", invalidTarget, "--runtime", "codex"]);
  assert.notEqual(invalid.status, 0);
  assert.equal(fs.readFileSync(invalidPath, "utf8"), "{invalid");
  assert.ok(!fs.existsSync(path.join(invalidTarget, "agent-home")));

  console.log("PASS install runtime integration");
} finally {
  for (const root of roots) {
    fs.rmSync(root, { recursive: true, force: true });
  }
}
