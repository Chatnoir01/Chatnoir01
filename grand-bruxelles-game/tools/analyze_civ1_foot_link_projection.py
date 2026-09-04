#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-foot-link-projection-v1"
WINDOW = (78, 79)
AXES = ("x", "y", "z")


def _vec3(value, label: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"invalid {label}")
    out = [float(x) for x in value]
    if not all(math.isfinite(x) for x in out):
        raise ValueError(f"non-finite {label}")
    return out


def _quat(value, label: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError(f"invalid {label}")
    q = [float(x) for x in value]
    if not all(math.isfinite(x) for x in q):
        raise ValueError(f"non-finite {label}")
    n = math.sqrt(sum(x * x for x in q))
    if n <= 1e-12:
        raise ValueError(f"degenerate {label}")
    return [x / n for x in q]


def _sub(a: list[float], b: list[float]) -> list[float]:
    return [a[i] - b[i] for i in range(3)]


def _dot(a: list[float], b: list[float]) -> float:
    return sum(a[i] * b[i] for i in range(3))


def _norm(v: list[float]) -> float:
    return math.sqrt(_dot(v, v))


def _matrix(q: list[float]) -> list[list[float]]:
    x, y, z, w = q
    return [
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ]


def _mul(m: list[list[float]], v: list[float]) -> list[float]:
    return [sum(m[r][c] * v[c] for c in range(3)) for r in range(3)]


def _transpose(m: list[list[float]]) -> list[list[float]]:
    return [[m[c][r] for c in range(3)] for r in range(3)]


def _bone(sample: dict, bone: str, side: str) -> dict:
    try:
        return sample["bones"][bone][side]
    except (KeyError, TypeError) as exc:
        raise ValueError(f"missing {bone} {side}") from exc


def _state(sample: dict, prefix: str, side: str) -> dict:
    parent = _bone(sample, prefix + "LowerLeg", side)
    child = _bone(sample, prefix + "Foot", side)
    parent_origin = _vec3(parent.get("model_origin"), f"{prefix}LowerLeg {side} origin")
    child_origin = _vec3(child.get("model_origin"), f"{prefix}Foot {side} origin")
    q = _quat(parent.get("model_rotation_xyzw"), f"{prefix}LowerLeg {side} rotation")
    r = _matrix(q)
    link_world = _sub(child_origin, parent_origin)
    rest_local = _mul(_transpose(r), link_world)
    reconstructed = _mul(r, rest_local)
    closure = _norm(_sub(reconstructed, link_world))
    if closure > 1e-8:
        raise ValueError(f"kinematic closure drift {prefix} {side}: {closure}")
    return {
        "parent_rotation_xyzw": q,
        "link_world_m": link_world,
        "rest_local_m": rest_local,
        "reconstruction_error_m": closure,
        "link_y_m": link_world[1],
        "matrix_y_row": r[1],
    }


def _mean(a: list[float], b: list[float]) -> list[float]:
    return [(a[i] + b[i]) * 0.5 for i in range(3)]


def _side_projection(before: dict, after: dict) -> dict:
    drift = _norm(_sub(after["rest_local_m"], before["rest_local_m"]))
    if drift > 1e-6:
        raise ValueError(f"rest-local drift across 78->79: {drift}")
    rest = _mean(before["rest_local_m"], after["rest_local_m"])
    component_delta = {}
    for i, axis in enumerate(AXES):
        component_delta[axis] = (after["matrix_y_row"][i] - before["matrix_y_row"][i]) * rest[i]
    projected_delta = sum(component_delta.values())
    direct_delta = after["link_y_m"] - before["link_y_m"]
    closure = projected_delta - direct_delta
    if abs(closure) > 2e-7:
        raise ValueError(f"projection closure drift: {closure}")
    return {
        "rest_local_m": rest,
        "rest_local_drift_m": drift,
        "component_y_delta_m": component_delta,
        "projected_link_y_delta_m": projected_delta,
        "direct_link_y_delta_m": direct_delta,
        "closure_error_m": closure,
    }


def _leg(samples: list[dict], prefix: str) -> dict:
    states: dict[str, dict[int, dict]] = {"source": {}, "target": {}}
    for side in ("source", "target"):
        for index in WINDOW:
            states[side][index] = _state(samples[index], prefix, side)
    source = _side_projection(states["source"][78], states["source"][79])
    target = _side_projection(states["target"][78], states["target"][79])
    components = {axis: target["component_y_delta_m"][axis] - source["component_y_delta_m"][axis] for axis in AXES}
    error_delta = target["direct_link_y_delta_m"] - source["direct_link_y_delta_m"]
    projected_error_delta = sum(components.values())
    closure = projected_error_delta - error_delta
    if abs(closure) > 3e-7:
        raise ValueError(f"target-source projection closure drift {prefix}: {closure}")
    dominant_axis = max(AXES, key=lambda axis: abs(components[axis]))
    return {
        "source": source,
        "target": target,
        "target_minus_source_component_y_delta_m": components,
        "foot_link_error_delta_m": error_delta,
        "projected_error_delta_m": projected_error_delta,
        "projection_closure_error_m": closure,
        "dominant_rest_axis": dominant_axis,
        "dominant_rest_axis_delta_m": components[dominant_axis],
    }


def analyze(payload: dict) -> dict:
    if payload.get("rotation_enabled") is not True:
        raise ValueError("rotation-enabled probe required")
    if payload.get("position_enabled") is not False or payload.get("scale_enabled") is not False:
        raise ValueError("position/scale-disabled probe required")
    samples = payload.get("model_space_samples")
    if not isinstance(samples, list) or len(samples) <= 79:
        raise ValueError("insufficient model_space_samples")
    for index in WINDOW:
        if samples[index].get("sample_index") != index:
            raise ValueError("sample index drift")
    right = _leg(samples, "Right")
    left = _leg(samples, "Left")
    if not (right["foot_link_error_delta_m"] < 0.0):
        raise ValueError("expected negative RightFoot link transition at 78->79")
    return {
        "schema": SCHEMA,
        "diagnostic_only": True,
        "window": list(WINDOW),
        "right_foot_link": right,
        "left_foot_link_control": left,
        "causal_parent": "LowerLeg model rotation",
        "child_foot_rotation_controls_origin": False,
        "runtime_authorized": False,
        "grounding_verified": False,
        "foot_slide_verified": False,
        "visual_approval_claimed": False,
        "verdict": "DIAGNOSTIC_FOOT_LINK_PARENT_ROTATION_PROJECTION_ISOLATED",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("native_json")
    parser.add_argument("output_json")
    args = parser.parse_args()
    result = analyze(json.loads(Path(args.native_json).read_text()))
    Path(args.output_json).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    right = result["right_foot_link"]
    parts = right["target_minus_source_component_y_delta_m"]
    print(
        "CIV1_FOOT_LINK_PROJECTION_OK "
        f"delta_mm={right['foot_link_error_delta_m'] * 1000:.3f} "
        f"x_mm={parts['x'] * 1000:.3f} y_mm={parts['y'] * 1000:.3f} z_mm={parts['z'] * 1000:.3f} "
        f"dominant={right['dominant_rest_axis']}"
    )


if __name__ == "__main__":
    main()
