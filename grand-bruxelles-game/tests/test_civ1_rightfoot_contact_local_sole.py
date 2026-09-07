#!/usr/bin/env python3
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "tools" / "analyze_civ1_rightfoot_contact_local_sole.py"
spec = importlib.util.spec_from_file_location("right_contact_sole", P)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

good = {
    2: [-3.60, -3.62, -3.58, -3.61],
    4: [-3.55, -3.57, -3.53, -3.56],
    8: [-3.50, -3.52, -3.48, -3.51],
}
q = m.assess_normalized_series(good)
assert q["passed"] is True
assert q["single_side_consistent"] is True

measured_shape = {
    2: [-3.7694687536, -3.7009631040, -1.8582859286, -1.4670868212],
    4: [-4.1435445931, -3.5180999552, -1.7623836162, -1.3151581271],
    8: [-3.7989065864, -2.6795725087, -1.5459072166, -1.1680187859],
}
q = m.assess_normalized_series(measured_shape)
assert q["single_side_consistent"] is True
assert q["distance_mean_relative_spread"] <= 0.15
assert q["passed"] is False
assert q["max_within_distance_relative_deviation"][2] > 0.47
assert q["max_within_distance_relative_deviation"][4] > 0.56
assert q["max_within_distance_relative_deviation"][8] > 0.79

side_flip = {2: [-3.5] * 4, 4: [-3.5] * 4, 8: [3.5] * 4}
assert m.assess_normalized_series(side_flip)["passed"] is False
assert m.MAX_DISTANCE_MEAN_REL_SPREAD == 0.15
assert m.MAX_WITHIN_DISTANCE_REL_DEVIATION == 0.15
assert m.ROI_RADIUS_MULT == 4.0
assert m.MIN_ROI_HALF_WIDTH_PX == 8
assert m.MAX_ANCHOR_CENTROID_ERROR_PX == 1.5

print("CIV1_RIGHTFOOT_CONTACT_LOCAL_SOLE_REGRESSION_OK")
