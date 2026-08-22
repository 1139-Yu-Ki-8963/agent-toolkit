#!/usr/bin/env bash
set -euo pipefail

# 実装判断: 無引数の実行で検査本体が走り切る構造のため、--self-test を
#   受けても同じ動作をすればよい。集約（run-layer-machine-checks.sh）は
#   --self-test の文字列を持つスクリプトを対象として集めるため、この分岐が
#   無いと「自己テスト未整備」として警告される。2026-08-21 に追加。
case "${1:-}" in --self-test) ;; esac

# 第1層の集約（generation-engine/scripts/verification/run-layer-machine-checks.sh）へ載せている。
# 2026-08-19 に、この検査が終了コード 2 を返す形へ直し、集約の側も終了コード 2 を
# [UNKNOWN] として不合格と区別するようにした。集約全体の終了コードには影響しない。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOSSARY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$GLOSSARY_DIR/validate-semantic-glossary.sh"
VALIDATOR_PY="$GLOSSARY_DIR/validate-semantic-glossary.py"
FIXTURES="$GLOSSARY_DIR/fixtures"
SCHEMA="$GLOSSARY_DIR/../../schemas/semantic-glossary/1.0.0/validation-report.schema.yaml"
PYTHON="$GLOSSARY_DIR/.venv/bin/python"

if [ ! -x "$VALIDATOR" ]; then
  echo "FAIL: validator is missing or not executable: $VALIDATOR" >&2
  exit 1
fi

if [ ! -x "$PYTHON" ]; then
  # 隔離環境が無いのは実行できなかったことであり、検査の対象が不合格だった
  # ことではない。判定不能の決まり（indeterminate-result）に従い終了コード 2 を
  # 返す。集約はこれを [UNKNOWN] として不合格と区別する（2026-08-19）。
  echo "[UNKNOWN] 隔離環境が無いため判定できません: $PYTHON" >&2
  exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/semantic-glossary-validator.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
passed=0

assert_report() {
  local report="$1"
  local expected_status="$2"
  local required_codes="$3"
  "$PYTHON" - "$report" "$SCHEMA" "$expected_status" "$required_codes" <<'PY'
import json
import pathlib
import sys

import jsonschema
import yaml

report_path, schema_path, expected_status, required_codes = sys.argv[1:]
report = json.loads(pathlib.Path(report_path).read_text(encoding="utf-8"))
schema = yaml.safe_load(pathlib.Path(schema_path).read_text(encoding="utf-8"))
jsonschema.Draft202012Validator(schema).validate(report)
if report["status"] != expected_status:
    raise SystemExit(f"expected status={expected_status}, got {report['status']}")
counts = report["counts"]
actual_counts = {severity: 0 for severity in ("error", "warning", "review_required")}
for finding in report["findings"]:
    actual_counts[finding["severity"]] += 1
if counts != actual_counts:
    raise SystemExit(f"finding counts differ: root={counts}, actual={actual_counts}")
sort_keys = [
    (item["severity"], item["code"], item["path"], item["message"])
    for item in report["findings"]
]
if sort_keys != sorted(sort_keys):
    raise SystemExit("findings are not stably sorted")
actual_codes = {finding["code"] for finding in report["findings"]}
missing = set(filter(None, required_codes.split(","))) - actual_codes
if missing:
    raise SystemExit(f"required diagnostic codes are missing: {sorted(missing)}")
PY
}

run_case() {
  local name="$1"
  local expected_exit="$2"
  local expected_status="$3"
  local required_codes="$4"
  shift 4
  local report="$tmp/$name.json"
  local stdout="$tmp/$name.stdout"
  local stderr="$tmp/$name.stderr"
  local actual_exit=0
  set +e
  "$VALIDATOR" "$@" --report "$report" >"$stdout" 2>"$stderr"
  actual_exit=$?
  set -e
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "FAIL: $name expected exit $expected_exit, got $actual_exit" >&2
    cat "$stdout" >&2
    cat "$stderr" >&2
    exit 1
  fi
  assert_report "$report" "$expected_status" "$required_codes"
  echo "PASS: $name"
  passed=$((passed + 1))
}

run_case valid-glossary-requires-publication-registry 0 valid "SGP_PUBLICATION_REGISTRY_REQUIRED" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml"
run_case valid-glossary-with-canonical-publication-registry 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml" \
  --registry "$FIXTURES/canonical-registry"
run_case valid-explicit-fourteen-columns-glossary 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-explicit-columns-glossary.yaml"
run_case valid-proposal 0 valid "" \
  --kind proposal --input "$FIXTURES/valid-proposal.yaml"
run_case valid-update-proposal-excludes-target-term 0 valid "" \
  --kind proposal --input "$FIXTURES/valid-update-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case merged-proposal-target-version-and-role-qualified-actor 0 valid "" \
  --kind proposal --input "$FIXTURES/valid-merged-same-actor-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary-2.1.yaml"
