#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cat >"$test_tmp/valid.json" <<'JSON'
{
  "handoff": {
    "goal": "published",
    "purpose": "session workflow improvements",
    "completionCriteria": ["tests pass"],
    "constraints": ["worktree only"],
    "userCorrections": [{
      "sourceId": "correct-runtime",
      "original": "Claudeだけを使う",
      "normalized": "ランタイムごとに実在ツールを選ぶ",
      "target": "runtime adapter handoff"
    }],
    "inputs": [
      {"type": "priorFailure", "id": "bootstrap-fail"},
      {"actionable": true,
       "scopeConfirmation": {
         "investigationAndImplementation": "proceed",
         "goalScope": "publication"
       },
       "findings": [
        {"id": "image-finding", "source": "screen.png", "observation": "missing gate"}
      ],
       "expectedChange": ["add gate"],
       "verification": ["dynamic test"]}
    ],
    "publication": {
      "required": true,
      "target": "agent-toolkit",
      "verification": "remote refetch"
    }
  },
  "coverage": [
    {"sourceId":"correct-runtime","source":"correction","target":"skill","implementation":"adapter","verification":"static test","status":"verified"},
    {"sourceId":"bootstrap-fail","source":"prior failure","target":"hook","implementation":"remove fake log","verification":"dynamic test","status":"verified"},
    {"sourceId":"image-finding","source":"image","target":"handoff","implementation":"map finding","verification":"validator test","status":"verified"}
  ],
  "publicationEvidence": {
    "commit":{"sha":"abc123","repository":"agent-toolkit"},
    "push":{"sha":"abc123","remote":"origin","ref":"refs/heads/fix"},
    "sync":{"command":"node scripts/sync-payload.mjs --apply","exitCode":0},
    "remoteFetch":{"remote":"origin","ref":"refs/heads/fix","sha":"abc123","contentVerified":true}
  }
}
JSON

node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/valid.json" >/dev/null
node "$here/validate-handoff-coverage.mjs" implementation "$test_tmp/valid.json" >/dev/null
node "$here/validate-handoff-coverage.mjs" coverage-completion "$test_tmp/valid.json" >/dev/null
node "$here/validate-handoff-coverage.mjs" publication "$test_tmp/valid.json" >/dev/null

printf '%s\n' '{}' >"$test_tmp/empty.json"
if node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/empty.json" >/dev/null 2>&1; then
  echo "empty handoff unexpectedly passed" >&2
  exit 1
fi

jq 'del(.coverage[2].verification)' "$test_tmp/valid.json" >"$test_tmp/missing.json"
if node "$here/validate-handoff-coverage.mjs" implementation "$test_tmp/missing.json" >/dev/null 2>&1; then
  echo "missing verification unexpectedly passed" >&2
  exit 1
fi

jq '.publicationEvidence = {
  commit:"done", push:"done", sync:"done", remoteFetch:"done"
}' "$test_tmp/valid.json" >"$test_tmp/unpublished.json"
if node "$here/validate-handoff-coverage.mjs" publication "$test_tmp/unpublished.json" >/dev/null 2>&1; then
  echo "fake string publication evidence unexpectedly passed" >&2
  exit 1
fi

jq '.handoff.inputs += [
  {"type":"priorFailure"},
  {"actionable":true,"findings":[{"id":"","source":"","observation":""}]}
]' "$test_tmp/valid.json" >"$test_tmp/invalid-sources.json"
if node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/invalid-sources.json" >/dev/null 2>&1; then
  echo "invalid source identifiers unexpectedly passed" >&2
  exit 1
fi

jq '.handoff.userCorrections += [{"sourceId":"incomplete"}]' "$test_tmp/valid.json" \
  >"$test_tmp/invalid-correction.json"
if node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/invalid-correction.json" >/dev/null 2>&1; then
  echo "correction without original/normalized/target unexpectedly passed" >&2
  exit 1
fi

jq 'del(.handoff.inputs[1].scopeConfirmation)' "$test_tmp/valid.json" \
  >"$test_tmp/unconfirmed-image.json"
if node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/unconfirmed-image.json" >/dev/null 2>&1; then
  echo "actionable image without two-stage confirmation unexpectedly passed" >&2
  exit 1
fi

jq 'del(.handoff.inputs[1].expectedChange, .handoff.inputs[1].verification)' \
  "$test_tmp/valid.json" >"$test_tmp/image-missing-change-verification.json"
