#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import math
import os
import sys
import zipfile
from collections import deque
from pathlib import Path
from typing import Any

import bpy
from mathutils import Vector

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_REMATCH_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

OBJECT_FRAGMENT = "female_sportsuit01"
HM08_VERTEX_COUNT = 19158
FOCUS_VERTICES = (377, 378, 379, 486, 599, 601, 615, 864)
ANCHOR_486 = (15673, 15666, 15667)
ORIGINAL_601 = (15947, 15583, 15871)
LOCAL_EDGES = (
    (377, 486),
    (379, 486),
    (486, 601),
    (486, 864),
    (378, 601),
    (599, 601),
    (601, 615),
)
CLIFF_L1 = 1.7
MPFB_WEIGHT_CUTOFF = 0.001


class StopAfterRematch(RuntimeError):
    pass


def cli_value(name: str) -> str:
    try:
        idx = sys.argv.index(name)
    except ValueError as exc:
        raise RuntimeError(f"missing CLI argument {name}") from exc
    if idx + 1 >= len(sys.argv):
        raise RuntimeError(f"missing value for CLI argument {name}")
    return sys.argv[idx + 1]


def l1(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(abs(a.get(k, 0.0) - b.get(k, 0.0)) for k in set(a) | set(b))


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
            f"expected exactly one {HM08_VERTEX_COUNT}-vertex hm08 mesh, "
            f"got {[(obj.name, len(obj.data.vertices)) for obj in matches]}"
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


def parse_mhclo_rows(asset_pack: Path) -> dict[int, dict[str, Any]]:
    if not asset_pack.is_file():
        raise RuntimeError(f"asset pack missing: {asset_pack}")
    with zipfile.ZipFile(asset_pack) as archive:
        name = "clothes/female_sportsuit01/female_sportsuit01.mhclo"
        text = archive.read(name).decode("utf-8")
    lines = text.splitlines()
    try:
        start = lines.index("verts 0") + 1
    except ValueError as exc:
        raise RuntimeError("sportsuit mhclo missing verts 0 section") from exc
    rows: dict[int, dict[str, Any]] = {}
    vertex_index = 0
    for line in lines[start:]:
        stripped = line.strip()
        if not stripped:
            break
        if stripped.startswith("#"):
            continue
        fields = stripped.split()
        if len(fields) == 1:
            body = int(fields[0])
            rows[vertex_index] = {
                "verts": [body, body, body],
                "weights": [1.0, 0.0, 0.0],
                "offsets": [0.0, 0.0, 0.0],
                "raw": stripped,
            }
        elif len(fields) == 9:
            rows[vertex_index] = {
                "verts": [int(fields[0]), int(fields[1]), int(fields[2])],
                "weights": [float(fields[3]), float(fields[4]), float(fields[5])],
                "offsets": [float(fields[6]), float(fields[7]), float(fields[8])],
                "raw": stripped,
            }
        else:
            raise RuntimeError(f"unexpected mhclo vertex row at {vertex_index}: {stripped}")
        vertex_index += 1
    if vertex_index != 1797:
        raise RuntimeError(f"expected 1797 sportsuit mhclo rows, got {vertex_index}")
    return rows


def body_graph(body: bpy.types.Object) -> list[list[int]]:
    graph: list[list[int]] = [[] for _ in body.data.vertices]
    for edge in body.data.edges:
        a, b = int(edge.vertices[0]), int(edge.vertices[1])
        graph[a].append(b)
        graph[b].append(a)
    return graph


def graph_components(graph: list[list[int]]) -> tuple[list[int], dict[int, int]]:
    component = [-1] * len(graph)
    sizes: dict[int, int] = {}
    cid = 0
    for start in range(len(graph)):
        if component[start] != -1:
            continue
        queue = deque([start])
        component[start] = cid
        size = 0
        while queue:
            node = queue.popleft()
            size += 1
            for nxt in graph[node]:
                if component[nxt] == -1:
                    component[nxt] = cid
                    queue.append(nxt)
        sizes[cid] = size
        cid += 1
    return component, sizes


def min_hops(graph: list[list[int]], starts: list[int], targets: list[int]) -> int | None:
    target_set = set(int(v) for v in targets)
    seen = set(int(v) for v in starts)
    queue = deque((int(v), 0) for v in starts)
    while queue:
        node, hops = queue.popleft()
        if node in target_set:
            return hops
        for nxt in graph[node]:
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, hops + 1))
    return None


