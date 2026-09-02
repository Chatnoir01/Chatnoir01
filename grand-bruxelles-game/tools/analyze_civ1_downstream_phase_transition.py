#!/usr/bin/env python3
"""Attribute the CIV-1 native right-leg downstream sign transition.

Consumes the JSON emitted by godot_civ1_global_chain_diagnostic.gd. This is a
QA-only analysis: it never edits source assets, retarget settings, thresholds,
or runtime/JOUABLE state.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

START_INDEX = 58
END_INDEX = 88
SIDES = ("Left", "Right")


def _y(samples: list[dict[str, Any]], i: int, bone: str, side: str) -> float:
    key = "source_hips_relative_origin" if side == "source" else "target_hips_relative_origin"
    value = float(samples[i]["bones"][bone][side][key][1])
    if not math.isfinite(value):
        raise ValueError(f"non-finite Y for {bone}/{side} at {i}")
    return value


def _terms(samples: list[dict[str, Any]], i: int, prefix: str) -> dict[str, float]:
    upper = _y(samples, i, prefix + "UpperLeg", "target") - _y(samples, i, prefix + "UpperLeg", "source")
    lower = (
        (_y(samples, i, prefix + "LowerLeg", "target") - _y(samples, i, prefix + "UpperLeg", "target"))
        - (_y(samples, i, prefix + "LowerLeg", "source") - _y(samples, i, prefix + "UpperLeg", "source"))
    )
    foot = (
        (_y(samples, i, prefix + "Foot", "target") - _y(samples, i, prefix + "LowerLeg", "target"))
        - (_y(samples, i, prefix + "Foot", "source") - _y(samples, i, prefix + "LowerLeg", "source"))
    )
    downstream = lower + foot
    final = _y(samples, i, prefix + "Foot", "target") - _y(samples, i, prefix + "Foot", "source")
    closure = final - (upper + downstream)
    return {
        "upperleg_hips_relative_m": upper,
        "lowerleg_relative_m": lower,
        "foot_relative_m": foot,
        "downstream_sum_m": downstream,
        "final_foot_hips_relative_m": final,
        "closure_error_m": closure,
    }


def _first_zero_cross(rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    previous = rows[0]
    if previous["downstream_sum_m"] == 0.0:
        return {"index": previous["index"], "kind": "exact_zero", "previous_index": None}
    for row in rows[1:]:
        value = row["downstream_sum_m"]
        prev_value = previous["downstream_sum_m"]
        if value == 0.0:
            return {"index": row["index"], "kind": "exact_zero", "previous_index": previous["index"]}
        if (prev_value < 0.0 < value) or (prev_value > 0.0 > value):
            return {
                "index": row["index"],
                "kind": "sign_cross",
                "previous_index": previous["index"],
                "previous_downstream_sum_m": prev_value,
                "downstream_sum_m": value,
            }
        previous = row
    return None


def analyze(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("format") != "grand-bruxelles-civ1-global-chain-diagnostic-v3":
        raise ValueError("unexpected global-chain payload format")
    if int(payload.get("sample_count", 0)) != 121:
        raise ValueError("expected exact 121-sample native probe")
    if payload.get("retarget_modifier") != "RetargetModifier3D":
        raise ValueError("expected native RetargetModifier3D")
    if payload.get("position_enabled") is not False or payload.get("rotation_enabled") is not True or payload.get("scale_enabled") is not False:
        raise ValueError("retarget channel contract changed")

    samples = payload["model_space_samples"]
    if len(samples) != 121:
        raise ValueError("model_space_samples length mismatch")

    result_sides: dict[str, Any] = {}
    for prefix in SIDES:
        rows = []
        for i in range(START_INDEX, END_INDEX + 1):
            row = {"index": i, **_terms(samples, i, prefix)}
            if abs(row["closure_error_m"]) >= 1e-5:
                raise ValueError(f"algebraic closure failed for {prefix} at {i}: {row['closure_error_m']}")
            rows.append(row)
        crossing = _first_zero_cross(rows)
        max_lower_step = max(
            rows[1:], key=lambda r: abs(r["lowerleg_relative_m"] - rows[r["index"] - START_INDEX - 1]["lowerleg_relative_m"])
        )
        max_foot_step = max(
            rows[1:], key=lambda r: abs(r["foot_relative_m"] - rows[r["index"] - START_INDEX - 1]["foot_relative_m"])
        )
        result_sides[prefix.lower()] = {
            "transition_window": [START_INDEX, END_INDEX],
            "first_downstream_zero_cross": crossing,
            "largest_lowerleg_step_index": max_lower_step["index"],
            "largest_foot_step_index": max_foot_step["index"],
            "rows": rows,
        }

    right = result_sides["right"]
    left = result_sides["left"]
    return {
        "format": "grand-bruxelles-civ1-downstream-phase-transition-v1",
        "source_format": payload["format"],
        "transition_window": [START_INDEX, END_INDEX],
        "right": right,
        "left_control": left,
        "right_first_cross_index": None if right["first_downstream_zero_cross"] is None else right["first_downstream_zero_cross"]["index"],
        "left_first_cross_index": None if left["first_downstream_zero_cross"] is None else left["first_downstream_zero_cross"]["index"],
        "threshold_was_modified": False,
        "diagnostic_only": True,
        "world_ground_assumed": False,
        "grounding_verified": False,
        "foot_slide_verified": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_json", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()
    payload = json.loads(args.input_json.read_text(encoding="utf-8"))
    result = analyze(payload)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "right_first_cross_index": result["right_first_cross_index"],
        "left_first_cross_index": result["left_first_cross_index"],
        "right_largest_lowerleg_step_index": result["right"]["largest_lowerleg_step_index"],
        "right_largest_foot_step_index": result["right"]["largest_foot_step_index"],
    }, sort_keys=True))
    print("CIV1_DOWNSTREAM_PHASE_TRANSITION_OK")


if __name__ == "__main__":
    main()
