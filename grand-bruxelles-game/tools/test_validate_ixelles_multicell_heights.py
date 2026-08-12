#!/usr/bin/env python3
from validate_ixelles_multicell_heights import bbox_for_cell, calibrate_any


def rec(i, semantic, p50, p75, p90, policy):
    return {
        "building_id": f"b{i}",
        "semantic_height_m": semantic,
        "dsm_height_p50_m": p50,
        "dsm_height_p75_m": p75,
        "dsm_height_p90_m": p90,
        "dsm_policy_candidate_m": policy,
        "candidate_minus_semantic_m": policy - semantic,
        "abs_delta_m": abs(policy - semantic),
        "runtime_approved": False,
    }


cell = "bxl-e149500-n169500-s500"
bbox = [149500.0, 169500.0, 150000.0, 170000.0]
assert bbox_for_cell(cell) == bbox
try:
    bbox_for_cell("bxl-e150000-n170000-s500")
    raise AssertionError("outside cell accepted")
except ValueError:
    pass

comparison = {
    "cell": cell,
    "source_crs": "EPSG:31370",
    "runtime_approved": False,
    "records": [
        rec(1, 10, 10.1, 12.0, 14.0, 12.0),
        rec(2, 20, 20.2, 26.0, 28.0, 26.0),
        rec(3, 30, 29.9, 31.0, 34.0, 31.0),
    ],
}
semantic = {
    "cell": cell,
    "bbox_epsg31370": bbox,
    "policy": {"crs": "EPSG:31370", "runtime_approval": False},
}
out = calibrate_any(comparison, semantic, cell)
assert out["runtime_approved"] is False
assert out["decision"]["promote_runtime"] is False
assert out["decision"]["best_tested_statistic"] == "p50"
assert out["counts"]["joined"] == 3
assert out["counts"]["current_conflicts_gt_4m"] == 1
print("IXELLES_MULTICELL_HEIGHT_VALIDATION_TEST_OK")
