#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_SPATIAL_FIT_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

OBJECT_FRAGMENT = "female_sportsuit01"
HM08_VERTEX_COUNT = 19158
CLIFF_L1 = 1.7
SOURCE_HEAD_SHA = "afcb7b352ed054d98fdf83eae3333ec82c814b3e"
PROXY_ROWS = {
    377: {"body_vertices": [15673, 15918, 15917], "barycentric": [0.71752, 0.17271, 0.10978]},
    378: {"body_vertices": [15947, 15583, 15871], "barycentric": [0.48277, 0.38490, 0.13233]},
    379: {"body_vertices": [15702, 15673, 15674], "barycentric": [0.01498, 0.38313, 0.60189]},
    486: {"body_vertices": [15673, 15666, 15667], "barycentric": [1.07592, -0.01267, -0.06324]},
    599: {"body_vertices": [15917, 15666, 15673], "barycentric": [0.34706, 0.32672, 0.32622]},
    601: {"body_vertices": [15947, 15583, 15871], "barycentric": [0.22473, 0.62788, 0.14739]},
    615: {"body_vertices": [15666, 15667, 15674], "barycentric": [0.48600, 0.22476, 0.28924]},
    864: {"body_vertices": [15702, 15673, 15674], "barycentric": [0.49398, 0.53367, -0.02765]},
}
FOCAL_NEIGHBORS = {
    486: [377, 379, 601, 864],
    601: [378, 486, 599, 615],
}


class StopAfterSpatialFit(RuntimeError):
    pass


def distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.dist(a, b)


def vec_sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(float(x - y) for x, y in zip(a, b))


def l1(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in set(a) | set(b))


def weights(obj: bpy.types.Object, vertex: bpy.types.MeshVertex) -> dict[str, float]:
    names = {group.index: group.name for group in obj.vertex_groups}
    out: dict[str, float] = {}
    for assignment in vertex.groups:
        name = names.get(assignment.group)
        if name and assignment.weight > 0.0:
            out[name] = out.get(name, 0.0) + float(assignment.weight)
    return out


def mesh_objects(root: bpy.types.Object) -> list[bpy.types.Object]:
    seen: set[int] = set()
    out: list[bpy.types.Object] = []
    for obj in [root, *ready.base.descendants(root)]:
        if obj.type != "MESH" or id(obj) in seen:
            continue
        seen.add(id(obj))
        out.append(obj)
    return out


def find_sportsuit(root: bpy.types.Object) -> bpy.types.Object:
    matches = [obj for obj in mesh_objects(root) if OBJECT_FRAGMENT in obj.name.lower()]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one sportsuit, got {[obj.name for obj in matches]}")
    return matches[0]


def find_hm08(root: bpy.types.Object) -> bpy.types.Object:
    matches = [
        obj
        for obj in mesh_objects(root)
        if len(obj.data.vertices) == HM08_VERTEX_COUNT and OBJECT_FRAGMENT not in obj.name.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one {HM08_VERTEX_COUNT}-vertex hm08 body, "
            f"got {[(obj.name, len(obj.data.vertices)) for obj in matches]}"
        )
    return matches[0]


def world_xyz(obj: bpy.types.Object, vertex_index: int) -> tuple[float, float, float]:
    value = obj.matrix_world @ obj.data.vertices[vertex_index].co
    return tuple(float(v) for v in value)


def weighted_point(points: list[tuple[float, float, float]], coefficients: list[float]) -> tuple[float, float, float]:
    total = float(sum(coefficients))
    if abs(total) <= 1e-12:
        raise RuntimeError("proxy coefficient sum is zero")
    return tuple(
        sum(float(c) * float(point[axis]) for c, point in zip(coefficients, points)) / total
        for axis in range(3)
    )


def max_pair_distance(points: list[tuple[float, float, float]]) -> float:
    return max(distance(a, b) for i, a in enumerate(points) for b in points[i + 1 :])


