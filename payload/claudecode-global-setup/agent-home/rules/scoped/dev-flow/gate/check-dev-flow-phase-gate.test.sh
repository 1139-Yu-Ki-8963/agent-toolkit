#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../../../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

project="$test_tmp/Projects/sample"
mkdir -p "$project/src"
git -C "$project" init -q
validator="$repo_root/skills/orchestrating-dev-flow/scripts/validate-handoff-coverage.mjs"

input=$(jq -nc --arg cwd "$project" --arg path "$project/src/app.js" \
  '{cwd:$cwd,tool_input:{file_path:$path}}')

write_progress() {
  jq -nc --arg phase "$1" --arg route "$2" --argjson completed "$3" \
    '{current_phase:$phase,route:$route,phases_completed:$completed}' \
    >"$project/.flow-progress.json"
}

write_valid_handoff() {
  mkdir -p "$project/.claude/dev-flow"
  cat >"$project/.claude/dev-flow/handoff-and-coverage.json" <<'JSON'
{
  "handoff": {
    "goal": null,
    "purpose": "test",
    "completionCriteria": ["verified"],
    "constraints": [],
    "userCorrections": [{"sourceId":"correction-1","original":"old","normalized":"new","target":"src/app.js"}],
    "inputs": [],
    "publication": {"required": false}
  },
  "coverage": [{
    "sourceId":"correction-1",
    "source":"userCorrection",
    "target":"src/app.js",
    "implementation":"apply correction",
    "verification":"regression test",
    "status":"planned"
  }]
}
JSON
}

expect_block() {
  local payload="$1"
  if printf '%s' "$payload" | HOME="$test_tmp" DEV_FLOW_HANDOFF_VALIDATOR="$validator" \
    "$here/check-dev-flow-phase-gate.sh" >/dev/null 2>&1; then
    echo "write unexpectedly passed: $(cat "$project/.flow-progress.json")" >&2
    exit 1
  fi
}

expect_pass() {
  local payload="$1"
  printf '%s' "$payload" | HOME="$test_tmp" DEV_FLOW_HANDOFF_VALIDATOR="$validator" \
    "$here/check-dev-flow-phase-gate.sh" >/dev/null
}

# Every implementation route must fail closed without the canonical artifact.
for route_case in \
  '6|feature-with-full-planning|[1,2,3,4,5]' \
  '6|feature-with-quick-delivery|[1,2,5]' \
  '7|refactor-with-safety-guarantee|[1,2,5]' \
  'D|config-with-review-and-verify|[1,2]' \
  'I|incident-with-emergency-path|[1,2]'; do
  IFS='|' read -r phase route completed <<<"$route_case"
  write_progress "$phase" "$route" "$completed"
  expect_block "$input"
done

# Config docs writes are also implementation writes; the old blanket bypass is forbidden.
config_input=$(jq -nc --arg cwd "$project" --arg path "$project/docs/guide.md" \
  '{cwd:$cwd,tool_input:{file_path:$path}}')
write_progress D config-with-review-and-verify '[1,2]'
expect_block "$config_input"

write_valid_handoff
for route_case in \
  '6|feature-with-full-planning|[1,2,3,4,5]' \
  '6|feature-with-quick-delivery|[1,2,5]' \
  '7|refactor-with-safety-guarantee|[1,2,5]' \
  'D|config-with-review-and-verify|[1,2]' \
  'I|incident-with-emergency-path|[1,2]'; do
  IFS='|' read -r phase route completed <<<"$route_case"
  write_progress "$phase" "$route" "$completed"
  expect_pass "$input"
done
write_progress D config-with-review-and-verify '[1,2]'
expect_pass "$config_input"

mkdir -p "$project/.claude/rules/always/project-context"
printf '%s\n' 'classify: [unterminated' \
  >"$project/.claude/rules/always/project-context/flow-values.yml"
if printf '%s' "$input" | HOME="$test_tmp" DEV_FLOW_YAML_VALIDATOR=ruby \
  "$here/check-dev-flow-phase-gate.sh" >/dev/null 2>&1; then
  echo "invalid existing flow-values.yml unexpectedly passed" >&2
  exit 1
fi

printf '%s\n' 'classify: {quick_max_files: 2}' \
  >"$project/.claude/rules/always/project-context/flow-values.yml"
printf '%s' "$input" | HOME="$test_tmp" DEV_FLOW_YAML_VALIDATOR=unavailable \
  DEV_FLOW_HANDOFF_VALIDATOR="$validator" "$here/check-dev-flow-phase-gate.sh" |
  jq -e '.hookSpecificOutput.additionalContext | contains("YAML parser")' >/dev/null

# A WARN followed by a later block must still emit exactly one JSON document.
write_progress 5 feature-with-quick-delivery '[1,2]'
set +e
warn_block_output=$(printf '%s' "$input" | HOME="$test_tmp" DEV_FLOW_YAML_VALIDATOR=unavailable \
  DEV_FLOW_HANDOFF_VALIDATOR="$validator" "$here/check-dev-flow-phase-gate.sh")
warn_block_status=$?
set -e
test "$warn_block_status" -eq 2
printf '%s' "$warn_block_output" | jq -s -e \
  'length == 1 and .[0].decision == "block"
    and (.[0].hookSpecificOutput.additionalContext | contains("YAML parser"))
    and (.[0].hookSpecificOutput.additionalContext | contains("Phase-5"))' >/dev/null

echo "PASS check-dev-flow-phase-gate"
