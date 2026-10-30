#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import civ1_roster_source_readiness as readiness


def hardlink_violations(repo_root: Path) -> list[str]:
    """Reject READY CIV-1 source payloads that alias another inode via hard links."""
    status = readiness._load_strict_json(repo_root / readiness.STATUS_PATH)
    if not isinstance(status, dict):
        return ["invalid_status"]
    # A blocked/not-yet-materialized candidate has no source authority to police yet.
    if not all(status.get(flag) is True for flag in readiness.REQUIRED_READY_FLAGS):
        return []
    source_paths = status.get("source_paths")
    if not isinstance(source_paths, list) or not source_paths:
        return ["invalid_source_paths"]
    bad: list[str] = []
    for source_path in source_paths:
        candidate = readiness._source_file(repo_root, source_path)
        if candidate is None or not candidate.is_file():
            bad.append(str(source_path))
            continue
        try:
            if candidate.stat().st_nlink != 1:
                bad.append(str(source_path))
        except OSError:
            bad.append(str(source_path))
    return bad


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args = parser.parse_args()
    try:
        bad = hardlink_violations(args.repo_root)
    except (OSError, ValueError, readiness.DuplicateJSONKeyError, readiness.NonStandardJSONConstantError) as exc:
        print(f"CIV1_SOURCE_HARDLINK_INTEGRITY_ERROR {exc}")
        return 2
    if bad:
        print("CIV1_SOURCE_HARDLINK_INTEGRITY_FORBIDDEN " + repr(sorted(set(bad))))
        return 2
    print("CIV1_SOURCE_HARDLINK_INTEGRITY_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
