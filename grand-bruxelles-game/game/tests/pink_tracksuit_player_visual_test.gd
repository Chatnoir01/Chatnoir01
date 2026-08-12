extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/pink_tracksuit_player_visual.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PINK_TRACKSUIT_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var actor := CharacterBody3D.new()
    actor.name = "PlayerTestActor"
    root.add_child(actor)

    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)

    var visual := VISUAL_SCRIPT.new() as PinkTracksuitPlayerVisual
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame

    if visual.character_signature() != "pink_tracksuit_v1":
        _fail("unexpected character signature")
        return
    if legacy.visible:
        _fail("legacy capsule must be hidden")
        return

    for required_name in ["UpperTorso", "CropTop", "Hips", "HairBun", "ShoulderBag", "Phone", "LeftTrouserStripe", "RightTrouserStripe"]:
        if visual.get_node_or_null(required_name) == null:
            _fail("missing required visual node: %s" % required_name)
            return

    if visual.get_child_count() < 20:
        _fail("character visual is unexpectedly incomplete")
        return

    print("PINK_TRACKSUIT_VISUAL_OK: approved silhouette, outfit, hair and accessories instantiated")
    actor.queue_free()
    quit(0)
