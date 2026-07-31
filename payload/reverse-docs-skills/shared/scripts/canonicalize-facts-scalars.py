#!/usr/bin/env python3
"""Canonicalize fixed facts.yml key/value scalars without erasing YAML types."""

import json
import re
import sys


FIELD_RE = re.compile(r"^(\s*(?:- key|value):\s*)(.*)$")
INTEGER_RE = re.compile(r"^[+-]?(?:0|[1-9][0-9_]*|0o[0-7_]+|0x[0-9a-fA-F_]+)$")
FLOAT_RE = re.compile(
    r"^[+-]?(?:"
    r"(?:[0-9][0-9_]*)?\.[0-9_]+(?:[eE][+-]?[0-9]+)?"
    r"|[0-9][0-9_]*[eE][+-]?[0-9]+"
    r"|\.inf|\.nan"
    r")$",
    re.IGNORECASE,
)


def tagged(kind, value):
    return "@{}:{}".format(
        kind,
        json.dumps(value, ensure_ascii=False, separators=(",", ":")),
    )


def canonical_scalar(raw):
    token = raw.strip()
    if len(token) >= 2 and token[0] == token[-1] == '"':
        value = json.loads(token)
        if not isinstance(value, str):
            raise ValueError("double-quoted YAML scalar did not decode as string")
        return tagged("string", value)
    if len(token) >= 2 and token[0] == token[-1] == "'":
        return tagged("string", token[1:-1].replace("''", "'"))

    lowered = token.lower()
    if lowered in ("null", "~"):
        return tagged("null", None)
    if lowered in ("true", "false"):
        return tagged("boolean", lowered == "true")
    if INTEGER_RE.match(token):
        return tagged("integer", token.replace("_", "").lower())
    if FLOAT_RE.match(token):
        return tagged("float", token.replace("_", "").lower())
    return tagged("string", token)


def main():
    # stdin/stdout の encoding を明示し、実行環境の locale に依存しないようにする。
    # strict locale 環境（LC_ALL=C 等）でも UnicodeDecodeError を出さず、
    # 復号できないバイト列は surrogateescape で保持して往復させる。
    sys.stdin.reconfigure(encoding="utf-8", errors="surrogateescape")
    sys.stdout.reconfigure(encoding="utf-8", errors="surrogateescape")

    for raw_line in sys.stdin:
        line = raw_line.rstrip("\n")
        match = FIELD_RE.match(line)
        if match is None:
            print(line)
            continue
        try:
            canonical = canonical_scalar(match.group(2))
        except (TypeError, ValueError) as exc:
            print("invalid fixed facts scalar: {} ({})".format(line, exc), file=sys.stderr)
            return 2
        print("{}{}".format(match.group(1), canonical))
    return 0


if __name__ == "__main__":
    sys.exit(main())
