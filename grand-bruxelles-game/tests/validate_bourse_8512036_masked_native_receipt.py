#!/usr/bin/env python3
import argparse
import copy
import json
import math
from pathlib import Path

ROAD_ID = 8512036
SCHEMA = "grand-bruxelles-bourse-8512036-corridor-masked-visual-v1"
SOURCE_RESOURCE_PATH = "res://data/osm/vertical_slice_01.game.json"
LOOKUP_MODE = "deterministic_runtime_index"
MASK_NODE = "Player/VisualUpgrade"
TARGET_SOURCE_SEGMENT_EPSILON_M = 0.001
SPAWN_SOURCE_GEOMETRY_EPSILON_M = 0.001
AXIS_ALIGNMENT_EPSILON = 1e-6


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def finite_pair(value):
    return isinstance(value, list) and len(value) == 2 and all(finite_number(v) for v in value)


def segment_projection(point, start, finish):
    vx = finish[0] - start[0]
    vy = finish[1] - start[1]
    length_sq = vx * vx + vy * vy
    assert length_sq > 0.0
    wx = point[0] - start[0]
    wy = point[1] - start[1]
    t = (wx * vx + wy * vy) / length_sq
    px = start[0] + t * vx
    py = start[1] + t * vy
    return t, [px, py], math.hypot(point[0] - px, point[1] - py)


def point_segment_distance(point, start, finish):
    t, _, _ = segment_projection(point, start, finish)
    t = max(0.0, min(1.0, t))
    px = start[0] + t * (finish[0] - start[0])
    py = start[1] + t * (finish[1] - start[1])
    return math.hypot(point[0] - px, point[1] - py)


def recomputed_axis_alignment(spawn, target, start, finish):
    view_x = target[0] - spawn[0]
    view_y = target[1] - spawn[1]
    source_x = finish[0] - start[0]
    source_y = finish[1] - start[1]
    view_length = math.hypot(view_x, view_y)
    source_length = math.hypot(source_x, source_y)
    assert view_length > 0.0 and source_length > 0.0
    return abs((view_x * source_x + view_y * source_y) / (view_length * source_length))


def display_road_width(road):
    width = road.get("width", 4.5)
    assert finite_number(width)
    width = max(float(width), 2.5)
    road_class = road.get("class", "")
    assert isinstance(road_class, str)
    if road_class == "primary":
        return max(width, 10.5)
    if road_class == "secondary":
        return max(width, 8.5)
    if road_class == "tertiary":
        return max(width, 7.2)
    return width


def expected_longest_segment_index(points):
    best_index = -1
    best_length = -1.0
    for index in range(len(points) - 1):
        a = points[index]
        b = points[index + 1]
        assert finite_pair(a) and finite_pair(b) and a != b
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length > best_length:
            best_length = length
            best_index = index
    assert best_index >= 0 and best_length >= 1.0
    return best_index


def verify_spawn_source_geometry(spawn, road, segment_index):
    points = road["points"]
    assert segment_index == expected_longest_segment_index(points)
    start = points[segment_index]
    finish = points[segment_index + 1]
    projection_t, _, lateral_distance = segment_projection(spawn, start, finish)
    segment_length_m = math.hypot(finish[0] - start[0], finish[1] - start[1])
    assert segment_length_m > 0.0
    longitudinal_error_m = abs(projection_t - 0.5) * segment_length_m
    assert longitudinal_error_m <= SPAWN_SOURCE_GEOMETRY_EPSILON_M, (
        "spawn midpoint longitudinal drift exceeds metric epsilon: "
        f"error_m={longitudinal_error_m:.9f} epsilon_m={SPAWN_SOURCE_GEOMETRY_EPSILON_M:.9f}"
    )
    half_road = display_road_width(road) * 0.5
    allowed_offsets = [half_road + delta for delta in (1.10, 2.00, 3.50, 5.00, 7.50)]
    assert any(abs(lateral_distance - offset) <= SPAWN_SOURCE_GEOMETRY_EPSILON_M for offset in allowed_offsets)


