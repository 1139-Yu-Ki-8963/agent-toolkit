#!/usr/bin/env python3
"""Validate one task's artifact with format- and task-specific production assertions."""
import argparse
import ast
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def validate_semantic_assertions(task_id, row, artifact, text):
    assertions = row.get("semantic_assertions")
    if not isinstance(assertions, list) or not assertions:
        return False
    seen = set()
    for assertion in assertions:
        if not isinstance(assertion, dict):
            return False
        assertion_id = assertion.get("assertion_id")
        if (
            not isinstance(assertion_id, str)
            or not assertion_id.startswith(f"{task_id}-")
            or assertion_id in seen
        ):
            return False
        seen.add(assertion_id)
        kind = assertion.get("kind")
        if kind == "required_terms":
            terms = assertion.get("terms")
            if not isinstance(terms, list) or not terms:
                return False
            if any(not isinstance(term, str) or not term or term not in text for term in terms):
                return False
        elif kind == "required_regex":
            pattern = assertion.get("pattern")
            if not isinstance(pattern, str) or re.search(pattern, text, re.M) is None:
                return False
        elif kind == "required_section":
            heading = assertion.get("heading")
            if not isinstance(heading, str) or re.search(
                rf"^#+\s+{re.escape(heading)}\s*$", text, re.M
            ) is None:
                return False
        elif kind == "companion_relation":
            companion = assertion.get("companion")
            terms = assertion.get("terms")
            if companion not in row.get("companion_paths", []):
                return False
            companion_path = ROOT / companion
            if not companion_path.is_file() or not isinstance(terms, list):
                return False
            companion_text = companion_path.read_text()
            if any(not isinstance(term, str) or term not in companion_text for term in terms):
                return False
        elif kind == "validator_outcome":
            command = assertion.get("command")
            if not isinstance(command, list) or not all(isinstance(value, str) for value in command):
                return False
            result = subprocess.run(
                [value.replace("{artifact}", str(artifact)) for value in command],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            if result.returncode != assertion.get("expected_exit", 0):
                return False
        else:
            return False
    return True


def validate_semantic_region(row, text):
    region = row.get("semantic_region")
    if not isinstance(region, dict) or set(region) != {
        "scope", "start_marker", "end_marker", "normalized_sha256",
    }:
        return False
    start_marker = region["start_marker"]
    end_marker = region["end_marker"]
    expected = region["normalized_sha256"]
    if region["scope"] != "whole_file":
        return False
    if not all(isinstance(value, str) and value for value in (start_marker, end_marker, expected)):
        return False
    if not text.startswith(start_marker) or not text.endswith(end_marker):
        return False
    normalized = "\n".join(
        line.rstrip() for line in text.replace("\r\n", "\n").split("\n")
    ).strip()
    return hashlib.sha256(normalized.encode()).hexdigest() == expected


def validate(task_id, artifact, registry_path=None):
    data = json.loads(
        pathlib.Path(
            registry_path
            or ROOT / "verification/delivery-reverse-skills/trace-contract-registry.json"
        ).read_text()
    )
    rows = {row["task_id"]: row for row in data["contracts"]}
    row = rows.get(task_id)
    if row is None:
        return False
    canonical = ROOT / row["implementation"]
    artifact = pathlib.Path(artifact)
    if not canonical.is_file() or not artifact.is_file():
        return False
    raw = artifact.read_bytes()
    if len(raw) < row["min_bytes"] or len(raw) > canonical.stat().st_size + 512:
        return False
    try:
        text = raw.decode()
    except UnicodeDecodeError:
        return False
    if any(anchor not in text for anchor in row["anchors"]):
        return False
    if not validate_semantic_assertions(task_id, row, artifact, text):
        return False
    if not validate_semantic_region(row, text):
        return False
    suffix = artifact.suffix.lower()
    if suffix == ".py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return False
        if not any(isinstance(node, ast.FunctionDef) and node.name == "main" for node in ast.walk(tree)):
            return False
    elif suffix in {".json", ".yml"} and text.lstrip().startswith(("{", "[")):
        try:
            if json.loads(text) is None:
                return False
        except json.JSONDecodeError:
            return False
    elif artifact.name == "SKILL.md":
        declared = re.search(r"^name:\s*(\S+)\s*$", text, re.M)
        if (
            not text.startswith("---\n") or declared is None
            or declared.group(1) != canonical.parent.name
            or not re.search(r"^##\s+\S+", text, re.M)
            or not any(token in text for token in ("停止", "STOPPED", "中断"))
        ):
            return False
    elif suffix == ".html":
        if "<html" not in text.lower() or "</html>" not in text.lower():
            return False
    elif suffix == ".md":
        if not re.search(r"^#\s+\S+", text, re.M):
            return False
    if any(not (ROOT / path).is_file() for path in row["companion_paths"]):
        return False
    # Semantic pairing for the two historically ambiguous mappings.
    if task_id == "T31" and "security" not in text:
        return False
    if task_id == "T36" and "release" not in text.lower() and "リリース" not in text:
        return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", required=True)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--registry")
    args = parser.parse_args()
    try:
        passed = validate(args.task, args.artifact, args.registry)
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        passed = False
    if not passed:
        return 1
    print(f"PASS: {args.task} task-specific artifact contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
