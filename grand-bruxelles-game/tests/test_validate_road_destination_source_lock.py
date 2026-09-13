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


def _run(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
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


def _expect_rejected(
    lock_doc: dict[str, object],
    source_doc: dict[str, object],
    needle: str,
    *,
    preserve_bad_digest: bool = False,
) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-road-source-lock-") as tmp:
        source_root = Path(tmp) / "data" / "osm"
        source_root.mkdir(parents=True)
        lock_path = source_root / "road_destination_sources.lock.json"
        source_path = source_root / "vertical_slice_01.game.json"

        source_bytes = json.dumps(
            source_doc,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
        source_path.write_bytes(source_bytes)

        effective_lock = json.loads(json.dumps(lock_doc))
        if not preserve_bad_digest:
            docs = effective_lock["documents"]
            assert isinstance(docs, dict)
            docs[SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
        lock_path.write_text(
            json.dumps(effective_lock, sort_keys=True, allow_nan=False),
            encoding="utf-8",
        )

        result = _run(lock_path, source_path)
        assert result.returncode != 0, result.stdout
        assert needle.lower() in (result.stdout + result.stderr).lower(), result.stderr


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = _run(LOCK, SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    assert "ROAD_DESTINATION_SOURCE_LOCK_OK" in baseline.stdout

    # The lock itself is provenance authority and must stay inside the canonical
    # source root. An arbitrary external lock must never be able to authorize the
    # same materialized source corpus.
    with tempfile.TemporaryDirectory(prefix="gb-road-source-lock-path-") as tmp:
        tmp_root = Path(tmp)
        source_root = tmp_root / "data" / "osm"
        source_root.mkdir(parents=True)
        source_path = source_root / "vertical_slice_01.game.json"
        source_path.write_bytes(SOURCE.read_bytes())
        external_lock = tmp_root / "external-road-source.lock.json"
        external_lock.write_bytes(LOCK.read_bytes())
        external_result = _run(external_lock, source_path)
        assert external_result.returncode != 0, external_result.stdout
        assert "lock path" in (external_result.stdout + external_result.stderr).lower()

    bad_license = json.loads(json.dumps(lock_doc))
    bad_license["license"] = "UNKNOWN"
    _expect_rejected(bad_license, source_doc, "license")

    bad_digest = json.loads(json.dumps(lock_doc))
    docs = bad_digest["documents"]
    assert isinstance(docs, dict)
    docs[SOURCE_KEY] = "0" * 64
    _expect_rejected(bad_digest, source_doc, "sha256", preserve_bad_digest=True)

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

    print("ROAD_DESTINATION_SOURCE_LOCK_TEST_OK digest=true provenance=true accounting=true lock_path=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
