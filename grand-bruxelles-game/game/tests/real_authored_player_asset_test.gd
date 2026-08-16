extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const REAL_ASSET := "res://assets/characters/player_character.glb"

var skeleton_count := 0
var skinned_mesh_count := 0
var material_surface_count := 0
var animation_count := 0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("REAL_AUTHORED_PLAYER_FAIL: %s" % message)
    quit(1)

func _scan(node: Node) -> void:
    if node is Skeleton3D:
        skeleton_count += 1
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null:
            if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
                skinned_mesh_count += 1
            for surface_index in range(mesh_instance.mesh.get_surface_count()):
                if mesh_instance.mesh.surface_get_material(surface_index) != null:
                    material_surface_count += 1
    if node is AnimationPlayer:
        animation_count += (node as AnimationPlayer).get_animation_list().size()
    for child in node.get_children():
        _scan(child)

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _first_playable_animation(player: AnimationPlayer) -> StringName:
    for animation_name: String in player.get_animation_list():
        if animation_name != "RESET":
            return StringName(animation_name)
    return &""

func _run() -> void:
    if not ResourceLoader.exists(REAL_ASSET):
        _fail("Pinned CC0 authored player GLB was not imported")
        return
    var packed := ResourceLoader.load(REAL_ASSET)
    if not packed is PackedScene:
        _fail("Authored player GLB did not import as PackedScene")
        return
    var asset := (packed as PackedScene).instantiate()
    root.add_child(asset)
    await process_frame
    _scan(asset)
    if skeleton_count < 1:
        _fail("No Skeleton3D found in real GLB")
        return
    if skinned_mesh_count < 1:
        _fail("No skinned MeshInstance3D found in real GLB")
        return
    if material_surface_count < 1:
        _fail("No imported material found on real GLB mesh")
        return
    if animation_count < 1:
        _fail("No animations found in real GLB")
        return
    asset.queue_free()
    await process_frame

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)
    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame
    if not visual.is_using_authored_character():
        _fail("Production Player did not select a real authored character")
        return
    if visual.resolved_authored_scene_path() != REAL_ASSET:
        _fail("Production Player resolved unexpected asset: %s" % visual.resolved_authored_scene_path())
        return

    var animation_player := _find_animation_player(visual)
    if animation_player == null:
        _fail("Selected production authored player has no AnimationPlayer")
        return
    var playable := _first_playable_animation(animation_player)
    if playable == &"":
        _fail("Selected production authored player has no playable non-RESET animation")
        return
    animation_player.play(playable)
    animation_player.advance(0.05)
    if animation_player.current_animation != String(playable):
        _fail("Selected production authored animation did not play")
        return

    print("REAL_AUTHORED_PLAYER_OK path=%s skeletons=%d skinned_meshes=%d material_surfaces=%d animations=%d playing=%s" % [visual.resolved_authored_scene_path(), skeleton_count, skinned_mesh_count, material_surface_count, animation_count, String(playable)])
    quit(0)
