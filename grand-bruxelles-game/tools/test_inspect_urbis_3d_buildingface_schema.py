#!/usr/bin/env python3
"""Synthetic regression for the BuildingFaces schema profiler."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("inspect_urbis_3d_buildingface_schema.py")
spec = importlib.util.spec_from_file_location("urbis3d_buildingface_schema", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ogr.UseExceptions()
osr.UseExceptions()


def create_fixture(path: Path) -> None:
    driver = ogr.GetDriverByName("GPKG")
    dataset = driver.CreateDataSource(str(path))
    assert dataset is not None
    spatial_ref = osr.SpatialReference()
    spatial_ref.ImportFromEPSG(31370)
    layer = dataset.CreateLayer("BuildingFaces", spatial_ref, ogr.wkbPolygon25D)
    assert layer is not None

    building_id = ogr.FieldDefn("BuildingID", ogr.OFTString)
    face_type = ogr.FieldDefn("FaceType", ogr.OFTString)
    source_rank = ogr.FieldDefn("SourceRank", ogr.OFTInteger)
    layer.CreateField(building_id)
    layer.CreateField(face_type)
    layer.CreateField(source_rank)

    for index, (bid, kind, rank) in enumerate((("A", "roof", 1), ("A", "wall", 1), ("B", "roof", 2))):
        feature = ogr.Feature(layer.GetLayerDefn())
        feature.SetField("BuildingID", bid)
        feature.SetField("FaceType", kind)
        feature.SetField("SourceRank", rank)
        ring = ogr.Geometry(ogr.wkbLinearRing)
        for x, y, z in (
            (149000 + index, 169000, 70.0),
            (149001 + index, 169000, 70.0),
            (149001 + index, 169001, 70.0),
            (149000 + index, 169001, 70.0),
            (149000 + index, 169000, 70.0),
        ):
            ring.AddPoint(x, y, z)
        polygon = ogr.Geometry(ogr.wkbPolygon25D)
        polygon.AddGeometry(ring)
        feature.SetGeometry(polygon)
        layer.CreateFeature(feature)
    dataset = None


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        fixture = root / "ixelles.gpkg"
        create_fixture(fixture)
        evidence = module.inspect_root(root, 100, 10)
        assert evidence["schema"] == module.SCHEMA
        assert evidence["policy"]["semantic_inference"] is False
        assert evidence["policy"]["runtime_approval"] is False
        assert evidence["package_count_with_buildingfaces"] == 1
        layer = evidence["packages"][0]["building_faces"]
        assert layer["feature_count_fast"] == 3
        assert layer["field_count"] == 3
        fields = {field["name"]: field for field in layer["fields"]}
        assert fields["BuildingID"]["sample_non_null"] == 3
        assert fields["BuildingID"]["sample_distinct"] == 2
        assert abs(fields["BuildingID"]["sample_uniqueness_ratio"] - (2 / 3)) < 1e-9
        assert fields["FaceType"]["sample_distinct"] == 2
        face_examples = {item["value"] for item in fields["FaceType"]["sample_examples"]}
        assert face_examples == {"roof", "wall"}
        assert fields["SourceRank"]["type_name"] == "Integer"
    print("URBIS3D_BUILDINGFACES_SCHEMA_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
