#!/usr/bin/env python3
from calibrate_ixelles_dsm_policy import calibrate


def rec(i, semantic, p50, p75, p90, policy):
    return {"building_id":f"b{i}","semantic_height_m":semantic,"dsm_height_p50_m":p50,"dsm_height_p75_m":p75,"dsm_height_p90_m":p90,"dsm_policy_candidate_m":policy,"candidate_minus_semantic_m":policy-semantic,"abs_delta_m":abs(policy-semantic),"runtime_approved":False}

comparison={
    "cell":"bxl-e149000-n169000-s500","source_crs":"EPSG:31370","runtime_approved":False,"schema":"cmp",
    "records":[rec(1,10,10.2,12.0,13.0,12.0),rec(2,20,20.1,25.0,26.0,25.0),rec(3,30,29.9,31.0,33.0,31.0)]
}
semantic={"schema":"sem","matches":[
    {"status":"matched_semantic_evidence","matched_inspire_id":"b1","roof_z_p25_m":20,"roof_z_p75_m":21,"roof_faces":3},
    {"status":"matched_semantic_evidence","matched_inspire_id":"b2","roof_z_p25_m":30,"roof_z_p75_m":38,"roof_faces":8},
    {"status":"matched_semantic_evidence","matched_inspire_id":"b3","roof_z_p25_m":40,"roof_z_p75_m":44,"roof_faces":4},
]}
out=calibrate(comparison,semantic)
assert out["runtime_approved"] is False
assert out["decision"]["best_tested_statistic"] == "p50"
assert out["decision"]["promote_runtime"] is False
assert out["variant_metrics"]["dsm_height_p50_m"]["mae_m"] < out["variant_metrics"]["dsm_policy_candidate_m"]["mae_m"]
assert out["counts"]["current_conflicts_gt_4m"] == 1
assert out["counts"]["conflicts_overestimate"] == 1
print("IXELLES_DSM_POLICY_CALIBRATION_TEST_OK")