def strict_json_loads(raw):
    def object_pairs_no_duplicates(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError(f"duplicate JSON key: {key}")
            out[key] = value
        return out

    def finite_float(token):
        value = float(token)
        if not math.isfinite(value):
            raise ValueError("non-finite JSON number")
        return value

    def reject_constant(token):
        raise ValueError(f"non-standard JSON constant: {token}")

    return json.loads(raw, object_pairs_hook=object_pairs_no_duplicates, parse_float=finite_float, parse_constant=reject_constant)


def expected_source_road(source_doc):
    roads = source_doc.get("roads")
    assert isinstance(roads, list)
    exact = [r for r in roads if isinstance(r, dict) and type(r.get("osm_id")) is int and r["osm_id"] == ROAD_ID]
    assert len(exact) == 1
    road = exact[0]
    assert road.get("drivable") is True
    name = road.get("name")
    assert isinstance(name, str) and name
    points = road.get("points")
    assert isinstance(points, list) and len(points) >= 2
    return road


def verify(receipt, source_doc, expected_source_sha):
    source_road = expected_source_road(source_doc)
    source_name = source_road["name"]
    assert receipt["schema"] == SCHEMA
    assert receipt["road_osm_id"] == ROAD_ID
    assert receipt["request"] == f"road-{ROAD_ID}"
    assert receipt["resolution"] == [1280, 720]
    assert receipt["source_path"] == SOURCE_RESOURCE_PATH
    assert receipt["source_name"] == source_name
    assert receipt["source_sha256"] == expected_source_sha
    assert receipt["lookup_mode"] == LOOKUP_MODE
    assert finite_pair(receipt["spawn_xz"])
    assert finite_pair(receipt["target_xz"])
    assert receipt["spawn_xz"] != receipt["target_xz"]
    assert finite_number(receipt["ground_y"])
    assert finite_number(receipt["camera_fov"]) and 1.0 < receipt["camera_fov"] < 179.0
    segment_index = receipt["segment_index"]
    assert type(segment_index) is int and segment_index >= 0
    points = source_road["points"]
    assert segment_index + 1 < len(points)
    segment_a = points[segment_index]
    segment_b = points[segment_index + 1]
    assert finite_pair(segment_a) and finite_pair(segment_b)
    assert segment_a != segment_b
    verify_spawn_source_geometry(receipt["spawn_xz"], source_road, segment_index)
    assert point_segment_distance(receipt["target_xz"], segment_a, segment_b) <= TARGET_SOURCE_SEGMENT_EPSILON_M
    assert finite_number(receipt["axis_alignment"]) and 0.90 <= receipt["axis_alignment"] <= 1.0
    measured_axis_alignment = recomputed_axis_alignment(receipt["spawn_xz"], receipt["target_xz"], segment_a, segment_b)
    assert 0.90 <= measured_axis_alignment <= 1.0
    assert abs(receipt["axis_alignment"] - measured_axis_alignment) <= AXIS_ALIGNMENT_EPSILON
    assert receipt["source_sightline_clear"] is True
    assert receipt["qa_mask_applied"] is True
    assert receipt["qa_mask_node"] == MASK_NODE
    assert receipt["qa_mask_originally_visible"] is True
    assert receipt["qa_mask_restored"] is True
    assert receipt["qa_mask_final_visibility"] is receipt["qa_mask_originally_visible"]
    assert receipt["qa_mask_ephemeral"] is True
    assert receipt["dynamic_state_frozen"] is True
    assert receipt["character_runtime_changed"] is False
    assert receipt["player_physics_changed"] is False
    assert receipt["camera_changed"] is False
    assert receipt["camera_authored_contract_unchanged"] is True
    assert "camera_local_transform_unchanged" not in receipt
    assert receipt["source_geometry_changed"] is False
    assert receipt["collision_geometry_changed"] is False
    assert receipt["resolver_thresholds_lowered"] is False
    assert receipt["human_visual_review_required"] is True
    assert receipt["masked_frame_cannot_promote_destination"] is True
    assert receipt["visual_acceptance"] is False
    assert receipt["destination_advertisable"] is False
    assert receipt["jouable_authorized"] is False


def strict_loader_self_test():
    invalid = ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":-Infinity}', '{"a":1e309}')
    for raw in invalid:
        try:
            strict_json_loads(raw)
        except ValueError:
            continue
        raise AssertionError("ambiguous or non-finite JSON accepted")


def self_test(receipt, source_doc, expected_source_sha):
    strict_loader_self_test()
    source_road = expected_source_road(source_doc)
    segment_index = receipt["segment_index"]
    segment_a = source_road["points"][segment_index]
    segment_b = source_road["points"][segment_index + 1]

    def shift_spawn_along_source_axis(r, distance_m=10.0):
        vx = segment_b[0] - segment_a[0]
        vy = segment_b[1] - segment_a[1]
        length = math.hypot(vx, vy)
        ux = vx / length
        uy = vy / length
        r["spawn_xz"] = [r["spawn_xz"][0] + ux * distance_m, r["spawn_xz"][1] + uy * distance_m]
        r["axis_alignment"] = recomputed_axis_alignment(r["spawn_xz"], r["target_xz"], segment_a, segment_b)

    def shift_spawn_ten_mm(r):
        shift_spawn_along_source_axis(r, 0.01)

    mutations = (
        ("source_name", lambda r: r.__setitem__("source_name", "Saint-G forged semantic alias")),
        ("spawn_missing", lambda r: r.pop("spawn_xz", None)),
        ("spawn_bool", lambda r: r.__setitem__("spawn_xz", [True, 0.0])),
        ("spawn_off_axis_with_forged_alignment", lambda r: r.__setitem__("spawn_xz", [r["spawn_xz"][0] + 100.0, r["spawn_xz"][1] + 100.0])),
        ("spawn_longitudinal_with_recomputed_alignment", shift_spawn_along_source_axis),
        ("spawn_longitudinal_ten_mm_metric_boundary", shift_spawn_ten_mm),
        ("target_nonfinite", lambda r: r.__setitem__("target_xz", [0.0, float("inf")])),
        ("target_off_source_segment", lambda r: r.__setitem__("target_xz", [r["target_xz"][0] + 100.0, r["target_xz"][1]])),
        ("ground_nonfinite", lambda r: r.__setitem__("ground_y", float("nan"))),
        ("camera_fov_bool", lambda r: r.__setitem__("camera_fov", True)),
        ("camera_fov_range", lambda r: r.__setitem__("camera_fov", 180.0)),
        ("segment_index_bool", lambda r: r.__setitem__("segment_index", True)),
        ("segment_index_out_of_source", lambda r: r.__setitem__("segment_index", 999999)),
        ("axis_alignment_impossible", lambda r: r.__setitem__("axis_alignment", 1.25)),
        ("axis_alignment_forged_but_plausible", lambda r: r.__setitem__("axis_alignment", 0.91 if abs(r["axis_alignment"] - 0.91) > 0.001 else 0.99)),
        ("lookup_mode", lambda r: r.__setitem__("lookup_mode", "nearest_guess")),
        ("qa_mask_restored", lambda r: r.__setitem__("qa_mask_restored", False)),
        ("dynamic_state_frozen", lambda r: r.__setitem__("dynamic_state_frozen", False)),
        ("camera_changed", lambda r: r.__setitem__("camera_changed", True)),
        ("camera_authored_contract_unchanged", lambda r: r.__setitem__("camera_authored_contract_unchanged", False)),
        ("legacy_camera_transform_claim", lambda r: r.__setitem__("camera_local_transform_unchanged", True)),
        ("source_geometry_changed", lambda r: r.__setitem__("source_geometry_changed", True)),
        ("collision_geometry_changed", lambda r: r.__setitem__("collision_geometry_changed", True)),
        ("resolver_thresholds_lowered", lambda r: r.__setitem__("resolver_thresholds_lowered", True)),
        ("destination_advertisable", lambda r: r.__setitem__("destination_advertisable", True)),
        ("jouable_authorized", lambda r: r.__setitem__("jouable_authorized", True)),
    )
    for label, mutate in mutations:
        bad = copy.deepcopy(receipt)
        mutate(bad)
        try:
            verify(bad, source_doc, expected_source_sha)
        except (AssertionError, KeyError):
            continue
        raise AssertionError(f"native receipt mutation accepted: {label}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    receipt = strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    source_doc = strict_json_loads(Path(args.source).read_text(encoding="utf-8"))
    verify(receipt, source_doc, args.source_sha)
    if args.self_test:
        self_test(receipt, source_doc, args.source_sha)
    print("BOURSE_8512036_MASKED_NATIVE_RECEIPT_GREEN")


if __name__ == "__main__":
    main()
