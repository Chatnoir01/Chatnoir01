#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "tools" / "correlate_civ1_rendered_sole_motion.py"
spec = importlib.util.spec_from_file_location("corr", TOOL)
assert spec and spec.loader
corr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(corr)


def raster() -> dict:
    return {
        "schema": "grand-bruxelles-civ1-rendered-sole-silhouette-v1",
        "source_semantic": "actual_godot_1280x720_low_side_raster",
        "candidate_samples": [115, 116, 117, 118],
        "candidate_bottom_centroid_path_px": 8.0,
        "candidate_bottom_row_span_px": 0,
        "ground_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }


def ground() -> dict:
    return {
        "schema": "grand-bruxelles-civ1-left-ground-reference-v3",
        "reference_semantic": "canonical_main_ground_collision_raycast",
        "resolution": [1280, 720],
        "target_left_candidate_samples": [115, 116, 117, 118],
        "candidate_left_horizontal_path_m": 0.0116812700871378,
        "candidate_left_min_clearance_m": 0.0062804669,
        "candidate_left_max_clearance_m": 0.0121824890,
        "ground_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }


def must_fail(r: dict, g: dict) -> None:
    try:
        corr.correlate(r, g)
    except corr.CorrelationError:
        return
    raise AssertionError("expected fail-closed correlation rejection")


def main() -> None:
    out = corr.correlate(raster(), ground())
    assert out["motion_observed_in_both_spaces"] is True
    assert abs(out["world_horizontal_path_m"] - 0.0116812700871378) < 1e-12
    assert abs(out["raster_centroid_path_px"] - 8.0) < 1e-12
    assert abs(out["world_mm_per_raster_px"] - 1.460158760892225) < 1e-12
    assert out["calibrated_player_distance_m"] is None
    assert out["perceptual_2_8m_claimed"] is False
    assert out["planted_contact_claimed"] is False
    assert out["animation_correction_authorized"] is False
    assert out["runtime_authorized"] is False

    bad = copy.deepcopy(raster())
    bad["candidate_samples"] = [114, 115, 116, 117]
    must_fail(bad, ground())

    bad = copy.deepcopy(ground())
    bad["ground_contact_claimed"] = True
    must_fail(raster(), bad)

    bad = copy.deepcopy(raster())
    bad["candidate_bottom_centroid_path_px"] = float("nan")
    must_fail(bad, ground())

    zero = raster()
    zero["candidate_bottom_centroid_path_px"] = 0.0
    out = corr.correlate(zero, ground())
    assert out["motion_observed_in_both_spaces"] is False
    assert out["world_mm_per_raster_px"] is None

    print("CIV1_RENDERED_SOLE_MOTION_CORRELATION_TEST_OK")


if __name__ == "__main__":
    main()
