#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
spec = importlib.util.spec_from_file_location("road_catalog_source_structure", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def valid_road() -> dict[str, object]:
    return {
        "osm_id": 42,
        "name": "Rue Test",
        "class": "tertiary",
        "width": 7.0,
        "drivable": True,
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
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_json(root / "valid.game.json", {
            "format": "grand-bruxelles-osm-v1",
            "roads": [valid_road()],
            "buildings": [],
        })

        # Once a document explicitly claims the canonical OSM source format, a malformed
        # roads container is source corruption. It must not be silently skipped while a
        # different valid document keeps the derived catalog apparently healthy.
        write_json(root / "malformed-container.game.json", {
            "format": "grand-bruxelles-osm-v1",
            "roads": {"42": valid_road()},
            "buildings": [],
        })
        expect_build_fail(root, "malformed source roads container")

        # Likewise, malformed members inside an otherwise canonical roads list must not
        # disappear from accounting/provenance as if they were never present.
        write_json(root / "malformed-container.game.json", {
            "format": "grand-bruxelles-osm-v1",
            "roads": [valid_road(), 42],
            "buildings": [],
        })
        expect_build_fail(root, "malformed source road record roads[1]")

    print("ROAD_DESTINATION_CATALOG_SOURCE_STRUCTURE_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
