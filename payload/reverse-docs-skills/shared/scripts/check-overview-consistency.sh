#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OVERVIEW="${ROOT_DIR}/reverse-docs-overview.html"
SAMPLE="${ROOT_DIR}/shared/samples/index.html"

if [[ ! -f "${OVERVIEW}" || ! -f "${SAMPLE}" ]]; then
  echo "FAIL: overview or sample index is missing" >&2
  exit 1
fi

python3 - "${OVERVIEW}" "${SAMPLE}" <<'PY'
import json
import re
import sys
from pathlib import Path

overview_path = Path(sys.argv[1])
sample_path = Path(sys.argv[2])
overview = overview_path.read_text(encoding="utf-8")
sample = sample_path.read_text(encoding="utf-8")

match = re.search(
    r'<script type="application/json" id="portal-categories">(.*?)</script>',
    sample,
    re.S,
)
if not match:
    raise SystemExit("FAIL: portal-categories JSON is missing from sample index")

categories = json.loads(match.group(1))
expected_titles = [category["title"] for category in categories]
expected_tools = [
    (category["title"], tool["title"], tool["href"])
    for category in categories
    for tool in category["tools"]
]

if len(categories) != 7:
    raise SystemExit(f"FAIL: expected 7 portal categories, got {len(categories)}")
if len(expected_tools) != 36:
    raise SystemExit(f"FAIL: expected 36 portal cards, got {len(expected_tools)}")

visible = re.sub(
    r'<template id="legacy-(?:deliverables-table|process-flow)">.*?</template>',
    '',
    overview,
    flags=re.S,
)

missing_categories = [title for title in expected_titles if title not in visible]
missing_tools = [
    f"{category}: {title} ({href})"
    for category, title, href in expected_tools
    if title not in visible or href[1:] not in visible
]
if missing_categories:
    raise SystemExit("FAIL: missing portal categories: " + ", ".join(missing_categories))
if missing_tools:
    raise SystemExit("FAIL: missing portal cards:\n  " + "\n  ".join(missing_tools))

required_markers = [
    "03. ユニットfacts・詳細設計",
    "04. 規約根拠・分類・生成と共通統合",
    "05. 基本設計・派生一覧・図表・対応表・AI設定資産",
    "06. ポータル生成・HTML検証",
    "07. 往復検証",
    "&lt;output_dir&gt;/一覧/テストケース一覧/テストケース一覧.html",
]
missing_markers = [marker for marker in required_markers if marker not in visible]
if missing_markers:
    raise SystemExit("FAIL: missing process markers:\n  " + "\n  ".join(missing_markers))

for forbidden in ("基本設計より先に詳細設計を書かない",):
    if forbidden in visible:
        raise SystemExit(f"FAIL: obsolete process statement remains: {forbidden}")

print(f"PASS: {len(categories)} portal categories, {len(expected_tools)} cards, process markers aligned")
PY
