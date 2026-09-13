#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _building(*, levels: str) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "way",
                "id": 5513,
                "tags": {"building": "yes", "building:levels": levels},
                "geometry": [
                    {"lat": 50.8410, "lon": 4.3470},
                    {"lat": 50.8410, "lon": 4.3472},
                    {"lat": 50.8412, "lon": 4.3472},
                    {"lat": 50.8412, "lon": 4.3470},
                    {"lat": 50.8410, "lon": 4.3470},
                ],
            }
        ]
    }


def _expect_rejected(raw_levels: str) -> None:
    try:
        transform_osm_to_game.convert(_building(levels=raw_levels), transform_osm_to_game.DEFAULT_ORIGIN)
    except ValueError as exc:
        assert "building levels" in str(exc).lower(), exc
    else:
        raise AssertionError(f"explicit invalid building:levels={raw_levels!r} must fail closed")


def _expect_cli_rejected_without_artifact(raw_levels: str) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-osm-building-levels-") as tmp:
        tmp_path = Path(tmp)
        source_path = tmp_path / "source.json"
        output_path = tmp_path / "game.json"
        source_path.write_text(json.dumps(_building(levels=raw_levels), allow_nan=False), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(PROJECT / "tools" / "transform_osm_to_game.py"), "--input", str(source_path), "--output", str(output_path)],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode != 0, result.stdout
        assert "building levels" in (result.stdout + result.stderr).lower(), result.stderr
        assert not output_path.exists(), "failed conversion must not leave a partial game JSON artifact"


def main() -> int:
    for raw_levels in ("bogus", "nan", "0", "-2", "81"):
        _expect_rejected(raw_levels)
    _expect_rejected("2.5")
    _expect_cli_rejected_without_artifact("2.5")

    two_levels = transform_osm_to_game.convert(_building(levels="2"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert two_levels["buildings"][0]["height"] == 6.3
    two_point_zero_levels = transform_osm_to_game.convert(_building(levels="2.0"), transform_osm_to_game.DEFAULT_ORIGIN)
    assert two_point_zero_levels["buildings"][0]["height"] == 6.3

    print("TRANSFORM_OSM_BUILDING_LEVELS_OK fractional_levels_rejected=true partial_artifact_absent=true integral_levels_retained=true network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
