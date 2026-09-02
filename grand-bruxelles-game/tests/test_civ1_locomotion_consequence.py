#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "assess_civ1_locomotion_consequence.py"
spec = importlib.util.spec_from_file_location("locomotion", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def bilateral() -> dict:
    return {"verdict": "ALLOW_QA_BILATERAL_REST_ATTRIBUTION", "runtime_authorized": False}


def locomotion() -> dict:
    sample = {
        "planted_sample_count": 8,
        "planted_horizontal_drift_m": 0.031,
        "planted_vertical_span_m": 0.012,
    }
    return {
        "format": "grand-bruxelles-civ1-locomotion-consequence-v1",
        "counterfactual_only": True,
        "runtime_authorized": False,
        "player_view_capture": {
            "width": 1280,
            "height": 720,
            "full_frame": True,
            "camera_unchanged": True,
            "ai_generated": False,
            "frame_sha256": "a" * 64,
        },
        "feet": {
            "LeftFoot": {"baseline": dict(sample), "counterfactual": dict(sample), "same_animation_window": True},
            "RightFoot": {"baseline": dict(sample), "counterfactual": dict(sample), "same_animation_window": True},
        },
    }


def main() -> int:
    allowed = module.assess(bilateral(), locomotion())
    assert allowed["verdict"] == "ALLOW_QA_LOCOMOTION_COMPARISON"
    assert allowed["runtime_authorized"] is False
    assert allowed["visual_approval_claimed"] is False

    no_capture = locomotion(); no_capture.pop("player_view_capture")
    assert module.assess(bilateral(), no_capture)["verdict"] == "BLOCK_INCOMPLETE_LOCOMOTION_EVIDENCE"

    camera_rescue = locomotion(); camera_rescue["player_view_capture"]["camera_unchanged"] = False
    result = module.assess(bilateral(), camera_rescue)
    assert "camera_rescue_detected" in result["failures"]

    ai_frame = locomotion(); ai_frame["player_view_capture"]["ai_generated"] = True
    result = module.assess(bilateral(), ai_frame)
    assert "ai_generated_evidence_forbidden" in result["failures"]

    mismatch = locomotion(); mismatch["feet"]["RightFoot"]["counterfactual"]["planted_sample_count"] = 7
    result = module.assess(bilateral(), mismatch)
    assert "sample_count_mismatch:RightFoot" in result["failures"]

    weak = bilateral(); weak["verdict"] = "BLOCK_UNSUPPORTED_BILATERAL_REST_ATTRIBUTION"
    result = module.assess(weak, locomotion())
    assert "bilateral_causality_not_proven" in result["failures"]

    nan_drift = locomotion(); nan_drift["feet"]["RightFoot"]["baseline"]["planted_horizontal_drift_m"] = float("nan")
    result = module.assess(bilateral(), nan_drift)
    assert "invalid_horizontal_drift:RightFoot:baseline" in result["failures"]

    infinite_span = locomotion(); infinite_span["feet"]["LeftFoot"]["counterfactual"]["planted_vertical_span_m"] = float("inf")
    result = module.assess(bilateral(), infinite_span)
    assert "invalid_vertical_span:LeftFoot:counterfactual" in result["failures"]

    fake_hash = locomotion(); fake_hash["player_view_capture"]["frame_sha256"] = "z" * 64
    result = module.assess(bilateral(), fake_hash)
    assert "invalid_frame_sha256" in result["failures"]
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
