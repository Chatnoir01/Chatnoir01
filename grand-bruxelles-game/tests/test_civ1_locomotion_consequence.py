#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "assess_civ1_locomotion_consequence.py"
spec = importlib.util.spec_from_file_location("locomotion", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def bilateral() -> dict:
    return {"verdict": "ALLOW_QA_BILATERAL_REST_ATTRIBUTION", "runtime_authorized": False}


def png(width: int = 1280, height: int = 720) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    ihdr = struct.pack(">I", len(ihdr_data)) + b"IHDR" + ihdr_data
    ihdr += struct.pack(">I", zlib.crc32(b"IHDR" + ihdr_data) & 0xFFFFFFFF)
    iend = struct.pack(">I", 0) + b"IEND" + struct.pack(">I", zlib.crc32(b"IEND") & 0xFFFFFFFF)
    return signature + ihdr + iend


def locomotion(frame: bytes) -> dict:
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
            "frame_sha256": hashlib.sha256(frame).hexdigest(),
        },
        "feet": {
            "LeftFoot": {"baseline": dict(sample), "counterfactual": dict(sample), "same_animation_window": True},
            "RightFoot": {"baseline": dict(sample), "counterfactual": dict(sample), "same_animation_window": True},
        },
    }


def main() -> int:
    frame = png()
    allowed = module.assess(bilateral(), locomotion(frame), frame)
    assert allowed["verdict"] == "ALLOW_QA_LOCOMOTION_COMPARISON"
    assert allowed["frame_receipt_verified"] is True
    assert allowed["runtime_authorized"] is False
    assert allowed["visual_approval_claimed"] is False

    missing = module.assess(bilateral(), locomotion(frame), None)
    assert "missing_frame_receipt" in missing["failures"]
    assert missing["frame_receipt_verified"] is False

    forged = locomotion(frame)
    forged["player_view_capture"]["frame_sha256"] = hashlib.sha256(b"not-the-frame").hexdigest()
    result = module.assess(bilateral(), forged, frame)
    assert "frame_sha256_mismatch" in result["failures"]

    wrong_size = png(640, 360)
    wrong_size_meta = locomotion(wrong_size)
    wrong_size_meta["player_view_capture"]["width"] = 640
    wrong_size_meta["player_view_capture"]["height"] = 360
    result = module.assess(bilateral(), wrong_size_meta, wrong_size)
    assert "player_view_not_1280x720" in result["failures"]
    assert "frame_receipt_not_1280x720" in result["failures"]

    metadata_lie = locomotion(frame)
    result = module.assess(bilateral(), metadata_lie, png(1920, 1080))
    assert "frame_receipt_not_1280x720" in result["failures"]
    assert "frame_metadata_dimension_mismatch" in result["failures"]

    invalid_png = b"not-a-png"
    invalid = locomotion(invalid_png)
    result = module.assess(bilateral(), invalid, invalid_png)
    assert "invalid_frame_png" in result["failures"]

    nan_drift = locomotion(frame)
    nan_drift["feet"]["RightFoot"]["baseline"]["planted_horizontal_drift_m"] = float("nan")
    result = module.assess(bilateral(), nan_drift, frame)
    assert "invalid_horizontal_drift:RightFoot:baseline" in result["failures"]

    infinite_span = locomotion(frame)
    infinite_span["feet"]["LeftFoot"]["counterfactual"]["planted_vertical_span_m"] = float("inf")
    result = module.assess(bilateral(), infinite_span, frame)
    assert "invalid_vertical_span:LeftFoot:counterfactual" in result["failures"]

    fake_hash = locomotion(frame)
    fake_hash["player_view_capture"]["frame_sha256"] = "z" * 64
    result = module.assess(bilateral(), fake_hash, frame)
    assert "invalid_frame_sha256" in result["failures"]

    camera_rescue = locomotion(frame)
    camera_rescue["player_view_capture"]["camera_unchanged"] = False
    result = module.assess(bilateral(), camera_rescue, frame)
    assert "camera_rescue_detected" in result["failures"]

    ai_frame = locomotion(frame)
    ai_frame["player_view_capture"]["ai_generated"] = True
    result = module.assess(bilateral(), ai_frame, frame)
    assert "ai_generated_evidence_forbidden" in result["failures"]

    mismatch = locomotion(frame)
    mismatch["feet"]["RightFoot"]["counterfactual"]["planted_sample_count"] = 7
    result = module.assess(bilateral(), mismatch, frame)
    assert "sample_count_mismatch:RightFoot" in result["failures"]

    weak = bilateral()
    weak["verdict"] = "BLOCK_UNSUPPORTED_BILATERAL_REST_ATTRIBUTION"
    result = module.assess(weak, locomotion(frame), frame)
    assert "bilateral_causality_not_proven" in result["failures"]
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
