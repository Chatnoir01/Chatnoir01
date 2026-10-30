#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import stat
from pathlib import Path

import civ1_roster_source_readiness as readiness

MAX_STATUS_BYTES = 1 << 20


def _regular_single_link_size(path: Path) -> int | None:
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        return None
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            return None
        return metadata.st_size
    finally:
        os.close(fd)


def status_within_bound(repo_root: Path) -> bool:
    if readiness._has_symlink_component(repo_root, tuple(readiness.STATUS_PATH.parts)):
        return False
    size = _regular_single_link_size(repo_root / readiness.STATUS_PATH)
    return size is not None and 0 < size <= MAX_STATUS_BYTES


def payload_sizes_match_manifest(repo_root: Path, status: object) -> bool:
    if not isinstance(status, dict):
        return False
    source_paths = status.get("source_paths")
    manifest = status.get("source_manifest")
    if not isinstance(source_paths, list) or not source_paths or not isinstance(manifest, dict):
        return False
    for source_path in source_paths:
        if not isinstance(source_path, str):
            return False
        record = manifest.get(source_path)
        if not isinstance(record, dict):
            return False
        expected_size = record.get("size_bytes")
        if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size <= 0:
            return False
        candidate = readiness._source_file(repo_root, source_path)
        if candidate is None or _regular_single_link_size(candidate) != expected_size:
            return False
    return True


def resource_bounds_green(repo_root: Path) -> bool:
    if not status_within_bound(repo_root):
        return False
    try:
        raw = readiness._read_regular_single_link(repo_root / readiness.STATUS_PATH)
        if raw is None:
            return False
        status = readiness._loads_strict_json(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, readiness.DuplicateJSONKeyError, readiness.NonStandardJSONConstantError):
        return False
    if not isinstance(status, dict):
        return False
    # A blocked intake may truthfully describe upstream files that are not materialized yet.
    # Bound the status read now; require payload preflight only once the package claims presence.
    if status.get("source_package_present") is not True:
        return True
    return payload_sizes_match_manifest(repo_root, status)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args = parser.parse_args()
    if not resource_bounds_green(args.repo_root):
        print("CIV1_ROSTER_RESOURCE_BOUNDS_RED")
        return 2
    print("CIV1_ROSTER_RESOURCE_BOUNDS_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
