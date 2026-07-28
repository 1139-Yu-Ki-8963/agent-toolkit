#!/usr/bin/env python3
"""Validate canonical non-screen unit facts against exact source evidence."""
import argparse
import hashlib
import json
import pathlib
import re
import sys

KINDS = {"api", "table", "batch", "report", "external"}
FIELDS = {
    "field", "observed_value", "source_path", "source_excerpt",
    "source_line", "source_sha256",
}
TEST_PATH_PARTS = {"test", "tests", "fixture", "fixtures", "__fixtures__"}
TEST_MARKERS = ("self-test", "self_test", "negative fixture", "test fixture")


def normalized(value):
    return " ".join(value.split())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.target_repo).resolve()
    if not root.is_dir():
        return 1
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 1
    allowed = {"status", "source_paths", "structure", "uncertainties", "unit_kind", "unit_id"}
    if not isinstance(data, dict) or set(data) != allowed:
        return 1
    if data["unit_kind"] not in KINDS:
        return 1
    if not isinstance(data["unit_id"], str) or not data["unit_id"].strip():
        return 1
    if not isinstance(data["source_paths"], list) or not isinstance(data["structure"], list):
        return 1
    if not isinstance(data["uncertainties"], list) or not all(
        isinstance(value, str) and value.strip()
        for value in data["uncertainties"]
    ):
        return 1
    if data["status"] == "STOPPED":
        return 0 if (
            data["source_paths"] == []
            and data["structure"] == []
            and data["uncertainties"]
        ) else 1
    if data["status"] != "DONE":
        return 1
    paths = data["source_paths"]
    if not isinstance(paths, list) or not paths or not isinstance(data["structure"], list) or not data["structure"]:
        return 1
    sources = {}
    for value in paths:
        relative = pathlib.PurePosixPath(value) if isinstance(value, str) else None
        if relative is None or relative.is_absolute() or TEST_PATH_PARTS.intersection(part.lower() for part in relative.parts):
            return 1
        resolved = (root / value).resolve()
        if root not in resolved.parents or not resolved.is_file():
            return 1
        try:
            raw = resolved.read_bytes()
            text = raw.decode()
        except (OSError, UnicodeDecodeError):
            return 1
        sources[value] = (text.splitlines(), hashlib.sha256(raw).hexdigest())
    cited = set()
    for item in data["structure"]:
        if not isinstance(item, dict) or set(item) != FIELDS:
            return 1
        if not all(isinstance(item[key], str) and item[key].strip() for key in FIELDS - {"source_line"}):
            return 1
        if not isinstance(item["source_line"], int) or item["source_line"] < 1:
            return 1
        value = normalized(item["observed_value"])
        if len(value) < 4 or not re.search(r"[\w\u3040-\u30ff\u3400-\u9fff]", value):
            return 1
        source = sources.get(item["source_path"])
        if source is None or item["source_sha256"] != source[1]:
            return 1
        lines = source[0]
        if item["source_line"] > len(lines):
            return 1
        excerpt = normalized(item["source_excerpt"])
        source_line = normalized(lines[item["source_line"] - 1])
        if excerpt != source_line or value != excerpt:
            return 1
        if any(marker in excerpt.lower() for marker in TEST_MARKERS):
            return 1
        cited.add(item["source_path"])
    return 0 if cited == set(paths) else 1


if __name__ == "__main__":
    raise SystemExit(main())
