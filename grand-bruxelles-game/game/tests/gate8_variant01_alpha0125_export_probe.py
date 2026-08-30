#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
EVIDENCE_PATH = Path(os.environ["GATE8_REMATCH_EVIDENCE"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_ALPHA_RESULT"]).resolve()
ALPHA = 0.125
FOCUS_VERTICES = (377, 378, 379, 486, 599, 601, 615, 864)
OBJECT_FRAGMENT = "female_sportsuit01"
FROZEN_POSE_DEGREES = {
    "upperarm_r": 35.0,
    "clavicle_r": 12.0,
    "spine_03": 4.0,
    "spine_02": 2.0,
}
WITNESS_PATH = Path("grand-bruxelles-game/game/tests/gate8_runtime_witness.gd")

sys.path.insert(0, str(SOURCE_DIR))
import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    return [root, *ready.base.descendants(root)]


def find_sportsuit(root: bpy.types.Object) -> bpy.types.Object:
    matches = [
        obj for obj in descendants(root)
        if obj.type == "MESH" and OBJECT_FRAGMENT in obj.name.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected one sportsuit under {root.name}, got {[o.name for o in matches]}")
    return matches[0]


def set_vertex_weights(obj: bpy.types.Object, vertex_index: int, weights: dict[str, float]) -> None:
    for group in obj.vertex_groups:
        try:
            group.remove([vertex_index])
        except RuntimeError:
            pass
    positive = {name: float(value) for name, value in weights.items() if float(value) > 0.0}
    total = sum(positive.values())
    if total <= 1e-12:
        raise RuntimeError(f"zero blended deform weight at vertex {vertex_index}")
    for name, value in positive.items():
        group = obj.vertex_groups.get(name)
        if group is None:
            group = obj.vertex_groups.new(name=name)
        group.add([vertex_index], value / total, "REPLACE")


def blend_weights(stored: dict[str, Any], rematched: dict[str, Any]) -> dict[str, float]:
    names = set(stored) | set(rematched)
    blended = {
        name: (1.0 - ALPHA) * float(stored.get(name, 0.0)) + ALPHA * float(rematched.get(name, 0.0))
        for name in names
    }
    return {name: value for name, value in blended.items() if value > 1e-12}


def patch_witness_for_frozen_pose() -> None:
    if not WITNESS_PATH.is_file():
        raise RuntimeError(f"historical Godot witness missing: {WITNESS_PATH}")
    text = WITNESS_PATH.read_text(encoding="utf-8")
    call_anchor = "    shot.add_child(model)\n\n    var correction := Gate8Loader.ground_external_visual(model)"
    if text.count(call_anchor) != 1:
        raise RuntimeError("Godot witness pose call anchor drifted")
    call = """    shot.add_child(model)\n\n    var pose_error := _apply_frozen_shoulder_pose(model)\n    if pose_error != OK:\n        push_error(\"Gate-8 witness could not apply frozen shoulder pose model=%02d distance=%.1f view=%s\" % [variant_index, distance_m, view_name])\n        shot.queue_free()\n        return pose_error\n\n    var correction := Gate8Loader.ground_external_visual(model)"""
    helper_anchor = "\nfunc _rest_vertex_world_bounds(root: Node3D) -> Dictionary:\n"
    if text.count(helper_anchor) != 1:
        raise RuntimeError("Godot witness helper anchor drifted")
    pose_rows = ", ".join(f'\"{name}\": {degrees:.1f}' for name, degrees in FROZEN_POSE_DEGREES.items())
    helper = f'''\nfunc _apply_frozen_shoulder_pose(root: Node3D) -> Error:\n    var skeletons := root.find_children("*", "Skeleton3D", true, false)\n    if skeletons.size() != 1:\n        push_error("Gate-8 frozen pose expected exactly one Skeleton3D, got %d" % skeletons.size())\n        return ERR_INVALID_DATA\n    var skeleton := skeletons[0] as Skeleton3D\n    if skeleton == null:\n        return ERR_INVALID_DATA\n    var pose_degrees := {{{pose_rows}}}\n    for bone_name: String in pose_degrees:\n        var bone_index := skeleton.find_bone(bone_name)\n        if bone_index < 0:\n            push_error("Gate-8 frozen pose missing bone %s" % bone_name)\n            return ERR_INVALID_DATA\n        skeleton.set_bone_pose_rotation(\n            bone_index,\n            Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(float(pose_degrees[bone_name])))\n        )\n    print("GATE8_FROZEN_SHOULDER_POSE_OK axis=local_z upperarm_r=35 clavicle_r=12 spine_03=4 spine_02=2")\n    return OK\n'''
    patched = text.replace(call_anchor, call).replace(helper_anchor, helper + helper_anchor)
    if patched == text:
        raise RuntimeError("Godot witness frozen-pose patch was a no-op")
    WITNESS_PATH.write_text(patched, encoding="utf-8")


def main() -> None:
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    if evidence.get("format") != "grand-bruxelles-gate8-variant01-mhclo-rematch-v2":
        raise RuntimeError("unexpected rematch evidence format")
    records = evidence.get("records", {})
    if set(records) != {str(v) for v in FOCUS_VERTICES}:
        raise RuntimeError("focus vertex evidence drifted")

    mpfb = ready.base.resolve_mpfb_module()
    services = __import__(mpfb.__package__ + ".services", fromlist=["ExportService"])
    ExportService = services.ExportService
    original_create_copy = ExportService.create_character_copy
    touched = False
    audit: dict[str, Any] = {}

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal touched, audit
        copy_root = original_create_copy(root, *args, **kwargs)
        if root.name != "npc_gate_01":
            return copy_root
        sportsuit = find_sportsuit(copy_root)
        if len(sportsuit.data.vertices) != 1797:
            raise RuntimeError(f"sportsuit topology drifted: {len(sportsuit.data.vertices)}")
        vertex_audit: dict[str, Any] = {}
        for vertex_index in FOCUS_VERTICES:
            record = records[str(vertex_index)]
            if not record.get("rematch_success"):
                raise RuntimeError(f"missing rematch for {vertex_index}")
            stored = record["stored_mpfb_deform_weights"]
            rematched = record["rematched_mpfb_deform_weights"]
            blended = blend_weights(stored, rematched)
            set_vertex_weights(sportsuit, vertex_index, blended)
            vertex_audit[str(vertex_index)] = {
                "stored": stored,
                "rematched": rematched,
                "alpha0125": blended,
                "sum": sum(blended.values()),
            }
        touched = True
        audit = {
            "variant": root.name,
            "sportsuit": sportsuit.name,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "alpha": ALPHA,
            "focus_vertices": list(FOCUS_VERTICES),
            "vertices": vertex_audit,
        }
        return copy_root

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    finally:
        ExportService.create_character_copy = original_create_copy

    if not touched:
        raise RuntimeError("alpha0125 probe never intercepted npc_gate_01 export")
    output_dir = next((Path(sys.argv[i + 1]).resolve() for i, arg in enumerate(sys.argv) if arg == "--output-dir"), None)
    if output_dir is None:
        raise RuntimeError("output dir missing")
    glbs = sorted(output_dir.glob("npc_gate_*.glb"))
    if len(glbs) != 8:
        raise RuntimeError(f"expected 8 generated GLBs, got {len(glbs)}")

    patch_witness_for_frozen_pose()

    result = {
        "format": "grand-bruxelles-gate8-alpha0125-export-v2-posed-witness",
        "alpha": ALPHA,
        "candidate_variant": "npc_gate_01",
        "focus_vertices": list(FOCUS_VERTICES),
        "source_evidence_artifact_id": 9720026708,
        "source_pack_sha256": ready.base.EXPECTED_ASSET_SHA256,
        "generator_mpfb": "2.0.17",
        "generator_mpfb_build": ready.base.EXPECTED_MPFB_BUILD,
        "godot_witness_pose_axis": "local_z",
        "godot_witness_pose_degrees": FROZEN_POSE_DEGREES,
        "audit": audit,
        "canonical_asset_mutation": False,
        "canonical_mhclo_mutation": False,
        "runtime_npc_mutation": False,
        "production_activation_allowed": False,
        "visual_approval_allowed": False,
    }
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("GATE8_ALPHA0125_EXPORT_OK variant=npc_gate_01 alpha=0.125 focus_vertices=8 posed_godot_witness=local_z", flush=True)


if __name__ == "__main__":
    main()
