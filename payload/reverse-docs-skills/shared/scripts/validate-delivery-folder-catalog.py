#!/usr/bin/env python3
"""Validate an exactly marked folder inventory against its manifest-backed catalog."""
import argparse
import json
import pathlib
import re
import tempfile
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
KINDS = ("control_artifacts", "assets", "evidence", "screen_deliverables")
START = "<!-- delivery-folder-leaves:start -->"
END = "<!-- delivery-folder-leaves:end -->"
PATH_SCHEMAS = {
    "control_artifacts": (
        r"一覧/画面一覧/複雑度プロファイル\.json",
        r"一覧/reverse-screen-registry\.yml",
        r"一覧/excluded-kinds\.json",
        r"プロジェクト共通/アーキテクチャ調査書\.md",
        r"画面/<screen-id>/シーケンス図-data\.json",
    ),
    "assets": (
        r"画面/<screen-id>/詳細設計/(?:original|rebuilt)\.png",
    ),
    "evidence": (
        r"verification/<unit-kind>-<unit-id>/facts/<run-id>/(?:facts\.yml|facts\.lock|recount-report\.txt)",
        r"verification/<unit-kind>-<unit-id>/<timestamp>/(?:修正指示書\.md|最終報告\.md|<test-log-or-diff>)",
    ),
    "screen_deliverables": (
        r"画面/<screen-id>/詳細設計/(?:画面詳細設計書\.(?:md|html)|DESIGN\.md|単体テスト観点表\.md|結合テスト観点表\.md)",
        r"画面/<screen-id>/基本設計/画面基本設計書\.(?:md|html)",
        r"画面/<screen-id>/シーケンス図\.html",
        r"画面/<screen-id>/テスト項目書/(?:単体テスト仕様書\.md|結合テスト仕様書\.md|操作シナリオ仕様書\.md)",
    ),
}


def validate(inventory_path, catalog_path):
    catalog = json.loads(catalog_path.read_text())
    manifest = json.loads((ROOT / "shared/references/delivery-reverse-manifest.yml").read_text())
    inventory = inventory_path.read_text()
    if inventory.count(START) != 1 or inventory.count(END) != 1:
        return None
    block = inventory.split(START, 1)[1].split(END, 1)[0]
    parsed = re.findall(r"^- ([a-z_]+) \| `([^`\n]+)`$", block, re.MULTILINE)
    if len(parsed) != len(set(parsed)):
        return None
    if (
        catalog.get("schema_version") != 1
        or catalog.get("path_semantics_version") != 1
        or catalog.get("deliverable_source")
        != "shared/references/delivery-reverse-manifest.yml#deliverables[].outputs"
        or set(catalog) != {
            "schema_version", "deliverable_source", "portal_rule",
            "path_semantics_version",
            "control_artifacts", "assets", "evidence", "screen_deliverables",
        }
    ):
        return None
    classified = {}
    for kind in KINDS:
        values = catalog[kind]
        if not isinstance(values, list) or not values:
            return None
        for path in values:
            if not isinstance(path, str) or not path or path in classified:
                return None
            classified[path] = kind
            if not any(re.fullmatch(pattern, path) for pattern in PATH_SCHEMAS[kind]):
                return None
    outputs = {}
    for row in manifest.get("deliverables", []):
        for path in row["outputs"]:
            if path in outputs:
                return None
            outputs[path] = row["id"]
    # The catalog expands its deliverable_source to exactly this set; no duplicate
    # path may be separately classified as a control/evidence/asset.
    if set(outputs) & set(classified):
        return None
    expected = {("deliverable", path) for path in outputs}
    expected.update((kind, path) for path, kind in classified.items())
    if set(parsed) != expected:
        return None
    return len(outputs), sum(len(catalog[k]) for k in KINDS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--inventory", type=pathlib.Path,
        default=ROOT / "shared/references/納品物フォルダ体系.md",
    )
    parser.add_argument(
        "--catalog", type=pathlib.Path,
        default=ROOT / "shared/references/delivery-folder-catalog.json",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        counts = validate(args.inventory, args.catalog)
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        counts = None
    if counts is None:
        return 1
    if args.self_test:
        with tempfile.TemporaryDirectory(prefix="folder-catalog-") as temporary:
            candidate = pathlib.Path(temporary) / "inventory.md"
            candidate_catalog = pathlib.Path(temporary) / "catalog.json"
            text = args.inventory.read_text().replace(
                END, "- control_artifacts | `任意/未分類.txt`\n" + END, 1
            )
            candidate.write_text(text)
            catalog = json.loads(args.catalog.read_text())
            catalog["control_artifacts"].append("任意/未分類.txt")
            candidate_catalog.write_text(json.dumps(catalog, ensure_ascii=False))
            result = subprocess.run(
                [sys.executable, str(pathlib.Path(__file__).resolve()),
                 "--inventory", str(candidate), "--catalog", str(candidate_catalog)],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            if result.returncode == 0:
                return 1
        print("PASS: catalog+document arbitrary unclassified path rejected")
        return 0
    outputs_count, classified_count = counts
    print(
        f"PASS: {outputs_count} deliverable paths; "
        f"{classified_count} classified non-manifest paths"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
