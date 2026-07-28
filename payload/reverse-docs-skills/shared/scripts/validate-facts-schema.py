#!/usr/bin/env python3
"""Validate the complete screen facts.yml data model before sealing or state use."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace

SECTIONS = (
    "import", "export_type", "const", "state", "handler", "jsx", "style", "api",
    "measurement_pending", "local_type", "effect_trigger", "error_handling",
)
TOP_FIELDS = {
    "schema_version", "run_id", "profile", "unit_kind", "unit_id",
    "target_repo_path", "target_file_paths", "meta", "sections",
}
ITEM_FIELDS = {"key", "value", "evidence", "call_order"}
EVIDENCE_BASE_FIELDS = {"path", "line_start", "line_end", "source_sha256", "excerpt"}
OBSERVED_SPAN_FIELDS = {"observed_start", "observed_end"}
SOURCE_REF = re.compile(r"^[0-9a-f]{40,64}$")


def load_yaml(path):
    converter = pathlib.Path(__file__).with_name("yaml-to-json.rb")
    result = subprocess.run(
        ["ruby", str(converter)], input=path.read_text(), text=True,
        capture_output=True, check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr)
    return json.loads(result.stdout)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip()) and "\x00" not in value


def normalized(value):
    return " ".join(str(value).split())


def portable_repo_identity(value):
    """Return a stable slash-separated identity without resolving host paths."""
    path = pathlib.PurePosixPath(str(value).replace("\\", "/"))
    return path.as_posix()


def resolve_repo_identity(value, facts_path):
    """Resolve absolute, fixture-relative, or repository-relative identities."""
    path = pathlib.Path(value)
    if path.is_absolute():
        return path.resolve()
    fixture_candidate = (facts_path.parent / path).resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(facts_path.parent), "rev-parse", "--show-toplevel"],
            text=True, capture_output=True, check=False,
        )
        if result.returncode == 0:
            repository_candidate = (pathlib.Path(result.stdout.strip()) / path).resolve()
            return fixture_candidate, repository_candidate
    except OSError:
        pass
    return (fixture_candidate,)


def repo_identity_matches(value, facts_path, root):
    resolved = resolve_repo_identity(value, facts_path)
    candidates = resolved if isinstance(resolved, tuple) else (resolved,)
    return root in candidates


def evidence_excerpt(evidence, root, paths, require_span):
    expected = EVIDENCE_BASE_FIELDS | (OBSERVED_SPAN_FIELDS if require_span else set())
    if not isinstance(evidence, dict) or set(evidence) != expected:
        return None
    path = evidence.get("path")
    start = evidence.get("line_start")
    end = evidence.get("line_end")
    sha = evidence.get("source_sha256")
    excerpt = evidence.get("excerpt")
    if (
        path not in paths or not isinstance(start, int) or isinstance(start, bool)
        or not isinstance(end, int) or isinstance(end, bool)
        or start < 1 or end < start or not SOURCE_REF.fullmatch(str(sha))
        or not nonempty(excerpt)
    ):
        return None
    source = (root / path).resolve()
    if root not in source.parents or not source.is_file():
        return None
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != sha:
        return None
    lines = raw.decode("utf-8").splitlines()
    if end > len(lines):
        return None
    actual = normalized("\n".join(lines[start - 1:end]))
    if actual != normalized(excerpt):
        return None
    if require_span:
        start_at = evidence.get("observed_start")
        end_at = evidence.get("observed_end")
        if (
            not isinstance(start_at, int) or isinstance(start_at, bool)
            or not isinstance(end_at, int) or isinstance(end_at, bool)
            or start_at < 0 or end_at <= start_at or end_at > len(actual)
        ):
            return None
    return actual


def key_agrees(key, excerpt):
    tokens = [token for token in re.split(r"[-_.:/]+", key) if len(token) >= 2]
    return bool(tokens) and any(normalized(token).lower() in excerpt.lower() for token in tokens)


def observed_value(evidence, excerpt):
    return excerpt[evidence["observed_start"]:evidence["observed_end"]]


def source_ref_digest(data, root):
    payload = {
        "schema_version": data["schema_version"],
        "profile": data["profile"],
        "unit_kind": data["unit_kind"],
        "target_repo": portable_repo_identity(data["target_repo_path"]),
        "unit_id": data["unit_id"],
        "target_file_paths": data["target_file_paths"],
        "route": data["meta"]["route"],
        "sections": [
            {
                "section": name,
                "reason": section["reason"],
                "items": [
                    {
                        key: item[key]
                        for key in ("key", "value", "call_order", "evidence")
                        if key in item
                    }
                    for item in section["items"]
                ],
            }
            for name, section in data["sections"].items()
        ],
    }
    encoded = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def valid(args):
    facts_path = pathlib.Path(args.facts)
    data = load_yaml(facts_path)
    if not isinstance(data, dict) or set(data) != TOP_FIELDS:
        return False
    if args.target_repo:
        root = pathlib.Path(args.target_repo).resolve()
    else:
        resolved = resolve_repo_identity(data.get("target_repo_path", ""), facts_path)
        candidates = resolved if isinstance(resolved, tuple) else (resolved,)
        existing = [candidate for candidate in candidates if candidate.is_dir()]
        if len(existing) != 1:
            return False
        root = existing[0]
    if (
        data["schema_version"] != 1
        or data["profile"] != "screen"
        or data["unit_kind"] != "screen"
        or not nonempty(data["run_id"])
        or not nonempty(data["unit_id"])
        or (args.unit_id is not None and data["unit_id"] != args.unit_id)
        or not nonempty(data["target_repo_path"])
        or not repo_identity_matches(data["target_repo_path"], facts_path, root)
    ):
        return False
    paths = data["target_file_paths"]
    if (
        not isinstance(paths, list) or not paths or len(paths) != len(set(paths))
        or not all(nonempty(value) for value in paths)
    ):
        return False
    for value in paths:
        source = (root / value).resolve()
        if root not in source.parents or not source.is_file():
            return False
    meta = data["meta"]
    if (
        not isinstance(meta, dict) or set(meta) != {"source_repo", "source_ref", "route"}
        or not nonempty(meta["source_repo"])
        or portable_repo_identity(meta["source_repo"])
        != portable_repo_identity(data["target_repo_path"])
        or not repo_identity_matches(meta["source_repo"], facts_path, root)
        or not isinstance(meta["source_ref"], str) or not SOURCE_REF.fullmatch(meta["source_ref"])
        or not isinstance(meta["route"], dict) or set(meta["route"]) != {"value", "evidence"}
        or not nonempty(meta["route"]["value"])
    ):
        return False
    route_excerpt = evidence_excerpt(meta["route"]["evidence"], root, paths, True)
    if (
        route_excerpt is None
        or normalized(meta["route"]["value"])
        != normalized(observed_value(meta["route"]["evidence"], route_excerpt))
    ):
        return False
    sections = data["sections"]
    if not isinstance(sections, dict) or tuple(sections) != SECTIONS:
        return False
    keys = set()
    for name in SECTIONS:
        section = sections[name]
        if not isinstance(section, dict) or set(section) != {"reason", "items"}:
            return False
        reason, items = section["reason"], section["items"]
        if not isinstance(reason, str) or not isinstance(items, list):
            return False
        if not items and not reason.strip():
            return False
        if items and reason.strip():
            return False
        for item in items:
            if not isinstance(item, dict) or not set(item) <= ITEM_FIELDS:
                return False
            required = {"key", "evidence"} if name == "measurement_pending" else {"key", "value", "evidence"}
            if not required <= set(item) or not nonempty(item["key"]):
                return False
            if name != "measurement_pending" and not nonempty(item["value"]):
                return False
            if name == "measurement_pending" and "value" in item:
                return False
            if item["key"] in keys:
                return False
            keys.add(item["key"])
            require_span = name != "measurement_pending"
            excerpt = evidence_excerpt(item["evidence"], root, paths, require_span)
            if excerpt is None or not key_agrees(item["key"], excerpt):
                return False
            if (
                require_span
                and normalized(item["value"])
                != normalized(observed_value(item["evidence"], excerpt))
            ):
                return False
            if "call_order" in item and (name != "handler" or not nonempty(item["call_order"])):
                return False
            if "\x00" in json.dumps(item, ensure_ascii=False):
                return False
    return meta["source_ref"] == source_ref_digest(data, root)


def self_test():
    with tempfile.TemporaryDirectory(prefix="screen-facts-schema-") as temporary:
        root = pathlib.Path(temporary)
        source = root / "a.ts"
        source.write_text('route /home\nimport-react value=react\nmethod DELETE /items\n')
        sha = hashlib.sha256(source.read_bytes()).hexdigest()

        def evidence(line, excerpt, observed):
            normalized_excerpt = normalized(excerpt)
            start_at = normalized_excerpt.index(observed)
            return {
                "path": "a.ts", "line_start": line, "line_end": line,
                "source_sha256": sha, "excerpt": excerpt,
                "observed_start": start_at, "observed_end": start_at + len(observed),
            }

        sections = {
            name: {"reason": "該当なし", "items": []}
            for name in SECTIONS
        }
        sections["import"] = {
            "reason": "",
            "items": [{
                "key": "import-react", "value": "react",
                "evidence": evidence(2, "import-react value=react", "react"),
            }],
        }
        data = {
            "schema_version": 1, "run_id": "self-test", "profile": "screen",
            "unit_kind": "screen", "unit_id": "home",
            "target_repo_path": str(root), "target_file_paths": ["a.ts"],
            "meta": {
                "source_repo": str(root), "source_ref": "",
                "route": {
                    "value": "/home",
                    "evidence": evidence(1, "route /home", "/home"),
                },
            },
            "sections": sections,
        }
        data["meta"]["source_ref"] = source_ref_digest(data, root.resolve())
        facts = root / "facts.yml"
        args = SimpleNamespace(facts=str(facts), target_repo=str(root), unit_id="home")

        def accepted(candidate):
            facts.write_text(json.dumps(candidate, ensure_ascii=False))
            return valid(args)

        if not accepted(data):
            return False
        portable = json.loads(json.dumps(data))
        portable["target_repo_path"] = "."
        portable["meta"]["source_repo"] = "."
        portable["meta"]["source_ref"] = source_ref_digest(portable, root.resolve())
        if not accepted(portable):
            return False
        wrong_portable = json.loads(json.dumps(portable))
        wrong_portable["target_repo_path"] = "../wrong"
        wrong_portable["meta"]["source_repo"] = "../wrong"
        wrong_portable["meta"]["source_ref"] = source_ref_digest(wrong_portable, root.resolve())
        if accepted(wrong_portable):
            return False
        bad_line = json.loads(json.dumps(data))
        bad_line["meta"]["route"]["evidence"]["line_start"] = 999
        bad_line["meta"]["route"]["evidence"]["line_end"] = 999
        if accepted(bad_line):
            return False
        fabricated = json.loads(json.dumps(data))
        fabricated["sections"]["import"]["items"][0]["value"] = "react FABRICATED"
        if accepted(fabricated):
            return False
        fake_ref = json.loads(json.dumps(data))
        fake_ref["meta"]["source_ref"] = "f" * 40
        if accepted(fake_ref):
            return False
        moved = json.loads(json.dumps(data))
        moved_item = moved["sections"]["import"]["items"].pop()
        moved["sections"]["import"]["reason"] = "移動済み"
        moved["sections"]["export_type"] = {"reason": "", "items": [moved_item]}
        if accepted(moved):
            return False
        changed_key = json.loads(json.dumps(data))
        changed_key["sections"]["import"]["items"][0]["key"] = "import-other"
        if accepted(changed_key):
            return False
        changed_reason = json.loads(json.dumps(data))
        changed_reason["sections"]["const"]["reason"] = "別の理由"
        if accepted(changed_reason):
            return False
        reordered = json.loads(json.dumps(data))
        reordered["sections"] = {
            key: reordered["sections"][key]
            for key in reversed(list(reordered["sections"]))
        }
        if accepted(reordered):
            return False
        return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--facts")
    parser.add_argument("--target-repo")
    parser.add_argument("--unit-id")
    parser.add_argument("--if-screen", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        if not self_test():
            return 1
        print("PASS: screen evidence range/SHA/excerpt self-test")
        return 0
    if not args.facts:
        return 1
    try:
        candidate = load_yaml(pathlib.Path(args.facts))
        if (
            args.if_screen
            and isinstance(candidate, dict)
            and candidate.get("profile") is not None
            and candidate.get("profile") != "screen"
        ):
            print("PASS: non-screen facts profile skipped")
            return 0
        passed = valid(args)
    except (OSError, ValueError, json.JSONDecodeError, TypeError):
        passed = False
    if not passed:
        return 1
    print("PASS: screen facts schema")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
