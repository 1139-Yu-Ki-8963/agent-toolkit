#!/usr/bin/env python3
"""Validate trace rows and reject a real corrupted artifact copy per task."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
TASK_IDS = tuple(f"T{index:02d}" for index in range(1, 49))
CHECKBOX = re.compile(r"^- \[([ x])\] (.+)$")


def load_inputs(trace_path=None):
    task_list = ROOT / "納品物リバーススキル実装タスクリスト.md"
    path = trace_path or ROOT / "verification/delivery-reverse-skills/task-traceability.json"
    task_items = []
    for line in task_list.read_text().splitlines():
        match = CHECKBOX.fullmatch(line)
        if match:
            task_items.append({"checked": match.group(1) == "x", "task": match.group(2)})
    return task_items, json.loads(path.read_text())


def load_registry(registry_path=None):
    path = registry_path or ROOT / "verification/delivery-reverse-skills/trace-contract-registry.json"
    data = json.loads(path.read_text())
    contracts = data.get("contracts") if isinstance(data, dict) else None
    publication_audit_task = data.get("publication_audit_task")
    if (
        set(data) != {
            "schema_version", "publication_audit_task",
            "production_validator_template", "contracts",
        }
        or data.get("schema_version") != 3
        or not isinstance(publication_audit_task, str)
        or not publication_audit_task.strip()
        or data.get("production_validator_template")
        != "python3 shared/scripts/validate-task-contract.py --task {task_id} --artifact {artifact}"
        or not isinstance(contracts, list)
    ):
        raise ValueError("invalid registry")
    return contracts, data["production_validator_template"], publication_audit_task


def validate_task_partition(task_items, data, publication_audit_task):
    rows = data.get("tasks") if isinstance(data, dict) else None
    if not isinstance(rows, list):
        return False
    labels = [item.get("task") for item in task_items if isinstance(item, dict)]
    if (
        len(task_items) != len(rows) + 1
        or len(labels) != len(task_items)
        or len(labels) != len(set(labels))
        or any(item.get("checked") is not True for item in task_items)
        or labels.count(publication_audit_task) != 1
    ):
        return False
    trace_labels = [label for label in labels if label != publication_audit_task]
    row_labels = [row.get("task") for row in rows]
    return publication_audit_task not in row_labels and trace_labels == row_labels


def validate(expected_tasks, data, artifact_overrides=None, registry_path=None):
    artifact_overrides = artifact_overrides or {}
    try:
        contracts, validator_template, publication_audit_task = load_registry(registry_path)
    except (OSError, json.JSONDecodeError, ValueError):
        return False
    if len(contracts) != 48 or [row.get("task_id") for row in contracts] != list(TASK_IDS):
        return False
    if len({row.get("contract_id") for row in contracts}) != 48:
        return False
    if len({row.get("property") for row in contracts}) != 48:
        return False
    semantic_ids = set()
    semantic_fingerprints = set()
    for contract in contracts:
        anchors = contract.get("anchors")
        assertions = contract.get("semantic_assertions")
        region = contract.get("semantic_region")
        if (
            not isinstance(anchors, list)
            or len(anchors) < 2
            or len(set(anchors)) != len(anchors)
            or not all(isinstance(value, str) and value.strip() for value in anchors)
            or not isinstance(contract.get("min_bytes"), int)
            or contract["min_bytes"] < 100
            or not isinstance(contract.get("companion_paths"), list)
            or not contract["companion_paths"]
            or not isinstance(assertions, list)
            or not assertions
            or not isinstance(region, dict)
            or set(region) != {"scope", "start_marker", "end_marker", "normalized_sha256"}
            or region.get("scope") != "whole_file"
        ):
            return False
        for assertion in assertions:
            assertion_id = assertion.get("assertion_id") if isinstance(assertion, dict) else None
            if not isinstance(assertion_id, str) or assertion_id in semantic_ids:
                return False
            semantic_ids.add(assertion_id)
        fingerprint = json.dumps(
            [
                {key: value for key, value in assertion.items() if key != "assertion_id"}
                for assertion in assertions
            ],
            ensure_ascii=False,
            sort_keys=True,
        )
        if fingerprint in semantic_fingerprints:
            return False
        semantic_fingerprints.add(fingerprint)
    registry = {row["task_id"]: row for row in contracts}
    rows = data.get("tasks") if isinstance(data, dict) else None
    if data.get("task_count") != 48:
        return False
    if not isinstance(rows, list) or len(rows) != 48:
        return False
    if not validate_task_partition(expected_tasks, data, publication_audit_task):
        return False
    if [row.get("task_id") for row in rows] != list(TASK_IDS):
        return False
    for row in rows:
        task_id = row["task_id"]
        contract = registry[task_id]
        task_sha = hashlib.sha256(row["task"].encode()).hexdigest()
        if row.get("task_sha256") != task_sha or contract.get("task_sha256") != task_sha:
            return False
        if contract.get("task_text") != row["task"]:
            return False
        for field in (
            "contract_id", "implementation", "anchors", "min_bytes",
            "companion_paths", "property",
            "semantic_assertions",
            "semantic_region",
        ):
            if row.get(field) != contract.get(field):
                return False
        command = f"python3 shared/scripts/validate-delivery-traceability.py --probe {task_id}"
        if row.get("negative_test") != command or contract.get("production_probe") != command:
            return False
        implementation = pathlib.Path(row["implementation"])
        path = pathlib.Path(artifact_overrides.get(task_id, ROOT / implementation))
        if not path.is_file():
            return False
        if path.stat().st_size < row["min_bytes"]:
            return False
        if (
            task_id not in artifact_overrides
            and hashlib.sha256(path.read_bytes()).hexdigest() != row.get("evidence_sha256")
        ):
            return False
        try:
            content = path.read_text()
        except (OSError, UnicodeDecodeError):
            return False
        if any(anchor not in content for anchor in row["anchors"]):
            return False
        if any(not (ROOT / companion).is_file() for companion in row["companion_paths"]):
            return False
        command = validator_template.format(task_id=task_id, artifact=str(path))
        checked = subprocess.run(
            command.split(), cwd=ROOT, capture_output=True, text=True, check=False,
        )
        if checked.returncode:
            return False
    return True


def run_probe(task_id, data):
    """Mutate the task's real implementation copy and require this checker to reject it."""
    rows = data["tasks"]
    index = TASK_IDS.index(task_id)
    row = rows[index]
    source = ROOT / row["implementation"]
    if not source.is_file():
        return False
    with tempfile.TemporaryDirectory() as temporary:
        temp = pathlib.Path(temporary)
        corrupted_asset = temp / f"{task_id}-{source.name}"
        shutil.copy2(source, corrupted_asset)
        content = corrupted_asset.read_text()
        region = row["semantic_region"]
        if not content.startswith(region["start_marker"]) or not content.endswith(region["end_marker"]):
            return False
        region_text = content
        if task_id == "T07":
            if "python3" not in region_text:
                return False
            mutated_region = region_text.replace("python3", "python4", 1)
        elif task_id == "T33" and "package.json" in region_text:
            mutated_region = region_text.replace("package.json", "shopping.txt", 1)
        else:
            protected = len(region["start_marker"])
            match = next(
                (index for index, char in enumerate(region_text[protected:], protected)
                 if char.isascii() and char.isalpha()),
                None,
            )
            if match is None:
                return False
            char = region_text[match]
            mutated_region = region_text[:match] + (
                "Z" if char != "Z" else "Y"
            ) + region_text[match + 1:]
        if len(mutated_region.encode()) != len(region_text.encode()):
            return False
        corrupted_asset.write_text(mutated_region)
        candidate_path = temp / f"trace-{task_id}.json"
        candidate_path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        result = subprocess.run(
            [
                sys.executable,
                str(pathlib.Path(__file__).resolve()),
                "--trace-file",
                str(candidate_path),
                "--check-only",
                "--artifact-override",
                f"{task_id}={corrupted_asset}",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode != 0


def rejects_t07_path_substitution(data):
    with tempfile.TemporaryDirectory() as temporary:
        candidate = json.loads(json.dumps(data))
        row = candidate["tasks"][TASK_IDS.index("T07")]
        replacement = ROOT / "README.md"
        row["implementation"] = "README.md"
        row["evidence_sha256"] = hashlib.sha256(replacement.read_bytes()).hexdigest()
        path = pathlib.Path(temporary) / "trace-t07-path.json"
        path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2))
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).resolve()),
             "--trace-file", str(path), "--check-only"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        return result.returncode != 0


