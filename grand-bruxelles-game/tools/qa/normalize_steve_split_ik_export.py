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
LEGACY_CONTROLLERS = ["master", "ikhand.L", "ikhand.R", "ikfoot.L", "ikfoot.R"]
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


def evaluated_mesh_world_vertices(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        matrix = evaluated.matrix_world.copy()
        return [matrix @ vertex.co.copy() for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def capture_mesh_samples(scene, frames):
    mesh_objects = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: o.name)
    assert mesh_objects, "expected at least one mesh"
    samples = {}
    vertex_counts = {obj.name: len(obj.data.vertices) for obj in mesh_objects}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        samples[frame] = {
            obj.name: evaluated_mesh_world_vertices(obj, depsgraph)
            for obj in mesh_objects
        }
    return samples, vertex_counts


def capture_role_pose_samples(scene, arm, frames):
    samples = {}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        samples[frame] = {role: arm.pose.bones[name].matrix.copy() for role, name in ROLE_MAP.items()}
    return samples


def compare_roundtrip_mesh(scene, frames, reference_samples):
    imported_meshes = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    reference_names = sorted(next(iter(reference_samples.values())).keys())
    assert set(imported_meshes) == set(reference_names), {
        "expected": reference_names,
        "actual": sorted(imported_meshes),
    }
    max_error = 0.0
    worst = {"frame": None, "mesh": "", "vertex": -1, "position_error_m": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for name in reference_names:
            actual = evaluated_mesh_world_vertices(imported_meshes[name], depsgraph)
            expected = reference_samples[frame][name]
            assert len(actual) == len(expected), (name, len(actual), len(expected))
            for index, (a, e) in enumerate(zip(actual, expected)):
                err = (a - e).length
                if err > max_error:
                    max_error = err
                    worst = {"frame": frame, "mesh": name, "vertex": index, "position_error_m": err}
    return max_error, worst


def compare_roundtrip_roles(scene, arm, frames, reference_samples):
    max_pos = 0.0
    max_rot = 0.0
    worst = {"frame": None, "role": "", "bone": "", "position_error_m": 0.0, "rotation_error_deg": 0.0}
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        for role, bone_name in ROLE_MAP.items():
            actual = arm.pose.bones[bone_name].matrix
            expected = reference_samples[frame][role]
            pos = (actual.translation - expected.translation).length
            rot = rot_error_deg(actual, expected)
            if pos > max_pos or rot > max_rot:
                worst = {
                    "frame": frame,
                    "role": role,
                    "bone": bone_name,
                    "position_error_m": pos,
                    "rotation_error_deg": rot,
                }
            max_pos = max(max_pos, pos)
            max_rot = max(max_rot, rot)
    return max_pos, max_rot, worst


def main():
    out = Path(arg("--output", "/tmp/steve_normalized.glb"))
    report_path = Path(arg("--report", "/tmp/steve_normalized_export_report.json"))
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    assert len(arms) == 1, f"expected one armature, got {len(arms)}"
    arm = arms[0]
    assert all(name in arm.data.bones for name in ROLE_MAP.values())
    assert all(name in arm.data.bones for name in LEGACY_CONTROLLERS)

    weighted_bones = weighted_bone_names(arm)
    protected_bones = sorted(weighted_bones | set(ROLE_MAP.values()))
    assert weighted_bones
    assert len(protected_bones) >= 17
    assert all(arm.data.bones[name].use_deform for name in protected_bones)
    assert not (set(LEGACY_CONTROLLERS) & set(protected_bones))
    assert all(not arm.data.bones[name].use_deform for name in LEGACY_CONTROLLERS)

    walks = [a for a in bpy.data.actions if a.name.lower() == "walk"]
    assert len(walks) == 1, f"expected exact walk action, got {[a.name for a in bpy.data.actions]}"
    walk = walks[0]
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = walk
    for track in arm.animation_data.nla_tracks:
        track.mute = True

    scene = bpy.context.scene
    frame_start = int(math.floor(walk.frame_range[0]))
    frame_end = max(frame_start + 1, int(math.ceil(walk.frame_range[1])))
    frames = list(range(frame_start, frame_end + 1))
    scene.frame_start = frame_start
    scene.frame_end = frame_end

    source_gaps = role_gaps(arm)
    expected_gaps = sorted([
        "hips>spine","left_forearm>left_hand","left_lower_leg>left_foot",
        "right_forearm>right_hand","right_lower_leg>right_foot",
    ])
    assert source_gaps == expected_gaps, source_gaps

    role_reference = capture_role_pose_samples(scene, arm, frames)
    mesh_reference, source_vertex_counts = capture_mesh_samples(scene, frames)

    # glTF cannot encode shear. This rig produces non-decomposable child TRS under
    # non-uniformly scaled parents, proven by prior red tests. Blender's exporter
    # explicitly provides Flatten Bone Hierarchy for this case; deform-only export
    # also bakes evaluated animation while omitting controller bones.
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animations=True,
        export_frame_range=True,
        export_force_sampling=True,
        export_def_bones=True,
        export_hierarchy_flatten_bones=True,
        export_draco_mesh_compression_enable=False,
    )
    assert out.is_file() and out.stat().st_size > 0

    # Strong visual/mechanical proof: round-trip the generated GLB back through
    # Blender, then compare every evaluated mesh vertex and all 17 humanoid role
    # transforms on every sampled frame against the original constrained source.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(out))
    imported_arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    assert len(imported_arms) == 1, f"roundtrip expected one armature, got {len(imported_arms)}"
    imported_arm = imported_arms[0]
    assert all(name in imported_arm.data.bones for name in ROLE_MAP.values())
    assert all(name not in imported_arm.data.bones for name in LEGACY_CONTROLLERS)
    assert all(name in imported_arm.data.bones for name in protected_bones)

    imported_walks = [a for a in bpy.data.actions if a.name.lower() == "walk"]
    assert len(imported_walks) == 1, f"roundtrip expected exact walk action, got {[a.name for a in bpy.data.actions]}"
    if imported_arm.animation_data is None:
        imported_arm.animation_data_create()
    imported_arm.animation_data.action = imported_walks[0]
    scene = bpy.context.scene
    scene.frame_start = frame_start
    scene.frame_end = frame_end

    roundtrip_role_pos, roundtrip_role_rot, roundtrip_role_worst = compare_roundtrip_roles(
        scene, imported_arm, frames, role_reference
    )
    roundtrip_vertex_error, roundtrip_vertex_worst = compare_roundtrip_mesh(
        scene, frames, mesh_reference
    )
    assert roundtrip_role_pos <= 1e-4, roundtrip_role_worst
    assert roundtrip_role_rot <= 0.10, roundtrip_role_worst
    assert roundtrip_vertex_error <= 1e-4, roundtrip_vertex_worst

    imported_role_parent_count = sum(
        1 for name in ROLE_MAP.values() if imported_arm.data.bones[name].parent is not None
    )
    imported_vertex_counts = {
        obj.name: len(obj.data.vertices) for obj in bpy.data.objects if obj.type == "MESH"
    }
    assert imported_vertex_counts == source_vertex_counts, {
        "source": source_vertex_counts,
        "roundtrip": imported_vertex_counts,
    }

    report = {
        "format": "grand-bruxelles-steve-source-normalized-export-v7",
        "normalization_method": "gltf_deform_only_flatten_hierarchy_sampled_v7",
        "red_manual_trs_run": 32930408411,
        "red_manual_trs_bone": "armlo.R",
        "red_manual_trs_position_error_m": 0.00685772872786266,
        "red_manual_trs_rotation_error_deg": 0.7454570379380938,
        "red_native_bake_run": 32930829243,
        "red_native_bake_bone": "armlo.R",
        "red_native_bake_position_error_m": 0.00801097044207385,
        "red_native_bake_rotation_error_deg": 1.054979493255945,
        "source_bone_count": len(arm.data.bones) if arm.name in bpy.data.objects else None,
        "roundtrip_bone_count": len(imported_arm.data.bones),
        "weighted_bone_count": len(weighted_bones),
        "protected_bone_count": len(protected_bones),
        "weighted_bones": sorted(weighted_bones),
        "protected_bones": protected_bones,
        "omitted_controller_bones": LEGACY_CONTROLLERS,
        "source_topology_gaps": source_gaps,
        "roundtrip_role_bones_with_parents": imported_role_parent_count,
        "frame_start": frame_start,
        "frame_end": frame_end,
        "sampled_frames": len(frames),
        "source_vertex_counts": source_vertex_counts,
        "roundtrip_vertex_counts": imported_vertex_counts,
        "max_roundtrip_role_position_error_m": roundtrip_role_pos,
        "max_roundtrip_role_rotation_error_deg": roundtrip_role_rot,
        "roundtrip_role_worst": roundtrip_role_worst,
        "max_roundtrip_vertex_position_error_m": roundtrip_vertex_error,
        "roundtrip_vertex_worst": roundtrip_vertex_worst,
        "export_def_bones": True,
        "export_hierarchy_flatten_bones": True,
        "export_force_sampling": True,
        "source_normalization_applied": True,
        "runtime_authorized": False,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))
    print(
        "GATE8_STEVE_NORMALIZED_EXPORT_OK solver=v7 protected=%d role_pos=%.9f role_rot=%.6f vertex_pos=%.9f flat_role_parents=%d bytes=%d"
        % (len(protected_bones), roundtrip_role_pos, roundtrip_role_rot,
           roundtrip_vertex_error, imported_role_parent_count, out.stat().st_size)
    )


if __name__ == "__main__":
    main()