run_case valid-change 0 valid "" \
  --kind change --input "$FIXTURES/valid-change.yaml"
run_case valid-change-resolves-affected-term-in-registry 0 valid "" \
  --kind change --input "$FIXTURES/valid-registry-change.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case retire-change-validates-applied-retired-state 0 valid "" \
  --kind change --input "$FIXTURES/valid-retire-change.yaml" \
  --registry "$FIXTURES/valid-lifecycle-applied-glossary.yaml"
run_case merge-change-validates-survivor-and-retired-sources 0 valid "" \
  --kind change --input "$FIXTURES/valid-merge-change.yaml" \
  --registry "$FIXTURES/valid-lifecycle-applied-glossary.yaml"
run_case retire-change-rejects-active-applied-state 1 invalid \
  "SGP_CHANGE_APPLIED_STATE_MISMATCH" \
  --kind change --input "$FIXTURES/valid-retire-change.yaml" \
  --registry "$FIXTURES/invalid-lifecycle-applied-glossary.yaml"
run_case merge-change-rejects-missing-retired-source 1 invalid \
  "SGP_CHANGE_APPLIED_STATE_MISMATCH" \
  --kind change --input "$FIXTURES/valid-merge-change.yaml" \
  --registry "$FIXTURES/invalid-lifecycle-applied-glossary.yaml"
proposal_change_registry="$tmp/proposal-change-registry"
mkdir -p "$proposal_change_registry"
cp "$FIXTURES/valid-glossary.yaml" "$proposal_change_registry/glossary.yaml"
cp "$FIXTURES/valid-approved-update-proposal.yaml" "$proposal_change_registry/proposal.yaml"
run_case valid-proposal-derived-change-with-complete-audit 0 valid "" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$proposal_change_registry"
decision_reason_change_registry="$tmp/decision-reason-change-registry"
mkdir -p "$decision_reason_change_registry"
cp "$FIXTURES/valid-glossary.yaml" "$decision_reason_change_registry/glossary.yaml"
cp "$FIXTURES/valid-approved-update-proposal.yaml" "$decision_reason_change_registry/proposal.yaml"
"$PYTHON" - "$decision_reason_change_registry/proposal.yaml" <<'PY'
import pathlib
import sys

import yaml

path = pathlib.Path(sys.argv[1])
proposal = yaml.safe_load(path.read_text(encoding="utf-8"))
proposal["proposal"]["approval"]["decision_reason"] = "承認理由だけを事後改変"
path.write_text(yaml.safe_dump(proposal, allow_unicode=True, sort_keys=False), encoding="utf-8")
PY
run_case proposal-derived-change-rejects-canonical-decision-reason-drift 1 invalid \
  "SGP_CHANGE_PROPOSAL_SNAPSHOT_MISMATCH" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$decision_reason_change_registry"
decision_reason_publication_registry="$tmp/decision-reason-publication-registry"
mkdir -p "$decision_reason_publication_registry"
cp "$decision_reason_change_registry/proposal.yaml" "$decision_reason_publication_registry/customer-update-proposal.yaml"
cp "$FIXTURES/canonical-registry/customer-update-change.yaml" "$decision_reason_publication_registry/customer-update-change.yaml"
cp "$FIXTURES/canonical-registry/customer-id-proposal.yaml" "$decision_reason_publication_registry/customer-id-proposal.yaml"
cp "$FIXTURES/canonical-registry/customer-id-change.yaml" "$decision_reason_publication_registry/customer-id-change.yaml"
run_case publication-rejects-canonical-decision-reason-drift 1 invalid \
  "SGP_PUBLICATION_ATTESTATION_INVALID" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml" \
  --registry "$decision_reason_publication_registry"
invalid_canonical_proposal_registry="$tmp/invalid-canonical-proposal-registry"
mkdir -p "$invalid_canonical_proposal_registry"
cp "$FIXTURES/valid-glossary.yaml" "$invalid_canonical_proposal_registry/glossary.yaml"
cp "$FIXTURES/invalid-canonical-proposal-semantics.yaml" "$invalid_canonical_proposal_registry/proposal.yaml"
run_case proposal-derived-change-rejects-semantically-invalid-canonical-proposal 1 invalid \
  "SGP_CHANGE_CANONICAL_PROPOSAL_INVALID" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$invalid_canonical_proposal_registry"
invalid_applied_term_registry="$tmp/invalid-applied-term-registry"
mkdir -p "$invalid_applied_term_registry"
cp "$FIXTURES/invalid-applied-term-glossary.yaml" "$invalid_applied_term_registry/glossary.yaml"
cp "$FIXTURES/valid-approved-update-proposal.yaml" "$invalid_applied_term_registry/proposal.yaml"
run_case proposal-derived-change-rejects-applied-term-drift 1 invalid \
  "SGP_CHANGE_APPLIED_TERM_MISMATCH,SGP_CHANGE_AFTER_HASH_MISMATCH" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$invalid_applied_term_registry"
