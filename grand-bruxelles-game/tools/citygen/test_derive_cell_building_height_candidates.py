#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("heights", HERE / "derive_cell_building_height_candidates.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

high = mod.summarize_height_deltas([10.0 + (i % 5) for i in range(100)], 100)
assert high["confidence"] == "high", high
assert high["candidate_height_m"] == high["plausible_difference_m"]["p75"]
assert high["candidate_policy"] == "high_confidence_p75"
assert high["runtime_approved"] is False

medium = mod.summarize_height_deltas([8.0 + (i % 3) for i in range(25)], 25)
assert medium["confidence"] == "medium", medium
assert medium["candidate_height_m"] == medium["plausible_difference_m"]["p50"]
assert medium["candidate_policy"] == "medium_confidence_p50"

insufficient = mod.summarize_height_deltas([12.0] * 10, 10)
assert insufficient["confidence"] == "insufficient"
assert insufficient["candidate_height_m"] is None
assert insufficient["candidate_policy"] == "no_candidate"

noisy = mod.summarize_height_deltas([-5.0] * 10 + [15.0] * 70 + [400.0] * 20, 100)
assert noisy["negative_below_noise_count"] == 10
assert noisy["over_250m_count"] == 20
assert noisy["pixel_count_plausible"] == 70
assert noisy["confidence"] == "medium"

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell = root / "cell"
    (cell / "raw").mkdir(parents=True)
    (cell / "manifest.json").write_text(json.dumps({
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": "bxl-e149000-n169000-s500",
        "crs": "EPSG:31370",
        "bbox": [149000,169000,149500,169500],
    }), encoding="utf-8")
    features = [
        {"id":"Buildings.2","type":"Feature","properties":{"INSPIRE_ID":"B2","AREA":120.0},"geometry":{"type":"Polygon","coordinates":[[[149010,169010],[149020,169010],[149020,169020],[149010,169020],[149010,169010]]]}},
        {"id":"Buildings.1","type":"Feature","properties":{"INSPIRE_ID":"B1","AREA":80.0},"geometry":{"type":"Polygon","coordinates":[[[149030,169030],[149040,169030],[149040,169040],[149030,169040],[149030,169030]]]}},
    ]
    (cell / "raw" / "buildings.geojson").write_text(json.dumps({"type":"FeatureCollection","features":features}), encoding="utf-8")
    value_evidence = cell / "elevation_value_evidence.json"
    value_evidence.write_text(json.dumps({
        "format": mod.VALUE_FORMAT,
        "cell_id": "bxl-e149000-n169000-s500",
        "crs": "EPSG:31370",
        "height_source_pair_ready": True,
        "evidence_digest": "a" * 64,
    }), encoding="utf-8")
    raster_validation = cell / "elevation_raster_validation.json"
    raster_validation.write_text(json.dumps({
        "format": mod.RASTER_FORMAT,
        "cell_id": "bxl-e149000-n169000-s500",
        "crs": "EPSG:31370",
        "validation_digest": "b" * 64,
        "dsm": {"rasters": []}, "dtm": {"rasters": []},
    }), encoding="utf-8")
    original = mod.sample_building
    def fake_sample(feature, *_):
        stable = (feature.get("properties") or {}).get("INSPIRE_ID")
        return ([12.0] * 100, 100) if stable == "B1" else ([9.0] * 25, 25)
    mod.sample_building = fake_sample
    try:
        result = mod.build(cell, value_evidence, raster_validation, root)
    finally:
        mod.sample_building = original
    assert [row["building_id"] for row in result["buildings"]] == ["B1", "B2"]
    assert result["confidence_counts"] == {"high":1,"medium":1,"insufficient":0}
    assert result["candidate_count"] == 2
    assert result["runtime_approved_count"] == 0
    assert result["maturity_effect"]["heights_gate"] is False
    assert result["candidate_digest"] == mod._digest({k:v for k,v in result.items() if k != "candidate_digest"})

print("CELL_BUILDING_HEIGHT_CANDIDATE_GUARDRAILS_OK confidence=true deterministic=true runtime_approval=false")
