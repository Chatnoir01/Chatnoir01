extends SceneTree

const HUMANOID_SCRIPT := "res://game/scripts/humanoid_visual.gd"
const KNOWN_MISSING := [
    "res://assets/characters/player/thandi/Thandi.glb",
    "res://assets/characters/player/thandi/Thandi.fbx",
    "res://assets/characters/player_character.glb",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("HUMANOID_AUTHORED_RESOURCE_PROBE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    for path: String in KNOWN_MISSING:
        if ResourceLoader.exists(path):
            _fail("fixture path unexpectedly exists: %s" % path)
            return

    var source := FileAccess.get_file_as_string(HUMANOID_SCRIPT)
    if source.is_empty():
        _fail("humanoid visual script source is unreadable")
        return
    var exists_probe := source.find("ResourceLoader.exists(candidate)")
    var load_probe := source.find("load(candidate)")
    if exists_probe < 0:
        _fail("missing ResourceLoader.exists(candidate) guard before authored load")
        return
    if load_probe < 0 or exists_probe > load_probe:
        _fail("authored resource existence guard must precede load(candidate)")
        return

    var player := CharacterBody3D.new()
    player.name = "Player"
    root.add_child(player)
    var visual := Node3D.new()
    visual.set_script(load(HUMANOID_SCRIPT))
    player.add_child(visual)
    for _frame: int in range(3):
        await process_frame
    if visual.call("is_using_authored_character"):
        _fail("missing authored candidates must not create an authored character")
        return
    if String(visual.call("resolved_authored_scene_path")) != "":
        _fail("missing candidates must leave resolved authored path empty")
        return
    if visual.get_node_or_null("Torso") == null:
        _fail("procedural player fallback did not build after missing authored candidates")
        return

    print("HUMANOID_AUTHORED_RESOURCE_PROBE_OK: missing=%d procedural_fallback=true" % KNOWN_MISSING.size())
    player.queue_free()
    quit(0)
