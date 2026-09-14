#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SOURCE_LOCK_VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
ORIGIN_VALIDATOR = PROJECT / "tools" / "validate_road_destination_origin_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"


def _run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _run(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    source_lock = _run_command(
        [
            sys.executable,
            str(SOURCE_LOCK_VALIDATOR),
            "--source-root",
            str(source_path.parent),
            "--lock",
            str(lock_path),
        ]
    )
    if source_lock.returncode != 0:
        return source_lock
    return _run_command(
        [
            sys.executable,
            str(ORIGIN_VALIDATOR),
            "--source",
            str(source_path),
        ]
    )


def _mutated_result(axis: str, delta: float) -> subprocess.CompletedProcess[str]:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    source_doc["origin"][axis] = float(source_doc["origin"][axis]) + delta

    with tempfile.TemporaryDirectory(prefix="gb-road-origin-lock-") as tmp:
        source_root = Path(tmp) / "data" / "osm"
        source_root.mkdir(parents=True)
        source_path = source_root / "vertical_slice_01.game.json"
        lock_path = source_root / "road_destination_sources.lock.json"

        source_bytes = json.dumps(
            source_doc,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
        source_path.write_bytes(source_bytes)
        lock_doc["documents"][SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
        lock_path.write_text(
            json.dumps(lock_doc, sort_keys=True, allow_nan=False),
            encoding="utf-8",
        )
        return _run(lock_path, source_path)


def main() -> int:
    baseline = _run(LOCK, SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr

    for axis, delta in (("lat", 0.001), ("lon", -0.001)):
        result = _mutated_result(axis, delta)
        assert result.returncode != 0, (
            f"source lock accepted origin.{axis} drift with recomputed digest; "
            "the game-frame origin must be semantically pinned"
        )
        combined = (result.stdout + result.stderr).lower()
        assert "origin" in combined and ("drift" in combined or axis in combined), combined

    print(
        "ROAD_DESTINATION_ORIGIN_LOCK_TEST_OK "
        "lat=true lon=true digest_recompute_resistant=true exact_schema=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
