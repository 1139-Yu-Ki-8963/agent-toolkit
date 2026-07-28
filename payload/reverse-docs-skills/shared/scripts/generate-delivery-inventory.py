#!/usr/bin/env python3
"""Production evidence scanner shared by the six unit-list owner skills."""
import argparse
import hashlib
import json
import pathlib

KINDS = ("screen", "api", "table", "batch", "report", "external")


def matches(kind, path, text):
    lowered = text.lower()
    return {
        "screen": path.name == "package.json" and '"react"' in lowered,
        "api": "@app.get(" in text or "@app.post(" in text,
        "table": path.suffix == ".sql" and "create table " in lowered,
        "batch": path.suffix == ".py" and "def run(" in text,
        "report": "REPORT_FORMAT =" in text,
        "external": "EXTERNAL_ENDPOINT =" in text,
    }[kind]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    parser.add_argument("--unit-kind", choices=KINDS, required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.target_repo).resolve()
    records = []
    try:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.name == "expected-deliverables.json":
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            if matches(args.unit_kind, path, text):
                records.append({
                    "source_path": path.relative_to(root).as_posix(),
                    "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                })
    except OSError:
        return 1
    print(json.dumps(
        {"unit_kind": args.unit_kind, "status": "DONE" if records else "STOPPED", "records": records},
        ensure_ascii=False, sort_keys=True,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