def max_internal_hops(graph: list[list[int]], verts: list[int]) -> int | None:
    values: list[int] = []
    for i, a in enumerate(verts):
        for b in verts[i + 1 :]:
            hops = min_hops(graph, [a], [b])
            if hops is None:
                return None
            values.append(hops)
    return max(values) if values else 0


def offset_norm(values: list[float]) -> float:
    return math.sqrt(sum(float(v) * float(v) for v in values))


def vertex_groups(obj: bpy.types.Object, vertex_index: int) -> list[str]:
    names = {group.index: group.name for group in obj.vertex_groups}
    return [
        names[assignment.group]
        for assignment in obj.data.vertices[vertex_index].groups
        if assignment.group in names
    ]


def vertex_weight_map(obj: bpy.types.Object, vertex_index: int) -> dict[str, float]:
    names = {group.index: group.name for group in obj.vertex_groups}
    out: dict[str, float] = {}
    for assignment in obj.data.vertices[vertex_index].groups:
        name = names.get(assignment.group)
        if name and assignment.weight > 0.0:
            out[name] = out.get(name, 0.0) + float(assignment.weight)
    return out


def mpfb_eligible(values: dict[str, float], rig_bones: set[str]) -> dict[str, float]:
    return {
        name: float(value)
        for name, value in values.items()
        if name in rig_bones or name.startswith("DEF-") or name.startswith("mhmask-")
    }


def mpfb_interpolate_line(
    body: bpy.types.Object,
    line: dict[str, Any],
    rig_bones: set[str],
) -> dict[str, float]:
    verts = [int(v) for v in line["verts"]]
    coeffs = [float(v) for v in line["weights"]]
    coefficient_sum = sum(coeffs)
    if abs(coefficient_sum) <= 1e-12:
        raise RuntimeError("MHCLO coefficient sum is zero")
    raw: dict[str, float] = {}
    for vertex_index, coefficient in zip(verts, coeffs):
        source = mpfb_eligible(vertex_weight_map(body, vertex_index), rig_bones)
        for bone, value in source.items():
            raw[bone] = raw.get(bone, 0.0) + coefficient * value
    averaged = {bone: value / coefficient_sum for bone, value in raw.items()}
    return {bone: value for bone, value in averaged.items() if value > MPFB_WEIGHT_CUTOFF}


def line_record(line: dict[str, Any]) -> dict[str, Any]:
    return {
        "verts": [int(v) for v in line["verts"]],
        "weights": [float(v) for v in line["weights"]],
        "offsets": [float(v) for v in line["offsets"]],
        "offset_norm": offset_norm([float(v) for v in line["offsets"]]),
    }


def support_metadata(
    body: bpy.types.Object,
    verts: list[int],
    components: list[int],
    component_sizes: dict[int, int],
) -> list[dict[str, Any]]:
    return [
        {
            "vertex": int(v),
            "component": int(components[v]),
            "component_size": int(component_sizes[components[v]]),
            "groups": vertex_groups(body, v),
        }
        for v in verts
    ]


def rematch_reconstruction_residual(
    focus_xref: Any,
    target_xref: Any,
    focus_vertex_index: int,
    line: dict[str, Any],
) -> float:
    verts = [int(v) for v in line["verts"]]
    weights = [float(v) for v in line["weights"]]
    offsets = [float(v) for v in line["offsets"]]
    q = Vector((0.0, 0.0, 0.0))
    for vertex_index, weight in zip(verts, weights):
        q += weight * Vector(target_xref.vertex_coordinates[vertex_index])
    # MHCLO stores Blender displacement D=(x,y,z) as (D.x, D.z, -D.y).
    d = Vector((offsets[0], -offsets[2], offsets[1]))
    predicted = q + d
    observed = Vector(focus_xref.vertex_coordinates[focus_vertex_index])
    return float((predicted - observed).length)


