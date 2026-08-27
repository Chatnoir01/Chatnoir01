import bpy
import json
import math
import sys
import traceback
from pathlib import Path


MIN_EXCITATION_DEG = 10.0
MIN_MOVING_BONES = 6
MOVING_ROTATION_DEG = 1.0
MOVING_POSITION_M = 0.005
MAX_BAKE_POSITION_ERROR_M = 0.0001
MAX_BAKE_ROTATION_ERROR_DEG = 0.10


def arg(name, default=None):
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return args[args.index(name) + 1] if name in args else default


def normalized_walk_name(name):
    return str(name).strip().lower().replace("-", "_").replace(" ", "_")


def is_walk_candidate(name):
    n = normalized_walk_name(name)
    return n == "walk" or n.startswith("walk_")


def action_stats(action):
    multi = 0
    total = 0
    curves = 0
    for fc in action.fcurves:
        curves += 1
        keys = len(fc.keyframe_points)
        total += keys
        if keys > 1:
            multi += 1
    return {
        "name": action.name,
        "fcurve_count": curves,
        "multi_key_fcurve_count": multi,
        "total_key_count": total,
    }


def score(stats):
    return (
        stats["multi_key_fcurve_count"],
        stats["total_key_count"],
        stats["fcurve_count"],
    )


def clear_scene():
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.context.scene.objects):
        obj.select_set(True)
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def select_hierarchy(root):
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    stack = [root]
    while stack:
        obj = stack.pop()
        obj.select_set(True)
        stack.extend(list(obj.children))
    bpy.context.view_layer.objects.active = root


def clear_nla(arm):
    if arm.animation_data is None:
        arm.animation_data_create()
    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)


def quat_delta_deg(a, b):
    qa = a.normalized()
    qb = b.normalized()
    dot = max(-1.0, min(1.0, abs(qa.dot(qb))))
    return math.degrees(2.0 * math.acos(dot))


def pose_snapshot(arm):
    return {
        pb.name: {
            "matrix_basis": pb.matrix_basis.copy(),
            "matrix": pb.matrix.copy(),
        }
        for pb in arm.pose.bones
    }


def measure_snapshots(frames, snapshots):
    first = snapshots[frames[0]]
    max_rot = {name: 0.0 for name in first}
    max_pos = {name: 0.0 for name in first}
    for frame in frames:
        snap = snapshots[frame]
        for name, base in first.items():
            cur = snap[name]
            max_rot[name] = max(
                max_rot[name],
                quat_delta_deg(
                    base["matrix"].to_quaternion(),
                    cur["matrix"].to_quaternion(),
                ),
            )
            max_pos[name] = max(
                max_pos[name],
                (base["matrix"].translation - cur["matrix"].translation).length,
            )
    moving = sorted(
        name
        for name in first
        if max_rot[name] >= MOVING_ROTATION_DEG
        or max_pos[name] >= MOVING_POSITION_M
    )
    return {
        "max_pose_excitation_deg": max(max_rot.values()) if max_rot else 0.0,
        "moving_bone_count": len(moving),
        "moving_bones": moving,
        "max_rotation_by_bone_deg": max_rot,
        "max_position_by_bone_m": max_pos,
    }


def capture_action_pose(arm, action):
    clear_nla(arm)
    arm.animation_data.action = action
    start = int(math.floor(action.frame_range[0]))
    end = int(math.ceil(action.frame_range[1]))
    frames = list(range(start, end + 1))
    assert len(frames) >= 2, action.frame_range
    snapshots = {}
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        snapshots[frame] = pose_snapshot(arm)
    return frames, snapshots, measure_snapshots(frames, snapshots)


def bake_snapshots_to_fresh_action(arm, frames, snapshots):
    clear_nla(arm)
    source_actions = list(bpy.data.actions)
    baked = bpy.data.actions.new("walk_canonical_baked")
    arm.animation_data.action = baked
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        for pb in arm.pose.bones:
            basis = snapshots[frame][pb.name]["matrix_basis"]
            loc, rot, scale = basis.decompose()
            pb.rotation_mode = "QUATERNION"
            pb.location = loc
            pb.rotation_quaternion = rot.normalized()
            pb.scale = scale
            pb.keyframe_insert(data_path="location", frame=frame, group=pb.name)
            pb.keyframe_insert(
                data_path="rotation_quaternion", frame=frame, group=pb.name
            )
            pb.keyframe_insert(data_path="scale", frame=frame, group=pb.name)
    for action in source_actions:
        bpy.data.actions.remove(action)
    baked.name = "walk"
    arm.animation_data.action = baked
    return baked


def verify_baked_pose(arm, baked, frames, expected):
    clear_nla(arm)
    arm.animation_data.action = baked
    max_pos = 0.0
    max_rot = 0.0
    worst_pos = {}
    worst_rot = {}
    actual = {}
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        actual[frame] = pose_snapshot(arm)
        for name in expected[frame]:
            want = expected[frame][name]["matrix"]
            got = actual[frame][name]["matrix"]
            pos = (want.translation - got.translation).length
            rot = quat_delta_deg(want.to_quaternion(), got.to_quaternion())
            if pos > max_pos:
                max_pos = pos
                worst_pos = {"frame": frame, "bone": name, "error_m": pos}
            if rot > max_rot:
                max_rot = rot
                worst_rot = {"frame": frame, "bone": name, "error_deg": rot}
    metrics = measure_snapshots(frames, actual)
    metrics.update(
        {
            "max_bake_position_error_m": max_pos,
            "max_bake_rotation_error_deg": max_rot,
            "bake_position_worst": worst_pos,
            "bake_rotation_worst": worst_rot,
        }
    )
    return metrics


