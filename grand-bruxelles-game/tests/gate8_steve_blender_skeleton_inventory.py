import json
import re
import sys
from pathlib import Path

import bpy


WEIGHT_EPSILON = 1e-8


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


def _role_candidates_for_armature(armature: bpy.types.Object) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {role: [] for role in ROLE_ALIASES}
    for bone in armature.data.bones:
        compact = _compact(bone.name)
        for role, aliases in ROLE_ALIASES.items():
            if compact in aliases:
                result[role].append(bone.name)
    return result


def _role_candidates(armature_objects: list[bpy.types.Object]) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {role: [] for role in ROLE_ALIASES}
    for armature in armature_objects:
        per_armature = _role_candidates_for_armature(armature)
        for role, bones in per_armature.items():
            for bone_name in bones:
                result[role].append({"armature": armature.name, "bone": bone_name})
    return result


def _complete_role_sets(armature_objects: list[bpy.types.Object]) -> list[dict]:
    complete = []
    for armature in armature_objects:
        candidates = _role_candidates_for_armature(armature)
        missing = [role for role, bones in candidates.items() if not bones]
        ambiguous = [role for role, bones in candidates.items() if len(bones) > 1]
        if not missing and not ambiguous:
            complete.append(
                {
                    "armature": armature.name,
                    "bone_count": len(armature.data.bones),
                    "roles": {role: bones[0] for role, bones in candidates.items()},
                }
            )
    return complete


def _positive_skin_stats(mesh: bpy.types.Object, armature: bpy.types.Object) -> dict:
    bone_names = {bone.name for bone in armature.data.bones}
    group_names = {group.index: group.name for group in mesh.vertex_groups}
    matching_groups = sorted(name for name in group_names.values() if name in bone_names)
    weighted_vertices: set[int] = set()
    positive_assignments = 0
    positive_weight_sum = 0.0
    for vertex in mesh.data.vertices:
        for assignment in vertex.groups:
            group_name = group_names.get(assignment.group)
            if group_name in bone_names and assignment.weight > WEIGHT_EPSILON:
                weighted_vertices.add(vertex.index)
                positive_assignments += 1
                positive_weight_sum += float(assignment.weight)
    return {
        "matching_bone_vertex_groups": matching_groups,
        "matching_bone_vertex_group_count": len(matching_groups),
        "positive_weighted_vertex_count": len(weighted_vertices),
        "positive_weight_assignment_count": positive_assignments,
        "positive_weight_sum": positive_weight_sum,
    }


def _regression_same_armature_requirement() -> None:
    split = {
        "hips": [{"armature": "A", "bone": "hips"}],
        "left_upper_arm": [{"armature": "A", "bone": "upperarm_l"}],
        "right_upper_arm": [{"armature": "A", "bone": "upperarm_r"}],
        "left_foot": [{"armature": "B", "bone": "foot_l"}],
        "right_foot": [{"armature": "B", "bone": "foot_r"}],
    }
    owners = [
        armature
        for armature in {item["armature"] for values in split.values() for item in values}
        if all(any(item["armature"] == armature for item in split[role]) for role in ROLE_ALIASES)
    ]
    assert owners == [], owners


