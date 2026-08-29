#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import struct
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_GLTF_TRACE_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

TARGET_GLB = "npc_gate_01.glb"
TARGET_SHA256 = "912ac8dedf4509640f90771f4c9d3b1af818b59261caab4d9b3f1fb0fe3e2ac9"
TARGET_SIZE = 15580240
TARGET_SEED = 53756543
OBJECT_FRAGMENT = "female_sportsuit01"
GODOT_TARGET_EDGE = tuple(sorted((416, 758)))
WEIGHT_TOL = 0.0001
ENDPOINT_A = {"clavicle_r": 0.00614938605576754, "upperarm_r": 0.99383533000946}
ENDPOINT_B = {
    "spine_01": 0.00190737773664296,
    "spine_02": 0.0763256251811981,
    "spine_03": 0.834409117698669,
    "upperarm_r": 0.0873273834586143,
}

_COMPONENT = {
    5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
    5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
}
_COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


class StopAfterVariantOne(RuntimeError):
    pass


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def vector_l1(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in set(a) | set(b))


def parse_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    blob = path.read_bytes()
    if len(blob) < 20 or blob[:4] != b"glTF":
        raise RuntimeError("not a GLB container")
    version, total_length = struct.unpack_from("<II", blob, 4)
    if version != 2 or total_length != len(blob):
        raise RuntimeError("unexpected GLB header")
    offset = 12
    document = None
    binary = b""
    while offset < len(blob):
        chunk_length, chunk_type = struct.unpack_from("<II", blob, offset)
        offset += 8
        chunk = blob[offset:offset + chunk_length]
        offset += chunk_length
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.rstrip(b" \t\r\n\x00").decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = chunk
    if document is None or not binary:
        raise RuntimeError("GLB JSON/BIN chunk missing")
    return document, binary


def normalize_component(value: int | float, component_type: int) -> float:
    if component_type == 5120:
        return max(float(value) / 127.0, -1.0)
    if component_type == 5121:
        return float(value) / 255.0
    if component_type == 5122:
        return max(float(value) / 32767.0, -1.0)
    if component_type == 5123:
        return float(value) / 65535.0
    return float(value)


