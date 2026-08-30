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
RESULT_PATH = Path(os.environ["GATE8_ONE_RING_BLEND_RESULT"]).resolve()
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
ALPHAS = (0.0625, 0.125, 0.25, 0.375, 0.5)
POSE_DEGREES = {
    "upperarm_r": 35.0,
    "clavicle_r": 12.0,
    "spine_03": 4.0,
    "spine_02": 2.0,
    "spine_01": 0.0,
}


class StopAfterMeasurement(RuntimeError):
    pass


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    return list(ready.base.descendants(root))


def find_sportsuit(root: bpy.types.Object) -> bpy.types.Object:
    matches = [obj for obj in [root, *descendants(root)] if obj.type == "MESH" and OBJECT_FRAGMENT in obj.name.lower()]
    if len(matches) != 1:
        raise RuntimeError(f"expected one sportsuit, got {[obj.name for obj in matches]}")
    return matches[0]


def find_rig(root: bpy.types.Object, sportsuit: bpy.types.Object) -> bpy.types.Object:
    rigs: dict[int, bpy.types.Object] = {}
    for modifier in sportsuit.modifiers:
        rig = getattr(modifier, "object", None)
        if modifier.type == "ARMATURE" and rig is not None and rig.type == "ARMATURE":
            rigs[id(rig)] = rig
    if not rigs:
        for obj in [root, *descendants(root)]:
            if obj.type == "ARMATURE":
                rigs[id(obj)] = obj
    if len(rigs) != 1:
        raise RuntimeError(f"expected one effective rig, got {[obj.name for obj in rigs.values()]}")
    return next(iter(rigs.values()))


def duplicate_mesh(source: bpy.types.Object, name: str) -> bpy.types.Object:
    clone = source.copy()
    clone.data = source.data.copy()
    clone.name = name
    clone.data.name = name + "_mesh"
    bpy.context.scene.collection.objects.link(clone)
    return clone


def normalize(weights: dict[str, float]) -> dict[str, float]:
    positive = {name: float(value) for name, value in weights.items() if float(value) > 0.0}
    total = sum(positive.values())
    if total <= 1e-12:
        raise RuntimeError("zero deform weight sum")
    return {name: value / total for name, value in positive.items()}


def blend_weights(stored: dict[str, float], rematched: dict[str, float], alpha: float) -> dict[str, float]:
    names = set(stored) | set(rematched)
    mixed = {
        name: (1.0 - alpha) * float(stored.get(name, 0.0)) + alpha * float(rematched.get(name, 0.0))
        for name in names
    }
    return normalize(mixed)


def set_vertex_weights(obj: bpy.types.Object, vertex_index: int, weights: dict[str, float]) -> None:
    for group in obj.vertex_groups:
        try:
            group.remove([vertex_index])
        except RuntimeError:
            pass
    for name, value in normalize(weights).items():
        group = obj.vertex_groups.get(name)
        if group is None:
            group = obj.vertex_groups.new(name=name)
        group.add([vertex_index], value, "REPLACE")


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
        pose_bone.rotation_euler[2] = math.radians(degrees)
    bpy.context.view_layer.update()


