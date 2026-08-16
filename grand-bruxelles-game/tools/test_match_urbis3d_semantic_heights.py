#!/usr/bin/env python3
"""Regression for a cell-agnostic, fail-closed UrbIS3D semantic height matcher."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

from osgeo import ogr, osr

MODULE_PATH = Path(__file__).with_name("match_urbis3d_semantic_heights.py")
spec = importlib.util.spec_from_file_location("urbis3d_semantic", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ogr.UseExceptions(); osr.UseExceptions()

ANDERLECHT_CELL = "bxl-e141500-n167500-s500"
ANDERLECHT_BBOX = (141500.0, 167500.0, 142000.0, 168000.0)


def polygon(x0: float, y0: float, x1: float, y1: float, z: float) -> ogr.Geometry:
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)):
        ring.AddPoint(x, y, z)
    geom = ogr.Geometry(ogr.wkbPolygon25D)
    geom.AddGeometry(ring)
    return geom


def create_gpkg(path: Path) -> None:
    ds = ogr.GetDriverByName("GPKG").CreateDataSource(str(path))
    srs = osr.SpatialReference(); srs.ImportFromEPSG(31370)
    layer = ds.CreateLayer("BuildingFaces", srs, ogr.wkbPolygon25D)
    for name in ("BUSOLID_ID", "TYPE"):
        layer.CreateField(ogr.FieldDefn(name, ogr.OFTString))
    cases = [
        ("anderlecht-solid", module.GROUND, polygon(141510, 167510, 141520, 167520, 24.0)),
        ("anderlecht-solid", module.ROOF, polygon(141510, 167510, 141520, 167520, 36.5)),
        # This valid Ixelles-looking solid must stay outside the explicit Anderlecht bbox.
        ("ixelles-solid", module.GROUND, polygon(149010, 169010, 149020, 169020, 60.0)),
        ("ixelles-solid", module.ROOF, polygon(149010, 169010, 149020, 169020, 72.0)),
    ]
    for solid, kind, geom in cases:
        f = ogr.Feature(layer.GetLayerDefn())
        f.SetField("BUSOLID_ID", solid); f.SetField("TYPE", kind); f.SetGeometry(geom)
        layer.CreateFeature(f)
    ds = None


def create_buildings(path: Path) -> None:
    payload = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [[[141510,167510],[141520,167510],[141520,167520],[141510,167520],[141510,167510]]]},
            "properties": {"INSPIRE_ID": "https://databrussels.be/id/building/ANDERLECHT-A", "AREA": 100},
        }],
    }
    path.write_text(json.dumps(payload), encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        gpkg = root / "region.gpkg"
        buildings_path = root / "buildings.geojson"
        create_gpkg(gpkg); create_buildings(buildings_path)
        buildings = module.load_buildings(buildings_path, ANDERLECHT_BBOX)
        ds, layer, _ = module.find_buildingfaces(root)
        solids = module.collect_solids(layer, ANDERLECHT_BBOX)
        evidence = module.build_evidence(
            buildings,
            solids,
            ANDERLECHT_BBOX,
            cell_id=ANDERLECHT_CELL,
            municipality="Anderlecht",
        )
        assert evidence["schema"] == "grand-bruxelles-urbis3d-semantic-match-v2"
        assert evidence["cell"] == ANDERLECHT_CELL
        assert evidence["municipality"] == "Anderlecht"
        assert evidence["bbox_epsg31370"] == list(ANDERLECHT_BBOX)
        assert evidence["policy"]["runtime_approval"] is False
        assert evidence["policy"]["dsm_dtm_comparison_performed"] is False
        assert evidence["counts"]["building_solids_in_bbox"] == 1
        assert {m["busolid_id"] for m in evidence["matches"]} == {"anderlecht-solid"}
        match = evidence["matches"][0]
        assert match["status"] == "matched_semantic_evidence"
        assert match["matched_inspire_id"].endswith("/ANDERLECHT-A")
        assert abs(match["semantic_height_m"] - 12.5) < 1e-9
        assert match["runtime_approved"] is False
        ds = None

    # Fail closed: production evidence must identify the geographic contract.
    try:
        module.build_evidence([], {}, ANDERLECHT_BBOX, cell_id=ANDERLECHT_CELL, municipality="")
    except ValueError:
        pass
    else:
        raise AssertionError("missing municipality must fail closed")

    print("URBIS3D_SEMANTIC_HEIGHT_GENERIC_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
