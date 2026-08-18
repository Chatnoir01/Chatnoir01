extends SceneTree

const AUTHORED_CHARACTER_PATH := "res://assets/characters/player_character.glb"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTHORED_NPC_ASSET_CONTRACT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(AUTHORED_CHARACTER_PATH):
        _fail("authored GLB is missing: %s" % AUTHORED_CHARACTER_PATH)
        return

    var packed := load(AUTHORED_CHARACTER_PATH) as PackedScene
    if packed == null:
        _fail("authored GLB did not import as PackedScene")
        return

    var instance := packed.instantiate()
    if instance == null:
        _fail("authored GLB could not instantiate")
        return
    root.add_child(instance)
    await process_frame

    var skeletons := instance.find_children("*", "Skeleton3D", true, false)
    var animation_players := instance.find_children("*", "AnimationPlayer", true, false)
    var animation_names: Array[String] = []
    for raw: Node in animation_players:
        var player := raw as AnimationPlayer
        if player == null:
            continue
        for raw_name: StringName in player.get_animation_list():
            var clip_name := str(raw_name)
            if clip_name not in animation_names:
                animation_names.append(clip_name)

    var skinned_meshes := 0
    for raw: Node in instance.find_children("*", "MeshInstance3D", true, false):
        var mesh := raw as MeshInstance3D
        if mesh != null and not mesh.skeleton.is_empty():
            skinned_meshes += 1

    print("AUTHORED_NPC_ASSET_INSPECT: skeletons=%d animation_players=%d animations=%s skinned_meshes=%d" % [skeletons.size(), animation_players.size(), str(animation_names), skinned_meshes])

    if skeletons.is_empty():
        _fail("committed authored GLB has no Skeleton3D; it is not a usable rigged NPC source")
        return
    if skinned_meshes < 1:
        _fail("committed authored GLB has no mesh bound to a Skeleton3D")
        return
    if animation_players.is_empty() or animation_names.is_empty():
        _fail("committed authored GLB has no AnimationPlayer clips; rig exists but locomotion is not authored")
        return

    print("AUTHORED_NPC_ASSET_CONTRACT_OK: path=%s skeletons=%d skinned_meshes=%d clips=%d" % [AUTHORED_CHARACTER_PATH, skeletons.size(), skinned_meshes, animation_names.size()])
    instance.queue_free()
    quit(0)
