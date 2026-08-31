extends SceneTree

var scene_paths: Array[String] = []
var load_failures: Array[String] = []
var animation_names: Dictionary = {}
var animation_metrics: Dictionary = {}
var animation_metric_conflicts: Array[String] = []
var bone_names: Dictionary = {}
var scene_count := 0
var skeleton_count := 0
var animation_player_count := 0
var mesh_instance_count := 0
var skinned_mesh_count := 0

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        push_error("usage: godot --headless --script res://probe.gd -- <output.json>")
        quit(2)
        return
    _scan_dir("res://")
    scene_paths.sort()
    for path in scene_paths:
        var resource := load(path)
        if not (resource is PackedScene):
            load_failures.append(path)
            continue
        var instance := (resource as PackedScene).instantiate()
        if instance == null:
            load_failures.append(path)
            continue
        scene_count += 1
        _walk(instance)
        instance.free()
    var animations := animation_names.keys()
    animations.sort()
    var bones := bone_names.keys()
    bones.sort()
    animation_metric_conflicts.sort()
    var payload := {
        "format": "grand-bruxelles-quaternius-ik-godot-characterization-v2",
        "godot_version": Engine.get_version_info(),
        "scene_candidates": scene_paths,
        "loaded_scene_count": scene_count,
        "load_failures": load_failures,
        "skeleton_count": skeleton_count,
        "animation_player_count": animation_player_count,
        "mesh_instance_count": mesh_instance_count,
        "skinned_mesh_count": skinned_mesh_count,
        "bone_names": bones,
        "animation_names": animations,
        "animation_metrics": animation_metrics,
        "animation_metric_conflicts": animation_metric_conflicts,
    }
    var output := FileAccess.open(args[0], FileAccess.WRITE)
    if output == null:
        push_error("cannot open output path: %s" % args[0])
        quit(3)
        return
    output.store_string(JSON.stringify(payload, "  "))
    output.close()
    print("QUATERNIUS_IK_GODOT_PROBE_OK scenes=%d skeletons=%d animations=%d metric_conflicts=%d" % [scene_count, skeleton_count, animations.size(), animation_metric_conflicts.size()])
    quit(0)

func _scan_dir(path: String) -> void:
    var dir := DirAccess.open(path)
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if name.begins_with("."):
            continue
        var child := path.path_join(name)
        if dir.current_is_dir():
            _scan_dir(child)
            continue
        var ext := name.get_extension().to_lower()
        if ext in ["tscn", "scn", "glb", "gltf"]:
            scene_paths.append(child)
    dir.list_dir_end()

func _record_animation(player: AnimationPlayer, animation_name: StringName) -> void:
    var key := str(animation_name)
    animation_names[key] = true
    var animation := player.get_animation(animation_name)
    if animation == null:
        return
    var metric := {
        "length_seconds": animation.length,
        "loop_mode": int(animation.loop_mode),
        "track_count": animation.get_track_count(),
    }
    if not animation_metrics.has(key):
        animation_metrics[key] = metric
        return
    var previous: Dictionary = animation_metrics[key]
    if not is_equal_approx(float(previous["length_seconds"]), float(metric["length_seconds"])) or int(previous["loop_mode"]) != int(metric["loop_mode"]) or int(previous["track_count"]) != int(metric["track_count"]):
        if not animation_metric_conflicts.has(key):
            animation_metric_conflicts.append(key)

func _walk(node: Node) -> void:
    if node is Skeleton3D:
        skeleton_count += 1
        var skeleton := node as Skeleton3D
        for index in range(skeleton.get_bone_count()):
            bone_names[str(skeleton.get_bone_name(index))] = true
    if node is AnimationPlayer:
        animation_player_count += 1
        var player := node as AnimationPlayer
        for animation_name in player.get_animation_list():
            _record_animation(player, animation_name)
    if node is MeshInstance3D:
        mesh_instance_count += 1
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
            skinned_mesh_count += 1
    for child in node.get_children():
        _walk(child)
