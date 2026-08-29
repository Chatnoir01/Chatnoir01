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
POSITION_TOL = 1e-4
WEIGHT_TOL = 1e-4
CLIFF_L1 = 1.7
MPFB_RELEASE = "2.0.17"
MPFB_RELEASE_COMMIT = "80919fa"
MPFB_WEIGHT_CUTOFF = 0.001


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


def find_effective_rig(root: bpy.types.Object, sportsuit: bpy.types.Object) -> bpy.types.Object:
    candidates: dict[int, bpy.types.Object] = {}
    for modifier in sportsuit.modifiers:
        rig = getattr(modifier, "object", None)
        if modifier.type == "ARMATURE" and rig is not None and rig.type == "ARMATURE":
            candidates[id(rig)] = rig
    if not candidates:
        for obj in [root, *ready.base.descendants(root)]:
            if obj.type == "ARMATURE":
                candidates[id(obj)] = obj
    if len(candidates) != 1:
        raise RuntimeError(f"expected exactly one effective rig, got {[obj.name for obj in candidates.values()]}")
    return next(iter(candidates.values()))


def mpfb_eligible_weights(values: dict[str, float], rig_bones: set[str]) -> dict[str, float]:
    return {
        name: float(value)
        for name, value in values.items()
        if name in rig_bones or name.startswith("DEF-") or name.startswith("mhmask-")
    }


def mpfb_interpolate(body_inputs: list[dict[str, Any]], rig_bones: set[str]) -> tuple[dict[str, float], float]:
    raw: dict[str, float] = {}
    coefficient_sum = sum(float(record["coefficient"]) for record in body_inputs)
    if abs(coefficient_sum) <= 1e-12:
        raise RuntimeError("MHCLO coefficient sum is zero")
    for record in body_inputs:
        coefficient = float(record["coefficient"])
        for bone, value in mpfb_eligible_weights(record["weights"], rig_bones).items():
            raw[bone] = raw.get(bone, 0.0) + coefficient * float(value)
    averaged = {bone: value / coefficient_sum for bone, value in raw.items()}
    return ({bone: value for bone, value in averaged.items() if value > MPFB_WEIGHT_CUTOFF}, coefficient_sum)


