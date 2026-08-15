extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const EXPECTED_PLAYER_ASSET := "res://assets/characters/player_character.glb"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PRODUCTION_PLAYER_BINARY_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not ResourceLoader.exists(EXPECTED_PLAYER_ASSET):
        _fail("authored binary missing: %s" % EXPECTED_PLAYER_ASSET)
        return

    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("could not load production main scene")
        return
    var main := packed.instantiate()
    root.add_child(main)

    for _frame in range(8):
        await process_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player node missing")
        return
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.has_method("is_using_authored_character"):
        _fail("production Player authored visual loader missing")
        return
    if not visual.is_using_authored_character():
        _fail("production Player is still procedural")
        return
    if visual.resolved_authored_scene_path() != EXPECTED_PLAYER_ASSET:
        _fail("production Player selected unexpected authored path: %s" % visual.resolved_authored_scene_path())
        return

    var authored := visual.get_node_or_null("AuthoredCharacter") as Node3D
    if authored == null:
        _fail("AuthoredCharacter instance missing")
        return

    var stats := {
        "skeletons": 0,
        "skinned_meshes": 0,
        "material_surfaces": 0,
        "animation_players": 0,
        "animation_names": PackedStringArray(),
    }
    _scan_authored(authored, stats)

    if int(stats.skeletons) < 1:
        _fail("imported character has no Skeleton3D")
        return
    if int(stats.skinned_meshes) < 1:
        _fail("imported character has no skinned MeshInstance3D")
        return
    if int(stats.material_surfaces) < 1:
        _fail("imported character has no material-bearing mesh surface")
        return
    if int(stats.animation_players) < 1 or (stats.animation_names as PackedStringArray).is_empty():
        _fail("imported character has no AnimationPlayer clips")
        return

    var names: PackedStringArray = stats.animation_names
    var has_idle := false
    var has_locomotion := false
    for animation_name in names:
        var lower := animation_name.to_lower()
        has_idle = has_idle or "idle" in lower
        has_locomotion = has_locomotion or "walk" in lower or "run" in lower or "jog" in lower or "sprint" in lower
    if not has_idle:
        _fail("no idle animation found: %s" % ", ".join(names))
        return
    if not has_locomotion:
        _fail("no walk/run/jog/sprint locomotion animation found: %s" % ", ".join(names))
        return

    if player.get_node_or_null("MeshInstance3D") is VisualInstance3D and (player.get_node("MeshInstance3D") as VisualInstance3D).visible:
        _fail("legacy capsule is visible while authored player is active")
        return

    print("PRODUCTION_PLAYER_BINARY_OK: path=%s skeletons=%d skinned_meshes=%d material_surfaces=%d animations=%d clips=%s" % [
        visual.resolved_authored_scene_path(),
        int(stats.skeletons),
        int(stats.skinned_meshes),
        int(stats.material_surfaces),
        names.size(),
        ",".join(names),
    ])
    main.queue_free()
    await process_frame
    quit(0)


func _scan_authored(node: Node, stats: Dictionary) -> void:
    if node is Skeleton3D:
        stats.skeletons = int(stats.skeletons) + 1
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
            stats.skinned_meshes = int(stats.skinned_meshes) + 1
        if mesh_instance.mesh != null:
            for surface_index in range(mesh_instance.mesh.get_surface_count()):
                if mesh_instance.mesh.surface_get_material(surface_index) != null or mesh_instance.material_override != null:
                    stats.material_surfaces = int(stats.material_surfaces) + 1
    if node is AnimationPlayer:
        stats.animation_players = int(stats.animation_players) + 1
        var player := node as AnimationPlayer
        for animation_name in player.get_animation_list():
            if animation_name != "RESET" and animation_name not in stats.animation_names:
                stats.animation_names.append(animation_name)
    for child in node.get_children():
        _scan_authored(child, stats)
