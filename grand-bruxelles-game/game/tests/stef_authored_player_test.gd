extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const STEF_PATH := "res://assets/characters/player/stef/Stef.glb"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("STEF_AUTHORED_PLAYER_FAIL: %s" % message)
    quit(1)


func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child in node.get_children():
        out.append(child)
        out.append_array(_descendants(child))
    return out


func _run() -> void:
    if not ResourceLoader.exists(STEF_PATH):
        _fail("Stef GLB does not exist at production candidate path")
        return

    var packed := load(STEF_PATH) as PackedScene
    if packed == null:
        _fail("Stef GLB did not import as PackedScene")
        return

    var direct := packed.instantiate()
    root.add_child(direct)
    await process_frame

    var all_nodes := _descendants(direct)
    var skeleton_count := 0
    var skinned_meshes := 0
    var material_surfaces := 0
    var animation_players: Array[AnimationPlayer] = []
    var animation_names: Array[StringName] = []

    for node in all_nodes:
        if node is Skeleton3D:
            skeleton_count += 1
        elif node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
                skinned_meshes += 1
            if mesh_instance.mesh != null:
                for surface_index in mesh_instance.mesh.get_surface_count():
                    if mesh_instance.get_active_material(surface_index) != null:
                        material_surfaces += 1
        elif node is AnimationPlayer:
            var player := node as AnimationPlayer
            animation_players.append(player)
            for library_name in player.get_animation_library_list():
                var library := player.get_animation_library(library_name)
                if library == null:
                    continue
                for animation_name in library.get_animation_list():
                    if animation_name != &"RESET":
                        animation_names.append(animation_name)

    if skeleton_count < 1:
        _fail("Imported Stef has no Skeleton3D")
        return
    if skinned_meshes < 1:
        _fail("Imported Stef has no skinned MeshInstance3D")
        return
    if material_surfaces < 1:
        _fail("Imported Stef has no active material surfaces")
        return
    if animation_names.is_empty():
        _fail("Imported Stef has no authored animation clips")
        return

    var played_animation := StringName()
    for player in animation_players:
        var libraries := player.get_animation_library_list()
        for library_name in libraries:
            var library := player.get_animation_library(library_name)
            if library == null:
                continue
            for animation_name in library.get_animation_list():
                if animation_name == &"RESET":
                    continue
                player.play(animation_name)
                played_animation = animation_name
                await process_frame
                break
            if played_animation != StringName():
                break
        if played_animation != StringName():
            break

    if played_animation == StringName():
        _fail("No Stef animation could be played")
        return

    direct.queue_free()
    await process_frame

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)
    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("Production Player still fell back to procedural humanoid")
        return
    if visual.resolved_authored_scene_path() != STEF_PATH:
        _fail("Production Player did not resolve Stef path: %s" % visual.resolved_authored_scene_path())
        return

    print(
        "STEF_AUTHORED_PLAYER_OK: path=%s skeletons=%d skinned_meshes=%d material_surfaces=%d animations=%d played=%s" % [
            STEF_PATH,
            skeleton_count,
            skinned_meshes,
            material_surfaces,
            animation_names.size(),
            String(played_animation),
        ]
    )
    quit(0)
