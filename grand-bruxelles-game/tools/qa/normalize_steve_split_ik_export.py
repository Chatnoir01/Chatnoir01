import bpy
import json
import math
import sys
from pathlib import Path

ROLE_MAP = {
    "hips":"pelvis","spine":"waist","chest":"torso","neck":"neck","head":"head",
    "left_upper_arm":"armup.L","left_forearm":"armlo.L","left_hand":"hand.L",
    "right_upper_arm":"armup.R","right_forearm":"armlo.R","right_hand":"hand.R",
    "left_upper_leg":"legup.L","left_lower_leg":"leglo.L","left_foot":"foot1.L",
    "right_upper_leg":"legup.R","right_lower_leg":"leglo.R","right_foot":"foot1.R",
}
REPAIRS = {
    "master":"pelvis",
    "ikhand.L":"armlo.L",
    "ikhand.R":"armlo.R",
    "ikfoot.L":"leglo.L",
    "ikfoot.R":"leglo.R",
}
CHAINS = [
    ["hips","spine","chest","neck","head"],
    ["left_upper_arm","left_forearm","left_hand"],
    ["right_upper_arm","right_forearm","right_hand"],
    ["left_upper_leg","left_lower_leg","left_foot"],
    ["right_upper_leg","right_lower_leg","right_foot"],
]


def arg(name, default=None):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv[argv.index(name) + 1] if name in argv else default


def rot_error_deg(a, b):
    return math.degrees(a.to_quaternion().rotation_difference(b.to_quaternion()).angle)


def parent_path(bone):
    names = []
    cur = bone
    while cur is not None:
        names.insert(0, cur.name)
        cur = cur.parent
    return ">".join(names)


def is_ancestor(ancestor, child):
    cur = child.parent
    while cur is not None:
        if cur == ancestor:
            return True
        cur = cur.parent
    return False


def role_gaps(arm):
    gaps = []
    for chain in CHAINS:
        for a_role, b_role in zip(chain, chain[1:]):
            if not is_ancestor(arm.data.bones[ROLE_MAP[a_role]], arm.data.bones[ROLE_MAP[b_role]]):
                gaps.append(f"{a_role}>{b_role}")
    return sorted(gaps)


def weighted_bone_names(arm):
    bone_names = set(arm.data.bones.keys())
    weighted = set()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        used = set()
        for vertex in obj.data.vertices:
            for membership in vertex.groups:
                if membership.weight > 1e-8:
                    used.add(membership.group)
        for index in used:
            if 0 <= index < len(obj.vertex_groups):
                name = obj.vertex_groups[index].name
                if name in bone_names:
                    weighted.add(name)
    return weighted


