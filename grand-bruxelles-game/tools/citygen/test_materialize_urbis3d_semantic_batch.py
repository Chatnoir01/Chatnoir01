#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("materialize_urbis3d_semantic_batch", HERE / "materialize_urbis3d_semantic_batch.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

class FakeMatcher:
    SCHEMA = "grand-bruxelles-urbis3d-semantic-match-v2"
    MIN_MATCH_SCORE = 0.70
    MIN_RUNNER_UP_MARGIN = 0.15
    MIN_HEIGHT_M = 2.0
    MAX_HEIGHT_M = 100.0
    @staticmethod
    def percentile(values, p):
        values = sorted(values)
        if not values: return None
        if len(values) == 1: return values[0]
        pos=(len(values)-1)*p; lo=int(pos); hi=min(lo+1,len(values)-1); frac=pos-lo
        return values[lo]*(1-frac)+values[hi]*frac

CELL="bxl-e149000-n169000-s500"
BASE_POLICY={"crs":"EPSG:31370","runtime_approval":False}
def piece(municipality, matches):
    return {"schema":FakeMatcher.SCHEMA,"cell":CELL,"municipality":municipality,"policy":dict(BASE_POLICY),"matches":matches}
def match(solid, building, height, status="matched_semantic_evidence"):
    return {"busolid_id":solid,"status":status,"matched_inspire_id":building,"semantic_height_m":height,"match_score":0.97,"match_margin":0.42,"runtime_approved":False}

merged=mod._merge_evidence(
    cell_id=CELL,
    bbox=[149000.0,169000.0,149500.0,169500.0],
    municipalities=["bruxelles","ixelles"],
    building_count=3,
    pieces=[piece("bruxelles",[match("solid-a","building-a",12.0)]),piece("ixelles",[match("solid-b","building-b",18.0)])],
    package_provenance=[{"nis_code":"21004"},{"nis_code":"21009"}],
    matcher=FakeMatcher,
)
assert merged["schema"]==FakeMatcher.SCHEMA
assert merged["municipalities"]==["bruxelles","ixelles"]
assert merged["counts"]["urbis_2d_buildings"]==3
assert merged["counts"]["building_solids_in_bbox"]==2
assert merged["counts"]["matched_semantic_evidence"]==2
assert merged["semantic_height_summary_m"]["median"]==15.0
assert merged["policy"]["runtime_approval"] is False

# Identical evidence duplicated at a municipality boundary is deterministically deduped.
duplicate=match("solid-a","building-a",12.0)
deduped=mod._merge_evidence(
    cell_id=CELL,bbox=[149000,169000,149500,169500],municipalities=["bruxelles","ixelles"],building_count=1,
    pieces=[piece("bruxelles",[duplicate]),piece("ixelles",[dict(duplicate)])],package_provenance=[],matcher=FakeMatcher,
)
assert deduped["counts"]["building_solids_in_bbox"]==1

# Conflicting cross-package identity/height evidence must fail closed.
try:
    mod._merge_evidence(
        cell_id=CELL,bbox=[149000,169000,149500,169500],municipalities=["bruxelles","ixelles"],building_count=1,
        pieces=[piece("bruxelles",[match("solid-a","building-a",12.0)]),piece("ixelles",[match("solid-a","building-a",17.0)])],
        package_provenance=[],matcher=FakeMatcher,
    )
except ValueError as exc:
    assert "cross-package semantic ambiguity" in str(exc)
else:
    raise AssertionError("conflicting boundary evidence must fail closed")

assert mod._allowed_url("https://urbisdownload.datastore.brussels/UrbIS/example.zip")
assert not mod._allowed_url("http://urbisdownload.datastore.brussels/UrbIS/example.zip")
assert not mod._allowed_url("https://evil.example/UrbIS/example.zip")

with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    sqlite=root/"source.gpkg"; sqlite.write_bytes(b"SQLite format 3\x00"+b"x"*32)
    out=root/"sqlite-out"
    paths=mod._safe_extract(sqlite,out)
    assert len(paths)==1 and paths[0].name=="selected.gpkg"

    safe=root/"safe.zip"
    with zipfile.ZipFile(safe,"w") as archive:
        archive.writestr("nested/cell.gpkg",b"SQLite format 3\x00fixture")
    safe_paths=mod._safe_extract(safe,root/"safe-out")
    assert len(safe_paths)==1 and safe_paths[0].name=="cell.gpkg"

    unsafe=root/"unsafe.zip"
    with zipfile.ZipFile(unsafe,"w") as archive:
        archive.writestr("../escape.gpkg",b"SQLite format 3\x00fixture")
    try:
        mod._safe_extract(unsafe,root/"unsafe-out")
    except ValueError as exc:
        assert "unsafe UrbIS3D ZIP member path" in str(exc)
    else:
        raise AssertionError("ZIP path traversal must fail closed")

print("CITYGEN_URBIS3D_SEMANTIC_BATCH_TEST_OK multi_municipality=true dedupe=true ambiguity_fail_closed=true archive_safe=true runtime=false")