def rejects_one_line_anchor_stub(data):
    with tempfile.TemporaryDirectory() as temporary:
        task_id = "T07"
        row = data["tasks"][TASK_IDS.index(task_id)]
        stub = pathlib.Path(temporary) / "stub.md"
        stub.write_text(" ".join(row["anchors"]))
        candidate = pathlib.Path(temporary) / "trace-one-line.json"
        candidate.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        result = subprocess.run(
            [
                sys.executable, str(pathlib.Path(__file__).resolve()),
                "--trace-file", str(candidate), "--check-only",
                "--artifact-override", f"{task_id}={stub}",
            ],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        return result.returncode != 0


def rejects_t07_anchor_garbage(data):
    with tempfile.TemporaryDirectory() as temporary:
        row = data["tasks"][TASK_IDS.index("T07")]
        source = ROOT / row["implementation"]
        garbage = pathlib.Path(temporary) / "SKILL.md"
        garbage.write_text(source.read_text() + "\n" + ("unrelated-garbage\n" * 400))
        candidate = pathlib.Path(temporary) / "trace-t07-garbage.json"
        candidate.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        result = subprocess.run(
            [
                sys.executable, str(pathlib.Path(__file__).resolve()),
                "--trace-file", str(candidate), "--check-only",
                "--artifact-override", f"T07={garbage}",
            ],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        return result.returncode != 0


def rejects_missing_semantic_assertions(data):
    with tempfile.TemporaryDirectory() as temporary:
        contracts, validator_template, publication_audit_task = load_registry()
        registry = {
            "schema_version": 3,
            "publication_audit_task": publication_audit_task,
            "production_validator_template": validator_template,
            "contracts": json.loads(json.dumps(contracts)),
        }
        registry["contracts"][0].pop("semantic_assertions", None)
        candidate = pathlib.Path(temporary) / "registry.json"
        candidate.write_text(json.dumps(registry))
        row = data["tasks"][0]
        result = subprocess.run(
            [
                sys.executable, str(ROOT / "shared/scripts/validate-task-contract.py"),
                "--task", row["task_id"], "--artifact", str(ROOT / row["implementation"]),
                "--registry", str(candidate),
            ],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        return result.returncode != 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", choices=TASK_IDS)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--trace-file", type=pathlib.Path)
    parser.add_argument("--registry-file", type=pathlib.Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--artifact-override", action="append", default=[])
    args = parser.parse_args()
    try:
        expected, data = load_inputs(args.trace_file)
    except (OSError, json.JSONDecodeError):
        return 1
    overrides = {}
    for value in args.artifact_override:
        if "=" not in value:
            return 1
        task_id, path = value.split("=", 1)
        if task_id not in TASK_IDS or task_id in overrides:
            return 1
        overrides[task_id] = path
    if not validate(expected, data, overrides, args.registry_file):
        return 1
    if args.check_only:
        print("PASS: trace fixture")
        return 0
    if args.probe:
        if not run_probe(args.probe, data):
            return 1
        print(f"PASS: {args.probe} production checker rejected corrupted artifact copy")
        return 0
    if args.self_test:
        try:
            _, _, publication_audit_task = load_registry(args.registry_file)
        except (OSError, json.JSONDecodeError, ValueError):
            return 1
        canonical_items = json.loads(json.dumps(expected))
        publication_index = next(
            index for index, item in enumerate(canonical_items)
            if item["task"] == publication_audit_task
        )
        unchecked_publication = json.loads(json.dumps(canonical_items))
        unchecked_publication[publication_index]["checked"] = False
        unknown_checked = canonical_items + [{"checked": True, "task": "未知の公開項目"}]
        unknown_unchecked = canonical_items + [{"checked": False, "task": "未知の未完了項目"}]
        duplicate_publication = canonical_items + [{
            "checked": True, "task": publication_audit_task,
        }]
        if (
            not validate_task_partition(canonical_items, data, publication_audit_task)
            or validate_task_partition(unchecked_publication, data, publication_audit_task)
            or validate_task_partition(unknown_checked, data, publication_audit_task)
            or validate_task_partition(unknown_unchecked, data, publication_audit_task)
            or validate_task_partition(duplicate_publication, data, publication_audit_task)
            or not all(run_probe(task_id, data) for task_id in TASK_IDS)
            or not rejects_t07_path_substitution(data)
            or not rejects_one_line_anchor_stub(data)
            or not rejects_t07_anchor_garbage(data)
            or not rejects_missing_semantic_assertions(data)
        ):
            return 1
        print("PASS: 48 task-specific corrupted artifact copies rejected")
    else:
        print("PASS: 48 task traceability rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
