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


def find_sportsuit(root: bpy.types.Object) -> bpy.types.Object:
    matches = [
        obj for obj in ready.base.descendants(root)
        if obj.type == "MESH" and OBJECT_FRAGMENT in obj.name.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one sportsuit under {root.name}, got {[o.name for o in matches]}")
    return matches[0]


def snapshot(root: bpy.types.Object, stage: str) -> dict[str, Any]:
    obj = find_sportsuit(root)
    edges = {tuple(sorted((int(e.vertices[0]), int(e.vertices[1])))) for e in obj.data.edges}
    vertices = []
    for vertex in obj.data.vertices:
        local = tuple(float(v) for v in vertex.co)
        world_v = obj.matrix_world @ vertex.co
        world = tuple(float(v) for v in world_v)
        vertices.append({
            "index": int(vertex.index),
            "local_xyz": local,
            "world_xyz": world,
            "weights": weights(obj, vertex),
        })
    return {
        "stage": stage,
        "object": obj.name,
        "vertex_count": len(vertices),
        "edge_count": len(edges),
        "matrix_world": [[float(v) for v in row] for row in obj.matrix_world],
        "edges": edges,
        "vertices": vertices,
    }


def distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def map_endpoint(target: dict[str, Any], earlier: dict[str, Any]) -> dict[str, Any]:
    target_local = tuple(target["local_xyz"])
    ranked = sorted(
        (
            distance(target_local, tuple(v["local_xyz"])),
            v,
        )
        for v in earlier["vertices"]
    )
    best_distance, best = ranked[0]
    return {
        "vertex": int(best["index"]),
        "position_distance_m": float(best_distance),
        "weights": best["weights"],
        "weight_delta_to_prepared_l1": l1(best["weights"], target["weights"]),
    }


def stage_transfer(prepared: dict[str, Any], earlier: dict[str, Any]) -> dict[str, Any]:
    pa = prepared["vertices"][PREPARED_ENDPOINTS[0]]
    pb = prepared["vertices"][PREPARED_ENDPOINTS[1]]
    ma = map_endpoint(pa, earlier)
    mb = map_endpoint(pb, earlier)
    pair = tuple(sorted((ma["vertex"], mb["vertex"])))
    edge_native = pair in earlier["edges"]
    cliff = l1(ma["weights"], mb["weights"])
    return {
        "stage": earlier["stage"],
        "mapped_vertices": [ma["vertex"], mb["vertex"]],
        "mapped_pair_is_native_edge": edge_native,
        "endpoint_a": ma,
        "endpoint_b": mb,
        "mapped_edge_weight_l1": cliff,
        "mapped_edge_is_cliff": cliff >= CLIFF_L1,
        "positions_resolved": ma["position_distance_m"] <= POSITION_TOL and mb["position_distance_m"] <= POSITION_TOL,
    }


def main() -> None:
    mpfb = ready.base.resolve_mpfb_module()
    services = importlib.import_module(mpfb.__package__ + ".services")
    ExportService = services.ExportService
    TargetService = services.TargetService

    original_create_copy = ExportService.create_character_copy
    original_bake_targets = TargetService.bake_targets
    original_bake_helpers = ExportService.bake_modifiers_remove_helpers
    original_export = ready._original_export_character

    captured: dict[str, dict[str, Any]] = {}
    result: dict[str, Any] | None = None
    active_copy_root: bpy.types.Object | None = None

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal active_copy_root
        if not captured:
            captured["source_before_copy"] = snapshot(root, "source_before_copy")
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
        digest = sha256_path(output_path)
        size = output_path.stat().st_size
        if digest != TARGET_SHA256 or size != TARGET_SIZE or int(record["seed"]) != TARGET_SEED:
            raise RuntimeError("deterministic variant01 regeneration drifted")

        for index in PREPARED_ENDPOINTS:
            if index >= prepared["vertex_count"]:
                raise RuntimeError(f"prepared endpoint {index} outside sportsuit vertex range")
        prepared_edge = tuple(sorted(PREPARED_ENDPOINTS))
        if prepared_edge not in prepared["edges"]:
            raise RuntimeError("prepared 486-601 edge is no longer native")
        prepared_cliff = l1(
            prepared["vertices"][PREPARED_ENDPOINTS[0]]["weights"],
            prepared["vertices"][PREPARED_ENDPOINTS[1]]["weights"],
        )
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
            state = "SOURCE_WEIGHT_TRANSFER_POSITION_MAPPING_UNRESOLVED"
            next_axis = "TRACE_SOURCE_TO_EXPORT_COPY_VERTEX_MAPPING"
        else:
            cliff_stages = [t["stage"] for t in transfers if t["mapped_edge_is_cliff"]]
            if "source_before_copy" in cliff_stages:
                state = "SOURCE_SPORTSUIT_WEIGHT_CLIFF_ALREADY_PRESENT"
                next_axis = "TRACE_SOURCE_ASSET_WEIGHT_ORIGIN"
            else:
                first_cliff = next((t["stage"] for t in transfers if t["mapped_edge_is_cliff"]), None)
                if first_cliff == "copy_after_create":
                    state = "WEIGHT_CLIFF_INTRODUCED_BY_EXPORT_COPY"
                    next_axis = "ISOLATE_CREATE_CHARACTER_COPY_WEIGHT_MUTATION"
                elif first_cliff in {"copy_after_target_bake", "copy_before_helper_bake"}:
                    state = "WEIGHT_CLIFF_INTRODUCED_DURING_TARGET_BAKE"
                    next_axis = "ISOLATE_TARGET_BAKE_PROXY_WEIGHT_MUTATION"
                elif first_cliff == "copy_after_helper_bake":
                    state = "WEIGHT_CLIFF_INTRODUCED_DURING_HELPER_BAKE"
                    next_axis = "ISOLATE_BAKE_MODIFIERS_PROXY_WEIGHT_MUTATION"
                else:
                    state = "SOURCE_WEIGHT_TRANSFER_STAGE_NOT_IDENTIFIED"
                    next_axis = "STOP_AND_INSPECT_WEIGHT_TRANSFER"

        result = {
            "format": "grand-bruxelles-gate8-variant01-source-weight-transfer-v1",
            "diagnostic_state": state,
            "next_safe_axis": next_axis,
            "generated_glb_sha256": digest,
            "generated_glb_size_bytes": size,
            "generated_seed": int(record["seed"]),
            "source_head_sha": "afcb7b352ed054d98fdf83eae3333ec82c814b3e",
            "prepared_native_edge": list(PREPARED_ENDPOINTS),
            "prepared_edge_weight_l1": prepared_cliff,
            "position_tolerance_m": POSITION_TOL,
            "weight_tolerance_l1": WEIGHT_TOL,
            "cliff_threshold_l1": CLIFF_L1,
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
