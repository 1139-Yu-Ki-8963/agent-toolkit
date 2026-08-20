#!/usr/bin/env python3
"""Validate captured proposal bytes from a verified bundle via an anonymous file descriptor."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--validator", required=True, type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    return parser.parse_args()


def proposal_bytes(bundle_path: Path) -> bytes:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    if (
        bundle.get("bundleVersion") != "1.0.0"
        or bundle.get("guarantee") != "captured_verified_bytes_only"
    ):
        raise ValueError("unsupported verified bundle")
    entry = bundle["proposal"]
    content = base64.b64decode(entry["contentBase64"], validate=True)
    if (
        len(content) != entry["byteLength"]
        or hashlib.sha256(content).hexdigest() != entry["sha256"]
    ):
        raise ValueError("verified proposal bundle hash mismatch")
    return content


def run(args: argparse.Namespace) -> int:
    if not args.validator.is_file():
        raise ValueError("validator is unavailable")
    content = proposal_bytes(args.bundle)
    file_fd, staging_path = tempfile.mkstemp(prefix="verified-proposal-", suffix=".yaml")
    staging_unlinked = False
    try:
        os.fchmod(file_fd, 0o600)
        os.unlink(staging_path)
        staging_unlinked = True
        view = memoryview(content)
        while view:
            written = os.write(file_fd, view)
            if written <= 0:
                raise OSError("short write while staging verified bytes")
            view = view[written:]
        os.fsync(file_fd)
        os.lseek(file_fd, 0, os.SEEK_SET)
        command = [
            str(args.validator),
            "--kind",
            "proposal",
            "--input",
            f"/dev/fd/{file_fd}",
        ]
        if args.registry is not None:
            command.extend(["--registry", str(args.registry)])
        command.extend(["--report", str(args.report)])
        result = subprocess.run(command, pass_fds=(file_fd,), check=False)
        return result.returncode
    finally:
        if not staging_unlinked:
            try:
                os.unlink(staging_path)
            except FileNotFoundError:
                pass
        os.close(file_fd)


def main() -> int:
    try:
        return run(parse_args())
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, binascii.Error, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
