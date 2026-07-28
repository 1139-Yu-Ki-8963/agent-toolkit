#!/usr/bin/env python3
"""Generate the canonical test-case list from evidence JSON."""
import argparse
import html
import json
import pathlib
import sys


def render(template, data):
    records = data.get("records") if isinstance(data, dict) else None
    if not isinstance(data, dict) or set(data) != {"status", "records"} or not isinstance(records, list):
        raise ValueError("invalid evidence schema")
    if not records:
        if data["status"] != "STOPPED":
            raise ValueError("zero records must be STOPPED")
        return template
    if data["status"] != "DONE":
        raise ValueError("non-empty records must be DONE")
    rows = []
    for record in records:
        steps = [*(f"前提: {value}" for value in record["preconditions"]), *record["steps"]]
        cells = [
            record["case_id"], record["screen_id"], record["level"],
            "\n".join(steps), record["expected_result"],
            f'{record["source_path"]}: {record["source_excerpt"]}',
        ]
        rows.append("<tr>" + "".join(f"<td>{html.escape(value)}</td>" for value in cells) + "</tr>")
    message = "    <p>根拠となる画面別テスト仕様書が0件のため、ケースは未生成です。</p>\n"
    if message not in template or "<tbody></tbody>" not in template:
        raise ValueError("template structure mismatch")
    return (
        template.replace('data-zero-case="true"', 'data-zero-case="false"', 1)
        .replace(message, "", 1)
        .replace("<tbody></tbody>", f"<tbody>{''.join(rows)}</tbody>", 1)
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        data = json.load(sys.stdin)
        template_path = pathlib.Path(args.template)
        output = pathlib.Path(args.output)
        if output.resolve() == template_path.resolve():
            return 1
        rendered = render(template_path.read_text(), data)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
