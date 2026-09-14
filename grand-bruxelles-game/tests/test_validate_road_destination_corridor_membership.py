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
MEMBERSHIP_VALIDATOR = PROJECT / "tools" / "validate_road_destination_corridor_membership.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"


def run_source_lock(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SOURCE_LOCK_VALIDATOR),
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


def run_membership(source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(MEMBERSHIP_VALIDATOR), "--source", str(source_path)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline_lock = run_source_lock(LOCK, SOURCE)
    assert baseline_lock.returncode == 0, baseline_lock.stdout + baseline_lock.stderr
    baseline_membership = run_membership(SOURCE)
    assert baseline_membership.returncode == 0, baseline_membership.stdout + baseline_membership.stderr
    assert "historical_vertex_to_polyline_metric=true" in baseline_membership.stdout

    corrupted = json.loads(json.dumps(source_doc))
    roads = corrupted["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    # Historical make_runtime_slice.py selects a road only when at least one ROAD
    # VERTEX lies within selection_radius_m.roads of the ordered corridor polyline.
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

        # Existing lock semantics still accept the internally valid source after digest
        # recomputation; the dedicated generation-equivalent membership gate must reject it.
        lock_result = run_source_lock(lock_path, source_path)
        assert lock_result.returncode == 0, lock_result.stdout + lock_result.stderr

        membership_result = run_membership(source_path)
        combined = membership_result.stdout + membership_result.stderr
        assert membership_result.returncode != 0, combined
        assert "corridor" in combined.lower() and "radius" in combined.lower(), combined

    print(
        "ROAD_DESTINATION_CORRIDOR_MEMBERSHIP_TEST_OK "
        "historical_vertex_to_polyline_metric=true digest_recomputed=true "
        "source_lock_control=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
