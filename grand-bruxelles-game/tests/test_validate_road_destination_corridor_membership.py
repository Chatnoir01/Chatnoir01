#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"


def run_validator(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "--source-root",
            str(source_path.parent),
            "--lock",
            str(lock_path),
        ],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = run_validator(LOCK, SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr

    corrupted = json.loads(json.dumps(source_doc))
    roads = corrupted["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    # Historical make_runtime_slice.py selects a road only when at least one road
    # VERTEX lies within selection_radius_m.roads of the ordered corridor polyline.
    # Move every vertex far outside that ribbon while keeping valid, non-degenerate geometry.
    roads[0]["points"] = [[100000.0, 100000.0], [100010.0, 100010.0]]

    with tempfile.TemporaryDirectory(prefix="gb-road-corridor-membership-") as tmp:
        source_root = Path(tmp) / "data" / "osm"
        source_root.mkdir(parents=True)
        source_path = source_root / "vertical_slice_01.game.json"
        lock_path = source_root / "road_destination_sources.lock.json"

        source_bytes = json.dumps(
            corrupted,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
        source_path.write_bytes(source_bytes)

        effective_lock = json.loads(json.dumps(lock_doc))
        documents = effective_lock["documents"]
        assert isinstance(documents, dict)
        documents[SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
        lock_path.write_text(json.dumps(effective_lock, sort_keys=True, allow_nan=False), encoding="utf-8")

        result = run_validator(lock_path, source_path)
        combined = result.stdout + result.stderr
        assert result.returncode != 0, combined
        assert "corridor" in combined.lower() and "radius" in combined.lower(), combined

    print(
        "ROAD_DESTINATION_CORRIDOR_MEMBERSHIP_TEST_OK "
        "historical_vertex_to_polyline_metric=true digest_recomputed=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
