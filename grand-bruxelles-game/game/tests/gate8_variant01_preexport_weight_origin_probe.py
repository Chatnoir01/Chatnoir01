#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
CONTRACT_PATH = Path(os.environ["GATE8_PREEXPORT_CONTRACT"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_PREEXPORT_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402


class StopAfterVariantOne(RuntimeError):
    pass


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def weight_vector(obj: bpy.types.Object, vertex_index: int) -> dict[str, float]:
    vertex = obj.data.vertices[vertex_index]
    groups = {group.index: group.name for group in obj.vertex_groups}
    result: dict[str, float] = {}
    for assignment in vertex.groups:
        name = groups.get(assignment.group)
        weight = float(assignment.weight)
        if name is not None and weight > 0.0:
            result[name] = weight
    return result


def vector_l1(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(abs(a.get(key, 0.0) - b.get(key, 0.0)) for key in set(a) | set(b))


def rounded_weights(weights: dict[str, float]) -> dict[str, float]:
    return {name: round(value, 12) for name, value in sorted(weights.items())}


def inspect_preexport(prepared_root: bpy.types.Object, contract: dict) -> dict:
    expected_a = {str(k): float(v) for k, v in contract["endpoint_a_weights"].items()}
    expected_b = {str(k): float(v) for k, v in contract["endpoint_b_weights"].items()}
    vector_tol = float(contract["weight_vector_l1_match_tolerance"])
    edge_tol = float(contract["edge_l1_match_tolerance"])
    expected_edge_l1 = float(contract["exported_target"]["target_edge_weight_l1"])
    name_fragment = str(contract["required_object_name_fragment"]).lower()

    object_summaries: list[dict] = []
    edge_matches: list[dict] = []
    coface_matches: list[dict] = []

    for obj in ready.base.descendants(prepared_root):
        if obj.type != "MESH":
            continue

        vectors = [weight_vector(obj, vertex.index) for vertex in obj.data.vertices]
        a_candidates = {
            idx: vector_l1(weights, expected_a)
            for idx, weights in enumerate(vectors)
            if vector_l1(weights, expected_a) <= vector_tol
        }
        b_candidates = {
            idx: vector_l1(weights, expected_b)
            for idx, weights in enumerate(vectors)
            if vector_l1(weights, expected_b) <= vector_tol
        }

        native_edges = {
            tuple(sorted((int(edge.vertices[0]), int(edge.vertices[1]))))
            for edge in obj.data.edges
        }
        polygons_by_vertex: dict[int, set[int]] = {}
        polygon_vertices: dict[int, list[int]] = {}
        for polygon in obj.data.polygons:
            vertices = [int(index) for index in polygon.vertices]
            polygon_vertices[int(polygon.index)] = vertices
            for index in vertices:
                polygons_by_vertex.setdefault(index, set()).add(int(polygon.index))

        cliff_count = 0
        max_edge_l1 = -1.0
        max_edge: tuple[int, int] | None = None
        for edge in obj.data.edges:
            i, j = int(edge.vertices[0]), int(edge.vertices[1])
            edge_l1 = vector_l1(vectors[i], vectors[j])
            if edge_l1 >= 1.7:
                cliff_count += 1
            if edge_l1 > max_edge_l1:
                max_edge_l1 = edge_l1
                max_edge = (i, j)

            orientation = None
            if i in a_candidates and j in b_candidates:
                orientation = (i, j, a_candidates[i], b_candidates[j])
            elif j in a_candidates and i in b_candidates:
                orientation = (j, i, a_candidates[j], b_candidates[i])
            if orientation is None:
                continue

            a_idx, b_idx, a_distance, b_distance = orientation
            pair_l1 = vector_l1(vectors[a_idx], vectors[b_idx])
            edge_matches.append(
                {
                    "object": obj.name,
                    "object_matches_required_fragment": name_fragment in obj.name.lower(),
                    "vertex_a": a_idx,
                    "vertex_b": b_idx,
                    "endpoint_a_distance_l1": a_distance,
                    "endpoint_b_distance_l1": b_distance,
                    "edge_weight_l1": pair_l1,
                    "edge_l1_matches_exported": abs(pair_l1 - expected_edge_l1) <= edge_tol,
                    "endpoint_a_weights": rounded_weights(vectors[a_idx]),
                    "endpoint_b_weights": rounded_weights(vectors[b_idx]),
                }
            )

        for a_idx, a_distance in a_candidates.items():
            for b_idx, b_distance in b_candidates.items():
                shared = sorted(
                    polygons_by_vertex.get(a_idx, set())
                    & polygons_by_vertex.get(b_idx, set())
                )
                if not shared:
                    continue
                pair_l1 = vector_l1(vectors[a_idx], vectors[b_idx])
                pair = tuple(sorted((a_idx, b_idx)))
                coface_matches.append(
                    {
                        "object": obj.name,
                        "object_matches_required_fragment": name_fragment in obj.name.lower(),
                        "vertex_a": a_idx,
                        "vertex_b": b_idx,
                        "endpoint_a_distance_l1": a_distance,
                        "endpoint_b_distance_l1": b_distance,
                        "native_edge": pair in native_edges,
                        "shared_polygon_indices": shared,
                        "shared_polygons": [polygon_vertices[index] for index in shared],
                        "edge_weight_l1": pair_l1,
                        "edge_l1_matches_exported": abs(pair_l1 - expected_edge_l1) <= edge_tol,
                        "endpoint_a_weights": rounded_weights(vectors[a_idx]),
                        "endpoint_b_weights": rounded_weights(vectors[b_idx]),
                    }
                )

        object_summaries.append(
            {
                "object": obj.name,
                "vertex_count": len(obj.data.vertices),
                "edge_count": len(obj.data.edges),
                "polygon_count": len(obj.data.polygons),
                "target_a_candidate_count": len(a_candidates),
                "target_b_candidate_count": len(b_candidates),
                "target_a_candidates": sorted(a_candidates),
                "target_b_candidates": sorted(b_candidates),
                "cliff_edge_count_ge_1_7": cliff_count,
                "max_edge_l1": max_edge_l1,
                "max_edge": list(max_edge) if max_edge is not None else None,
            }
        )

    valid_edges = [
        match
        for match in edge_matches
        if match["object_matches_required_fragment"] and match["edge_l1_matches_exported"]
    ]
    valid_cofaces = [
        match
        for match in coface_matches
        if match["object_matches_required_fragment"]
        and match["edge_l1_matches_exported"]
        and not match["native_edge"]
    ]
    return {
        "objects": object_summaries,
        "matching_preexport_edges": edge_matches,
        "matching_preexport_cofaces": coface_matches,
        "valid_preexport_matches": valid_edges,
        "valid_preexport_coface_matches": valid_cofaces,
    }


def main() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract["format"] != "grand-bruxelles-gate8-variant01-preexport-weight-origin-v1":
        raise RuntimeError("unexpected contract format")
    if int(contract["candidate_variant"]) != 1:
        raise RuntimeError("this probe is frozen to Gate-8 variant 01")

    original_export = ready._original_export_character
    captured: dict | None = None

    def instrumented_export(prepared_root: bpy.types.Object, output_path: Path) -> dict:
        nonlocal captured
        if output_path.name != contract["exported_target"]["glb"]:
            raise RuntimeError(f"unexpected first export target: {output_path.name}")

        preexport = inspect_preexport(prepared_root, contract)
        record = original_export(prepared_root, output_path)
        generated_sha = sha256_path(output_path)
        generated_size = output_path.stat().st_size

        valid_edges = preexport["valid_preexport_matches"]
        valid_cofaces = preexport["valid_preexport_coface_matches"]
        if generated_sha != contract["exported_target"]["sha256"]:
            state = "SOURCE_REGEN_DRIFTED_FROM_FROZEN_GLB"
        elif generated_size != int(contract["exported_target"]["size_bytes"]):
            state = "SOURCE_REGEN_DRIFTED_FROM_FROZEN_GLB"
        elif valid_edges:
            state = "PRE_EXPORT_WEIGHT_DISCONTINUITY_CONFIRMED"
        elif valid_cofaces:
            state = "PRE_EXPORT_COFACE_WEIGHT_CLIFF_CONFIRMED"
        else:
            state = "PRE_EXPORT_TARGET_EDGE_NOT_REPRODUCED"

        captured = {
            "format": "grand-bruxelles-gate8-variant01-preexport-weight-origin-result-v2",
            "diagnostic_state": state,
            "candidate_variant": 1,
            "source_head_sha": contract["source_generation"]["head_sha"],
            "blender_version": bpy.app.version_string,
            "generated_glb": output_path.name,
            "generated_glb_sha256": generated_sha,
            "generated_glb_size_bytes": generated_size,
            "generated_seed": int(record["seed"]),
            "frozen_exported_target_sha256": contract["exported_target"]["sha256"],
            "frozen_exported_target_edge_weight_l1": contract["exported_target"]["target_edge_weight_l1"],
            "preexport": preexport,
            "canonical_asset_mutation": False,
            "canonical_generator_mutation": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
            "next_safe_axis": (
                "LOCATE_MPF_BASIS_OR_PROXY_WEIGHT_SOURCE_BEFORE_EXPORT_PREP"
                if state == "PRE_EXPORT_WEIGHT_DISCONTINUITY_CONFIRMED"
                else "MAP_GLTF_TRIANGULATION_OF_COFACE_TO_EXPORTED_TARGET_EDGE"
                if state == "PRE_EXPORT_COFACE_WEIGHT_CLIFF_CONFIRMED"
                else "TRACE_GLTF_EXPORT_VERTEX_WEIGHT_TRANSFORMATION"
                if state == "PRE_EXPORT_TARGET_EDGE_NOT_REPRODUCED"
                else "REESTABLISH_DETERMINISTIC_SOURCE_REGEN_BEFORE_ORIGIN_DIAGNOSIS"
            ),
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(captured, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(captured, sort_keys=True), flush=True)
        raise StopAfterVariantOne("variant01 source-origin witness complete")

    ready._original_export_character = instrumented_export
    try:
        ready.base.main()
    except StopAfterVariantOne:
        pass

    if captured is None or not RESULT_PATH.is_file():
        raise RuntimeError("variant01 pre-export witness did not produce a result")


if __name__ == "__main__":
    main()
