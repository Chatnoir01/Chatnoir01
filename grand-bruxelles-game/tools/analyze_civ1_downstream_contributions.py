#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-downstream-contribution-v1"
REQUIRED_WINDOW = (78, 79)


def _vec(sample: dict, bone: str, side: str, key: str) -> list[float]:
    value = sample["bones"][bone][side][key]
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"invalid {bone} {side} {key}")
    out = [float(x) for x in value]
    if not all(math.isfinite(x) for x in out):
        raise ValueError("non-finite diagnostic vector")
    return out


def _y(sample: dict, bone: str, side: str, key: str) -> float:
    return _vec(sample, bone, side, key)[1]


def _origin_key(side: str) -> str:
    return f"{side}_hips_relative_origin"


def _link_contribution(sample: dict, parent: str, child: str) -> dict[str, float]:
    def side_terms(side: str) -> tuple[float, float]:
        origin_key = _origin_key(side)
        parent_origin = _y(sample, parent, side, origin_key)
        child_origin = _y(sample, child, side, origin_key)
        parent_motion = _y(sample, parent, side, f"{side}_motion_from_rest")
        child_motion = _y(sample, child, side, f"{side}_motion_from_rest")
        static_relative = (child_origin - child_motion) - (parent_origin - parent_motion)
        motion_relative = child_motion - parent_motion
        return static_relative, motion_relative

    source_static, source_motion = side_terms("source")
    target_static, target_motion = side_terms("target")
    static_error = target_static - source_static
    rotation_error = target_motion - source_motion
    total_error = static_error + rotation_error
    direct_error = (
        (_y(sample, child, "target", _origin_key("target")) - _y(sample, parent, "target", _origin_key("target")))
        - (_y(sample, child, "source", _origin_key("source")) - _y(sample, parent, "source", _origin_key("source")))
    )
    closure = total_error - direct_error
    if abs(closure) > 1e-9:
        raise ValueError(f"contribution closure drift for {child}: {closure}")
    return {
        "static_rest_error_m": static_error,
        "rotation_driven_error_m": rotation_error,
        "total_relative_error_m": direct_error,
        "closure_error_m": closure,
    }


def _sample_terms(sample: dict, prefix: str) -> dict:
    upper = prefix + "UpperLeg"
    lower = prefix + "LowerLeg"
    foot = prefix + "Foot"
    lower_terms = _link_contribution(sample, upper, lower)
    foot_terms = _link_contribution(sample, lower, foot)
    return {
        "lowerleg": lower_terms,
        "foot": foot_terms,
        "downstream": {
            "static_rest_error_m": lower_terms["static_rest_error_m"] + foot_terms["static_rest_error_m"],
            "rotation_driven_error_m": lower_terms["rotation_driven_error_m"] + foot_terms["rotation_driven_error_m"],
            "total_relative_error_m": lower_terms["total_relative_error_m"] + foot_terms["total_relative_error_m"],
        },
    }


def _delta(a: dict, b: dict, section: str, term: str) -> float:
    return b[section][term] - a[section][term]


def analyze(payload: dict, start: int = 78, end: int = 79) -> dict:
    if (start, end) != REQUIRED_WINDOW:
        raise ValueError("unsupported transition window")
    if payload.get("rotation_enabled") is not True:
        raise ValueError("rotation-enabled probe required")
    if payload.get("position_enabled") is not False or payload.get("scale_enabled") is not False:
        raise ValueError("position/scale-disabled probe required")
    samples = payload.get("model_space_samples")
    if not isinstance(samples, list) or len(samples) <= end:
        raise ValueError("insufficient model_space_samples")

    rows = []
    for sample_index in range(start, end + 1):
        sample = samples[sample_index]
        if sample.get("sample_index") != sample_index:
            raise ValueError("sample index drift")
        right = _sample_terms(sample, "Right")
        left = _sample_terms(sample, "Left")
        rows.append({"sample_index": sample_index, "time_s": float(sample["time_s"]), "right": right, "left": left})

    before, after = rows
    before_total = before["right"]["downstream"]["total_relative_error_m"]
    after_total = after["right"]["downstream"]["total_relative_error_m"]
    if not (before_total > 0.0 and after_total < 0.0):
        raise ValueError("expected right downstream + to - crossing at 78->79")

    contributions = {}
    for section in ("lowerleg", "foot", "downstream"):
        contributions[section] = {
            "static_rest_delta_m": _delta(before["right"], after["right"], section, "static_rest_error_m"),
            "rotation_driven_delta_m": _delta(before["right"], after["right"], section, "rotation_driven_error_m"),
            "total_delta_m": _delta(before["right"], after["right"], section, "total_relative_error_m"),
        }

    ranked = []
    for section in ("lowerleg", "foot"):
        for kind in ("static_rest_delta_m", "rotation_driven_delta_m"):
            ranked.append((abs(contributions[section][kind]), section, kind, contributions[section][kind]))
    ranked.sort(reverse=True)
    _, dominant_link, dominant_kind, dominant_delta = ranked[0]

    return {
        "schema": SCHEMA,
        "diagnostic_only": True,
        "window": [start, end],
        "rows": rows,
        "right_transition_contributions": contributions,
        "dominant_transition_driver": {
            "link": dominant_link,
            "kind": dominant_kind,
            "delta_m": dominant_delta,
        },
        "runtime_authorized": False,
        "grounding_verified": False,
        "foot_slide_verified": False,
        "visual_approval_claimed": False,
        "verdict": "DIAGNOSTIC_RIGHT_DOWNSTREAM_TRANSITION_DECOMPOSED",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("native_json")
    parser.add_argument("output_json")
    args = parser.parse_args()
    payload = json.loads(Path(args.native_json).read_text())
    result = analyze(payload)
    Path(args.output_json).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    driver = result["dominant_transition_driver"]
    downstream = result["right_transition_contributions"]["downstream"]
    print(
        "CIV1_DOWNSTREAM_CONTRIBUTION_OK "
        f"driver={driver['link']}:{driver['kind']} "
        f"driver_delta_mm={driver['delta_m'] * 1000:.3f} "
        f"downstream_rotation_delta_mm={downstream['rotation_driven_delta_m'] * 1000:.3f} "
        f"downstream_static_delta_mm={downstream['static_rest_delta_m'] * 1000:.3f}"
    )


if __name__ == "__main__":
    main()
