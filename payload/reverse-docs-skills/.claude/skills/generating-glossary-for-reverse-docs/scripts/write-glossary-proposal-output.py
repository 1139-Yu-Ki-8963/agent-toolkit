#!/usr/bin/env python3
"""Create proposal and diagnostics once in one verified directory descriptor."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CreatedOutput:
    name: str
    identity: tuple[int, int]
    expected_bytes: bytes
    expected_hash: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-repo", required=True, type=Path)
    parser.add_argument("--proposal-output", required=True, type=Path)
    parser.add_argument("--proposal-input", required=True, type=Path)
    parser.add_argument("--diagnostics-input", required=True, type=Path)
    return parser.parse_args()


def is_within(path: Path, root: Path) -> bool:
    try:
        return os.path.commonpath((str(path), str(root))) == str(root)
    except ValueError:
        return False


def read_inputs(proposal: Path, diagnostics: Path) -> tuple[bytes, bytes]:
    try:
        proposal_bytes = proposal.read_bytes()
        diagnostics_bytes = diagnostics.read_bytes()
        json.loads(diagnostics_bytes.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read writer input: {error}") from error
    if not proposal_bytes:
        raise ValueError("proposal input must not be empty")
    return proposal_bytes, diagnostics_bytes


def directory_identity(directory_fd: int) -> tuple[int, int]:
    value = os.fstat(directory_fd)
    return value.st_dev, value.st_ino


def require_owner_only_directory(directory_fd: int) -> None:
    value = os.fstat(directory_fd)
    if value.st_uid != os.geteuid() or stat.S_IMODE(value.st_mode) != 0o700:
        raise ValueError("proposal output directory must be owned by the writer and have mode 0700")


def path_identity(path: Path) -> tuple[int, int] | None:
    try:
        value = path.stat(follow_symlinks=False)
    except FileNotFoundError:
        return None
    return value.st_dev, value.st_ino


def create_file(directory_fd: int, name: str, content: bytes) -> CreatedOutput:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    file_fd = os.open(name, flags, 0o600, dir_fd=directory_fd)
    try:
        view = memoryview(content)
        while view:
            written = os.write(file_fd, view)
            if written <= 0:
                raise OSError("short write")
            view = view[written:]
        os.fsync(file_fd)
        value = os.fstat(file_fd)
        if not stat.S_ISREG(value.st_mode) or value.st_nlink != 1:
            raise OSError("created output is not a private regular file")
        created = CreatedOutput(
            name=name,
            identity=(value.st_dev, value.st_ino),
            expected_bytes=content,
            expected_hash=hashlib.sha256(content).hexdigest(),
        )
    finally:
        os.close(file_fd)
    return created


def entry_identity(directory_fd: int, name: str) -> tuple[int, int] | None:
    try:
        value = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    return value.st_dev, value.st_ino


def verify_created(directory_fd: int, created: CreatedOutput) -> dict[str, object]:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    file_fd = os.open(created.name, flags, dir_fd=directory_fd)
    try:
        before = os.fstat(file_fd)
        if (
            (before.st_dev, before.st_ino) != created.identity
            or not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
        ):
            raise OSError(f"created output identity changed: {created.name}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        actual_bytes = b"".join(chunks)
        after = os.fstat(file_fd)
        if (
            (after.st_dev, after.st_ino) != created.identity
            or not stat.S_ISREG(after.st_mode)
            or after.st_nlink != 1
        ):
            raise OSError(f"created output changed while verifying: {created.name}")
    finally:
        os.close(file_fd)
    named = os.stat(created.name, dir_fd=directory_fd, follow_symlinks=False)
    if (
        (named.st_dev, named.st_ino) != created.identity
        or not stat.S_ISREG(named.st_mode)
        or named.st_nlink != 1
    ):
        raise OSError(f"created output name was replaced: {created.name}")
    actual_hash = hashlib.sha256(actual_bytes).hexdigest()
    if actual_bytes != created.expected_bytes or actual_hash != created.expected_hash:
        raise OSError(f"created output content changed: {created.name}")
    return {
        "name": created.name,
        "sha256": actual_hash,
        "device": named.st_dev,
        "inode": named.st_ino,
    }


def final_verification(
    directory_fd: int,
    parent_requested: Path,
    expected_directory_identity: tuple[int, int],
    created_outputs: list[CreatedOutput],
) -> list[dict[str, object]]:
    if path_identity(parent_requested) != expected_directory_identity:
        raise ValueError("proposal output directory changed before final verification")
    require_owner_only_directory(directory_fd)
    verified = [verify_created(directory_fd, output) for output in created_outputs]
    if path_identity(parent_requested) != expected_directory_identity:
        raise ValueError("proposal output directory changed during final verification")
    require_owner_only_directory(directory_fd)
    return verified


def remove_created(directory_fd: int, created_outputs: list[CreatedOutput]) -> None:
    for created in reversed(created_outputs):
        try:
            if entry_identity(directory_fd, created.name) == created.identity:
                os.unlink(created.name, dir_fd=directory_fd)
        except FileNotFoundError:
            pass


def write_outputs(args: argparse.Namespace) -> dict[str, object]:
    if not args.target_repo.is_absolute() or not args.target_repo.is_dir():
        raise ValueError("--target-repo must be an existing absolute directory")
    if not args.proposal_output.is_absolute():
        raise ValueError("--proposal-output must be an explicit absolute path")
    if args.proposal_output.suffix.lower() not in {".yaml", ".yml"}:
        raise ValueError("--proposal-output must end in .yaml or .yml")

    target = args.target_repo.resolve(strict=True)
    parent_requested = args.proposal_output.parent
    parent = parent_requested.resolve(strict=True)
    if not parent.is_dir() or is_within(parent, target):
        raise ValueError("proposal output directory must exist outside --target-repo")
    if parent_requested != parent:
        raise ValueError("proposal output directory must not contain symlink components")

    proposal_name = args.proposal_output.name
    diagnostics_name = f"{proposal_name}.diagnostics.json"
    if not proposal_name or proposal_name in {".", ".."}:
        raise ValueError("proposal output filename is invalid")

    proposal_bytes, diagnostics_bytes = read_inputs(
        args.proposal_input, args.diagnostics_input
    )
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    if hasattr(os, "O_NOFOLLOW"):
        directory_flags |= os.O_NOFOLLOW
    directory_fd = os.open(parent, directory_flags)
    created: list[CreatedOutput] = []
    try:
        require_owner_only_directory(directory_fd)
        expected_identity = directory_identity(directory_fd)
        if path_identity(parent_requested) != expected_identity:
            raise ValueError("proposal output directory changed during verification")
        created.append(create_file(directory_fd, proposal_name, proposal_bytes))
        created.append(create_file(directory_fd, diagnostics_name, diagnostics_bytes))
        os.fsync(directory_fd)
        verified = final_verification(
            directory_fd, parent_requested, expected_identity, created
        )
    except BaseException:
        remove_created(directory_fd, created)
        raise
    finally:
        os.close(directory_fd)
    proposal_receipt, diagnostics_receipt = verified
    return {
        "receiptVersion": "1.0.0",
        "guarantee": "creation_transaction_and_receipt_issuance",
        "outputDirectory": {
            "path": str(parent),
            "device": expected_identity[0],
            "inode": expected_identity[1],
        },
        "proposal": proposal_receipt,
        "diagnostics": diagnostics_receipt,
    }


def main() -> int:
    try:
        receipt = write_outputs(parse_args())
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
