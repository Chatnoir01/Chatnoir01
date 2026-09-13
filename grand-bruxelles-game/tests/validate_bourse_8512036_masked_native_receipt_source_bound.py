#!/usr/bin/env python3
import argparse
import copy
import hashlib
import math
from pathlib import Path

from validate_bourse_8512036_deterministic_candidate import (
    deterministic_source_candidate,
    verify as verify_deterministic_candidate,
)
from validate_bourse_8512036_deterministic_target_identity import verify as verify_deterministic_target
from validate_bourse_8512036_masked_native_receipt import (
    SPAWN_SOURCE_GEOMETRY_EPSILON_M,
    display_road_width,
    expected_source_road,
    recomputed_axis_alignment,
    segment_projection,
    strict_json_loads,
    verify,
)


METRIC_RED_DRIFT_M = 0.01


def verify_source_bytes(source_raw, expected_source_sha):
    assert isinstance(source_raw, bytes), "source bytes required"
    assert isinstance(expected_source_sha, str) and len(expected_source_sha) == 64, "expected source SHA-256 malformed"
    try:
        int(expected_source_sha, 16)
    except ValueError as exc:
        raise AssertionError("expected source SHA-256 malformed") from exc
    measured = hashlib.sha256(source_raw).hexdigest()
    assert measured == expected_source_sha.lower(), (
        f"source SHA-256 drift: expected={expected_source_sha.lower()} actual={measured}"
    )
    return measured


def spawn_midpoint_error_m(receipt, source_doc):
    road = expected_source_road(source_doc)
    segment_index = receipt["segment_index"]
    points = road["points"]
    assert type(segment_index) is int and 0 <= segment_index < len(points) - 1
    start = points[segment_index]
    finish = points[segment_index + 1]
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    segment_length_m = math.hypot(vx, vy)
    assert segment_length_m > 0.0
    projection_t, _, _ = segment_projection(receipt["spawn_xz"], start, finish)
    return abs(projection_t - 0.5) * segment_length_m


def verify_spawn_midpoint_metric(receipt, source_doc):
    error_m = spawn_midpoint_error_m(receipt, source_doc)
    assert error_m <= SPAWN_SOURCE_GEOMETRY_EPSILON_M, (
        "spawn midpoint longitudinal drift exceeds metric epsilon: "
        f"error_m={error_m:.9f} epsilon_m={SPAWN_SOURCE_GEOMETRY_EPSILON_M:.9f}"
    )
    return error_m


def verify_bound(receipt, source_raw, expected_source_sha):
    verify_source_bytes(source_raw, expected_source_sha)
    source_doc = strict_json_loads(source_raw.decode("utf-8", errors="strict"))
    verify(receipt, source_doc, expected_source_sha.lower())
    midpoint_error_m = verify_spawn_midpoint_metric(receipt, source_doc)
    verify_deterministic_candidate(receipt, source_doc)
    verify_deterministic_target(receipt, source_raw, expected_source_sha)
    return midpoint_error_m


def metric_boundary_self_test(receipt, source_doc):
    baseline_error_m = verify_spawn_midpoint_metric(receipt, source_doc)
    bad = copy.deepcopy(receipt)
    road = expected_source_road(source_doc)
    segment_index = bad["segment_index"]
    start = road["points"][segment_index]
    finish = road["points"][segment_index + 1]
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    segment_length_m = math.hypot(vx, vy)
    assert segment_length_m > 0.0
    ux = vx / segment_length_m
    uy = vy / segment_length_m
    bad["spawn_xz"] = [
        bad["spawn_xz"][0] + ux * METRIC_RED_DRIFT_M,
        bad["spawn_xz"][1] + uy * METRIC_RED_DRIFT_M,
    ]
    try:
        verify_spawn_midpoint_metric(bad, source_doc)
    except AssertionError as exc:
        assert "spawn midpoint longitudinal drift exceeds metric epsilon:" in str(exc), (
            f"10 mm drift rejected for an unrelated reason: {exc}"
        )
    else:
        raise AssertionError("10 mm longitudinal spawn drift accepted under 1 mm metric boundary")
    return baseline_error_m


