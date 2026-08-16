#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("heights", HERE / "derive_cell_building_height_candidates.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell = root / "bxl-e142000-n169000-s500"
    (cell / "raw").mkdir(parents=True)
    (cell / "manifest.json").write_text(json.dumps({
        "format": mod.SOURCE_FORMAT,
        "cell_id": cell.name,
        "crs": mod.CRS,
        "bbox": [142000, 169000, 142500, 169500],
    }), encoding="utf-8")

    valid = {
        "id": "Buildings.valid",
        "type": "Feature",
        "properties": {"INSPIRE_ID": "B-valid", "AREA": 100.0},
        "geometry": {"type": "Polygon", "coordinates": [[[142010,169010],[142020,169010],[142020,169020],[142010,169020],[142010,169010]]]},
    }
    # These are present in the authoritative raw layer but are rejected by the
    # candidate-package contract, so they must not inflate the height sample set.
    missing_inspire = {
        "id": "Buildings.no-inspire",
        "type": "Feature",
        "properties": {"AREA": 20.0},
        "geometry": {"type": "Polygon", "coordinates": [[[142030,169030],[142040,169030],[142040,169040],[142030,169040],[142030,169030]]]},
    }
    multipolygon = {
        "id": "Buildings.multi",
        "type": "Feature",
        "properties": {"INSPIRE_ID": "B-multi", "AREA": 30.0},
        "geometry": {"type": "MultiPolygon", "coordinates": [[[[142050,169050],[142060,169050],[142060,169060],[142050,169060],[142050,169050]]]]},
    }
    (cell / "raw" / "buildings.geojson").write_text(json.dumps({
        "type": "FeatureCollection",
        "features": [valid, missing_inspire, multipolygon],
    }), encoding="utf-8")

    value = cell / "elevation_value_evidence.json"
    value.write_text(json.dumps({
        "format": mod.VALUE_FORMAT,
        "cell_id": cell.name,
        "crs": mod.CRS,
        "height_source_pair_ready": True,
        "evidence_digest": "a" * 64,
    }), encoding="utf-8")
    frontier = cell / "elevation_candidate_frontier.json"
    frontier.write_text(json.dumps({
        "format": mod.FRONTIER_FORMAT,
        "cell_id": cell.name,
        "crs": mod.CRS,
        "heights": {"source_pair_ready": True, "building_sample_target_count": 1},
        "frontier_digest": "b" * 64,
        "runtime_promotion_allowed": False,
    }), encoding="utf-8")
    raster = cell / "elevation_raster_validation.json"
    raster.write_text(json.dumps({
        "format": mod.RASTER_FORMAT,
        "cell_id": cell.name,
        "crs": mod.CRS,
        "validation_digest": "c" * 64,
        "dsm": {"rasters": []},
        "dtm": {"rasters": []},
    }), encoding="utf-8")

    original = mod.sample_building
    mod.sample_building = lambda feature, *_: ([8.0] * 64, 64)
    try:
        result = mod.build(cell, value, frontier, raster, root)
    finally:
        mod.sample_building = original

    assert result["building_count"] == 1, result
    assert [row["building_id"] for row in result["buildings"]] == ["B-valid"], result
    assert "frontier_building_target_count_mismatch" not in result["blockers"], result
    assert result["runtime_approved_count"] == 0
    assert result["runtime_promotion_allowed"] is False

print("HEIGHT_SAMPLER_CANDIDATE_CONTRACT_OK sampled_only_candidate_package_eligible=true runtime_approval=false")
