#!/usr/bin/env python3
"""Validate the JSON-compatible YAML delivery-reverse manifest."""
import json
import re
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
OWNER_START = "<!-- delivery-owner-contracts:start -->"
OWNER_END = "<!-- delivery-owner-contracts:end -->"
REQUIRED = {"id", "category", "title", "classification", "owner", "inputs", "outputs", "validator", "prerequisites", "stop_conditions", "publish_status", "evidence_fields"}
CLASSES = {"dedicated-skill", "integrated-skill", "template-only"}
PUBLISH_STATUSES = {"implemented", "planned", "unimplemented"}
RULE_CATEGORIES = {"agent-operation","safety","development-flow","tool-execution","environment","communication","session","ai-configuration","git","placement","naming","architecture","coding","testing","review","security","delivery","documentation","portal","routines"}
SKILL_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

def contained_skill_path(skills_root, owner):
    if not isinstance(owner, str) or not SKILL_NAME.fullmatch(owner):
        return None
    root = skills_root.resolve()
    candidate = skills_root / owner / "SKILL.md"
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    return resolved if root in resolved.parents and resolved.is_file() else None

def owner_path_self_test():
    with tempfile.TemporaryDirectory(prefix="owner-path-contract-") as temporary:
        base = pathlib.Path(temporary)
        skills = base / ".claude/skills"
        valid = skills / "valid-skill"
        external = base / "external"
        valid.mkdir(parents=True)
        external.mkdir()
        (valid / "SKILL.md").write_text("---\nname: valid-skill\n---\n")
        (external / "SKILL.md").write_text("---\nname: escape\n---\n")
        (skills / "escape-skill").symlink_to(external, target_is_directory=True)
        return (
            contained_skill_path(skills, "valid-skill") is not None
            and contained_skill_path(skills, str(external)) is None
            and contained_skill_path(skills, "../external") is None
            and contained_skill_path(skills, "escape-skill") is None
        )

def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    return 1

