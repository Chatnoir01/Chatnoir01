#!/usr/bin/env python3
"""Fail-closed CIV-1 contact-candidate classifier.

Low foot height is only a geometric candidate. This diagnostic adds a cyclic,
hysteretic vertical-stability classifier so transient low sweeps are not
mislabelled as support. It never claims ground contact or authorizes runtime.
"""
from __future__ import annotations
import json, math, statistics, sys
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-civ1-contact-windows-v2"
BUNDLE_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
FOOT_SEMANTICS = ("RightFoot", "LeftFoot")
LOW_BAND_FRACTION = 0.10
MIN_CANDIDATE_WINDOW_SAMPLES = 3
HYSTERESIS_EXIT_MULTIPLIER = 2.0


def _point(frame: dict[str, Any], semantic: str) -> tuple[float, float, float]:
    try:
        origin = frame["poses"][semantic]["origin"]
        if len(origin) != 3:
            raise ValueError
        values = tuple(float(v) for v in origin)
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"missing/invalid {semantic} origin") from exc
    if not all(math.isfinite(v) for v in values):
        raise ValueError(f"non-finite {semantic} origin")
    return values


def _horizontal_distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.hypot(b[0] - a[0], b[2] - a[2])


def _raw_windows(indices: list[int]) -> list[list[int]]:
    if not indices:
        return []
    windows = [[indices[0]]]
    for index in indices[1:]:
        if index == windows[-1][-1] + 1:
            windows[-1].append(index)
        else:
            windows.append([index])
    return windows


def _merge_cyclic_edge_windows(windows: list[list[int]], frame_count: int) -> list[list[int]]:
    if len(windows) >= 2 and windows[0][0] == 0 and windows[-1][-1] == frame_count - 1:
        return [windows[-1] + windows[0], *windows[1:-1]]
    return windows


def _vertical_velocity(ys: list[float], index: int) -> float:
    count = len(ys)
    return (ys[(index + 1) % count] - ys[(index - 1) % count]) / 2.0


def _stable_mask(ys: list[float], low_mask: list[bool]) -> tuple[list[bool], float, float]:
    speeds = [abs(_vertical_velocity(ys, i)) for i, is_low in enumerate(low_mask) if is_low]
    if not speeds:
        return [False] * len(ys), 0.0, 0.0
    enter = float(statistics.median(speeds))
    exit_threshold = enter * HYSTERESIS_EXIT_MULTIPLIER
    state = bool(low_mask[-1] and abs(_vertical_velocity(ys, len(ys) - 1)) <= enter)
    output = [False] * len(ys)
    for _ in range(2):
        for index in range(len(ys)):
            speed = abs(_vertical_velocity(ys, index))
            if state:
                if (not low_mask[index]) or speed > exit_threshold:
                    state = False
            elif low_mask[index] and speed <= enter:
                state = True
            output[index] = state
    return output, enter, exit_threshold


def analyze_foot(frames: list[dict[str, Any]], semantic: str) -> dict[str, Any]:
    points = [_point(frame, semantic) for frame in frames]
    ys = [point[1] for point in points]
    low = min(ys)
    high = max(ys)
    band_threshold = low + (high - low) * LOW_BAND_FRACTION
    low_mask = [point[1] <= band_threshold for point in points]
    stable_mask, enter, exit_threshold = _stable_mask(ys, low_mask)
    low_indices = [i for i, value in enumerate(low_mask) if value]
    stable_indices = [i for i, value in enumerate(stable_mask) if value]
    low_windows = _merge_cyclic_edge_windows(_raw_windows(low_indices), len(frames))
    stable_windows = _merge_cyclic_edge_windows(_raw_windows(stable_indices), len(frames))

    def measure(indices: list[int]) -> dict[str, Any]:
        path = 0.0
        max_step = 0.0
        max_from = None
        max_to = None
        for previous_index, current_index in zip(indices, indices[1:]):
            step = _horizontal_distance(points[previous_index], points[current_index])
            path += step
            if step > max_step:
                max_step, max_from, max_to = step, previous_index, current_index
        net = _horizontal_distance(points[indices[0]], points[indices[-1]]) if len(indices) > 1 else 0.0
        return {
            "start_sample": indices[0], "end_sample": indices[-1], "wraps_cycle": indices[0] > indices[-1],
            "sample_count": len(indices), "eligible_vertical_stability_window": len(indices) >= MIN_CANDIDATE_WINDOW_SAMPLES,
            "horizontal_path_m": path, "net_horizontal_displacement_m": net,
            "max_horizontal_step_m": max_step, "max_horizontal_step_from_sample": max_from,
            "max_horizontal_step_to_sample": max_to, "sample_indices": indices,
        }

    measured = [measure(window) for window in stable_windows]
    eligible = [window for window in measured if window["eligible_vertical_stability_window"]]
    return {
        "semantic": semantic, "min_y_m": low, "max_y_m": high, "low_band_fraction": LOW_BAND_FRACTION,
        "band_threshold_y_m": band_threshold, "low_sample_count": len(low_indices), "low_window_count": len(low_windows),
        "vertical_velocity_metric": "cyclic_central_difference_m_per_sample",
        "vertical_stability_enter_m_per_sample": enter, "vertical_stability_exit_m_per_sample": exit_threshold,
        "hysteresis_exit_multiplier": HYSTERESIS_EXIT_MULTIPLIER, "vertical_stable_sample_count": len(stable_indices),
        "vertical_stability_window_count": len(measured),
        "eligible_vertical_stability_window_count": len(eligible),
        "max_eligible_horizontal_path_m": max((window["horizontal_path_m"] for window in eligible), default=0.0),
        "windows": measured,
    }


def analyze_bundle(bundle: dict[str, Any]) -> dict[str, Any]:
    if bundle.get("schema") != BUNDLE_SCHEMA:
        raise ValueError("unexpected bundle schema")
    if bundle.get("runtime_authorized", True) or bundle.get("visual_approval_claimed", True) or bundle.get("player_view_claimed", True):
        raise ValueError("production rail violated")
    frames = bundle.get("frames")
    if not isinstance(frames, list) or len(frames) != 120:
        raise ValueError("expected exactly 120 frames")
    return {
        "schema": SCHEMA, "diagnostic_only": True, "ground_contact_claimed": False,
        "runtime_authorized": False, "visual_approval_claimed": False, "player_view_claimed": False,
        "frame_count": 120, "minimum_vertical_stability_window_samples": MIN_CANDIDATE_WINDOW_SAMPLES,
        "feet": {semantic: analyze_foot(frames, semantic) for semantic in FOOT_SEMANTICS},
        "verdict": "AMELIORER_VERTICAL_STABILITY_CLASSIFIED_GROUND_CONTACT_UNPROVEN",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_contact_windows.py INPUT_BUNDLE OUTPUT_JSON", file=sys.stderr)
        return 2
    try:
        result = analyze_bundle(json.loads(Path(argv[1]).read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"CIV1_CONTACT_WINDOWS_FAIL: {exc}", file=sys.stderr)
        return 3
    Path(argv[2]).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    right = result["feet"]["RightFoot"]
    left = result["feet"]["LeftFoot"]
    print(f"CIV1_CONTACT_WINDOWS_OK right_stable={right['eligible_vertical_stability_window_count']} left_stable={left['eligible_vertical_stability_window_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
