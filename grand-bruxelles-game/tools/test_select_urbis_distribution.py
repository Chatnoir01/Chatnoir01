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

    # Real Atom metadata can describe a parent entry advertising multiple formats.
    # A concrete SHP href must never satisfy GPKG just because title/type metadata
    # happens to contain the word GPKG.
    mixed_anderlecht = [
        {
            "href": "https://datastore.brussels/download/332_31370_shp_21001_anderlecht.zip",
            "title": "Anderlecht GPKG SHP",
            "type": "application/gpkg+zip",
            "rel": "enclosure",
        },
        {
            "href": "https://datastore.brussels/download/332_31370_gpkg_21001_anderlecht.zip",
            "title": "Anderlecht GPKG SHP",
            "type": "application/zip",
            "rel": "enclosure",
        },
    ]
    gpkg_only = module.filter_candidates(mixed_anderlecht, ["31370", "GPKG", "21001", "Anderlecht"])
    assert len(gpkg_only) == 1, gpkg_only
    assert "_gpkg_" in gpkg_only[0]["href"].casefold()
    assert "_shp_" not in gpkg_only[0]["href"].casefold()

    # Workflow-specific guardrail: Brussels municipality code 21001 is Anderlecht;
    # 21009 is Ixelles. The official direct-file naming contract is allowed to use
    # the stable municipality code without spelling the municipality name in the URL.
    # Requiring both code and display name can make a valid official GPKG impossible
    # to select even when the feed metadata identifies the municipality correctly.
    workflow = MODULE_PATH.parents[2] / ".github/workflows/grand-bruxelles-citygen-anderlecht-secondary-height.yml"
    workflow_text = workflow.read_text(encoding="utf-8")
    assert "--candidate-token GPKG --candidate-token 21001 --prefer-latest" in workflow_text
    assert "assert all(x in folded for x in ('31370','gpkg','21001'))" in workflow_text
    assert "--candidate-token 21009" not in workflow_text
    assert "--candidate-token Anderlecht" not in workflow_text

    print("URBIS_DISTRIBUTION_SELECTOR_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
