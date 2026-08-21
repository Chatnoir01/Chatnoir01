#!/usr/bin/env python3
"""Regression for the read-only UrbIS3D identity diagnostic."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("diagnose_urbis3d_face_identity.py")
spec = importlib.util.spec_from_file_location("urbis3d_identity_diagnostic", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ogr.UseExceptions(); osr.UseExceptions()

BBOX = (142000.0, 167000.0, 142500.0, 167500.0)
BUILDING_ID = "https://databrussels.be/id/building/1828139"
FACE_ID = "https://databrussels.be/id/buildingface/FACE-1"
SOLID_ID = "https://databrussels.be/id/buildingsolid/SOLID-1"


def polygon() -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in (
        (142010.0, 167010.0),
        (142020.0, 167010.0),
        (142020.0, 167020.0),
        (142010.0, 167020.0),
        (142010.0, 167010.0),
    ):
        ring.AddPoint(x, y, 25.0)
    geometry = ogr.Geometry(ogr.wkbPolygon25D)
    geometry.AddGeometry(ring)
    return geometry


def create_faces_only_gpkg(path: Path) -> None:
    dataset = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    srs = osr.SpatialReference(); srs.ImportFromEPSG(31370)
    faces = dataset.CreateLayer("BuildingFaces", srs, ogr.wkbPolygon25D)
    for name in ("INSPIRE_ID", "BUSOLID_ID", "TYPE"):
        faces.CreateField(ogr.FieldDefn(name, ogr.OFTString))
    feature = ogr.Feature(faces.GetLayerDefn())
    feature.SetField("INSPIRE_ID", FACE_ID)
    feature.SetField("BUSOLID_ID", SOLID_ID)
    feature.SetField("TYPE", "GROUNDSURFACE")
    feature.SetGeometry(polygon())
    faces.CreateFeature(feature)
    dataset = None


def create_buildings(path: Path) -> None:
    path.write_text(json.dumps({
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [142010.0, 167010.0], [142020.0, 167010.0],
                    [142020.0, 167020.0], [142010.0, 167020.0],
                    [142010.0, 167010.0],
                ]],
            },
            "properties": {"INSPIRE_ID": BUILDING_ID},
        }],
    }), encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        gpkg = root / "official-current-shape.gpkg"
        buildings_path = root / "buildings.geojson"
        create_faces_only_gpkg(gpkg)
        create_buildings(buildings_path)

        building_ids = module.load_2d_building_ids(buildings_path)
        dataset, faces, solids, package, source_schema = module.find_urbis3d_layers(root)
        assert package == gpkg
        assert solids is None

        report = module.diagnose(
            faces,
            solids,
            building_ids,
            BBOX,
            ["1828139"],
            source_schema=source_schema,
        )
        assert report["schema"] == "grand-bruxelles-urbis3d-building-identity-diagnostic-v3"
        assert report["source_schema"]["building_faces_layer_present"] is True
        assert report["source_schema"]["building_solids_layer_present"] is False
        assert report["policy"]["official_chain_available"] is False
        assert report["policy"]["identity_authorization"] is False
        assert report["policy"]["runtime_approval"] is False
        assert report["counts"]["building_2d_ids"] == 1
        assert report["counts"]["building_faces_in_bbox"] == 1
        assert report["counts"]["unique_busolid_ids"] == 1
        assert report["counts"]["exact_face_inspire_to_2d_ids"] == 0
        assert report["counts"]["exact_busolid_to_2d_ids"] == 0
        assert report["counts"]["face_busolid_ids_joined_to_buildingsolids"] == 0
        assert report["counts"]["face_busolid_ids_without_buildingsolids_layer"] == 1
        assert report["counts"]["joined_bu2d_exact_2d_ids"] == 0
        assert report["probes"][0]["official_chain_match"] is False
        dataset = None

    print("URBIS3D_FACE_IDENTITY_DIAGNOSTIC_TEST_OK missing_buildingsolids=fail_closed runtime_approved=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
