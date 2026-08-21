#!/usr/bin/env python3
"""Regression for the missing-building spatial diagnostic."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("diagnose_urbis3d_missing_buildings.py")
spec = importlib.util.spec_from_file_location("missing_building_diagnostic", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ogr.UseExceptions(); osr.UseExceptions()

BBOX = (142000.0, 167000.0, 142500.0, 167500.0)


def polygon(minx: float, miny: float, maxx: float, maxy: float, z: float = 25.0) -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((minx, miny), (maxx, miny), (maxx, maxy), (minx, maxy), (minx, miny)):
        ring.AddPoint(x, y, z)
    geometry = ogr.Geometry(ogr.wkbPolygon25D)
    geometry.AddGeometry(ring)
    return geometry


def create_gpkg(path: Path) -> None:
    dataset = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    srs = osr.SpatialReference(); srs.ImportFromEPSG(31370)
    faces = dataset.CreateLayer("BuildingFaces", srs, ogr.wkbPolygon25D)
    for name in ("INSPIRE_ID", "BUSOLID_ID", "TYPE", "DETAILSLEVEL", "BEGINLIFE", "ENDLIFE"):
        faces.CreateField(ogr.FieldDefn(name, ogr.OFTString))
    feature = ogr.Feature(faces.GetLayerDefn())
    feature.SetField("INSPIRE_ID", "https://databrussels.be/id/buildingface/FACE-1")
    feature.SetField("BUSOLID_ID", "https://databrussels.be/id/buildingsolid/SOLID-1")
    feature.SetField("TYPE", "GROUNDSURFACE")
    feature.SetField("DETAILSLEVEL", "2")
    feature.SetField("BEGINLIFE", "2024-01-01")
    feature.SetGeometry(polygon(142010.0, 167010.0, 142020.0, 167020.0))
    faces.CreateFeature(feature)
    dataset = None


def create_buildings(path: Path) -> None:
    path.write_text(json.dumps({
        "type": "FeatureCollection",
        "timeStamp": "2026-08-21T13:14:03.097Z",
        "numberReturned": 2,
        "features": [
            {
                "type": "Feature",
                "geometry": {"type": "Polygon", "coordinates": [[[142010,167010],[142020,167010],[142020,167020],[142010,167020],[142010,167010]]]},
                "properties": {"INSPIRE_ID": "https://databrussels.be/id/building/1828139", "BLOCK_ID": "https://databrussels.be/id/block/1", "AREA": 100},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Polygon", "coordinates": [[[142100,167100],[142110,167100],[142110,167110],[142100,167110],[142100,167100]]]},
                "properties": {"INSPIRE_ID": "https://databrussels.be/id/building/235182", "BLOCK_ID": None, "AREA": 100},
            },
        ],
    }), encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        gpkg = root / "official.gpkg"
        buildings = root / "buildings.geojson"
        create_gpkg(gpkg)
        create_buildings(buildings)

        probes, source_2d = module.load_probes(buildings, ["1828139", "235182"], BBOX)
        dataset, layer, package = module.find_buildingfaces(root)
        assert package == gpkg
        solids = module.collect_ground_solids(layer, BBOX)
        report = module.build_report(probes, solids, BBOX, source_2d=source_2d, package_date="20260808")

        assert report["schema"] == module.SCHEMA
        assert report["policy"]["read_only"] is True
        assert report["policy"]["identity_authorization"] is False
        assert report["policy"]["runtime_approval"] is False
        assert report["policy"]["thresholds_changed"] is False
        assert report["counts"] == {
            "probe_count": 2,
            "probes_with_groundsurface_overlap": 1,
            "probes_without_groundsurface_overlap": 1,
        }
        first, second = report["probes"]
        assert first["probe_id"] == "1828139"
        assert first["intersecting_groundsolid_count"] == 1
        assert first["best_overlap"] is not None
        assert abs(first["best_overlap"]["symmetric_score"] - 1.0) < 1e-9
        assert first["nearest_groundsolid"]["distance_m"] == 0.0
        assert first["identity_authorized"] is False
        assert first["runtime_approved"] is False
        assert second["probe_id"] == "235182"
        assert second["block_id"] is None
        assert second["intersecting_groundsolid_count"] == 0
        assert second["spatial_observation"] == "no_groundsurface_overlap_in_snapshot"
        assert second["nearest_groundsolid"] is not None
        assert second["nearest_groundsolid"]["distance_m"] > 0.0
        dataset = None

    print("URBIS3D_MISSING_BUILDING_SPATIAL_DIAGNOSTIC_TEST_OK overlap=1 no_overlap=1 runtime_approved=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
