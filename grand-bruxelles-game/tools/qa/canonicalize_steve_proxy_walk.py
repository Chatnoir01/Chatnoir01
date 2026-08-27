import bpy
import json
import sys
import traceback
from pathlib import Path


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
    return {"name": action.name, "fcurve_count": curves, "multi_key_fcurve_count": multi, "total_key_count": total}


def score(stats):
    return (stats["multi_key_fcurve_count"], stats["total_key_count"], stats["fcurve_count"])


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


def main():
    inp = Path(arg("--input", "/tmp/steve_reviewed_proxy.glb"))
    out = Path(arg("--output", "/tmp/steve_reviewed_proxy_canonical.glb"))
    report_path = Path(arg("--report", "/tmp/steve-walk-canonicalization.json"))
    report = {"format": "grand-bruxelles-steve-reviewed-walk-canonicalization-v2", "state": "STARTED", "runtime_alias_published": False, "production_authorized": False}
    def write_report(): report_path.write_text(json.dumps(report, indent=2, sort_keys=True))
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
        report["candidate_count_before"] = len(candidates)
        assert len(candidates) >= 1, report["candidate_actions_before"]
        selected = max(candidates, key=lambda a: score(action_stats(a)))
        selected_stats = action_stats(selected)
        assert selected_stats["multi_key_fcurve_count"] > 0, selected_stats
        exact_walks = [a for a in candidates if normalized_walk_name(a.name) == "walk"]
        assert len(exact_walks) <= 1, [a.name for a in exact_walks]
        exact_stats = action_stats(exact_walks[0]) if exact_walks else None
        duplicate_identity_present = len(candidates) > 1
        if exact_stats is not None and exact_walks[0] != selected:
            assert score(selected_stats) > score(exact_stats), (selected_stats, exact_stats)
        if arm.animation_data is None: arm.animation_data_create()
        for track in arm.animation_data.nla_tracks: track.mute = True
        arm.animation_data.action = selected
        for action in list(candidates):
            if action != selected: bpy.data.actions.remove(action)
        selected.name = "walk"
        remaining_walks = [a for a in bpy.data.actions if is_walk_candidate(a.name)]
        assert len(remaining_walks) == 1, [a.name for a in remaining_walks]
        final_stats = action_stats(remaining_walks[0])
        assert final_stats["multi_key_fcurve_count"] == selected_stats["multi_key_fcurve_count"]
        assert final_stats["total_key_count"] == selected_stats["total_key_count"]
        select_hierarchy(arm)
        bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_animations=True, export_draco_mesh_compression_enable=False)
        assert out.is_file() and out.stat().st_size > 0
        report.update({"selected_action_before": selected_stats["name"], "selected_action_stats": selected_stats, "exact_walk_before_stats": exact_stats, "duplicate_walk_identity_present": duplicate_identity_present, "canonical_action_after": "walk", "walk_candidate_count_after": 1, "export_bytes": out.stat().st_size, "state": "CANONICAL_WALK_EXPORT_READY"})
        write_report()
        print("GATE8_STEVE_WALK_CANONICALIZATION_OK selected=%s candidates_before=%d duplicate_before=%s multi_key_fcurves=%d total_keys=%d canonical=walk candidates_after=1 bytes=%d" % (selected_stats["name"], len(candidates), str(duplicate_identity_present).lower(), selected_stats["multi_key_fcurve_count"], selected_stats["total_key_count"], out.stat().st_size))
    except Exception as exc:
        report["state"] = "FAILED"; report["exception"] = repr(exc); report["traceback"] = traceback.format_exc(); write_report(); raise


if __name__ == "__main__": main()
