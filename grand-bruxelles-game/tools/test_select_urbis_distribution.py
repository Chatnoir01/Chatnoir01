#!/usr/bin/env python3
"""Regression tests for file-format, municipality and freshness filtering."""

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
        {"href": "https://x/31370/DWG/UrbISBuildings3D_31370_DWG_21009_20260808.zip", "title": "Ixelles", "type": "application/zip"},
        {"href": "https://x/31370/GPKG/UrbISBuildings3D_31370_GPKG_21001_20260808.zip", "title": "Anderlecht", "type": "application/geopackage+sqlite3"},
        {"href": "https://x/31370/GPKG/UrbISBuildings3D_31370_GPKG_21009_20250116.zip", "title": "Ixelles", "type": "application/geopackage+sqlite3"},
        {"href": "https://x/31370/GPKG/UrbISBuildings3D_31370_GPKG_21009_20260704.zip", "title": "Ixelles", "type": "application/geopackage+sqlite3"},
        {"href": "https://x/31370/GPKG/UrbISBuildings3D_31370_GPKG_21009_20260808.zip", "title": "Ixelles", "type": "application/geopackage+sqlite3"},
        {"href": "https://x/4326/GPKG/UrbISBuildings3D_4326_GPKG_21009_20260808.zip", "title": "Ixelles", "type": "application/geopackage+sqlite3"},
    ]

    exact = module.filter_candidates(candidates, ["31370", "GPKG", "21009"])
    assert len(exact) == 3
    assert all("/GPKG/" in item["href"] for item in exact)
    assert all("21009" in item["href"] for item in exact)
    assert all("DWG" not in item["href"] for item in exact)

    latest = module.choose_candidate(exact, True)
    assert latest is not None
    assert module.candidate_date(latest) == "20260808"
    assert latest["href"].endswith("UrbISBuildings3D_31370_GPKG_21009_20260808.zip")

    non_latest = module.choose_candidate(exact, False)
    assert non_latest is not None

    missing = module.filter_candidates(candidates, ["31370", "GPKG", "99999"])
    assert missing == []

    print("URBIS_DISTRIBUTION_SELECTOR_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
