extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const REAL_ASSET := "res://assets/characters/player_character.glb"

func _fail(message: String) -> void:
    push_error("AUTHORED_PLAYER_LOCOMOTION_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if not ResourceLoader.exists(REAL_ASSET):
        _fail("real authored player asset is unavailable")
        return

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)
    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("Player did not select authored character")
        return
    if not visual.has_method("authored_locomotion_animations") or not visual.has_method("authored_current_animation"):
        _fail("production visual has no authored locomotion runtime contract")
        return

    var locomotion: Dictionary = visual.call("authored_locomotion_animations")
    for key: String in ["idle", "walk", "run"]:
        if String(locomotion.get(key, "")).is_empty():
            _fail("missing resolved %s animation" % key)
            return
    if String(locomotion["walk"]) == String(locomotion["run"]):
        _fail("walk and run resolved to the same animation")
        return

    actor.velocity = Vector3.ZERO
    await process_frame
    var idle_name := String(visual.call("authored_current_animation"))
    if idle_name != String(locomotion["idle"]):
        _fail("zero speed did not select idle: %s" % idle_name)
        return

    actor.velocity = Vector3(2.5, 0.0, 0.0)
    await process_frame
    var walk_name := String(visual.call("authored_current_animation"))
    if walk_name != String(locomotion["walk"]):
        _fail("walking speed did not select walk: %s" % walk_name)
        return

    actor.velocity = Vector3(7.0, 0.0, 0.0)
    await process_frame
    var run_name := String(visual.call("authored_current_animation"))
    if run_name != String(locomotion["run"]):
        _fail("running speed did not select run: %s" % run_name)
        return

    print("AUTHORED_PLAYER_LOCOMOTION_OK idle=%s walk=%s run=%s" % [idle_name, walk_name, run_name])
    quit(0)
