#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("select_cell_urbis3d_packages", HERE / "select_cell_urbis3d_packages.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)
SELECTOR = mod._load_selector()

CELL_A = "bxl-e141500-n167500-s500"
CELL_B = "bxl-e149000-n169000-s500"
GRID = {
    "format": "grand-bruxelles-regional-target-grid-v1",
    "crs": "EPSG:31370",
    "cells": [
        {"cell_id": CELL_A, "bbox": [141500,167500,142000,168000], "municipalities": ["anderlecht"]},
        {"cell_id": CELL_B, "bbox": [149000,169000,149500,169500], "municipalities": ["bruxelles","ixelles"]},
    ],
}

def direct(nis: str, date: str):
    return {"href": f"https://urbisdownload.datastore.brussels/UrbIS/3D/UrbIS3D_31370_GPKG_{nis}_{date}.zip", "rel": "enclosure"}

FEED = {
    "feeds": [{
        "source_id": "urbis_3d_constructions",
        "entries": [{
            "title": "UrbIS 3D Constructions EPSG 31370 GPKG",
            "updated": "2026-08-20T00:00:00Z",
            "links": [
                direct("21001","20260101"), direct("21001","20260801"),
                direct("21004","20260715"), direct("21009","20260720"),
            ],
        }],
    }],
}

result = mod.build(FEED, GRID, [CELL_A, CELL_B], selector=SELECTOR)
assert result["format"] == "grand-bruxelles-citygen-urbis3d-package-plan-v1"
assert result["crs"] == "EPSG:31370"
assert result["policy"]["runtime_authorized"] is False
assert result["policy"]["runtime_promotion_allowed"] is False
assert len(result["cells"]) == 2
assert len(result["packages"]) == 3
packages = {row["nis_code"]: row for row in result["packages"]}
assert packages["21001"]["embedded_date"] == "20260801"
assert packages["21004"]["municipality"] == "bruxelles"
assert packages["21009"]["municipality"] == "ixelles"
by_cell = {row["cell_id"]: row for row in result["cells"]}
assert by_cell[CELL_A]["nis_codes"] == ["21001"]
assert by_cell[CELL_B]["nis_codes"] == ["21004","21009"]

# All 19 canonical French municipality slugs must have stable NIS coverage.
canonical = {
    "anderlecht":"21001","auderghem":"21002","berchem-sainte-agathe":"21003","bruxelles":"21004",
    "etterbeek":"21005","evere":"21006","forest":"21007","ganshoren":"21008","ixelles":"21009",
    "jette":"21010","koekelberg":"21011","molenbeek-saint-jean":"21012","saint-gilles":"21013",
    "saint-josse-ten-noode":"21014","schaerbeek":"21015","uccle":"21016","watermael-boitsfort":"21017",
    "woluwe-saint-lambert":"21018","woluwe-saint-pierre":"21019",
}
assert {slug: mod._nis_for(slug) for slug in canonical} == canonical

bad_grid = dict(GRID)
bad_grid["cells"] = [{"cell_id": CELL_A, "bbox": [141500,167500,142000,168000], "municipalities": ["unknown-ville"]}]
try:
    mod.build(FEED, bad_grid, [CELL_A], selector=SELECTOR)
except ValueError as exc:
    assert "unknown Brussels municipality slug" in str(exc)
else:
    raise AssertionError("unknown municipality must fail closed")

missing_feed = {"feeds": []}
try:
    mod.build(missing_feed, GRID, [CELL_A], selector=SELECTOR)
except ValueError as exc:
    assert "official source not found" in str(exc)
else:
    raise AssertionError("missing official feed must fail closed")

print("CITYGEN_URBIS3D_PACKAGE_PLAN_TEST_OK cells=2 municipalities=3 all_brussels_nis=19 latest=true fail_closed=true")
