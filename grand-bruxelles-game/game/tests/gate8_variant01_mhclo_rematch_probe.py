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

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_REMATCH_RESULT"]).resolve()
sys.path.insert(0, str(SOURCE_DIR))

import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402

OBJECT_FRAGMENT = "female_sportsuit01"
HM08_VERTEX_COUNT = 19158
FOCUS_VERTICES = (377, 378, 379, 486, 599, 601, 615, 864)
ANCHOR_486 = (15673, 15666, 15667)
ORIGINAL_601 = (15947, 15583, 15871)


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


def line_record(line: dict[str, Any]) -> dict[str, Any]:
    return {
        "verts": [int(v) for v in line["verts"]],
        "weights": [float(v) for v in line["weights"]],
        "offsets": [float(v) for v in line["offsets"]],
        "offset_norm": offset_norm([float(v) for v in line["offsets"]]),
    }


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
        graph = body_graph(body)

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
            record: dict[str, Any] = {
                "sportsuit_vertex": vertex_index,
                "focus_vertex_groups": vertex_groups(sportsuit, vertex_index),
                "stored": line_record(stored),
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
                stored_verts = [int(v) for v in stored["verts"]]
                record.update(
                    {
                        "rematch_success": True,
                        "final_strategy": str(match.final_strategy),
                        "focus_vertex_group_selected": str(match.focus_vert_group_name),
                        "rematched": rematched,
                        "same_support_exact_order": rematched_verts == stored_verts,
                        "same_support_set": set(rematched_verts) == set(stored_verts),
                        "rematched_internal_hops_max": max_internal_hops(graph, rematched_verts),
                        "stored_internal_hops_max": max_internal_hops(graph, stored_verts),
                        "rematched_to_stored_hops_min": min_hops(graph, rematched_verts, stored_verts),
                        "rematched_to_anchor_486_hops_min": min_hops(graph, rematched_verts, list(ANCHOR_486)),
                        "rematched_to_original_601_hops_min": min_hops(graph, rematched_verts, list(ORIGINAL_601)),
                    }
                )
                successful.append(vertex_index)
                if not record["same_support_set"]:
                    changed_support.append(vertex_index)
            except Exception as exc:
                record["error"] = f"{type(exc).__name__}: {exc}"
            records[str(vertex_index)] = record

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

        result = {
            "format": "grand-bruxelles-gate8-variant01-mhclo-rematch-v1",
            "diagnostic_state": state,
            "next_safe_axis": next_axis,
            "mpfb_release": "2.0.17",
            "mpfb_release_commit": "80919fa",
            "algorithm": "VertexMatch",
            "algorithm_order": ["EXACT", "RIGID_GROUP", "SIMPLE_FACE", "EXTENDED_FACE"],
            "asset_pack_filename": asset_pack.name,
            "sportsuit_object": sportsuit.name,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "body_object": body.name,
            "body_vertex_count": len(body.data.vertices),
            "body_edge_count": len(body.data.edges),
            "focus_vertices": list(FOCUS_VERTICES),
            "successful_rematches": successful,
            "changed_support_vertices": changed_support,
            "records": records,
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
