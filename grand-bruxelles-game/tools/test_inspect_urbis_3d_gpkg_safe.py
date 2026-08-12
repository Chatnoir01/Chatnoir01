#!/usr/bin/env python3
"""Synthetic regression test for the read-only UrbIS 3D GeoPackage inspector."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("inspect_urbis_3d_gpkg_safe.py")
spec = importlib.util.spec_from_file_location("urbis3d_inspector", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ogr.UseExceptions()
osr.UseExceptions()


def create_fixture(path: Path, epsg: int, with_z: bool) -> None:
    driver = ogr.GetDriverByName("GPKG")
    dataset = driver.CreateDataSource(str(path))
    assert dataset is not None
    spatial_ref = osr.SpatialReference()
    spatial_ref.ImportFromEPSG(epsg)
    geometry_type = ogr.wkbPolygon25D if with_z else ogr.wkbPolygon
    layer = dataset.CreateLayer("constructions", spatial_ref, geometry_type)
    assert layer is not None
    feature = ogr.Feature(layer.GetLayerDefn())

    ring = ogr.Geometry(ogr.wkbLinearRing)
    if with_z:
        ring.SetCoordinateDimension(3)
    points = [
        (148000.0, 169000.0, 24.0),
        (148010.0, 169000.0, 24.0),
        (148010.0, 169010.0, 31.0),
        (148000.0, 169010.0, 31.0),
        (148000.0, 169000.0, 24.0),
    ]
    for x, y, z in points:
        if with_z:
            ring.AddPoint(x, y, z)
        else:
            ring.AddPoint_2D(x, y)

    polygon = ogr.Geometry(geometry_type)
    polygon.AddGeometry(ring)
    feature.SetGeometry(polygon)
    layer.CreateFeature(feature)
    feature = None
    layer = None
    dataset = None


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        good = root / "official-31370-z.gpkg"
        flat = root / "official-31370-flat.gpkg"
        wrong_crs = root / "wrong-crs-z.gpkg"
        create_fixture(good, 31370, True)
        create_fixture(flat, 31370, False)
        create_fixture(wrong_crs, 4326, True)

        inventory = module.build_inventory(root, {"selected": {"href": "https://example.invalid/source.zip"}}, 10, 100)
        assert inventory["schema"] == module.SCHEMA
        assert inventory["gpkg_count"] == 3
        assert inventory["candidate_layer_count"] == 1
        assert inventory["usable_as_second_height_source"] is True
        assert "31370" in inventory["observed_epsg_codes"]
        assert "4326" in inventory["observed_epsg_codes"]

        packages = {Path(package["path"]).name: package for package in inventory["packages"]}
        good_layer = packages[good.name]["layers"][0]
        assert good_layer["epsg"] == "31370"
        assert good_layer["declared_has_z"] is True
        assert good_layer["sample_z"]["actual_has_nonzero_z"] is True
        assert good_layer["sample_z"]["min"] == 24.0
        assert good_layer["sample_z"]["max"] == 31.0
        assert good_layer["candidate_for_height_validation"] is True
        assert len(packages[good.name]["sha256"]) == 64

        flat_layer = packages[flat.name]["layers"][0]
        assert flat_layer["epsg"] == "31370"
        assert flat_layer["declared_has_z"] is False
        assert flat_layer["candidate_for_height_validation"] is False

        wrong_layer = packages[wrong_crs.name]["layers"][0]
        assert wrong_layer["epsg"] == "4326"
        assert wrong_layer["declared_has_z"] is True
        assert wrong_layer["candidate_for_height_validation"] is False

    print("URBIS_3D_GPKG_INSPECTOR_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