if node "$here/validate-handoff-coverage.mjs" schema \
  "$test_tmp/image-missing-change-verification.json" >/dev/null 2>&1; then
  echo "actionable image without expectedChange/verification unexpectedly passed" >&2
  exit 1
fi

jq '.handoff.inputs[1].expectedChange = "add gate"
  | .handoff.inputs[1].verification = {method:"dynamic test"}' \
  "$test_tmp/valid.json" >"$test_tmp/image-invalid-change-verification-types.json"
if node "$here/validate-handoff-coverage.mjs" schema \
  "$test_tmp/image-invalid-change-verification-types.json" >/dev/null 2>&1; then
  echo "actionable image with invalid expectedChange/verification types unexpectedly passed" >&2
  exit 1
fi

jq '.handoff.inputs[1].scopeConfirmation = {
  investigationAndImplementation:"transcription-only", goalScope:null
}' "$test_tmp/valid.json" >"$test_tmp/transcription-only.json"
node "$here/validate-handoff-coverage.mjs" schema "$test_tmp/transcription-only.json" >/dev/null
if node "$here/validate-handoff-coverage.mjs" implementation "$test_tmp/transcription-only.json" >/dev/null 2>&1; then
  echo "transcription-only image unexpectedly authorized implementation" >&2
  exit 1
fi

skill_root=$(cd "$here/.." && pwd)
grep -q '全ルート共通の実装開始・FAIL gate' "$skill_root/SKILL.md"
grep -q 'validate-handoff-coverage.mjs implementation' \
  "$skill_root/references/phase-d-docs-editing.md"
grep -q 'coverage-completion validator' \
  "$skill_root/references/incident-flow-i1-i7.md"
if rg -n '回帰テストの追加（後日でも可）' \
  "$skill_root/references/incident-flow-i1-i7.md" >/dev/null; then
  echo "incident regression deferral remains" >&2
  exit 1
fi

transcribing_root=$(cd "$skill_root/../transcribing-images" && pwd)
session_root=$(cd "$skill_root/../managing-session-workflow" && pwd)
grep -q 'ここまでで本 Skill は完結する' "$transcribing_root/SKILL.md"
grep -q '標準 reviewer・通常応答へ縮退' "$transcribing_root/SKILL.md"
grep -q '画像文字起こしの完了を、特定 Skill の存在や起動に依存させない' \
  "$session_root/SKILL.md"
if rg -n -F \
  -e 'Skill("subagent-investigation-checklist")' \
  -e 'Skill("presenting-plan-with-artifacts")' \
  -e 'Skill("managing-review-sets")' \
  "$transcribing_root/SKILL.md" "$transcribing_root/references/transcribing-images-guide.html" >/dev/null; then
  echo "transcribing-images still hard-depends on a downstream skill" >&2
  exit 1
fi

grep -q '独立 reviewer も利用できない場合' "$skill_root/SKILL.md"
grep -q 'presenting-plan-with-artifacts.*利用可能なら' \
  "$skill_root/references/phase-4-prd-creation.md"
grep -q 'frontend-design.*利用可能なら' \
  "$skill_root/references/phase-4-prd-creation.md"
grep -q '明示承認なしに実行しない' \
  "$skill_root/references/module-preflight-check.md"
grep -q '具体的なコマンドまたは差分、影響範囲を提示' \
  "$skill_root/references/module-preflight-check.md"
grep -q '明示承認後だけ実行' \
  "$skill_root/references/module-preflight-check.md"
grep -q '追記差分を提示し、明示承認後だけ編集' \
  "$skill_root/references/module-preflight-check.md"
grep -q 'ユーザーが明示承認した場合だけ' \
  "$skill_root/references/phase-2-branch-preparation.md"
if rg -n 'curl -fsSL https://raw.githubusercontent.com/Homebrew|自動インストールを実行する|他ルートは従来どおり依存パッケージをインストール|存在しない場合は自動生成する|mkdir -p.*自動作成|不足行を追記する' \
  "$skill_root/references/module-preflight-check.md" \
  "$skill_root/references/phase-2-branch-preparation.md" >/dev/null; then
  echo "automatic environment installation remains" >&2
  exit 1
fi

if test -e "$skill_root/references/creating-screen-mock-examples-issue-1588-mockup.html" ||
  rg -n 'issue.?1588|#1588' "$skill_root/SKILL.md" "$skill_root/assets" \
    "$skill_root/references" >/dev/null; then
  echo "issue-specific mock artifact remains in the reusable skill" >&2
  exit 1
fi

echo "PASS validate-handoff-coverage"
