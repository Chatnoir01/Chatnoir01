extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PRODUCTION_PLAYER_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main_source := FileAccess.get_file_as_string("res://game/main.tscn")
    if main_source.is_empty():
        _fail("main.tscn could not be read")
        return
    if 'path="res://game/scripts/humanoid_visual.gd"' not in main_source:
        _fail("production player is no longer wired through humanoid_visual.gd")
        return

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)

    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)

    var visual := VISUAL_SCRIPT.new()
    visual.name = "VisualUpgrade"
    visual.authored_scene_path = "res://assets/characters/player/does-not-exist.glb"
    visual.allow_authored_fallback_paths = false
    actor.add_child(visual)
    await process_frame

    if visual.is_using_authored_character():
        _fail("identity fallback unexpectedly loaded an authored asset")
        return
    if visual.visual_signature() != "pink_tracksuit_procedural_v1":
        _fail("production fallback does not expose canonical pink identity: %s" % visual.visual_signature())
        return

    for required_name: String in ["CropTop", "LeftTrouserStripe", "RightTrouserStripe", "ShoulderBag", "BagStrap", "Phone", "HairBun"]:
        if visual.get_node_or_null(required_name) == null:
            _fail("production fallback missing canonical identity detail: %s" % required_name)
            return

    var torso := visual.get_node_or_null("Torso") as MeshInstance3D
    var hips := visual.get_node_or_null("Hips") as MeshInstance3D
    if torso == null or hips == null:
        _fail("production fallback body missing")
        return
    if not torso.mesh is ArrayMesh or not hips.mesh is ArrayMesh:
        _fail("identity lot must preserve profiled ArrayMesh body from #368")
        return

    print("PRODUCTION_PLAYER_IDENTITY_OK: canonical pink tracksuit identity is active on production humanoid fallback")
    actor.queue_free()
    quit(0)
