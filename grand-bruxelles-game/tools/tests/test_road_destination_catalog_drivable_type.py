#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
spec = importlib.util.spec_from_file_location("road_catalog_drivable_type", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def road(osm_id: int, drivable: object) -> dict[str, object]:
    return {
        "osm_id": osm_id,
        "name": f"Rue Test {osm_id}",
        "class": "tertiary",
        "width": 7.0,
        "drivable": drivable,
        "points": [[0.0, 0.0], [10.0, 0.0]],
    }


def expect_build_fail(root: Path, needle: str) -> None:
    try:
        module.build_catalog(root)
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected fail-closed rejection containing {needle!r}")


def main() -> int:
    # Keep one valid road in every fixture so a malformed drivable flag cannot hide
    # behind an otherwise healthy derived catalog. Canonical source booleans are
    # schema evidence; strings/integers/null must not be normalized to non-drivable.
    for malformed in ("true", 1, None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data" / "osm"
            write_json(root / "fixture.game.json", {
                "format": "grand-bruxelles-osm-v1",
                "roads": [road(42, True), road(43, malformed)],
                "buildings": [],
            })
            expect_build_fail(root, "source JSON type drift drivable")

    print("ROAD_DESTINATION_CATALOG_DRIVABLE_TYPE_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
