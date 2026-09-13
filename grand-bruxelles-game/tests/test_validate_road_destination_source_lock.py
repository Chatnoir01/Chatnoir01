#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"


def _run(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    if not VALIDATOR.is_file():
        raise AssertionError(f"required validator missing: {VALIDATOR.relative_to(PROJECT)}")
    return subprocess.run(
        [sys.executable, str(VALIDATOR), "--lock", str(lock_path), "--source", str(source_path)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _expect_rejected(lock_doc: dict[str, object], source_doc: dict[str, object], needle: str) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-road-source-lock-") as tmp:
        root = Path(tmp)
        lock_path = root / "road_destination_sources.lock.json"
        source_path = root / "vertical_slice_01.game.json"
        lock_path.write_text(json.dumps(lock_doc, sort_keys=True, allow_nan=False), encoding="utf-8")
        source_path.write_text(json.dumps(source_doc, separators=(",", ":"), allow_nan=False), encoding="utf-8")
        result = _run(lock_path, source_path)
        assert result.returncode != 0, result.stdout
        assert needle.lower() in (result.stdout + result.stderr).lower(), result.stderr


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = _run(LOCK, SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    assert "ROAD_DESTINATION_SOURCE_LOCK_OK" in baseline.stdout

    bad_license = dict(lock_doc)
    bad_license["license"] = "UNKNOWN"
    _expect_rejected(bad_license, source_doc, "license")

    bad_digest = json.loads(json.dumps(lock_doc))
    docs = bad_digest["documents"]
    assert isinstance(docs, dict)
    docs["data/osm/vertical_slice_01.game.json"] = "0" * 64
    _expect_rejected(bad_digest, source_doc, "sha256")

    bad_stats = json.loads(json.dumps(source_doc))
    stats = bad_stats["stats"]
    assert isinstance(stats, dict)
    stats["roads"] = int(stats["roads"]) + 1
    _expect_rejected(lock_doc, bad_stats, "accounting")

    bad_source_stats = json.loads(json.dumps(source_doc))
    source_stats = bad_source_stats["source_stats"]
    assert isinstance(source_stats, dict)
    source_stats["drivable_roads"] = int(source_stats["roads"]) + 1
    _expect_rejected(lock_doc, bad_source_stats, "source_stats")

    print("ROAD_DESTINATION_SOURCE_LOCK_TEST_OK digest=true provenance=true accounting=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
