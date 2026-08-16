#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-thandi-source-status-v1"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Thandi source status must be a JSON object")
    return value


def validate(root: Path, status_path: Path) -> dict[str, Any]:
    status = _read(status_path)
    if status.get("format") != FORMAT:
        raise ValueError("unsupported Thandi source status format")
    required = status.get("required_files")
    if not isinstance(required, list) or not required or not all(isinstance(path, str) and path for path in required):
        raise ValueError("required_files must be a non-empty string list")
    runtime_asset = status.get("runtime_asset")
    if not isinstance(runtime_asset, str) or not runtime_asset:
        raise ValueError("runtime_asset missing")

    present_required = [path for path in required if (root / path).is_file() and (root / path).stat().st_size > 0]
    missing_required = [path for path in required if path not in present_required]
    declared_source = status.get("source_package_present") is True
    actual_source = not missing_required
    if declared_source and not actual_source:
        raise ValueError(f"status says source package present but required files are missing: {missing_required}")
    if not declared_source and present_required:
        raise ValueError(f"status says source package absent but source files are present: {present_required}")

    runtime_path = root / runtime_asset
    actual_runtime = runtime_path.is_file() and runtime_path.stat().st_size > 0
    declared_runtime = status.get("runtime_authored_asset_present") is True
    if declared_runtime != actual_runtime:
        raise ValueError(f"runtime authored asset status mismatch declared={declared_runtime} actual={actual_runtime}")

    blocker = status.get("blocker")
    if not declared_source and not blocker:
        raise ValueError("missing source package must have an explicit blocker")
    if declared_source and blocker == "source_binary_and_textures_not_committed":
        raise ValueError("source blocker is stale after package becomes present")

    return {
        "truthful": True,
        "source_package_present": actual_source,
        "runtime_asset_present": actual_runtime,
        "missing_required_files": missing_required,
        "blocker": blocker,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.root, args.status)
    print("THANDI_SOURCE_STATUS_OK", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
