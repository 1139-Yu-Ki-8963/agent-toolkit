#!/usr/bin/env python3
"""Validate reverse-rule records against their source content and manifest schema."""
import argparse, hashlib, json, pathlib, re, sys
REQUIRED = {"observed_practices", "approved_norms", "evidence_paths", "observation_count", "exceptions", "confidence", "uncertainties", "rule_md_generated"}
CONFIDENCE = {"low", "medium", "high"}
ENTRY_FIELDS = {"statement", "evidence_path", "excerpt"}
SURVEY_FIELDS = {"id", "evidence_path", "excerpt", "evidence_kind", "source_sha256"}
CLASSIFICATION_FIELDS = SURVEY_FIELDS | {"primary_category", "layer_or_kind", "dedupe_key", "references"}
NON_NORMATIVE_NAMES = {"README.md", "README"}
NORMATIVE_MARKER = re.compile(r"\b(?:MUST|SHALL|REQUIRED)\b|必須|禁止|しなければ|すること", re.I)

def read_source(root, value):
    if not isinstance(value, str) or pathlib.Path(value).is_absolute():
        return None
    resolved = (root / value).resolve()
    if root not in resolved.parents or not resolved.is_file():
        return None
    try:
        return resolved.read_text()
    except (OSError, UnicodeDecodeError):
        return None

def valid_entry(root, entry, approved):
    if not isinstance(entry, dict) or set(entry) != ENTRY_FIELDS:
        return False
    if not all(isinstance(entry[key], str) and entry[key].strip() for key in ENTRY_FIELDS):
        return False
    source = read_source(root, entry["evidence_path"])
    if source is None or entry["excerpt"] not in source:
        return False
    if not approved and " ".join(entry["statement"].split()) != " ".join(entry["excerpt"].split()):
        return False
    if approved:
        if pathlib.Path(entry["evidence_path"]).name in NON_NORMATIVE_NAMES:
            return False
        statement = " ".join(entry["statement"].split())
        excerpt = " ".join(entry["excerpt"].split())
        if (
            statement != excerpt
            or len(statement) < 12
            or len(re.findall(r"[A-Za-z0-9_]+|[\u3040-\u30ff\u3400-\u9fff]+", statement)) < 2
            or NORMATIVE_MARKER.search(statement) is None
        ):
            return False
    return True

def valid_pipeline(root, data, mode, categories, survey_rows=None):
    expected = SURVEY_FIELDS if mode == "survey" else CLASSIFICATION_FIELDS
    if not isinstance(data, dict) or set(data) != {"records"} or not isinstance(data["records"], list):
        return False
    ids = set()
    dedupe_keys = set()
    for row in data["records"]:
        if not isinstance(row, dict) or set(row) != expected:
            return False
        if not all(isinstance(row[key], str) and row[key].strip() for key in SURVEY_FIELDS):
            return False
        if row["id"] in ids or row["evidence_kind"] not in {"explicit_norm", "observed_practice"}:
            return False
        ids.add(row["id"])
        source = read_source(root, row["evidence_path"])
        if source is None or row["excerpt"] not in source:
            return False
        source_path = (root / row["evidence_path"]).resolve()
        if hashlib.sha256(source_path.read_bytes()).hexdigest() != row["source_sha256"]:
            return False
        if mode == "classification":
            if survey_rows is None or row["id"] not in survey_rows:
                return False
            original = survey_rows[row["id"]]
            if any(
                row[key] != original[key]
                for key in SURVEY_FIELDS
            ):
                return False
            if row["primary_category"] not in categories:
                return False
            if not isinstance(row["references"], list) or not all(isinstance(value, str) for value in row["references"]):
                return False
            if any(value not in survey_rows for value in row["references"]):
                return False
            if row["dedupe_key"] in dedupe_keys:
                return False
            dedupe_keys.add(row["dedupe_key"])
            if row["evidence_kind"] == "explicit_norm" and not row["layer_or_kind"]:
                return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    parser.add_argument("--mode", choices=("rule", "survey", "classification"), default="rule")
    parser.add_argument("--survey-ledger")
    args = parser.parse_args()
    root = pathlib.Path(args.target_repo).resolve()
    if not root.is_dir(): return 1
    try: data = json.load(sys.stdin)
    except json.JSONDecodeError: return 1
    manifest = pathlib.Path(__file__).resolve().parents[1] / "references/delivery-reverse-manifest.yml"
    try: categories = set(json.loads(manifest.read_text())["rule_evidence_contract"]["categories"])
    except (OSError, json.JSONDecodeError, KeyError, TypeError): return 1
    if args.mode != "rule":
        survey_ids = None
        if args.mode == "classification":
            if not args.survey_ledger:
                return 1
            ledger_path = pathlib.Path(args.survey_ledger)
            try:
                ledger = json.loads(ledger_path.read_text())
            except (OSError, json.JSONDecodeError):
                return 1
            if not valid_pipeline(root, ledger, "survey", categories):
                return 1
            survey_ids = {row["id"]: row for row in ledger["records"]}
        return 0 if valid_pipeline(root, data, args.mode, categories, survey_ids) else 1
    if not isinstance(data, dict): return 1
    missing = REQUIRED - data.keys()
    if missing or set(data) != REQUIRED: return 1
    if missing or not isinstance(data["evidence_paths"], list) or not data["evidence_paths"] or not isinstance(data["observation_count"], int) or data["observation_count"] < 0 or not isinstance(data["rule_md_generated"], bool):
        return 1
    for value in data["evidence_paths"]:
        if read_source(root, value) is None: return 1
    for key in ("approved_norms", "observed_practices", "exceptions", "uncertainties"):
        if not isinstance(data[key], list): return 1
    if not all(valid_entry(root, entry, False) for entry in data["observed_practices"]): return 1
    if not all(valid_entry(root, entry, True) for entry in data["approved_norms"]): return 1
    cited = {entry["evidence_path"] for key in ("observed_practices", "approved_norms") for entry in data[key]}
    if cited != set(data["evidence_paths"]): return 1
    if data["observation_count"] != len(data["observed_practices"]) + len(data["approved_norms"]): return 1
    confidence = data["confidence"]
    if not ((isinstance(confidence, str) and confidence in CONFIDENCE)
            or (isinstance(confidence, (int, float)) and not isinstance(confidence, bool)
                and 0 <= confidence <= 1)):
        return 1
    if not data["approved_norms"] and data["rule_md_generated"]:
        return 1
    return 0
if __name__ == "__main__": raise SystemExit(main())
