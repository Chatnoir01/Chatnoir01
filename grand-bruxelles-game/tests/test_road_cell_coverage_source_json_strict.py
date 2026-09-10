#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools.city_machine.discover_road_cell_coverage_candidates import discover


def canonical_source() -> dict:
    return {
        "format": "grand-bruxelles-osm-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "stats": {"roads": 1},
        "roads": [
            {
                "osm_id": 1,
                "name": "Synthetic provenance witness",
                "class": "residential",
                "points": [[0.0, 0.0], [1.0, 1.0]],
            }
        ],
        "corridor": {"anchors": [{"id": "synthetic", "name": "Synthetic", "x": 0.0, "z": 0.0}]},
    }


def require_rejected(raw: bytes, label: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "source.json"
        path.write_bytes(raw)
        try:
            discover(path)
        except (ValueError, json.JSONDecodeError):
            return
    raise AssertionError(f"source factory accepted ambiguous/non-finite JSON: {label}")


def require_transform_rejected(raw: bytes, label: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        source = tmp_path / "overpass.json"
        output = tmp_path / "game.json"
        source.write_bytes(raw)
        proc = subprocess.run(
            [
                sys.executable,
                str(PROJECT / "tools" / "transform_osm_to_game.py"),
                "--input",
                str(source),
                "--output",
                str(output),
            ],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            return
    raise AssertionError(f"Overpass converter accepted ambiguous/non-finite JSON: {label}")


def main() -> int:
    payload = canonical_source()
    canonical = json.dumps(payload, separators=(",", ":")).encode("utf-8")

    duplicate_license = canonical.replace(
        b'"license":"ODbL-1.0"',
        b'"license":"NOT-A-LICENSE","license":"ODbL-1.0"',
        1,
    )
    require_rejected(duplicate_license, "duplicate license with canonical final value")

    duplicate_source = canonical.replace(
        b'"source":"OpenStreetMap contributors via Overpass API"',
        b'"source":"untrusted provider","source":"OpenStreetMap contributors via Overpass API"',
        1,
    )
    require_rejected(duplicate_source, "duplicate source with canonical final value")

    overflow_in_anchor = canonical.replace(b'"x":0.0', b'"x":1e309', 1)
    require_rejected(overflow_in_anchor, "finite-syntax float overflow")

    overpass = b'{"version":0.6,"elements":[]}'
    duplicate_elements = overpass.replace(
        b'"elements":[]',
        b'"elements":[{"type":"node","id":999,"lat":50.84,"lon":4.34,"tags":{"natural":"tree"}}],"elements":[]',
        1,
    )
    require_transform_rejected(duplicate_elements, "duplicate root elements with canonical final value")

    overflow_overpass = b'{"version":0.6,"elements":[{"type":"node","id":1,"lat":1e309,"lon":4.34,"tags":{"natural":"tree"}}]}'
    require_transform_rejected(overflow_overpass, "Overpass coordinate finite-syntax float overflow")

    nonstandard_overpass = b'{"version":0.6,"elements":[{"type":"node","id":1,"lat":NaN,"lon":4.34,"tags":{"natural":"tree"}}]}'
    require_transform_rejected(nonstandard_overpass, "Overpass non-standard NaN constant")

    print(
        "ROAD_CELL_COVERAGE_SOURCE_JSON_STRICT_OK "
        "duplicate_keys_rejected=true float_overflow_rejected=true "
        "overpass_converter_strict=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
