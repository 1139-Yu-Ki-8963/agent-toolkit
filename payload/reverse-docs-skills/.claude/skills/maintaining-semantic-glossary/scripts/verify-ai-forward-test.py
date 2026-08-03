#!/usr/bin/env python3
"""Replay executable CLI evidence and check separately labelled Skill contracts."""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

import jsonschema


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_ref(repo_root: pathlib.Path, value: str) -> pathlib.Path:
    ref = pathlib.PurePosixPath(value)
    assert not ref.is_absolute() and ".." not in ref.parts
    path = repo_root / ref
    assert path.is_file(), path
    return path


def scenario_map(record: dict[str, Any]) -> dict[str, dict[str, Any]]:
    scenarios = {item["id"]: item for item in record["scenarios"]}
    assert len(scenarios) == len(record["scenarios"])
    return scenarios


def assert_fixture_set(
    scenario: dict[str, Any], repo_root: pathlib.Path, expected_refs: set[str]
) -> dict[str, pathlib.Path]:
    fixtures = {item["ref"]: item for item in scenario["inputFixtures"]}
    assert set(fixtures) == expected_refs
    paths: dict[str, pathlib.Path] = {}
    for ref, fixture in fixtures.items():
        path = checked_ref(repo_root, ref)
        actual = sha256(path)
        assert fixture["sha256Before"] == actual
        assert fixture["sha256After"] == actual
        paths[ref] = path
    return paths


def run_validator(
    validator: pathlib.Path,
    input_path: pathlib.Path,
    report_path: pathlib.Path,
    registry_path: pathlib.Path | None = None,
) -> tuple[int, str, dict[str, int]]:
    command = [str(validator), "--kind", "proposal", "--input", str(input_path)]
    if registry_path is not None:
        command.extend(["--registry", str(registry_path)])
    command.extend(["--report", str(report_path)])
    result = subprocess.run(command, cwd=validator.parents[3], capture_output=True, text=True)
    assert report_path.is_file(), result.stderr
    report = json.loads(report_path.read_text(encoding="utf-8"))
    return result.returncode, report["status"], report["counts"]


def assert_observed(
    scenario: dict[str, Any], actual: tuple[int | None, str | None, dict[str, int] | None]
) -> None:
    observed = scenario["observed"]
    assert observed["validatorExit"] == actual[0]
    assert observed["validatorStatus"] == actual[1]
    assert observed["counts"] == actual[2]


def assert_artifact(
    scenario: dict[str, Any], repo_root: pathlib.Path, skill_name: str
) -> pathlib.Path | None:
    artifact = scenario["artifact"]
    expected = scenario["expected"]["artifactExpectation"]
    assert artifact["expectation"] == expected
    if expected == "absent":
        assert artifact["ref"] is None and artifact["sha256"] is None
        return None
    path = checked_ref(repo_root, artifact["ref"])
    assert artifact["ref"].startswith(f".claude/skills/{skill_name}/verification/")
    assert artifact["sha256"] == sha256(path)
    return path


record_path, schema_path, repo_root_arg = map(pathlib.Path, sys.argv[1:])
repo_root = repo_root_arg.resolve()
record_text = record_path.read_text(encoding="utf-8")
record = json.loads(record_text)
schema = json.loads(schema_path.read_text(encoding="utf-8"))
jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker()).validate(record)

skill_name = "maintaining-semantic-glossary"
expected = {
    "registry-dry-run-change-request": (
        "review_required",
        "human_review_and_impact_scan_required",
        "generated",
        "cli_and_contract",
    ),
    "registry-omitted": ("review_required", "registry_required", "absent", "cli_and_contract"),
    "single-approval": ("invalid", "two_party_approval_required", "absent", "cli_and_contract"),
    "ai-index-stop": ("review_required", "not_implemented", "absent", "contract_only"),
}
assert record["skill"] == skill_name
scenarios = scenario_map(record)
assert set(scenarios) == set(expected)
assert "/Users/" not in record_text

