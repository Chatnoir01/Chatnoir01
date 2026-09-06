#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / "tools" / "analyze_civ1_bilateral_landmark_promotion.py"
spec = importlib.util.spec_from_file_location("bilateral_landmark", TOOL)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


SAMPLES = [114, 115, 116, 117, 118]


def receipt(side: str) -> dict:
    """Synthetic receipt matching the real LeftFoot/RightFoot v1 record schema."""
    lower = side.lower()
    return {
        "schema": f"grand-bruxelles-civ1-{lower}-landmark-raster-analysis-v1",
        "diagnostic_only": True,
        "landmark_semantic": f"magenta_raster_of_verified_{lower}_bone_pose",
        "samples": SAMPLES,
        "distances_m": [2, 4, 8],
        "max_centroid_error_px": 1.5,
        "max_path_relative_error": 0.25,
        "measurements": [
            {
                "distance_m": d,
                "records": [
                    {
                        "sample_index": s,
                        "centroid_x_px": 500.0 + (s - 114) * 0.5,
                        "centroid_y_px": 300.0,
                        "marker_pixel_count": 64,
                        "marker_weight": 16320.0,
                        "expected_screen_x_px": 500.2 + (s - 114) * 0.5,
                        "expected_screen_y_px": 300.1,
                        "centroid_error_px": 0.22360679775,
                    }
                    for s in SAMPLES
                ],
                "path_relative_error": 0.09,
                "max_centroid_error_px": 0.8,
                "direction_match": True,
                "passed": True,
            }
            for d in [2, 4, 8]
        ],
        f"single_{lower}_identity_preserved_2_4_8m": True,
        "quantitative_landmark_candidate": True,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }


def run_pair(left: dict, right: dict) -> dict:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        lp, rp = root / "left.json", root / "right.json"
        lp.write_text(json.dumps(left), encoding="utf-8")
        rp.write_text(json.dumps(right), encoding="utf-8")
        return m.analyze(lp, rp)


def main() -> int:
    # Positive control mirrors the record-level fields present in both immutable
    # Godot landmark receipts, rather than an older summary-only fixture.
    good = run_pair(receipt("leftfoot"), receipt("rightfoot"))
    assert good["schema"] == "grand-bruxelles-civ1-bilateral-landmark-promotion-v2"
    assert good["centroid_validation_semantic"] == "recomputed_from_every_record_not_summary_only"
    assert good["bilateral_identity_ready"] is True
    assert good["leftfoot"]["max_observed_record_centroid_error_px"] < 1.5
    assert good["rightfoot"]["max_observed_record_centroid_error_px"] < 1.5
    assert good["bilateral_contact_phase_ready"] is False
    assert good["quantitative_foot_slide_candidate"] is False
    assert good["animation_correction_authorized"] is False
    assert good["runtime_authorized"] is False
    assert good["player_view_claimed"] is False
    assert good["verdict"].startswith("AMELIORER_BILATERAL_LANDMARK_IDENTITY_READY")

    wrong_side = receipt("rightfoot")
    wrong_side["landmark_semantic"] = "magenta_raster_of_verified_leftfoot_bone_pose"
    bad = run_pair(receipt("leftfoot"), wrong_side)
    assert bad["bilateral_identity_ready"] is False
    assert bad["rightfoot"]["ready"] is False
    assert "landmark_semantic" in bad["rightfoot"]["problems"]

    weak = receipt("rightfoot")
    weak["measurements"][2]["path_relative_error"] = 0.251
    bad = run_pair(receipt("leftfoot"), weak)
    assert bad["bilateral_identity_ready"] is False
    assert "distance_8_path" in bad["rightfoot"]["problems"]

    # Causal v2 regression: a forged/lagging summary must not hide one bad frame.
    record_bad = receipt("rightfoot")
    record_bad["measurements"][1]["max_centroid_error_px"] = 0.2
    record_bad["measurements"][1]["records"][2]["centroid_error_px"] = 1.501
    bad = run_pair(receipt("leftfoot"), record_bad)
    assert bad["bilateral_identity_ready"] is False
    assert "distance_4_centroid_record" in bad["rightfoot"]["problems"]

    # Missing record-level error is fail-closed; v2 must never silently fall back
    # to the distance summary after claiming record-level validation.
    missing_record_error = receipt("leftfoot")
    del missing_record_error["measurements"][0]["records"][0]["centroid_error_px"]
    bad = run_pair(missing_record_error, receipt("rightfoot"))
    assert bad["bilateral_identity_ready"] is False
    assert "distance_2_centroid_record" in bad["leftfoot"]["problems"]

    promoted = receipt("leftfoot")
    promoted["planted_contact_claimed"] = True
    bad = run_pair(promoted, receipt("rightfoot"))
    assert bad["bilateral_identity_ready"] is False
    assert "planted_contact_claimed" in bad["leftfoot"]["problems"]

    text = TOOL.read_text(encoding="utf-8")
    for literal in (
        '"bilateral_contact_phase_ready": False',
        '"quantitative_foot_slide_candidate": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"player_view_claimed": False',
    ):
        assert literal in text
    print("CIV1_BILATERAL_LANDMARK_PROMOTION_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
