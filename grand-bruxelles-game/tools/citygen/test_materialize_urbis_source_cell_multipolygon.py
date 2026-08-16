#!/usr/bin/env python3
"""Regression: valid UrbIS MultiPolygons participate in canonical 500 m ownership."""
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("materialize_urbis_source_cell", HERE / "materialize_urbis_source_cell.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

CELL = "bxl-e142000-n167000-s500"
BBOX = (142000.0, 167000.0, 142500.0, 167500.0)


def multipolygon(x0: float, y0: float, x1: float, y1: float, inspire_id: str) -> dict:
    ring = [[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]]
    return {
        "type": "Feature",
        "properties": {"INSPIRE_ID": inspire_id},
        "geometry": {"type": "MultiPolygon", "coordinates": [[ring]]},
    }


def fetcher(_bbox):
    return {
        "type": "FeatureCollection",
        "features": [
            multipolygon(142100, 167100, 142120, 167120, "inside-multipolygon"),
            multipolygon(142510, 167100, 142530, 167120, "neighbor-multipolygon"),
        ],
    }


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / CELL
    manifest = mod.materialize(CELL, BBOX, out, fetcher)
    buildings = manifest["layers"]["buildings"]
    assert buildings["features"] == 1, buildings
    assert buildings["ownership_filtered"] == 1, buildings
    assert buildings["invalid_ownership_features"] == 0, buildings
    assert mod.owner_cell(fetcher(BBOX)["features"][0]) == CELL
    assert mod.owner_cell(fetcher(BBOX)["features"][1]) == "bxl-e142500-n167000-s500"

    maturity = mod.build_maturity(out)
    assert maturity["geometry"]["authoritative_geometry_ready"] is True, maturity["geometry"]
    assert maturity["maturity"]["state"] == "data_ready"

print("MATERIALIZE_URBIS_MULTIPOLYGON_OWNERSHIP_OK invalid=0 filtered=1 kept=1")
