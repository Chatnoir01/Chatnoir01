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
EXPECTED_APPROVAL = {
    "footprint": True,
    "height": True,
    "roof": True,
    "frontage": False,
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


def _mutated_result(field: str) -> subprocess.CompletedProcess[str]:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    corridor = source_doc["corridor"]
    required = corridor["required_buildings"]
    assert isinstance(required, list) and len(required) == 1
    building = required[0]
    assert isinstance(building, dict)
    approval = building["runtime_approval"]
    assert isinstance(approval, dict)
    approval[field] = False

    with tempfile.TemporaryDirectory(prefix="gb-required-building-runtime-approval-") as tmp:
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
        return _run(lock_path, source_root)


def main() -> int:
    baseline = _run(LOCK, SOURCE.parent)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr

    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    required = source_doc["corridor"]["required_buildings"]
    assert isinstance(required, list) and len(required) == 1
    building = required[0]
    assert isinstance(building, dict)
    assert building.get("osm_id") == 13494623
    observed = building.get("runtime_approval")
    assert observed == EXPECTED_APPROVAL, f"unexpected canonical runtime_approval: {observed!r}"

    for field in ("footprint", "height", "roof"):
        result = _mutated_result(field)
        assert result.returncode != 0, (
            "required-building runtime approval drift survived a recomputed source digest: "
            f"field={field}; validator must pin the historical Bourse approval contract"
        )

    print(
        "REQUIRED_BUILDING_RUNTIME_APPROVAL_LOCK_TEST_OK "
        "osm=way/13494623 footprint=true height=true roof=true frontage=false "
        "digest_recompute_resistant=true network_used=false authorization=none"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
