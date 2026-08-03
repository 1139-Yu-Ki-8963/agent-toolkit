#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$skill_dir/../../.." && pwd)"
skill_file="$skill_dir/SKILL.md"
validator="$repo_root/shared/scripts/glossary/validate-semantic-glossary.sh"
validator_py="$repo_root/shared/scripts/glossary/validate-semantic-glossary.py"
projector="$repo_root/shared/scripts/detail-pages/project-semantic-glossary.py"
fixtures="$repo_root/shared/scripts/glossary/fixtures"
canonical_registry="$fixtures/canonical-registry"
report_schema="$repo_root/shared/schemas/semantic-glossary/1.0.0/validation-report.schema.yaml"
python_bin="$repo_root/shared/scripts/glossary/.venv/bin/python"

require() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq -- "$pattern" "$skill_file"; then
    printf 'FAIL: %s\n' "$label" >&2
    exit 1
  fi
}

assert_report() {
  local report="$1"
  local expected_status="$2"
  local required_code="$3"
  "$python_bin" - "$report" "$report_schema" "$expected_status" "$required_code" <<'PY'
import json
import pathlib
import re
import sys

import jsonschema
import yaml

report_path, schema_path, expected_status, required_code = sys.argv[1:]
report = json.loads(pathlib.Path(report_path).read_text(encoding="utf-8"))
schema = yaml.safe_load(pathlib.Path(schema_path).read_text(encoding="utf-8"))
jsonschema.Draft202012Validator(schema).validate(report)
assert report["status"] == expected_status, report
actual = {name: 0 for name in ("error", "warning", "review_required")}
for finding in report["findings"]:
    actual[finding["severity"]] += 1
    assert re.fullmatch(r"(?:SGS|SGK|SGR|SGL|SGP|SGV|SGD)_[A-Z0-9_]+", finding["code"])
assert actual == report["counts"], (actual, report["counts"])
if required_code:
    assert required_code in {item["code"] for item in report["findings"]}, report
PY
}

run_validator() {
  local expected_exit="$1"
  local report="$2"
  shift 2
  local actual_exit=0
  set +e
  "$validator" "$@" --report "$report" >/dev/null 2>&1
  actual_exit=$?
  set -e
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    printf 'FAIL: expected validator exit %s, got %s\n' "$expected_exit" "$actual_exit" >&2
    exit 1
  fi
}

require '^name: managing-semantic-glossary$' 'name'
require '^invocation: managing-semantic-glossary$' 'invocation'
require '^type: orchestration$' 'type'
require 'dry-run|dry_run' 'dry-run default'
require 'business approver' 'business approval'
require 'technical approver' 'technical approval'
require 'active -> deprecated -> retired' 'lifecycle'
require 'validate-semantic-glossary\.sh' 'validator path'
require 'project-semantic-glossary\.py' 'portal projection path'
require 'ai_index' 'ai_index boundary'
require 'not_implemented' 'ai_index stop reason'
require 'SGS.*SGK.*SGR.*SGL.*SGP.*SGV.*SGD' 'diagnostic family handling'
require '--registry <file-or-dir>' 'registry argument contract'
require 'registry省略時.*review_required.*適用不可|registryが省略されたら.*review_required' 'registry omission blocking'
require '独立したCRUD runner.*ではない' 'procedural skill boundary'
require 'scripts/.*契約検証用テスト' 'test-only scripts boundary'
require '外部identity provider.*未実装' 'identity provider boundary'
require 'business_approver:<actor>.*technical_approver:<actor>.*role-qualified approval identity.*2件' 'role-qualified dual approval'

if [ ! -x "$validator" ] || [ ! -x "$python_bin" ]; then
  printf 'FAIL: validator runtime is unavailable\n' >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/managing-semantic-glossary.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
target="$tmp/glossary-target.yaml"
target_before="$tmp/glossary-target.before.yaml"
cp "$fixtures/valid-glossary.yaml" "$target"
cp "$target" "$target_before"
cp "$fixtures/valid-glossary.yaml" "$tmp/valid-input.before.yaml"
cp "$fixtures/invalid-glossary.yaml" "$tmp/invalid-input.before.yaml"
cp "$fixtures/valid-proposal.yaml" "$tmp/unapproved-proposal.before.yaml"
cp "$fixtures/invalid-approved-proposal.yaml" "$tmp/invalid-approved-proposal.before.yaml"

run_validator 0 "$tmp/valid.json" --kind glossary --input "$fixtures/valid-glossary.yaml" --registry "$canonical_registry"
assert_report "$tmp/valid.json" valid ""
cmp -s "$fixtures/valid-glossary.yaml" "$tmp/valid-input.before.yaml"
cmp -s "$target" "$target_before"

run_validator 1 "$tmp/invalid.json" --kind glossary --input "$fixtures/invalid-glossary.yaml"
assert_report "$tmp/invalid.json" invalid SGS_SCHEMA_VIOLATION
cmp -s "$fixtures/invalid-glossary.yaml" "$tmp/invalid-input.before.yaml"
cmp -s "$target" "$target_before"

