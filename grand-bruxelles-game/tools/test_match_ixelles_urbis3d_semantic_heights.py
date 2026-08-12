#!/usr/bin/env python3
"""Synthetic red/green regression for Ixelles semantic BuildingFaces matching."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("match_ixelles_urbis3d_semantic_heights.py")
spec = importlib.util.spec_from_file_location("ixelles_semantic", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ogr.UseExceptions(); osr.UseExceptions()


def polygon(x0: float, y0: float, x1: float, y1: float, z: float) -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((x0,y0),(x1,y0),(x1,y1),(x0,y1),(x0,y0)):
        ring.AddPoint(x,y,z)
    geom = ogr.Geometry(ogr.wkbPolygon25D); geom.AddGeometry(ring); return geom


def create_gpkg(path: Path) -> None:
    ds = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    srs = osr.SpatialReference(); srs.ImportFromEPSG(31370)
    layer = ds.CreateLayer("BuildingFaces", srs, ogr.wkbPolygon25D)
    for name in ("BUSOLID_ID","TYPE"):
        layer.CreateField(ogr.FieldDefn(name, ogr.OFTString))
    cases = [
        ("solid-a", module.GROUND, polygon(149010,169010,149020,169020,60)),
        ("solid-a", module.ROOF, polygon(149010,169010,149020,169020,72)),
        ("solid-b", module.GROUND, polygon(149030,169010,149040,169020,61)),
        ("solid-b", module.ROOF, polygon(149030,169010,149040,169020,60)),
    ]
    for solid, kind, geom in cases:
        f = ogr.Feature(layer.GetLayerDefn()); f.SetField("BUSOLID_ID",solid); f.SetField("TYPE",kind); f.SetGeometry(geom); layer.CreateFeature(f)
    ds = None


def create_buildings(path: Path) -> None:
    def feature(identity: str, coords):
        return {"type":"Feature","geometry":{"type":"Polygon","coordinates":[coords]},"properties":{"INSPIRE_ID":identity,"AREA":100}}
    payload={"type":"FeatureCollection","features":[
        feature("https://databrussels.be/id/building/A", [[149010,169010],[149020,169010],[149020,169020],[149010,169020],[149010,169010]]),
        feature("https://databrussels.be/id/building/B", [[149030,169010],[149040,169010],[149040,169020],[149030,169020],[149030,169010]]),
    ]}
    path.write_text(json.dumps(payload),encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); gpkg=root/"ixelles.gpkg"; buildings_path=root/"buildings.geojson"
        create_gpkg(gpkg); create_buildings(buildings_path)
        buildings=module.load_buildings(buildings_path,module.DEFAULT_BBOX)
        ds,layer,_=module.find_buildingfaces(root); solids=module.collect_solids(layer,module.DEFAULT_BBOX)
        evidence=module.build_evidence(buildings,solids,module.DEFAULT_BBOX)
        assert evidence["policy"]["runtime_approval"] is False
        assert evidence["policy"]["dsm_dtm_comparison_performed"] is False
        assert evidence["counts"]["urbis_2d_buildings"] == 2
        assert evidence["counts"]["building_solids_in_bbox"] == 2
        matches={m["busolid_id"]:m for m in evidence["matches"]}
        a=matches["solid-a"]
        assert a["status"] == "matched_semantic_evidence"
        assert a["matched_inspire_id"].endswith("/A")
        assert abs(a["match_score"]-1.0)<1e-9
        assert abs(a["semantic_height_m"]-12.0)<1e-9
        assert a["runtime_approved"] is False
        b=matches["solid-b"]
        assert b["status"] == "matched_implausible_height"
        assert b["semantic_height_m"] == -1.0
        assert b["runtime_approved"] is False
        ds=None
    print("IXELLES_SEMANTIC_BUILDING_MATCH_TEST_OK")
    return 0

if __name__ == "__main__": raise SystemExit(main())
