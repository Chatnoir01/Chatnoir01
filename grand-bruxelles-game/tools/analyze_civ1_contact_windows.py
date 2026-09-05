#!/usr/bin/env python3
"""Fail-closed diagnostic for contiguous CIV-1 low-foot contact windows.

This does not authorize runtime or claim grounding. It decomposes the existing
10%-low support band into contiguous, cyclic-aware windows so separated stance
phases are never summed into one misleading foot-slide number.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-civ1-contact-windows-v1"
BUNDLE_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
FOOT_SEMANTICS = ("RightFoot", "LeftFoot")
LOW_BAND_FRACTION = 0.10
MIN_WINDOW_SAMPLES = 3


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


def _raw_windows(low_indices: list[int]) -> list[list[int]]:
    if not low_indices:
        return []
    windows: list[list[int]] = [[low_indices[0]]]
    for index in low_indices[1:]:
        if index == windows[-1][-1] + 1:
            windows[-1].append(index)
        else:
            windows.append([index])
    return windows


def _merge_cyclic_edge_windows(windows: list[list[int]], frame_count: int) -> list[list[int]]:
    if len(windows) < 2:
        return windows
    if windows[0][0] != 0 or windows[-1][-1] != frame_count - 1:
        return windows
    merged = windows[-1] + windows[0]
    return [merged, *windows[1:-1]]


def analyze_foot(frames: list[dict[str, Any]], semantic: str) -> dict[str, Any]:
    points = [_point(frame, semantic) for frame in frames]
    ys = [point[1] for point in points]
    low = min(ys)
    high = max(ys)
    threshold = low + (high - low) * LOW_BAND_FRACTION
    low_indices = [index for index, point in enumerate(points) if point[1] <= threshold]
    windows = _merge_cyclic_edge_windows(_raw_windows(low_indices), len(frames))

    measured: list[dict[str, Any]] = []
    for indices in windows:
        path = 0.0
        max_step = 0.0
        for previous_index, current_index in zip(indices, indices[1:]):
            step = _horizontal_distance(points[previous_index], points[current_index])
            path += step
            max_step = max(max_step, step)
        net = _horizontal_distance(points[indices[0]], points[indices[-1]]) if len(indices) > 1 else 0.0
        measured.append(
            {
                "start_sample": indices[0],
                "end_sample": indices[-1],
                "wraps_cycle": indices[0] > indices[-1],
                "sample_count": len(indices),
                "eligible_planted_window": len(indices) >= MIN_WINDOW_SAMPLES,
                "horizontal_path_m": path,
                "net_horizontal_displacement_m": net,
                "max_horizontal_step_m": max_step,
                "sample_indices": indices,
            }
        )

    eligible = [window for window in measured if window["eligible_planted_window"]]
    return {
        "semantic": semantic,
        "min_y_m": low,
        "max_y_m": high,
        "low_band_fraction": LOW_BAND_FRACTION,
        "band_threshold_y_m": threshold,
        "low_sample_count": len(low_indices),
        "window_count": len(measured),
        "eligible_window_count": len(eligible),
        "max_eligible_window_horizontal_path_m": max((w["horizontal_path_m"] for w in eligible), default=0.0),
        "max_eligible_window_horizontal_step_m": max((w["max_horizontal_step_m"] for w in eligible), default=0.0),
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
        "schema": SCHEMA,
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "frame_count": len(frames),
        "minimum_planted_window_samples": MIN_WINDOW_SAMPLES,
        "feet": {semantic: analyze_foot(frames, semantic) for semantic in FOOT_SEMANTICS},
        "verdict": "AMELIORER_CONTACT_WINDOWS_REQUIRE_GROUNDING_REVIEW",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_contact_windows.py INPUT_BUNDLE OUTPUT_JSON", file=sys.stderr)
        return 2
    source = Path(argv[1])
    target = Path(argv[2])
    try:
        bundle = json.loads(source.read_text(encoding="utf-8"))
        result = analyze_bundle(bundle)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"CIV1_CONTACT_WINDOWS_FAIL: {exc}", file=sys.stderr)
        return 3
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    right = result["feet"]["RightFoot"]
    left = result["feet"]["LeftFoot"]
    print(
        "CIV1_CONTACT_WINDOWS_OK "
        f"right_windows={right['eligible_window_count']} right_max_path={right['max_eligible_window_horizontal_path_m']:.9f} "
        f"left_windows={left['eligible_window_count']} left_max_path={left['max_eligible_window_horizontal_path_m']:.9f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
