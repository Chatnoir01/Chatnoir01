#!/usr/bin/env python3
import argparse
import copy
import math
from pathlib import Path

from validate_bourse_8512036_masked_native_receipt import (
    SPAWN_SOURCE_GEOMETRY_EPSILON_M,
    expected_source_road,
    recomputed_axis_alignment,
    segment_projection,
    strict_json_loads,
)
from validate_bourse_8512036_masked_native_receipt_source_bound import verify_bound

DRIFT_M = 0.01


def metric_midpoint_error_m(receipt, source_doc):
    road = expected_source_road(source_doc)
    segment_index = receipt["segment_index"]
    start = road["points"][segment_index]
    finish = road["points"][segment_index + 1]
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    segment_length_m = math.hypot(vx, vy)
    assert segment_length_m > 0.0
    projection_t, _, _ = segment_projection(receipt["spawn_xz"], start, finish)
    return abs(projection_t - 0.5) * segment_length_m


def verify_metric_bound(receipt, source_raw, expected_source_sha):
    verify_bound(receipt, source_raw, expected_source_sha)
    source_doc = strict_json_loads(source_raw.decode("utf-8", errors="strict"))
    midpoint_error_m = metric_midpoint_error_m(receipt, source_doc)
    assert midpoint_error_m <= SPAWN_SOURCE_GEOMETRY_EPSILON_M, (
        "spawn midpoint longitudinal drift exceeds metric epsilon: "
        f"error_m={midpoint_error_m:.9f} epsilon_m={SPAWN_SOURCE_GEOMETRY_EPSILON_M:.9f}"
    )
    return midpoint_error_m


def shifted_receipt(receipt, source_doc):
    bad = copy.deepcopy(receipt)
    road = expected_source_road(source_doc)
    segment_index = bad["segment_index"]
    start = road["points"][segment_index]
    finish = road["points"][segment_index + 1]
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    length = math.hypot(vx, vy)
    assert length > 0.0
    ux = vx / length
    uy = vy / length
    bad["spawn_xz"] = [bad["spawn_xz"][0] + ux * DRIFT_M, bad["spawn_xz"][1] + uy * DRIFT_M]
    bad["axis_alignment"] = recomputed_axis_alignment(bad["spawn_xz"], bad["target_xz"], start, finish)
    return bad


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--source-sha", required=True)
    args = parser.parse_args()

    receipt = strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    source_raw = Path(args.source).read_bytes()
    source_doc = strict_json_loads(source_raw.decode("utf-8", errors="strict"))

    measured_error_m = verify_metric_bound(receipt, source_raw, args.source_sha)

    bad = shifted_receipt(receipt, source_doc)
    try:
        verify_metric_bound(bad, source_raw, args.source_sha)
    except AssertionError as exc:
        assert "spawn midpoint longitudinal drift exceeds metric epsilon:" in str(exc), (
            f"10 mm drift rejected for an unrelated reason: {exc}"
        )
    else:
        raise AssertionError("10 mm longitudinal spawn drift accepted under 1 mm metric boundary")

    print(
        "BOURSE_8512036_SPAWN_METRIC_BOUNDARY_GREEN "
        f"midpoint_error_m={measured_error_m:.9f} epsilon_m={SPAWN_SOURCE_GEOMETRY_EPSILON_M:.9f} "
        "ten_mm_drift_rejected=true"
    )


if __name__ == "__main__":
    main()
