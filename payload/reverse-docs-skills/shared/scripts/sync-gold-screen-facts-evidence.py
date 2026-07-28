#!/usr/bin/env python3
"""Upgrade the retained screen gold facts to range/SHA/excerpt evidence mappings."""
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
FACTS = ROOT / "shared/references/gold-standard/docs/facts.yml"
SOURCE_ROOT = ROOT / "shared/references/gold-standard/original"
SOURCE_IDENTITY = "../original"
OLD = re.compile(r"^(.+):([1-9][0-9]*)(?:-([1-9][0-9]*))?$")


def load():
    result = subprocess.run(
        ["ruby", str(ROOT / "shared/scripts/yaml-to-json.rb")],
        input=FACTS.read_text(), text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


def upgrade(value):
    if isinstance(value, dict):
        return value
    match = OLD.fullmatch(value)
    if not match:
        raise ValueError(f"old evidence is not a line or range: {value}")
    path = match.group(1)
    start = int(match.group(2))
    end = int(match.group(3) or start)
    source = SOURCE_ROOT / path
    raw = source.read_bytes()
    lines = raw.decode().splitlines()
    return {
        "path": path,
        "line_start": start,
        "line_end": end,
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "excerpt": "\n".join(lines[start - 1:end]),
    }


def align_with_key(evidence, key):
    source = SOURCE_ROOT / evidence["path"]
    lines = source.read_text().splitlines()
    excerpt = evidence["excerpt"].lower()
    tokens = [
        token for token in re.split(r"[-_.:/]+", key)
        if len(token) >= 3
    ]
    if any(token.lower() in excerpt for token in tokens):
        return evidence
    candidates = [
        (abs(index - evidence["line_start"]), index, line)
        for index, line in enumerate(lines, 1)
        if any(token.lower() in line.lower() for token in tokens)
    ]
    if not candidates:
        return evidence
    _, line_number, line = min(candidates)
    evidence.update(line_start=line_number, line_end=line_number, excerpt=line)
    return evidence


def with_observed_span(evidence, value):
    excerpt = " ".join(evidence["excerpt"].split())
    normalized_value = " ".join(value.split())
    if normalized_value not in excerpt:
        normalized_value = excerpt
    start = excerpt.index(normalized_value)
    evidence["observed_start"] = start
    evidence["observed_end"] = start + len(normalized_value)
    return evidence, normalized_value


def main():
    data = load()
    data["schema_version"] = 1
    data["unit_kind"] = "screen"
    data["unit_id"] = "item-list"
    data["target_repo_path"] = SOURCE_IDENTITY
    data["meta"]["source_repo"] = SOURCE_IDENTITY
    # The retained route value first occurs in executable navigation at line 101.
    route_evidence, route_value = with_observed_span(
        upgrade("ItemListPage.tsx:101"), data["meta"]["route"]["value"]
    )
    data["meta"]["route"]["evidence"] = route_evidence
    data["meta"]["route"]["value"] = route_value
    for section in data["sections"].values():
        for item in section["items"]:
            item["evidence"] = align_with_key(upgrade(item["evidence"]), item["key"])
            if "value" in item:
                item["evidence"], item["value"] = with_observed_span(
                    item["evidence"], item["value"]
                )
    ordered = {
        key: data[key]
        for key in (
            "schema_version", "run_id", "profile", "unit_kind", "unit_id",
            "target_repo_path", "target_file_paths", "meta", "sections",
        )
    }
    import importlib.util
    validator_path = ROOT / "shared/scripts/validate-facts-schema.py"
    spec = importlib.util.spec_from_file_location("facts_validator", validator_path)
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    ordered["meta"]["source_ref"] = validator.source_ref_digest(ordered, SOURCE_ROOT.resolve())
    # JSON is a valid YAML subset and preserves multiline excerpts without an
    # indentation-sensitive custom serializer.
    FACTS.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
