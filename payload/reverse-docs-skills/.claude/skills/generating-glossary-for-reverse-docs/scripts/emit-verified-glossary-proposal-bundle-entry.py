#!/usr/bin/env python3
"""Emit one captured entry from a verified proposal bundle without reopening source paths."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--entry", required=True, choices=("proposal", "diagnostics"))
    args = parser.parse_args()
    try:
        bundle = json.loads(args.bundle.read_text(encoding="utf-8"))
        if (
            bundle.get("bundleVersion") != "1.0.0"
            or bundle.get("guarantee") != "captured_verified_bytes_only"
        ):
            raise ValueError("unsupported verified bundle")
        entry = bundle[args.entry]
        content = base64.b64decode(entry["contentBase64"], validate=True)
        if (
            len(content) != entry["byteLength"]
            or hashlib.sha256(content).hexdigest() != entry["sha256"]
        ):
            raise ValueError("verified bundle entry hash mismatch")
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, binascii.Error, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
