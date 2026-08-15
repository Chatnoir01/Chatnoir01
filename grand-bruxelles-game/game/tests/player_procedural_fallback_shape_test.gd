extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_PROCEDURAL_FALLBACK_SHAPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var player := CharacterBody3D.new()
    player.name = "Player"
    root.add_child(player)
    var visual := Node3D.new()
    visual.set_script(load("res://game/scripts/humanoid_visual.gd"))
    player.add_child(visual)
    for _frame: int in range(3):
        await process_frame

    if visual.call("is_using_authored_character"):
        _fail("fixture unexpectedly resolved an authored player")
        return
    var torso := visual.get_node_or_null("Torso") as MeshInstance3D
    if torso == null:
        _fail("procedural fallback has no Torso")
        return
    if not (torso.mesh is ArrayMesh):
        _fail("player Torso must use shaped ArrayMesh fallback, got %s" % torso.mesh.get_class())
        return
    var hips := visual.get_node_or_null("Hips") as MeshInstance3D
    if hips == null or not (hips.mesh is ArrayMesh):
        _fail("player Hips must use shaped ArrayMesh fallback")
        return
    for limb_name: String in ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
        var limb := visual.get_node_or_null(limb_name) as MeshInstance3D
        if limb == null or not (limb.mesh is ArrayMesh):
            _fail("%s must use shaped ArrayMesh fallback" % limb_name)
            return
    if visual.get_node_or_null("Shoulders") != null:
        _fail("legacy rectangular Shoulders mass remains")
        return

    print("PLAYER_PROCEDURAL_FALLBACK_SHAPE_OK: torso=%s hips=%s" % [torso.mesh.get_class(), hips.mesh.get_class()])
    player.queue_free()
    quit(0)
