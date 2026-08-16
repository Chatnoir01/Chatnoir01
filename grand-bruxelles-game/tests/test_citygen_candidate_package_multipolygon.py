from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CITYGEN = ROOT / "tools" / "citygen"
if str(CITYGEN) not in sys.path:
    sys.path.insert(0, str(CITYGEN))

SPEC = importlib.util.spec_from_file_location(
    "build_cell_candidate_package",
    CITYGEN / "build_cell_candidate_package.py",
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _multipolygon_feature() -> dict:
    return {
        "type": "Feature",
        "id": "Buildings.multi-1",
        "properties": {
            "INSPIRE_ID": "https://databrussels.be/id/building/multi-1",
            "AREA": 32,
        },
        "geometry": {
            "type": "MultiPolygon",
            "coordinates": [
                [[[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]]],
                [[[10, 10], [12, 10], [12, 12], [10, 12], [10, 10]]],
            ],
        },
    }


def test_polygon_record_retains_all_multipolygon_components_without_runtime_promotion() -> None:
    row = MODULE.polygon_record(_multipolygon_feature(), "bxl-test")
    assert row is not None
    assert row["geometry_type"] == "MultiPolygon"
    assert row["footprint_31370"] is None
    assert len(row["footprints_31370"]) == 2
    assert row["bbox_31370"] == [0.0, 0.0, 12.0, 12.0]
    assert row["vertex_count"] == 10
    assert row["runtime_approved"] is False


def test_candidate_package_counts_valid_multipolygon_as_authoritative_building(tmp_path: Path) -> None:
    cell = tmp_path / "bxl-test"
    raw = cell / "raw"
    raw.mkdir(parents=True)
    (cell / "manifest.json").write_text(
        json.dumps({"cell_id": "bxl-test", "crs": "EPSG:31370"}),
        encoding="utf-8",
    )
    polygon = {
        "type": "Feature",
        "id": "Buildings.poly-1",
        "properties": {
            "INSPIRE_ID": "https://databrussels.be/id/building/poly-1",
            "AREA": 16,
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[20, 20], [24, 20], [24, 24], [20, 24], [20, 20]]],
        },
    }
    (raw / "buildings.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": [polygon, _multipolygon_feature()]}),
        encoding="utf-8",
    )

    package = MODULE.build(cell, None)
    assert package["summary"]["valid_buildings"] == 2
    assert package["summary"]["invalid_features"] == 0
    assert "invalid_building_features_present" not in package["blockers"]
    assert all(row["runtime_approved"] is False for row in package["buildings"])


def test_malformed_multipolygon_remains_fail_closed() -> None:
    feature = _multipolygon_feature()
    feature["geometry"]["coordinates"][1] = []
    assert MODULE.polygon_record(feature, "bxl-test") is None