def main() -> None:
    out_path = Path(_arg("--out"))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    _regression_same_armature_requirement()

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

    role_candidates = _role_candidates(armature_objects)
    complete_role_sets = _complete_role_sets(armature_objects)
    selected_role_set = complete_role_sets[0] if len(complete_role_sets) == 1 else None
    selected_armature = None
    if selected_role_set is not None:
        selected_armature = next(
            armature for armature in armature_objects if armature.name == selected_role_set["armature"]
        )

    skinned_meshes = []
    armature_modifier_meshes = []
    positive_weighted_meshes = []
    material_slot_count = 0
    for mesh in mesh_objects:
        material_slot_count += len(mesh.material_slots)
        modifiers = [
            modifier.object
            for modifier in mesh.modifiers
            if modifier.type == "ARMATURE" and modifier.object is not None
        ]
        if not modifiers:
            continue
        armature_modifier_meshes.append(mesh.name)
        mesh_records = []
        for modifier_armature in modifiers:
            stats = _positive_skin_stats(mesh, modifier_armature)
            record = {
                "mesh": mesh.name,
                "armature_object": modifier_armature.name,
                "vertex_group_count": len(mesh.vertex_groups),
                "material_slot_count": len(mesh.material_slots),
                **stats,
            }
            mesh_records.append(record)
            if stats["positive_weight_assignment_count"] > 0:
                positive_weighted_meshes.append(record)
        skinned_meshes.extend(mesh_records)

    selected_armature_weighted_meshes = []
    if selected_armature is not None:
        selected_armature_weighted_meshes = [
            record
            for record in positive_weighted_meshes
            if record["armature_object"] == selected_armature.name
        ]

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
    required_roles = list(ROLE_ALIASES)
    missing_roles = [role for role in required_roles if not role_candidates[role]]
    ambiguous_roles = [role for role in required_roles if len(role_candidates[role]) > 1]

    max_bones = max((item["bone_count"] for item in armatures), default=0)
    single_armature_role_set_complete = len(complete_role_sets) == 1
    positive_weighted_skin = bool(selected_armature_weighted_meshes)
    structural_ok = (
        bool(armatures)
        and max_bones >= 10
        and single_armature_role_set_complete
        and positive_weighted_skin
    )
    semantic_ok = bool(walk_candidates)
    explicit_role_candidates_complete = (
        not missing_roles and not ambiguous_roles and single_armature_role_set_complete
    )
    target_humanoid_retarget_compatible = structural_ok and semantic_ok and explicit_role_candidates_complete

    if target_humanoid_retarget_compatible:
        state = "READY_FOR_GODOT_4_7_1_IMPORT_PREFLIGHT"
        verdict = "AMELIORER_PENDING_GODOT_IMPORT_AND_RETARGET_MEASUREMENT"
    elif not armatures or max_bones < 10 or not positive_weighted_meshes:
        state = "BLOCKED_NON_HUMANOID_OR_UNSKINNED_SOURCE"
        verdict = "JETER_GATE8_HUMANOID_RETARGET_INCOMPATIBLE"
    elif not semantic_ok:
        state = "BLOCKED_NO_WALK_CLIP_IN_BLEND_DATA"
        verdict = "JETER_CURRENT_WALK_SOURCE_CONTRACT"
    else:
        state = "BLOCKED_NEEDS_EXPLICIT_ROLE_MAPPING"
        verdict = "AMELIORER_NEEDS_EXPLICIT_ROLE_MAPPING"

    result = {
        "format": "grand-bruxelles-gate8-variant01-steve-blender-skeleton-inventory-result-v2",
        "blender_runtime_version": bpy.app.version_string,
        "blend_file_version": list(bpy.data.version),
        "armature_count": len(armatures),
        "armatures": armatures,
        "mesh_object_count": len(mesh_objects),
        "armature_modifier_mesh_count": len(armature_modifier_meshes),
        "armature_modifier_meshes": sorted(armature_modifier_meshes),
        "positive_weighted_mesh_count": len(positive_weighted_meshes),
        "positive_weighted_meshes": positive_weighted_meshes,
        "selected_armature_weighted_mesh_count": len(selected_armature_weighted_meshes),
        "skinned_mesh_count": len(positive_weighted_meshes),
        "skinned_meshes": positive_weighted_meshes,
        "material_slot_count": material_slot_count,
        "action_count": len(action_names),
        "action_names": action_names,
        "nla_strip_names": nla_strip_names,
        "walk_clip_candidates": walk_candidates,
        "required_humanoid_roles": required_roles,
        "role_candidates": role_candidates,
        "missing_roles": missing_roles,
        "ambiguous_roles": ambiguous_roles,
        "complete_role_sets": complete_role_sets,
        "complete_role_set_count": len(complete_role_sets),
        "selected_role_set": selected_role_set,
        "single_armature_role_set_complete": single_armature_role_set_complete,
        "positive_weighted_skin": positive_weighted_skin,
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
        f"armatures={len(armatures)} max_bones={max_bones} "
        f"modifier_meshes={len(armature_modifier_meshes)} weighted_meshes={len(positive_weighted_meshes)} "
        f"selected_weighted_meshes={len(selected_armature_weighted_meshes)} actions={len(action_names)} "
        f"walk_candidates={len(walk_candidates)} complete_role_sets={len(complete_role_sets)} "
        f"missing_roles={len(missing_roles)} ambiguous_roles={len(ambiguous_roles)} state={state}"
    )


if __name__ == "__main__":
    main()
