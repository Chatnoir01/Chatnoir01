#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

import civ1_roster_source_readiness as readiness


def _status_path(root: Path) -> Path:
    path = root / readiness.STATUS_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def main() -> int:
    original = readiness._status_consistent
    readiness._status_consistent = lambda status, repo_root: status == {"probe": "ok"}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            status = _status_path(root)
            status.write_text(json.dumps({"probe": "ok"}), encoding="utf-8")
            if not readiness.source_ready(root):
                raise AssertionError("ordinary regular status control must remain eligible")

            status.unlink()
            if not hasattr(os, "mkfifo"):
                print("CIV1_ROSTER_STATUS_REGULAR_FILE_INTEGRITY_SKIPPED_NO_MKFIFO")
                return 0
            os.mkfifo(status)
            if readiness.source_ready(root):
                raise AssertionError("FIFO source_status.json must not establish CIV-1 READY authority")
    finally:
        readiness._status_consistent = original

    print("CIV1_ROSTER_STATUS_REGULAR_FILE_INTEGRITY_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
