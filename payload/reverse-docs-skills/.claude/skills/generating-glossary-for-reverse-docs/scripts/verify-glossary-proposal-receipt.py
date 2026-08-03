#!/usr/bin/env python3
"""Revalidate proposal outputs against a safely transferred writer receipt."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import stat
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    return parser.parse_args()


def read_receipt(path: Path) -> tuple[dict[str, object], bytes]:
    try:
        receipt_bytes = path.read_bytes()
        value = json.loads(receipt_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read receipt: {error}") from error
    if (
        not isinstance(value, dict)
        or value.get("receiptVersion") != "1.0.0"
        or value.get("guarantee") != "creation_transaction_and_receipt_issuance"
    ):
        raise ValueError("unsupported receipt")
    return value, receipt_bytes


def verify_entry(directory_fd: int, entry: object) -> dict[str, object]:
    if not isinstance(entry, dict):
        raise ValueError("receipt output entry must be an object")
    name = entry.get("name")
    expected_hash = entry.get("sha256")
    expected_device = entry.get("device")
    expected_inode = entry.get("inode")
    if (
        not isinstance(name, str)
        or Path(name).name != name
        or name in {"", ".", ".."}
        or not isinstance(expected_hash, str)
        or len(expected_hash) != 64
        or not isinstance(expected_device, int)
        or not isinstance(expected_inode, int)
    ):
        raise ValueError("receipt output entry is invalid")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    file_fd = os.open(name, flags, dir_fd=directory_fd)
    try:
        value = os.fstat(file_fd)
        content = bytearray()
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            content.extend(chunk)
        after = os.fstat(file_fd)
    finally:
        os.close(file_fd)
    expected_identity = (expected_device, expected_inode)
    for current in (value, after):
        if (
            (current.st_dev, current.st_ino) != expected_identity
            or not stat.S_ISREG(current.st_mode)
            or current.st_nlink != 1
        ):
            raise ValueError(f"receipt identity mismatch: {name}")
    actual_hash = hashlib.sha256(content).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError(f"receipt revalidation failed: {name}")
    return {
        "sourceName": name,
        "sha256": actual_hash,
        "device": after.st_dev,
        "inode": after.st_ino,
        "byteLength": len(content),
        "contentBase64": base64.b64encode(content).decode("ascii"),
    }


def verify(args: argparse.Namespace) -> dict[str, object]:
    receipt, receipt_bytes = read_receipt(args.receipt)
    if not args.output_directory.is_absolute():
        raise ValueError("--output-directory must be absolute")
    directory = args.output_directory.resolve(strict=True)
    directory_receipt = receipt.get("outputDirectory")
    if not isinstance(directory_receipt, dict) or directory_receipt.get("path") != str(directory):
        raise ValueError("receipt output directory mismatch")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(directory, flags)
    try:
        value = os.fstat(directory_fd)
        if (
            (value.st_dev, value.st_ino)
            != (directory_receipt.get("device"), directory_receipt.get("inode"))
            or value.st_uid != os.geteuid()
            or stat.S_IMODE(value.st_mode) != 0o700
        ):
            raise ValueError("receipt output directory identity or permissions changed")
        proposal = verify_entry(directory_fd, receipt.get("proposal"))
        diagnostics = verify_entry(directory_fd, receipt.get("diagnostics"))
    finally:
        os.close(directory_fd)
    return {
        "bundleVersion": "1.0.0",
        "sourceReceiptSha256": hashlib.sha256(receipt_bytes).hexdigest(),
        "guarantee": "captured_verified_bytes_only",
        "proposal": proposal,
        "diagnostics": diagnostics,
    }


def main() -> int:
    try:
        bundle = verify(parse_args())
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(bundle, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