def deterministic_candidate_boundary_self_test(receipt, source_raw, expected_source_sha, source_doc):
    candidate = deterministic_source_candidate(source_doc)
    road = expected_source_road(source_doc)
    points = road["points"]
    segment_index = candidate["segment_index"]
    start = points[segment_index]
    finish = points[segment_index + 1]
    mid = [(start[0] + finish[0]) * 0.5, (start[1] + finish[1]) * 0.5]
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    segment_length_m = math.hypot(vx, vy)
    assert segment_length_m > 0.0
    perpendicular = [-vy / segment_length_m, vx / segment_length_m]
    half_road = display_road_width(road) * 0.5
    allowed_offsets = [half_road + delta for delta in (1.10, 2.00, 3.50, 5.00, 7.50)]
    alternatives = sorted(
        (offset for offset in allowed_offsets if abs(offset - candidate["offset_m"]) > SPAWN_SOURCE_GEOMETRY_EPSILON_M),
        key=lambda offset: abs(offset - candidate["offset_m"]),
    )
    assert alternatives, "no alternate legal source offset available for deterministic-candidate regression"

    bad = copy.deepcopy(receipt)
    alternate_offset = alternatives[0]
    bad["spawn_xz"] = [
        mid[0] + perpendicular[0] * candidate["side"] * alternate_offset,
        mid[1] + perpendicular[1] * candidate["side"] * alternate_offset,
    ]
    bad["axis_alignment"] = recomputed_axis_alignment(bad["spawn_xz"], bad["target_xz"], start, finish)

    # Prove this mutation still satisfies the older source/native + metric contract;
    # the only intended rejection is that it is not the deterministic winner.
    verify(bad, source_doc, expected_source_sha.lower())
    verify_spawn_midpoint_metric(bad, source_doc)
    try:
        verify_bound(bad, source_raw, expected_source_sha)
    except AssertionError as exc:
        assert "deterministic spawn drift:" in str(exc), f"alternate legal offset rejected for unrelated reason: {exc}"
    else:
        raise AssertionError("alternate legal source offset accepted without deterministic-candidate binding")


def deterministic_target_boundary_self_test(receipt, source_raw, expected_source_sha, source_doc):
    candidate = deterministic_source_candidate(source_doc)
    road = expected_source_road(source_doc)
    points = road["points"]
    segment_index = candidate["segment_index"]
    start = points[segment_index]
    finish = points[segment_index + 1]
    current_t, _, _ = segment_projection(receipt["target_xz"], start, finish)
    assert 0.0 <= current_t <= 1.0
    alternate_t = current_t + 0.05 if current_t <= 0.95 else current_t - 0.05
    assert 0.0 <= alternate_t <= 1.0 and abs(alternate_t - current_t) > 1e-9

    bad = copy.deepcopy(receipt)
    bad["target_xz"] = [
        start[0] + (finish[0] - start[0]) * alternate_t,
        start[1] + (finish[1] - start[1]) * alternate_t,
    ]
    bad["axis_alignment"] = recomputed_axis_alignment(bad["spawn_xz"], bad["target_xz"], start, finish)

    # Prove the forged target remains valid under the native/source, metric and
    # deterministic-spawn contracts. The source-bound wrapper must additionally
    # bind the exact deterministic target rather than accepting any point on the
    # selected source segment.
    verify(bad, source_doc, expected_source_sha.lower())
    verify_spawn_midpoint_metric(bad, source_doc)
    verify_deterministic_candidate(bad, source_doc)
    try:
        verify_bound(bad, source_raw, expected_source_sha)
    except AssertionError as exc:
        assert "deterministic target drift:" in str(exc), f"alternate same-segment target rejected for unrelated reason: {exc}"
    else:
        raise AssertionError("alternate same-segment target accepted without deterministic-target binding")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    receipt = strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    source_raw = Path(args.source).read_bytes()
    measured_error_m = verify_bound(receipt, source_raw, args.source_sha)

    if args.self_test:
        try:
            verify_bound(receipt, source_raw + b"\n", args.source_sha)
        except AssertionError as exc:
            assert "source SHA-256 drift:" in str(exc), f"unexpected source-byte rejection: {exc}"
        else:
            raise AssertionError("modified source bytes accepted under locked source SHA")
        source_doc = strict_json_loads(source_raw.decode("utf-8", errors="strict"))
        metric_boundary_self_test(receipt, source_doc)
        deterministic_candidate_boundary_self_test(receipt, source_raw, args.source_sha, source_doc)
        deterministic_target_boundary_self_test(receipt, source_raw, args.source_sha, source_doc)

    print(
        "BOURSE_8512036_MASKED_NATIVE_RECEIPT_SOURCE_BOUND_GREEN "
        "source_bytes_sha_bound=true spawn_midpoint_metric_bound=true deterministic_candidate_bound=true "
        "deterministic_target_bound=true "
        f"midpoint_error_m={measured_error_m:.9f}"
    )


if __name__ == "__main__":
    main()
