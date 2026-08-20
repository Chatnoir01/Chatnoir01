#!/usr/bin/env python3
"""Build a review-only clean Vitruvian CharMorph game-rig GLB.

Expected to run inside Blender after the pinned CharMorph add-on and sparse
CharMorph-Vitruvian source have been staged by CI. No animations, Mixamo or
production authorization are allowed here.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
import traceback

import bpy


def _args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    return parser.parse_args(argv)


def _fail(message: str) -> None:
    print("GB_VITRUVIAN_GAME_RIG_BUILD_FAIL", message)
    raise RuntimeError(message)


def _enable_charmorph() -> None:
    try:
        bpy.ops.preferences.addon_enable(module="CharMorph")
        return
    except Exception:
        pass
    sys.path.insert(0, "/tmp/blender-user/scripts/addons")
    import CharMorph  # pylint: disable=import-error,import-outside-toplevel

    CharMorph.register()


def main() -> None:
    args = _args()
    _enable_charmorph()
    from CharMorph.common import manager  # pylint: disable=import-error,import-outside-toplevel

    obj = bpy.data.objects.get("cm_vitruvian")
    if obj is None or obj.type != "MESH":
        _fail("cm_vitruvian mesh missing from char.blend")

    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    manager.create_charmorphs(obj)
    morpher = manager.morpher
    if not morpher or getattr(morpher, "error", None):
        _fail(f"CharMorph recognition failed: {getattr(morpher, 'error', None)}")
    rigs = sorted(str(key) for key in morpher.core.char.armature.keys())
    print("GB_VITRUVIAN_AVAILABLE_RIGS", rigs)
    if "game-rig" not in rigs:
        _fail(f"game-rig unavailable; available={rigs}")

    ui = bpy.context.window_manager.charmorph_ui
    ui.rig = "game-rig"
    ui.rig_manual_sculpt = False
    ui.rig_manual_joints = False
    ui.rig_manual_weights = False
    result = bpy.ops.charmorph.rig()
    if "FINISHED" not in result:
        _fail(f"charmorph.rig did not finish: {result}")

    rig = obj.find_armature()
    if rig is None or rig.type != "ARMATURE":
        _fail("generated game-rig armature missing")
    rig_type = str(rig.data.get("charmorph_rig_type", ""))
    if rig_type != "game-rig":
        _fail(f"wrong rig type: {rig_type}")

    bones = [bone.name for bone in rig.data.bones]
    parents = {
        bone.name: (bone.parent.name if bone.parent is not None else "")
        for bone in rig.data.bones
    }
    forbidden_bones = [
        name for name in bones
        if any(token in name.lower() for token in ("mixamo", "mixamorig", "adobe"))
    ]
    if forbidden_bones:
        _fail(f"forbidden bone names: {forbidden_bones[:20]}")
    if len(bones) < 35:
        _fail(f"game-rig too small: {len(bones)} bones")

    active_actions: list[str] = []
    for datablock in (rig, obj):
        animation_data = getattr(datablock, "animation_data", None)
        if animation_data and animation_data.action:
            active_actions.append(animation_data.action.name)
    if active_actions:
        _fail(f"active animation actions present before export: {active_actions}")

    if not any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers):
        _fail("body has no armature modifier bound to game-rig")

    bone_set = set(bones)
    candidates: list[tuple[int, str, list[int]]] = []
    for vertex_group in obj.vertex_groups:
        if vertex_group.name not in bone_set:
            continue
        low = vertex_group.name.lower()
        if not any(token in low for token in ("arm", "forearm", "thigh", "shin", "leg")):
            continue
        indices: list[int] = []
        for vertex in obj.data.vertices:
            if any(
                membership.group == vertex_group.index and membership.weight > 0.15
                for membership in vertex.groups
            ):
                indices.append(vertex.index)
        if len(indices) >= 20:
            candidates.append((len(indices), vertex_group.name, indices[:400]))
    candidates.sort(reverse=True)
    if not candidates:
        _fail("no weighted limb group found for deformation proof")

    _, probe_bone_name, probe_indices = candidates[0]
    pose_bone = rig.pose.bones.get(probe_bone_name)
    if pose_bone is None:
        _fail(f"pose bone missing for weighted group {probe_bone_name}")

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh_before = evaluated.to_mesh()
    before = [mesh_before.vertices[index].co.copy() for index in probe_indices]
    evaluated.to_mesh_clear()

    pose_bone.rotation_mode = "XYZ"
    original_rotation = pose_bone.rotation_euler.copy()
    pose_bone.rotation_euler[0] += math.radians(18.0)
    bpy.context.view_layer.update()
    evaluated = obj.evaluated_get(depsgraph)
    mesh_after = evaluated.to_mesh()
    displacements = [
        (mesh_after.vertices[index].co - before[position]).length
        for position, index in enumerate(probe_indices)
    ]
    evaluated.to_mesh_clear()
    pose_bone.rotation_euler = original_rotation
    bpy.context.view_layer.update()

    max_displacement = max(displacements) if displacements else 0.0
    moved_vertices = sum(1 for displacement in displacements if displacement > 0.001)
    if max_displacement <= 0.003 or moved_vertices < 10:
        _fail(
            "skinning deformation proof failed "
            f"bone={probe_bone_name} moved={moved_vertices} max={max_displacement}"
        )

    neutral = bpy.data.materials.new("GB_Vitruvian_Body_Retarget_Neutral")
    neutral.diffuse_color = (0.42, 0.30, 0.24, 1.0)
    neutral.roughness = 0.72
    obj.data.materials.clear()
    obj.data.materials.append(neutral)
    for polygon in obj.data.polygons:
        polygon.material_index = 0

    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for datablock in (rig, obj):
        if datablock.animation_data:
            datablock.animation_data_clear()

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(args.output),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_morph=False,
        export_materials="EXPORT",
    )
    if not args.output.exists() or args.output.stat().st_size < 10000:
        _fail("GLB export missing or unexpectedly small")

    triangle_count = len(obj.data.polygons)
    report = {
        "schema": "grand-bruxelles-vitruvian-game-rig-body-build-v1",
        "production_authorized": False,
        "candidate_scope": "clean_game_rig_body_retarget_review_no_final_materials_no_hair",
        "charmorph_commit": "e2e87480657c87eb17bbfbd83833bee628494a90",
        "vitruvian_commit": "db7736668dfbcb090019068c8aeab28105af36a0",
        "character_license": "CC0",
        "tool_license": "GPL-3.0",
        "rig_type": rig_type,
        "available_rigs": rigs,
        "bone_count": len(bones),
        "bone_names": bones,
        "bone_parents": parents,
        "forbidden_bones": forbidden_bones,
        "animation_actions_before_export": active_actions,
        "export_animations": False,
        "deformation_probe_bone": probe_bone_name,
        "deformation_probe_vertices": len(probe_indices),
        "deformation_moved_vertices": moved_vertices,
        "deformation_max_local_m": max_displacement,
        "source_polygon_count": triangle_count,
        "glb_bytes": args.output.stat().st_size,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "GB_VITRUVIAN_GAME_RIG_BUILD_OK",
        json.dumps(
            {
                key: report[key]
                for key in (
                    "rig_type",
                    "bone_count",
                    "deformation_probe_bone",
                    "deformation_moved_vertices",
                    "deformation_max_local_m",
                    "source_polygon_count",
                    "glb_bytes",
                )
            },
            sort_keys=True,
        ),
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - Blender CI diagnostics
        traceback.print_exc()
        print("GB_VITRUVIAN_GAME_RIG_BUILD_FAIL", str(exc))
        raise
