#!/usr/bin/env python3
"""Refresh canonical artifact SHA values in the task trace after reviewed edits."""
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
TRACE = ROOT / "verification/delivery-reverse-skills/task-traceability.json"


def main():
    data = json.loads(TRACE.read_text())
    for row in data["tasks"]:
        row["evidence_sha256"] = hashlib.sha256((ROOT / row["implementation"]).read_bytes()).hexdigest()
    TRACE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"PASS: refreshed {len(data['tasks'])} trace evidence hashes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