def pose_error(arm, matrix_map, names, frame):
    pos_max = 0.0
    rot_max = 0.0
    worst = {"frame": frame, "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for name in names:
        current = arm.pose.bones[name].matrix
        desired = matrix_map[name]
        pos_err = (current.translation - desired.translation).length
        rot_err = rot_error_deg(current, desired)
        if pos_err > pos_max or rot_err > rot_max:
            worst = {
                "frame": frame,
                "bone": name,
                "position_error_m": pos_err,
                "rotation_error_deg": rot_err,
                "parent": arm.pose.bones[name].parent.name if arm.pose.bones[name].parent else "",
            }
        pos_max = max(pos_max, pos_err)
        rot_max = max(rot_max, rot_err)
    return pos_max, rot_max, worst


def sampled_error(scene, arm, pose_samples, names, frames):
    pos_max = 0.0
    rot_max = 0.0
    worst = {"frame": None, "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        pos, rot, candidate = pose_error(arm, pose_samples[frame], names, frame)
        if pos > pos_max or rot > rot_max:
            worst = candidate
        pos_max = max(pos_max, pos)
        rot_max = max(rot_max, rot)
    return pos_max, rot_max, worst


def main():
    out = Path(arg("--output", "/tmp/steve_normalized.glb"))
    report_path = Path(arg("--report", "/tmp/steve_normalized_export_report.json"))
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    assert len(arms) == 1, f"expected one armature, got {len(arms)}"
    arm = arms[0]
    assert all(name in arm.data.bones for name in ROLE_MAP.values())
    assert all(child in arm.data.bones and parent in arm.data.bones for child, parent in REPAIRS.items())

    weighted_bones = weighted_bone_names(arm)
    assert weighted_bones, "expected at least one weighted armature bone"
    protected_bones = sorted(weighted_bones | set(ROLE_MAP.values()))
    moved_controllers = sorted(REPAIRS.keys())
    assert not (set(moved_controllers) & set(protected_bones)), "controller root unexpectedly influences skin"
    assert all(arm.data.bones[name].use_deform for name in protected_bones), "protected bone must be deform-exportable"
    assert all(not arm.data.bones[name].use_deform for name in moved_controllers), "moved controller must stay non-deform"

    walks = [a for a in bpy.data.actions if a.name.lower() == "walk"]
    assert len(walks) == 1, f"expected exact walk action, got {[a.name for a in bpy.data.actions]}"
    walk = walks[0]
    scene = bpy.context.scene
    frame_start = int(math.floor(walk.frame_range[0]))
    frame_end = max(frame_start + 1, int(math.ceil(walk.frame_range[1])))
    frames = list(range(frame_start, frame_end + 1))
    scene.frame_start = frame_start
    scene.frame_end = frame_end

    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = walk
    for track in arm.animation_data.nla_tracks:
        track.mute = True

    expected_gaps = sorted([
        "hips>spine","left_forearm>left_hand","left_lower_leg>left_foot",
        "right_forearm>right_hand","right_lower_leg>right_foot",
    ])
    before_gaps = role_gaps(arm)
    assert before_gaps == expected_gaps, before_gaps
    rest_before = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    parent_before = {b.name: b.parent.name if b.parent else "" for b in arm.data.bones}
    paths_before = {role: parent_path(arm.data.bones[name]) for role, name in ROLE_MAP.items()}

    pose_samples = {}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        pose_samples[frame] = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}

    # First bake the constrained source in its ORIGINAL hierarchy. Blender's native
    # visual-keying bake is designed for this exact job and avoids forcing evaluated
    # non-decomposable matrices through a custom TRS solver after hierarchy surgery.
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    result = bpy.ops.nla.bake(
        frame_start=frame_start,
        frame_end=frame_end,
        step=1,
        only_selected=False,
        visual_keying=True,
        clear_constraints=True,
        clear_parents=False,
        use_current_action=True,
        clean_curves=False,
        bake_types={'POSE'},
    )
    assert 'FINISHED' in result, result
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    native_pos, native_rot, native_worst = sampled_error(scene, arm, pose_samples, protected_bones, frames)
    assert native_pos <= 1e-4, native_worst
    assert native_rot <= 0.10, native_worst

    # With constraints now baked away, repair the hierarchy without introducing an
    # IK dependency cycle. Only the five non-deform controller roots move.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for child_name, parent_name in REPAIRS.items():
        child = arm.data.edit_bones[child_name]
        parent = arm.data.edit_bones[parent_name]
        matrix = child.matrix.copy()
        child.parent = parent
        child.use_connect = False
        child.matrix = matrix
    bpy.ops.object.mode_set(mode="OBJECT")
    for child_name in moved_controllers:
        bone = arm.data.bones[child_name]
        bone.use_inherit_rotation = True
        bone.inherit_scale = 'NONE'
        arm.pose.bones[child_name].rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()

    rest_pos_max = 0.0
    rest_rot_max = 0.0
    for name, before in rest_before.items():
        after = arm.data.bones[name].matrix_local
        rest_pos_max = max(rest_pos_max, (after.translation - before.translation).length)
        rest_rot_max = max(rest_rot_max, rot_error_deg(after, before))
    assert rest_pos_max <= 1e-6, rest_pos_max
    assert rest_rot_max <= 1e-4, rest_rot_max

    changed_parents = {}
    for bone in arm.data.bones:
        before = parent_before[bone.name]
        after = bone.parent.name if bone.parent else ""
        if before != after:
            changed_parents[bone.name] = {"before": before, "after": after}
    assert set(changed_parents) == set(REPAIRS), changed_parents
    assert role_gaps(arm) == []

    # Re-key only the five moved controller roots in their new parent spaces. The
    # already-baked deform channels remain untouched.
    controller_pos_max = 0.0
    controller_rot_max = 0.0
    controller_worst = {"frame": None, "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        for _pass in range(2):
            for name in moved_controllers:
                arm.pose.bones[name].matrix = pose_samples[frame][name]
                bpy.context.view_layer.update()
        pos, rot, worst = pose_error(arm, pose_samples[frame], moved_controllers, frame)
        if pos > controller_pos_max or rot > controller_rot_max:
            controller_worst = worst
        controller_pos_max = max(controller_pos_max, pos)
        controller_rot_max = max(controller_rot_max, rot)
        assert pos <= 1e-4, worst
        assert rot <= 0.10, worst
        for name in moved_controllers:
            pb = arm.pose.bones[name]
            pb.keyframe_insert(data_path="location", frame=frame, group=name)
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=name)
            pb.keyframe_insert(data_path="scale", frame=frame, group=name)

    repaired_pos, repaired_rot, repaired_worst = sampled_error(scene, arm, pose_samples, protected_bones, frames)
    assert repaired_pos <= 1e-4, repaired_worst
    assert repaired_rot <= 0.10, repaired_worst

    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)
    for action in list(bpy.data.actions):
        if action != walk:
            bpy.data.actions.remove(action)
    walk.name = "walk"
    arm.animation_data.action = walk

    paths_after = {role: parent_path(arm.data.bones[name]) for role, name in ROLE_MAP.items()}
    report = {
        "format": "grand-bruxelles-steve-source-normalized-export-v6",
        "bake_solver": "native_visual_bake_original_hierarchy_then_controller_bridge_v6",
        "red_manual_trs_run": 32930408411,
        "red_manual_trs_bone": "armlo.R",
        "red_manual_trs_position_error_m": 0.00685772872786266,
        "red_manual_trs_rotation_error_deg": 0.7454570379380938,
        "source_bone_count": len(arm.data.bones),
        "weighted_bone_count": len(weighted_bones),
        "protected_bone_count": len(protected_bones),
        "weighted_bones": sorted(weighted_bones),
        "protected_bones": protected_bones,
        "moved_controller_bones": moved_controllers,
        "repairs": REPAIRS,
        "changed_parents": changed_parents,
        "topology_gaps_before": before_gaps,
        "topology_gaps_after": role_gaps(arm),
        "role_parent_paths_before": paths_before,
        "role_parent_paths_after": paths_after,
        "max_rest_position_drift_m": rest_pos_max,
        "max_rest_rotation_drift_deg": rest_rot_max,
        "max_native_bake_position_error_m": native_pos,
        "max_native_bake_rotation_error_deg": native_rot,
        "native_bake_worst": native_worst,
        "max_controller_assignment_position_error_m": controller_pos_max,
        "max_controller_assignment_rotation_error_deg": controller_rot_max,
        "controller_assignment_worst": controller_worst,
        "max_repaired_pose_position_error_m": repaired_pos,
        "max_repaired_pose_rotation_error_deg": repaired_rot,
        "repaired_pose_worst": repaired_worst,
        "controller_inherit_scale_after": {name: str(arm.data.bones[name].inherit_scale) for name in moved_controllers},
        "controller_inherit_rotation_after": {name: bool(arm.data.bones[name].use_inherit_rotation) for name in moved_controllers},
        "export_def_bones": True,
        "export_force_sampling": True,
        "source_normalization_applied": True,
        "runtime_authorized": False,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))

    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animations=True,
        export_frame_range=True,
        export_force_sampling=True,
        export_def_bones=True,
        export_draco_mesh_compression_enable=False,
    )
    assert out.is_file() and out.stat().st_size > 0
    print(
        "GATE8_STEVE_NORMALIZED_EXPORT_OK solver=v6 protected=%d native_pos=%.9f native_rot=%.6f controller_pos=%.9f controller_rot=%.6f repaired_pos=%.9f repaired_rot=%.6f bytes=%d"
        % (len(protected_bones), native_pos, native_rot, controller_pos_max, controller_rot_max,
           repaired_pos, repaired_rot, out.stat().st_size)
    )


if __name__ == "__main__":
    main()
