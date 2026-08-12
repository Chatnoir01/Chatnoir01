#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from osgeo import ogr, osr

import extract_urbis3d_hero_evidence as evidence


class UrbIS3DHeroEvidenceTest(unittest.TestCase):
    def make_gpkg(self, root: Path) -> Path:
        path = root / "bruxelles_21004_31370.gpkg"
        driver = ogr.GetDriverByName("GPKG")
        dataset = driver.CreateDataSource(str(path))
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(31370)
        layer = dataset.CreateLayer("BuildingFaces", srs=srs, geom_type=ogr.wkbPolygon25D)
        layer.CreateField(ogr.FieldDefn("building_ref", ogr.OFTString))

        def add(ref: str, e: float, n: float, low: float, high: float) -> None:
            ring = ogr.Geometry(ogr.wkbLinearRing)
            ring.AddPoint(e - 2.0, n - 2.0, low)
            ring.AddPoint(e + 2.0, n - 2.0, low)
            ring.AddPoint(e + 2.0, n + 2.0, high)
            ring.AddPoint(e - 2.0, n + 2.0, high)
            ring.AddPoint(e - 2.0, n - 2.0, low)
            polygon = ogr.Geometry(ogr.wkbPolygon25D)
            polygon.AddGeometry(ring)
            feature = ogr.Feature(layer.GetLayerDefn())
            feature.SetField("building_ref", ref)
            feature.SetGeometry(polygon)
            layer.CreateFeature(feature)

        add("8186511", 148620.0, 170830.0, 20.0, 55.0)
        add("neighbor", 148625.0, 170835.0, 22.0, 35.0)
        dataset = None
        return path

    def test_identifier_match_is_required_for_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_gpkg(root)
            result = evidence.extract(root, ["8186511", "1751663"], 148620.0, 170830.0, 50.0)
            self.assertTrue(result["identity_proven"])
            self.assertTrue(result["usable_for_runtime_height_review"])
            self.assertEqual(result["identifier_match_count"], 1)
            self.assertAlmostEqual(result["combined_identifier_z"]["min"], 20.0)
            self.assertAlmostEqual(result["combined_identifier_z"]["max"], 55.0)
            self.assertAlmostEqual(result["combined_identifier_z"]["span"], 35.0)
            self.assertGreaterEqual(len(result["nearby_diagnostics"]), 1)
            self.assertFalse(result["runtime_approved"])

    def test_nearby_geometry_does_not_prove_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_gpkg(root)
            result = evidence.extract(root, ["not-the-building"], 148620.0, 170830.0, 50.0)
            self.assertFalse(result["identity_proven"])
            self.assertFalse(result["usable_for_runtime_height_review"])
            self.assertEqual(result["combined_identifier_z"]["count"], 0)
            self.assertGreaterEqual(len(result["nearby_diagnostics"]), 1)


if __name__ == "__main__":
    unittest.main()
