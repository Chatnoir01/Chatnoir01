#!/usr/bin/env python3
from __future__ import annotations

import json
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

    print("ROAD_CELL_COVERAGE_SOURCE_JSON_STRICT_OK duplicate_keys_rejected=true float_overflow_rejected=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
