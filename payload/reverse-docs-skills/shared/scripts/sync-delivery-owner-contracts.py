#!/usr/bin/env python3
"""Synchronize machine-readable owner contracts into non-template SKILL bodies."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
START = "<!-- delivery-owner-contracts:start -->"
END = "<!-- delivery-owner-contracts:end -->"


def main():
    manifest = json.loads((ROOT / "shared/references/delivery-reverse-manifest.yml").read_text())
    failure = manifest["owner_contract_defaults"]["failure_return_to"]
    owners = {}
    for row in manifest["deliverables"]:
        if row["classification"] == "template-only":
            continue
        owners.setdefault(row["owner"], []).append({
            key: row[key]
            for key in ("id", "inputs", "outputs", "validator", "stop_conditions")
        } | {"failure_return_to": failure})
    for owner, contracts in owners.items():
        path = ROOT / ".claude/skills" / owner / "SKILL.md"
        text = path.read_text()
        payload = json.dumps(contracts, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        block = f"{START}\n```json\n{payload}\n```\n{END}"
        pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
        updated = pattern.sub(block, text) if pattern.search(text) else text.rstrip() + "\n\n" + block + "\n"
        path.write_text(updated)
    print(f"PASS: synchronized {len(owners)} owner skill contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