run_case publication-rejects-self-claimed-unresolved-refs 1 invalid \
  "SGP_PUBLICATION_REF_UNRESOLVED" \
  --kind glossary --input "$FIXTURES/invalid-publication-self-claim-glossary.yaml" \
  --registry "$FIXTURES/canonical-registry"
manual_publication_registry="$tmp/manual-publication-registry"
mkdir -p "$manual_publication_registry"
cp "$FIXTURES/canonical-registry/customer-update-proposal.yaml" "$manual_publication_registry/customer-update-proposal.yaml"
cp "$FIXTURES/invalid-publication-manual-change.yaml" "$manual_publication_registry/customer-update-change.yaml"
cp "$FIXTURES/canonical-registry/customer-id-proposal.yaml" "$manual_publication_registry/customer-id-proposal.yaml"
cp "$FIXTURES/canonical-registry/customer-id-change.yaml" "$manual_publication_registry/customer-id-change.yaml"
run_case publication-rejects-manual-change-proposal-bypass 1 invalid \
  "SGP_PUBLICATION_BINDING_MISMATCH" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml" \
  --registry "$manual_publication_registry"
run_case proposal-all-statuses-require-event-history 1 invalid "SGP_EVENT_REQUIRED" \
  --kind proposal --input "$FIXTURES/invalid-proposal-missing-events.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case proposal-change-requires-approved-reviewer-roles 1 invalid "SGP_PROPOSAL_AUDIT_APPROVAL_REQUIRED" \
  --kind change --input "$FIXTURES/invalid-proposal-change-rejected-reviewers.yaml" \
  --registry "$proposal_change_registry"
run_case proposal-change-requires-complete-approval-events 1 invalid "SGP_PROPOSAL_AUDIT_HISTORY_REQUIRED" \
  --kind change --input "$FIXTURES/invalid-proposal-change-missing-events.yaml" \
  --registry "$proposal_change_registry"
run_case proposal-change-requires-role-actor-identity-match 1 invalid "SGP_PROPOSAL_AUDIT_APPROVER_MISMATCH" \
  --kind change --input "$FIXTURES/invalid-proposal-change-approver-mismatch.yaml" \
  --registry "$proposal_change_registry"
run_case change-requires-target-glossary-when-registry-specified 1 invalid \
  "SGR_CHANGE_GLOSSARY_MISSING" \
  --kind change --input "$FIXTURES/invalid-missing-glossary-change.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case single-approver-change-is-rejected 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind change --input "$FIXTURES/invalid-single-approver-change.yaml"
run_case unqualified-change-approvers-are-rejected 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind change --input "$FIXTURES/invalid-unqualified-approvers-change.yaml"
run_case empty-is-zero-results 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml"
run_case schema-required-negative-is-independent 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/invalid-required-glossary.yaml"
run_case schema-enum-negative-is-independent 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/invalid-enum-glossary.yaml"
run_case schema-pattern-negative-is-independent 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/invalid-pattern-glossary.yaml"
run_case confidence-minimum-boundary-is-valid 0 valid "" \
  --kind proposal --input "$FIXTURES/valid-boundary-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case legacy-page-data-requires-explicit-migration 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/invalid-legacy-migration-glossary.yaml"
run_case warning-is-nonblocking 0 valid "SGS_DEFINITION_TAUTOLOGY" \
  --kind glossary --input "$FIXTURES/valid-warning-glossary.yaml"
run_case review-required-is-cli-nonblocking 0 valid "SGK_ALLOWED_FORM_COLLISION" \
  --kind glossary --input "$FIXTURES/valid-review-required-glossary.yaml"
run_case unapproved-glossary-is-not-publishable 0 valid "SGP_PUBLICATION_APPROVAL_REQUIRED" \
  --kind glossary --input "$FIXTURES/valid-unapproved-glossary.yaml"
run_case approved-glossary-rejects-legacy-source-marker 1 invalid \
  "SGS_SCHEMA_VIOLATION,SGP_APPROVED_LEGACY_SOURCE_FORBIDDEN" \
  --kind glossary --input "$FIXTURES/invalid-approved-legacy-source-glossary.yaml"
run_case schema-key-ref-lifecycle-version-errors 1 invalid \
  "SGS_SCHEMA_VIOLATION,SGK_MEANINGLESS,SGR_MISSING,SGL_ACTIVE_HAS_RETIREMENT,SGV_LIFECYCLE_VERSION,SGV_SCHEMA_VERSION" \
  --kind glossary --input "$FIXTURES/invalid-glossary.yaml"
run_case normalized-collision-and-cycle 1 invalid \
  "SGK_FORBIDDEN_FORM_COLLISION,SGR_CYCLE" \
  --kind glossary --input "$FIXTURES/invalid-collision-cycle-glossary.yaml"