def main():
    inp = Path(arg("--input", "/tmp/steve_reviewed_proxy.glb"))
    out = Path(arg("--output", "/tmp/steve_reviewed_proxy_canonical.glb"))
    report_path = Path(arg("--report", "/tmp/steve-walk-canonicalization.json"))
    report = {
        "format": "grand-bruxelles-steve-reviewed-walk-canonicalization-v4",
        "state": "STARTED",
        "runtime_alias_published": False,
        "production_authorized": False,
        "canonicalization_strategy": "evaluated_pose_fresh_bake",
    }

    def write_report():
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True))

    try:
        assert inp.is_file(), inp
        clear_scene()
        bpy.ops.import_scene.gltf(filepath=str(inp))
        armatures = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
        assert len(armatures) == 1, [o.name for o in armatures]
        arm = armatures[0]
        assert len(arm.data.bones) == 17, len(arm.data.bones)

        candidates = [a for a in bpy.data.actions if is_walk_candidate(a.name)]
        stats = [action_stats(a) for a in candidates]
        report["candidate_actions_before"] = sorted(stats, key=lambda x: x["name"])
        assert candidates, stats
        selected = max(candidates, key=lambda a: score(action_stats(a)))
        selected_stats = action_stats(selected)
        assert selected_stats["multi_key_fcurve_count"] >= 17, selected_stats
        assert selected_stats["total_key_count"] >= 300, selected_stats

        frames, source_snapshots, source_motion = capture_action_pose(arm, selected)
        report["selected_action_before"] = selected_stats["name"]
        report["source_evaluated_motion"] = source_motion
        report["sampled_frame_start"] = frames[0]
        report["sampled_frame_end"] = frames[-1]
        report["sampled_frame_count"] = len(frames)
        assert source_motion["max_pose_excitation_deg"] >= MIN_EXCITATION_DEG, source_motion
        assert source_motion["moving_bone_count"] >= MIN_MOVING_BONES, source_motion

        baked = bake_snapshots_to_fresh_action(arm, frames, source_snapshots)
        baked_stats = action_stats(baked)
        baked_motion = verify_baked_pose(arm, baked, frames, source_snapshots)
        report["baked_action_stats"] = baked_stats
        report["baked_evaluated_motion"] = baked_motion
        assert baked_stats["multi_key_fcurve_count"] >= 17, baked_stats
        assert baked_stats["total_key_count"] >= 300, baked_stats
        assert baked_motion["max_bake_position_error_m"] <= MAX_BAKE_POSITION_ERROR_M, baked_motion
        assert baked_motion["max_bake_rotation_error_deg"] <= MAX_BAKE_ROTATION_ERROR_DEG, baked_motion
        assert baked_motion["max_pose_excitation_deg"] >= MIN_EXCITATION_DEG, baked_motion
        assert baked_motion["moving_bone_count"] >= MIN_MOVING_BONES, baked_motion

        remaining = [a for a in bpy.data.actions if is_walk_candidate(a.name)]
        assert len(remaining) == 1 and remaining[0] == baked, [a.name for a in remaining]
        assert len(bpy.data.actions) == 1, [a.name for a in bpy.data.actions]

        select_hierarchy(arm)
        bpy.ops.export_scene.gltf(
            filepath=str(out),
            export_format="GLB",
            use_selection=True,
            export_animations=True,
            export_draco_mesh_compression_enable=False,
        )
        assert out.is_file() and out.stat().st_size > 0
        report.update(
            {
                "canonical_action_after": "walk",
                "walk_candidate_count_after": 1,
                "action_count_after": 1,
                "multi_key_fcurve_count": baked_stats["multi_key_fcurve_count"],
                "total_key_count": baked_stats["total_key_count"],
                "export_bytes": out.stat().st_size,
                "state": "CANONICAL_WALK_EXPORT_READY",
            }
        )
        write_report()
        print(
            "GATE8_STEVE_WALK_CANONICALIZATION_OK canonical=walk "
            "source_excitation_deg=%.6f baked_excitation_deg=%.6f "
            "moving_bones=%d bake_pos_error_m=%.9f bake_rot_error_deg=%.6f"
            % (
                source_motion["max_pose_excitation_deg"],
                baked_motion["max_pose_excitation_deg"],
                baked_motion["moving_bone_count"],
                baked_motion["max_bake_position_error_m"],
                baked_motion["max_bake_rotation_error_deg"],
            )
        )
    except Exception as exc:
        report["state"] = "FAILED"
        report["exception"] = repr(exc)
        report["traceback"] = traceback.format_exc()
        write_report()
        raise


if __name__ == "__main__":
    main()
