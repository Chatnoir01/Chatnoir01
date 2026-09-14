#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_road_destination_origin.py"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"


def _run(source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), "--source", str(source_path)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _expect_rejected(source_doc: dict[str, object], needle: str) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-road-origin-") as tmp:
        source_path = Path(tmp) / "source.game.json"
        source_path.write_text(
            json.dumps(source_doc, separators=(",", ":"), ensure_ascii=False, allow_nan=False),
            encoding="utf-8",
        )
        result = _run(source_path)
        assert result.returncode != 0, result.stdout
        assert needle.lower() in (result.stdout + result.stderr).lower(), result.stderr


def main() -> int:
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = _run(SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    assert "ROAD_DESTINATION_ORIGIN_OK" in baseline.stdout

    bad_origin_type = json.loads(json.dumps(source_doc))
    bad_origin_type["origin"] = [50.8419, 4.348]
    _expect_rejected(bad_origin_type, "origin")

    bad_lat_string = json.loads(json.dumps(source_doc))
    origin = bad_lat_string["origin"]
    assert isinstance(origin, dict)
    origin["lat"] = "50.8419"
    _expect_rejected(bad_lat_string, "lat")

    bad_lon_bool = json.loads(json.dumps(source_doc))
    origin = bad_lon_bool["origin"]
    assert isinstance(origin, dict)
    origin["lon"] = True
    _expect_rejected(bad_lon_bool, "lon")

    bad_lat_range = json.loads(json.dumps(source_doc))
    origin = bad_lat_range["origin"]
    assert isinstance(origin, dict)
    origin["lat"] = 91.0
    _expect_rejected(bad_lat_range, "lat")

    bad_lon_range = json.loads(json.dumps(source_doc))
    origin = bad_lon_range["origin"]
    assert isinstance(origin, dict)
    origin["lon"] = -181.0
    _expect_rejected(bad_lon_range, "lon")

    print("ROAD_DESTINATION_ORIGIN_TEST_OK finite=true wgs84=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
