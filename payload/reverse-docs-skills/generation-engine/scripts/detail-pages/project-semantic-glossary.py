#!/usr/bin/env python3
"""Project an approved semantic glossary YAML into portal page-data v0.2."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


PROJECTION_VERSION = "0.2"
GLOSSARY_SCHEMA_VERSION = "1.0.0"
CATEGORIES = (
    {"key": "entity", "label": "エンティティ"},
    {"key": "attribute", "label": "属性"},
    {"key": "value", "label": "値"},
    {"key": "process", "label": "処理"},
    {"key": "event", "label": "イベント"},
    {"key": "role", "label": "役割"},
    {"key": "rule", "label": "ルール"},
    {"key": "metric", "label": "指標"},
)
LEGACY_KIND_CATEGORY = {
    "entity": "entity",
    "attribute": "attribute",
    "identifier": "attribute",
    "status": "value",
    "value_object": "value",
    "process": "process",
    "event": "event",
    "role": "role",
    "rule": "rule",
    "technical_concept": "entity",
}


class ProjectionError(RuntimeError):
    """Expected projection failure with a stable exit code."""

    def __init__(self, message: str, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def import_yaml() -> Any:
    # 素直な形(呼び出し元にvenvのpythonを指定させる)を避け、システムのpython3で
    # 起動された場合でも自分自身をglossary/.venv配下のpythonへos.execveで再実行する。
    # このprojectorはgeneration-engine/scripts/detail-pages配下にあり呼び出し元は
    # 素のpython3を使うことが多いが、PyYAMLはglossaryのvenv(validate-semantic-glossary.py用)
    # にしか入っていない。呼び出し契約(python3 project-semantic-glossary.py ...)を
    # 変えずに依存を満たすため、この関数の中だけで再実行する。
    # SEMANTIC_GLOSSARY_PROJECTOR_REEXEC で再実行済みかどうかを見て1回しか
    # execveしない(venv側にもPyYAMLが無い場合の無限再実行を防ぐ)。
    try:
        import yaml

        return yaml
    except ImportError as error:
        validator_dir = Path(__file__).resolve().parents[1] / "glossary"
        venv_python = validator_dir / ".venv" / "bin" / "python"
        if os.environ.get("SEMANTIC_GLOSSARY_PROJECTOR_REEXEC") != "1" and venv_python.is_file():
            environment = os.environ.copy()
            environment["SEMANTIC_GLOSSARY_PROJECTOR_REEXEC"] = "1"
            os.execve(
                str(venv_python),
                [str(venv_python), str(Path(__file__).resolve()), *sys.argv[1:]],
                environment,
            )
        raise ProjectionError(f"PyYAML is unavailable: {error}", 2) from error


# 素直な形(args.inputのパスを検証にも投影にも渡す)を避け、main()はこの関数で
# 入力ファイルを1回だけ読み、以降は同じバイト列(input_bytes)だけを使い回す。
# 検証(run_validator)と投影(load_glossary)の間でargs.inputを2回読むと、その間に
# 元ファイルが書き換わった場合(TOCTOU)、検証した内容と実際に投影する内容が
# 一致しなくなる。test-project-semantic-glossary-race.shはこの一致を、検証中に
# 元ファイルを差し替えるレースを再現して検証する。
def read_input_once(input_path: Path) -> bytes:
    try:
        return input_path.read_bytes()
    except OSError as error:
        raise ProjectionError(f"cannot read glossary YAML: {error}", 2) from error


def run_validator(input_bytes: bytes, registry_path: Path) -> None:
    # 検証にはargs.inputへのパスではなく、read_input_onceが読んだinput_bytesを
    # 新規の一時ファイルへ書き出してから渡す。args.inputのパスをそのまま渡すと、
    # 検証の実行中に元ファイルが変わりうる余地を残すため、フリーズしたバイト列を
    # 独立した一時ファイルへ固定してから検証器へ渡す。
    validator = Path(__file__).resolve().parents[1] / "glossary" / "validate-semantic-glossary.sh"
    if not validator.is_file():
        raise ProjectionError(f"semantic glossary validator is unavailable: {validator}", 2)
    source_path: Path | None = None
    report_path: Path | None = None
    try:
        try:
            with tempfile.NamedTemporaryFile(
                prefix="semantic-glossary-source-", suffix=".yaml", delete=False
            ) as source_handle:
                source_path = Path(source_handle.name)
                source_handle.write(input_bytes)
                source_handle.flush()
                os.fsync(source_handle.fileno())
            with tempfile.NamedTemporaryFile(
                prefix="semantic-glossary-report-", suffix=".json", delete=False
            ) as report_handle:
                report_path = Path(report_handle.name)
        except OSError as error:
            raise ProjectionError(f"cannot stage semantic glossary validation input: {error}", 2) from error
        try:
            result = subprocess.run(
                [
                    str(validator),
                    "--kind",
                    "glossary",
                    "--input",
                    str(source_path),
                    "--registry",
                    str(registry_path),
                    "--report",
                    str(report_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        except OSError as error:
            raise ProjectionError(f"cannot execute semantic glossary validator: {error}", 2) from error
        if result.returncode in (1, 2):
            detail = (result.stderr or result.stdout).strip()
            raise ProjectionError(detail or "semantic glossary validation failed", result.returncode)
        if result.returncode != 0:
            raise ProjectionError(f"semantic glossary validator returned unexpected exit {result.returncode}", 2)
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
            counts = report["counts"]
            error_count = int(counts["error"])
            review_count = int(counts["review_required"])
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
            raise ProjectionError(f"cannot read semantic glossary validation report: {error}", 2) from error
        if report.get("sourceKind") != "glossary" or report.get("status") != "valid":
            raise ProjectionError("validator report does not identify a valid glossary", 1)
        if error_count > 0 or review_count > 0:
            raise ProjectionError(
                f"projection blocked by validator report: errors={error_count} review_required={review_count}",
                1,
            )
    finally:
        if report_path is not None:
            report_path.unlink(missing_ok=True)
        if source_path is not None:
            source_path.unlink(missing_ok=True)


def load_glossary(input_bytes: bytes, yaml: Any) -> dict[str, Any]:
    try:
        documents = list(yaml.safe_load_all(input_bytes.decode("utf-8")))
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        raise ProjectionError(f"cannot parse glossary YAML: {error}", 2) from error
    if len(documents) != 1 or not isinstance(documents[0], dict):
        raise ProjectionError("glossary YAML must contain one object document", 2)
    document = documents[0]
    if "proposal" in document or "change_type" in document or "terms" not in document:
        raise ProjectionError("proposal/change documents cannot be projected", 1)
    if document.get("schema_version") != GLOSSARY_SCHEMA_VERSION:
        raise ProjectionError(
            f"schema version mismatch: expected {GLOSSARY_SCHEMA_VERSION}, found {document.get('schema_version')}",
            1,
        )
    if not isinstance(document.get("content_version"), str) or not re.fullmatch(
        r"[0-9]+\.[0-9]+\.[0-9]+", document["content_version"]
    ):
        raise ProjectionError("content_version must be semantic version text", 1)
    return document


def project_representation(value: dict[str, Any]) -> dict[str, Any]:
    result = {"channel": value["channel"], "value": value["value"], "location": value["location"]}
    if "symbol_kind" in value:
        result["symbolKind"] = value["symbol_kind"]
    return result


def first_representation(
    term: dict[str, Any], channel: str, symbol_kinds: set[str] | None = None
) -> str:
    for representation in term.get("representations", []):
        if not isinstance(representation, dict) or representation.get("channel") != channel:
            continue
        symbol_kind = representation.get("symbol_kind")
        if symbol_kinds is not None and symbol_kind not in symbol_kinds:
            continue
        value = representation.get("value")
        if isinstance(value, str):
            return value
    return ""


def project_scope(term: dict[str, Any]) -> str:
    scope = term.get("scope")
    if isinstance(scope, str):
        return scope
    if isinstance(scope, dict):
        includes = [value for value in scope.get("includes", []) if isinstance(value, str)]
        return ", ".join(includes)
    return ""


def project_term_en(term: dict[str, Any]) -> str:
    if isinstance(term.get("term_en"), str):
        return term["term_en"]
    for alias in term.get("aliases", []):
        if isinstance(alias, dict) and alias.get("language") == "en" and isinstance(alias.get("value"), str):
            return alias["value"]
    return ""


def project_term(term: dict[str, Any]) -> dict[str, Any]:
    lifecycle = term["lifecycle"]
    stewardship = term["stewardship"]
    provenance = term["provenance"]
    term_ja = term.get("term_ja") if isinstance(term.get("term_ja"), str) else term.get("label", "")
    code_name = term.get("code_name") if isinstance(term.get("code_name"), str) else first_representation(term, "code")
    type_name = term.get("type_name") if isinstance(term.get("type_name"), str) else first_representation(term, "code", {"type", "class", "enum", "interface"})
    result: dict[str, Any] = {
        "key": term["key"],
        "term_ja": term_ja,
        "term_en": project_term_en(term),
        "definition": term["definition"],
        "scope": project_scope(term),
        "category": (
            term.get("category")
            if "term_ja" in term
            else LEGACY_KIND_CATEGORY.get(term.get("kind", ""), "entity")
        ),
        "code_name": code_name,
        "type_name": type_name,
        "db_name": term.get("db_name") if isinstance(term.get("db_name"), str) else first_representation(term, "database"),
        "api_name": term.get("api_name") if isinstance(term.get("api_name"), str) else first_representation(term, "api"),
        "ui_label": term.get("ui_label") if isinstance(term.get("ui_label"), str) else first_representation(term, "ui") or term_ja,
        "allowed_values": term.get("allowed_values") if isinstance(term.get("allowed_values"), list) else [],
        "status": term.get("status") if isinstance(term.get("status"), str) else lifecycle["status"],
        "notes": term.get("notes") if isinstance(term.get("notes"), str) else "",
    }
    result["representations"] = [project_representation(value) for value in term.get("representations", [])]
    result["sourceRefs"] = [source["ref"] for source in provenance["sources"]]
    optional: tuple[tuple[str, str], ...] = (
        ("examples", "examples"),
        ("counter_examples", "counterExamples"),
        ("constraints", "constraints"),
        ("tags", "tags"),
        ("security_classification", "securityClassification"),
    )
    for source_key, target_key in optional:
        if source_key in term:
            result[target_key] = term[source_key]
    if "aliases" in term:
        result["aliases"] = [alias["value"] for alias in term["aliases"]]
    if "forbidden_terms" in term:
        result["forbiddenTerms"] = [
            {
                "term": forbidden["value"],
                "reason": forbidden["reason"],
                "replacementKey": forbidden["replacement_key"],
            }
            for forbidden in term["forbidden_terms"]
        ]
    if "relations" in term:
        result["relations"] = [
            {"type": relation["type"], "targetKey": relation["target_key"]}
            for relation in term["relations"]
        ]
    lifecycle_optional: tuple[tuple[str, str], ...] = (
        ("introduced_in", "introducedIn"),
        ("deprecated_in", "deprecatedIn"),
        ("retired_in", "retiredIn"),
        ("migration_deadline", "migrationDeadline"),
        ("replaced_by", "replacementKey"),
        ("reason", "lifecycleReason"),
    )
    for source_key, target_key in lifecycle_optional:
        if lifecycle.get(source_key) is not None:
            result[target_key] = lifecycle[source_key]
    result["approvers"] = stewardship.get("approvers", [])
    if "decision_ref" in provenance:
        result["decisionRef"] = provenance["decision_ref"]
    if "change_ref" in provenance:
        result["changeRef"] = provenance["change_ref"]
    return result


def project_document(document: dict[str, Any]) -> dict[str, Any]:
    metadata = document.get("metadata") if isinstance(document.get("metadata"), dict) else {}
    generated_at = metadata.get("updated_at") or metadata.get("created_at") or "1970-01-01T00:00:00Z"
    return {
        "pageKind": "glossary",
        "generatedAt": generated_at,
        "title": document["title"],
        "description": f"承認済み用語集「{document['title']}」の業務概念とコード表現。",
        "projectName": document["glossary_key"],
        "projectionVersion": PROJECTION_VERSION,
        "glossarySchemaVersion": document["schema_version"],
        "glossaryContentVersion": document["content_version"],
        "categories": [dict(category) for category in CATEGORIES],
        "terms": [project_term(term) for term in document["terms"]],
    }


def write_atomic(output_path: Path, page_data: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=output_path.parent, prefix=f".{output_path.name}.", delete=False
        ) as handle:
            temporary = Path(handle.name)
            json.dump(page_data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, output_path)
    except OSError as error:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise ProjectionError(f"cannot write page-data atomically: {error}", 2) from error


def main() -> int:
    args = parse_args()
    try:
        if args.input.resolve() == args.output.resolve():
            raise ProjectionError("--input and --output must be different files", 2)
        input_bytes = read_input_once(args.input)
        yaml = import_yaml()
        run_validator(input_bytes, args.registry)
        document = load_glossary(input_bytes, yaml)
        page_data = project_document(document)
        write_atomic(args.output, page_data)
        print(f"OK: wrote {args.output}")
        return 0
    except ProjectionError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return error.exit_code
    except (KeyError, TypeError, ValueError) as error:
        print(f"ERROR: validated glossary could not be projected: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
