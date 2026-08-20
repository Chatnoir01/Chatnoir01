#!/usr/bin/env python3
import json
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "data/urbis/bourse_curb_alignment_source_lock.game.json"
D = json.loads(P.read_text(encoding="utf-8"))

assert D["schema"] == "grand-bruxelles-bourse-curb-alignment-source-lock-v1"
assert D["source"]["layer"] == "bm_urbis_topo:road_line"
assert D["source"]["resolved_topo_type"] == "BR0101L"
assert D["diagnostic_probe"]["production_base_sha"] == "a8737b5b4cbe0ee205bdede14217938118ee3c1b"
assert D["diagnostic_probe"]["sidewalk_intersecting_target_feature_count"] == 8
assert D["diagnostic_probe"]["cr63l_intersection_count_with_committed_sidewalks"] == 0
features = D["sidewalk_intersecting_features"]
assert len(features) == 8
assert len({f["feature_id"] for f in features}) == 8
assert all(f["topo_type"] == "BR0101L" for f in features)
assert {"road_line.27161", "road_line.142994", "road_line.181088"} <= {f["feature_id"] for f in features}
overlap = D["boundary_overlap_measurement"]
assert overlap["sample_count"] == 1147
assert overlap["estimated_boundary_overlap_length_within_0_10m_m"] == 43.0
assert 0.37 < overlap["sample_ratio_within_0_10m"] < 0.38
visual = D["negative_visual_evidence"]
assert visual["closed_unmerged_pr"] == 986
assert visual["changed_pixels_over_3_rgb_ratio"] < visual["frozen_gate_min_over_3_rgb_ratio"]
assert visual["difference_bbox_px"][1] < visual["frozen_gate_min_bbox_px"][1]
decision = D["decision"]
assert decision["horizontal_alignment_source_resolved"] is True
assert decision["horizontal_runtime_correction_justified_by_this_evidence"] is False
assert decision["physical_curb_height_supported"] is False
assert decision["dtm_1m_is_not_curb_height_proof"] is True
assert decision["vertical_extrusion_allowed"] is False
assert decision["curb_elevation_resolved"] is False
assert decision["runtime_approved"] is False
assert decision["realism_complete"] is False
print("BOURSE_CURB_ALIGNMENT_SOURCE_LOCK_OK")
