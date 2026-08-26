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
    if name in argv:
        return argv[argv.index(name) + 1]
    return default


def rot_error_deg(a, b):
    return math.degrees(a.to_quaternion().rotation_difference(b.to_quaternion()).angle)


def scale_tuple(matrix):
    s = matrix.to_scale()
    return [float(s.x), float(s.y), float(s.z)]


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


def bone_depth(pbone):
    depth = 0
    cur = pbone.parent
    while cur is not None:
        depth += 1
        cur = cur.parent
    return depth


def set_pose_matrices(arm, matrix_map):
    ordered = sorted(list(arm.pose.bones), key=lambda pb: (bone_depth(pb), pb.name))
    for _pass in range(2):
        for pbone in ordered:
            pbone.matrix = matrix_map[pbone.name]
            bpy.context.view_layer.update()


def pose_error(arm, matrix_map, names, frame):
    pos_max = 0.0
    rot_max = 0.0
    worst = {"frame": frame, "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for name in names:
        pb = arm.pose.bones[name]
        desired = matrix_map[name]
        pos_err = (pb.matrix.translation - desired.translation).length
        rot_err = rot_error_deg(pb.matrix, desired)
        if pos_err > pos_max or rot_err > rot_max:
            worst = {
                "frame": frame,
                "bone": name,
                "position_error_m": pos_err,
                "rotation_error_deg": rot_err,
                "parent": pb.parent.name if pb.parent else "",
                "use_inherit_rotation": bool(pb.bone.use_inherit_rotation),
                "inherit_scale": str(pb.bone.inherit_scale),
                "use_local_location": bool(pb.bone.use_local_location),
                "desired_scale": scale_tuple(desired),
                "current_scale": scale_tuple(pb.matrix),
                "basis_scale": scale_tuple(pb.matrix_basis),
            }
        pos_max = max(pos_max, pos_err)
        rot_max = max(rot_max, rot_err)
    if worst["bone"]:
        pb = arm.pose.bones[worst["bone"]]
        if pb.parent:
            parent = pb.parent
            desired_parent = matrix_map[parent.name]
            worst.update({
                "parent_position_error_m": (parent.matrix.translation - desired_parent.translation).length,
                "parent_rotation_error_deg": rot_error_deg(parent.matrix, desired_parent),
                "parent_use_inherit_rotation": bool(parent.bone.use_inherit_rotation),
                "parent_inherit_scale": str(parent.bone.inherit_scale),
                "parent_use_local_location": bool(parent.bone.use_local_location),
                "parent_desired_scale": scale_tuple(desired_parent),
                "parent_current_scale": scale_tuple(parent.matrix),
                "parent_basis_scale": scale_tuple(parent.matrix_basis),
            })
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
    excluded_controller_bones = sorted(set(arm.data.bones.keys()) - set(protected_bones))

    walks = [a for a in bpy.data.actions if a.name.lower() == "walk"]
    assert len(walks) == 1, f"expected exact walk action, got {[a.name for a in bpy.data.actions]}"
    walk = walks[0]
    scene = bpy.context.scene
    frame_start = int(math.floor(walk.frame_range[0]))
    frame_end = max(frame_start + 1, int(math.ceil(walk.frame_range[1])))
    frames = list(range(frame_start, frame_end + 1))

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
    inherit_scale_before = {name: str(arm.data.bones[name].inherit_scale) for name in REPAIRS}
    inherit_rotation_before = {name: bool(arm.data.bones[name].use_inherit_rotation) for name in REPAIRS}
    paths_before = {role: parent_path(arm.data.bones[name]) for role, name in ROLE_MAP.items()}

    pose_samples = {}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        pose_samples[frame] = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}

    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for child_name, parent_name in REPAIRS.items():
        child = arm.data.edit_bones[child_name]
        parent = arm.data.edit_bones[parent_name]
        matrix = child.matrix.copy()
        child.parent = parent
        child.use_connect = False
        child.matrix = matrix
    bpy.ops.object.mode_set(mode="OBJECT")

    # The moved nodes are controller roots, not deform bones. Their old global/master
    # space did not receive non-uniform deform-chain scale. Once structurally inserted
    # under armlo/leglo/pelvis, FULL scale inheritance introduces shear that a TRS
    # animation cannot represent exactly. Preserve rotation inheritance but isolate
    # only these five moved controller roots from parent scale.
    for child_name in REPAIRS:
        bone = arm.data.bones[child_name]
        bone.use_inherit_rotation = True
        bone.inherit_scale = 'NONE'
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
    for child_name, parent_name in REPAIRS.items():
        assert changed_parents[child_name]["after"] == parent_name
        assert arm.data.bones[child_name].inherit_scale == 'NONE'
        assert arm.data.bones[child_name].use_inherit_rotation is True
    after_gaps = role_gaps(arm)
    assert after_gaps == [], after_gaps

    for pb in arm.pose.bones:
        for constraint in list(pb.constraints):
            pb.constraints.remove(constraint)
        pb.rotation_mode = "QUATERNION"
    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)
    baked = bpy.data.actions.new("walk")
    arm.animation_data.action = baked
    bpy.context.view_layer.update()

    assignment_pos_max = 0.0
    assignment_rot_max = 0.0
    assignment_worst = {"frame": None, "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        set_pose_matrices(arm, pose_samples[frame])
        frame_pos, frame_rot, frame_worst = pose_error(arm, pose_samples[frame], protected_bones, frame)
        if frame_pos > assignment_pos_max or frame_rot > assignment_rot_max:
            assignment_worst = frame_worst
        assignment_pos_max = max(assignment_pos_max, frame_pos)
        assignment_rot_max = max(assignment_rot_max, frame_rot)
        assert frame_pos <= 1e-4, frame_worst
        assert frame_rot <= 0.10, frame_worst
        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="location", frame=frame, group=pb.name)
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pb.name)
            pb.keyframe_insert(data_path="scale", frame=frame, group=pb.name)

    role_by_bone = {bone: role for role, bone in ROLE_MAP.items()}
    pose_pos_max = 0.0
    pose_rot_max = 0.0
    pose_worst = {"frame": None, "role": "", "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        frame_pos, frame_rot, frame_worst = pose_error(arm, pose_samples[frame], protected_bones, frame)
        if frame_pos > pose_pos_max or frame_rot > pose_rot_max:
            frame_worst["role"] = role_by_bone.get(frame_worst["bone"], "")
            pose_worst = frame_worst
        pose_pos_max = max(pose_pos_max, frame_pos)
        pose_rot_max = max(pose_rot_max, frame_rot)
    assert pose_pos_max <= 1e-4, pose_worst
    assert pose_rot_max <= 0.10, pose_worst

    paths_after = {role: parent_path(arm.data.bones[name]) for role, name in ROLE_MAP.items()}
    report = {
        "format": "grand-bruxelles-steve-source-normalized-export-v5",
        "bake_solver": "controller_bridge_no_parent_scale_parent_first_matrix_v5",
        "red_reference_run": 32918396107,
        "red_reference_max_baked_pose_position_error_m": 1.5499066473743874,
        "red_assignment_run": 32922400044,
        "red_assignment_bone": "f2.R.002",
        "red_assignment_position_error_m": 0.021451851118810414,
        "red_assignment_rotation_error_deg": 0.7548473741080977,
        "controller_leaf_red_run": 32925637116,
        "controller_leaf_red_bone": "poleelbo.R",
        "weighted_hand_red_run": 32925862392,
        "weighted_hand_red_bone": "hand.R",
        "weighted_hand_red_position_error_m": 0.018322910366781766,
        "weighted_hand_red_rotation_error_deg": 2.3393807718643873,
        "parent_scale_red_run": 32926622094,
        "parent_scale_red_bone": "hand.R",
        "parent_scale_red_position_error_m": 1.2013700229374393e-07,
        "parent_scale_red_rotation_error_deg": 1.8354114219735884,
        "parent_scale_red_parent": "ikhand.R",
        "parent_scale_red_parent_rotation_error_deg": 1.1183630084234288,
        "parent_scale_red_parent_basis_scale": [0.8573974370956421, 0.8384586572647095, 0.8524900078773499],
        "source_bone_count": len(arm.data.bones),
        "weighted_bone_count": len(weighted_bones),
        "protected_bone_count": len(protected_bones),
        "weighted_bones": sorted(weighted_bones),
        "protected_bones": protected_bones,
        "excluded_controller_bones": excluded_controller_bones,
        "action_name": baked.name,
        "frame_start": frame_start,
        "frame_end": frame_end,
        "sampled_frames": len(frames),
        "repairs": REPAIRS,
        "changed_parents": changed_parents,
        "controller_inherit_scale_before": inherit_scale_before,
        "controller_inherit_scale_after": {name: str(arm.data.bones[name].inherit_scale) for name in REPAIRS},
        "controller_inherit_rotation_before": inherit_rotation_before,
        "controller_inherit_rotation_after": {name: bool(arm.data.bones[name].use_inherit_rotation) for name in REPAIRS},
        "topology_gaps_before": before_gaps,
        "topology_gaps_after": after_gaps,
        "role_parent_paths_before": paths_before,
        "role_parent_paths_after": paths_after,
        "max_rest_position_drift_m": rest_pos_max,
        "max_rest_rotation_drift_deg": rest_rot_max,
        "max_assignment_position_error_m": assignment_pos_max,
        "max_assignment_rotation_error_deg": assignment_rot_max,
        "assignment_worst": assignment_worst,
        "max_baked_pose_position_error_m": pose_pos_max,
        "max_baked_pose_rotation_error_deg": pose_rot_max,
        "baked_pose_worst": pose_worst,
        "source_normalization_applied": True,
        "controller_parent_scale_isolated": True,
        "runtime_authorized": False,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", export_animations=True,
        export_draco_mesh_compression_enable=False,
    )
    assert out.is_file() and out.stat().st_size > 0
    print(
        "GATE8_STEVE_NORMALIZED_EXPORT_OK bones=%d weighted=%d protected=%d gaps_before=%d gaps_after=%d assignment_pos_error_m=%.9f assignment_rot_error_deg=%.6f pose_pos_error_m=%.9f pose_rot_error_deg=%.6f bytes=%d"
        % (len(arm.data.bones), len(weighted_bones), len(protected_bones), len(before_gaps), len(after_gaps),
           assignment_pos_max, assignment_rot_max, pose_pos_max, pose_rot_max, out.stat().st_size)
    )


if __name__ == "__main__":
    main()
