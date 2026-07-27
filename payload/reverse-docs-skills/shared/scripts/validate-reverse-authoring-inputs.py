#!/usr/bin/env python3
"""Deterministic runtime gates for reverse authoring inputs.

The same helper is called by authoring/rebuilding skills and by the aggregate
self-test, so the documented 1-23/1-24 branches cannot drift from execution.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


def write_result(result: dict[str, Any], record: Path | None) -> None:
    payload = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if record is not None:
        record.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(
            prefix=f".{record.name}.", dir=str(record.parent)
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(payload)
            os.replace(tmp_name, record)
        except BaseException:
            try:
                os.unlink(tmp_name)
            except FileNotFoundError:
                pass
            raise
    sys.stdout.write(payload)


def facts_has_jsx_structure(facts_path: Path) -> bool:
    if not facts_path.is_file():
        raise ValueError(f"facts file not found: {facts_path}")
    lines = facts_path.read_text(encoding="utf-8").splitlines()
    section_start = None
    section_indent = 0
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)jsx:\s*(?:#.*)?$", line)
        if match:
            section_start = index + 1
            section_indent = len(match.group(1))
            break
    if section_start is None:
        return False
    for line in lines[section_start:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= section_indent:
            break
        if re.match(r"^\s*-\s+key:\s*\S", line):
            return True
    return False


def check_screen_composition(
    screen_dir: Path, facts_path: Path, record: Path | None
) -> int:
    original_path = screen_dir / "詳細設計" / "original.png"
    has_original = original_path.is_file()
    try:
        has_jsx = facts_has_jsx_structure(facts_path)
    except (OSError, UnicodeError, ValueError) as error:
        result = {
            "check": "screen-composition",
            "status": "FAIL",
            "reason": str(error),
        }
        write_result(result, record)
        return 1

    if has_original:
        route = "image-priority"
        status = "PASS"
        instruction = "original.pngを優先し、factsの構造は補助根拠に限定する"
    elif has_jsx:
        route = "facts-structure"
        status = "PASS"
        instruction = "factsのjsx構造だけで構成し、見出しに「構造推定」と明記する"
    else:
        route = "blocked-no-evidence"
        status = "FAIL"
        instruction = "画面構成を著述せず、画像とjsx構造の両方が無いと記録する"

    result = {
        "check": "screen-composition",
        "factsJsxAvailable": has_jsx,
        "instruction": instruction,
        "originalPngAvailable": has_original,
        "route": route,
        "status": status,
    }
    write_result(result, record)
    return 0 if status == "PASS" else 1


def frontmatter_lines(document: Path) -> list[str]:
    if not document.is_file():
        raise ValueError(f"design document not found: {document}")
    lines = document.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("YAML frontmatter is missing")
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return lines[1:index]
    raise ValueError("YAML frontmatter is not closed")


def scalar_present(value: str) -> bool:
    normalized = value.strip().strip("\"'")
    return normalized not in {"", "null", "~", "{}", "[]"}


def parse_scenarios(document: Path) -> list[dict[str, bool]]:
    lines = frontmatter_lines(document)
    scenario_indent = None
    scenario_lines: list[str] = []
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)scenarios:\s*(.*)$", line)
        if not match:
            continue
        scenario_indent = len(match.group(1))
        inline_value = match.group(2).strip()
        if inline_value and inline_value != "[]":
            raise ValueError("inline scenarios syntax is unsupported; use a YAML list")
        for nested in lines[index + 1 :]:
            if nested.strip():
                indent = len(nested) - len(nested.lstrip())
                if indent <= scenario_indent:
                    break
            scenario_lines.append(nested)
        break
    if scenario_indent is None:
        raise ValueError("frontmatter scenarios is missing")

    scenarios: list[dict[str, bool]] = []
    current: dict[str, bool] | None = None
    item_indent = None
    expected_item_indent = scenario_indent + 2
    nested_parent = None
    for line in scenario_lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        item_match = re.match(r"^(\s*)-\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if item_match and len(item_match.group(1)) == expected_item_indent:
            if current is not None:
                scenarios.append(current)
            current = {}
            item_indent = len(item_match.group(1))
            nested_parent = None
            current[item_match.group(2)] = scalar_present(item_match.group(3))
            continue
        if current is None or item_indent is None:
            continue
        key_match = re.match(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if not key_match:
            continue
        indent = len(key_match.group(1))
        key = key_match.group(2)
        value = key_match.group(3)
        if indent == item_indent + 2:
            current[key] = scalar_present(value)
            nested_parent = key if not scalar_present(value) else None
        elif indent > item_indent + 2 and nested_parent is not None and line.strip():
            current[nested_parent] = True
    if current is not None:
        scenarios.append(current)
    return scenarios


def check_scenarios(
    document: Path,
    verification_url: str | None,
    measurement_evidence: Path | None,
    record: Path | None,
) -> int:
    evidence_present = bool(verification_url and verification_url.strip())
    if measurement_evidence is not None:
        evidence_present = evidence_present or (
            measurement_evidence.is_file()
            and measurement_evidence.stat().st_size > 0
        )
    try:
        scenarios = parse_scenarios(document)
    except (OSError, UnicodeError, ValueError) as error:
        result = {
            "check": "scenarios",
            "measuredEvidence": evidence_present,
            "reason": str(error),
            "status": "FAIL",
        }
        write_result(result, record)
        return 1

    failures: list[str] = []
    if not scenarios:
        failures.append("scenarios must contain at least one item")
    for index, scenario in enumerate(scenarios, start=1):
        for key in ("path", "ready"):
            if not scenario.get(key, False):
                failures.append(f"scenarios[{index}].{key} is required")
        if evidence_present:
            for key in ("query", "path_params"):
                if not scenario.get(key, False):
                    failures.append(
                        f"scenarios[{index}].{key} is required when measured evidence exists"
                    )

    result = {
        "check": "scenarios",
        "failures": failures,
        "measuredEvidence": evidence_present,
        "scenarioCount": len(scenarios),
        "status": "FAIL" if failures else "PASS",
    }
    write_result(result, record)
    return 1 if failures else 0


def run_self_test() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="reverse-authoring-inputs.") as tmp_name:
        root = Path(tmp_name)
        facts_with_jsx = root / "facts-with-jsx.yml"
        facts_without_jsx = root / "facts-without-jsx.yml"
        facts_with_jsx.write_text(
            "sections:\n  jsx:\n    items:\n      - key: jsx-root\n        value: main\n",
            encoding="utf-8",
        )
        facts_without_jsx.write_text(
            "sections:\n  jsx:\n    reason: no structure\n    items: []\n",
            encoding="utf-8",
        )

        for original, jsx, expected in (
            (True, True, 0),
            (True, False, 0),
            (False, True, 0),
            (False, False, 1),
        ):
            screen_dir = root / f"screen-{int(original)}-{int(jsx)}"
            (screen_dir / "詳細設計").mkdir(parents=True)
            if original:
                (screen_dir / "詳細設計" / "original.png").write_bytes(b"fixture")
            facts_path = facts_with_jsx if jsx else facts_without_jsx
            rc = check_screen_composition(
                screen_dir,
                facts_path,
                root / f"screen-{int(original)}-{int(jsx)}.json",
            )
            if rc != expected:
                failures.append(
                    f"1-23 branch original={original} jsx={jsx}: expected {expected}, got {rc}"
                )

        def write_design(name: str, body: str) -> Path:
            path = root / name
            path.write_text(f"---\n{body}---\n# fixture\n", encoding="utf-8")
            return path

        unmeasured = write_design(
            "unmeasured.md",
            "scenarios:\n  - path: /items\n    ready: '#items'\n",
        )
        measured_complete = write_design(
            "measured-complete.md",
            "scenarios:\n  - path: /items/42\n    ready: '#item'\n"
            "    query:\n      tab: detail\n"
            "    path_params:\n      id: '42'\n"
            "    operations:\n"
            "      - action: click\n"
            "        target: '#item'\n",
        )
        measured_missing = write_design(
            "measured-missing.md",
            "scenarios:\n  - path: /items/42\n    ready: '#item'\n",
        )
        missing_required = write_design(
            "missing-required.md",
            "scenarios:\n  - query:\n      tab: detail\n",
        )

        scenario_cases = (
            (unmeasured, None, 0),
            (measured_complete, "http://127.0.0.1/items/42?tab=detail", 0),
            (measured_missing, "http://127.0.0.1/items/42?tab=detail", 1),
            (missing_required, None, 1),
        )
        for document, url, expected in scenario_cases:
            rc = check_scenarios(
                document,
                url,
                None,
                root / f"{document.stem}.json",
            )
            if rc != expected:
                failures.append(
                    f"1-24 branch {document.name}: expected {expected}, got {rc}"
                )

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print("PASS: 1-23 original.png有無×facts jsx有無の4分岐")
    print("PASS: 1-24 scenarios必須値・未開通省略・実測証跡不足の実動分岐")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    subparsers = parser.add_subparsers(dest="command")

    screen_parser = subparsers.add_parser("screen-composition")
    screen_parser.add_argument("--screen-dir", type=Path, required=True)
    screen_parser.add_argument("--facts", type=Path, required=True)
    screen_parser.add_argument("--record", type=Path)

    scenarios_parser = subparsers.add_parser("scenarios")
    scenarios_parser.add_argument("--design-doc", type=Path, required=True)
    scenarios_parser.add_argument("--verification-url")
    scenarios_parser.add_argument("--measurement-evidence", type=Path)
    scenarios_parser.add_argument("--record", type=Path)

    args = parser.parse_args()

    if args.self_test:
        return run_self_test()
    if args.command is None:
        parser.error("a command is required unless --self-test is used")
    if args.command == "screen-composition":
        return check_screen_composition(args.screen_dir, args.facts, args.record)
    if args.command == "scenarios":
        return check_scenarios(
            args.design_doc,
            args.verification_url,
            args.measurement_evidence,
            args.record,
        )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
