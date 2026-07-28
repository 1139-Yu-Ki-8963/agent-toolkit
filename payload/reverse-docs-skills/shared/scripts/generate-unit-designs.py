#!/usr/bin/env python3
"""Generate canonical non-screen unit designs from validated unit facts."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUTPUTS = {
    "api": [("unit-design-api-detail.md", "API/{id}/詳細設計/API詳細設計書.md")],
    "table": [("unit-design-table-detail.md", "テーブル/{id}/詳細設計/テーブル定義書.md")],
    "batch": [
        ("unit-design-batch-detail.md", "バッチ/{id}/詳細設計/バッチ詳細設計書.md"),
        ("unit-design-batch-basic.md", "バッチ/{id}/基本設計/バッチ基本設計書.md"),
    ],
    "report": [
        ("unit-design-report-detail.md", "帳票/{id}/詳細設計/帳票詳細設計書.md"),
        ("unit-design-report-basic.md", "帳票/{id}/基本設計/帳票基本設計書.md"),
    ],
    "external": [
        ("unit-design-external-detail.md", "外部連携/{id}/詳細設計/外部連携詳細設計書.md"),
        ("unit-design-external-basic.md", "外部連携/{id}/基本設計/外部連携基本設計書.md"),
    ],
}

def render_outputs(payload, facts_path):
    kind, unit_id = payload["unit_kind"], payload["unit_id"]
    rows = "\n".join(
        f'| {item["field"]} | {item["observed_value"]} | '
        f'{item["source_path"]}:{item["source_line"]} |'
        for item in payload["structure"]
    )
    identity = (
        "---\n"
        "schema_version: 1\n"
        f"unit_kind: {kind}\n"
        f"unit_id: {unit_id}\n"
        f"facts_sha256: {hashlib.sha256(facts_path.read_bytes()).hexdigest()}\n"
        "---\n"
    )
    rendered = {}
    for template_name, output_pattern in OUTPUTS[kind]:
        template = (ROOT / "shared/templates" / template_name).read_text()
        rendered[output_pattern.format(id=unit_id)] = identity + template.replace(
            "|---|---|---|", f"|---|---|---|\n{rows}", 1
        )
    return rendered


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    parser.add_argument("--facts", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--mode", choices=("facts", "design"), default="design")
    parser.add_argument("--validate-output", action="store_true")
    parser.add_argument("--validate-scope", choices=("all", "detail", "basic"), default="all")
    args = parser.parse_args()
    facts_path = pathlib.Path(args.facts)
    try:
        payload = json.loads(facts_path.read_text())
    except (OSError, json.JSONDecodeError):
        return 1
    checked = subprocess.run(
        ["python3", str(pathlib.Path(__file__).with_name("check-unit-design-evidence.py")),
         "--target-repo", args.target_repo],
        input=json.dumps(payload), text=True, capture_output=True, check=False,
    )
    if checked.returncode:
        return 1
    if args.mode == "facts":
        return 0
    if payload["status"] == "STOPPED":
        return 0
    output_root = pathlib.Path(args.output_dir)
    try:
        rendered = render_outputs(payload, facts_path)
        if args.validate_output:
            if args.validate_scope != "all":
                needle = "/詳細設計/" if args.validate_scope == "detail" else "/基本設計/"
                rendered = {path: text for path, text in rendered.items() if needle in path}
            return 0 if all(
                (output_root / relative).is_file()
                and (output_root / relative).read_text() == document
                for relative, document in rendered.items()
            ) else 1
        for relative, document in rendered.items():
            destination = output_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(document)
    except (OSError, KeyError):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