def proxy_interpolation_trace(root: bpy.types.Object) -> dict[str, Any]:
    sportsuit = find_sportsuit(root)
    body = find_hm08(root)
    rig = find_effective_rig(root, sportsuit)
    rig_bones = {str(bone.name) for bone in rig.data.bones}
    sportsuit_edges = {tuple(sorted((int(edge.vertices[0]), int(edge.vertices[1])))) for edge in sportsuit.data.edges}
    endpoint_records: dict[str, Any] = {}
    for endpoint, proxy in PROXY_ROWS.items():
        observed = weights(sportsuit, sportsuit.data.vertices[endpoint])
        body_records: list[dict[str, Any]] = []
        for body_vertex, coefficient in zip(proxy["body_vertices"], proxy["barycentric"]):
            source = weights(body, body.data.vertices[body_vertex])
            body_records.append(
                {
                    "vertex": int(body_vertex),
                    "coefficient": float(coefficient),
                    "weights": source,
                    "mpfb_eligible_weights": mpfb_eligible_weights(source, rig_bones),
                }
            )
        interpolated, coefficient_sum = mpfb_interpolate(body_records, rig_bones)
        endpoint_records[str(endpoint)] = {
            "sportsuit_vertex": int(endpoint),
            "observed_weights": observed,
            "body_inputs": body_records,
            "mhclo_coefficient_sum": coefficient_sum,
            "mpfb_interpolated_weights": interpolated,
            "mpfb_to_observed_l1": l1(interpolated, observed),
        }

    a, b = endpoint_records[str(PREPARED_ENDPOINTS[0])], endpoint_records[str(PREPARED_ENDPOINTS[1])]
    observed_cliff = l1(a["observed_weights"], b["observed_weights"])
    mpfb_cliff = l1(a["mpfb_interpolated_weights"], b["mpfb_interpolated_weights"])
    cross_pairs: list[dict[str, Any]] = []
    for source_a in a["body_inputs"]:
        for source_b in b["body_inputs"]:
            cross_pairs.append(
                {
                    "endpoint_a_body_vertex": int(source_a["vertex"]),
                    "endpoint_b_body_vertex": int(source_b["vertex"]),
                    "deform_weight_l1": l1(source_a["mpfb_eligible_weights"], source_b["mpfb_eligible_weights"]),
                }
            )
    cross_min = min(record["deform_weight_l1"] for record in cross_pairs)
    cross_max = max(record["deform_weight_l1"] for record in cross_pairs)
    max_mpfb_residual = max(record["mpfb_to_observed_l1"] for record in endpoint_records.values())
    amplified_beyond_source_cross_max = mpfb_cliff > cross_max + WEIGHT_TOL

    neighborhood: dict[str, Any] = {}
    for focal, neighbors in FOCAL_NEIGHBORS.items():
        focal_record = endpoint_records[str(focal)]
        edge_records = []
        for neighbor in neighbors:
            pair = tuple(sorted((focal, neighbor)))
            if pair not in sportsuit_edges:
                raise RuntimeError(f"expected source native edge missing: {focal}<->{neighbor}")
            neighbor_record = endpoint_records[str(neighbor)]
            observed_l1 = l1(focal_record["observed_weights"], neighbor_record["observed_weights"])
            interpolated_l1 = l1(
                focal_record["mpfb_interpolated_weights"],
                neighbor_record["mpfb_interpolated_weights"],
            )
            edge_records.append(
                {
                    "neighbor": int(neighbor),
                    "native_edge": True,
                    "observed_weight_l1": observed_l1,
                    "mpfb_interpolated_weight_l1": interpolated_l1,
                    "observed_is_cliff": observed_l1 >= CLIFF_L1,
                    "mpfb_interpolated_is_cliff": interpolated_l1 >= CLIFF_L1,
                }
            )
        neighborhood[str(focal)] = {
            "neighbors": edge_records,
            "native_degree": len(edge_records),
            "observed_cliff_neighbor_count": sum(1 for record in edge_records if record["observed_is_cliff"]),
            "mpfb_cliff_neighbor_count": sum(1 for record in edge_records if record["mpfb_interpolated_is_cliff"]),
            "observed_neighbor_l1_min": min(record["observed_weight_l1"] for record in edge_records),
            "observed_neighbor_l1_max": max(record["observed_weight_l1"] for record in edge_records),
        }

    if max_mpfb_residual <= WEIGHT_TOL and cross_min >= CLIFF_L1 and not amplified_beyond_source_cross_max:
        state = "SOURCE_SPORTSUIT_CLIFF_INHERITED_FROM_HM08_INPUT_REGIONS"
        next_axis = "TRACE_MHCLO_NATIVE_EDGE_SOURCE_REGION_MAPPING"
    elif max_mpfb_residual <= WEIGHT_TOL:
        state = "SOURCE_SPORTSUIT_WEIGHTS_MATCH_MPF_B_INTERPOLATION"
        next_axis = "TRACE_HM08_SOURCE_WEIGHT_INPUTS"
    else:
        state = "SOURCE_SPORTSUIT_WEIGHTS_NOT_EXPLAINED_BY_MPF_B_2_0_17_INTERPOLATION"
        next_axis = "TRACE_MPF_B_PROXY_WEIGHT_TRANSFER_IMPLEMENTATION"

    return {
        "diagnostic_state": state,
        "next_safe_axis": next_axis,
        "mpfb_release": MPFB_RELEASE,
        "mpfb_release_commit": MPFB_RELEASE_COMMIT,
        "mpfb_algorithm": "ClothesService.interpolate_weights",
        "mpfb_group_policy": "rig bones plus DEF-/mhmask- only",
        "mpfb_weight_cutoff": MPFB_WEIGHT_CUTOFF,
        "rig_object": rig.name,
        "rig_bone_count": len(rig_bones),
        "body_object": body.name,
        "body_vertex_count": len(body.data.vertices),
        "sportsuit_object": sportsuit.name,
        "sportsuit_vertex_count": len(sportsuit.data.vertices),
        "endpoint_records": endpoint_records,
        "observed_endpoint_cliff_l1": observed_cliff,
        "mpfb_interpolated_endpoint_cliff_l1": mpfb_cliff,
        "max_mpfb_to_observed_l1": max_mpfb_residual,
        "body_input_cross_endpoint_pairs": cross_pairs,
        "body_input_cross_endpoint_min_l1": cross_min,
        "body_input_cross_endpoint_max_l1": cross_max,
        "mpfb_cliff_amplified_beyond_source_cross_max": amplified_beyond_source_cross_max,
        "native_edge_neighborhood": neighborhood,
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