def spatial_fit_trace(root: bpy.types.Object) -> dict[str, Any]:
    sportsuit = find_sportsuit(root)
    body = find_hm08(root)
    sportsuit_edges = {
        tuple(sorted((int(edge.vertices[0]), int(edge.vertices[1]))))
        for edge in sportsuit.data.edges
    }
    body_world = [world_xyz(body, int(vertex.index)) for vertex in body.data.vertices]

    vertex_records: dict[str, Any] = {}
    for sportsuit_vertex, proxy in PROXY_ROWS.items():
        clothing = world_xyz(sportsuit, sportsuit_vertex)
        body_vertices = [int(value) for value in proxy["body_vertices"]]
        coefficients = [float(value) for value in proxy["barycentric"]]
        support_vertices = [body_world[index] for index in body_vertices]
        support = weighted_point(support_vertices, coefficients)
        nearest_distance, nearest_vertex = min(
            (distance(clothing, position), index)
            for index, position in enumerate(body_world)
        )
        mapped_input_distances = [distance(clothing, position) for position in support_vertices]
        observed_weights = weights(sportsuit, sportsuit.data.vertices[sportsuit_vertex])
        vertex_records[str(sportsuit_vertex)] = {
            "sportsuit_vertex": sportsuit_vertex,
            "clothing_world_xyz": clothing,
            "body_vertices": body_vertices,
            "barycentric": coefficients,
            "barycentric_sum": sum(coefficients),
            "barycentric_has_negative": any(value < 0.0 for value in coefficients),
            "support_world_xyz": support,
            "support_to_clothing_vector": vec_sub(clothing, support),
            "support_to_clothing_distance_m": distance(clothing, support),
            "support_triangle_span_m": max_pair_distance(support_vertices),
            "mapped_input_to_clothing_distance_m_min": min(mapped_input_distances),
            "mapped_input_to_clothing_distance_m_max": max(mapped_input_distances),
            "nearest_body_vertex": int(nearest_vertex),
            "nearest_body_distance_m": float(nearest_distance),
            "nearest_body_is_mapped_input": int(nearest_vertex) in body_vertices,
            "nearest_to_mapped_input_distance_m_min": min(
                distance(body_world[int(nearest_vertex)], body_world[index]) for index in body_vertices
            ),
            "observed_weights": observed_weights,
        }

    unique_edges = sorted(
        {
            tuple(sorted((int(focal), int(neighbor))))
            for focal, neighbors in FOCAL_NEIGHBORS.items()
            for neighbor in neighbors
        }
    )
    edge_records: list[dict[str, Any]] = []
    for a, b in unique_edges:
        if (a, b) not in sportsuit_edges:
            raise RuntimeError(f"expected sportsuit native edge missing: {a}<->{b}")
        ra, rb = vertex_records[str(a)], vertex_records[str(b)]
        clothing_length = distance(tuple(ra["clothing_world_xyz"]), tuple(rb["clothing_world_xyz"]))
        support_length = distance(tuple(ra["support_world_xyz"]), tuple(rb["support_world_xyz"]))
        residual_change = distance(
            tuple(ra["support_to_clothing_vector"]),
            tuple(rb["support_to_clothing_vector"]),
        )
        weight_delta = l1(ra["observed_weights"], rb["observed_weights"])
        edge_records.append(
            {
                "edge": [a, b],
                "native_edge": True,
                "observed_weight_l1": weight_delta,
                "weight_class": "cliff" if weight_delta >= CLIFF_L1 else "smooth",
                "clothing_edge_length_m": clothing_length,
                "mapped_support_edge_length_m": support_length,
                "support_to_clothing_edge_ratio": support_length / clothing_length if clothing_length > 1e-12 else None,
                "support_minus_clothing_length_m": support_length - clothing_length,
                "support_offset_vector_change_m": residual_change,
                "endpoint_support_distance_m": [
                    float(ra["support_to_clothing_distance_m"]),
                    float(rb["support_to_clothing_distance_m"]),
                ],
                "endpoint_nearest_body_distance_m": [
                    float(ra["nearest_body_distance_m"]),
                    float(rb["nearest_body_distance_m"]),
                ],
            }
        )

    def summarize(kind: str) -> dict[str, Any]:
        rows = [row for row in edge_records if row["weight_class"] == kind]
        ratios = [float(row["support_to_clothing_edge_ratio"]) for row in rows if row["support_to_clothing_edge_ratio"] is not None]
        return {
            "count": len(rows),
            "edges": [row["edge"] for row in rows],
            "clothing_edge_length_m_min": min(float(row["clothing_edge_length_m"]) for row in rows),
            "clothing_edge_length_m_max": max(float(row["clothing_edge_length_m"]) for row in rows),
            "mapped_support_edge_length_m_min": min(float(row["mapped_support_edge_length_m"]) for row in rows),
            "mapped_support_edge_length_m_max": max(float(row["mapped_support_edge_length_m"]) for row in rows),
            "support_to_clothing_edge_ratio_min": min(ratios),
            "support_to_clothing_edge_ratio_max": max(ratios),
            "support_offset_vector_change_m_max": max(float(row["support_offset_vector_change_m"]) for row in rows),
        }

    result = {
        "format": "grand-bruxelles-gate8-variant01-mhclo-spatial-fit-v1",
        "diagnostic_state": "SPATIAL_FIT_MEASURED_RED_FIRST",
        "next_safe_axis": "REVIEW_MHCLO_SPATIAL_FIT_ARTIFACT",
        "source_head_sha": SOURCE_HEAD_SHA,
        "sportsuit_object": sportsuit.name,
        "sportsuit_vertex_count": len(sportsuit.data.vertices),
        "body_object": body.name,
        "body_vertex_count": len(body.data.vertices),
        "source_edge": [486, 601],
        "weight_cliff_threshold_l1": CLIFF_L1,
        "coordinate_space": "blender_world",
        "vertex_records": vertex_records,
        "edge_records": edge_records,
        "smooth_edge_summary": summarize("smooth"),
        "cliff_edge_summary": summarize("cliff"),
        "canonical_asset_mutation": False,
        "canonical_generator_mutation": False,
        "runtime_npc_mutation": False,
        "reweight_allowed": False,
        "production_activation_allowed": False,
        "visual_approval_allowed": False,
    }
    return result


def main() -> None:
    mpfb = ready.base.resolve_mpfb_module()
    services = importlib.import_module(mpfb.__package__ + ".services")
    ExportService = services.ExportService
    original_create_copy = ExportService.create_character_copy
    result: dict[str, Any] | None = None

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal result
        if result is not None:
            raise RuntimeError("spatial fit probe unexpectedly reached a second export copy")
        bpy.context.view_layer.update()
        result = spatial_fit_trace(root)
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True), flush=True)
        raise StopAfterSpatialFit("variant01 MHCLO spatial fit measured")

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    except StopAfterSpatialFit:
        pass
    finally:
        ExportService.create_character_copy = original_create_copy

    if result is None or not RESULT_PATH.is_file():
        raise RuntimeError("MHCLO spatial fit probe did not produce a result")


if __name__ == "__main__":
    main()
