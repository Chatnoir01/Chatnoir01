extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const AUTHORED_FIXTURE := "res://game/tests/fixtures/rigged_character_fixture.tscn"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("HUMANOID_AUTHORED_PLAYER_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not await _test_authored_player_selected():
        return
    if not await _test_player_fallback_remains_safe():
        return
    if not await _test_police_never_uses_player_asset():
        return
    print("HUMANOID_AUTHORED_PLAYER_OK: production player visual selects a real authored scene when available and preserves safe civilian/police fallback behavior")
    quit(0)


func _test_authored_player_selected() -> bool:
    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)

    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)

    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    visual.authored_player_scene_path = AUTHORED_FIXTURE
    visual.allow_authored_fallback_paths = false
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("Player did not select the authored fixture")
        return false
    if visual.resolved_authored_scene_path() != AUTHORED_FIXTURE:
        _fail("Resolved authored path was not recorded")
        return false
    if legacy.visible:
        _fail("Legacy player capsule must be hidden")
        return false

    var authored: Node3D = visual.authored_character()
    if authored == null or authored.name != "AuthoredCharacter":
        _fail("Authored player instance missing")
        return false
    if authored.get_node_or_null("Skeleton3D") == null:
        _fail("Authored player skeleton missing")
        return false
    if visual.get_node_or_null("Torso") != null:
        _fail("Procedural humanoid must not be built when authored player loads")
        return false

    actor.queue_free()
    await process_frame
    return true


func _test_player_fallback_remains_safe() -> bool:
    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)

    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    visual.authored_player_scene_path = "res://assets/characters/player/does-not-exist.glb"
    visual.allow_authored_fallback_paths = false
    actor.add_child(visual)
    await process_frame

    if visual.is_using_authored_character():
        _fail("Missing authored asset unexpectedly loaded")
        return false
    if visual.get_node_or_null("Torso") == null or visual.get_node_or_null("Head") == null:
        _fail("Procedural safety fallback was not built")
        return false

    actor.queue_free()
    await process_frame
    return true


func _test_police_never_uses_player_asset() -> bool:
    var actor := CharacterBody3D.new()
    actor.name = "PoliceTestActor"
    actor.add_to_group("police_officer")
    root.add_child(actor)

    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    visual.authored_player_scene_path = AUTHORED_FIXTURE
    visual.allow_authored_fallback_paths = false
    actor.add_child(visual)
    await process_frame

    if visual.is_using_authored_character():
        _fail("Police actor must not load the authored player character")
        return false
    if visual.get_node_or_null("HiVisVest") == null:
        _fail("Police fallback uniform was not preserved")
        return false

    actor.queue_free()
    await process_frame
    return true
