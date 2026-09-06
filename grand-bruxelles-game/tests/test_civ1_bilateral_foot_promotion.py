#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tools" / "analyze_civ1_bilateral_foot_promotion.py"
spec = importlib.util.spec_from_file_location("bilateral", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


def foot(side: str) -> dict:
    return {
        "side": side,
        "skeleton_skin_tied": True,
        "resolution": [1280, 720],
        "distances_m": [2, 4, 8],
        "single_identity_preserved_2_4_8m": True,
        "max_centroid_error_px": 1.49,
        "max_path_relative_error": 0.249,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }

base = {"schema": "grand-bruxelles-civ1-bilateral-foot-input-v1", "leftfoot": foot("LeftFoot")}
missing = mod.analyze(base)
assert missing["leftfoot_identity_ready"] is True
assert missing["rightfoot_identity_ready"] is False
assert missing["bilateral_identity_ready"] is False
assert missing["quantitative_foot_slide_candidate"] is False
assert "RightFoot:missing" in missing["blockers"]

both = dict(base)
both["rightfoot"] = foot("RightFoot")
ready = mod.analyze(both)
assert ready["bilateral_identity_ready"] is True
assert ready["quantitative_foot_slide_candidate"] is False
assert ready["animation_correction_authorized"] is False

bad = dict(base)
bad["rightfoot"] = foot("RightFoot")
bad["rightfoot"]["max_path_relative_error"] = 0.251
rejected = mod.analyze(bad)
assert rejected["bilateral_identity_ready"] is False
assert "RightFoot:path" in rejected["blockers"]

wrong_side = dict(base)
wrong_side["rightfoot"] = foot("LeftFoot")
rejected = mod.analyze(wrong_side)
assert rejected["rightfoot_identity_ready"] is False
assert "RightFoot:side" in rejected["blockers"]

print("CIV1_BILATERAL_FOOT_PROMOTION_REGRESSION_OK")
