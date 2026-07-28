#!/usr/bin/env python3
"""Render the catalog-backed leaf-path block in the folder-system document."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOC = ROOT / "shared/references/納品物フォルダ体系.md"
CATALOG = ROOT / "shared/references/delivery-folder-catalog.json"
MANIFEST = ROOT / "shared/references/delivery-reverse-manifest.yml"
START = "<!-- delivery-folder-leaves:start -->"
END = "<!-- delivery-folder-leaves:end -->"


def main():
    catalog = json.loads(CATALOG.read_text())
    manifest = json.loads(MANIFEST.read_text())
    rows = []
    for deliverable in manifest["deliverables"]:
        rows.extend(("deliverable", path) for path in deliverable["outputs"])
    for kind in ("control_artifacts", "assets", "evidence", "screen_deliverables"):
        rows.extend((kind, path) for path in catalog[kind])
    block = "\n".join([
        START,
        "この範囲だけを機械抽出する。上の説明用ツリーと下の履歴・例は対象外。",
        *[f"- {kind} | `{path}`" for kind, path in rows],
        END,
    ])
    text = DOC.read_text()
    if START in text and END in text:
        before, rest = text.split(START, 1)
        _, after = rest.split(END, 1)
        text = before + block + after
    else:
        text = text.replace("## 出典", f"## 機械照合対象の全leaf path\n\n{block}\n\n## 出典")
    DOC.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
