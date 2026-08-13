#!/usr/bin/env python3
import importlib.util
import json
import math
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools" / "inventory_bourse_adjacent_surfaces.py"
spec = importlib.util.spec_from_file_location("inventory_bourse_adjacent_surfaces", TOOL_PATH)
inventory = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(inventory)
base = inventory.base


def feature(inspire_id, ring, street="Rue Test", type_code="S"):
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [ring]},
        "properties": {
            "INSPIRE_ID": inspire_id,
            "TYPE": type_code,
            "AREA": 20,
            "LVL": 0,
            "STRNAMEFRE": street,
            "STRNAMEDUT": "Teststraat",
        },
    }


def square(e, n, size=4.0):
    return [[e, n], [e + size, n], [e + size, n + size], [e, n + size], [e, n]]


def target_feature(inspire_id, offset):
    e, n = base.BOURSE_CENTER
    item = feature(inspire_id, square(e + offset, n, 4.0), "Place de la Bourse")
    item["properties"]["STRNAMEDUT"] = "Beursplein"
    return item


def main():
    e, n = base.BOURSE_CENTER
    payload = {
        "type": "FeatureCollection",
        "features": [
            target_feature("https://databrussels.be/id/streetsurface/22358", 0.0),
            target_feature("https://databrussels.be/id/streetsurface/151495", 5.0),
            target_feature("https://databrussels.be/id/streetsurface/152281", 10.0),
            feature("https://databrussels.be/id/streetsurface/near", square(e + 14.5, n, 3.0)),
            feature("https://databrussels.be/id/streetsurface/far", square(e + 80.0, n, 3.0)),
            {
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": [[e, n], [e + 1, n + 1]]},
                "properties": {"INSPIRE_ID": "line-not-polygon"},
            },
        ],
    }
    transform = (e, n, 0.0, 0.0)
    rows, target_box = inventory.inventory_neighbors(payload, transform)
    assert [row["inspire_id"] for row in rows] == [
        "https://databrussels.be/id/streetsurface/near",
        "https://databrussels.be/id/streetsurface/far",
    ]
    assert math.isclose(rows[0]["target_bbox_gap_m"], 0.5, abs_tol=1e-9)
    assert rows[0]["target_bbox_gap_m"] < rows[1]["target_bbox_gap_m"]
    assert target_box == [e, n, e + 14.0, n + 4.0]
    assert rows[0]["world_rings_xz"][0][0] == [14.5, 0.0]

    with tempfile.TemporaryDirectory() as tmp:
        evidence = Path(tmp) / "axis.json"
        evidence.write_text(json.dumps({
            "world_coordinate_evidence": {
                "lambert72_origin": [e, n],
                "world_origin_xz": [0.0, 0.0],
            }
        }), encoding="utf-8")
        output = inventory.build_output(payload, "abc123", evidence)
        assert output["runtime_approved"] is False
        assert output["realism_complete"] is False
        assert len(output["neighbor_inventory"]) == 2
        assert "No distance threshold" in output["selection_policy"]

    print("BOURSE_ADJACENT_SURFACE_INVENTORY_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
