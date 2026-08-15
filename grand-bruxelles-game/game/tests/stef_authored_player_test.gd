extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const STEF_PATH := "res://assets/characters/player/stef/Stef.glb"
const MIN_WALK_BONE_TRACKS := 8


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


func _valid_bone_tracks(scene_root: Node, animation: Animation) -> int:
    var valid := 0
    for track_index in animation.get_track_count():
        var track_type := animation.track_get_type(track_index)
        if track_type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
            continue
        var path := animation.track_get_path(track_index)
        if path.get_subname_count() < 1:
            continue
        var node_path_text := String(path).split(":", false, 1)[0]
        var target := scene_root.get_node_or_null(NodePath(node_path_text))
        if target is Skeleton3D:
            var bone_name := StringName(path.get_subname(0))
            if (target as Skeleton3D).find_bone(bone_name) >= 0:
                valid += 1
    return valid


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
    var total_bones := 0
    var skinned_meshes := 0
    var material_surfaces := 0
    var animation_players: Array[AnimationPlayer] = []
    var animation_names: Array[StringName] = []
    var walk_player: AnimationPlayer = null
    var walk_animation_name := StringName()
    var walk_animation: Animation = null

    for node in all_nodes:
        if node is Skeleton3D:
            skeleton_count += 1
            total_bones += (node as Skeleton3D).get_bone_count()
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
                    if animation_name == &"RESET":
                        continue
                    animation_names.append(animation_name)
                    if String(animation_name).to_lower().contains("walk"):
                        walk_player = player
                        walk_animation_name = animation_name
                        walk_animation = library.get_animation(animation_name)

    if skeleton_count < 1 or total_bones < 1:
        _fail("Imported Stef has no usable Skeleton3D bones")
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
    if walk_player == null or walk_animation == null:
        _fail("Imported Stef has no walk locomotion clip")
        return
    if walk_animation.length < 0.2:
        _fail("Stef walk clip is unexpectedly short: %.3fs" % walk_animation.length)
        return

    var valid_walk_bone_tracks := _valid_bone_tracks(direct, walk_animation)
    if valid_walk_bone_tracks < MIN_WALK_BONE_TRACKS:
        _fail("Stef walk clip has too few valid Skeleton3D bone tracks: %d" % valid_walk_bone_tracks)
        return

    walk_player.play(walk_animation_name)
    walk_player.seek(minf(0.25, walk_animation.length * 0.5), true)
    walk_player.advance(0.0)
    await process_frame
    if walk_player.current_animation != walk_animation_name:
        _fail("Stef walk locomotion clip did not remain active")
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
        "STEF_AUTHORED_PLAYER_OK: path=%s skeletons=%d bones=%d skinned_meshes=%d material_surfaces=%d animations=%d walk=%s walk_length=%.3f valid_walk_bone_tracks=%d" % [
            STEF_PATH,
            skeleton_count,
            total_bones,
            skinned_meshes,
            material_surfaces,
            animation_names.size(),
            String(walk_animation_name),
            walk_animation.length,
            valid_walk_bone_tracks,
        ]
    )
    quit(0)
