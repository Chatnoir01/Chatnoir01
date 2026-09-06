#!/usr/bin/env python3
"""Fail-closed bilateral locomotion evidence gate for CIV-1.

This gate intentionally does not infer a missing foot from the opposite foot. A
locomotion/foot-slide candidate may only advance after independently verified
Skeleton/Skin-tied raster identity exists for both LeftFoot and RightFoot at
2/4/8 m under the same frozen camera contract.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

DISTANCES = [2, 4, 8]
MAX_CENTROID_ERROR_PX = 1.5
MAX_PATH_REL_ERROR = 0.25


def _valid_foot(rec: dict, side: str) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    if not isinstance(rec, dict):
        return False, [f"{side}:missing"]
    if rec.get("side") != side:
        reasons.append(f"{side}:side")
    if rec.get("skeleton_skin_tied") is not True:
        reasons.append(f"{side}:skeleton_skin")
    if rec.get("resolution") != [1280, 720]:
        reasons.append(f"{side}:resolution")
    if rec.get("distances_m") != DISTANCES:
        reasons.append(f"{side}:distances")
    if rec.get("single_identity_preserved_2_4_8m") is not True:
        reasons.append(f"{side}:identity")
    if float(rec.get("max_centroid_error_px", 1e9)) > MAX_CENTROID_ERROR_PX:
        reasons.append(f"{side}:centroid")
    if float(rec.get("max_path_relative_error", 1e9)) > MAX_PATH_REL_ERROR:
        reasons.append(f"{side}:path")
    for key in (
        "planted_contact_claimed", "animation_correction_authorized",
        "runtime_authorized", "visual_approval_claimed", "player_view_claimed",
    ):
        if rec.get(key) is not False:
            reasons.append(f"{side}:rail:{key}")
    return not reasons, reasons


def analyze(doc: dict) -> dict:
    if doc.get("schema") != "grand-bruxelles-civ1-bilateral-foot-input-v1":
        raise ValueError("input schema")
    left_ok, left_reasons = _valid_foot(doc.get("leftfoot"), "LeftFoot")
    right_ok, right_reasons = _valid_foot(doc.get("rightfoot"), "RightFoot")
    bilateral = left_ok and right_ok
    return {
        "schema": "grand-bruxelles-civ1-bilateral-foot-promotion-v1",
        "diagnostic_only": True,
        "leftfoot_identity_ready": left_ok,
        "rightfoot_identity_ready": right_ok,
        "bilateral_identity_ready": bilateral,
        "blockers": left_reasons + right_reasons,
        "required_distances_m": DISTANCES,
        "max_centroid_error_px": MAX_CENTROID_ERROR_PX,
        "max_path_relative_error": MAX_PATH_REL_ERROR,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": (
            "AMELIORER_BILATERAL_IDENTITY_PRESENT_STILL_NO_SLIDE_PROMOTION"
            if bilateral else
            "AMELIORER_RIGHTFOOT_EVIDENCE_REQUIRED_NO_SLIDE_PROMOTION"
        ),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_bilateral_foot_promotion.py INPUT.json OUT.json", file=sys.stderr)
        return 2
    try:
        doc = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        out = analyze(doc)
        Path(argv[2]).write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_BILATERAL_FOOT_PROMOTION_FAIL: {exc}", file=sys.stderr)
        return 3
    print("CIV1_BILATERAL_FOOT_PROMOTION_OK", out["verdict"], out["blockers"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
