#!/usr/bin/env bash
set -euo pipefail

# 改善課題 1-138: 横断検収条件（本番経路スクリプトへの --self-test 実装）に対応する。
# 必要性: catalog/portal/overview/delivery 4資産の整合検査は build-portal.sh の生成物と
#   人間向けガイドの乖離を防ぐ決定的チェックであり、正常系（4資産が整合）・異常系（必須マーカー
#   欠落）を自己テストで固定しておくことで、検査条件を変更した際のリグレッションを検知できる。
#   本スクリプトは ROOT_DIR を自身の配置位置から算出するため、self-test は合成リポジトリ構造
#   （tmp配下に4資産一式を複製）を作り、本スクリプトのコピーをその中で実行する形にする。
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-overview-consistency-self-test.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  mkdir -p "$tmp/shared/scripts" "$tmp/shared/samples" "$tmp/shared/references" "$tmp/docs"
  cp "${BASH_SOURCE[0]}" "$tmp/shared/scripts/check-overview-consistency.sh"
  cp "$(dirname "${BASH_SOURCE[0]}")/output-layout.sh" "$tmp/shared/scripts/output-layout.sh"
  cp "$(dirname "${BASH_SOURCE[0]}")/../references/output-layout.json" "$tmp/shared/references/output-layout.json"

  cat > "$tmp/shared/references/portal-catalog.json" <<'JSON'
{ "categories": [ { "key": "demo", "label": "デモカテゴリ" } ] }
JSON

  cat > "$tmp/shared/samples/index.html" <<'HTML'
<html><body>
<script type="application/json" id="portal-categories">
[{"id":"demo","title":"デモカテゴリ","tools":[{"title":"デモツール","href":"/demo/demo.html"}]}]
</script>
</body></html>
HTML

  cat > "$tmp/shared/references/納品物フォルダ体系.md" <<'MD'
## ポータルカテゴリ対応表

| カテゴリキー | カテゴリ名 |
|---|---|
| `demo` | デモカテゴリ |
MD

  cat > "$tmp/docs/reverse-docs-overview.html" <<'HTML'
<html><body>
<p>デモカテゴリ / デモツール / demo/demo.html</p>
<p>generating-reverse-basic-design ∥ generating-reverse-detailed-design</p>
<p>詳細設計パス1 → 基本設計・テスト資料パス2</p>
<p>通常の状態遷移:</p>
<p>project-portal/一覧/テストケース一覧/テストケース一覧.html</p>
</body></html>
HTML

  pass=0 fail=0
  if ( cd "$tmp" && bash shared/scripts/check-overview-consistency.sh ) >/dev/null 2>&1; then
    echo "PASS: 正常系（4資産整合）で終了コード0"; pass=$((pass + 1))
  else
    echo "FAIL: 正常系で終了コード0になるべき"; fail=$((fail + 1))
  fi

  # 異常系: 必須マーカーの1つを overview.html から欠落させる
  cat > "$tmp/docs/reverse-docs-overview.html" <<'HTML'
<html><body>
<p>デモカテゴリ / デモツール / demo/demo.html</p>
<p>通常の状態遷移:</p>
<p>project-portal/一覧/テストケース一覧/テストケース一覧.html</p>
</body></html>
HTML
  if ( cd "$tmp" && bash shared/scripts/check-overview-consistency.sh ) >/dev/null 2>&1; then
    echo "FAIL: 異常系（必須マーカー欠落）で終了コード1になるべき"; fail=$((fail + 1))
  else
    echo "PASS: 異常系（必須マーカー欠落）で終了コード1"; pass=$((pass + 1))
  fi

  echo "self-test: $pass PASS, $fail FAIL"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OVERVIEW="${ROOT_DIR}/docs/reverse-docs-overview.html"
SAMPLE="${ROOT_DIR}/shared/samples/index.html"
CATALOG="${ROOT_DIR}/shared/references/portal-catalog.json"
DELIVERY="${ROOT_DIR}/shared/references/納品物フォルダ体系.md"

if [[ ! -f "${OVERVIEW}" || ! -f "${SAMPLE}" || ! -f "${CATALOG}" || ! -f "${DELIVERY}" ]]; then
  echo "FAIL: overview, sample index, catalog, or delivery inventory is missing" >&2
  exit 1
fi

# shellcheck source=output-layout.sh
source "${ROOT_DIR}/shared/scripts/output-layout.sh"
LAYOUT_JSON="$(resolve_output_layout "")" || exit 1
TEST_CASE_LIST_HTML="project-portal/$(output_layout_get "$LAYOUT_JSON" unitListHtml テストケース)" || exit 1

python3 - "${OVERVIEW}" "${SAMPLE}" "${CATALOG}" "${DELIVERY}" "${TEST_CASE_LIST_HTML}" <<'PY'
import json
import re
import sys
from pathlib import Path

overview_path = Path(sys.argv[1])
sample_path = Path(sys.argv[2])
catalog_path = Path(sys.argv[3])
delivery_path = Path(sys.argv[4])
test_case_list_html = sys.argv[5]
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
    test_case_list_html,
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
