#!/usr/bin/env python3
"""Regression tests for official UrbIS street-surface level preservation."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).with_name("make_urbis_midi_runtime.py")


def feature_collection(features: list[dict]) -> dict:
    return {"type": "FeatureCollection", "features": features}


def polygon_feature(feature_id: str, properties: dict, x_offset: float = 0.0) -> dict:
    return {
        "type": "Feature",
        "id": feature_id,
        "properties": properties,
        "geometry": {
            "type": "Polygon",
            "coordinates": [[
                [x_offset, 0.0],
                [x_offset + 8.0, 0.0],
                [x_offset + 8.0, 8.0],
                [x_offset, 8.0],
                [x_offset, 0.0],
            ]],
        },
    }


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="urbis-midi-runtime-") as temporary:
        root = Path(temporary)
        buildings_path = root / "buildings.json"
        surfaces_path = root / "surfaces.json"
        output_path = root / "runtime.json"

        buildings_path.write_text(
            json.dumps(feature_collection([
                polygon_feature("building-1", {"INSPIRE_ID": "building-1", "AREA": 64}),
            ])),
            encoding="utf-8",
        )
        surfaces_path.write_text(
            json.dumps(feature_collection([
                polygon_feature(
                    "surface-road",
                    {
                        "INSPIRE_ID": "surface-road",
                        "TYPE": "S",
                        "LVL": 0,
                        "AREA": 64,
                        "STRNAMEFRE": "Avenue Fonsny",
                        "STRNAMEDUT": "Fonsnylaan",
                    },
                ),
                polygon_feature(
                    "surface-metro",
                    {
                        "INSPIRE_ID": "surface-metro",
                        "TYPE": "MS",
                        "LVL": -1,
                        "AREA": 64,
                        "STRNAMEFRE": "Station STIB Gare du Midi",
                        "STRNAMEDUT": "Station MIVB Zuidstation",
                    },
                    x_offset=12.0,
                ),
            ])),
            encoding="utf-8",
        )

        subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--buildings",
                str(buildings_path),
                "--surfaces",
                str(surfaces_path),
                "--output",
                str(output_path),
                "--radius",
                "100",
            ],
            check=True,
        )
        runtime = json.loads(output_path.read_text(encoding="utf-8"))

    by_id = {surface["id"]: surface for surface in runtime["street_surfaces"]}
    assert by_id["surface-road"]["level"] == 0.0
    assert by_id["surface-metro"]["level"] == -1.0
    assert runtime["accuracy"]["street_surface_levels"] == "official_urbis"
    assert runtime["stats"]["street_surfaces_surface_level"] == 1
    assert runtime["stats"]["street_surfaces_non_surface_level"] == 1
    print("URBIS_MIDI_RUNTIME_LEVEL_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
