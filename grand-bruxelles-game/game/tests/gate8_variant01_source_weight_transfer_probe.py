#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_WEIGHT_TRANSFER_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

TARGET_GLB = "npc_gate_01.glb"
TARGET_SHA256 = "912ac8dedf4509640f90771f4c9d3b1af818b59261caab4d9b3f1fb0fe3e2ac9"
TARGET_SIZE = 15580240
TARGET_SEED = 53756543
OBJECT_FRAGMENT = "female_sportsuit01"
PREPARED_ENDPOINTS = (486, 601)
HM08_VERTEX_COUNT = 19158
PROXY_ROWS = {
    486: {"body_vertices": [15673, 15666, 15667], "barycentric": [1.07592, -0.01267, -0.06324]},
    601: {"body_vertices": [15947, 15583, 15871], "barycentric": [0.22473, 0.62788, 0.14739]},
}
POSITION_TOL = 1e-4
WEIGHT_TOL = 1e-4
CLIFF_L1 = 1.7


class StopAfterVariantOne(RuntimeError):
    pass


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


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
        raise RuntimeError(f"expected exactly one sportsuit under {root.name}, got {[o.name for o in matches]}")
    return matches[0]


def find_hm08(root: bpy.types.Object) -> bpy.types.Object:
    matches = [obj for obj in mesh_objects(root) if len(obj.data.vertices) == HM08_VERTEX_COUNT and OBJECT_FRAGMENT not in obj.name.lower()]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one {HM08_VERTEX_COUNT}-vertex hm08 mesh under {root.name}, "
            f"got {[(o.name, len(o.data.vertices)) for o in matches]}"
        )
    return matches[0]


def normalize_positive(values: dict[str, float]) -> dict[str, float]:
    positive = {name: max(0.0, float(value)) for name, value in values.items() if value > 0.0}
    total = sum(positive.values())
    if total <= 0.0:
        return {}
    return {name: value / total for name, value in positive.items() if value / total > 0.0}


def proxy_interpolation_trace(root: bpy.types.Object) -> dict[str, Any]:
    sportsuit = find_sportsuit(root)
    body = find_hm08(root)
    endpoint_records: dict[str, Any] = {}
    for endpoint, proxy in PROXY_ROWS.items():
        observed = weights(sportsuit, sportsuit.data.vertices[endpoint])
        body_records = []
        linear: dict[str, float] = {}
        for body_vertex, coefficient in zip(proxy["body_vertices"], proxy["barycentric"]):
            source = weights(body, body.data.vertices[body_vertex])
            body_records.append(
                {
                    "vertex": int(body_vertex),
                    "coefficient": float(coefficient),
                    "weights": source,
                }
            )
            for bone, value in source.items():
                linear[bone] = linear.get(bone, 0.0) + float(coefficient) * float(value)
        linear = {bone: value for bone, value in linear.items() if abs(value) > 1e-12}
        positive_normalized = normalize_positive(linear)
        endpoint_records[str(endpoint)] = {
            "sportsuit_vertex": int(endpoint),
            "observed_weights": observed,
            "body_inputs": body_records,
            "linear_interpolated_weights": linear,
            "positive_normalized_interpolated_weights": positive_normalized,
            "linear_to_observed_l1": l1(linear, observed),
            "positive_normalized_to_observed_l1": l1(positive_normalized, observed),
        }
    records = list(endpoint_records.values())
    observed_cliff = l1(records[0]["observed_weights"], records[1]["observed_weights"])
    linear_cliff = l1(records[0]["linear_interpolated_weights"], records[1]["linear_interpolated_weights"])
    normalized_cliff = l1(
        records[0]["positive_normalized_interpolated_weights"],
        records[1]["positive_normalized_interpolated_weights"],
    )
    max_linear_residual = max(record["linear_to_observed_l1"] for record in records)
    max_normalized_residual = max(record["positive_normalized_to_observed_l1"] for record in records)
    if max_normalized_residual <= WEIGHT_TOL:
        state = "SOURCE_SPORTSUIT_WEIGHTS_MATCH_POSITIVE_NORMALIZED_PROXY_INTERPOLATION"
        next_axis = "TRACE_HM08_SOURCE_WEIGHT_INPUTS"
    elif max_linear_residual <= WEIGHT_TOL:
        state = "SOURCE_SPORTSUIT_WEIGHTS_MATCH_LINEAR_PROXY_INTERPOLATION"
        next_axis = "TRACE_HM08_SOURCE_WEIGHT_INPUTS"
    else:
        state = "SOURCE_SPORTSUIT_WEIGHTS_NOT_EXPLAINED_BY_MHCLO_LINEAR_INTERPOLATION"
        next_axis = "TRACE_MPF_B_PROXY_WEIGHT_TRANSFER_IMPLEMENTATION"
    return {
        "diagnostic_state": state,
        "next_safe_axis": next_axis,
        "body_object": body.name,
        "body_vertex_count": len(body.data.vertices),
        "sportsuit_object": sportsuit.name,
        "sportsuit_vertex_count": len(sportsuit.data.vertices),
        "endpoint_records": endpoint_records,
        "observed_endpoint_cliff_l1": observed_cliff,
        "linear_interpolated_endpoint_cliff_l1": linear_cliff,
        "positive_normalized_endpoint_cliff_l1": normalized_cliff,
        "max_linear_to_observed_l1": max_linear_residual,
        "max_positive_normalized_to_observed_l1": max_normalized_residual,
    }


