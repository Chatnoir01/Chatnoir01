extends SceneTree

const TARGET_SCENE := "res://civ1_body.glb"

func _init() -> void:
    call_deferred("_run")

func _fail(message: String, code: int) -> void:
    push_error("CIV1_SKIN_BIND_PREFLIGHT_FAIL: %s" % message)
    quit(code)

func _collect_skeletons(node: Node, result: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        result.append(node as Skeleton3D)
    for child in node.get_children():
        _collect_skeletons(child, result)

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _fail("target scene failed to load", 2)
        return
    var instance := packed.instantiate()
    root.add_child(instance)
    await process_frame

    var skeletons: Array[Skeleton3D] = []
    var meshes: Array[MeshInstance3D] = []
    _collect_skeletons(instance, skeletons)
    _collect_meshes(instance, meshes)
    if skeletons.size() != 1:
        _fail("expected exactly one Skeleton3D, got %d" % skeletons.size(), 3)
        return
    var skeleton := skeletons[0]
    var checked_skins := 0
    var checked_binds := 0
    for mesh in meshes:
        var skin := mesh.skin
        if skin == null:
            continue
        checked_skins += 1
        for bind_index in range(skin.get_bind_count()):
            checked_binds += 1
            var bind_name := skin.get_bind_name(bind_index)
            if bind_name != StringName():
                if skeleton.find_bone(bind_name) < 0:
                    _fail("mesh=%s bind=%d named bone '%s' missing from original Skeleton3D" % [mesh.name, bind_index, bind_name], 4)
                    return
            else:
                var bind_bone := skin.get_bind_bone(bind_index)
                if bind_bone < 0 or bind_bone >= skeleton.get_bone_count():
                    _fail("mesh=%s bind=%d indexed bone %d outside original Skeleton3D" % [mesh.name, bind_index, bind_bone], 5)
                    return
    if checked_skins == 0 or checked_binds == 0:
        _fail("no skinned mesh binds found", 6)
        return

    print("CIV1_SKIN_BIND_PREFLIGHT_OK skins=%d binds=%d bones=%d" % [checked_skins, checked_binds, skeleton.get_bone_count()])
    quit(0)
