#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OVERVIEW="${ROOT_DIR}/reverse-docs-overview.html"
SAMPLE="${ROOT_DIR}/shared/samples/index.html"
CATALOG="${ROOT_DIR}/shared/references/portal-catalog.json"
DELIVERY="${ROOT_DIR}/shared/references/納品物フォルダ体系.md"

if [[ ! -f "${OVERVIEW}" || ! -f "${SAMPLE}" || ! -f "${CATALOG}" || ! -f "${DELIVERY}" ]]; then
  echo "FAIL: overview, sample index, catalog, or delivery inventory is missing" >&2
  exit 1
fi

python3 - "${OVERVIEW}" "${SAMPLE}" "${CATALOG}" "${DELIVERY}" <<'PY'
import json
import re
import sys
from pathlib import Path

overview_path = Path(sys.argv[1])
sample_path = Path(sys.argv[2])
catalog_path = Path(sys.argv[3])
delivery_path = Path(sys.argv[4])
overview = overview_path.read_text(encoding="utf-8")
sample = sample_path.read_text(encoding="utf-8")
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
delivery = delivery_path.read_text(encoding="utf-8")

match = re.search(
    r'<script type="application/json" id="portal-categories">(.*?)</script>',
    sample,
    re.S,
)
if not match:
    raise SystemExit("FAIL: portal-categories JSON is missing from sample index")

portal_categories = json.loads(match.group(1))
catalog_keys = {category["key"] for category in catalog["categories"]}
catalog_labels = {category["label"] for category in catalog["categories"]}
portal_keys = {category["id"] for category in portal_categories}
portal_labels = {category["title"] for category in portal_categories}
expected_tools = [
    (category["title"], tool["title"], tool["href"])
    for category in portal_categories
    for tool in category["tools"]
]

table_match = re.search(
    r"^## ポータルカテゴリ対応表\s*$([\s\S]*?)(?=^##\s|\Z)",
    delivery,
    re.M,
)
if not table_match:
    raise SystemExit("FAIL: delivery inventory has no ポータルカテゴリ対応表")
delivery_keys = set(re.findall(r"^\|\s*`([a-z0-9-]+)`\s*\|", table_match.group(1), re.M))

differences = []
for left_name, left, right_name, right in (
    ("catalog", catalog_keys, "portal", portal_keys),
    ("catalog", catalog_keys, "delivery", delivery_keys),
):
    missing = sorted(left - right)
    unknown = sorted(right - left)
    if missing:
        differences.append(f"{right_name} missing keys from {left_name}: {', '.join(missing)}")
    if unknown:
        differences.append(f"{right_name} has unknown keys vs {left_name}: {', '.join(unknown)}")

visible = re.sub(
    r'<template id="legacy-(?:deliverables-table|process-flow)">.*?</template>',
    '',
    overview,
    flags=re.S,
)

overview_labels = {label for label in catalog_labels if label in visible}
missing_overview_labels = sorted(catalog_labels - overview_labels)
missing_portal_labels = sorted(catalog_labels - portal_labels)
unknown_portal_labels = sorted(portal_labels - catalog_labels)
if missing_overview_labels:
    differences.append("overview missing category labels: " + ", ".join(missing_overview_labels))
if missing_portal_labels:
    differences.append("portal missing category labels: " + ", ".join(missing_portal_labels))
if unknown_portal_labels:
    differences.append("portal has unknown category labels: " + ", ".join(unknown_portal_labels))

missing_tools = [
    f"{category}: {title} ({href})"
    for category, title, href in expected_tools
    if title not in visible or href[1:] not in visible
]
if missing_tools:
    differences.append("overview missing portal cards:\n  " + "\n  ".join(missing_tools))
if differences:
    raise SystemExit("FAIL: catalog/portal/overview/delivery mismatch:\n  " + "\n  ".join(differences))

required_markers = [
    "generating-reverse-basic-design ∥ generating-reverse-detailed-design",
    "詳細設計パス1 → 基本設計・テスト資料パス2",
    "通常の状態遷移:",
    "project-portal/一覧/テストケース一覧/テストケース一覧.html",
]
missing_markers = [marker for marker in required_markers if marker not in visible]
if missing_markers:
    raise SystemExit("FAIL: missing process markers:\n  " + "\n  ".join(missing_markers))

for forbidden in ("基本設計より先に詳細設計を書かない",):
    if forbidden in visible:
        raise SystemExit(f"FAIL: obsolete process statement remains: {forbidden}")

print(
    f"PASS: {len(portal_categories)} portal categories, "
    f"{len(expected_tools)} discovered cards, catalog/portal/overview/delivery sets aligned"
)
PY