def snapshot(root: bpy.types.Object, stage: str) -> dict[str, Any]:
    obj = find_sportsuit(root)
    edges = {tuple(sorted((int(e.vertices[0]), int(e.vertices[1])))) for e in obj.data.edges}
    vertices = []
    for vertex in obj.data.vertices:
        local = tuple(float(v) for v in vertex.co)
        world_v = obj.matrix_world @ vertex.co
        vertices.append(
            {
                "index": int(vertex.index),
                "local_xyz": local,
                "world_xyz": tuple(float(v) for v in world_v),
                "weights": weights(obj, vertex),
            }
        )
    return {
        "stage": stage,
        "object": obj.name,
        "vertex_count": len(vertices),
        "edge_count": len(edges),
        "edges": edges,
        "vertices": vertices,
    }


def distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def map_endpoint(target: dict[str, Any], earlier: dict[str, Any]) -> dict[str, Any]:
    target_local = tuple(target["local_xyz"])
    best_distance, best = min((distance(target_local, tuple(v["local_xyz"])), v) for v in earlier["vertices"])
    return {
        "vertex": int(best["index"]),
        "position_distance_m": float(best_distance),
        "weights": best["weights"],
        "weight_delta_to_prepared_l1": l1(best["weights"], target["weights"]),
    }


def stage_transfer(prepared: dict[str, Any], earlier: dict[str, Any]) -> dict[str, Any]:
    pa = prepared["vertices"][PREPARED_ENDPOINTS[0]]
    pb = prepared["vertices"][PREPARED_ENDPOINTS[1]]
    ma, mb = map_endpoint(pa, earlier), map_endpoint(pb, earlier)
    pair = tuple(sorted((ma["vertex"], mb["vertex"])))
    cliff = l1(ma["weights"], mb["weights"])
    return {
        "stage": earlier["stage"],
        "mapped_vertices": [ma["vertex"], mb["vertex"]],
        "mapped_pair_is_native_edge": pair in earlier["edges"],
        "endpoint_a": ma,
        "endpoint_b": mb,
        "mapped_edge_weight_l1": cliff,
        "mapped_edge_is_cliff": cliff >= CLIFF_L1,
        "positions_resolved": ma["position_distance_m"] <= POSITION_TOL and mb["position_distance_m"] <= POSITION_TOL,
    }


