#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "tools" / "project_civ1_motion_at_player_distances.py"
spec = importlib.util.spec_from_file_location("distance_projection", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def base() -> dict:
    return {
        "schema": "grand-bruxelles-civ1-rendered-sole-world-correlation-v1",
        "candidate_samples": [115, 116, 117, 118],
        "world_horizontal_path_m": 0.0117063114885241,
        "planted_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "ground_contact_claimed": False,
        "runtime_authorized": False,
        "animation_correction_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "perceptual_2_8m_claimed": False,
    }


def expect_raises(mutator) -> None:
    d = base()
    mutator(d)
    try:
        mod.project(d)
    except ValueError:
        return
    raise AssertionError("expected fail-closed rejection")


def main() -> None:
    report = mod.project(base())
    assert report["schema"] == "grand-bruxelles-civ1-player-distance-projection-plan-v1"
    assert report["camera_distances_m"] == [2.0, 4.0, 8.0]
    assert report["resolution"] == [1280, 720]
    assert report["vertical_fov_deg"] == 45.0
    px = [r["expected_horizontal_motion_px"] for r in report["projections"]]
    assert px[0] > px[1] > px[2] > 0.0
    assert math.isclose(px[0] / px[1], 2.0, rel_tol=1e-12)
    assert math.isclose(px[1] / px[2], 2.0, rel_tol=1e-12)
    assert all(r["real_raster_observed"] is False for r in report["projections"])
    for key in (
        "actual_2_4_8m_rasters_present",
        "perceptual_2_8m_claimed",
        "planted_contact_claimed",
        "rendered_sole_contact_claimed",
        "ground_contact_claimed",
        "runtime_authorized",
        "animation_correction_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
    ):
        assert report[key] is False
    assert report["verdict"] == "AMELIORER_DISTANCE_CAPTURE_SIGNAL_PLANNED_REAL_RASTER_REQUIRED"

    expect_raises(lambda d: d.__setitem__("schema", "wrong"))
    expect_raises(lambda d: d.__setitem__("candidate_samples", [115, 116, 117]))
    expect_raises(lambda d: d.__setitem__("world_horizontal_path_m", float("nan")))
    expect_raises(lambda d: d.__setitem__("world_horizontal_path_m", -0.001))
    for key in (
        "planted_contact_claimed",
        "rendered_sole_contact_claimed",
        "ground_contact_claimed",
        "runtime_authorized",
        "animation_correction_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
        "perceptual_2_8m_claimed",
    ):
        expect_raises(lambda d, k=key: d.__setitem__(k, True))
    print("CIV1_PLAYER_DISTANCE_PROJECTION_TEST_OK")


if __name__ == "__main__":
    main()