def evaluated_world_positions(obj: bpy.types.Object) -> list[Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        if len(mesh.vertices) != len(obj.data.vertices):
            raise RuntimeError(f"topology changed for {obj.name}: {len(obj.data.vertices)} -> {len(mesh.vertices)}")
        matrix = evaluated.matrix_world.copy()
        return [matrix @ vertex.co.copy() for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def rest_world_positions(obj: bpy.types.Object) -> list[Vector]:
    matrix = obj.matrix_world.copy()
    return [matrix @ vertex.co.copy() for vertex in obj.data.vertices]


def polygon_normal(points: list[Vector]) -> Vector:
    normal = Vector((0.0, 0.0, 0.0))
    for index, current in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        normal.x += (current.y - nxt.y) * (current.z + nxt.z)
        normal.y += (current.z - nxt.z) * (current.x + nxt.x)
        normal.z += (current.x - nxt.x) * (current.y + nxt.y)
    return normal


def incident_polygons(obj: bpy.types.Object) -> list[bpy.types.MeshPolygon]:
    edge_keys = {frozenset(edge) for edge in LOCAL_EDGES}
    out: list[bpy.types.MeshPolygon] = []
    for polygon in obj.data.polygons:
        verts = list(map(int, polygon.vertices))
        poly_edges = {frozenset((verts[i], verts[(i + 1) % len(verts)])) for i in range(len(verts))}
        if edge_keys & poly_edges:
            out.append(polygon)
    if not out:
        raise RuntimeError("no incident polygons")
    return out


def edge_metrics(rest: list[Vector], posed: list[Vector]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for a, b in LOCAL_EDGES:
        rest_len = float((rest[a] - rest[b]).length)
        posed_len = float((posed[a] - posed[b]).length)
        if rest_len <= 1e-9:
            raise RuntimeError(f"degenerate rest edge {a}<->{b}")
        ratio = posed_len / rest_len
        rows.append({
            "edge": [a, b],
            "critical": (a, b) in CRITICAL_EDGES,
            "rest_length_m": rest_len,
            "posed_length_m": posed_len,
            "stretch_ratio": ratio,
            "abs_strain": abs(ratio - 1.0),
        })
    return rows


def inversion_count(obj: bpy.types.Object, rest: list[Vector], posed: list[Vector]) -> int:
    count = 0
    for polygon in incident_polygons(obj):
        verts = list(map(int, polygon.vertices))
        rest_n = polygon_normal([rest[v] for v in verts])
        posed_n = polygon_normal([posed[v] for v in verts])
        if min(rest_n.length, posed_n.length) <= 1e-12:
            raise RuntimeError(f"degenerate polygon normal at {polygon.index}")
        if float(rest_n.normalized().dot(posed_n.normalized())) < 0.0:
            count += 1
    return count


def summarize(edges: list[dict[str, Any]]) -> tuple[float, float]:
    critical = [row["abs_strain"] for row in edges if row["critical"]]
    controls = [row["abs_strain"] for row in edges if not row["critical"]]
    return sum(critical) / len(critical), sum(controls) / len(controls)


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
        variants: list[tuple[float, bpy.types.Object]] = []
        for alpha in ALPHAS:
            variants.append((alpha, duplicate_mesh(sportsuit, f"gate8_probe_one_ring_blend_{int(alpha * 10000):04d}")))

        for vertex_index in FOCUS_VERTICES:
            record = records[str(vertex_index)]
            if not record.get("rematch_success"):
                raise RuntimeError(f"rematch unavailable for vertex {vertex_index}")
            stored_weights = record["stored_mpfb_deform_weights"]
            rematched_weights = record["rematched_mpfb_deform_weights"]
            set_vertex_weights(stored_variant, vertex_index, stored_weights)
            for alpha, variant in variants:
                set_vertex_weights(variant, vertex_index, blend_weights(stored_weights, rematched_weights, alpha))

        rest = rest_world_positions(sportsuit)
        apply_pose(rig)
        stored_posed = evaluated_world_positions(stored_variant)
        stored_edges = edge_metrics(rest, stored_posed)
        stored_critical, stored_control = summarize(stored_edges)

        candidates: list[dict[str, Any]] = []
        for alpha, variant in variants:
            posed = evaluated_world_positions(variant)
            for point in posed:
                if not all(math.isfinite(float(value)) for value in point):
                    raise RuntimeError("non-finite posed geometry")
            edges = edge_metrics(rest, posed)
            critical_mean, control_mean = summarize(edges)
            focus_deltas = {str(v): float((posed[v] - stored_posed[v]).length) for v in FOCUS_VERTICES}
            candidates.append({
                "alpha": alpha,
                "critical_edge_mean_abs_strain": critical_mean,
                "control_edge_mean_abs_strain": control_mean,
                "control_edge_378_601_abs_strain": next(row["abs_strain"] for row in edges if row["edge"] == [378, 601]),
                "focus_vertex_delta_m": focus_deltas,
                "focus_vertex_max_delta_m": max(focus_deltas.values()),
                "focus_vertex_mean_delta_m": sum(focus_deltas.values()) / len(focus_deltas),
                "inversion_count": inversion_count(sportsuit, rest, posed),
                "local_edges": edges,
            })

        measured = {
            "format": "grand-bruxelles-gate8-variant01-one-ring-blend-sweep-v1-red-first",
            "candidate_strategy": "UNIFORM_LINEAR_BLEND_STORED_TO_REMATCHED_WEIGHTS_ACROSS_REVIEWED_ONE_RING",
            "alphas": list(ALPHAS),
            "source_evidence_artifact_id": 9720026708,
            "source_evidence_head_sha": "9defe931b0b51b3582c1e555ff80992f64f311fc",
            "mpfb_release": "2.0.17",
            "mpfb_release_commit": "80919fa",
            "pose_degrees": POSE_DEGREES,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "rig_bone_count": len(rig.data.bones),
            "focus_vertices": list(FOCUS_VERTICES),
            "topology_constraint": {
                "changed_vertices_exactly": list(FOCUS_VERTICES),
                "outside_focus_vertices_modified": False,
                "shared_alpha_across_one_ring": True,
            },
            "stored_reference": {
                "critical_edge_mean_abs_strain": stored_critical,
                "control_edge_mean_abs_strain": stored_control,
                "control_edge_378_601_abs_strain": next(row["abs_strain"] for row in stored_edges if row["edge"] == [378, 601]),
                "inversion_count": inversion_count(sportsuit, rest, stored_posed),
                "local_edges": stored_edges,
            },
            "candidates": candidates,
            "diagnostic_state": "RED_FIRST_ONE_RING_BLEND_SWEEP_MEASURED_UNREVIEWED",
            "next_safe_axis": "REVIEW_ONE_RING_PARETO_FRONTIER_BEFORE_ANY_SOURCE_MUTATION",
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
        raise StopAfterMeasurement("one-ring blend sweep measured")

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    except StopAfterMeasurement:
        pass
    finally:
        ExportService.create_character_copy = original_create_copy

    if measured is None or not RESULT_PATH.is_file():
        raise RuntimeError("one-ring blend sweep did not produce a result")


if __name__ == "__main__":
    main()
