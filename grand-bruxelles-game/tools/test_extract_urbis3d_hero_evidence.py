#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from osgeo import ogr, osr

import extract_urbis3d_hero_evidence as evidence


class UrbIS3DHeroEvidenceTest(unittest.TestCase):
    def make_official_footprint(self, root: Path) -> Path:
        path = root / "buildings.geojson"
        feature = {
            "type": "Feature",
            "properties": {
                "INSPIRE_ID": "https://databrussels.be/id/building/1751663",
                "URBIS_ID": "8186511",
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [[
                    [148600.0, 170700.0],
                    [148640.0, 170700.0],
                    [148640.0, 170730.0],
                    [148600.0, 170730.0],
                    [148600.0, 170700.0],
                ]],
            },
        }
        path.write_text(
            json.dumps({
                "type": "FeatureCollection",
                "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
                "features": [feature],
            }),
            encoding="utf-8",
        )
        return path

    def make_gpkg(self, root: Path, ambiguous: bool = False) -> Path:
        path = root / "bruxelles_21004_31370.gpkg"
        driver = ogr.GetDriverByName("GPKG")
        dataset = driver.CreateDataSource(str(path))
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(31370)
        layer = dataset.CreateLayer("BuildingFaces", srs=srs, geom_type=ogr.wkbPolygon25D)
        for name in ("BUSOLID_ID", "TYPE"):
            layer.CreateField(ogr.FieldDefn(name, ogr.OFTString))

        def polygon(min_e: float, min_n: float, max_e: float, max_n: float, z_values: list[float]) -> ogr.Geometry:
            ring = ogr.Geometry(ogr.wkbLinearRing)
            coords = [
                (min_e, min_n), (max_e, min_n), (max_e, max_n),
                (min_e, max_n), (min_e, min_n),
            ]
            for index, (easting, northing) in enumerate(coords):
                ring.AddPoint(easting, northing, z_values[min(index, len(z_values) - 1)])
            poly = ogr.Geometry(ogr.wkbPolygon25D)
            poly.AddGeometry(ring)
            return poly

        def add(solid: str, face_type: str, geom: ogr.Geometry) -> None:
            feature = ogr.Feature(layer.GetLayerDefn())
            feature.SetField("BUSOLID_ID", solid)
            feature.SetField("TYPE", face_type)
            feature.SetGeometry(geom)
            layer.CreateFeature(feature)

        # Exact plan match for the intended solid: 40m x 30m.
        add("solid-bourse", "GROUNDSURFACE", polygon(148600, 170700, 148640, 170730, [20.0]))
        add("solid-bourse", "ROOFSURFACE", polygon(148600, 170700, 148640, 170730, [48.0, 50.0, 55.0, 50.0, 48.0]))
        add("solid-bourse", "WALLSURFACE", polygon(148600, 170700, 148600.2, 170730, [20.0, 20.0, 55.0, 55.0, 20.0]))

        if ambiguous:
            add("solid-copy", "GROUNDSURFACE", polygon(148600, 170700, 148640, 170730, [20.0]))
            add("solid-copy", "ROOFSURFACE", polygon(148600, 170700, 148640, 170730, [45.0]))
        else:
            add("solid-neighbor", "GROUNDSURFACE", polygon(148642, 170700, 148660, 170730, [21.0]))
            add("solid-neighbor", "ROOFSURFACE", polygon(148642, 170700, 148660, 170730, [35.0]))

        dataset = None
        return path

    def test_official_2d_footprint_uniquely_identifies_3d_solid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            footprint = self.make_official_footprint(root)
            self.make_gpkg(root)
            result = evidence.extract(root, footprint, ["8186511", "1751663"])
            self.assertTrue(result["identity_proven"])
            self.assertTrue(result["usable_for_runtime_height_review"])
            self.assertEqual(result["best_candidate"]["busolid_id"], "solid-bourse")
            self.assertAlmostEqual(result["best_candidate"]["overlap"]["coverage"], 1.0)
            self.assertAlmostEqual(result["best_candidate"]["overlap"]["iou"], 1.0)
            self.assertAlmostEqual(result["best_candidate"]["ground_to_roof_max_m"], 35.0)
            self.assertFalse(result["runtime_approved"])

    def test_ambiguous_equal_overlap_does_not_prove_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            footprint = self.make_official_footprint(root)
            self.make_gpkg(root, ambiguous=True)
            result = evidence.extract(root, footprint, ["8186511", "1751663"])
            self.assertFalse(result["identity_proven"])
            self.assertFalse(result["usable_for_runtime_height_review"])
            self.assertAlmostEqual(result["unique_iou_margin"], 0.0)

    def test_wrong_2d_identifier_is_rejected_before_spatial_matching(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            footprint = self.make_official_footprint(root)
            self.make_gpkg(root)
            with self.assertRaisesRegex(ValueError, "exactly one official 2D building match"):
                evidence.extract(root, footprint, ["not-the-building"])


if __name__ == "__main__":
    unittest.main()
