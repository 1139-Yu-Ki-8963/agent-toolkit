#!/usr/bin/env python3
"""Cross-check every repository skill across its published surfaces."""
import argparse
import json
import pathlib
import re
import shutil
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def validate(root):
    skills = sorted((root / ".claude/skills").glob("*/SKILL.md"))
    names = {path.parent.name for path in skills}
    if not names:
        return False
    readme = (root / "README.md").read_text()
    overview = (root / "reverse-docs-overview.html").read_text()
    manifest = json.loads((root / "shared/references/delivery-reverse-manifest.yml").read_text())
    exclusions_data = json.loads((root / "shared/references/skill-portal-exclusions.json").read_text())
    exclusions = exclusions_data.get("exclusions")
    if exclusions_data.get("schema_version") != 1 or not isinstance(exclusions, dict):
        return False
    portal_owners = {
        row["owner"] for row in manifest["deliverables"]
        if row["classification"] != "template-only"
        and row["publish_status"] == "implemented"
        and any("<" not in output and output.endswith(".html") for output in row["outputs"])
    }
    if set(exclusions) != names - portal_owners or not all(
        isinstance(reason, str) and reason.strip() for reason in exclusions.values()
    ):
        return False
    for skill in skills:
        name = skill.parent.name
        declared = re.search(r"^name:\s*(\S+)\s*$", skill.read_text(), re.M)
        guide = skill.parent / "references" / f"{name}-guide.html"
        readme_link = f".claude/skills/{name}/references/{name}-guide.html"
        if (
            declared is None or declared.group(1) != name
            or not guide.is_file() or readme_link not in readme
            or name not in overview
            or (name not in portal_owners and name not in exclusions)
        ):
            return False
    return True


def self_test():
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary) / "repository"
        shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        if not validate(root):
            return False
        first = sorted((root / ".claude/skills").glob("*/SKILL.md"))[0]
        original = first.read_text()
        first.write_text(original.replace(f"name: {first.parent.name}", "name: broken", 1))
        if validate(root):
            return False
        first.write_text(original)
        guide = first.parent / "references" / f"{first.parent.name}-guide.html"
        broken = guide.with_suffix(".broken")
        guide.rename(broken)
        if validate(root):
            return False
        broken.rename(guide)
        readme = root / "README.md"
        readme.write_text(readme.read_text().replace(
            f".claude/skills/{first.parent.name}/references/{first.parent.name}-guide.html",
            "broken-guide.html", 1,
        ))
        return not validate(root)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if not (self_test() if args.self_test else validate(ROOT)):
        return 1
    print(f"PASS: {len(list((ROOT / '.claude/skills').glob('*/SKILL.md')))} skill surfaces")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
