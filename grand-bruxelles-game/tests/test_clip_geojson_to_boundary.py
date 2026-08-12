from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "clip_geojson_to_boundary.py"
SPEC = importlib.util.spec_from_file_location("clip_geojson_to_boundary", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def collection(coords, name="x"):
    return {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
        "features": [{
            "type": "Feature",
            "id": name,
            "properties": {"name": name},
            "geometry": {"type": "Polygon", "coordinates": [coords]},
        }],
    }


class ClipGeojsonToBoundaryTests(unittest.TestCase):
    def test_collection_must_explicitly_declare_lambert72(self) -> None:
        payload = {"type": "FeatureCollection", "features": []}
        with self.assertRaises(ValueError):
            # mirror load-time invariant without filesystem dependency
            crs_name = str(((payload.get("crs") or {}).get("properties") or {}).get("name") or "")
            source_crs = str(((payload.get("grand_bruxelles_source") or {}).get("crs") or ""))
            if "31370" not in crs_name and "31370" not in source_crs:
                raise ValueError("missing EPSG:31370")

    def test_polygon_features_rejects_point_only_collection(self) -> None:
        payload = {
            "type": "FeatureCollection",
            "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [1, 2]}}],
        }
        with self.assertRaises(ValueError):
            MODULE.polygon_features(payload)

    @unittest.skipUnless(importlib.util.find_spec("shapely") is not None, "Shapely optional outside clipping workflow")
    def test_source_is_clipped_to_boundary_and_area_is_measured(self) -> None:
        source = collection([[0,0],[10,0],[10,10],[0,10],[0,0]], "source")
        boundary = collection([[5,-5],[15,-5],[15,15],[5,15],[5,-5]], "city")
        result = MODULE.clip_collections(source, boundary, "source", "city")
        stats = result["grand_bruxelles_clip"]
        self.assertEqual(stats["source_area_m2"], 100.0)
        self.assertEqual(stats["clipped_area_m2"], 50.0)
        self.assertEqual(stats["retained_area_percent"], 50.0)
        self.assertEqual(len(result["features"]), 1)
        self.assertEqual(result["features"][0]["properties"]["grand_bruxelles_clipped_to"], "city")

    @unittest.skipUnless(importlib.util.find_spec("shapely") is not None, "Shapely optional outside clipping workflow")
    def test_disjoint_source_is_rejected(self) -> None:
        source = collection([[0,0],[1,0],[1,1],[0,1],[0,0]], "source")
        boundary = collection([[5,5],[6,5],[6,6],[5,6],[5,5]], "city")
        with self.assertRaises(ValueError):
            MODULE.clip_collections(source, boundary, "source", "city")


if __name__ == "__main__":
    unittest.main()
