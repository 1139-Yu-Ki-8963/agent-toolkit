#!/usr/bin/env python3
"""Validate test-case list rows and the dedicated zero-case template."""
import argparse
import hashlib
import html.parser
import json
import pathlib
import re
import sys

FIELDS = {
    "case_id", "screen_id", "level", "preconditions", "steps",
    "expected_result", "source_path", "source_excerpt", "input_kind",
    "screen_registry_path", "source_test_spec_path", "source_test_spec_sha256",
}
LEVELS = {"unit", "integration", "operation"}
TYPE_BY_LEVEL = {
    "unit": "unit-test-spec",
    "integration": "integration-test-spec",
    "operation": "operation-test-spec",
}
TEMPLATE_MARKERS = (
    'id="test-case-list"',
    'data-zero-case="true"',
    "<th>ケースID</th>",
    "<th>根拠</th>",
)
HEADERS = ["ケースID", "画面ID", "レベル", "手順", "期待結果", "根拠"]


class TableParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_table = self.in_thead = self.in_tbody = False
        self.cell = self.row = None
        self.headers, self.rows = [], []
        self.main_zero = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "main" and attributes.get("id") == "test-case-list":
            self.main_zero = attributes.get("data-zero-case")
        elif tag == "table":
            self.in_table = True
        elif self.in_table and tag == "thead":
            self.in_thead = True
        elif self.in_table and tag == "tbody":
            self.in_tbody = True
        elif self.in_tbody and tag == "tr":
            self.row = []
        elif self.in_table and tag in {"th", "td"}:
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in {"th", "td"} and self.cell is not None:
            value = "".join(self.cell)
            if tag == "th" and self.in_thead:
                self.headers.append(value)
            elif tag == "td" and self.row is not None:
                self.row.append(value)
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None
        elif tag == "thead":
            self.in_thead = False
        elif tag == "tbody":
            self.in_tbody = False
        elif tag == "table":
            self.in_table = False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-repo", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.target_repo).resolve()
    template = pathlib.Path(args.template)
    output = pathlib.Path(args.output)
    try:
        data = json.load(sys.stdin)
        template_text = template.read_text()
        output_text = output.read_text()
    except (OSError, json.JSONDecodeError):
        return 1
    if output.resolve() == template.resolve():
        return 1
    if not isinstance(data, dict) or set(data) != {"status", "records"}:
        return 1
    records = data["records"]
    if not isinstance(records, list) or not all(marker in template_text for marker in TEMPLATE_MARKERS):
        return 1
    if not records:
        return 0 if (
            data["status"] == "STOPPED"
            and hashlib.sha256(output_text.encode()).hexdigest()
            == hashlib.sha256(template_text.encode()).hexdigest()
        ) else 1
    if data["status"] != "DONE":
        return 1
    parser = TableParser()
    try:
        parser.feed(output_text)
    except Exception:
        return 1
    if parser.main_zero != "false" or parser.headers != HEADERS or len(parser.rows) != len(records):
        return 1
    ids = set()
    for index, row in enumerate(records):
        if not isinstance(row, dict) or set(row) != FIELDS:
            return 1
        if row["level"] not in LEVELS or row["case_id"] in ids:
            return 1
        if row["input_kind"] != "test-spec" or row["source_path"] != row["source_test_spec_path"]:
            return 1
        ids.add(row["case_id"])
        if not all(isinstance(row[key], str) and row[key].strip() for key in FIELDS - {"steps", "preconditions"}):
            return 1
        if not isinstance(row["steps"], list) or not row["steps"] or not all(isinstance(step, str) and step.strip() for step in row["steps"]):
            return 1
        if not isinstance(row["preconditions"], list) or not all(isinstance(value, str) for value in row["preconditions"]):
            return 1
        source = (root / row["source_path"]).resolve()
        if root not in source.parents or not source.is_file():
            return 1
        try:
            source_text = source.read_text()
            if (
                row["source_excerpt"] not in source_text
                or hashlib.sha256(source.read_bytes()).hexdigest() != row["source_test_spec_sha256"]
                or not source.name.endswith("テスト仕様書.md")
                or re.search(
                    r"^type:\s*([a-z-]+)\s*$", source_text, re.MULTILINE
                ) is None
                or re.search(
                    r"^type:\s*([a-z-]+)\s*$", source_text, re.MULTILINE
                ).group(1) != TYPE_BY_LEVEL[row["level"]]
                or f"/画面/{row['screen_id']}/テスト項目書/" not in source.as_posix()
            ):
                return 1
        except (OSError, UnicodeDecodeError):
            return 1
        registry = (root / row["screen_registry_path"]).resolve()
        if root not in registry.parents or not registry.is_file():
            return 1
        try:
            registry_text = registry.read_text()
        except (OSError, UnicodeDecodeError):
            return 1
        expected_screen_path = f"画面/{row['screen_id']}"
        if row["screen_id"] not in registry_text or expected_screen_path not in registry_text:
            return 1
        cited_behavior = [*row["steps"], row["expected_result"]]
        if not all(value in row["source_excerpt"] for value in cited_behavior):
            return 1
        expected_steps = [*(f"前提: {value}" for value in row["preconditions"]), *row["steps"]]
        expected_cells = [
            row["case_id"], row["screen_id"], row["level"], "\n".join(expected_steps),
            row["expected_result"], f'{row["source_path"]}: {row["source_excerpt"]}',
        ]
        if parser.rows[index] != expected_cells:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
