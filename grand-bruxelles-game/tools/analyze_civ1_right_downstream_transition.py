#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-right-downstream-transition-v1"


def _y(sample: dict, bone: str, side: str) -> float:
    return float(sample["bones"][bone][side][f"{side}_hips_relative_origin"][1])


def _terms(sample: dict, prefix: str) -> dict[str, float]:
    upper = prefix + "UpperLeg"
    lower = prefix + "LowerLeg"
    foot = prefix + "Foot"
    upper_error = _y(sample, upper, "target") - _y(sample, upper, "source")
    lower_relative_error = ((_y(sample, lower, "target") - _y(sample, upper, "target")) - (_y(sample, lower, "source") - _y(sample, upper, "source")))
    foot_relative_error = ((_y(sample, foot, "target") - _y(sample, lower, "target")) - (_y(sample, foot, "source") - _y(sample, lower, "source")))
    downstream_error = lower_relative_error + foot_relative_error
    return {"upperleg_hips_error_m": upper_error, "lowerleg_relative_error_m": lower_relative_error, "foot_relative_error_m": foot_relative_error, "downstream_error_m": downstream_error, "final_foot_error_m": upper_error + downstream_error}


def _first_crossing(rows: list[dict], key: str) -> dict | None:
    for left, right in zip(rows, rows[1:]):
        a = left["right"][key]
        b = right["right"][key]
        if a == 0.0 or b == 0.0 or a * b < 0.0:
            return {"term": key, "from_sample": left["sample_index"], "to_sample": right["sample_index"], "from_m": a, "to_m": b}
    return None


def analyze(payload: dict, start: int = 58, end: int = 88) -> dict:
    samples = payload.get("model_space_samples")
    if not isinstance(samples, list) or len(samples) < end + 1:
        raise ValueError("insufficient model_space_samples")
    rows: list[dict] = []
    for sample_index in range(start, end + 1):
        sample = samples[sample_index]
        if sample.get("sample_index") != sample_index:
            raise ValueError("sample index drift")
        right = _terms(sample, "Right")
        left = _terms(sample, "Left")
        if not all(math.isfinite(value) for value in (*right.values(), *left.values())):
            raise ValueError("non-finite composition term")
        rows.append({"sample_index": sample_index, "time_s": float(sample["time_s"]), "right": right, "left": left})
    downstream = _first_crossing(rows, "downstream_error_m")
    if downstream is None:
        raise ValueError("right downstream sum does not cross zero in transition window")
    lower = _first_crossing(rows, "lowerleg_relative_error_m")
    foot = _first_crossing(rows, "foot_relative_error_m")
    return {"schema": SCHEMA, "diagnostic_only": True, "window": [start, end], "first_right_downstream_zero_crossing": downstream, "first_right_lowerleg_relative_zero_crossing": lower, "first_right_foot_relative_zero_crossing": foot, "rows": rows, "runtime_authorized": False, "grounding_verified": False, "foot_slide_verified": False, "visual_approval_claimed": False, "verdict": "DIAGNOSTIC_RIGHT_DOWNSTREAM_ZERO_CROSSING_ISOLATED"}


def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("native_json"); parser.add_argument("output_json"); args = parser.parse_args()
    payload = json.loads(Path(args.native_json).read_text()); result = analyze(payload); Path(args.output_json).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    crossing = result["first_right_downstream_zero_crossing"]
    print("CIV1_RIGHT_DOWNSTREAM_TRANSITION_OK " f"crossing={crossing['from_sample']}->{crossing['to_sample']} " f"from_mm={crossing['from_m'] * 1000:.3f} " f"to_mm={crossing['to_m'] * 1000:.3f}")

if __name__ == "__main__": main()
