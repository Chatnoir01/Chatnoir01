extends SceneTree

var scene_paths: Array[String] = []
var load_failures: Array[String] = []
var animation_names: Dictionary = {}
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
    var payload := {
        "format": "grand-bruxelles-quaternius-ik-godot-characterization-v1",
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
    }
    var output := FileAccess.open(args[0], FileAccess.WRITE)
    if output == null:
        push_error("cannot open output path: %s" % args[0])
        quit(3)
        return
    output.store_string(JSON.stringify(payload, "  "))
    output.close()
    print("QUATERNIUS_IK_GODOT_PROBE_OK scenes=%d skeletons=%d animations=%d" % [scene_count, skeleton_count, animations.size()])
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
            animation_names[str(animation_name)] = true
    if node is MeshInstance3D:
        mesh_instance_count += 1
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
            skinned_mesh_count += 1
    for child in node.get_children():
        _walk(child)