run_case proposal-approval-and-stale-base 1 invalid \
  "SGP_CONFIDENCE_LEVEL,SGP_INVALID_TRANSITION,SGP_TWO_PARTY_APPROVAL_REQUIRED,SGP_STALE_BASE" \
  --kind proposal --input "$FIXTURES/invalid-approved-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case change-version-and-ref 1 invalid \
  "SGK_MEANINGLESS,SGR_MISSING,SGV_VERSION_ORDER" \
  --kind change --input "$FIXTURES/invalid-change.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case kind-mixing-is-rejected 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind proposal --input "$FIXTURES/valid-glossary.yaml"

"$PYTHON" - "$FIXTURES" "$tmp" <<'PY'
import copy
import pathlib
import sys

import yaml

fixtures, output = map(pathlib.Path, sys.argv[1:])
proposal = yaml.safe_load((fixtures / "valid-proposal.yaml").read_text(encoding="utf-8"))

invalid_term = copy.deepcopy(proposal)
term = invalid_term["proposed_term"]
term["key"] = "item_001"
term["scope"]["includes"] = ["missing_scope"]
term["aliases"] = [{"value": "顧客", "type": "synonym", "language": "ja", "usage": "allowed"}]
term["forbidden_terms"] = [{"value": "顧客", "reason": "許可表記との衝突", "replacement_key": "missing_term"}]
term["relations"] = [{"type": "part_of", "target_key": "missing_term"}]
term["lifecycle"] = {
    "status": "active",
    "introduced_in": "3.0.0",
    "replaced_by": "missing_term",
    "reason": "active状態の不正値",
}
(output / "invalid-proposed-term.yaml").write_text(
    yaml.safe_dump(invalid_term, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

missing_target = copy.deepcopy(proposal)
missing_target["target_glossary_key"] = "missing_catalog"
(output / "missing-target-proposal.yaml").write_text(
    yaml.safe_dump(missing_target, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

approved_without_events = copy.deepcopy(proposal)
approval = approved_without_events["proposal"]["approval"]
approval.update(
    {
        "status": "approved",
        "reviewed_at": "2026-08-01T02:00:00Z",
        "events": [],
        "reviewers": [
            {"actor": "business-reviewer", "role": "business_approver", "decision": "approved", "decided_at": "2026-08-01T01:00:00Z"},
            {"actor": "architecture-reviewer", "role": "technical_approver", "decision": "approved", "decided_at": "2026-08-01T01:30:00Z"},
        ],
    }
)
(output / "approved-without-events.yaml").write_text(
    yaml.safe_dump(approved_without_events, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

update_proposal = yaml.safe_load((fixtures / "valid-update-proposal.yaml").read_text(encoding="utf-8"))
stale_update = copy.deepcopy(update_proposal)
stale_update["base_content_version"] = "1.9.0"
(output / "stale-update-proposal.yaml").write_text(
    yaml.safe_dump(stale_update, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
other_term_collision = copy.deepcopy(update_proposal)
other_term_collision["proposed_term"]["label"] = "顧客ID"
(output / "update-collides-with-other-term.yaml").write_text(
    yaml.safe_dump(other_term_collision, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

operation_omitted = copy.deepcopy(proposal)
operation_omitted.pop("proposal_operation", None)
(output / "operation-omitted-proposal.yaml").write_text(
    yaml.safe_dump(operation_omitted, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
add_existing = copy.deepcopy(update_proposal)
add_existing["proposal_operation"] = "add"
(output / "add-existing-proposal.yaml").write_text(
    yaml.safe_dump(add_existing, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
update_missing = copy.deepcopy(proposal)
update_missing["proposal_operation"] = "update"
(output / "update-missing-proposal.yaml").write_text(
    yaml.safe_dump(update_missing, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
dangling_evidence = copy.deepcopy(proposal)
dangling_evidence["proposal"]["extracted_facts"][0]["evidence_ref"] = "missing://evidence"
(output / "dangling-evidence-proposal.yaml").write_text(
    yaml.safe_dump(dangling_evidence, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
duplicate_evidence = copy.deepcopy(proposal)
duplicate_evidence["proposal"]["evidence"].append(copy.deepcopy(duplicate_evidence["proposal"]["evidence"][0]))
(output / "duplicate-evidence-proposal.yaml").write_text(
    yaml.safe_dump(duplicate_evidence, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
short_hash = copy.deepcopy(proposal)
short_hash["proposal"]["evidence"][0]["excerpt_hash"] = "sha256:a"
(output / "short-hash-proposal.yaml").write_text(
    yaml.safe_dump(short_hash, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
time_forged = yaml.safe_load((fixtures / "valid-merged-same-actor-proposal.yaml").read_text(encoding="utf-8"))
time_forged["proposal"]["approval"]["reviewers"][0]["decided_at"] = "2099-01-01T00:00:00Z"
time_forged["proposal"]["approval"]["events"][1]["occurred_at"] = "2030-01-01T00:00:00Z"
time_forged["proposal"]["approval"]["events"][2]["occurred_at"] = "2020-01-01T00:00:00Z"
(output / "time-forged-proposal.yaml").write_text(
    yaml.safe_dump(time_forged, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
blank_actor = copy.deepcopy(proposal)
blank_actor["proposal"]["approval"]["events"][0]["actor"] = " "
(output / "blank-actor-proposal.yaml").write_text(
    yaml.safe_dump(blank_actor, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

canonical = yaml.safe_load((fixtures / "valid-approved-update-proposal.yaml").read_text(encoding="utf-8"))
approved_null_reason = copy.deepcopy(canonical)
approved_null_reason["proposal"]["approval"]["status"] = "approved"
approved_null_reason["proposal"]["approval"]["decision_reason"] = None
approved_null_reason["proposal"]["approval"]["events"] = approved_null_reason["proposal"]["approval"]["events"][:-1]
approved_null_reason["merged_revision"] = None
(output / "approved-null-decision-reason.yaml").write_text(
    yaml.safe_dump(approved_null_reason, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
merged_blank_reason = copy.deepcopy(canonical)
merged_blank_reason["proposal"]["approval"]["decision_reason"] = "   "
(output / "merged-blank-decision-reason.yaml").write_text(
    yaml.safe_dump(merged_blank_reason, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
valid_change = yaml.safe_load((fixtures / "valid-proposal-change.yaml").read_text(encoding="utf-8"))
snapshot_mismatch = copy.deepcopy(valid_change)
snapshot_mismatch["proposal_audit"]["confidence"]["rationale"] = "改ざんされたsnapshot"
(output / "snapshot-mismatch-change.yaml").write_text(
    yaml.safe_dump(snapshot_mismatch, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
time_forged_change = copy.deepcopy(valid_change)
time_forged_change["proposal_audit"]["approval_events"][1]["occurred_at"] = "2030-01-01T00:00:00Z"
time_forged_change["proposal_audit"]["approval_events"][2]["occurred_at"] = "2020-01-01T00:00:00Z"
time_forged_change["applied_at"] = "2010-01-01T00:00:00Z"
(output / "time-forged-change.yaml").write_text(
    yaml.safe_dump(time_forged_change, allow_unicode=True, sort_keys=False), encoding="utf-8"
)
unapproved = copy.deepcopy(canonical)
unapproved["proposal"]["approval"] = {
    "status": "detected",
    "reviewers": [],
    "reviewed_at": None,
    "decision_reason": None,
    "events": [canonical["proposal"]["approval"]["events"][0]],
}
unapproved_registry = output / "unapproved-proposal-registry"
unapproved_registry.mkdir()
(unapproved_registry / "glossary.yaml").write_text((fixtures / "valid-glossary.yaml").read_text(encoding="utf-8"), encoding="utf-8")
(unapproved_registry / "proposal.yaml").write_text(
    yaml.safe_dump(unapproved, allow_unicode=True, sort_keys=False), encoding="utf-8"
)

registry_dir = output / "registry-collision"
registry_dir.mkdir()
source = yaml.safe_load((fixtures / "valid-glossary.yaml").read_text(encoding="utf-8"))

def registry_document(glossary_key, term_index, term_key, label, aliases, forbidden):
    document = copy.deepcopy(source)
    document["glossary_key"] = glossary_key
    document["scope"]["includes"] = [f"{glossary_key}_scope"]
    document["scope_catalog"] = [{"key": f"{glossary_key}_scope", "level": "application", "parent_key": None, "source_ref": "docs/registry.md"}]
    term = document["terms"][term_index]
    term["key"] = term_key
    term["label"] = label
    term["scope"]["includes"] = [f"{glossary_key}_scope"]
    term["aliases"] = [{"value": value, "type": "synonym", "language": "ja", "usage": "allowed"} for value in aliases]
    term["forbidden_terms"] = [{"value": value, "reason": "横断衝突検証", "replacement_key": term_key} for value in forbidden]
    term.pop("relations", None)
    document["terms"] = [term]
    return document

documents = [
    registry_document("registry_catalog", 0, "registry_customer", "共通名", ["共有別名"], []),
    registry_document("registry_catalog", 1, "registry_client", "別概念", ["共通名"], ["共有別名"]),
    registry_document("registry_third", 0, "registry_customer", "第三概念", [], []),
]
for index, document in enumerate(documents):
    (registry_dir / f"registry-{index}.yaml").write_text(
        yaml.safe_dump(document, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
PY

run_case proposal-validates-proposed-term 1 invalid \
  "SGK_MEANINGLESS,SGK_FORBIDDEN_FORM_COLLISION,SGR_MISSING,SGL_ACTIVE_HAS_RETIREMENT,SGV_LIFECYCLE_VERSION" \
  --kind proposal --input "$tmp/invalid-proposed-term.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case proposal-requires-target-glossary 1 invalid "SGR_TARGET_GLOSSARY_MISSING" \
  --kind proposal --input "$tmp/missing-target-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case update-proposal-stale-base-remains-review-required 0 valid "SGP_STALE_BASE" \
  --kind proposal --input "$tmp/stale-update-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case update-proposal-other-term-collision-remains 0 valid "SGK_ALLOWED_FORM_COLLISION" \
  --kind proposal --input "$tmp/update-collides-with-other-term.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case operation-omission-is-review-required-with-registry 0 valid "SGP_OPERATION_REQUIRED" \
  --kind proposal --input "$tmp/operation-omitted-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case add-operation-rejects-existing-target 1 invalid "SGP_ADD_TARGET_EXISTS" \
  --kind proposal --input "$tmp/add-existing-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case update-operation-requires-existing-target 1 invalid "SGP_UPDATE_TARGET_MISSING" \
  --kind proposal --input "$tmp/update-missing-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case extracted-fact-must-resolve-evidence 1 invalid "SGP_EVIDENCE_REF_MISSING" \
  --kind proposal --input "$tmp/dangling-evidence-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case evidence-ref-must-be-unique 1 invalid "SGP_DUPLICATE_EVIDENCE_REF" \
  --kind proposal --input "$tmp/duplicate-evidence-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case excerpt-hash-must-be-full-sha256 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind proposal --input "$tmp/short-hash-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case proposal-audit-time-forgery-is-rejected 1 invalid "SGP_EVENT_TIME_ORDER,SGP_REVIEW_TIME_ORDER" \
  --kind proposal --input "$tmp/time-forged-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary-2.1.yaml"
run_case approval-actor-must-be-nonblank 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind proposal --input "$tmp/blank-actor-proposal.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case approved-proposal-requires-nonblank-decision-reason 1 invalid \
  "SGS_SCHEMA_VIOLATION,SGP_DECISION_REASON_REQUIRED" \
  --kind proposal --input "$tmp/approved-null-decision-reason.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case merged-proposal-requires-nonblank-decision-reason 1 invalid \
  "SGS_SCHEMA_VIOLATION,SGP_DECISION_REASON_REQUIRED" \
  --kind proposal --input "$tmp/merged-blank-decision-reason.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case proposal-derived-change-requires-registry-proposal 1 invalid "SGP_CHANGE_PROPOSAL_MISSING" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$FIXTURES/valid-glossary.yaml"
run_case proposal-derived-change-requires-approved-registry-proposal 1 invalid "SGP_CHANGE_PROPOSAL_UNAPPROVED" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$tmp/unapproved-proposal-registry"
run_case proposal-derived-change-snapshot-must-match-registry 1 invalid "SGP_CHANGE_PROPOSAL_SNAPSHOT_MISMATCH" \
  --kind change --input "$tmp/snapshot-mismatch-change.yaml" \
  --registry "$proposal_change_registry"
run_case proposal-derived-change-affected-key-must-match-proposed-term 1 invalid "SGP_CHANGE_TERM_MISMATCH" \
  --kind change --input "$FIXTURES/invalid-proposal-change-affected-key-mismatch.yaml" \
  --registry "$proposal_change_registry"
run_case proposal-derived-change-type-must-match-proposal-operation 1 invalid "SGP_CHANGE_OPERATION_MISMATCH" \
  --kind change --input "$FIXTURES/invalid-proposal-change-operation-mismatch.yaml" \
  --registry "$proposal_change_registry"

mutated_term_registry="$tmp/mutated-proposed-term-registry"
mkdir -p "$mutated_term_registry"
cp "$FIXTURES/valid-glossary.yaml" "$mutated_term_registry/glossary.yaml"
cp "$FIXTURES/invalid-approved-proposal-mutated-term-key.yaml" "$mutated_term_registry/proposal.yaml"
run_case proposal-derived-change-rejects-mutated-canonical-term-key 1 invalid "SGP_CHANGE_TERM_MISMATCH" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$mutated_term_registry"

mutated_content_registry="$tmp/mutated-proposal-content-registry"
mkdir -p "$mutated_content_registry"
cp "$FIXTURES/valid-glossary.yaml" "$mutated_content_registry/glossary.yaml"
cp "$FIXTURES/invalid-approved-proposal-mutated-content.yaml" "$mutated_content_registry/proposal.yaml"
run_case proposal-derived-change-rejects-approved-content-mutation 1 invalid "SGP_CHANGE_CONTENT_SNAPSHOT_MISMATCH" \
  --kind change --input "$FIXTURES/valid-proposal-change.yaml" \
  --registry "$mutated_content_registry"
run_case proposal-derived-change-time-forgery-is-rejected 1 invalid "SGP_EVENT_TIME_ORDER,SGP_CHANGE_APPLIED_TIME_ORDER" \
  --kind change --input "$tmp/time-forged-change.yaml" \
  --registry "$proposal_change_registry"
run_case approved-proposal-requires-event-history 1 invalid "SGP_EVENT_REQUIRED" \
  --kind proposal --input "$tmp/approved-without-events.yaml"
run_case registry-global-uniqueness-and-collisions 1 invalid \
  "SGK_DUPLICATE_GLOSSARY,SGK_DUPLICATE,SGK_ALLOWED_FORM_COLLISION,SGK_FORBIDDEN_FORM_COLLISION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$tmp/registry-collision"

run_case registry-glossary-schema-is-validated 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-invalid-glossary-version.yaml"
run_case registry-proposal-schema-is-validated 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-invalid-proposal.yaml"
run_case registry-change-schema-is-validated 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-invalid-change.yaml"
run_case registry-glossary-missing-terms-is-not-ignored 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-glossary-missing-terms.yaml"
run_case registry-proposal-missing-key-is-not-ignored 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-proposal-missing-proposal-key.yaml"
run_case registry-change-missing-key-is-not-ignored 1 invalid "SGS_SCHEMA_VIOLATION" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-change-missing-change-key.yaml"
run_case ambiguous-semantic-registry-is-unavailable 2 unavailable "SGD_PARSE" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-ambiguous-semantic.yaml"
run_case nonsemantic-registry-yaml-is-ignored 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-nonsemantic-config.yaml"
run_case nonsemantic-list-registry-yaml-is-ignored 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-nonsemantic-list.yaml"
run_case nonsemantic-scalar-registry-yaml-is-ignored 0 valid "" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-nonsemantic-scalar.yaml"
run_case malformed-registry-yaml-remains-unavailable 2 unavailable "SGD_PARSE" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-malformed.yaml"
run_case multi-document-registry-yaml-remains-unavailable 2 unavailable "SGD_PARSE" \
  --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$FIXTURES/registry-multiple-documents.yaml"
run_case list-input-still-requires-object-root 2 unavailable "SGD_PARSE" \
  --kind glossary --input "$FIXTURES/registry-nonsemantic-list.yaml"

duplicate_merge_registry="$tmp/duplicate-merge-registry"
mkdir -p "$duplicate_merge_registry"
cp "$FIXTURES/valid-glossary.yaml" "$duplicate_merge_registry/glossary.yaml"
cp "$FIXTURES/registry-duplicate-merge-proposal.yaml" "$duplicate_merge_registry/proposal.yaml"
run_case duplicate-proposal-merge-key-is-rejected 1 invalid "SGP_DUPLICATE_MERGE_KEY" \
  --kind proposal --input "$FIXTURES/valid-proposal.yaml" \
  --registry "$duplicate_merge_registry"

duplicate_change_registry="$tmp/duplicate-change-registry"
mkdir -p "$duplicate_change_registry"
cp "$FIXTURES/valid-glossary.yaml" "$duplicate_change_registry/glossary.yaml"
cp "$FIXTURES/registry-duplicate-change.yaml" "$duplicate_change_registry/change.yaml"
run_case duplicate-change-key-is-rejected 1 invalid "SGK_DUPLICATE_CHANGE_KEY" \
  --kind change --input "$FIXTURES/valid-registry-change.yaml" \
  --registry "$duplicate_change_registry"

cross_kind_registry="$tmp/cross-kind-operation-registry"
mkdir -p "$cross_kind_registry"
cp "$FIXTURES/valid-glossary.yaml" "$cross_kind_registry/glossary.yaml"
cp "$FIXTURES/registry-cross-kind-operation-proposal.yaml" "$cross_kind_registry/proposal.yaml"
run_case cross-kind-operation-key-is-rejected 1 invalid "SGK_DUPLICATE_OPERATION_KEY" \
  --kind change --input "$FIXTURES/valid-change.yaml" \
  --registry "$cross_kind_registry"

same_path="$tmp/input-and-report.yaml"
same_path_before="$tmp/input-and-report.before.yaml"
cp "$FIXTURES/valid-glossary.yaml" "$same_path"
cp "$same_path" "$same_path_before"
same_path_exit=0
set +e
"$VALIDATOR" --kind glossary --input "$same_path" --report "$same_path" \
  >"$tmp/same-path.stdout" 2>"$tmp/same-path.stderr"
same_path_exit=$?
set -e
if [ "$same_path_exit" -ne 2 ]; then
  echo "FAIL: same input/report path expected exit 2, got $same_path_exit" >&2
  exit 1
fi
if ! cmp -s "$same_path" "$same_path_before"; then
  echo "FAIL: validator modified input when --report resolved to the same path" >&2
  exit 1
fi
echo "PASS: same input/report path is rejected without input mutation"
passed=$((passed + 1))

hardlink_input="$tmp/hardlink-input.yaml"
hardlink_report="$tmp/hardlink-report.yaml"
cp "$FIXTURES/valid-glossary.yaml" "$hardlink_input"
ln "$hardlink_input" "$hardlink_report"
hardlink_exit=0
set +e
"$VALIDATOR" --kind glossary --input "$hardlink_input" --report "$hardlink_report" \
  >"$tmp/hardlink.stdout" 2>"$tmp/hardlink.stderr"
hardlink_exit=$?
set -e
if [ "$hardlink_exit" -ne 2 ]; then
  echo "FAIL: hard-linked input/report expected exit 2, got $hardlink_exit" >&2
  exit 1
fi
echo "PASS: hard-linked input/report paths are rejected"
passed=$((passed + 1))

report_registry="$tmp/report-registry"
mkdir -p "$report_registry"
cp "$FIXTURES/valid-glossary.yaml" "$report_registry/glossary.yaml"
cp "$FIXTURES/valid-proposal.yaml" "$report_registry/proposal.yaml"
cp "$report_registry/glossary.yaml" "$tmp/report-registry-glossary.before"
cp "$report_registry/proposal.yaml" "$tmp/report-registry-proposal.before"
registry_report_exit=0
set +e
"$VALIDATOR" --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$report_registry" --report "$report_registry/glossary.yaml" \
  >"$tmp/report-registry.stdout" 2>"$tmp/report-registry.stderr"
registry_report_exit=$?
set -e
if [ "$registry_report_exit" -ne 2 ]; then
  echo "FAIL: report targeting registry source expected exit 2, got $registry_report_exit" >&2
  exit 1
fi
if ! cmp -s "$report_registry/glossary.yaml" "$tmp/report-registry-glossary.before" \
  || ! cmp -s "$report_registry/proposal.yaml" "$tmp/report-registry-proposal.before"; then
  echo "FAIL: validator modified registry bytes when report targeted a source file" >&2
  exit 1
fi
echo "PASS: report cannot target a registry source file"
passed=$((passed + 1))

hardlink_registry="$tmp/hardlink-registry.yaml"
hardlink_registry_report="$tmp/hardlink-registry-report.json"
cp "$FIXTURES/valid-glossary.yaml" "$hardlink_registry"
ln "$hardlink_registry" "$hardlink_registry_report"
hardlink_registry_exit=0
set +e
"$VALIDATOR" --kind glossary --input "$FIXTURES/valid-empty-glossary.yaml" \
  --registry "$hardlink_registry" --report "$hardlink_registry_report" \
  >"$tmp/hardlink-registry.stdout" 2>"$tmp/hardlink-registry.stderr"
hardlink_registry_exit=$?
set -e
if [ "$hardlink_registry_exit" -ne 2 ]; then
  echo "FAIL: report hard-linked to registry source expected exit 2, got $hardlink_registry_exit" >&2
  exit 1
fi
echo "PASS: hard-linked registry report path is rejected"
passed=$((passed + 1))

cp "$FIXTURES/valid-glossary.yaml" "$tmp/registry-copy.yaml"
run_case duplicate-across-registry 1 invalid "SGK_DUPLICATE" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml" \
  --registry "$tmp/registry-copy.yaml"
run_case missing-input-is-unavailable 2 unavailable "SGD_SCAN_UNAVAILABLE" \
  --kind glossary --input "$tmp/missing.yaml"
run_case unscannable-registry-is-unavailable 2 unavailable "SGD_SCAN_UNAVAILABLE" \
  --kind glossary --input "$FIXTURES/valid-glossary.yaml" \
  --registry "$tmp/missing-registry"

printf '%s\n' 'schema_version: [' >"$tmp/malformed.yaml"
run_case parse-error-is-unavailable 2 unavailable "SGD_PARSE" \
  --kind glossary --input "$tmp/malformed.yaml"

dependency_report="$tmp/dependency.json"
dependency_exit=0
set +e
"$PYTHON" -S "$VALIDATOR_PY" --kind glossary \
  --input "$FIXTURES/valid-glossary.yaml" --report "$dependency_report" \
  >"$tmp/dependency.stdout" 2>"$tmp/dependency.stderr"
dependency_exit=$?
set -e
if [ "$dependency_exit" -ne 2 ]; then
  echo "FAIL: dependency failure expected exit 2, got $dependency_exit" >&2
  exit 1
fi
assert_report "$dependency_report" unavailable "SGD_DEPENDENCY"
echo "PASS: dependency failure is unavailable"
passed=$((passed + 1))

usage_exit=0
set +e
"$VALIDATOR" >"$tmp/usage.stdout" 2>"$tmp/usage.stderr"
usage_exit=$?
set -e
if [ "$usage_exit" -ne 2 ]; then
  echo "FAIL: usage failure expected exit 2, got $usage_exit" >&2
  exit 1
fi
echo "PASS: usage failure exits 2"
passed=$((passed + 1))

echo "PASS: semantic glossary validator ($passed cases)"
