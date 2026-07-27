#!/usr/bin/env python3
"""Independent Python fact counter and source-span validator.

This module deliberately does not import the extractor. It implements the
profile contract independently so an extractor regression cannot make recount
agree by construction.
"""

import argparse
import ast
import json
import pathlib
import re
import sys
import tokenize
from collections import Counter
from typing import List, Optional, Tuple, Union


def require_runtime_version(version_info=None) -> None:
    """Fail before AST processing on Python older than 3.8."""
    version = sys.version_info if version_info is None else version_info
    if tuple(version[:2]) < (3, 8):
        print(
            "ERROR: profile=python requires Python 3.8 or newer "
            "(AST end-position metadata is mandatory)",
            file=sys.stderr,
        )
        raise SystemExit(2)


require_runtime_version()


SECTIONS = (
    "import",
    "function",
    "local_assignment",
    "external_call",
    "exception_handling",
    "measurement_pending",
)
LITERAL_NODES = (ast.Constant,)


def read_source(path: pathlib.Path) -> str:
    with tokenize.open(path) as handle:
        return handle.read().replace("\r\n", "\n").replace("\r", "\n")


def call_name(node: ast.AST) -> str:
    parts = []  # type: List[str]
    current = node
    while isinstance(current, ast.Attribute):
        parts.append(current.attr)
        current = current.value
    if isinstance(current, ast.Name):
        parts.append(current.id)
    return ".".join(reversed(parts))


def target_count(node: Union[ast.Assign, ast.AnnAssign, ast.AugAssign]) -> int:
    count = 0

    def visit(target: ast.AST) -> None:
        nonlocal count
        if isinstance(target, (ast.Name, ast.Attribute)):
            count += 1
        elif isinstance(target, (ast.Tuple, ast.List)):
            for element in target.elts:
                visit(element)

    if isinstance(node, ast.Assign):
        for target in node.targets:
            visit(target)
    else:
        visit(node.target)
    return count or 1


def expression_is_static(node: Optional[ast.AST]) -> bool:
    if node is None:
        return True
    if isinstance(node, LITERAL_NODES):
        return True
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        return all(expression_is_static(element) for element in node.elts)
    if isinstance(node, ast.Dict):
        return all(
            (key is None or expression_is_static(key)) and expression_is_static(value)
            for key, value in zip(node.keys, node.values)
        )
    if isinstance(node, ast.UnaryOp):
        return expression_is_static(node.operand)
    if isinstance(node, ast.BinOp):
        return expression_is_static(node.left) and expression_is_static(node.right)
    if isinstance(node, ast.BoolOp):
        return all(expression_is_static(value) for value in node.values)
    if isinstance(node, ast.Compare):
        return expression_is_static(node.left) and all(
            expression_is_static(comparator) for comparator in node.comparators
        )
    if isinstance(node, ast.IfExp):
        return (
            expression_is_static(node.test)
            and expression_is_static(node.body)
            and expression_is_static(node.orelse)
        )
    if isinstance(node, ast.JoinedStr):
        for value in node.values:
            nested = value.value if isinstance(value, ast.FormattedValue) else value
            if not expression_is_static(nested):
                return False
        return True
    return isinstance(node, ast.Lambda)


