#!/usr/bin/env python3
"""Fail-closed contiguous 3-sample search over a RightFoot local-sole receipt.

The minimum eligible contact interval is frozen at three samples. This analyzer
checks every contiguous 3-sample subwindow of [68,69,70,71] against the same
15% cross-distance and 15% within-distance bone-local sole rails. It does not
relax or re-fit the source-derived contact context.
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

DISTANCES = (2, 4, 8)
SAMPLES = (68, 69, 70, 71)
MIN_ELIGIBLE_SAMPLES = 3
MAX_DISTANCE_MEAN_REL_SPREAD = 0.15
MAX_WITHIN_DISTANCE_REL_DEVIATION = 0.15


def _relative(a: float, b: float) -> float:
    return abs(a - b) / max(abs(b), 1e-12)


def _assess(samples: list[int], series: dict[int, list[float]]) -> dict:
    means = {d: statistics.mean(series[d]) for d in DISTANCES}
    medians = {d: statistics.median(series[d]) for d in DISTANCES}
    signs = {1 if means[d] > 0 else -1 if means[d] < 0 else 0 for d in DISTANCES}
    single_side = signs in ({1}, {-1})
    center = statistics.median(means.values())
    spread = (max(means.values()) - min(means.values())) / max(abs(center), 1e-12)
    within = {d: max(_relative(v, medians[d]) for v in series[d]) for d in DISTANCES}
    passed = single_side and spread <= MAX_DISTANCE_MEAN_REL_SPREAD and all(v <= MAX_WITHIN_DISTANCE_REL_DEVIATION for v in within.values())
    return {
        "samples": samples,
        "single_side_consistent": single_side,
        "distance_mean_relative_spread": spread,
        "max_within_distance_relative_deviation": within,
        "passed": passed,
    }


def analyze(receipt: dict) -> dict:
    if receipt.get("schema") != "grand-bruxelles-civ1-rightfoot-contact-local-sole-v1":
        raise ValueError("receipt schema")
    if receipt.get("samples") != list(SAMPLES) or receipt.get("distances_m") != list(DISTANCES):
        raise ValueError("sample/distance contract")
    if float(receipt.get("max_distance_mean_relative_spread", -1)) != MAX_DISTANCE_MEAN_REL_SPREAD:
        raise ValueError("distance spread rail drift")
    if receipt.get("bone_local_sole_identity_preserved_2_4_8m") is not False:
        raise ValueError("expected rejected four-sample source context")
    for key in ("contact_phase_ready", "quantitative_foot_slide_candidate", "planted_contact_claimed", "animation_correction_authorized", "runtime_authorized", "visual_approval_claimed", "player_view_claimed"):
        if receipt.get(key) is not False:
            raise ValueError("upstream promotion claim " + key)

    by_distance: dict[int, dict[int, float]] = {}
    measurements = receipt.get("measurements", [])
    if [int(m.get("distance_m", -1)) for m in measurements] != list(DISTANCES):
        raise ValueError("measurement matrix")
    for measurement in measurements:
        d = int(measurement["distance_m"])
        records = measurement.get("records", [])
        if [int(r.get("sample_index", -1)) for r in records] != list(SAMPLES):
            raise ValueError("record matrix")
        by_distance[d] = {int(r["sample_index"]): float(r["normalized_offset_x"]) for r in records}

    windows = []
    for start in range(0, len(SAMPLES) - MIN_ELIGIBLE_SAMPLES + 1):
        sample_window = list(SAMPLES[start:start + MIN_ELIGIBLE_SAMPLES])
        series = {d: [by_distance[d][s] for s in sample_window] for d in DISTANCES}
        windows.append(_assess(sample_window, series))
    eligible = [w["samples"] for w in windows if w["passed"]]
    return {
        "schema": "grand-bruxelles-civ1-rightfoot-contact-subwindows-v1",
        "diagnostic_only": True,
        "source_samples": list(SAMPLES),
        "minimum_eligible_samples": MIN_ELIGIBLE_SAMPLES,
        "max_distance_mean_relative_spread": MAX_DISTANCE_MEAN_REL_SPREAD,
        "max_within_distance_relative_deviation": MAX_WITHIN_DISTANCE_REL_DEVIATION,
        "windows": windows,
        "eligible_windows": eligible,
        "rightfoot_contact_phase_ready": bool(eligible),
        "quantitative_foot_slide_candidate": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_RIGHTFOOT_THREE_SAMPLE_CONTACT_WINDOW_FOUND_REQUIRES_MORE_EVIDENCE" if eligible else "JETER_RIGHTFOOT_NO_STABLE_THREE_SAMPLE_CONTACT_SUBWINDOW",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_rightfoot_contact_subwindows.py LOCAL_SOLE.json OUT.json", file=sys.stderr)
        return 2
    try:
        receipt = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        out = analyze(receipt)
        Path(argv[2]).write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_RIGHTFOOT_CONTACT_SUBWINDOW_FAIL: {exc}", file=sys.stderr)
        return 3
    print("CIV1_RIGHTFOOT_CONTACT_SUBWINDOW_CLASSIFIED", out["eligible_windows"], out["verdict"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
