#!/usr/bin/env python3
"""Return D3, D4, or D6 for screen and non-screen canonical artifacts."""
import argparse
import json
import pathlib
import subprocess
import sys

DESIGN_PATHS = {
    "api": ["API/{id}/詳細設計/API詳細設計書.md"],
    "table": ["テーブル/{id}/詳細設計/テーブル定義書.md"],
    "batch": ["バッチ/{id}/詳細設計/バッチ詳細設計書.md"],
    "report": ["帳票/{id}/詳細設計/帳票詳細設計書.md"],
    "external": ["外部連携/{id}/詳細設計/外部連携詳細設計書.md"],
}
BASIC_PATHS = {
    "batch": "バッチ/{id}/基本設計/バッチ基本設計書.md",
    "report": "帳票/{id}/基本設計/帳票基本設計書.md",
    "external": "外部連携/{id}/基本設計/外部連携基本設計書.md",
}


def valid_screen_facts(facts_dir, root, expected_id):
    facts = facts_dir / "facts.yml"
    validator = pathlib.Path(__file__).with_name("validate-facts-schema.py")
    checked = subprocess.run(
        [
            sys.executable, str(validator), "--facts", str(facts),
            "--target-repo", str(root), "--unit-id", expected_id,
        ],
        capture_output=True, text=True, check=False,
    )
    if checked.returncode:
        return False
    seal = pathlib.Path(__file__).with_name("seal-facts.sh")
    return subprocess.run(
        ["bash", str(seal), "verify", str(facts_dir)],
        capture_output=True,
        text=True,
        check=False,
    ).returncode == 0


def valid_non_screen_facts(root, facts_path, expected_kind, expected_id):
    validator = pathlib.Path(__file__).with_name("check-unit-design-evidence.py")
    try:
        payload = json.loads(facts_path.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    if payload.get("unit_kind") != expected_kind or payload.get("unit_id") != expected_id:
        return False
    return subprocess.run(
        ["python3", str(validator), "--target-repo", str(root)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    ).returncode == 0


def next_state(root, verification, output, units):
    facts_by_unit = {}
    for unit in units:
        kind, unit_id = unit["kind"], unit["id"]
        if kind == "screen":
            facts_dirs = [
                path.parent
                for path in (verification / f"screen-{unit_id}" / "facts").glob("*/facts.lock")
            ]
            if not facts_dirs or not any(valid_screen_facts(path, root, unit_id) for path in facts_dirs):
                return "D3"
            continue
        facts = verification / f"{kind}-{unit_id}" / "facts" / "unit-facts.json"
        if not facts.is_file() or not valid_non_screen_facts(root, facts, kind, unit_id):
            return "D3"
        facts_by_unit[(kind, unit_id)] = facts
    for unit in units:
        kind, unit_id = unit["kind"], unit["id"]
        if kind == "screen":
            design = output / "画面" / f"screen-{unit_id}" / "詳細設計" / "画面詳細設計書.md"
            if not design.is_file() or not design.read_text(errors="ignore").strip():
                return "D4"
            continue
        validator = pathlib.Path(__file__).with_name("generate-unit-designs.py")
        validated = subprocess.run(
            [
                sys.executable, str(validator), "--validate-output",
                "--validate-scope", "detail",
                "--target-repo", str(root),
                "--facts", str(facts_by_unit[(kind, unit_id)]),
                "--output-dir", str(output),
            ],
            capture_output=True, text=True, check=False,
        )
        if validated.returncode:
            return "D4"
    for unit in units:
        pattern = BASIC_PATHS.get(unit["kind"])
        if pattern:
            basic = output / pattern.format(id=unit["id"])
            validator = pathlib.Path(__file__).with_name("generate-unit-designs.py")
            validated = subprocess.run(
                [
                    sys.executable, str(validator), "--validate-output",
                    "--validate-scope", "basic",
                    "--target-repo", str(root),
                    "--facts", str(facts_by_unit[(unit["kind"], unit["id"])]),
                    "--output-dir", str(output),
                ],
                capture_output=True, text=True, check=False,
            )
            if not basic.is_file() or validated.returncode:
                return "D6"
    return "COMPLETE"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    parser.add_argument("--verification-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 1
    units = data.get("units") if isinstance(data, dict) else None
    if not isinstance(units, list) or not units:
        return 1
    if any(
        not isinstance(unit, dict)
        or set(unit) != {"kind", "id"}
        or unit["kind"] not in {"screen", *DESIGN_PATHS}
        or not isinstance(unit["id"], str)
        or not unit["id"]
        for unit in units
    ):
        return 1
    state = next_state(
        pathlib.Path(args.target_repo).resolve(),
        pathlib.Path(args.verification_dir).resolve(),
        pathlib.Path(args.output_dir).resolve(),
        units,
    )
    print(state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