def main(argv):
    arguments = list(argv[1:])
    if arguments == ["--self-test-owner-paths"]:
        if not owner_path_self_test():
            return fail("owner external/symlink path self-test failed")
        print("PASS: owner paths reject absolute, traversal, and symlink escape")
        return 0
    registry_override = None
    if "--owner-registry" in arguments:
        index = arguments.index("--owner-registry")
        if index + 1 >= len(arguments):
            return fail("--owner-registry requires a path")
        registry_override = pathlib.Path(arguments[index + 1])
        del arguments[index:index + 2]
    if len(arguments) > 1:
        return fail("too many manifest arguments")
    path = pathlib.Path(arguments[0]) if arguments else ROOT / "shared/references/delivery-reverse-manifest.yml"
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"manifest is not JSON-compatible YAML: {exc}")
    if not isinstance(data, dict):
        return fail("manifest root must be an object")
    rule_contract = data.get("rule_evidence_contract")
    test_contract = data.get("test_case_contract")
    if (not isinstance(rule_contract, dict)
            or set(rule_contract.get("categories", [])) != RULE_CATEGORIES
            or rule_contract.get("evidence_entry_fields") != ["statement","evidence_path","excerpt"]
            or rule_contract.get("survey_fields") != ["id","evidence_path","excerpt","evidence_kind","source_sha256"]
            or rule_contract.get("classification_fields") != ["id","evidence_path","excerpt","evidence_kind","source_sha256","primary_category","layer_or_kind","dedupe_key","references"]
            or not isinstance(test_contract, dict)
            or test_contract.get("zero_case_status") != "STOPPED"
            or test_contract.get("zero_case_template") != "shared/templates/test-case-list.html"
            or test_contract.get("output_required") is not True):
        return fail("manifest evidence contracts are missing or inconsistent")
    rows = data.get("deliverables")
    if not isinstance(rows, list) or not rows:
        return fail("deliverables must be a non-empty list")
    owner_registry_path = registry_override or ROOT / "shared/references/delivery-owner-contracts.json"
    try:
        owner_registry = json.loads(owner_registry_path.read_text())
        owner_rows = owner_registry["contracts"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        return fail(f"owner contract registry unavailable: {exc}")
    if (
        owner_registry.get("version") != 2
        or owner_registry.get("effective_contract_fields") != [
            "id", "owner", "title", "inputs", "outputs", "validator",
            "stop_conditions", "failure_return_to",
        ]
        or not isinstance(owner_rows, list)
        or any(not isinstance(value, dict) for value in owner_rows)
    ):
        return fail("owner contract registry schema invalid")
    owner_contracts = {value.get("id"): value for value in owner_rows}
    if len(owner_contracts) != len(owner_rows):
        return fail("owner contract registry has empty or duplicate ids")
    ids, output_owners = set(), {}
    skills_root = ROOT / ".claude/skills"
    enumerated_skills = {
        skill.parent.name
        for skill in skills_root.glob("*/SKILL.md")
        if contained_skill_path(skills_root, skill.parent.name) is not None
    }
    expected_skill_contracts = {}
    manifest_defaults = data.get("owner_contract_defaults")
    registry_defaults = owner_registry.get("defaults")
    if (
        manifest_defaults != {"failure_return_to": "orchestrating-reverse-docs-flow"}
        or registry_defaults != manifest_defaults
    ):
        return fail("owner contract defaults invalid")
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            return fail(f"row {index} must be an object")
        missing = REQUIRED - row.keys()
        if missing:
            return fail(f"row {index} missing {sorted(missing)}")
        if not isinstance(row["id"], str) or not row["id"] or row["id"] in ids:
            return fail(f"row {index} has empty or duplicate id")
        ids.add(row["id"])
        if not isinstance(row["classification"], str) or row["classification"] not in CLASSES:
            return fail(f"{row['id']} has invalid classification")
        if row["publish_status"] not in PUBLISH_STATUSES:
            return fail(f"{row['id']} has invalid publish_status")
        list_fields = ("inputs", "outputs", "prerequisites", "stop_conditions", "evidence_fields")
        if (not isinstance(row["owner"], str) or not isinstance(row["validator"], str)
                or not all(isinstance(row[field], list) and all(isinstance(value, str) for value in row[field]) for field in list_fields)
                or not row["owner"] or not row["outputs"] or not row["validator"] or not row["evidence_fields"]):
            return fail(f"{row['id']} lacks owner/output/validator/evidence fields")
        if row["validator"] != "check-delivery-artifacts.sh":
            return fail(f"{row['id']} references unknown validator")
        if row["classification"] == "template-only":
            owner = ROOT / "shared/templates" / row["owner"]
            if not owner.is_file() or row["inputs"]:
                return fail(f"{row['id']} template-only ownership/purity invalid")
            purity = ROOT / "shared/scripts/validate-template-only.py"
            if subprocess.run([sys.executable, str(purity), str(owner)]).returncode:
                return fail(f"{row['id']} template-only contains fabricated content")
        else:
            owner = contained_skill_path(skills_root, row["owner"])
            if owner is None or row["owner"] not in enumerated_skills:
                return fail(f"{row['id']} owner skill does not exist: {row['owner']}")
            try:
                owner_text = owner.read_text()
            except OSError as exc:
                return fail(f"{row['id']} owner skill unreadable: {exc}")
            declared = re.search(r"^name:\s*(\S+)\s*$", owner_text, re.M)
            if declared is None or declared.group(1) != row["owner"]:
                return fail(f"{row['id']} owner/frontmatter mismatch")
            output_names = [
                pathlib.Path(path.rsplit("/", 1)[-1].replace("<layer>", "")).stem
                for path in row["outputs"]
            ]
            if not any(name in owner_text for name in output_names):
                return fail(f"{row['id']} owner skill contract semantics mismatch")
            expected_skill_contracts.setdefault(row["owner"], []).append({
                key: row[key]
                for key in ("id", "inputs", "outputs", "validator", "stop_conditions")
            } | {"failure_return_to": manifest_defaults["failure_return_to"]})
        expected_owner_contract = {
            key: row[key]
            for key in ("id", "owner", "title", "inputs", "outputs", "validator", "stop_conditions")
        }
        expected_owner_contract["failure_return_to"] = manifest_defaults["failure_return_to"]
        if owner_contracts.get(row["id"]) != expected_owner_contract:
            return fail(f"{row['id']} owner contract registry mismatch")
        for output in row["outputs"]:
            if not output or output in output_owners:
                return fail(f"duplicate or empty output: {output}")
            output_owners[output] = row["id"]
    if set(owner_contracts) != ids:
        return fail("owner contract registry/manifest id mismatch")
    for owner, expected in expected_skill_contracts.items():
        text = (ROOT / ".claude/skills" / owner / "SKILL.md").read_text()
        match = re.search(
            re.escape(OWNER_START) + r"\s*```json\s*(.*?)\s*```\s*" + re.escape(OWNER_END),
            text, re.S,
        )
        try:
            declared_contracts = json.loads(match.group(1)) if match else None
        except json.JSONDecodeError:
            declared_contracts = None
        if declared_contracts != expected:
            return fail(f"{owner} SKILL/manifest owner contracts mismatch")
    inventory = ROOT / "shared/references/納品物フォルダ体系.md"
    try:
        inventory_text = inventory.read_text()
    except OSError as exc:
        return fail(f"folder inventory unavailable: {exc}")
    canonical = [
        "プロジェクト共通/機能要件一覧.md", "プロジェクト共通/帳票要件.md",
        "プロジェクト共通/バッチ要件.md", "プロジェクト共通/外部連携要件.md", "プロジェクト共通/ビジネス概要.md",
        "API/<id>/詳細設計/API詳細設計書.md", "テーブル/<id>/詳細設計/テーブル定義書.md",
        "バッチ/<id>/詳細設計/バッチ詳細設計書.md", "バッチ/<id>/基本設計/バッチ基本設計書.md",
        "帳票/<id>/詳細設計/帳票詳細設計書.md", "帳票/<id>/基本設計/帳票基本設計書.md",
        "外部連携/<id>/詳細設計/外部連携詳細設計書.md", "外部連携/<id>/基本設計/外部連携基本設計書.md",
    ]
    aliases = {"<id>": "<API-ID>", "テーブル/<id>": "table-<テーブルID>", "バッチ/<id>": "batch-<バッチID>", "帳票/<id>": "report-<帳票ID>", "外部連携/<id>": "exif-<連携ID>"}
    for output in canonical:
        inventory_path = output
        for source, target in aliases.items(): inventory_path = inventory_path.replace(source, target)
        filename = inventory_path.rsplit("/", 1)[-1]
        if filename not in inventory_text or output not in output_owners:
            return fail(f"folder inventory/manifest mismatch: {output}")
    portal = ROOT / "shared/samples/index.html"
    try:
        portal_text = portal.read_text()
        block = re.search(
            r'<script type="application/json" id="portal-categories">(.*?)</script>',
            portal_text,
            re.S,
        )
        categories = json.loads(block.group(1)) if block else None
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"portal inventory unavailable: {exc}")
    if not isinstance(categories, list):
        return fail("portal-categories must be a list")
    cards = {}
    for category in categories:
        if not isinstance(category, dict) or not isinstance(category.get("tools"), list):
            return fail("portal category/tool schema invalid")
        for tool in category["tools"]:
            if not isinstance(tool, dict):
                return fail("portal tool must be an object")
            title, href = tool.get("title"), tool.get("href")
            if not isinstance(title, str) or not isinstance(href, str):
                return fail("portal tool title/href invalid")
            output = href.removeprefix("./")
            if output in cards:
                return fail(f"duplicate portal href: {output}")
            cards[output] = title
    manifest_cards = {}
    for row in rows:
        if row["publish_status"] != "implemented":
            continue
        for output in row["outputs"]:
            if "<" not in output and output.endswith(".html"):
                sample = ROOT / "shared/samples" / output
                if not sample.is_file():
                    return fail(f"concrete HTML output has no sample: {output}")
                manifest_cards[output] = row["title"]
    if cards != manifest_cards:
        missing = sorted(set(cards) - set(manifest_cards))
        extra = sorted(set(manifest_cards) - set(cards))
        wrong = sorted(path for path in set(cards) & set(manifest_cards)
                       if cards[path] != manifest_cards[path])
        return fail(f"portal/manifest mismatch missing={missing} extra={extra} title={wrong}")
    print(f"PASS: {len(rows)} deliverables; {len(output_owners)} unique outputs")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
