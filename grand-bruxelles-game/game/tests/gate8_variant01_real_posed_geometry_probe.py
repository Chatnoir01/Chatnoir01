#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import bpy
from mathutils import Vector

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
EVIDENCE_PATH = Path(os.environ["GATE8_REMATCH_EVIDENCE"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_REAL_POSE_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

OBJECT_FRAGMENT = "female_sportsuit01"
FOCUS_VERTICES = (377, 378, 379, 486, 599, 601, 615, 864)
LOCAL_EDGES = (
    (377, 486),
    (379, 486),
    (486, 601),
    (486, 864),
    (378, 601),
    (599, 601),
    (601, 615),
)
CRITICAL_EDGES = {(486, 601), (599, 601), (601, 615)}
POSE_DEGREES = {
    "upperarm_r": 35.0,
    "clavicle_r": 12.0,
    "spine_03": 4.0,
    "spine_02": 2.0,
    "spine_01": 0.0,
}


class StopAfterMeasurement(RuntimeError):
    pass


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
        raise RuntimeError(f"expected one sportsuit, got {[obj.name for obj in matches]}")
    return matches[0]


def find_rig(root: bpy.types.Object, sportsuit: bpy.types.Object) -> bpy.types.Object:
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
        raise RuntimeError(f"expected one effective rig, got {[obj.name for obj in candidates.values()]}")
    return next(iter(candidates.values()))


def duplicate_mesh(source: bpy.types.Object, name: str) -> bpy.types.Object:
    clone = source.copy()
    clone.data = source.data.copy()
    clone.name = name
    clone.data.name = name + "_mesh"
    bpy.context.scene.collection.objects.link(clone)
    return clone


def set_vertex_weights(obj: bpy.types.Object, vertex_index: int, weights: dict[str, float]) -> None:
    for group in obj.vertex_groups:
        try:
            group.remove([vertex_index])
        except RuntimeError:
            pass
    total = sum(float(v) for v in weights.values() if float(v) > 0.0)
    if total <= 1e-12:
        raise RuntimeError(f"zero deform weight sum for vertex {vertex_index}")
    for name, value in weights.items():
        value = float(value)
        if value <= 0.0:
            continue
        group = obj.vertex_groups.get(name)
        if group is None:
            group = obj.vertex_groups.new(name=name)
        group.add([vertex_index], value / total, "REPLACE")


def apply_pose(rig: bpy.types.Object) -> None:
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    for bone_name, degrees in POSE_DEGREES.items():
        pose_bone = rig.pose.bones.get(bone_name)
        if pose_bone is None:
            raise RuntimeError(f"pose bone missing: {bone_name}")
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler[2] = math.radians(degrees)
    bpy.context.view_layer.update()


def evaluated_world_positions(obj: bpy.types.Object) -> list[Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        if len(mesh.vertices) != len(obj.data.vertices):
            raise RuntimeError(
                f"topology changed through modifiers for {obj.name}: "
                f"{len(obj.data.vertices)} -> {len(mesh.vertices)}"
            )
        matrix = evaluated.matrix_world.copy()
        return [matrix @ vertex.co.copy() for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def rest_world_positions(obj: bpy.types.Object) -> list[Vector]:
    matrix = obj.matrix_world.copy()
    return [matrix @ vertex.co.copy() for vertex in obj.data.vertices]


def polygon_normal(points: list[Vector]) -> Vector:
    if len(points) < 3:
        return Vector((0.0, 0.0, 0.0))
    normal = Vector((0.0, 0.0, 0.0))
    for index, current in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        normal.x += (current.y - nxt.y) * (current.z + nxt.z)
        normal.y += (current.z - nxt.z) * (current.x + nxt.x)
        normal.z += (current.x - nxt.x) * (current.y + nxt.y)
    return normal


def edge_record(a: int, b: int, rest: list[Vector], stored: list[Vector], rematched: list[Vector]) -> dict[str, Any]:
    rest_len = float((rest[a] - rest[b]).length)
    stored_len = float((stored[a] - stored[b]).length)
    rematched_len = float((rematched[a] - rematched[b]).length)
    if rest_len <= 1e-9:
        raise RuntimeError(f"degenerate rest edge {a}<->{b}")
    stored_ratio = stored_len / rest_len
    rematched_ratio = rematched_len / rest_len
    return {
        "edge": [a, b],
        "critical": (a, b) in CRITICAL_EDGES,
        "rest_length_m": rest_len,
        "stored_posed_length_m": stored_len,
        "rematched_posed_length_m": rematched_len,
        "stored_stretch_ratio": stored_ratio,
        "rematched_stretch_ratio": rematched_ratio,
        "stored_abs_strain": abs(stored_ratio - 1.0),
        "rematched_abs_strain": abs(rematched_ratio - 1.0),
    }


def incident_polygons(obj: bpy.types.Object) -> list[bpy.types.MeshPolygon]:
    edge_keys = {frozenset(edge) for edge in LOCAL_EDGES}
    out: list[bpy.types.MeshPolygon] = []
    for polygon in obj.data.polygons:
        verts = list(map(int, polygon.vertices))
        polygon_edges = {
            frozenset((verts[i], verts[(i + 1) % len(verts)]))
            for i in range(len(verts))
        }
        if edge_keys & polygon_edges:
            out.append(polygon)
    if not out:
        raise RuntimeError("no source polygons incident to reviewed shoulder edges")
    return out


def inversion_records(
    obj: bpy.types.Object,
    rest: list[Vector],
    stored: list[Vector],
    rematched: list[Vector],
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for polygon in incident_polygons(obj):
        verts = list(map(int, polygon.vertices))
        rest_n = polygon_normal([rest[v] for v in verts])
        stored_n = polygon_normal([stored[v] for v in verts])
        rematched_n = polygon_normal([rematched[v] for v in verts])
        if min(rest_n.length, stored_n.length, rematched_n.length) <= 1e-12:
            raise RuntimeError(f"degenerate polygon normal at polygon {polygon.index}")
        stored_dot = float(rest_n.normalized().dot(stored_n.normalized()))
        rematched_dot = float(rest_n.normalized().dot(rematched_n.normalized()))
        records.append(
            {
                "polygon_index": int(polygon.index),
                "vertices": verts,
                "stored_rest_normal_dot": stored_dot,
                "rematched_rest_normal_dot": rematched_dot,
                "stored_inverted": stored_dot < 0.0,
                "rematched_inverted": rematched_dot < 0.0,
            }
        )
    return records


def displacement_records(rest: list[Vector], stored: list[Vector], rematched: list[Vector]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for vertex_index in FOCUS_VERTICES:
        stored_displacement = float((stored[vertex_index] - rest[vertex_index]).length)
        rematched_displacement = float((rematched[vertex_index] - rest[vertex_index]).length)
        variant_delta = float((rematched[vertex_index] - stored[vertex_index]).length)
        out[str(vertex_index)] = {
            "stored_displacement_m": stored_displacement,
            "rematched_displacement_m": rematched_displacement,
            "stored_vs_rematched_delta_m": variant_delta,
        }
    return out


def main() -> None:
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    if evidence.get("format") != "grand-bruxelles-gate8-variant01-mhclo-rematch-v2":
        raise RuntimeError("unexpected rematch evidence format")
    if evidence.get("mpfb_release") != "2.0.17" or evidence.get("mpfb_release_commit") != "80919fa":
        raise RuntimeError("unexpected MPFB provenance")
    records = evidence["records"]
    if set(records) != {str(v) for v in FOCUS_VERTICES}:
        raise RuntimeError("reviewed focus-vertex set drifted")

    mpfb = ready.base.resolve_mpfb_module()
    services = __import__(mpfb.__package__ + ".services", fromlist=["ExportService"])
    ExportService = services.ExportService
    original_create_copy = ExportService.create_character_copy
    measured: dict[str, Any] | None = None

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal measured
        sportsuit = find_sportsuit(root)
        rig = find_rig(root, sportsuit)
        if len(sportsuit.data.vertices) != 1797:
            raise RuntimeError(f"sportsuit vertex count drifted: {len(sportsuit.data.vertices)}")
        if len(rig.data.bones) != 53:
            raise RuntimeError(f"rig bone count drifted: {len(rig.data.bones)}")

        stored_variant = duplicate_mesh(sportsuit, "gate8_probe_stored_weights")
        rematched_variant = duplicate_mesh(sportsuit, "gate8_probe_rematched_weights")
        for vertex_index in FOCUS_VERTICES:
            record = records[str(vertex_index)]
            if not record.get("rematch_success"):
                raise RuntimeError(f"rematch unavailable for vertex {vertex_index}")
            set_vertex_weights(stored_variant, vertex_index, record["stored_mpfb_deform_weights"])
            set_vertex_weights(rematched_variant, vertex_index, record["rematched_mpfb_deform_weights"])

        rest = rest_world_positions(sportsuit)
        apply_pose(rig)
        stored_posed = evaluated_world_positions(stored_variant)
        rematched_posed = evaluated_world_positions(rematched_variant)

        edges = [edge_record(a, b, rest, stored_posed, rematched_posed) for a, b in LOCAL_EDGES]
        inversions = inversion_records(sportsuit, rest, stored_posed, rematched_posed)
        displacements = displacement_records(rest, stored_posed, rematched_posed)
        critical = [edge for edge in edges if edge["critical"]]
        controls = [edge for edge in edges if not edge["critical"]]

        for point in [*rest, *stored_posed, *rematched_posed]:
            if not all(math.isfinite(float(value)) for value in point):
                raise RuntimeError("non-finite posed geometry")

        measured = {
            "format": "grand-bruxelles-gate8-variant01-real-posed-geometry-v1-red-first",
            "source_evidence_artifact_id": 9720026708,
            "source_evidence_head_sha": "9defe931b0b51b3582c1e555ff80992f64f311fc",
            "mpfb_release": "2.0.17",
            "mpfb_release_commit": "80919fa",
            "blender_pose_axis": "local_euler_z",
            "pose_degrees": POSE_DEGREES,
            "sportsuit_object": sportsuit.name,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "rig_object": rig.name,
            "rig_bone_count": len(rig.data.bones),
            "focus_vertices": list(FOCUS_VERTICES),
            "local_edges": edges,
            "critical_edge_mean_stored_abs_strain": sum(x["stored_abs_strain"] for x in critical) / len(critical),
            "critical_edge_mean_rematched_abs_strain": sum(x["rematched_abs_strain"] for x in critical) / len(critical),
            "control_edge_mean_stored_abs_strain": sum(x["stored_abs_strain"] for x in controls) / len(controls),
            "control_edge_mean_rematched_abs_strain": sum(x["rematched_abs_strain"] for x in controls) / len(controls),
            "displacements": displacements,
            "incident_polygon_count": len(inversions),
            "polygon_orientation": inversions,
            "stored_inversion_count": sum(1 for x in inversions if x["stored_inverted"]),
            "rematched_inversion_count": sum(1 for x in inversions if x["rematched_inverted"]),
            "diagnostic_state": "RED_FIRST_REAL_POSED_GEOMETRY_MEASURED_UNREVIEWED",
            "next_safe_axis": "REVIEW_REAL_POSED_EDGE_STRETCH_AND_INVERSION_RESULT",
            "canonical_asset_mutation": False,
            "canonical_mhclo_mutation": False,
            "canonical_generator_mutation": False,
            "runtime_npc_mutation": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(measured, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(measured, sort_keys=True), flush=True)
        raise StopAfterMeasurement("real posed geometry measured")

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    except StopAfterMeasurement:
        pass
    finally:
        ExportService.create_character_copy = original_create_copy

    if measured is None or not RESULT_PATH.is_file():
        raise RuntimeError("real posed geometry probe did not produce a result")


if __name__ == "__main__":
    main()
