#!/usr/bin/env python3
import argparse
import copy
import math
from pathlib import Path

from validate_bourse_8512036_masked_native_receipt import (
    ROAD_ID,
    display_road_width,
    expected_source_road,
    finite_pair,
    strict_json_loads,
)

MAX_WORLD_ABS_M = 890.0
MIN_SOURCE_AXIS_ALIGNMENT = 0.90
SOURCE_NETWORK_POINT_EPSILON_M = 0.001
SOURCE_VIEW_CLEARANCE_EPSILON_M = 0.001
SPAWN_IDENTITY_EPSILON_M = 0.001


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, scalar):
    return (a[0] * scalar, a[1] * scalar)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def length(v):
    return math.hypot(v[0], v[1])


def distance(a, b):
    return length(sub(a, b))


def normalized(v):
    size = length(v)
    assert size > 1e-12
    return (v[0] / size, v[1] / size)


def midpoint(a, b):
    return ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)


def point_segment_distance(point, start, finish):
    segment = sub(finish, start)
    length_sq = dot(segment, segment)
    if length_sq <= 1e-7:
        return distance(point, start)
    t = max(0.0, min(1.0, dot(sub(point, start), segment) / length_sq))
    return distance(point, add(start, mul(segment, t)))


def orientation(a, b, c):
    value = (b[1] - a[1]) * (c[0] - b[0]) - (b[0] - a[0]) * (c[1] - b[1])
    if abs(value) <= 1e-10:
        return 0
    return 1 if value > 0.0 else 2


def on_segment(a, b, c):
    return min(a[0], c[0]) - 1e-10 <= b[0] <= max(a[0], c[0]) + 1e-10 and min(a[1], c[1]) - 1e-10 <= b[1] <= max(a[1], c[1]) + 1e-10


def segments_intersect(a0, a1, b0, b1):
    o1 = orientation(a0, a1, b0)
    o2 = orientation(a0, a1, b1)
    o3 = orientation(b0, b1, a0)
    o4 = orientation(b0, b1, a1)
    if o1 != o2 and o3 != o4:
        return True
    return (
        (o1 == 0 and on_segment(a0, b0, a1))
        or (o2 == 0 and on_segment(a0, b1, a1))
        or (o3 == 0 and on_segment(b0, a0, b1))
        or (o4 == 0 and on_segment(b0, a1, b1))
    )


def point_in_polygon(point, polygon):
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        a = polygon[j]
        b = polygon[i]
        if point_segment_distance(point, a, b) <= 1e-10:
            return True
        crosses = (b[1] > point[1]) != (a[1] > point[1])
        if crosses:
            x_cross = (a[0] - b[0]) * (point[1] - b[1]) / (a[1] - b[1]) + b[0]
            if point[0] < x_cross:
                inside = not inside
        j = i
    return inside


def source_polygons(source_doc):
    buildings = source_doc.get("buildings")
    assert isinstance(buildings, list)
    result = []
    for building in buildings:
        assert isinstance(building, dict)
        footprint = building.get("footprint")
        assert isinstance(footprint, list) and len(footprint) >= 3
        assert all(finite_pair(pair) for pair in footprint)
        result.append([(float(pair[0]), float(pair[1])) for pair in footprint])
    return result


def inside_any(polygons, point):
    return any(point_in_polygon(point, polygon) for polygon in polygons)


def segment_clear(polygons, start, finish):
    if inside_any(polygons, start) or inside_any(polygons, finish):
        return False
    for polygon in polygons:
        for index in range(len(polygon)):
            if segments_intersect(start, finish, polygon[index], polygon[(index + 1) % len(polygon)]):
                return False
    return True


def segment_segment_distance(a0, a1, b0, b1):
    if segments_intersect(a0, a1, b0, b1):
        return 0.0
    return min(
        point_segment_distance(a0, b0, b1),
        point_segment_distance(a1, b0, b1),
        point_segment_distance(b0, a0, a1),
        point_segment_distance(b1, a0, a1),
    )


