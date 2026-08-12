extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/pink_tracksuit_player_visual.gd")
const AUTHORED_FIXTURE := "res://game/tests/fixtures/rigged_character_fixture.tscn"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PINK_TRACKSUIT_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not await _test_fallback_character():
        return
    if not await _test_authored_character_loader():
        return
    print("PINK_TRACKSUIT_VISUAL_OK: fallback remains valid and authored rigged scene loads as the primary player visual")
    quit(0)

func _test_fallback_character() -> bool:
    var actor := CharacterBody3D.new()
    actor.name = "FallbackPlayerTestActor"
    root.add_child(actor)

    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)

    var visual := VISUAL_SCRIPT.new() as PinkTracksuitPlayerVisual
    visual.name = "VisualUpgrade"
    visual.authored_scene_path = ""
    actor.add_child(visual)
    await process_frame

    if visual.character_signature() != "pink_tracksuit_v1":
        _fail("unexpected character signature")
        return false
    if visual.pipeline_signature() != "authored_glb_or_procedural_v2":
        _fail("unexpected render pipeline signature")
        return false
    if visual.is_using_authored_character():
        _fail("fallback test unexpectedly loaded an authored character")
        return false
    if legacy.visible:
        _fail("legacy capsule must be hidden")
        return false

    for required_name in ["UpperTorso", "CropTop", "Hips", "HairBun", "ShoulderBag", "Phone", "LeftTrouserStripe", "RightTrouserStripe"]:
        if visual.get_node_or_null(required_name) == null:
            _fail("missing fallback visual node: %s" % required_name)
            return false

    actor.queue_free()
    await process_frame
    return true

func _test_authored_character_loader() -> bool:
    var actor := CharacterBody3D.new()
    actor.name = "AuthoredPlayerTestActor"
    root.add_child(actor)

    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)

    var visual := VISUAL_SCRIPT.new() as PinkTracksuitPlayerVisual
    visual.name = "VisualUpgrade"
    visual.authored_scene_path = AUTHORED_FIXTURE
    visual.authored_position = Vector3(0.0, -0.9, 0.0)
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("authored character fixture was not selected")
        return false
    if legacy.visible:
        _fail("legacy capsule must stay hidden with authored character")
        return false
    var authored := visual.authored_character()
    if authored == null or authored.name != "AuthoredCharacter":
        _fail("authored character instance missing")
        return false
    if authored.get_node_or_null("Skeleton3D") == null:
        _fail("authored fixture skeleton missing")
        return false
    if visual.get_node_or_null("UpperTorso") != null:
        _fail("procedural fallback must not be built when authored asset loads")
        return false

    actor.queue_free()
    await process_frame
    return true
