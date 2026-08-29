#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import os
import struct
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_SOURCE_MAP_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

TARGET_GLB = "npc_gate_01.glb"
TARGET_SHA256 = "912ac8dedf4509640f90771f4c9d3b1af818b59261caab4d9b3f1fb0fe3e2ac9"
TARGET_SIZE = 15580240
TARGET_SEED = 53756543
OBJECT_FRAGMENT = "female_sportsuit01"
WEIGHT_TOL = 0.0001
POSITION_TOL = 0.0001
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


def l1(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in set(a) | set(b))


def euclidean(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def yup(v: tuple[float, float, float]) -> tuple[float, float, float]:
    return (v[0], v[2], -v[1])


def normalize_top4(weights: dict[str, float]) -> dict[str, float]:
    chosen = sorted(((float(w), name) for name, w in weights.items() if w > 0.0), reverse=True)[:4]
    total = sum(w for w, _ in chosen)
    if total <= 0.0:
        return {}
    return {name: w / total for w, name in chosen}


def vertex_weights(obj: bpy.types.Object, vertex: bpy.types.MeshVertex) -> dict[str, float]:
    groups = {group.index: group.name for group in obj.vertex_groups}
    result: dict[str, float] = {}
    for assignment in vertex.groups:
        name = groups.get(assignment.group)
        if name and assignment.weight > 0.0:
            result[name] = result.get(name, 0.0) + float(assignment.weight)
    return result


def native_edges(obj: bpy.types.Object) -> set[tuple[int, int]]:
    return {tuple(sorted((int(edge.vertices[0]), int(edge.vertices[1])))) for edge in obj.data.edges}


def snapshot_sportsuit(prepared_root: bpy.types.Object) -> dict[str, Any]:
    matches = [
        obj for obj in ready.base.descendants(prepared_root)
        if obj.type == "MESH" and OBJECT_FRAGMENT in obj.name.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one prepared sportsuit, got {[o.name for o in matches]}")
    obj = matches[0]
    edges = native_edges(obj)
    vertices = []
    for vertex in obj.data.vertices:
        local = tuple(float(v) for v in vertex.co)
        world_vec = obj.matrix_world @ vertex.co
        world = tuple(float(v) for v in world_vec)
        full = vertex_weights(obj, vertex)
        top4 = normalize_top4(full)
        vertices.append({
            "index": int(vertex.index),
            "local_xyz": local,
            "local_yup": yup(local),
            "world_xyz": world,
            "world_yup": yup(world),
            "full_weights": full,
            "top4_normalized": top4,
            "full_influence_count": len(full),
            "full_to_a_l1": l1(full, ENDPOINT_A),
            "full_to_b_l1": l1(full, ENDPOINT_B),
            "top4_to_a_l1": l1(top4, ENDPOINT_A),
            "top4_to_b_l1": l1(top4, ENDPOINT_B),
        })
    return {
        "object": obj.name,
        "vertex_count": len(vertices),
        "edge_count": len(edges),
        "edges": edges,
        "vertices": vertices,
    }


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
        raise RuntimeError("sparse accessor not allowed")
    view = document["bufferViews"][accessor["bufferView"]]
    component_type = int(accessor["componentType"])
    fmt, component_size = _COMPONENT[component_type]
    ncomp = _COMPONENT_COUNT[accessor["type"]]
    count = int(accessor["count"])
    element_size = component_size * ncomp
    stride = int(view.get("byteStride", element_size))
    base = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    unpack = struct.Struct("<" + fmt * ncomp)
    normalized = bool(accessor.get("normalized", False))
    result = []
    for index in range(count):
        raw = unpack.unpack_from(binary, base + index * stride)
        values = tuple(normalize_component(v, component_type) if normalized else v for v in raw)
        result.append(values[0] if ncomp == 1 else values)
    return result


def primitive_edges(indices: list[int]) -> set[tuple[int, int]]:
    edges: set[tuple[int, int]] = set()
    if len(indices) % 3:
        raise RuntimeError("triangle index count is not divisible by 3")
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


def nearest_prepared(snapshot: dict[str, Any], position: tuple[float, float, float]) -> dict[str, Any]:
    best = None
    for vertex in snapshot["vertices"]:
        for scheme in ("local_xyz", "local_yup", "world_xyz", "world_yup"):
            distance = euclidean(tuple(vertex[scheme]), position)
            if best is None or distance < best["distance"]:
                best = {"vertex": vertex, "scheme": scheme, "distance": distance}
    assert best is not None
    v = best["vertex"]
    return {
        "prepared_vertex": v["index"],
        "coordinate_scheme": best["scheme"],
        "position_distance": best["distance"],
        "full_influence_count": v["full_influence_count"],
        "full_weights": v["full_weights"],
        "top4_normalized": v["top4_normalized"],
        "full_to_a_l1": v["full_to_a_l1"],
        "full_to_b_l1": v["full_to_b_l1"],
        "top4_to_a_l1": v["top4_to_a_l1"],
        "top4_to_b_l1": v["top4_to_b_l1"],
    }


def trace_serialized_edge(path: Path, snapshot: dict[str, Any]) -> dict[str, Any]:
    document, binary = parse_glb(path)
    candidates = []
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        if OBJECT_FRAGMENT not in str(mesh.get("name", "")).lower():
            continue
        joint_names = joint_names_for_mesh(document, mesh_index)
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            attrs = primitive.get("attributes", {})
            if not {"POSITION", "JOINTS_0", "WEIGHTS_0"}.issubset(attrs):
                continue
            positions = read_accessor(document, binary, int(attrs["POSITION"]))
            joints = read_accessor(document, binary, int(attrs["JOINTS_0"]))
            weights = read_accessor(document, binary, int(attrs["WEIGHTS_0"]))
            indices = [int(v) for v in read_accessor(document, binary, int(primitive["indices"]))]
            edges = primitive_edges(indices)
            vectors = []
            for js, ws in zip(joints, weights):
                vector: dict[str, float] = {}
                for joint, weight in zip(js, ws):
                    value = float(weight)
                    if value > 0.0:
                        name = joint_names[int(joint)]
                        vector[name] = vector.get(name, 0.0) + value
                vectors.append(vector)
            a = {i for i, v in enumerate(vectors) if l1(v, ENDPOINT_A) <= WEIGHT_TOL}
            b = {i for i, v in enumerate(vectors) if l1(v, ENDPOINT_B) <= WEIGHT_TOL}
            for ai in sorted(a):
                for bi in sorted(b):
                    edge = tuple(sorted((ai, bi)))
                    if edge not in edges:
                        continue
                    apos = tuple(float(x) for x in positions[ai])
                    bpos = tuple(float(x) for x in positions[bi])
                    amap = nearest_prepared(snapshot, apos)
                    bmap = nearest_prepared(snapshot, bpos)
                    prepared_edge = tuple(sorted((amap["prepared_vertex"], bmap["prepared_vertex"])))
                    candidates.append({
                        "mesh_index": mesh_index,
                        "mesh_name": str(mesh.get("name", "")),
                        "primitive_index": primitive_index,
                        "gltf_edge": [ai, bi],
                        "gltf_a_position": apos,
                        "gltf_b_position": bpos,
                        "gltf_edge_weight_l1": l1(vectors[ai], vectors[bi]),
                        "a_map": amap,
                        "b_map": bmap,
                        "prepared_edge": list(prepared_edge),
                        "prepared_pair_is_native_edge": prepared_edge in snapshot["edges"],
                    })
    if not candidates:
        return {"diagnostic_state": "SERIALIZED_EDGE_SOURCE_MAP_NOT_FOUND", "candidates": []}
    resolved = [
        c for c in candidates
        if c["a_map"]["position_distance"] <= POSITION_TOL and c["b_map"]["position_distance"] <= POSITION_TOL
    ]
    native = [c for c in resolved if c["prepared_pair_is_native_edge"]]
    if native:
        state = "SERIALIZED_EDGE_MAPS_TO_NATIVE_PREEXPORT_CLIFF"
        next_axis = "MEASURE_SOURCE_WEIGHT_TRANSFER_BEFORE_EXPORT"
    elif resolved:
        state = "SERIALIZED_EDGE_MAPS_TO_NONADJACENT_PREPARED_VERTICES"
        next_axis = "TRACE_EXPORTER_VERTEX_MERGE_OR_INDEX_REMAP"
    else:
        state = "SERIALIZED_EDGE_POSITION_MAPPING_UNRESOLVED"
        next_axis = "TRACE_GLTF_NODE_TRANSFORMS_AND_MESH_COORDINATES"
    return {
        "diagnostic_state": state,
        "next_safe_axis": next_axis,
        "position_tolerance": POSITION_TOL,
        "candidate_count": len(candidates),
        "resolved_candidate_count": len(resolved),
        "native_candidate_count": len(native),
        "candidates": candidates,
    }


def main() -> None:
    original_export = ready._original_export_character
    captured = None

    def instrumented_export(prepared_root: bpy.types.Object, output_path: Path) -> dict:
        nonlocal captured
        if output_path.name != TARGET_GLB:
            raise RuntimeError(f"unexpected first export target: {output_path.name}")
        snapshot = snapshot_sportsuit(prepared_root)
        record = original_export(prepared_root, output_path)
        digest = sha256_path(output_path)
        size = output_path.stat().st_size
        if digest != TARGET_SHA256 or size != TARGET_SIZE or int(record["seed"]) != TARGET_SEED:
            raise RuntimeError("deterministic source regeneration drifted")
        source_map = trace_serialized_edge(output_path, snapshot)
        captured = {
            "format": "grand-bruxelles-gate8-variant01-export-source-map-v1",
            "diagnostic_state": source_map["diagnostic_state"],
            "generated_glb_sha256": digest,
            "generated_glb_size_bytes": size,
            "generated_seed": int(record["seed"]),
            "source_head_sha": "afcb7b352ed054d98fdf83eae3333ec82c814b3e",
            "predecessor_gltf_trace_artifact_id": 9714558072,
            "prepared_object": snapshot["object"],
            "prepared_vertex_count": snapshot["vertex_count"],
            "prepared_edge_count": snapshot["edge_count"],
            "source_map": source_map,
            "canonical_asset_mutation": False,
            "canonical_generator_mutation": False,
            "runtime_npc_mutation": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
            "next_safe_axis": source_map.get("next_safe_axis", "STOP_AND_INSPECT_SOURCE_MAP"),
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(captured, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(captured, sort_keys=True), flush=True)
        raise StopAfterVariantOne("variant01 export source map complete")

    ready._original_export_character = instrumented_export
    try:
        ready.base.main()
    except StopAfterVariantOne:
        pass
    if captured is None or not RESULT_PATH.is_file():
        raise RuntimeError("export source map did not produce a result")


if __name__ == "__main__":
    main()
