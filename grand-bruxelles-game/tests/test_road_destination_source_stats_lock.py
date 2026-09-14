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
EXPECTED_SOURCE_STATS = {
    "roads": 6114,
    "drivable_roads": 1330,
    "buildings": 8728,
    "railways": 536,
    "environment_points": 3564,
}


def _run(lock_path: Path, source_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "--source-root",
            str(source_root),
            "--lock",
            str(lock_path),
        ],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _mutated_result(kind: str) -> subprocess.CompletedProcess[str]:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    source_doc["source_stats"][kind] = EXPECTED_SOURCE_STATS[kind] + 1

    with tempfile.TemporaryDirectory(prefix="gb-road-source-stats-lock-") as tmp:
        repo_root = Path(tmp)
        source_root = repo_root / "data" / "osm"
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
        lock_path.write_text(json.dumps(lock_doc, sort_keys=True, allow_nan=False), encoding="utf-8")
        return _run(lock_path, source_root)


def main() -> int:
    baseline = _run(LOCK, SOURCE.parent)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr

    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    observed = source_doc.get("source_stats")
    assert observed == EXPECTED_SOURCE_STATS, f"unexpected canonical source_stats: {observed!r}"

    for kind in EXPECTED_SOURCE_STATS:
        result = _mutated_result(kind)
        assert result.returncode != 0, (
            f"source lock accepted source_stats.{kind} drift with recomputed digest; "
            "historical acquisition accounting must be pinned independently of the digest"
        )

    print(
        "ROAD_DESTINATION_SOURCE_STATS_LOCK_TEST_OK "
        "roads=6114 drivable_roads=1330 buildings=8728 railways=536 environment_points=3564 "
        "digest_recompute_resistant=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
