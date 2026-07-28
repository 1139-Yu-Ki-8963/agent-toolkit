#!/usr/bin/env python3
"""Synchronize the manually selected semantic fingerprint of every task."""
import json
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "verification/delivery-reverse-skills/trace-contract-registry.json"
TRACE = ROOT / "verification/delivery-reverse-skills/task-traceability.json"

# Explicit by design: these are reviewed task meanings, not filename-derived anchors.
TERMS = {
    "T01": ["owner_contract_defaults", "failure_return_to"],
    "T02": ["schema_version", "classification"],
    "T03": ["stop_conditions", "failure_return_to"],
    "T04": ["template-only", "structure"],
    "T05": ["delivery-reverse", "manifest"],
    "T06": ["common-only", "common_docs_root"],
    "T07": ["coding", "STOPPED"],
    "T08": ["naming", "STOPPED"],
    "T09": ["placement", "directory"],
    "T10": ["architecture", "STOPPED"],
    "T11": ["observation_count", "evidence"],
    "T12": ["observed_practices", "approved_norms"],
    "T13": ["NORMATIVE_MARKER", "rule_md_generated"],
    "T14": ["README", "source_sha256"],
    "T15": ["manifest", "dedupe"],
    "T16": ["category", "agent-operation"],
    "T17": ["category", "safety"],
    "T18": ["category", "development-flow"],
    "T19": ["category", "tool-execution"],
    "T20": ["category", "environment"],
    "T21": ["category", "communication"],
    "T22": ["category", "session"],
    "T23": ["category", "ai-configuration"],
    "T24": ["category", "git"],
    "T25": ["category", "placement"],
    "T26": ["category", "naming"],
    "T27": ["category", "architecture"],
    "T28": ["category", "coding"],
    "T29": ["category", "testing"],
    "T30": ["category", "review"],
    "T31": ["security", "delivery", "documentation", "portal", "routines"],
    "T32": ["NORMATIVE_MARKER", "approved_norms"],
    "T33": ["package.json", "stack"],
    "T34": ["guide", "env-config.json"],
    "T35": ["glossary", "detail-pages"],
    "T36": ["git", "release-notes"],
    "T37": ["facts", "output_dir"],
    "T38": ["screen-list", "api-list", "table-list"],
    "T39": ["owner_contract_defaults", "feature-list"],
    "T40": ["owner_contract_defaults", "screen-transition"],
    "T41": ["owner_contract_defaults", "traceability-matrix"],
    "T42": ["owner_contract_defaults", "design-system"],
    "T43": ["orchestration", "TaskCreate"],
    "T44": ["effective_contract_fields", "failure_return_to"],
    "T45": ["check-test-case-list-evidence.py", "check-static-delivery-state.py"],
    "T46": ["fixtures", "evidence"],
    "T47": ["validate-skill-surfaces.py", "scripts"],
    "T48": ["PUBLISH_STATUSES", "unimplemented"],
}


def main():
    if set(TERMS) != {f"T{i:02d}" for i in range(1, 49)}:
        return 1
    registry = json.loads(REGISTRY.read_text())
    trace = json.loads(TRACE.read_text())
    for row in registry["contracts"]:
        task_id = row["task_id"]
        row["semantic_assertions"] = [{
            "assertion_id": f"{task_id}-semantic-fingerprint",
            "kind": "required_terms",
            "terms": TERMS[task_id],
        }]
        text = (ROOT / row["implementation"]).read_text()
        start_marker = text[: min(48, len(text))]
        end_marker = text[max(0, len(text) - 48):]
        normalized = "\n".join(
            line.rstrip() for line in text.replace("\r\n", "\n").split("\n")
        ).strip()
        row["semantic_region"] = {
            "scope": "whole_file",
            "start_marker": start_marker,
            "end_marker": end_marker,
            "normalized_sha256": hashlib.sha256(normalized.encode()).hexdigest(),
        }
    by_id = {row["task_id"]: row for row in registry["contracts"]}
    for row in trace["tasks"]:
        row["semantic_assertions"] = by_id[row["task_id"]]["semantic_assertions"]
        row["semantic_region"] = by_id[row["task_id"]]["semantic_region"]
    REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n")
    TRACE.write_text(json.dumps(trace, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
