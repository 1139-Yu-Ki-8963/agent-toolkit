#!/usr/bin/env python3
"""Deterministic Python facts extractor and independent counter.

The implementation intentionally uses only the Python standard library. Source
files are decoded with ``tokenize.open`` so extraction and recount share the
same PEP 263 encoding decision.
"""

import sys


def require_runtime_version(version_info=None) -> None:
    """Fail before profile-specific imports on Python older than 3.8."""
    version = sys.version_info if version_info is None else version_info
    if tuple(version[:2]) < (3, 8):
        print(
            "ERROR: profile=python requires Python 3.8 or newer "
            "(AST end-position metadata is mandatory)",
            file=sys.stderr,
        )
        raise SystemExit(2)


require_runtime_version()

import argparse
import ast
import hashlib
import json
import pathlib
import tokenize
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Union


SECTIONS = (
    "import",
    "function",
    "local_assignment",
    "external_call",
    "exception_handling",
    "measurement_pending",
)

@dataclass(frozen=True)
class Fact:
    section: str
    key: str
    value: Optional[str]
    evidence: str
    source_span: str


def read_source(path: pathlib.Path) -> str:
    """Read a Python source file using its declared encoding and LF newlines."""
    with tokenize.open(path) as handle:
        return handle.read().replace("\r\n", "\n").replace("\r", "\n")


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = dotted_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return ""


def source_segment(source: str, node: ast.AST) -> str:
    segment = ast.get_source_segment(source, node)
    if segment is None:
        lines = source.splitlines()
        start = max(getattr(node, "lineno", 1) - 1, 0)
        end = max(getattr(node, "end_lineno", start + 1), start + 1)
        segment = "\n".join(lines[start:end])
    return segment


def assignment_names(node: ast.AST) -> List[str]:
    names: List[str] = []

    def visit(target: ast.AST) -> None:
        if isinstance(target, ast.Name):
            names.append(target.id)
        elif isinstance(target, (ast.Tuple, ast.List)):
            for element in target.elts:
                visit(element)
        elif isinstance(target, ast.Attribute):
            names.append(dotted_name(target))

    if isinstance(node, ast.Assign):
        for target in node.targets:
            visit(target)
    elif isinstance(node, (ast.AnnAssign, ast.AugAssign)):
        visit(node.target)
    return names or ["assignment"]


def is_statically_determined(node: Optional[ast.AST]) -> bool:
    """Return whether an expression's value is fixed by its syntax alone.

    Names, attributes, subscriptions, calls, comprehensions, awaits and yields
    depend on runtime state. Literal containers and expressions composed only
    from other statically determined expressions remain deterministic.
    """
    if node is None:
        return True
    if isinstance(node, ast.Constant):
        return True
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        return all(is_statically_determined(element) for element in node.elts)
    if isinstance(node, ast.Dict):
        return all(
            (key is None or is_statically_determined(key))
            and is_statically_determined(value)
            for key, value in zip(node.keys, node.values)
        )
    if isinstance(node, ast.UnaryOp):
        return is_statically_determined(node.operand)
    if isinstance(node, ast.BinOp):
        return is_statically_determined(node.left) and is_statically_determined(node.right)
    if isinstance(node, ast.BoolOp):
        return all(is_statically_determined(value) for value in node.values)
    if isinstance(node, ast.Compare):
        return is_statically_determined(node.left) and all(
            is_statically_determined(comparator) for comparator in node.comparators
        )
    if isinstance(node, ast.IfExp):
        return all(
            is_statically_determined(value)
            for value in (node.test, node.body, node.orelse)
        )
    if isinstance(node, ast.JoinedStr):
        return all(
            is_statically_determined(value.value)
            if isinstance(value, ast.FormattedValue)
            else is_statically_determined(value)
            for value in node.values
        )
    if isinstance(node, ast.Lambda):
        return True
    return False


def source_span_for_header(relative_path: str, source: str, node: ast.AST) -> str:
    """Return a half-open span for a compound statement's header only."""
    start_line = getattr(node, "lineno", 1)
    start_col = getattr(node, "col_offset", 0)
    body = getattr(node, "body", [])
    if body:
        first = body[0]
        first_line = getattr(first, "lineno", start_line)
        first_col = getattr(first, "col_offset", start_col)
        if first_line == start_line:
            end_line = start_line
            end_col = first_col
        else:
            end_line = first_line - 1
            lines = source.splitlines()
            end_col = len(lines[end_line - 1]) if 0 < end_line <= len(lines) else start_col
    else:
        end_line = getattr(node, "end_lineno", start_line)
        end_col = getattr(node, "end_col_offset", start_col)
    return f"{relative_path}:{start_line}:{start_col}-{end_line}:{end_col}"