def read_accessor(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[Any]:
    accessor = document["accessors"][accessor_index]
    if "sparse" in accessor:
        raise RuntimeError("sparse accessor not allowed in frozen witness")
    view = document["bufferViews"][accessor["bufferView"]]
    component_type = int(accessor["componentType"])
    fmt, component_size = _COMPONENT[component_type]
    count_components = _COMPONENT_COUNT[accessor["type"]]
    count = int(accessor["count"])
    element_size = component_size * count_components
    stride = int(view.get("byteStride", element_size))
    base = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    unpack = struct.Struct("<" + fmt * count_components)
    normalized = bool(accessor.get("normalized", False))
    result = []
    for index in range(count):
        raw = unpack.unpack_from(binary, base + index * stride)
        values = tuple(normalize_component(v, component_type) if normalized else v for v in raw)
        result.append(values[0] if count_components == 1 else values)
    return result


def primitive_edges(indices: list[int]) -> set[tuple[int, int]]:
    if len(indices) % 3:
        raise RuntimeError("triangle index count is not divisible by 3")
    edges: set[tuple[int, int]] = set()
    for offset in range(0, len(indices), 3):
        a, b, c = indices[offset:offset + 3]
        edges.update({tuple(sorted((a, b))), tuple(sorted((b, c))), tuple(sorted((c, a)))})
    return edges


def joint_names_for_mesh(document: dict[str, Any], mesh_index: int) -> list[str]:
    nodes = document.get("nodes", [])
    matching = [n for n in nodes if int(n.get("mesh", -1)) == mesh_index and "skin" in n]
    if len(matching) != 1:
        raise RuntimeError(f"expected one skinned node for mesh {mesh_index}, got {len(matching)}")
    skin = document["skins"][int(matching[0]["skin"])]
    return [str(nodes[int(i)].get("name", f"node_{i}")) for i in skin["joints"]]


def trace_glb(path: Path) -> dict[str, Any]:
    document, binary = parse_glb(path)
    primitive_records = []
    profile_pairs = []
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        mesh_name = str(mesh.get("name", ""))
        if OBJECT_FRAGMENT not in mesh_name.lower():
            continue
        joint_names = joint_names_for_mesh(document, mesh_index)
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            if int(primitive.get("mode", 4)) != 4:
                raise RuntimeError("sportsuit primitive is not TRIANGLES")
            attrs = primitive.get("attributes", {})
            if not {"POSITION", "JOINTS_0", "WEIGHTS_0"}.issubset(attrs):
                continue
            positions = read_accessor(document, binary, int(attrs["POSITION"]))
            joints = read_accessor(document, binary, int(attrs["JOINTS_0"]))
            weights = read_accessor(document, binary, int(attrs["WEIGHTS_0"]))
            if not (len(positions) == len(joints) == len(weights)):
                raise RuntimeError("primitive attribute count mismatch")
            indices = [int(v) for v in read_accessor(document, binary, int(primitive["indices"]))] if "indices" in primitive else list(range(len(positions)))
            edges = primitive_edges(indices)
            vectors = []
            for js, ws in zip(joints, weights):
                if not isinstance(js, tuple) or not isinstance(ws, tuple):
                    raise RuntimeError("JOINTS_0/WEIGHTS_0 must be VEC4")
                vector: dict[str, float] = {}
                for joint, weight in zip(js, ws):
                    value = float(weight)
                    if value <= 0.0:
                        continue
                    name = joint_names[int(joint)]
                    vector[name] = vector.get(name, 0.0) + value
                vectors.append(vector)
            a_candidates = {i: vector_l1(v, ENDPOINT_A) for i, v in enumerate(vectors) if vector_l1(v, ENDPOINT_A) <= WEIGHT_TOL}
            b_candidates = {i: vector_l1(v, ENDPOINT_B) for i, v in enumerate(vectors) if vector_l1(v, ENDPOINT_B) <= WEIGHT_TOL}
            primitive_records.append({
                "mesh_index": mesh_index,
                "mesh_name": mesh_name,
                "primitive_index": primitive_index,
                "vertex_count": len(vectors),
                "triangle_count": len(indices) // 3,
                "a_candidates": sorted(a_candidates),
                "b_candidates": sorted(b_candidates),
                "godot_target_indices_in_range": GODOT_TARGET_EDGE[1] < len(vectors),
                "godot_target_pair_is_gltf_edge": GODOT_TARGET_EDGE in edges if GODOT_TARGET_EDGE[1] < len(vectors) else False,
            })
            for a_idx, a_distance in a_candidates.items():
                for b_idx, b_distance in b_candidates.items():
                    pair = tuple(sorted((a_idx, b_idx)))
                    profile_pairs.append({
                        "mesh_index": mesh_index,
                        "mesh_name": mesh_name,
                        "primitive_index": primitive_index,
                        "vertex_a": a_idx,
                        "vertex_b": b_idx,
                        "endpoint_a_distance_l1": a_distance,
                        "endpoint_b_distance_l1": b_distance,
                        "pair_is_triangle_edge": pair in edges,
                        "pair_equals_godot_target_indices": pair == GODOT_TARGET_EDGE,
                        "endpoint_a_position": [round(float(v), 9) for v in positions[a_idx]],
                        "endpoint_b_position": [round(float(v), 9) for v in positions[b_idx]],
                    })
    adjacent = [p for p in profile_pairs if p["pair_is_triangle_edge"]]
    exact = [p for p in profile_pairs if p["pair_equals_godot_target_indices"]]
    if adjacent:
        state = "GLTF_TARGET_WEIGHT_EDGE_REPRODUCED"
        next_axis = "MAP_GLTF_EDGE_BACK_TO_PREPARED_LOOP_SPLITS"
    elif profile_pairs:
        state = "GLTF_TARGET_PROFILES_PRESENT_NOT_ADJACENT"
        next_axis = "TRACE_GODOT_IMPORT_VERTEX_TOPOLOGY_TRANSFORMATION"
    else:
        state = "GLTF_TARGET_PROFILE_MAPPING_NOT_FOUND"
        next_axis = "TRACE_GLTF_SKIN_WEIGHT_QUANTIZATION_OR_JOINT_REMAP"
    return {
        "diagnostic_state": state,
        "next_safe_axis": next_axis,
        "mesh_primitive_records": primitive_records,
        "matching_profile_pairs": profile_pairs,
        "adjacent_matching_profile_pairs": adjacent,
        "exact_godot_index_profile_pairs": exact,
    }


def main() -> None:
    original_export = ready._original_export_character
    captured = None

    def instrumented_export(prepared_root: bpy.types.Object, output_path: Path) -> dict:
        nonlocal captured
        if output_path.name != TARGET_GLB:
            raise RuntimeError(f"unexpected first export target: {output_path.name}")
        record = original_export(prepared_root, output_path)
        digest = sha256_path(output_path)
        size = output_path.stat().st_size
        if digest != TARGET_SHA256 or size != TARGET_SIZE or int(record["seed"]) != TARGET_SEED:
            raise RuntimeError("deterministic source regeneration drifted")
        trace = trace_glb(output_path)
        captured = {
            "format": "grand-bruxelles-gate8-variant01-gltf-weight-trace-result-v1",
            "diagnostic_state": trace["diagnostic_state"],
            "generated_glb_sha256": digest,
            "generated_glb_size_bytes": size,
            "generated_seed": int(record["seed"]),
            "source_head_sha": "afcb7b352ed054d98fdf83eae3333ec82c814b3e",
            "prior_preexport_artifact_id": 9713849514,
            "prior_preexport_state": "PRE_EXPORT_TARGET_EDGE_NOT_REPRODUCED",
            "trace": trace,
            "canonical_asset_mutation": False,
            "canonical_generator_mutation": False,
            "runtime_npc_mutation": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
            "next_safe_axis": trace["next_safe_axis"],
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(captured, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(captured, sort_keys=True), flush=True)
        raise StopAfterVariantOne("variant01 glTF weight trace complete")

    ready._original_export_character = instrumented_export
    try:
        ready.base.main()
    except StopAfterVariantOne:
        pass
    if captured is None or not RESULT_PATH.is_file():
        raise RuntimeError("glTF weight trace did not produce a result")


if __name__ == "__main__":
    main()
