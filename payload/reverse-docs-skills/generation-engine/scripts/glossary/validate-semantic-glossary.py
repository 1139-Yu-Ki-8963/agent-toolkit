#!/usr/bin/env python3
"""Validate semantic glossary YAML documents against contract v0.1.6."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


CONTRACT_VERSION = "0.1.6"
SCHEMA_VERSION = "1.0.0"
KINDS = ("glossary", "proposal", "change")
SEMANTIC_KEY = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
HASH = re.compile(r"^[0-9a-f]{12,}$")
GENERIC_KEYS = {"id", "key", "item", "data", "info", "value", "master", "term"}
GENERIC_SEQUENCE = re.compile(r"^(?:id|key|item|data|info|value|master|term)_?0*[0-9]+$")
STRUCTURAL_RELATIONS = {"broader_than", "narrower_than", "part_of", "has_part", "replaced_by"}
REGISTRY_KIND_MARKERS = {
    "glossary": {"schema_version", "content_version", "scope_catalog", "terms", "default_language"},
    "proposal": {"proposal_schema_version", "merge_key", "proposed_term", "proposal", "merged_revision"},
    "change": {"change_type", "affected_term_keys", "approved_by", "applied_at", "applied_revision", "after_hash"},
}
SEMANTIC_REGISTRY_HINTS = {
    "glossary_key",
    "proposal_key",
    "change_key",
    "target_glossary_key",
    "base_content_version",
    "target_content_version",
    "stewardship",
    "provenance",
    "representations",
    "lifecycle",
    *set().union(*REGISTRY_KIND_MARKERS.values()),
}
ALLOWED_TRANSITIONS = {
    (None, "detected"): {"analyzer"},
    ("detected", "needs_review"): {"maintainer"},
    ("needs_review", "changes_requested"): {"steward", "business_approver", "technical_approver"},
    ("needs_review", "rejected"): {"steward", "business_approver", "technical_approver"},
    ("needs_review", "deferred"): {"steward", "business_approver", "technical_approver"},
    ("changes_requested", "needs_review"): {"steward"},
    ("needs_review", "approved"): {"maintainer"},
    ("approved", "merged"): {"maintainer"},
    ("approved", "needs_review"): {"maintainer"},
}


class UnavailableError(RuntimeError):
    """Raised when validation cannot be completed."""

    def __init__(self, message: str, code: str = "SGD_UNAVAILABLE") -> None:
        super().__init__(message)
        self.code = code


class ReportTargetCollision(UnavailableError):
    """Raised when writing a report could replace an input source."""


class FindingCollector:
    def __init__(self) -> None:
        self.items: list[dict[str, Any]] = []

    def add(
        self,
        severity: str,
        code: str,
        path: str,
        message: str,
        related_refs: Iterable[str] = (),
    ) -> None:
        self.items.append(
            {
                "severity": severity,
                "code": code,
                "path": path,
                "message": message,
                "relatedRefs": sorted(set(related_refs)),
            }
        )

    def sorted(self) -> list[dict[str, Any]]:
        return sorted(
            self.items,
            key=lambda item: (
                item["severity"],
                item["code"],
                item["path"],
                item["message"],
            ),
        )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", required=True, choices=KINDS)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args(argv)


def dependency_modules() -> tuple[Any, Any, Any, Any, Any]:
    try:
        import yaml
        from jsonschema import Draft202012Validator, FormatChecker
        from referencing import Registry, Resource
    except ImportError as error:
        raise UnavailableError(
            f"required dependency is unavailable: {error.name}", "SGD_DEPENDENCY"
        ) from error
    # 素直な形(`>= 3.10`等の範囲比較)を避け、マイナーバージョンの完全一致を要求する。
    # このvalidatorはSKILL.md/README.mdの手順どおりglossary/.venv配下の特定の
    # Pythonビルド(python3.13 -m venv)で動かす設計であり、範囲比較にすると
    # 想定外のPythonマイナーバージョン(stdlibの挙動がマイナーバージョン間で
    # 変わりうる)でも通過してしまう。この具体的な不一致事例の実測・記録は
    # この作業時点では見つからない(実測値なし)。
    if sys.version_info[:2] != (3, 13):
        raise UnavailableError(
            f"Python 3.13 is required; found {sys.version_info.major}.{sys.version_info.minor}",
            "SGD_DEPENDENCY",
        )
    def version_tuple(value: str) -> tuple[int, ...]:
        return tuple(int(part) for part in re.findall(r"[0-9]+", value)[:3])

    if not ((6,) <= version_tuple(yaml.__version__) < (7,)):
        raise UnavailableError(
            f"PyYAML>=6,<7 is required; found {yaml.__version__}", "SGD_DEPENDENCY"
        )
    from importlib.metadata import version

    jsonschema_version = version("jsonschema")
    if not ((4, 23) <= version_tuple(jsonschema_version) < (5,)):
        raise UnavailableError(
            f"jsonschema>=4.23,<5 is required; found {jsonschema_version}",
            "SGD_DEPENDENCY",
        )
    return yaml, Draft202012Validator, FormatChecker, Registry, Resource


def yaml_loader(yaml: Any) -> type:
    class StringSafeLoader(yaml.SafeLoader):
        pass

    for first_char, resolvers in list(StringSafeLoader.yaml_implicit_resolvers.items()):
        StringSafeLoader.yaml_implicit_resolvers[first_char] = [
            resolver
            for resolver in resolvers
            if resolver[0] != "tag:yaml.org,2002:timestamp"
        ]
    return StringSafeLoader


def load_yaml_document(path: Path, yaml: Any) -> Any:
    if not path.is_file():
        raise UnavailableError(f"input is not a readable file: {path}", "SGD_SCAN_UNAVAILABLE")
    try:
        text = path.read_text(encoding="utf-8")
        documents = list(yaml.load_all(text, Loader=yaml_loader(yaml)))
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        raise UnavailableError(f"cannot parse YAML {path}: {error}", "SGD_PARSE") from error
    if len(documents) != 1:
        raise UnavailableError(
            f"YAML must contain exactly one document: {path}", "SGD_PARSE"
        )
    return documents[0]


def load_yaml(path: Path, yaml: Any) -> dict[str, Any]:
    document = load_yaml_document(path, yaml)
    if not isinstance(document, dict):
        raise UnavailableError(f"YAML root must be an object: {path}", "SGD_PARSE")
    return document


def schema_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "schemas" / "semantic-glossary" / SCHEMA_VERSION


def load_schemas(yaml: Any, Registry: Any, Resource: Any) -> tuple[dict[str, dict[str, Any]], Any]:
    schemas: dict[str, dict[str, Any]] = {}
    registry = Registry()
    for kind in (*KINDS, "validation-report"):
        path = schema_dir() / f"{kind}.schema.yaml"
        schema = load_yaml(path, yaml)
        schemas[kind] = schema
        try:
            resource = Resource.from_contents(schema)
            registry = registry.with_resource(schema["$id"], resource)
        except Exception as error:
            raise UnavailableError(
                f"cannot load schema {path}: {error}", "SGD_INTERNAL"
            ) from error
    return schemas, registry


def json_path(parts: Iterable[Any]) -> str:
    result = "$"
    for part in parts:
        if isinstance(part, int):
            result += f"[{part}]"
        else:
            result += f".{part}"
    return result


def validate_schema(
    document: dict[str, Any],
    schema: dict[str, Any],
    registry: Any,
    Draft202012Validator: Any,
    FormatChecker: Any,
    findings: FindingCollector,
    source_ref: str | None = None,
) -> None:
    try:
        validator = Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        )
        errors = sorted(validator.iter_errors(document), key=lambda error: list(error.absolute_path))
    except Exception as error:
        raise UnavailableError(
            f"schema validation failed internally: {error}", "SGD_INTERNAL"
        ) from error
    for error in errors:
        path = json_path(error.absolute_path)
        if source_ref is not None:
            path = f"{source_ref}:{path}"
        findings.add(
            "error",
            "SGS_SCHEMA_VIOLATION",
            path,
            error.message,
            [source_ref] if source_ref is not None else [],
        )


def semver(value: Any) -> tuple[int, int, int] | None:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value):
        return None
    return tuple(int(part) for part in value.split("."))  # type: ignore[return-value]


def instant(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def proposal_content_hash(document: dict[str, Any]) -> str:
    """Hash every semantic input covered by a proposal approval decision."""
    proposal = document.get("proposal")
    payload = proposal if isinstance(proposal, dict) else {}
    snapshot = {
        "proposal_key": document.get("proposal_key"),
        "proposal_operation": document.get("proposal_operation"),
        "target_glossary_key": document.get("target_glossary_key"),
        "base_content_version": document.get("base_content_version"),
        "target_content_version": document.get("target_content_version"),
        "merge_key": document.get("merge_key"),
        "proposed_term": document.get("proposed_term"),
        "extracted_facts": payload.get("extracted_facts"),
        "inferences": payload.get("inferences"),
        "evidence": payload.get("evidence"),
        "confidence": payload.get("confidence"),
        "detected_by": payload.get("detected_by"),
    }
    canonical = json.dumps(
        snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(canonical).hexdigest()}"


def canonical_hash(value: Any) -> str:
    """Hash a JSON-compatible value using the contract canonical encoding."""
    canonical = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(canonical).hexdigest()}"


def semantic_term_snapshot(term: dict[str, Any]) -> dict[str, Any]:
    """Remove publication-only attestations from an approved semantic term."""
    snapshot = json.loads(json.dumps(term, ensure_ascii=False))
    provenance = snapshot.get("provenance")
    if isinstance(provenance, dict):
        for field in (
            "publication_status",
            "decision_ref",
            "change_ref",
        ):
            provenance.pop(field, None)
    return snapshot


def applied_terms_hash(terms: list[dict[str, Any]]) -> str:
    """Hash the complete applied state of affected terms in key order."""
    snapshots = [semantic_term_snapshot(term) for term in terms]
    snapshots.sort(key=lambda term: str(term.get("key")))
    return canonical_hash(snapshots)


def referenced_key(value: Any, prefix: str) -> str | None:
    if not isinstance(value, str) or not value.startswith(prefix):
        return None
    key = value[len(prefix):]
    return key if SEMANTIC_KEY.fullmatch(key) else None


def normalized_form(value: str) -> str:
    return "".join(unicodedata.normalize("NFKC", value).casefold().split())


def key_is_meaningless(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    return (
        value in GENERIC_KEYS
        or bool(GENERIC_SEQUENCE.fullmatch(value))
        or bool(UUID.fullmatch(value))
        or bool(HASH.fullmatch(value))
    )


def check_key(value: Any, path: str, findings: FindingCollector) -> None:
    if isinstance(value, str) and SEMANTIC_KEY.fullmatch(value) and key_is_meaningless(value):
        findings.add("error", "SGK_MEANINGLESS", path, f"key does not express a stable concept: {value}")


def glossary_keys(document: dict[str, Any]) -> list[tuple[Any, str]]:
    values: list[tuple[Any, str]] = [(document.get("glossary_key"), "$.glossary_key")]
    for index, scope in enumerate(document.get("scope_catalog", [])):
        if isinstance(scope, dict):
            values.append((scope.get("key"), f"$.scope_catalog[{index}].key"))
    for index, term in enumerate(document.get("terms", [])):
        if not isinstance(term, dict):
            continue
        values.append((term.get("key"), f"$.terms[{index}].key"))
        for tag_index, tag in enumerate(term.get("tags", [])):
            values.append((tag, f"$.terms[{index}].tags[{tag_index}]"))
    return values


def proposal_keys(document: dict[str, Any]) -> list[tuple[Any, str]]:
    values = [
        (document.get("proposal_key"), "$.proposal_key"),
        (document.get("target_glossary_key"), "$.target_glossary_key"),
        (document.get("merge_key"), "$.merge_key"),
    ]
    proposed = document.get("proposed_term")
    if isinstance(proposed, dict):
        values.append((proposed.get("key"), "$.proposed_term.key"))
    return values


def change_keys(document: dict[str, Any]) -> list[tuple[Any, str]]:
    values = [
        (document.get("change_key"), "$.change_key"),
        (document.get("glossary_key"), "$.glossary_key"),
        (document.get("proposal_key"), "$.proposal_key"),
    ]
    values.extend(
        (value, f"$.affected_term_keys[{index}]")
        for index, value in enumerate(document.get("affected_term_keys", []))
    )
    return values


def load_registry(
    path: Path | None,
    input_path: Path,
    yaml: Any,
    report_path: Path | None = None,
) -> dict[str, list[tuple[Path, dict[str, Any]]]]:
    if path is None:
        return {kind: [] for kind in KINDS}
    if not path.exists():
        raise UnavailableError(
            f"registry cannot be scanned: {path}", "SGD_SCAN_UNAVAILABLE"
        )
    if path.is_file():
        candidates = [path]
    elif path.is_dir():
        try:
            candidates = sorted(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file() and candidate.suffix.lower() in {".yaml", ".yml"}
            )
        except OSError as error:
            raise UnavailableError(
                f"registry cannot be scanned: {path}: {error}",
                "SGD_SCAN_UNAVAILABLE",
            ) from error
    else:
        raise UnavailableError(
            f"registry is neither a file nor directory: {path}",
            "SGD_SCAN_UNAVAILABLE",
        )
    loaded: dict[str, list[tuple[Path, dict[str, Any]]]] = {
        kind: [] for kind in KINDS
    }
    for candidate in candidates:
        if candidate.resolve() == input_path.resolve():
            continue
        if report_path is not None and paths_refer_to_same_file(candidate, report_path):
            raise ReportTargetCollision(
                f"--report must not resolve to a registry source file: {candidate}",
                "SGD_REPORT_WRITE",
            )
        document = load_yaml_document(candidate, yaml)
        if not isinstance(document, dict):
            continue
        document_keys = set(document)
        matches = [
            kind
            for kind, markers in REGISTRY_KIND_MARKERS.items()
            if document_keys & markers
        ]
        if len(matches) > 1:
            raise UnavailableError(
                f"registry document has ambiguous semantic kind: {candidate}",
                "SGD_PARSE",
            )
        if matches:
            loaded[matches[0]].append((candidate, document))
        elif document_keys & SEMANTIC_REGISTRY_HINTS:
            raise UnavailableError(
                f"registry document appears semantic but its kind cannot be determined: {candidate}",
                "SGD_PARSE",
            )
    return loaded


def detect_cycle(graph: dict[str, set[str]]) -> list[str] | None:
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        state[node] = 1
        stack.append(node)
        for target in sorted(graph.get(node, set())):
            if target == node:
                return [node, node]
            if state.get(target, 0) == 0:
                cycle = visit(target)
                if cycle:
                    return cycle
            elif state.get(target) == 1:
                start = stack.index(target)
                return stack[start:] + [target]
        stack.pop()
        state[node] = 2
        return None

    for node in sorted(graph):
        if state.get(node, 0) == 0:
            cycle = visit(node)
            if cycle:
                return cycle
    return None


def validate_glossaries(
    current: dict[str, Any],
    registry_documents: list[tuple[Path, dict[str, Any]]],
    findings: FindingCollector,
    *,
    check_glossary_uniqueness: bool = True,
    require_publishable_terms: bool = True,
    registry_proposals: list[tuple[Path, dict[str, Any]]] | None = None,
    registry_changes: list[tuple[Path, dict[str, Any]]] | None = None,
    registry_requested: bool = False,
) -> dict[str, dict[str, Any]]:
    documents = [(Path("<input>"), current), *registry_documents]
    terms_by_key: dict[str, dict[str, Any]] = {}
    term_origins: defaultdict[str, list[str]] = defaultdict(list)
    glossary_origins: defaultdict[str, list[str]] = defaultdict(list)
    catalog_keys: set[str] = set()
    catalog_graph: dict[str, set[str]] = defaultdict(set)

    def located(source: Path, path: str) -> str:
        return path if source.name == "<input>" else f"{source}:{path}"

    for source, document in documents:
        for value, path in glossary_keys(document):
            check_key(value, located(source, path), findings)
        glossary_key = document.get("glossary_key")
        if isinstance(glossary_key, str):
            glossary_origins[glossary_key].append(located(source, "$.glossary_key"))
        for index, entry in enumerate(document.get("scope_catalog", [])):
            if not isinstance(entry, dict) or not isinstance(entry.get("key"), str):
                continue
            key = entry["key"]
            catalog_keys.add(key)
            parent = entry.get("parent_key")
            if isinstance(parent, str):
                catalog_graph[key].add(parent)
        for index, term in enumerate(document.get("terms", [])):
            if not isinstance(term, dict) or not isinstance(term.get("key"), str):
                continue
            key = term["key"]
            origin = located(source, f"$.terms[{index}]")
            term_origins[key].append(origin)
            terms_by_key.setdefault(key, term)

    if check_glossary_uniqueness:
        for key, origins in sorted(glossary_origins.items()):
            if len(origins) > 1:
                findings.add(
                    "error",
                    "SGK_DUPLICATE_GLOSSARY",
                    "$.glossary_key",
                    f"glossary key is duplicated: {key}",
                    origins,
                )
    for key, origins in sorted(term_origins.items()):
        if len(origins) > 1:
            findings.add("error", "SGK_DUPLICATE", "$.terms", f"term key is duplicated: {key}", origins)

    allowed_forms: defaultdict[str, list[tuple[str, str]]] = defaultdict(list)
    forbidden_forms: defaultdict[str, list[tuple[str, str]]] = defaultdict(list)
    relation_graph: dict[str, set[str]] = defaultdict(set)
    replacement_graph: dict[str, set[str]] = defaultdict(set)

    for source, document in documents:
        content_version = semver(document.get("content_version"))
        for index, term in enumerate(document.get("terms", [])):
            if not isinstance(term, dict) or not isinstance(term.get("key"), str):
                continue
            key = term["key"]
            base = located(source, f"$.terms[{index}]")
            provenance = term.get("provenance")
            provenance = provenance if isinstance(provenance, dict) else {}
            publication_status = provenance.get("publication_status")
            if publication_status == "approved" and "legacy_source_ref" in provenance:
                findings.add(
                    "error",
                    "SGP_APPROVED_LEGACY_SOURCE_FORBIDDEN",
                    f"{base}.provenance.legacy_source_ref",
                    "approved term must not retain a legacy migration source marker",
                )
            if require_publishable_terms:
                stewardship = term.get("stewardship")
                stewardship = stewardship if isinstance(stewardship, dict) else {}
                if publication_status == "approved":
                    approvers = stewardship.get("approvers")
                    if (
                        not isinstance(approvers, list)
                        or len(set(approvers)) < 2
                        or not provenance.get("decision_ref")
                        or not provenance.get("change_ref")
                    ):
                        findings.add(
                            "error",
                            "SGP_PUBLICATION_APPROVAL_INCOMPLETE",
                            f"{base}.provenance",
                            "approved publication requires two approvers plus decision_ref and change_ref",
                        )
                elif publication_status == "legacy_migrated":
                    findings.add(
                        "review_required",
                        "SGP_LEGACY_TERM_REVIEW_REQUIRED",
                        f"{base}.provenance.publication_status",
                        "legacy-migrated term must be approved through a change before portal publication",
                    )
                else:
                    findings.add(
                        "review_required",
                        "SGP_PUBLICATION_APPROVAL_REQUIRED",
                        f"{base}.provenance.publication_status",
                            "term is not explicitly approved for portal publication",
                        )
            label_field = "term_ja" if isinstance(term.get("term_ja"), str) else "label"
            label = term.get(label_field)
            if isinstance(label, str):
                allowed_forms[normalized_form(label)].append((key, f"{base}.{label_field}"))
                definition = term.get("definition")
                if isinstance(definition, str) and normalized_form(definition) in {
                    normalized_form(f"{label}を表す用語"),
                    normalized_form(f"{label}を示す用語"),
                }:
                    findings.add("warning", "SGS_DEFINITION_TAUTOLOGY", f"{base}.definition", "definition only restates the representative label")
            for alias_index, alias in enumerate(term.get("aliases", [])):
                if isinstance(alias, dict) and isinstance(alias.get("value"), str):
                    allowed_forms[normalized_form(alias["value"])].append((key, f"{base}.aliases[{alias_index}].value"))
            for forbidden_index, forbidden in enumerate(term.get("forbidden_terms", [])):
                if not isinstance(forbidden, dict):
                    continue
                value = forbidden.get("value")
                replacement = forbidden.get("replacement_key")
                if isinstance(value, str):
                    forbidden_forms[normalized_form(value)].append((key, f"{base}.forbidden_terms[{forbidden_index}].value"))
                if isinstance(replacement, str) and replacement not in terms_by_key:
                    findings.add("error", "SGR_MISSING", f"{base}.forbidden_terms[{forbidden_index}].replacement_key", f"replacement term does not exist: {replacement}", [replacement])

            scope = term.get("scope")
            if isinstance(scope, dict):
                for field in ("includes", "excludes"):
                    for scope_index, scope_key in enumerate(scope.get(field, [])):
                        if isinstance(scope_key, str) and scope_key not in catalog_keys:
                            findings.add("error", "SGR_MISSING", f"{base}.scope.{field}[{scope_index}]", f"scope key does not exist: {scope_key}", [scope_key])

            lifecycle = term.get("lifecycle")
            if isinstance(lifecycle, dict):
                status = lifecycle.get("status")
                if isinstance(term.get("status"), str) and term["status"] != status:
                    findings.add("error", "SGL_STATUS_MISMATCH", f"{base}.status", "status must match lifecycle.status")
                introduced = semver(lifecycle.get("introduced_in"))
                if introduced and content_version and introduced > content_version:
                    findings.add("error", "SGV_LIFECYCLE_VERSION", f"{base}.lifecycle.introduced_in", "introduced_in exceeds glossary content_version")
                replacement = lifecycle.get("replaced_by")
                if isinstance(replacement, str):
                    replacement_graph[key].add(replacement)
                    if replacement not in terms_by_key:
                        findings.add("error", "SGR_MISSING", f"{base}.lifecycle.replaced_by", f"replacement term does not exist: {replacement}", [replacement])
                if status == "active" and any(lifecycle.get(field) is not None for field in ("deprecated_in", "retired_in", "migration_deadline", "replaced_by", "reason")):
                    findings.add("error", "SGL_ACTIVE_HAS_RETIREMENT", f"{base}.lifecycle", "active term must not contain retirement values")
                if status == "deprecated":
                    deprecated = semver(lifecycle.get("deprecated_in"))
                    if introduced and deprecated and introduced > deprecated:
                        findings.add("error", "SGL_VERSION_ORDER", f"{base}.lifecycle.deprecated_in", "deprecated_in precedes introduced_in")
                    if content_version and deprecated and deprecated > content_version:
                        findings.add("error", "SGV_LIFECYCLE_VERSION", f"{base}.lifecycle.deprecated_in", "deprecated_in exceeds glossary content_version")
                if status == "retired":
                    retired = semver(lifecycle.get("retired_in"))
                    if introduced and retired and introduced > retired:
                        findings.add("error", "SGL_VERSION_ORDER", f"{base}.lifecycle.retired_in", "retired_in precedes introduced_in")
                    if content_version and retired and retired > content_version:
                        findings.add("error", "SGV_LIFECYCLE_VERSION", f"{base}.lifecycle.retired_in", "retired_in exceeds glossary content_version")

            for relation_index, relation in enumerate(term.get("relations", [])):
                if not isinstance(relation, dict):
                    continue
                target = relation.get("target_key")
                relation_type = relation.get("type")
                if isinstance(target, str):
                    if target not in terms_by_key:
                        findings.add("error", "SGR_MISSING", f"{base}.relations[{relation_index}].target_key", f"relation target does not exist: {target}", [target])
                    if target == key:
                        findings.add("error", "SGR_CYCLE", f"{base}.relations[{relation_index}]", f"term cannot relate to itself: {key}", [key])
                    elif relation_type in STRUCTURAL_RELATIONS:
                        relation_graph[key].add(target)

    for form, locations in sorted(allowed_forms.items()):
        if len(locations) > 1:
            findings.add("review_required", "SGK_ALLOWED_FORM_COLLISION", locations[0][1], "label or alias has a normalized collision", [location for _, location in locations])
        if form in forbidden_forms:
            related = [location for _, location in locations + forbidden_forms[form]]
            findings.add("error", "SGK_FORBIDDEN_FORM_COLLISION", locations[0][1], "allowed and forbidden forms collide after normalization", related)

    for graph, label in ((catalog_graph, "scope parent"), (relation_graph, "relation"), (replacement_graph, "replacement")):
        cycle = detect_cycle(graph)
        if cycle:
            findings.add("error", "SGR_CYCLE", "$", f"{label} cycle detected: {' -> '.join(cycle)}", cycle)

    for source, document in documents:
        catalog = [entry for entry in document.get("scope_catalog", []) if isinstance(entry, dict)]
        local_keys = [entry.get("key") for entry in catalog if isinstance(entry.get("key"), str)]
        for key, count in Counter(local_keys).items():
            if count > 1:
                findings.add("error", "SGK_DUPLICATE", located(source, "$.scope_catalog"), f"scope key is duplicated: {key}")
        for index, entry in enumerate(catalog):
            parent = entry.get("parent_key")
            if isinstance(parent, str) and parent not in catalog_keys:
                findings.add("error", "SGR_MISSING", located(source, f"$.scope_catalog[{index}].parent_key"), f"parent scope does not exist: {parent}", [parent])
        root_scope = document.get("scope")
        if isinstance(root_scope, dict):
            for field in ("includes", "excludes"):
                for index, scope_key in enumerate(root_scope.get(field, [])):
                    if isinstance(scope_key, str) and scope_key not in catalog_keys:
                        findings.add("error", "SGR_MISSING", located(source, f"$.scope.{field}[{index}]"), f"scope key does not exist: {scope_key}", [scope_key])
    if require_publishable_terms:
        validate_publication_links(
            current,
            registry_documents,
            registry_proposals or [],
            registry_changes or [],
            findings,
            registry_requested=registry_requested,
        )
    return terms_by_key


def validate_approval_history(
    events: Any,
    expected_final_states: set[str],
    findings: FindingCollector,
    *,
    path: str,
    missing_code: str,
    history_code: str,
    final_code: str,
) -> None:
    if not isinstance(events, list) or not events:
        findings.add(
            "error",
            missing_code,
            path,
            "a complete approval event history is required",
        )
        return
    previous: str | None = None
    previous_time: dt.datetime | None = None
    for index, event in enumerate(events):
        if not isinstance(event, dict):
            continue
        transition = (event.get("from"), event.get("to"))
        if (
            event.get("from") != previous
            or event.get("actor_role") not in ALLOWED_TRANSITIONS.get(transition, set())
        ):
            findings.add(
                "error",
                history_code,
                f"{path}[{index}]",
                f"invalid approval transition or actor role: {transition[0]} -> {transition[1]}",
            )
        if isinstance(event.get("to"), str):
            previous = event["to"]
        event_time = instant(event.get("occurred_at"))
        if event_time is not None and previous_time is not None and event_time < previous_time:
            findings.add(
                "error",
                "SGP_EVENT_TIME_ORDER",
                f"{path}[{index}].occurred_at",
                "approval event timestamps must be monotonically nondecreasing",
            )
        if event_time is not None:
            previous_time = event_time
    if previous not in expected_final_states:
        findings.add(
            "error",
            final_code,
            path,
            f"approval event history ends at {previous}, expected one of {sorted(expected_final_states)}",
        )


def validate_proposal(
    document: dict[str, Any],
    registry_documents: list[tuple[Path, dict[str, Any]]],
    findings: FindingCollector,
    *,
    registry_requested: bool,
) -> None:
    for value, path in proposal_keys(document):
        check_key(value, path, findings)
    base = semver(document.get("base_content_version"))
    target = semver(document.get("target_content_version"))
    if base and target and target <= base:
        findings.add("error", "SGV_VERSION_ORDER", "$.target_content_version", "target_content_version must exceed base_content_version")
    proposal = document.get("proposal")
    if not isinstance(proposal, dict):
        return
    confidence = proposal.get("confidence")
    if isinstance(confidence, dict) and isinstance(confidence.get("score"), (int, float)):
        score = confidence["score"]
        expected = "high" if score >= 0.8 else "medium" if score >= 0.5 else "low"
        if confidence.get("level") != expected:
            findings.add("error", "SGP_CONFIDENCE_LEVEL", "$.proposal.confidence.level", f"confidence level must be {expected} for score {score}")
    evidence = [item for item in proposal.get("evidence", []) if isinstance(item, dict)]
    evidence_refs = [item.get("ref") for item in evidence if isinstance(item.get("ref"), str)]
    for ref, count in Counter(evidence_refs).items():
        if count > 1:
            findings.add(
                "error",
                "SGP_DUPLICATE_EVIDENCE_REF",
                "$.proposal.evidence",
                f"evidence ref must be unique within a proposal: {ref}",
                [ref],
            )
    evidence_ref_set = set(evidence_refs)
    for index, fact in enumerate(proposal.get("extracted_facts", [])):
        if isinstance(fact, dict) and fact.get("evidence_ref") not in evidence_ref_set:
            findings.add(
                "error",
                "SGP_EVIDENCE_REF_MISSING",
                f"$.proposal.extracted_facts[{index}].evidence_ref",
                f"extracted fact evidence_ref does not resolve within proposal.evidence: {fact.get('evidence_ref')}",
                [str(fact.get("evidence_ref"))],
            )
    approval = proposal.get("approval")
    if not isinstance(approval, dict):
        return
    status = approval.get("status")
    events = approval.get("events", [])
    validate_approval_history(
        events,
        {status} if isinstance(status, str) else set(),
        findings,
        path="$.proposal.approval.events",
        missing_code="SGP_EVENT_REQUIRED",
        history_code="SGP_INVALID_TRANSITION",
        final_code="SGP_STATE_HISTORY_MISMATCH",
    )
    if status in {"rejected", "deferred", "changes_requested"} and not approval.get("decision_reason"):
        findings.add("error", "SGP_DECISION_REASON_REQUIRED", "$.proposal.approval.decision_reason", f"decision_reason is required for {status}")
    reviewers = [reviewer for reviewer in approval.get("reviewers", []) if isinstance(reviewer, dict)]
    if status in {"approved", "merged"}:
        decision_reason = approval.get("decision_reason")
        if not isinstance(decision_reason, str) or not decision_reason.strip():
            findings.add(
                "error",
                "SGP_DECISION_REASON_REQUIRED",
                "$.proposal.approval.decision_reason",
                "decision_reason must be nonblank after approval",
            )
        approved_roles = {reviewer.get("role") for reviewer in reviewers if reviewer.get("decision") == "approved"}
        if approved_roles != {"business_approver", "technical_approver"}:
            findings.add("error", "SGP_TWO_PARTY_APPROVAL_REQUIRED", "$.proposal.approval.reviewers", "approved or merged proposal requires approved business and technical roles")
        if not approval.get("reviewed_at"):
            findings.add("error", "SGP_REVIEWED_AT_REQUIRED", "$.proposal.approval.reviewed_at", "reviewed_at is required after approval")
        reviewed_at = instant(approval.get("reviewed_at"))
        reviewer_times = [
            instant(reviewer.get("decided_at"))
            for reviewer in reviewers
        ]
        if reviewed_at is not None and any(
            reviewer_time is not None and reviewer_time > reviewed_at
            for reviewer_time in reviewer_times
        ):
            findings.add(
                "error",
                "SGP_REVIEW_TIME_ORDER",
                "$.proposal.approval.reviewed_at",
                "all approved reviewer decisions must occur at or before reviewed_at",
            )
        approval_event_times = [
            instant(event.get("occurred_at"))
            for event in events
            if isinstance(event, dict) and event.get("to") in {"approved", "merged"}
        ]
        if reviewed_at is not None and any(
            event_time is not None and reviewed_at > event_time
            for event_time in approval_event_times
        ):
            findings.add(
                "error",
                "SGP_REVIEW_TIME_ORDER",
                "$.proposal.approval.reviewed_at",
                "reviewed_at must occur at or before approval and merge events",
            )
    if status == "merged" and not document.get("merged_revision"):
        findings.add("error", "SGP_MERGED_REVISION_REQUIRED", "$.merged_revision", "merged proposal requires merged_revision")
    if status != "merged" and document.get("merged_revision"):
        findings.add("error", "SGP_MERGED_REVISION_UNEXPECTED", "$.merged_revision", "merged_revision is only allowed for merged status")

    glossary_key = document.get("target_glossary_key")
    target_documents = [
        (path, registry)
        for path, registry in registry_documents
        if registry.get("glossary_key") == glossary_key
    ]
    if registry_requested and not target_documents:
        findings.add(
            "error",
            "SGR_TARGET_GLOSSARY_MISSING",
            "$.target_glossary_key",
            f"target glossary does not exist in registry: {glossary_key}",
            [str(glossary_key)],
        )
    for path, registry in target_documents:
        if status == "merged":
            if registry.get("content_version") != document.get("target_content_version"):
                findings.add("review_required", "SGP_STALE_BASE", "$.target_content_version", "merged proposal target_content_version differs from the target glossary", [str(path)])
        elif registry.get("content_version") != document.get("base_content_version"):
            findings.add("review_required", "SGP_STALE_BASE", "$.base_content_version", "proposal base_content_version differs from the target glossary", [str(path)])
    proposed_term = document.get("proposed_term")
    if isinstance(proposed_term, dict):
        target_document = target_documents[0][1] if target_documents else {}
        proposed_key = proposed_term.get("key")
        proposal_operation = document.get("proposal_operation")
        target_term_exists = any(
            isinstance(term, dict) and term.get("key") == proposed_key
            for _, registry_document in target_documents
            for term in registry_document.get("terms", [])
        )
        if registry_requested and proposal_operation is None:
            findings.add(
                "review_required",
                "SGP_OPERATION_REQUIRED",
                "$.proposal_operation",
                "proposal_operation is required for deterministic add/update validation when a registry is used",
            )
        elif (
            registry_requested
            and proposal_operation == "add"
            and target_term_exists
            and status != "merged"
        ):
            findings.add(
                "error",
                "SGP_ADD_TARGET_EXISTS",
                "$.proposed_term.key",
                f"add proposal target already exists: {proposed_key}",
                [str(proposed_key)],
            )
        elif (
            registry_requested
            and proposal_operation == "add"
            and status == "merged"
            and not target_term_exists
        ):
            findings.add(
                "error",
                "SGP_MERGED_TARGET_MISSING",
                "$.proposed_term.key",
                f"merged add proposal target is absent from the applied glossary: {proposed_key}",
                [str(proposed_key)],
            )
        elif registry_requested and proposal_operation == "update" and not target_term_exists:
            findings.add(
                "error",
                "SGP_UPDATE_TARGET_MISSING",
                "$.proposed_term.key",
                f"update proposal target does not exist: {proposed_key}",
                [str(proposed_key)],
            )
        comparison_registry: list[tuple[Path, dict[str, Any]]] = []
        for path, registry_document in registry_documents:
            is_target_glossary = registry_document.get("glossary_key") == glossary_key
            target_terms = registry_document.get("terms", [])
            target_contains_proposed_key = any(
                isinstance(term, dict) and term.get("key") == proposed_key
                for term in target_terms
            )
            if (
                is_target_glossary
                and target_contains_proposed_key
                and (proposal_operation == "update" or status == "merged")
            ):
                filtered_document = dict(registry_document)
                filtered_document["terms"] = [
                    term
                    for term in target_terms
                    if not (isinstance(term, dict) and term.get("key") == proposed_key)
                ]
                comparison_registry.append((path, filtered_document))
            else:
                comparison_registry.append((path, registry_document))
        proposed_scope = proposed_term.get("scope", {})
        fallback_scope_keys = sorted(
            {
                key
                for field in ("includes", "excludes")
                for key in (
                    proposed_scope.get(field, [])
                    if isinstance(proposed_scope, dict)
                    else []
                )
                if isinstance(key, str)
            }
        )
        scope_catalog = target_document.get("scope_catalog") or [
            {
                "key": key,
                "level": "application",
                "parent_key": None,
                "source_ref": "proposal-local-scope",
            }
            for key in fallback_scope_keys
        ]
        proposal_glossary = {
            "glossary_key": glossary_key,
            "content_version": document.get("target_content_version"),
            "scope": target_document.get("scope") or proposed_scope,
            "scope_catalog": scope_catalog,
            "terms": [proposed_term],
        }
        validate_glossaries(
            proposal_glossary,
            comparison_registry,
            findings,
            check_glossary_uniqueness=False,
            require_publishable_terms=False,
        )


def validate_registry_glossary_keys(
    registry_documents: list[tuple[Path, dict[str, Any]]],
    findings: FindingCollector,
) -> None:
    origins: defaultdict[str, list[str]] = defaultdict(list)
    for path, document in registry_documents:
        key = document.get("glossary_key")
        if isinstance(key, str):
            origins[key].append(f"{path}:$.glossary_key")
    for key, locations in sorted(origins.items()):
        if len(locations) > 1:
            findings.add(
                "error",
                "SGK_DUPLICATE_GLOSSARY",
                "$.glossary_key",
                f"glossary key is duplicated: {key}",
                locations,
            )


def validate_registry_documents(
    registry_documents: dict[str, list[tuple[Path, dict[str, Any]]]],
    schemas: dict[str, dict[str, Any]],
    schema_registry: Any,
    Draft202012Validator: Any,
    FormatChecker: Any,
    findings: FindingCollector,
) -> None:
    for kind in KINDS:
        for path, document in registry_documents[kind]:
            validate_schema(
                document,
                schemas[kind],
                schema_registry,
                Draft202012Validator,
                FormatChecker,
                findings,
                source_ref=str(path),
            )
            marker = {
                "glossary": "schema_version",
                "proposal": "proposal_schema_version",
                "change": None,
            }[kind]
            if marker is not None and document.get(marker) != SCHEMA_VERSION:
                findings.add(
                    "error",
                    "SGV_SCHEMA_VERSION",
                    f"{path}:$.{marker}",
                    f"registry {marker} must be {SCHEMA_VERSION}",
                    [str(path)],
                )


def validate_operation_key_uniqueness(
    source_kind: str,
    source_document: dict[str, Any],
    registry_documents: dict[str, list[tuple[Path, dict[str, Any]]]],
    findings: FindingCollector,
) -> None:
    specifications = (("proposal", "merge_key"), ("change", "change_key"))
    origins: defaultdict[str, list[tuple[str, str]]] = defaultdict(list)
    for kind, field in specifications:
        for path, document in registry_documents[kind]:
            value = document.get(field)
            if isinstance(value, str):
                origins[value].append((kind, f"{path}:$.{field}"))
        if source_kind == kind:
            value = source_document.get(field)
            if isinstance(value, str):
                origins[value].append((kind, f"$.{field}"))
    for value, entries in sorted(origins.items()):
        if len(entries) < 2:
            continue
        kinds = {kind for kind, _ in entries}
        if len(kinds) > 1:
            code = "SGK_DUPLICATE_OPERATION_KEY"
            path = "$"
        elif "proposal" in kinds:
            code = "SGP_DUPLICATE_MERGE_KEY"
            path = "$.merge_key"
        else:
            code = "SGK_DUPLICATE_CHANGE_KEY"
            path = "$.change_key"
        findings.add(
            "error",
            code,
            path,
            f"operation key is duplicated and cannot be applied twice: {value}",
            [location for _, location in entries],
        )


def validate_change(
    document: dict[str, Any],
    registry_documents: list[tuple[Path, dict[str, Any]]],
    registry_proposals: list[tuple[Path, dict[str, Any]]],
    findings: FindingCollector,
    *,
    registry_requested: bool,
    allow_historical_target: bool = False,
) -> None:
    for value, path in change_keys(document):
        if value is not None:
            check_key(value, path, findings)
    base = semver(document.get("base_content_version"))
    target = semver(document.get("target_content_version"))
    if base and target and target <= base:
        findings.add("error", "SGV_VERSION_ORDER", "$.target_content_version", "target_content_version must exceed base_content_version")
    glossary_key = document.get("glossary_key")
    target_documents = [
        (path, registry)
        for path, registry in registry_documents
        if registry.get("glossary_key") == glossary_key
    ]
    if registry_requested and not target_documents:
        findings.add(
            "error",
            "SGR_CHANGE_GLOSSARY_MISSING",
            "$.glossary_key",
            f"change target glossary does not exist in registry: {glossary_key}",
            [str(glossary_key)],
        )
    for path, registry in target_documents:
        if (
            not allow_historical_target
            and registry.get("content_version") != document.get("target_content_version")
        ):
            findings.add("error", "SGV_TARGET_MISMATCH", "$.target_content_version", "change target_content_version differs from current glossary", [str(path)])
        known = {term.get("key") for term in registry.get("terms", []) if isinstance(term, dict)}
        for index, key in enumerate(document.get("affected_term_keys", [])):
            if key not in known:
                findings.add("error", "SGR_MISSING", f"$.affected_term_keys[{index}]", f"affected term does not exist: {key}", [str(key)])

    proposal_key = document.get("proposal_key")
    proposal_audit = document.get("proposal_audit")
    if isinstance(proposal_key, str) and isinstance(proposal_audit, dict):
        matching_proposals = [
            (path, proposal)
            for path, proposal in registry_proposals
            if proposal.get("proposal_key") == proposal_key
        ]
        if len(matching_proposals) != 1:
            findings.add(
                "error",
                "SGP_CHANGE_PROPOSAL_MISSING" if not matching_proposals else "SGP_CHANGE_PROPOSAL_AMBIGUOUS",
                "$.proposal_key",
                f"proposal-derived change must resolve exactly one registry proposal; found {len(matching_proposals)} for {proposal_key}",
                [str(path) for path, _ in matching_proposals],
            )
        else:
            proposal_path, canonical = matching_proposals[0]
            canonical_findings = FindingCollector()
            validate_proposal(
                canonical,
                registry_documents,
                canonical_findings,
                registry_requested=True,
            )
            blocking_codes = sorted(
                {
                    item["code"]
                    for item in canonical_findings.items
                    if item["severity"] in {"error", "review_required"}
                    and not (
                        allow_historical_target and item["code"] == "SGP_STALE_BASE"
                    )
                }
            )
            if blocking_codes:
                findings.add(
                    "error",
                    "SGP_CHANGE_CANONICAL_PROPOSAL_INVALID",
                    "$.proposal_key",
                    "registry proposal fails full semantic validation: "
                    + ", ".join(blocking_codes),
                    [str(proposal_path)],
                )
            canonical_payload = canonical.get("proposal") if isinstance(canonical.get("proposal"), dict) else {}
            canonical_approval = canonical_payload.get("approval") if isinstance(canonical_payload.get("approval"), dict) else {}
            comparisons = (
                (canonical.get("target_glossary_key"), document.get("glossary_key"), "target glossary"),
                (canonical.get("base_content_version"), document.get("base_content_version"), "base content version"),
                (canonical.get("target_content_version"), document.get("target_content_version"), "target content version"),
            )
            for canonical_value, recorded_value, label in comparisons:
                if canonical_value != recorded_value:
                    findings.add(
                        "error",
                        "SGP_CHANGE_PROPOSAL_MISMATCH",
                        "$.proposal_key",
                        f"change {label} does not match registry proposal",
                        [str(proposal_path)],
                    )
            proposal_operation = canonical.get("proposal_operation")
            if (
                proposal_operation not in {"add", "update"}
                or document.get("change_type") != proposal_operation
            ):
                findings.add(
                    "error",
                    "SGP_CHANGE_OPERATION_MISMATCH",
                    "$.change_type",
                    "proposal-derived change_type must exactly match an add/update registry proposal_operation",
                    [str(proposal_path)],
                )
            proposed_term = canonical.get("proposed_term")
            proposed_term_key = (
                proposed_term.get("key") if isinstance(proposed_term, dict) else None
            )
            if document.get("affected_term_keys") != [proposed_term_key]:
                findings.add(
                    "error",
                    "SGP_CHANGE_TERM_MISMATCH",
                    "$.affected_term_keys",
                    "proposal-derived affected_term_keys must contain only the registry proposed_term.key",
                    [str(proposal_path)],
                )
            expected_content_hash = proposal_content_hash(canonical)
            if document.get("proposal_content_hash") != expected_content_hash:
                findings.add(
                    "error",
                    "SGP_CHANGE_CONTENT_SNAPSHOT_MISMATCH",
                    "$.proposal_content_hash",
                    "proposal-derived change must preserve the complete approved semantic proposal snapshot",
                    [str(proposal_path), expected_content_hash],
                )
            if canonical_approval.get("status") not in {"approved", "merged"}:
                findings.add(
                    "error",
                    "SGP_CHANGE_PROPOSAL_UNAPPROVED",
                    "$.proposal_key",
                    "proposal-derived change requires an approved or merged registry proposal",
                    [str(proposal_path)],
                )

            actual_terms = [
                term
                for _, registry in target_documents
                for term in registry.get("terms", [])
                if isinstance(term, dict) and term.get("key") == proposed_term_key
            ]
            if (
                isinstance(proposed_term, dict)
                and len(actual_terms) == 1
                and semantic_term_snapshot(actual_terms[0])
                != semantic_term_snapshot(proposed_term)
            ):
                findings.add(
                    "error",
                    "SGP_CHANGE_APPLIED_TERM_MISMATCH",
                    "$.affected_term_keys",
                    "applied glossary term differs from the approved proposed_term",
                    [str(proposal_path), str(proposed_term_key)],
                )
            snapshot_pairs = (
                ("evidence", canonical_payload.get("evidence"), document.get("evidence")),
                ("inferences", canonical_payload.get("inferences"), proposal_audit.get("inferences")),
                ("confidence", canonical_payload.get("confidence"), proposal_audit.get("confidence")),
                (
                    "decision_reason",
                    canonical_approval.get("decision_reason"),
                    proposal_audit.get("decision_reason"),
                ),
                ("reviewers", canonical_approval.get("reviewers"), proposal_audit.get("reviewers")),
                ("approval_events", canonical_approval.get("events"), proposal_audit.get("approval_events")),
                ("detected_by", canonical_payload.get("detected_by"), proposal_audit.get("detected_by")),
            )
            for field, canonical_value, recorded_value in snapshot_pairs:
                if canonical_value != recorded_value:
                    findings.add(
                        "error",
                        "SGP_CHANGE_PROPOSAL_SNAPSHOT_MISMATCH",
                        f"$.proposal_audit.{field}" if field != "evidence" else "$.evidence",
                        f"change snapshot differs from registry proposal: {field}",
                        [str(proposal_path)],
                    )
        reviewers = [
            reviewer
            for reviewer in proposal_audit.get("reviewers", [])
            if isinstance(reviewer, dict)
        ]
        approved_identities = {
            (reviewer.get("role"), reviewer.get("actor"))
            for reviewer in reviewers
            if reviewer.get("decision") == "approved"
            and reviewer.get("role") in {"business_approver", "technical_approver"}
            and isinstance(reviewer.get("actor"), str)
        }
        approved_roles = {role for role, _ in approved_identities}
        if approved_roles != {"business_approver", "technical_approver"}:
            findings.add(
                "error",
                "SGP_PROPOSAL_AUDIT_APPROVAL_REQUIRED",
                "$.proposal_audit.reviewers",
                "proposal-derived change requires approved business and technical reviewers",
            )

        validate_approval_history(
            proposal_audit.get("approval_events", []),
            {"approved", "merged"},
            findings,
            path="$.proposal_audit.approval_events",
            missing_code="SGP_PROPOSAL_AUDIT_HISTORY_REQUIRED",
            history_code="SGP_PROPOSAL_AUDIT_HISTORY_REQUIRED",
            final_code="SGP_PROPOSAL_AUDIT_HISTORY_REQUIRED",
        )

        applied_at = instant(document.get("applied_at"))
        audit_times = [
            instant(item.get(field))
            for items, field in (
                (proposal_audit.get("reviewers", []), "decided_at"),
                (proposal_audit.get("approval_events", []), "occurred_at"),
            )
            for item in items
            if isinstance(item, dict)
        ]
        if applied_at is not None and any(
            audit_time is not None and audit_time > applied_at
            for audit_time in audit_times
        ):
            findings.add(
                "error",
                "SGP_CHANGE_APPLIED_TIME_ORDER",
                "$.applied_at",
                "applied_at must occur at or after all proposal audit decisions and events",
            )

        recorded_identities: set[tuple[str, str]] = set()
        for identity in document.get("approved_by", []):
            if not isinstance(identity, str) or ":" not in identity:
                continue
            role, actor = identity.split(":", 1)
            if role in {"business_approver", "technical_approver"} and actor:
                recorded_identities.add((role, actor))
        if recorded_identities != approved_identities:
            findings.add(
                "error",
                "SGP_PROPOSAL_AUDIT_APPROVER_MISMATCH",
                "$.approved_by",
                "approved_by must exactly match approved proposal_audit reviewer role/actor identities",
                [f"{role}:{actor}" for role, actor in sorted(approved_identities)],
            )

    change_type = document.get("change_type")
    if change_type == "add" and document.get("before_hash") is not None:
        findings.add(
            "error",
            "SGP_CHANGE_BEFORE_HASH_UNEXPECTED",
            "$.before_hash",
            "add change must have a null before_hash",
        )
    if change_type != "add" and document.get("before_hash") is None:
        findings.add(
            "error",
            "SGP_CHANGE_BEFORE_HASH_REQUIRED",
            "$.before_hash",
            "non-add change requires a before_hash attestation",
        )

    for glossary_path, registry in target_documents:
        term_map = {
            term.get("key"): term
            for term in registry.get("terms", [])
            if isinstance(term, dict) and isinstance(term.get("key"), str)
        }
        affected = document.get("affected_term_keys", [])
        applied_terms = [term_map[key] for key in affected if key in term_map]
        if len(applied_terms) != len(affected):
            continue
        expected_after_hash = applied_terms_hash(applied_terms)
        if document.get("after_hash") != expected_after_hash:
            findings.add(
                "error",
                "SGP_CHANGE_AFTER_HASH_MISMATCH",
                "$.after_hash",
                "after_hash does not match the applied affected-term state",
                [str(glossary_path), expected_after_hash],
            )
        lifecycle_statuses = {
            str(term.get("key")): (
                term.get("lifecycle", {}).get("status")
                if isinstance(term.get("lifecycle"), dict)
                else None
            )
            for term in applied_terms
        }
        if change_type == "deprecate" and any(
            status != "deprecated" for status in lifecycle_statuses.values()
        ):
            findings.add(
                "error",
                "SGP_CHANGE_APPLIED_STATE_MISMATCH",
                "$.affected_term_keys",
                "deprecate change requires every affected term to be deprecated",
                [str(glossary_path)],
            )
        if change_type == "retire" and any(
            status != "retired" for status in lifecycle_statuses.values()
        ):
            findings.add(
                "error",
                "SGP_CHANGE_APPLIED_STATE_MISMATCH",
                "$.affected_term_keys",
                "retire change requires every affected term to be retired",
                [str(glossary_path)],
            )
        if change_type == "merge":
            active = [term for term in applied_terms if lifecycle_statuses[str(term.get("key"))] == "active"]
            retired = [term for term in applied_terms if lifecycle_statuses[str(term.get("key"))] == "retired"]
            survivor = active[0].get("key") if len(active) == 1 else None
            if (
                survivor is None
                or not retired
                or any(
                    not isinstance(term.get("lifecycle"), dict)
                    or term["lifecycle"].get("replaced_by") != survivor
                    for term in retired
                )
            ):
                findings.add(
                    "error",
                    "SGP_CHANGE_APPLIED_STATE_MISMATCH",
                    "$.affected_term_keys",
                    "merge change requires one active survivor and retired sources replaced_by that survivor",
                    [str(glossary_path)],
                )


def validate_publication_links(
    document: dict[str, Any],
    registry_glossaries: list[tuple[Path, dict[str, Any]]],
    registry_proposals: list[tuple[Path, dict[str, Any]]],
    registry_changes: list[tuple[Path, dict[str, Any]]],
    findings: FindingCollector,
    *,
    registry_requested: bool,
) -> None:
    """Bind approved publication claims to canonical proposal/change records."""
    glossary_key = document.get("glossary_key")
    validation_glossaries = [(Path("<publication-input>"), document), *registry_glossaries]
    for index, term in enumerate(document.get("terms", [])):
        if not isinstance(term, dict):
            continue
        provenance = term.get("provenance")
        if not isinstance(provenance, dict) or provenance.get("publication_status") != "approved":
            continue
        base = f"$.terms[{index}]"
        if not registry_requested:
            findings.add(
                "review_required",
                "SGP_PUBLICATION_REGISTRY_REQUIRED",
                f"{base}.provenance",
                "approved publication refs require a canonical registry",
            )
            continue
        proposal_key = referenced_key(provenance.get("decision_ref"), "proposals/")
        change_key = referenced_key(provenance.get("change_ref"), "changes/")
        if proposal_key is None or change_key is None:
            findings.add(
                "error",
                "SGP_PUBLICATION_REF_INVALID",
                f"{base}.provenance",
                "decision_ref and change_ref must use proposals/<key> and changes/<key>",
            )
            continue
        proposals = [
            (path, proposal)
            for path, proposal in registry_proposals
            if proposal.get("proposal_key") == proposal_key
        ]
        changes = [
            (path, change)
            for path, change in registry_changes
            if change.get("change_key") == change_key
        ]
        if len(proposals) != 1 or len(changes) != 1:
            findings.add(
                "error",
                "SGP_PUBLICATION_REF_UNRESOLVED",
                f"{base}.provenance",
                "publication refs must resolve exactly one canonical proposal and change",
                [str(path) for path, _ in proposals + changes],
            )
            continue
        proposal_path, proposal = proposals[0]
        change_path, change = changes[0]
        linked_findings = FindingCollector()
        validate_proposal(
            proposal,
            validation_glossaries,
            linked_findings,
            registry_requested=True,
        )
        validate_change(
            change,
            validation_glossaries,
            registry_proposals,
            linked_findings,
            registry_requested=True,
            allow_historical_target=True,
        )
        blocking_codes = sorted(
            {
                item["code"]
                for item in linked_findings.items
                if item["severity"] in {"error", "review_required"}
                and item["code"] != "SGP_STALE_BASE"
            }
        )
        if blocking_codes:
            findings.add(
                "error",
                "SGP_PUBLICATION_ATTESTATION_INVALID",
                f"{base}.provenance",
                "publication proposal/change fail semantic validation: "
                + ", ".join(blocking_codes),
                [str(proposal_path), str(change_path)],
            )
        payload = proposal.get("proposal") if isinstance(proposal.get("proposal"), dict) else {}
        approval = payload.get("approval") if isinstance(payload.get("approval"), dict) else {}
        proposed_term = proposal.get("proposed_term")
        expected_approvers = sorted(
            identity
            for identity in change.get("approved_by", [])
            if isinstance(identity, str)
        )
        stewardship = term.get("stewardship") if isinstance(term.get("stewardship"), dict) else {}
        recorded_approvers = stewardship.get("approvers", [])
        proposed_key = proposed_term.get("key") if isinstance(proposed_term, dict) else None
        change_type = change.get("change_type")
        affected_keys = change.get("affected_term_keys", [])
        comparisons = (
            (approval.get("status") in {"approved", "merged"}, "proposal is not approved or merged"),
            (
                isinstance(change.get("proposal_key"), str)
                and change.get("proposal_key") == proposal_key,
                "change does not bind the decision proposal",
            ),
            (change.get("glossary_key") == glossary_key, "change targets another glossary"),
            (term.get("key") in affected_keys, "change does not affect this term"),
            (proposed_key == term.get("key"), "proposal targets another term"),
            (
                proposal.get("proposal_operation") == change_type,
                "proposal/change operations differ",
            ),
            (
                change.get("proposal_content_hash") == proposal_content_hash(proposal),
                "change proposal snapshot hash differs",
            ),
            (sorted(recorded_approvers) == expected_approvers, "term approvers differ from change approved_by"),
            (
                isinstance(proposed_term, dict)
                and semantic_term_snapshot(term) == semantic_term_snapshot(proposed_term),
                "published term differs from approved proposed_term",
            ),
        )
        failed = [message for passed, message in comparisons if not passed]
        if failed:
            findings.add(
                "error",
                "SGP_PUBLICATION_BINDING_MISMATCH",
                f"{base}.provenance",
                "; ".join(failed),
                [str(proposal_path), str(change_path)],
            )


def make_report(kind: str, source: Path, status: str, findings: FindingCollector) -> dict[str, Any]:
    ordered = findings.sorted()
    counts = Counter(item["severity"] for item in ordered)
    return {
        "contractVersion": CONTRACT_VERSION,
        "status": status,
        "sourceKind": kind,
        "sourceRef": str(source),
        "counts": {
            "error": counts["error"],
            "warning": counts["warning"],
            "review_required": counts["review_required"],
        },
        "findings": ordered,
    }


def write_report(path: Path | None, report: dict[str, Any]) -> None:
    if path is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(report, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            os.replace(temporary, path)
        except BaseException:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
            raise
    except OSError as error:
        raise UnavailableError(
            f"cannot write report {path}: {error}", "SGD_REPORT_WRITE"
        ) from error


def unavailable_report(
    kind: str, source: Path, message: str, code: str = "SGD_UNAVAILABLE"
) -> dict[str, Any]:
    findings = FindingCollector()
    findings.add("error", code, "$", message)
    return make_report(kind, source, "unavailable", findings)


# 素直な形(resolve()の一致だけで同一ファイル判定する)を避け、samefile()も併用する
# 二重チェックにしている。resolve()は絶対path化・symlink解決までは同一化するが、
# 2つの異なるハードリンク(同じinodeを指す別々のディレクトリエントリ)はそれぞれ
# 別のpathへresolve()されるため一致しない。samefile()(stat結果のst_dev/st_inoで
# 比較)を併用しないと、ハードリンク経由で--reportが--inputと同じ実体を指す
# ケースを見逃す(README.md「Operation keyと出力先の保護」節が守ろうとしている
# 「入力とregistryのbyte列を変更しない」という保証が破れる)。
def paths_refer_to_same_file(left: Path, right: Path) -> bool:
    if left.resolve() == right.resolve():
        return True
    try:
        return os.path.samefile(left, right)
    except OSError:
        return False


def run(args: argparse.Namespace) -> int:
    if args.report is not None and paths_refer_to_same_file(args.input, args.report):
        print("--report must not resolve to the --input file", file=sys.stderr)
        return 2
    try:
        yaml, Draft202012Validator, FormatChecker, Registry, Resource = dependency_modules()
        schemas, schema_registry = load_schemas(yaml, Registry, Resource)
        document = load_yaml(args.input, yaml)
        registry_by_kind = load_registry(
            args.registry, args.input, yaml, report_path=args.report
        )
        registry_documents = registry_by_kind["glossary"]
        findings = FindingCollector()
        validate_schema(document, schemas[args.kind], schema_registry, Draft202012Validator, FormatChecker, findings)
        validate_registry_documents(
            registry_by_kind,
            schemas,
            schema_registry,
            Draft202012Validator,
            FormatChecker,
            findings,
        )
        validate_operation_key_uniqueness(
            args.kind, document, registry_by_kind, findings
        )
        expected_marker = {
            "glossary": ("schema_version", SCHEMA_VERSION),
            "proposal": ("proposal_schema_version", SCHEMA_VERSION),
            "change": (None, None),
        }[args.kind]
        if expected_marker[0] and document.get(expected_marker[0]) != expected_marker[1]:
            findings.add("error", "SGV_SCHEMA_VERSION", f"$.{expected_marker[0]}", f"{expected_marker[0]} must be {SCHEMA_VERSION}")
        if args.kind == "glossary":
            validate_glossaries(
                document,
                registry_documents,
                findings,
                registry_proposals=registry_by_kind["proposal"],
                registry_changes=registry_by_kind["change"],
                registry_requested=args.registry is not None,
            )
        elif args.kind == "proposal":
            validate_registry_glossary_keys(registry_documents, findings)
            validate_proposal(
                document,
                registry_documents,
                findings,
                registry_requested=args.registry is not None,
            )
        else:
            validate_registry_glossary_keys(registry_documents, findings)
            validate_change(
                document,
                registry_documents,
                registry_by_kind["proposal"],
                findings,
                registry_requested=args.registry is not None,
            )
        status = "invalid" if any(item["severity"] == "error" for item in findings.items) else "valid"
        report = make_report(args.kind, args.input, status, findings)
        write_report(args.report, report)
        print(
            f"{args.kind}: {status}; errors={report['counts']['error']} "
            f"warnings={report['counts']['warning']} review_required={report['counts']['review_required']}"
        )
        return 1 if status == "invalid" else 0
    except ReportTargetCollision as error:
        print(str(error), file=sys.stderr)
        return 2
    except UnavailableError as error:
        report = unavailable_report(args.kind, args.input, str(error), error.code)
        try:
            write_report(args.report, report)
        except UnavailableError as report_error:
            print(str(report_error), file=sys.stderr)
        print(str(error), file=sys.stderr)
        return 2
    except Exception as error:
        report = unavailable_report(
            args.kind, args.input, f"internal error: {error}", "SGD_INTERNAL"
        )
        try:
            write_report(args.report, report)
        except UnavailableError:
            pass
        print(f"internal error: {error}", file=sys.stderr)
        return 2


def main() -> int:
    try:
        args = parse_args(sys.argv[1:])
    except SystemExit as error:
        return int(error.code)
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