for scenario_id, scenario in scenarios.items():
    expected_status, expected_reason, expected_artifact, evidence_mode = expected[scenario_id]
    assert scenario["evidenceMode"] == evidence_mode
    assert scenario["expected"]["skillStatus"] == expected_status
    assert scenario["expected"]["reason"] == expected_reason
    assert scenario["expected"]["artifactExpectation"] == expected_artifact
    assert scenario["observed"]["skillStatus"] == expected_status
    assert scenario["observed"]["reason"] == expected_reason
    assert scenario["verdict"] == "PASS"

validator = repo_root / "shared/scripts/glossary/validate-semantic-glossary.sh"
skill_dir = repo_root / ".claude/skills" / skill_name
assert validator.is_file()

with tempfile.TemporaryDirectory(prefix="maintaining-semantic-glossary-forward-") as temporary:
    temp = pathlib.Path(temporary)

    scenario = scenarios["registry-dry-run-change-request"]
    paths = assert_fixture_set(
        scenario,
        repo_root,
        {
            "shared/scripts/glossary/fixtures/valid-update-proposal.yaml",
            "shared/scripts/glossary/fixtures/valid-glossary.yaml",
        },
    )
    before = {ref: sha256(path) for ref, path in paths.items()}
    assert_observed(
        scenario,
        run_validator(
            validator,
            paths["shared/scripts/glossary/fixtures/valid-update-proposal.yaml"],
            temp / "registry-dry-run-change-request-report.json",
            paths["shared/scripts/glossary/fixtures/valid-glossary.yaml"],
        ),
    )
    persisted = assert_artifact(scenario, repo_root, skill_name)
    assert persisted is not None
    request = json.loads(persisted.read_text(encoding="utf-8"))
    assert request["dryRun"] is True and request["sourceMutation"] is False
    assert request["proposalRef"] == "shared/scripts/glossary/fixtures/valid-update-proposal.yaml"
    assert request["registryRef"] == "shared/scripts/glossary/fixtures/valid-glossary.yaml"
    assert request["validation"] == {
        "exit": scenario["observed"]["validatorExit"],
        "status": scenario["observed"]["validatorStatus"],
        "counts": scenario["observed"]["counts"],
    }
    assert before == {ref: sha256(path) for ref, path in paths.items()}

    scenario = scenarios["registry-omitted"]
    paths = assert_fixture_set(
        scenario, repo_root, {"shared/scripts/glossary/fixtures/valid-proposal.yaml"}
    )
    source = paths["shared/scripts/glossary/fixtures/valid-proposal.yaml"]
    source_before = sha256(source)
    assert_observed(
        scenario,
        run_validator(validator, source, temp / "registry-omitted-report.json"),
    )
    assert sha256(source) == source_before
    assert_artifact(scenario, repo_root, skill_name)

    scenario = scenarios["single-approval"]
    paths = assert_fixture_set(
        scenario,
        repo_root,
        {
            "shared/scripts/glossary/fixtures/invalid-approved-proposal.yaml",
            "shared/scripts/glossary/fixtures/valid-glossary.yaml",
        },
    )
    before = {ref: sha256(path) for ref, path in paths.items()}
    assert_observed(
        scenario,
        run_validator(
            validator,
            paths["shared/scripts/glossary/fixtures/invalid-approved-proposal.yaml"],
            temp / "single-approval-report.json",
            paths["shared/scripts/glossary/fixtures/valid-glossary.yaml"],
        ),
    )
    assert before == {ref: sha256(path) for ref, path in paths.items()}
    assert_artifact(scenario, repo_root, skill_name)

    scenario = scenarios["ai-index-stop"]
    paths = assert_fixture_set(
        scenario, repo_root, {"shared/scripts/glossary/fixtures/valid-glossary.yaml"}
    )
    before = {ref: sha256(path) for ref, path in paths.items()}
    assert_observed(scenario, (None, None, None))
    skill_text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    assert "ai_index" in skill_text and "review_required" in skill_text and "not_implemented" in skill_text
    assert not list((skill_dir / "verification").glob("*ai*index*"))
    assert before == {ref: sha256(path) for ref, path in paths.items()}
    assert_artifact(scenario, repo_root, skill_name)

print("PASS: maintaining-semantic-glossary CLI evidence replayed and procedural contracts checked")