def source_building_clearance(polygons, point):
    if inside_any(polygons, point):
        return 0.0
    best = math.inf
    for polygon in polygons:
        for index in range(len(polygon)):
            best = min(best, point_segment_distance(point, polygon[index], polygon[(index + 1) % len(polygon)]))
    return best


def source_view_clearance(polygons, start, finish):
    if not segment_clear(polygons, start, finish):
        return 0.0
    best = math.inf
    for polygon in polygons:
        for index in range(len(polygon)):
            best = min(best, segment_segment_distance(start, finish, polygon[index], polygon[(index + 1) % len(polygon)]))
    return best


def exact_road_id(raw):
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        return 0
    numeric = float(raw)
    if not math.isfinite(numeric) or numeric <= 0.0 or math.floor(numeric) != numeric or numeric > 9007199254740991.0:
        return 0
    return int(numeric)


def endpoint_continuation_count(source_doc, selected_road, endpoint):
    selected_id = exact_road_id(selected_road.get("osm_id"))
    assert selected_id == ROAD_ID
    roads = source_doc.get("roads")
    assert isinstance(roads, list)
    count = 0
    for other in roads:
        assert isinstance(other, dict)
        if exact_road_id(other.get("osm_id")) == selected_id:
            continue
        points = other.get("points")
        assert isinstance(points, list)
        found = False
        for point in points:
            assert finite_pair(point)
            if distance(point, endpoint) <= SOURCE_NETWORK_POINT_EPSILON_M:
                found = True
                break
        if found:
            count += 1
    return count


def same_way_arc_target(points, segment_index, direction_sign, maximum_distance_m):
    start = points[segment_index]
    finish = points[segment_index + 1]
    mid = midpoint(start, finish)
    endpoint = finish if direction_sign > 0 else start
    first_distance = distance(mid, endpoint)
    remaining = maximum_distance_m
    travelled = 0.0
    if first_distance > 1e-7:
        if remaining <= first_distance:
            ratio = remaining / first_distance
            return add(mid, mul(sub(endpoint, mid), ratio)), remaining
        travelled = first_distance
        remaining -= first_distance
    if direction_sign > 0:
        for index in range(segment_index + 1, len(points) - 1):
            a, b = points[index], points[index + 1]
            segment_length = distance(a, b)
            if segment_length <= 1e-7:
                continue
            if remaining <= segment_length:
                return add(a, mul(sub(b, a), remaining / segment_length)), travelled + remaining
            travelled += segment_length
            remaining -= segment_length
    else:
        for index in range(segment_index - 1, -1, -1):
            a, b = points[index + 1], points[index]
            segment_length = distance(a, b)
            if segment_length <= 1e-7:
                continue
            if remaining <= segment_length:
                return add(a, mul(sub(b, a), remaining / segment_length)), travelled + remaining
            travelled += segment_length
            remaining -= segment_length
    if travelled <= 1e-7:
        return None
    return (points[-1] if direction_sign > 0 else points[0]), travelled


