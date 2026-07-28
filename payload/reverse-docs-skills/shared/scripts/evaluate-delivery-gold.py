#!/usr/bin/env python3
"""Evaluate gold fixtures by content and execute the real evidence validators."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import tempfile

REPOSITORY = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY / "shared/scripts"
INVENTORY_KINDS = ("screen", "api", "table", "batch", "report", "external")
COVERAGE_MATRIX = [
    {
        "claim": "inventory-owner-results",
        "generated_by": "shared/scripts/generate-delivery-inventory.py",
        "validated_by": "exact expected inventory_owner_results comparison",
        "decision_source": "fixture source files",
    },
    {
        "claim": "unit-artifacts",
        "generated_by": "shared/scripts/generate-unit-designs.py",
        "validated_by": "shared/scripts/check-unit-design-evidence.py + exact artifact SHA-256",
        "decision_source": "unit_records",
    },
    {
        "claim": "test-case-stop",
        "generated_by": "shared/scripts/generate-test-case-list.py",
        "validated_by": "shared/scripts/check-test-case-list-evidence.py",
        "decision_source": "explicit STOPPED zero-case fixture",
    },
]


def run_validator(name, args, payload):
    command = ["python3", str(SCRIPTS / name), *args]
    return subprocess.run(
        command,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    ).returncode == 0


def source_files(root):
    return [
        path for path in root.iterdir()
        if path.is_file() and path.name != "expected-deliverables.json"
    ]


def derive(root):
    generate, skip = set(), set()
    contents = {}
    for path in source_files(root):
        try:
            contents[path] = path.read_text()
        except UnicodeDecodeError:
            continue
    if any(
        path.suffix == ".json"
        and isinstance((parsed := json.loads(text)), dict)
        and "react" in parsed.get("dependencies", {})
        for path, text in contents.items()
    ):
        generate |= {"screen-list", "component-inventory"}
        skip |= {"table-list", "batch-list"}
    if any("@app.get(" in text or "@app.post(" in text for text in contents.values()):
        generate.add("api-list")
        skip |= {"screen-list", "table-list"}
    if any(
        path.suffix == ".py" and "def run(" in text
        for path, text in contents.items()
    ):
        generate.add("batch-list")
    if any(path.suffix == ".sql" and "create table " in text.lower() for path, text in contents.items()):
        generate |= {"table-list", "er-diagram"}
        skip |= {"screen-list", "batch-list"}
    return generate, skip, {"coding-rules", "test-cases"}, contents


def exercise_inventory_owners(root, expected):
    actual = {}
    for kind in INVENTORY_KINDS:
        result = subprocess.run(
            [
                "python3", str(SCRIPTS / "generate-delivery-inventory.py"),
                "--target-repo", str(root), "--unit-kind", kind,
            ],
            capture_output=True, text=True, check=False,
        )
        if result.returncode:
            return False
        try:
            actual[kind] = json.loads(result.stdout)
        except json.JSONDecodeError:
            return False
    return actual == expected.get("inventory_owner_results")


def exercise_rule_pipeline(root, contents):
    path, text = next(iter(contents.items()))
    relative = path.relative_to(root).as_posix()
    excerpt = next(line for line in text.splitlines() if line.strip())
    source_sha = hashlib.sha256(path.read_bytes()).hexdigest()
    survey = {
        "records": [{
            "id": "gold-observation",
            "evidence_path": relative,
            "excerpt": excerpt,
            "evidence_kind": "observed_practice",
            "source_sha256": source_sha,
        }]
    }
    classification = {
        "records": [{
            **survey["records"][0],
            "primary_category": "coding",
            "layer_or_kind": "fixture",
            "dedupe_key": "gold-observation",
            "references": [],
        }]
    }
    rule = {
        "observed_practices": [{
            "statement": excerpt,
            "evidence_path": relative,
            "excerpt": excerpt,
        }],
        "approved_norms": [],
        "evidence_paths": [relative],
        "observation_count": 1,
        "exceptions": [],
        "confidence": "high",
        "uncertainties": [],
        "rule_md_generated": False,
    }
    with tempfile.TemporaryDirectory() as temporary:
        ledger = pathlib.Path(temporary) / "survey.json"
        ledger.write_text(json.dumps(survey))
        return (
            run_validator("check-rule-reverse-evidence.py", ["--target-repo", str(root), "--mode", "survey"], survey)
            and run_validator(
                "check-rule-reverse-evidence.py",
                ["--target-repo", str(root), "--mode", "classification", "--survey-ledger", str(ledger)],
                classification,
            )
            and run_validator("check-rule-reverse-evidence.py", ["--target-repo", str(root)], rule)
        )


def detected_unit_records(root, contents):
    records = []
    for path, text in contents.items():
        relative = path.relative_to(root).as_posix()
        if "@app.get(" in text:
            records.append(("api", relative, 3, '@app.get("/health")'))
        if path.suffix == ".py" and "def run(" in text:
            records.append(("batch", relative, 1, "def run(): pass"))
        if path.suffix == ".sql" and "create table " in text.lower():
            records.append(("table", relative, 1, "create table item (id integer primary key);"))
        if "REPORT_FORMAT =" in text:
            records.append(("report", relative, 1, 'REPORT_FORMAT = "monthly-sales-csv"'))
        if "EXTERNAL_ENDPOINT =" in text:
            records.append(("external", relative, 1, 'EXTERNAL_ENDPOINT = "https://partner.invalid/orders"'))
    return records


def exercise_unit_generation(root, contents, expected, inject_extra_content=False):
    records = detected_unit_records(root, contents)
    expected_records = expected.get("unit_records")
    actual_records = [
        {"kind": kind, "source": relative, "line": source_line, "observed": observed}
        for kind, relative, source_line, observed in records
    ]
    record_key = lambda row: (
        row.get("kind"), row.get("source"), row.get("line"), row.get("observed")
    )
    if (
        not isinstance(expected_records, list)
        or sorted(actual_records, key=record_key) != sorted(expected_records, key=record_key)
    ):
        return False
    expected_artifacts = expected.get("unit_artifact_sha256")
    if not isinstance(expected_artifacts, dict):
        return False
    with tempfile.TemporaryDirectory() as temporary:
        output = pathlib.Path(temporary)
        if not records:
            stopped = {
                "status": "STOPPED", "source_paths": [], "structure": [],
                "uncertainties": ["unit evidenceなし"], "unit_kind": "api", "unit_id": "api-gold",
            }
            return (
                expected.get("unit_status") == "STOPPED"
                and expected_artifacts == {}
                and _run_unit_generator(root, output, stopped, "facts")
                and not any(output.rglob("*.md"))
            )
        if expected.get("unit_status") != "DONE":
            return False
        for kind, relative, source_line, observed in records:
            source_path = root / relative
            source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
            payload = {
                "status": "DONE",
                "source_paths": [relative],
                "structure": [{
                    "field": "observable-structure",
                    "observed_value": observed,
                    "source_path": relative,
                    "source_excerpt": observed,
                    "source_line": source_line,
                    "source_sha256": source_sha,
                }],
                "uncertainties": [],
                "unit_kind": kind,
                "unit_id": f"{kind}-gold",
            }
            if not run_validator(
                "check-unit-design-evidence.py",
                ["--target-repo", str(root)],
                payload,
            ):
                return False
            facts_path = output / "facts" / f"{kind}-gold" / "unit-facts.json"
            facts_path.parent.mkdir(parents=True, exist_ok=True)
            facts_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
            generated = subprocess.run(
                [
                    "python3", str(SCRIPTS / "generate-unit-designs.py"),
                    "--mode", "design", "--target-repo", str(root),
                    "--facts", str(facts_path), "--output-dir", str(output),
                ],
                capture_output=True, text=True, check=False,
            )
            if generated.returncode:
                return False
        artifacts = {
            path.relative_to(output).as_posix(): path
            for path in output.rglob("*.md")
        }
        if inject_extra_content and artifacts:
            first = next(iter(artifacts.values()))
            first.write_text(first.read_text() + "\n株式会社青空の架空内容\n")
        if set(artifacts) != set(expected_artifacts):
            return False
        actual_hashes = {
            path: hashlib.sha256(artifact.read_bytes()).hexdigest()
            for path, artifact in artifacts.items()
        }
        if actual_hashes != expected_artifacts:
            print(json.dumps(actual_hashes, ensure_ascii=False, indent=2))
            return False
        return all(
            isinstance(expected_sha, str)
            and len(expected_sha) == 64
            and hashlib.sha256(artifacts[path].read_bytes()).hexdigest() == expected_sha
            for path, expected_sha in expected_artifacts.items()
        )


def _run_unit_generator(root, output, payload, mode):
    facts = output / "facts" / "stopped" / "unit-facts.json"
    facts.parent.mkdir(parents=True, exist_ok=True)
    facts.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    return subprocess.run(
        [
            "python3", str(SCRIPTS / "generate-unit-designs.py"),
            "--mode", mode, "--target-repo", str(root),
            "--facts", str(facts), "--output-dir", str(output),
        ],
        capture_output=True, text=True, check=False,
    ).returncode == 0


def exercise_test_case_stop(root):
    template = REPOSITORY / "shared/templates/test-case-list.html"
    with tempfile.TemporaryDirectory() as temporary:
        output = pathlib.Path(temporary) / "test-case-list.html"
        generated = subprocess.run(
            [
                "python3", str(SCRIPTS / "generate-test-case-list.py"),
                "--template", str(template), "--output", str(output),
            ],
            input=json.dumps({"status": "STOPPED", "records": []}),
            text=True,
            capture_output=True,
            check=False,
        )
        if generated.returncode:
            return False
        return run_validator(
            "check-test-case-list-evidence.py",
            [
                "--target-repo", str(root),
                "--template", str(template),
                "--output", str(output),
            ],
            {"status": "STOPPED", "records": []},
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture")
    parser.add_argument("--inject-extra-content", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(args.fixture).resolve()
    try:
        expected = json.loads((root / "expected-deliverables.json").read_text())
        actual_generate, actual_skip, actual_stop, contents = derive(root)
    except (OSError, json.JSONDecodeError, StopIteration):
        return 1
    decisions = expected.get("fixture_decisions")
    if not isinstance(decisions, dict):
        return 1
    if actual_generate != set(decisions.get("detected", [])):
        return 1
    if actual_skip != set(decisions.get("not_detected", [])):
        return 1
    if actual_stop != set(decisions.get("stopped_checks", [])):
        return 1
    if expected.get("coverage_matrix") != COVERAGE_MATRIX:
        return 1
    if not exercise_inventory_owners(root, expected):
        return 1
    if not exercise_rule_pipeline(root, contents):
        return 1
    if not exercise_unit_generation(root, contents, expected, args.inject_extra_content):
        return 1
    if not exercise_test_case_stop(root):
        return 1
    print(f"PASS: {root.name} exercised production coverage matrix")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