class IndependentCounter(ast.NodeVisitor):
    def __init__(self) -> None:
        self.counts = Counter()
        self.function_depth = 0

    def visit_Import(self, node: ast.Import) -> None:
        self.counts["import"] += len(node.names)

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        self.counts["import"] += len(node.names)

    def _function(self, node: Union[ast.FunctionDef, ast.AsyncFunctionDef]) -> None:
        self.counts["function"] += 1
        self.function_depth += 1
        for statement in node.body:
            self.visit(statement)
        self.function_depth -= 1

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._function(node)

    def _assignment(
        self, node: Union[ast.Assign, ast.AnnAssign, ast.AugAssign]
    ) -> None:
        if self.function_depth == 0:
            return
        section = (
            "local_assignment"
            if expression_is_static(getattr(node, "value", None))
            else "measurement_pending"
        )
        self.counts[section] += target_count(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        self._assignment(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        self._assignment(node)

    def visit_AugAssign(self, node: ast.AugAssign) -> None:
        self._assignment(node)

    def visit_Try(self, node: ast.Try) -> None:
        self.counts["exception_handling"] += 1
        for statement in node.body:
            self.visit(statement)
        for handler in node.handlers:
            self.visit(handler)
        for statement in node.orelse:
            self.visit(statement)
        for statement in node.finalbody:
            self.visit(statement)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        self.counts["exception_handling"] += 1
        for statement in node.body:
            self.visit(statement)

    def visit_Raise(self, node: ast.Raise) -> None:
        self.counts["exception_handling"] += 1

    def visit_Call(self, node: ast.Call) -> None:
        if "." in call_name(node.func):
            self.counts["external_call"] += 1
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


def independent_counts(repo: pathlib.Path, files: List[str]) -> Counter:
    repo = repo.resolve(strict=True)
    if not repo.is_dir():
        raise ValueError(f"repository path is not a directory: {repo}")
    result = Counter()
    for relative_path in files:
        path = resolve_target(repo, relative_path)
        tree = ast.parse(read_source(path), filename=relative_path)
        counter = IndependentCounter()
        counter.visit(tree)
        result.update(counter.counts)
    return result


SPAN_RE = re.compile(r"^(.*):(\d+):(\d+)-(\d+):(\d+)$")


def decode_scalar(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return str(json.loads(value))
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    return value


def read_span_items(
    facts_path: pathlib.Path, target_files: List[str]
) -> Tuple[
    List[Tuple[str, str, str, Tuple[int, int], Tuple[int, int]]],
    List[str],
]:
    section = ""
    current_key = None  # type: Optional[str]
    evidence_values = []  # type: List[str]
    span_values = []  # type: List[str]
    spans = []  # type: List[Tuple[str, str, str, Tuple[int, int], Tuple[int, int]]]
    errors = []  # type: List[str]
    allowed_targets = set(target_files)

    def flush_item() -> None:
        if current_key is None or section not in SECTIONS:
            return
        item_label = "{}:{}".format(section, current_key)
        if len(evidence_values) != 1:
            errors.append(
                "{} evidence-count={} expected=1".format(
                    item_label, len(evidence_values)
                )
            )
        if len(span_values) != 1:
            errors.append(
                "{} source-span-count={} expected=1".format(
                    item_label, len(span_values)
                )
            )
        if len(evidence_values) != 1 or len(span_values) != 1:
            return

        evidence = evidence_values[0]
        evidence_match = re.fullmatch(r"^(.*):(\d+)$", evidence)
        if evidence_match is None or not evidence_match.group(1):
            errors.append("{} invalid-evidence={}".format(item_label, evidence))
            return
        evidence_path = evidence_match.group(1)

        value = span_values[0]
        match = SPAN_RE.fullmatch(value)
        if match is None:
            errors.append("{} invalid-source-span={}".format(item_label, value))
            return
        path, start_line, start_col, end_line, end_col = match.groups()
        start = (int(start_line), int(start_col))
        end = (int(end_line), int(end_col))
        if start >= end:
            errors.append(
                "{} invalid-source-span-range={}-{}".format(item_label, start, end)
            )
        if path != evidence_path:
            errors.append(
                "{} span-path={} evidence-path={}".format(
                    item_label, path, evidence_path
                )
            )
        if path not in allowed_targets:
            errors.append(
                "{} span-path-not-target={}".format(item_label, path)
            )
        if start < end and path == evidence_path and path in allowed_targets:
            spans.append((section, current_key, path, start, end))

    for raw in facts_path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("  ") and not raw.startswith("    ") and raw.endswith(":"):
            flush_item()
            section = raw.strip()[:-1]
            current_key = None
            evidence_values = []
            span_values = []
            continue
        if raw.startswith("      - key:"):
            flush_item()
            current_key = decode_scalar(raw.split(":", 1)[1].strip())
            evidence_values = []
            span_values = []
            continue
        if current_key is None:
            continue
        if raw.startswith("        evidence:"):
            evidence_values.append(decode_scalar(raw.split(":", 1)[1].strip()))
        elif raw.startswith("        source_span:"):
            span_values.append(decode_scalar(raw.split(":", 1)[1].strip()))
    flush_item()
    return spans, errors


def validate_cross_section_spans(
    facts_path: pathlib.Path, target_files: List[str]
) -> List[str]:
    spans, errors = read_span_items(facts_path, target_files)
    for index, left in enumerate(spans):
        for right in spans[index + 1 :]:
            if left[0] == right[0] or left[2] != right[2]:
                continue
            if left[3] < right[4] and right[3] < left[4]:
                errors.append(
                    f"cross-section-overlap: {left[0]}:{left[1]} "
                    f"{left[3]}-{left[4]} <-> {right[0]}:{right[1]} "
                    f"{right[3]}-{right[4]} ({left[2]})"
                )
    return errors


def command_counts(args: argparse.Namespace) -> int:
    counts = independent_counts(pathlib.Path(args.repo).resolve(), args.files)
    for section in SECTIONS:
        print(section, counts[section])
    return 0


def command_validate_spans(args: argparse.Namespace) -> int:
    errors = validate_cross_section_spans(
        pathlib.Path(args.facts), args.target_files
    )
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("cross-section-span-overlap 0")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command")
    counts = subparsers.add_parser("counts")
    counts.add_argument("--repo", required=True)
    counts.add_argument("files", nargs="+")
    counts.set_defaults(func=command_counts)
    validate = subparsers.add_parser("validate-spans")
    validate.add_argument("--facts", required=True)
    validate.add_argument("--target-file", dest="target_files", action="append", required=True)
    validate.set_defaults(func=command_validate_spans)
    args = parser.parse_args()
    if args.command is None:
        parser.error("a command is required")
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