def deterministic_source_candidate(source_doc):
    road = expected_source_road(source_doc)
    points = [(float(p[0]), float(p[1])) for p in road["points"]]
    best_index = max(range(len(points) - 1), key=lambda index: distance(points[index], points[index + 1]))
    best_length = distance(points[best_index], points[best_index + 1])
    assert best_length >= 1.0
    polygons = source_polygons(source_doc)
    start_connections = endpoint_continuation_count(source_doc, road, points[0])
    end_connections = endpoint_continuation_count(source_doc, road, points[-1])
    start = points[best_index]
    finish = points[best_index + 1]
    mid = midpoint(start, finish)
    assert not inside_any(polygons, mid)
    direction = normalized(sub(finish, start))
    perpendicular = (-direction[1], direction[0])
    half_road = display_road_width(road) * 0.5
    offsets = [half_road + delta for delta in (1.10, 2.00, 3.50, 5.00, 7.50)]
    for offset in offsets:
        required_lookahead = offset * 2.10
        candidates = []
        safest = -math.inf
        for side in (1.0, -1.0):
            spawn = add(mid, mul(perpendicular, offset * side))
            if abs(spawn[0]) > MAX_WORLD_ABS_M or abs(spawn[1]) > MAX_WORLD_ABS_M or inside_any(polygons, spawn):
                continue
            spawn_clearance = source_building_clearance(polygons, spawn)
            for along_sign in (1, -1):
                arc = same_way_arc_target(points, best_index, along_sign, 22.0)
                if arc is None:
                    continue
                target, lookahead = arc
                if lookahead < required_lookahead:
                    continue
                if abs(target[0]) > MAX_WORLD_ABS_M or abs(target[1]) > MAX_WORLD_ABS_M or inside_any(polygons, target):
                    continue
                axis = sub(target, spawn)
                if length(axis) <= 1e-12 or abs(dot(normalized(axis), direction)) < MIN_SOURCE_AXIS_ALIGNMENT:
                    continue
                if not segment_clear(polygons, spawn, target):
                    continue
                continuation = end_connections if along_sign > 0 else start_connections
                clearance = source_view_clearance(polygons, spawn, target)
                if not math.isfinite(clearance) or clearance < 0.0:
                    continue
                safest = max(safest, clearance)
                candidates.append((spawn, target, continuation, spawn_clearance, clearance, offset, side, along_sign))
        if not candidates or not math.isfinite(safest):
            continue
        best = None
        best_continuation = -1
        best_spawn_clearance = -math.inf
        for candidate in candidates:
            if candidate[4] + SOURCE_VIEW_CLEARANCE_EPSILON_M < safest:
                continue
            continuation = candidate[2]
            spawn_clearance = candidate[3]
            if best is None or continuation > best_continuation or (continuation == best_continuation and spawn_clearance > best_spawn_clearance):
                best = candidate
                best_continuation = continuation
                best_spawn_clearance = spawn_clearance
        if best is not None:
            return {
                "spawn": best[0],
                "target": best[1],
                "segment_index": best_index,
                "offset_m": best[5],
                "side": best[6],
                "along_sign": best[7],
            }
    raise AssertionError("independent source-only candidate unavailable")


def verify(receipt, source_doc):
    assert receipt["road_osm_id"] == ROAD_ID
    assert finite_pair(receipt["spawn_xz"])
    candidate = deterministic_source_candidate(source_doc)
    assert receipt["segment_index"] == candidate["segment_index"]
    measured = distance(receipt["spawn_xz"], candidate["spawn"])
    assert measured <= SPAWN_IDENTITY_EPSILON_M, (
        f"deterministic spawn drift: {measured:.9f} m; expected={candidate['spawn']} actual={receipt['spawn_xz']}"
    )
    return candidate


def assert_rejected(mutated, source_doc, label):
    try:
        verify(mutated, source_doc)
    except AssertionError:
        return
    raise AssertionError(f"forged deterministic candidate accepted: {label}")


def self_test(receipt, source_doc):
    candidate = deterministic_source_candidate(source_doc)
    road = expected_source_road(source_doc)
    start = road["points"][candidate["segment_index"]]
    finish = road["points"][candidate["segment_index"] + 1]
    direction = normalized(sub(finish, start))
    perpendicular = (-direction[1], direction[0])
    mid = midpoint(start, finish)

    bad = copy.deepcopy(receipt)
    bad["spawn_xz"] = list(add(mid, mul(perpendicular, -candidate["side"] * candidate["offset_m"])))
    assert_rejected(bad, source_doc, "opposite_side")

    bad = copy.deepcopy(receipt)
    bad["spawn_xz"] = list(add(mid, mul(perpendicular, candidate["side"] * (candidate["offset_m"] + 0.90))))
    assert_rejected(bad, source_doc, "lower_priority_offset")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    receipt = strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    source_doc = strict_json_loads(Path(args.source).read_text(encoding="utf-8"))
    candidate = verify(receipt, source_doc)
    if args.self_test:
        self_test(receipt, source_doc)
    print(
        "BOURSE_8512036_DETERMINISTIC_CANDIDATE_GREEN "
        f"offset_m={candidate['offset_m']:.6f} side={candidate['side']:.1f} along_sign={candidate['along_sign']}"
    )


if __name__ == "__main__":
    main()
