extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_STALE_RUNTIME_SCENE_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _all_batches_visible(runtime: Node3D, expected: bool) -> bool:
    var seen := 0
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            seen += 1
            if (child as MultiMeshInstance3D).visible != expected:
                return false
    return seen > 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if current_scene != null:
        _fail("witness requires no current_scene before setup")
        return

    var old_world := Node3D.new()
    old_world.name = "OldJetteWorld"
    root.add_child(old_world)
    current_scene = old_world

    var old_player := Node3D.new()
    old_player.name = "Player"
    old_player.add_to_group("player")
    old_player.position = JETTE_SPAWN
    old_world.add_child(old_player)

    var stale_runtime := RUNTIME_SCRIPT.new() as Node3D
    stale_runtime.name = "BrusselsOsmEnvironment"
    stale_runtime.set("data_path", JETTE_DATA)
    old_world.add_child(stale_runtime)

    for _frame: int in range(18):
        await process_frame

    if stale_runtime.call("_target") != old_player:
        _fail("baseline runtime did not select its current-scene Player")
        return
    if not _all_batches_visible(stale_runtime, true):
        _fail("baseline runtime did not materialize visible Jette batches")
        return

    # Simulate scene replacement before deferred teardown of the old zone. The
    # stale runtime remains alive under the old scene while current_scene now
    # points at the replacement scene. A renderer must never borrow Player
    # authority from that replacement scene and re-expose old-zone OSM content.
    var replacement_world := Node3D.new()
    replacement_world.name = "ReplacementWorld"
    root.add_child(replacement_world)
    var replacement_player := Node3D.new()
    replacement_player.name = "Player"
    replacement_player.add_to_group("player")
    replacement_player.position = JETTE_SPAWN
    replacement_world.add_child(replacement_player)
    current_scene = replacement_world

    if stale_runtime.call("_target") != null:
        _fail("stale out-of-scene runtime borrowed Player authority from replacement current_scene")
        return
    stale_runtime.call("_refresh", false)
    if not _all_batches_visible(stale_runtime, false):
        _fail("stale out-of-scene runtime kept old-zone OSM batches visible after scene replacement")
        return

    # Positive control: a renderer owned by the replacement scene may use that
    # scene's canonical Player and must still load the same trusted source.
    var replacement_runtime := RUNTIME_SCRIPT.new() as Node3D
    replacement_runtime.name = "ReplacementBrusselsOsmEnvironment"
    replacement_runtime.set("data_path", JETTE_DATA)
    replacement_world.add_child(replacement_runtime)
    for _frame: int in range(18):
        await process_frame
    if replacement_runtime.call("_target") != replacement_player:
        _fail("replacement-scene runtime could not select replacement current_scene/Player")
        return
    if not _all_batches_visible(replacement_runtime, true):
        _fail("replacement-scene runtime did not materialize trusted OSM batches")
        return

    print("BRUSSELS_OSM_STALE_RUNTIME_SCENE_AUTHORITY_OK: stale_runtime_rejected=true replacement_runtime_authorized=true source=%s license=%s" % [str(replacement_runtime.get_meta("source", "")), str(replacement_runtime.get_meta("license", ""))])
    quit(0)
