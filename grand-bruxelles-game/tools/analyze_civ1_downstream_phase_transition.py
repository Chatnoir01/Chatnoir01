#!/usr/bin/env python3
"""Attribute the CIV-1 native leg downstream sign transition.

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
TERM_KEYS = ("lowerleg_relative_m", "foot_relative_m", "downstream_sum_m")
EPSILON_M = 1e-9


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


def _sign(value: float) -> int:
    if value > EPSILON_M:
        return 1
    if value < -EPSILON_M:
        return -1
    return 0


def _first_zero_cross(rows: list[dict[str, Any]], key: str) -> dict[str, Any] | None:
    previous = rows[0]
    previous_value = float(previous[key])
    if _sign(previous_value) == 0:
        return {
            "index": previous["index"],
            "kind": "exact_zero",
            "previous_index": None,
            "previous_value_m": None,
            "value_m": previous_value,
            "interpolated_index": float(previous["index"]),
        }
    for row in rows[1:]:
        value = float(row[key])
        prev_value = float(previous[key])
        value_sign = _sign(value)
        prev_sign = _sign(prev_value)
        if value_sign == 0:
            return {
                "index": row["index"],
                "kind": "exact_zero",
                "previous_index": previous["index"],
                "previous_value_m": prev_value,
                "value_m": value,
                "interpolated_index": float(row["index"]),
            }
        if prev_sign != value_sign:
            fraction = abs(prev_value) / (abs(prev_value) + abs(value))
            return {
                "index": row["index"],
                "kind": "sign_cross",
                "previous_index": previous["index"],
                "previous_value_m": prev_value,
                "value_m": value,
                "interpolated_index": float(previous["index"]) + fraction,
            }
        previous = row
    return None


def _largest_step(rows: list[dict[str, Any]], key: str) -> dict[str, Any]:
    best: dict[str, Any] | None = None
    for previous, row in zip(rows, rows[1:]):
        delta = float(row[key]) - float(previous[key])
        candidate = {
            "index": row["index"],
            "previous_index": previous["index"],
            "previous_value_m": float(previous[key]),
            "value_m": float(row[key]),
            "delta_m": delta,
            "abs_delta_m": abs(delta),
        }
        if best is None or candidate["abs_delta_m"] > best["abs_delta_m"]:
            best = candidate
    if best is None:
        raise ValueError(f"cannot measure step for {key}: fewer than two rows")
    return best


def _cross_driver(rows: list[dict[str, Any]], crossing: dict[str, Any] | None) -> dict[str, Any] | None:
    if crossing is None or crossing["previous_index"] is None:
        return None
    by_index = {int(row["index"]): row for row in rows}
    previous = by_index[int(crossing["previous_index"])]
    current = by_index[int(crossing["index"])]
    lower_delta = float(current["lowerleg_relative_m"]) - float(previous["lowerleg_relative_m"])
    foot_delta = float(current["foot_relative_m"]) - float(previous["foot_relative_m"])
    if math.isclose(abs(lower_delta), abs(foot_delta), abs_tol=EPSILON_M):
        driver = "tie"
    elif abs(lower_delta) > abs(foot_delta):
        driver = "lowerleg_relative"
    else:
        driver = "foot_relative"
    return {
        "interval": [int(previous["index"]), int(current["index"])],
        "lowerleg_delta_m": lower_delta,
        "foot_delta_m": foot_delta,
        "downstream_delta_m": lower_delta + foot_delta,
        "largest_absolute_delta_term": driver,
    }


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

        crossings = {key: _first_zero_cross(rows, key) for key in TERM_KEYS}
        largest_steps = {key: _largest_step(rows, key) for key in TERM_KEYS}
        downstream_crossing = crossings["downstream_sum_m"]
        result_sides[prefix.lower()] = {
            "transition_window": [START_INDEX, END_INDEX],
            "first_zero_cross_by_term": crossings,
            # Kept for consumers of v1 output while the richer term attribution is adopted.
            "first_downstream_zero_cross": downstream_crossing,
            "largest_step_by_term": largest_steps,
            "downstream_cross_driver": _cross_driver(rows, downstream_crossing),
            "largest_lowerleg_step_index": largest_steps["lowerleg_relative_m"]["index"],
            "largest_foot_step_index": largest_steps["foot_relative_m"]["index"],
            "rows": rows,
        }

    right = result_sides["right"]
    left = result_sides["left"]
    return {
        "format": "grand-bruxelles-civ1-downstream-phase-transition-v2",
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
    right = result["right"]
    print(json.dumps({
        "right_first_cross_index": result["right_first_cross_index"],
        "left_first_cross_index": result["left_first_cross_index"],
        "right_lowerleg_first_cross": right["first_zero_cross_by_term"]["lowerleg_relative_m"],
        "right_foot_first_cross": right["first_zero_cross_by_term"]["foot_relative_m"],
        "right_downstream_cross_driver": right["downstream_cross_driver"],
        "right_largest_lowerleg_step": right["largest_step_by_term"]["lowerleg_relative_m"],
        "right_largest_foot_step": right["largest_step_by_term"]["foot_relative_m"],
    }, sort_keys=True))
    print("CIV1_DOWNSTREAM_PHASE_TRANSITION_OK")


if __name__ == "__main__":
    main()
