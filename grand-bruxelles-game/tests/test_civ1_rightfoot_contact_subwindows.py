#!/usr/bin/env python3
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "tools" / "analyze_civ1_rightfoot_contact_subwindows.py"
spec = importlib.util.spec_from_file_location("right_contact_subwindows", P)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def receipt(series):
    return {
        "schema": "grand-bruxelles-civ1-rightfoot-contact-local-sole-v1",
        "samples": [68,69,70,71],
        "distances_m": [2,4,8],
        "max_distance_mean_relative_spread": 0.15,
        "max_within_distance_relative_deviation": {"2":0.4,"4":0.4,"8":0.4},
        "bone_local_sole_identity_preserved_2_4_8m": False,
        "contact_phase_ready": False,
        "quantitative_foot_slide_candidate": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "measurements": [
            {"distance_m": d, "records": [
                {"sample_index": s, "normalized_offset_x": v}
                for s,v in zip((68,69,70,71), series[d])
            ]}
            for d in (2,4,8)
        ],
    }

# Exact measured shape from real artifact 10001144196: neither contiguous
# three-sample window is eligible under the unchanged 15%/15% rails.
measured = {
    2: [-3.7694687536, -3.7009631040, -1.8582859286, -1.4670868212],
    4: [-4.1435445931, -3.5180999552, -1.7623836162, -1.3151581271],
    8: [-3.7989065864, -2.6795725087, -1.5459072166, -1.1680187859],
}
r = m.analyze(receipt(measured))
assert r["eligible_windows"] == []
assert r["rightfoot_contact_phase_ready"] is False
assert [w["samples"] for w in r["windows"]] == [[68,69,70],[69,70,71]]
assert all(w["passed"] is False for w in r["windows"])
assert r["windows"][0]["distance_mean_relative_spread"] > 0.15
assert max(r["windows"][0]["max_within_distance_relative_deviation"].values()) > 0.42
assert r["windows"][1]["distance_mean_relative_spread"] > 0.24
assert max(r["windows"][1]["max_within_distance_relative_deviation"].values()) > 0.73
assert r["verdict"] == "JETER_RIGHTFOOT_NO_STABLE_THREE_SAMPLE_CONTACT_SUBWINDOW"

# Positive control: a four-frame interval may be globally rejected while one
# contiguous three-frame core is stable. The analyzer must be able to detect it.
positive = {
    2: [-3.50,-3.52,-3.49,-5.0],
    4: [-3.45,-3.47,-3.44,-5.1],
    8: [-3.40,-3.42,-3.39,-5.2],
}
r = m.analyze(receipt(positive))
assert [68,69,70] in r["eligible_windows"]
assert r["rightfoot_contact_phase_ready"] is True

assert m.MIN_ELIGIBLE_SAMPLES == 3
assert m.MAX_DISTANCE_MEAN_REL_SPREAD == 0.15
assert m.MAX_WITHIN_DISTANCE_REL_DEVIATION == 0.15
print("CIV1_RIGHTFOOT_CONTACT_SUBWINDOW_REGRESSION_OK")