printf '%s\n' 'schema_version: [' >"$tmp/malformed.yaml"
cp "$tmp/malformed.yaml" "$tmp/malformed.before.yaml"
run_validator 2 "$tmp/parse.json" --kind glossary --input "$tmp/malformed.yaml"
assert_report "$tmp/parse.json" unavailable SGD_PARSE
cmp -s "$tmp/malformed.yaml" "$tmp/malformed.before.yaml"
cmp -s "$target" "$target_before"

dependency_exit=0
set +e
"$python_bin" -S "$validator_py" --kind glossary --input "$fixtures/valid-glossary.yaml" --report "$tmp/dependency.json" >/dev/null 2>&1
dependency_exit=$?
set -e
if [ "$dependency_exit" -ne 2 ]; then
  printf 'FAIL: dependency case expected exit 2, got %s\n' "$dependency_exit" >&2
  exit 1
fi
assert_report "$tmp/dependency.json" unavailable SGD_DEPENDENCY
cmp -s "$fixtures/valid-glossary.yaml" "$tmp/valid-input.before.yaml"
cmp -s "$target" "$target_before"

run_validator 0 "$tmp/review-required.json" --kind glossary --input "$fixtures/valid-review-required-glossary.yaml"
assert_report "$tmp/review-required.json" valid SGK_ALLOWED_FORM_COLLISION
"$python_bin" - "$tmp/review-required.json" <<'PY'
import json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["counts"]["review_required"] > 0
decision = "blocked" if report["counts"]["review_required"] else "applicable"
assert decision == "blocked"
PY
cmp -s "$fixtures/valid-proposal.yaml" "$tmp/unapproved-proposal.before.yaml"

run_validator 0 "$tmp/missing-registry-proposal.json" --kind proposal --input "$fixtures/valid-proposal.yaml"
assert_report "$tmp/missing-registry-proposal.json" valid ""
cmp -s "$target" "$target_before"

run_validator 0 "$tmp/unapproved-proposal.json" --kind proposal --input "$fixtures/valid-proposal.yaml" --registry "$fixtures/valid-glossary.yaml"
assert_report "$tmp/unapproved-proposal.json" valid ""
"$python_bin" - "$fixtures/valid-proposal.yaml" "$target" "$target_before" <<'PY'
import pathlib, sys, yaml
proposal = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert proposal["proposal"]["approval"]["status"] != "approved"
assert pathlib.Path(sys.argv[2]).read_bytes() == pathlib.Path(sys.argv[3]).read_bytes()
PY

run_validator 1 "$tmp/invalid-approved-proposal.json" --kind proposal --input "$fixtures/invalid-approved-proposal.yaml" --registry "$fixtures/valid-glossary.yaml"
assert_report "$tmp/invalid-approved-proposal.json" invalid SGP_TWO_PARTY_APPROVAL_REQUIRED
cmp -s "$fixtures/invalid-approved-proposal.yaml" "$tmp/invalid-approved-proposal.before.yaml"
cmp -s "$target" "$target_before"

portal_output="$tmp/portal-page-data.json"
ai_index_output="$tmp/ai-index.json"
other_output="$tmp/other-publish.json"
"$python_bin" "$projector" --input "$fixtures/valid-glossary.yaml" --registry "$canonical_registry" --output "$portal_output" >/dev/null
test -s "$portal_output"
"$python_bin" - "$portal_output" <<'PY'
import json, pathlib, sys
page = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert page["pageKind"] == "glossary"
assert page["glossarySchemaVersion"] == "1.0.0"
PY
proposal_projection_exit=0
set +e
"$python_bin" "$projector" --input "$fixtures/valid-proposal.yaml" --registry "$canonical_registry" --output "$tmp/proposal-page-data.json" >/dev/null 2>&1
proposal_projection_exit=$?
set -e
test "$proposal_projection_exit" -eq 1
test ! -e "$tmp/proposal-page-data.json"
test ! -e "$ai_index_output"
other_target=pdf
other_status=review_required
test "$other_target" != portal
test "$other_status" = review_required
test ! -e "$other_output"
if "$python_bin" "$projector" --help | grep -Eq -- '--target|ai_index'; then
  printf 'FAIL: projector exposes a non-portal publish target\n' >&2
  exit 1
fi

"$python_bin" "$skill_dir/scripts/verify-ai-forward-test.py" \
  "$skill_dir/verification/ai-forward-test.json" \
  "$skill_dir/verification/ai-forward-test-record.schema.json" \
  "$repo_root"
reproduced_portal="$tmp/reproduced-portal-page-data.json"
"$python_bin" "$projector" --input "$fixtures/valid-glossary.yaml" --registry "$canonical_registry" --output "$reproduced_portal" >/dev/null
cmp -s "$reproduced_portal" "$skill_dir/verification/portal-page-data.json"

printf 'PASS: managing-semantic-glossary CLI integration and static policy contract\n'