class PythonFactCollector(ast.NodeVisitor):
    """Classify facts with an explicit, exclusive precedence.

    Precedence is measurement_pending > exception_handling > import > function
    > local_assignment > external_call. A call consumed as an assignment value,
    exception expression, or runtime measurement is not counted again as an
    external call.
    """

    def __init__(self, relative_path: str, source: str) -> None:
        self.relative_path = relative_path
        self.source = source
        self.facts: List[Fact] = []
        self.function_depth = 0

    def add(
        self,
        section: str,
        label: str,
        node: ast.AST,
        value: Optional[str],
        *,
        source_span_override: Optional[str] = None,
    ) -> None:
        line = getattr(node, "lineno", 1)
        col = getattr(node, "col_offset", 0)
        end_line = getattr(node, "end_lineno", line)
        end_col = getattr(node, "end_col_offset", col)
        digest = hashlib.sha256(
            f"{self.relative_path}:{line}:{col}:{section}:{label}".encode("utf-8")
        ).hexdigest()[:10]
        safe_label = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in label)
        key = f"{section}-{safe_label}-{line}-{col}-{digest}"
        self.facts.append(
            Fact(
                section=section,
                key=key,
                value=value,
                evidence=f"{self.relative_path}:{line}",
                source_span=source_span_override
                or f"{self.relative_path}:{line}:{col}-{end_line}:{end_col}",
            )
        )

    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            self.add("import", alias.asname or alias.name, node, source_segment(self.source, node))

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        module = "." * node.level + (node.module or "")
        for alias in node.names:
            label = f"{module}.{alias.asname or alias.name}"
            self.add("import", label, node, source_segment(self.source, node))

    def _visit_function(
        self, node: Union[ast.FunctionDef, ast.AsyncFunctionDef]
    ) -> None:
        self.add(
            "function",
            node.name,
            node,
            source_segment(self.source, node),
            source_span_override=source_span_for_header(
                self.relative_path, self.source, node
            ),
        )
        self.function_depth += 1
        for statement in node.body:
            self.visit(statement)
        self.function_depth -= 1

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node)

    def _visit_assignment(
        self, node: Union[ast.Assign, ast.AnnAssign, ast.AugAssign]
    ) -> None:
        value_node = getattr(node, "value", None)
        if self.function_depth > 0:
            section = (
                "local_assignment"
                if is_statically_determined(value_node)
                else "measurement_pending"
            )
            for name in assignment_names(node):
                self.add(
                    section,
                    name,
                    node,
                    source_segment(self.source, node)
                    if section == "local_assignment"
                    else None,
                )

    def visit_Assign(self, node: ast.Assign) -> None:
        self._visit_assignment(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        self._visit_assignment(node)

    def visit_AugAssign(self, node: ast.AugAssign) -> None:
        self._visit_assignment(node)

    def visit_Try(self, node: ast.Try) -> None:
        self.add(
            "exception_handling",
            "try",
            node,
            "try",
            source_span_override=(
                f"{self.relative_path}:{node.lineno}:{node.col_offset}"
                f"-{node.lineno}:{node.col_offset + 3}"
            ),
        )
        for statement in node.body:
            self.visit(statement)
        for handler in node.handlers:
            self.visit(handler)
        for statement in node.orelse:
            self.visit(statement)
        for statement in node.finalbody:
            self.visit(statement)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        label = dotted_name(node.type) if node.type is not None else "bare-except"
        self.add(
            "exception_handling",
            f"except-{label}",
            node,
            source_segment(self.source, node),
            source_span_override=source_span_for_header(
                self.relative_path, self.source, node
            ),
        )
        for statement in node.body:
            self.visit(statement)

    def visit_Raise(self, node: ast.Raise) -> None:
        self.add("exception_handling", "raise", node, source_segment(self.source, node))

    def visit_Call(self, node: ast.Call) -> None:
        name = dotted_name(node.func)
        if "." in name:
            self.add("external_call", name, node, source_segment(self.source, node))
        self.generic_visit(node)


def resolve_target(repo: pathlib.Path, relative_path: str) -> pathlib.Path:
    """Resolve one Python target without allowing repository-boundary escape."""
    candidate = pathlib.Path(relative_path)
    if candidate.is_absolute():
        raise ValueError(f"absolute target path is not allowed: {relative_path}")
    if ".." in candidate.parts:
        raise ValueError(f"parent traversal is not allowed: {relative_path}")
    if candidate.suffix != ".py":
        raise ValueError(f"Python profile accepts only .py targets: {relative_path}")

    resolved = (repo / candidate).resolve(strict=True)
    try:
        resolved.relative_to(repo)
    except ValueError as exc:
        raise ValueError(
            f"target resolves outside repository: {relative_path}"
        ) from exc
    if not resolved.is_file():
        raise ValueError(f"target is not a file: {relative_path}")
    return resolved


def collect(repo: pathlib.Path, relative_paths: Iterable[str]) -> List[Fact]:
    repo = repo.resolve(strict=True)
    if not repo.is_dir():
        raise ValueError(f"repository path is not a directory: {repo}")

    facts: List[Fact] = []
    for relative_path in relative_paths:
        path = resolve_target(repo, relative_path)
        source = read_source(path)
        tree = ast.parse(source, filename=relative_path, type_comments=True)
        collector = PythonFactCollector(relative_path, source)
        collector.visit(tree)
        facts.extend(collector.facts)
    return sorted(
        facts,
        key=lambda fact: (
            fact.evidence.rsplit(":", 1)[0],
            int(fact.evidence.rsplit(":", 1)[1]),
            fact.source_span,
            SECTIONS.index(fact.section),
            fact.key,
        ),
    )


def yaml_scalar(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def write_facts(
    output: pathlib.Path,
    repo: pathlib.Path,
    relative_paths: List[str],
    run_id: str,
    facts: List[Fact],
) -> None:
    lines = [
        f"run_id: {yaml_scalar(run_id)}",
        "profile: python",
        f"target_repo_path: {yaml_scalar(str(repo.resolve()))}",
        "target_file_paths:",
    ]
    lines.extend(f"  - {yaml_scalar(path)}" for path in relative_paths)
    lines.append("sections:")
    for section in SECTIONS:
        section_facts = [fact for fact in facts if fact.section == section]
        lines.append(f"  {section}:")
        if not section_facts:
            lines.extend(
                [
                    '    reason: "該当なし（決定的AST分類で対象構文0件）"',
                    "    items: []",
                ]
            )
            continue
        lines.extend(['    reason: ""', "    items:"])
        for fact in section_facts:
            lines.append(f"      - key: {yaml_scalar(fact.key)}")
            if fact.value is not None:
                lines.append(f"        value: {yaml_scalar(fact.value)}")
            lines.append(f"        evidence: {yaml_scalar(fact.evidence)}")
            lines.append(f"        source_span: {yaml_scalar(fact.source_span)}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_fixed_facts(path: pathlib.Path) -> Dict[str, List[Dict[str, str]]]:
    sections: Dict[str, List[Dict[str, str]]] = {
        section: [] for section in SECTIONS
    }
    current_section = ""
    current: Optional[Dict[str, str]] = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("  ") and not raw.startswith("    ") and raw.endswith(":"):
            current_section = raw.strip()[:-1]
            continue
        if raw.startswith("      - key:"):
            current = {"key": decode_scalar(raw.split(":", 1)[1].strip())}
            sections.setdefault(current_section, []).append(current)
            continue
        if current is not None and raw.startswith("        ") and ":" in raw:
            name, value = raw.strip().split(":", 1)
            current[name] = decode_scalar(value.strip())
    return sections


def decode_scalar(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return json.loads(value)
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    return value


def verify_function_bodies(
    facts_path: pathlib.Path, repo: pathlib.Path, relative_paths: List[str]
) -> List[str]:
    expected = {
        fact.key: fact.value
        for fact in collect(repo, relative_paths)
        if fact.section == "function"
    }
    actual = {
        item.get("key", ""): item.get("value")
        for item in parse_fixed_facts(facts_path).get("function", [])
    }
    errors: List[str] = []
    for key, value in expected.items():
        if key not in actual:
            errors.append(f"function-missing: {key}")
        elif actual[key] != value:
            errors.append(f"function-body-incomplete: {key}")
    for key in sorted(set(actual) - set(expected)):
        errors.append(f"function-orphan: {key}")
    return errors


def command_extract(args: argparse.Namespace) -> int:
    repo = pathlib.Path(args.repo).resolve()
    facts = collect(repo, args.files)
    write_facts(pathlib.Path(args.out), repo, args.files, args.run_id, facts)
    return 0


def command_counts(args: argparse.Namespace) -> int:
    repo = pathlib.Path(args.repo).resolve()
    facts = collect(repo, args.files)
    for section in SECTIONS:
        print(section, sum(fact.section == section for fact in facts))
    return 0


def command_verify_bodies(args: argparse.Namespace) -> int:
    errors = verify_function_bodies(
        pathlib.Path(args.facts),
        pathlib.Path(args.repo).resolve(),
        args.files,
    )
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("function-body-coverage PASS")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    extract = sub.add_parser("extract")
    extract.add_argument("--repo", required=True)
    extract.add_argument("--out", required=True)
    extract.add_argument("--run-id", default="extract-1")
    extract.add_argument("files", nargs="+")
    extract.set_defaults(func=command_extract)

    counts = sub.add_parser("counts")
    counts.add_argument("--repo", required=True)
    counts.add_argument("files", nargs="+")
    counts.set_defaults(func=command_counts)

    verify = sub.add_parser("verify-bodies")
    verify.add_argument("--facts", required=True)
    verify.add_argument("--repo", required=True)
    verify.add_argument("files", nargs="+")
    verify.set_defaults(func=command_verify_bodies)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except (OSError, SyntaxError, UnicodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
