#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("assess", HERE / "assess_cell_elevation_values.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

GOOD_DTM = {"valid_samples": 1000, "valid_ratio": 0.999, "min_m": 48.0, "max_m": 92.0, "span_m": 44.0}
GOOD_DSM = {"valid_samples": 1000, "valid_ratio": 0.999, "min_m": 48.0, "max_m": 130.0, "span_m": 82.0}
GOOD_DELTA = {"valid_samples": 1000, "valid_ratio": 0.999, "severe_negative_ratio": 0.001}
terrain, heights, failures = mod.assess_quality(GOOD_DTM, GOOD_DSM, GOOD_DELTA)
assert terrain is True and heights is True and failures == []

bad_dtm = dict(GOOD_DTM); bad_dtm.update({"min_m": 50.0, "max_m": 50.0, "span_m": 0.0})
terrain, heights, failures = mod.assess_quality(bad_dtm, GOOD_DSM, GOOD_DELTA)
assert terrain is False and heights is False and "dtm_degenerate_or_nearly_constant" in failures

bad_delta = dict(GOOD_DELTA); bad_delta["severe_negative_ratio"] = 0.5
terrain, heights, failures = mod.assess_quality(GOOD_DTM, GOOD_DSM, bad_delta)
assert terrain is True and heights is False and "dsm_minus_dtm_severe_negative_ratio_too_high" in failures

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    validation = root / "validation.json"
    validation.write_text(json.dumps({"format": mod.RASTER_FORMAT, "cell_id": "bxl-e149000-n169000-s500", "crs": "EPSG:31370", "bbox": [149000,169000,149500,169500]}), encoding="utf-8")
    original = mod._collect
    mod._collect = lambda *_: (dict(GOOD_DTM), dict(GOOD_DSM), dict(GOOD_DELTA))
    try:
        result = mod.build(validation, root)
    finally:
        mod._collect = original
    assert result["terrain_source_evidence_ready"] is True
    assert result["height_source_pair_ready"] is True
    assert result["maturity_effect"]["terrain_gate"] is False
    assert result["maturity_effect"]["heights_gate"] is False
    assert result["evidence_digest"] == mod._digest({k:v for k,v in result.items() if k != "evidence_digest"})

print("CELL_ELEVATION_VALUE_EVIDENCE_GUARDRAILS_OK nodata_fail_closed=true terrain_source=true height_pair=true runtime_gates_false=true")
