import json
import re
import sys
from pathlib import Path

import bpy


def _arg(name: str) -> str:
    try:
        index = sys.argv.index(name)
    except ValueError as exc:
        raise SystemExit(f"missing argument: {name}") from exc
    if index + 1 >= len(sys.argv):
        raise SystemExit(f"missing value for argument: {name}")
    return sys.argv[index + 1]


def _compact(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def _tokens(value: str) -> list[str]:
    return [token for token in re.sub(r"[^a-z0-9]+", " ", value.lower()).split() if token]


def _has_walk_semantics(value: str) -> bool:
    tokens = _tokens(value)
    return "walk" in tokens or _compact(value) in {"walk", "walking", "walkcycle", "walkloop"}


ROLE_ALIASES = {
    "hips": {"hips", "hip", "pelvis"},
    "left_upper_arm": {
        "upperarml",
        "upperarmleft",
        "leftupperarm",
        "luparm",
        "uparml",
    },
    "right_upper_arm": {
        "upperarmr",
        "upperarmright",
        "rightupperarm",
        "ruparm",
        "uparmr",
    },
    "left_foot": {"footl", "footleft", "leftfoot", "lfoot"},
    "right_foot": {"footr", "footright", "rightfoot", "rfoot"},
}


def _role_candidates(armature_objects: list[bpy.types.Object]) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {role: [] for role in ROLE_ALIASES}
    for armature in armature_objects:
        for bone in armature.data.bones:
            compact = _compact(bone.name)
            for role, aliases in ROLE_ALIASES.items():
                if compact in aliases:
                    result[role].append({"armature": armature.name, "bone": bone.name})
    return result


def main() -> None:
    out_path = Path(_arg("--out"))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    armature_objects = sorted(
        (obj for obj in bpy.data.objects if obj.type == "ARMATURE"), key=lambda obj: obj.name
    )
    mesh_objects = sorted((obj for obj in bpy.data.objects if obj.type == "MESH"), key=lambda obj: obj.name)

    armatures = []
    for armature in armature_objects:
        bones = [bone.name for bone in armature.data.bones]
        armatures.append(
            {
                "object_name": armature.name,
                "data_name": armature.data.name,
                "bone_count": len(bones),
                "bones": bones,
            }
        )

    skinned_meshes = []
    material_slot_count = 0
    for mesh in mesh_objects:
        material_slot_count += len(mesh.material_slots)
        modifiers = [
            modifier.object.name
            for modifier in mesh.modifiers
            if modifier.type == "ARMATURE" and modifier.object is not None
        ]
        if modifiers:
            skinned_meshes.append(
                {
                    "mesh": mesh.name,
                    "armature_objects": sorted(modifiers),
                    "vertex_group_count": len(mesh.vertex_groups),
                    "material_slot_count": len(mesh.material_slots),
                }
            )

    action_names = sorted(action.name for action in bpy.data.actions)
    nla_strip_names = []
    for obj in bpy.data.objects:
        animation_data = obj.animation_data
        if animation_data is None:
            continue
        for track in animation_data.nla_tracks:
            for strip in track.strips:
                nla_strip_names.append(strip.name)
                if strip.action is not None:
                    nla_strip_names.append(strip.action.name)
    nla_strip_names = sorted(set(nla_strip_names))

    clip_names = sorted(set(action_names + nla_strip_names))
    walk_candidates = [name for name in clip_names if _has_walk_semantics(name)]
    role_candidates = _role_candidates(armature_objects)
    required_roles = list(ROLE_ALIASES)
    missing_roles = [role for role in required_roles if not role_candidates[role]]
    ambiguous_roles = [role for role in required_roles if len(role_candidates[role]) > 1]

    max_bones = max((item["bone_count"] for item in armatures), default=0)
    structural_ok = bool(armatures) and max_bones >= 10 and bool(skinned_meshes)
    semantic_ok = bool(walk_candidates)
    explicit_role_candidates_complete = not missing_roles and not ambiguous_roles
    target_humanoid_retarget_compatible = structural_ok and semantic_ok and explicit_role_candidates_complete

    if target_humanoid_retarget_compatible:
        state = "READY_FOR_GODOT_4_7_1_IMPORT_PREFLIGHT"
        verdict = "AMELIORER_PENDING_GODOT_IMPORT_AND_RETARGET_MEASUREMENT"
    elif not armatures or max_bones < 10 or not skinned_meshes:
        state = "BLOCKED_NON_HUMANOID_OR_UNSKINNED_SOURCE"
        verdict = "JETER_GATE8_HUMANOID_RETARGET_INCOMPATIBLE"
    elif not semantic_ok:
        state = "BLOCKED_NO_WALK_CLIP_IN_BLEND_DATA"
        verdict = "JETER_CURRENT_WALK_SOURCE_CONTRACT"
    else:
        state = "BLOCKED_NEEDS_EXPLICIT_ROLE_MAPPING"
        verdict = "AMELIORER_NEEDS_EXPLICIT_ROLE_MAPPING"

    result = {
        "format": "grand-bruxelles-gate8-variant01-steve-blender-skeleton-inventory-result-v1",
        "blender_runtime_version": bpy.app.version_string,
        "blend_file_version": list(bpy.data.version),
        "armature_count": len(armatures),
        "armatures": armatures,
        "mesh_object_count": len(mesh_objects),
        "skinned_mesh_count": len(skinned_meshes),
        "skinned_meshes": skinned_meshes,
        "material_slot_count": material_slot_count,
        "action_count": len(action_names),
        "action_names": action_names,
        "nla_strip_names": nla_strip_names,
        "walk_clip_candidates": walk_candidates,
        "required_humanoid_roles": required_roles,
        "role_candidates": role_candidates,
        "missing_roles": missing_roles,
        "ambiguous_roles": ambiguous_roles,
        "explicit_role_candidates_complete": explicit_role_candidates_complete,
        "target_humanoid_retarget_compatible": target_humanoid_retarget_compatible,
        "mechanical_state": state,
        "owner_verdict": verdict,
        "retarget_applied": False,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "production_authorized": False,
        "activation_ready": False,
        "adoption_ready": False,
        "visual_approval_claimed": False,
    }
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")

    print(
        "GATE8_STEVE_BLEND_INVENTORY_OK "
        f"armatures={len(armatures)} max_bones={max_bones} skinned_meshes={len(skinned_meshes)} "
        f"actions={len(action_names)} walk_candidates={len(walk_candidates)} "
        f"missing_roles={len(missing_roles)} ambiguous_roles={len(ambiguous_roles)} state={state}"
    )


if __name__ == "__main__":
    main()
