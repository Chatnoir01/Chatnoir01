#!/usr/bin/env python3
"""Regression tests for parent-entry vs actual-file UrbIS distribution filtering."""

from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("select_urbis_distribution.py")
spec = importlib.util.spec_from_file_location("selector", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main() -> int:
    candidates = [
        {
            "href": "https://urbisdownload.datastore.brussels/3D/31370/DWG/UrbISBuildings3D_31370_DWG_141167_20250116.zip",
            "type": "application/zip",
            "title": "UrbISBuildings3D DWG",
        },
        {
            "href": "https://urbisdownload.datastore.brussels/3D/31370/GPKG/UrbISBuildings3D_31370_GPKG_141167_20250116.zip",
            "type": "application/zip",
            "title": "UrbISBuildings3D GPKG",
        },
        {
            "href": "https://urbisdownload.datastore.brussels/3D/4326/GPKG/UrbISBuildings3D_4326_GPKG_141167_20250116.zip",
            "type": "application/zip",
            "title": "UrbISBuildings3D GPKG 4326",
        },
    ]

    exact = module.filter_candidates(candidates, ["31370", "GPKG"])
    assert len(exact) == 1
    assert "/31370/GPKG/" in exact[0]["href"]
    assert "DWG" not in exact[0]["href"]

    gpkg_any_crs = module.filter_candidates(candidates, ["GPKG"])
    assert len(gpkg_any_crs) == 2

    untouched = module.filter_candidates(candidates, [])
    assert untouched == candidates

    missing = module.filter_candidates(candidates, ["31370", "SHP"])
    assert missing == []

    print("URBIS_DISTRIBUTION_SELECTOR_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