def main() -> None:
    mpfb = ready.base.resolve_mpfb_module()
    services = importlib.import_module(mpfb.__package__ + ".services")
    ExportService, TargetService = services.ExportService, services.TargetService
    original_create_copy = ExportService.create_character_copy
    original_bake_targets = TargetService.bake_targets
    original_bake_helpers = ExportService.bake_modifiers_remove_helpers
    original_export = ready._original_export_character
    captured: dict[str, dict[str, Any]] = {}
    result: dict[str, Any] | None = None
    active_copy_root: bpy.types.Object | None = None
    proxy_trace: dict[str, Any] | None = None

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal active_copy_root, proxy_trace
        if not captured:
            captured["source_before_copy"] = snapshot(root, "source_before_copy")
            proxy_trace = proxy_interpolation_trace(root)
        copied = original_create_copy(root, *args, **kwargs)
        active_copy_root = copied
        captured["copy_after_create"] = snapshot(copied, "copy_after_create")
        return copied

    def wrapped_bake_targets(obj, *args, **kwargs):
        value = original_bake_targets(obj, *args, **kwargs)
        if active_copy_root is not None:
            captured["copy_after_target_bake"] = snapshot(active_copy_root, "copy_after_target_bake")
        return value

    def wrapped_bake_helpers(obj, *args, **kwargs):
        if active_copy_root is not None and "copy_before_helper_bake" not in captured:
            captured["copy_before_helper_bake"] = snapshot(active_copy_root, "copy_before_helper_bake")
        value = original_bake_helpers(obj, *args, **kwargs)
        bpy.context.view_layer.update()
        if active_copy_root is not None:
            captured["copy_after_helper_bake"] = snapshot(active_copy_root, "copy_after_helper_bake")
        return value

    def wrapped_export(prepared_root: bpy.types.Object, output_path: Path) -> dict:
        nonlocal result
        if output_path.name != TARGET_GLB:
            raise RuntimeError(f"unexpected first export target: {output_path.name}")
        prepared = snapshot(prepared_root, "prepared_before_gltf_export")
        captured["prepared_before_gltf_export"] = prepared
        record = original_export(prepared_root, output_path)
        digest, size = sha256_path(output_path), output_path.stat().st_size
        if digest != TARGET_SHA256 or size != TARGET_SIZE or int(record["seed"]) != TARGET_SEED:
            raise RuntimeError("deterministic variant01 regeneration drifted")
        prepared_edge = tuple(sorted(PREPARED_ENDPOINTS))
        if prepared_edge not in prepared["edges"]:
            raise RuntimeError("prepared 486-601 edge is no longer native")
        prepared_cliff = l1(prepared["vertices"][486]["weights"], prepared["vertices"][601]["weights"])
        if prepared_cliff < CLIFF_L1:
            raise RuntimeError(f"prepared shoulder cliff unexpectedly disappeared: {prepared_cliff}")
        stage_order = [
            "source_before_copy",
            "copy_after_create",
            "copy_after_target_bake",
            "copy_before_helper_bake",
            "copy_after_helper_bake",
        ]
        transfers = [stage_transfer(prepared, captured[name]) for name in stage_order if name in captured]
        if not transfers or not all(t["positions_resolved"] for t in transfers):
            state, next_axis = (
                "SOURCE_WEIGHT_TRANSFER_POSITION_MAPPING_UNRESOLVED",
                "TRACE_SOURCE_TO_EXPORT_COPY_VERTEX_MAPPING",
            )
        else:
            cliff_stages = [t["stage"] for t in transfers if t["mapped_edge_is_cliff"]]
            if "source_before_copy" in cliff_stages:
                if proxy_trace is None:
                    raise RuntimeError("proxy interpolation trace missing")
                state, next_axis = proxy_trace["diagnostic_state"], proxy_trace["next_safe_axis"]
            else:
                first = next((t["stage"] for t in transfers if t["mapped_edge_is_cliff"]), None)
                mapping = {
                    "copy_after_create": (
                        "WEIGHT_CLIFF_INTRODUCED_BY_EXPORT_COPY",
                        "ISOLATE_CREATE_CHARACTER_COPY_WEIGHT_MUTATION",
                    ),
                    "copy_after_target_bake": (
                        "WEIGHT_CLIFF_INTRODUCED_DURING_TARGET_BAKE",
                        "ISOLATE_TARGET_BAKE_PROXY_WEIGHT_MUTATION",
                    ),
                    "copy_before_helper_bake": (
                        "WEIGHT_CLIFF_INTRODUCED_DURING_TARGET_BAKE",
                        "ISOLATE_TARGET_BAKE_PROXY_WEIGHT_MUTATION",
                    ),
                    "copy_after_helper_bake": (
                        "WEIGHT_CLIFF_INTRODUCED_DURING_HELPER_BAKE",
                        "ISOLATE_BAKE_MODIFIERS_PROXY_WEIGHT_MUTATION",
                    ),
                }
                state, next_axis = mapping.get(
                    first,
                    ("SOURCE_WEIGHT_TRANSFER_STAGE_NOT_IDENTIFIED", "STOP_AND_INSPECT_WEIGHT_TRANSFER"),
                )
        result = {
            "format": "grand-bruxelles-gate8-variant01-source-weight-transfer-v2",
            "diagnostic_state": state,
            "next_safe_axis": next_axis,
            "generated_glb_sha256": digest,
            "generated_glb_size_bytes": size,
            "generated_seed": int(record["seed"]),
            "source_head_sha": "afcb7b352ed054d98fdf83eae3333ec82c814b3e",
            "prepared_native_edge": [486, 601],
            "prepared_edge_weight_l1": prepared_cliff,
            "position_tolerance_m": POSITION_TOL,
            "weight_tolerance_l1": WEIGHT_TOL,
            "cliff_threshold_l1": CLIFF_L1,
            "proxy_interpolation": proxy_trace,
            "transfers": transfers,
            "canonical_asset_mutation": False,
            "canonical_generator_mutation": False,
            "runtime_npc_mutation": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True), flush=True)
        raise StopAfterVariantOne("variant01 source weight transfer complete")

    ExportService.create_character_copy = wrapped_create_copy
    TargetService.bake_targets = wrapped_bake_targets
    ExportService.bake_modifiers_remove_helpers = wrapped_bake_helpers
    ready._original_export_character = wrapped_export
    try:
        ready.base.main()
    except StopAfterVariantOne:
        pass
    finally:
        ExportService.create_character_copy = original_create_copy
        TargetService.bake_targets = original_bake_targets
        ExportService.bake_modifiers_remove_helpers = original_bake_helpers
        ready._original_export_character = original_export
    if result is None or not RESULT_PATH.is_file():
        raise RuntimeError("source weight transfer probe did not produce a result")


if __name__ == "__main__":
    main()
