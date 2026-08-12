#!/usr/bin/env python3
import importlib.util
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools" / "probe_bourse_urbis_context.py"
spec = importlib.util.spec_from_file_location("probe_bourse_urbis_context", TOOL_PATH)
probe = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(probe)


def main() -> int:
    bbox = probe.probe_bbox()
    east, north = probe.BOURSE_CENTER
    assert math.isclose(bbox[0], east - 180.0, abs_tol=1e-9)
    assert math.isclose(bbox[1], north - 180.0, abs_tol=1e-9)
    assert math.isclose(bbox[2], east + 180.0, abs_tol=1e-9)
    assert math.isclose(bbox[3], north + 180.0, abs_tol=1e-9)

    synthetic = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": "building.near",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[[east - 10, north - 4], [east + 8, north - 4], [east + 8, north + 6], [east - 10, north - 4]]],
                },
                "properties": {"INSPIRE_ID": "https://databrussels.be/id/building/near", "TYPE": "synthetic"},
            },
            {
                "type": "Feature",
                "id": "building.far",
                "geometry": {
                    "type": "LineString",
                    "coordinates": [[east + 20, north], [east + 30, north]],
                },
                "properties": {"INSPIRE_ID": "https://databrussels.be/id/building/far"},
            },
        ],
    }
    summary = probe.summarize_geojson(synthetic)
    assert summary["features"] == 2
    assert summary["geometry_types"] == {"LineString": 1, "Polygon": 1}
    assert summary["coordinate_count"] == 6
    assert summary["coordinate_bounds"] == [east - 10, north - 4, east + 30, north + 6]
    assert summary["nearest_coordinate_to_bourse_m"] is not None
    assert summary["nearest_coordinate_to_bourse_m"] < 11.0
    assert len(summary["nearest_features"]) == 2
    assert summary["nearest_features"][0]["id"] == "building.near"
    assert summary["nearest_features"][0]["properties"]["INSPIRE_ID"] == "https://databrussels.be/id/building/near"
    assert summary["nearest_features"][1]["id"] == "building.far"

    try:
        probe.summarize_geojson({"type": "Feature", "features": []})
    except ValueError:
        pass
    else:
        raise AssertionError("non-FeatureCollection payload must be rejected")

    print("BOURSE_URBIS_CONTEXT_PROBE_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
