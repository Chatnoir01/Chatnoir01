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


def receipt(side: str) -> dict:
    lower = side.lower()
    return {
        "schema": f"grand-bruxelles-civ1-{lower}-landmark-raster-analysis-v1",
        "diagnostic_only": True,
        "landmark_semantic": f"magenta_raster_of_verified_{lower}_bone_pose",
        "samples": [114, 115, 116, 117, 118],
        "distances_m": [2, 4, 8],
        "max_centroid_error_px": 1.5,
        "max_path_relative_error": 0.25,
        "measurements": [
            {
                "distance_m": d,
                "records": [{"sample_index": s} for s in [114, 115, 116, 117, 118]],
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
    good = run_pair(receipt("leftfoot"), receipt("rightfoot"))
    assert good["bilateral_identity_ready"] is True
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