def main() -> None:
    asset_pack = Path(cli_value("--asset-pack")).resolve()
    stored_rows = parse_mhclo_rows(asset_pack)

    mpfb = ready.base.resolve_mpfb_module()
    services = importlib.import_module(mpfb.__package__ + ".services")
    meshcrossref_module = importlib.import_module(mpfb.__package__ + ".entities.meshcrossref")
    vertexmatch_module = importlib.import_module(mpfb.__package__ + ".entities.clothes.vertexmatch")
    ExportService = services.ExportService
    MeshCrossRef = meshcrossref_module.MeshCrossRef
    VertexMatch = vertexmatch_module.VertexMatch

    original_create_copy = ExportService.create_character_copy
    result: dict[str, Any] | None = None

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal result
        sportsuit = find_sportsuit(root)
        body = find_hm08(root)
        rig = find_effective_rig(root, sportsuit)
        rig_bones = {str(bone.name) for bone in rig.data.bones}
        graph = body_graph(body)
        components, component_sizes = graph_components(graph)

        focus_xref = MeshCrossRef(
            sportsuit,
            after_modifiers=False,
            build_faces_by_group_reference=True,
            world_coordinates=True,
        )
        target_xref = MeshCrossRef(
            body,
            after_modifiers=False,
            build_faces_by_group_reference=True,
            world_coordinates=True,
        )

        records: dict[str, Any] = {}
        successful: list[int] = []
        changed_support: list[int] = []

        for vertex_index in FOCUS_VERTICES:
            stored = stored_rows[vertex_index]
            stored_verts = [int(v) for v in stored["verts"]]
            stored_interp = mpfb_interpolate_line(body, stored, rig_bones)
            observed_deform = mpfb_eligible(vertex_weight_map(sportsuit, vertex_index), rig_bones)
            record: dict[str, Any] = {
                "sportsuit_vertex": vertex_index,
                "focus_vertex_groups": vertex_groups(sportsuit, vertex_index),
                "stored": line_record(stored),
                "stored_support_metadata": support_metadata(body, stored_verts, components, component_sizes),
                "stored_mpfb_deform_weights": stored_interp,
                "stored_to_observed_deform_l1": l1(stored_interp, observed_deform),
                "observed_deform_weights": observed_deform,
                "rematch_success": False,
            }
            try:
                match = VertexMatch(
                    sportsuit,
                    vertex_index,
                    focus_xref,
                    body,
                    target_xref,
                    scale_factor=1.0,
                    reference_scale=None,
                    allow_exact=True,
                )
                rematched = line_record(match.mhclo_line)
                rematched_verts = rematched["verts"]
                rematched_interp = mpfb_interpolate_line(body, match.mhclo_line, rig_bones)
                record.update(
                    {
                        "rematch_success": True,
                        "final_strategy": str(match.final_strategy),
                        "focus_vertex_group_selected": str(match.focus_vert_group_name),
                        "rematched": rematched,
                        "rematched_support_metadata": support_metadata(
                            body, rematched_verts, components, component_sizes
                        ),
                        "rematched_mpfb_deform_weights": rematched_interp,
                        "rematched_to_observed_deform_l1": l1(rematched_interp, observed_deform),
                        "rematched_reconstruction_residual": rematch_reconstruction_residual(
                            focus_xref, target_xref, vertex_index, match.mhclo_line
                        ),
                        "same_support_exact_order": rematched_verts == stored_verts,
                        "same_support_set": set(rematched_verts) == set(stored_verts),
                        "rematched_internal_hops_max": max_internal_hops(graph, rematched_verts),
                        "stored_internal_hops_max": max_internal_hops(graph, stored_verts),
                        "rematched_to_stored_hops_min": min_hops(graph, rematched_verts, stored_verts),
                        "rematched_to_anchor_486_hops_min": min_hops(
                            graph, rematched_verts, list(ANCHOR_486)
                        ),
                        "rematched_to_original_601_hops_min": min_hops(
                            graph, rematched_verts, list(ORIGINAL_601)
                        ),
                    }
                )
                successful.append(vertex_index)
                if not record["same_support_set"]:
                    changed_support.append(vertex_index)
            except Exception as exc:
                record["error"] = f"{type(exc).__name__}: {exc}"
            records[str(vertex_index)] = record

        edge_records: list[dict[str, Any]] = []
        for a, b in LOCAL_EDGES:
            ra, rb = records[str(a)], records[str(b)]
            stored_l1 = l1(ra["stored_mpfb_deform_weights"], rb["stored_mpfb_deform_weights"])
            observed_l1 = l1(ra["observed_deform_weights"], rb["observed_deform_weights"])
            edge: dict[str, Any] = {
                "edge": [a, b],
                "stored_mpfb_l1": stored_l1,
                "observed_deform_l1": observed_l1,
                "stored_is_cliff": stored_l1 >= CLIFF_L1,
                "observed_is_cliff": observed_l1 >= CLIFF_L1,
                "rematch_available": bool(ra["rematch_success"] and rb["rematch_success"]),
            }
            if edge["rematch_available"]:
                rematched_l1 = l1(
                    ra["rematched_mpfb_deform_weights"],
                    rb["rematched_mpfb_deform_weights"],
                )
                edge.update(
                    {
                        "rematched_mpfb_l1": rematched_l1,
                        "rematched_is_cliff": rematched_l1 >= CLIFF_L1,
                        "rematched_support_hops_min": min_hops(
                            graph,
                            ra["rematched"]["verts"],
                            rb["rematched"]["verts"],
                        ),
                    }
                )
            edge_records.append(edge)

        rec601 = records["601"]
        if not rec601["rematch_success"]:
            state = "CURRENT_MPF_B_VERTEXMATCH_CANNOT_REMATCH_601_IN_EFFECTIVE_SOURCE_CONTEXT"
            next_axis = "INSPECT_601_AUTHORING_GROUP_CONTEXT"
        elif rec601["same_support_set"]:
            state = "CURRENT_MPF_B_VERTEXMATCH_REPRODUCES_STORED_601_SUPPORT"
            next_axis = "TRACE_AUTHORING_REGION_BOUNDARY_BEYOND_VERTEXMATCH"
        else:
            state = "CURRENT_MPF_B_VERTEXMATCH_SELECTS_DIFFERENT_601_SUPPORT"
            next_axis = "EVALUATE_REMATCH_GEOMETRY_AND_WEIGHT_CONTINUITY"

        stored_cliffs = sum(1 for edge in edge_records if edge["stored_is_cliff"])
        observed_cliffs = sum(1 for edge in edge_records if edge["observed_is_cliff"])
        rematched_edges = [edge for edge in edge_records if edge["rematch_available"]]
        rematched_cliffs = sum(1 for edge in rematched_edges if edge["rematched_is_cliff"])
        stored_helper_vertices = sorted(
            {
                meta["vertex"]
                for record in records.values()
                for meta in record["stored_support_metadata"]
                if "HelperGeometry" in meta["groups"]
            }
        )
        rematched_helper_vertices = sorted(
            {
                meta["vertex"]
                for record in records.values()
                if record["rematch_success"]
                for meta in record["rematched_support_metadata"]
                if "HelperGeometry" in meta["groups"]
            }
        )

        result = {
            "format": "grand-bruxelles-gate8-variant01-mhclo-rematch-v2",
            "diagnostic_state": state,
            "next_safe_axis": next_axis,
            "mpfb_release": "2.0.17",
            "mpfb_release_commit": "80919fa",
            "algorithm": "VertexMatch",
            "algorithm_order": ["EXACT", "RIGID_GROUP", "SIMPLE_FACE", "EXTENDED_FACE"],
            "mpfb_weight_cutoff": MPFB_WEIGHT_CUTOFF,
            "cliff_threshold_l1": CLIFF_L1,
            "asset_pack_filename": asset_pack.name,
            "sportsuit_object": sportsuit.name,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "body_object": body.name,
            "body_vertex_count": len(body.data.vertices),
            "body_edge_count": len(body.data.edges),
            "body_component_count": len(component_sizes),
            "rig_object": rig.name,
            "rig_bone_count": len(rig_bones),
            "focus_vertices": list(FOCUS_VERTICES),
            "successful_rematches": successful,
            "changed_support_vertices": changed_support,
            "records": records,
            "local_edges": edge_records,
            "continuity_summary": {
                "edge_count": len(edge_records),
                "stored_cliff_count": stored_cliffs,
                "observed_cliff_count": observed_cliffs,
                "rematched_edge_count": len(rematched_edges),
                "rematched_cliff_count": rematched_cliffs,
                "stored_helpergeometry_support_vertices": stored_helper_vertices,
                "rematched_helpergeometry_support_vertices": rematched_helper_vertices,
                "stored_helpergeometry_support_count": len(stored_helper_vertices),
                "rematched_helpergeometry_support_count": len(rematched_helper_vertices),
            },
            "canonical_asset_mutation": False,
            "canonical_mhclo_mutation": False,
            "canonical_generator_mutation": False,
            "runtime_npc_mutation": False,
            "reweight_applied": False,
            "retarget_applied": False,
            "production_activation_allowed": False,
            "visual_approval_allowed": False,
        }
        RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
        RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True), flush=True)
        raise StopAfterRematch("mhclo rematch diagnostic complete")

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    except StopAfterRematch:
        pass
    finally:
        ExportService.create_character_copy = original_create_copy

    if result is None or not RESULT_PATH.is_file():
        raise RuntimeError("mhclo rematch probe did not produce a result")


if __name__ == "__main__":
    main()
