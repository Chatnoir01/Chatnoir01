extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_NULL_CURRENT_SCENE_AUTHORITY_FAIL: %s" % message)
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
        _fail("baseline runtime did not select its authoritative scene Player")
        return
    if not _all_batches_visible(stale_runtime, true):
        _fail("baseline runtime did not materialize visible Jette batches")
        return

    # Reproduce the transition gap: SceneTree has no authoritative current_scene,
    # the old zone remains alive for deferred teardown, and another root-owned
    # world already exposes a Player group member. The stale zone renderer must
    # not use the global group fallback to borrow that unrelated Player.
    var replacement_world := Node3D.new()
    replacement_world.name = "ReplacementWorld"
    root.add_child(replacement_world)
    var replacement_player := Node3D.new()
    replacement_player.name = "Player"
    replacement_player.add_to_group("player")
    replacement_player.position = JETTE_SPAWN
    replacement_world.add_child(replacement_player)

    old_player.remove_from_group("player")
    current_scene = null

    if stale_runtime.call("_target") != null:
        _fail("nested stale runtime borrowed global Player authority while current_scene was null")
        return
    stale_runtime.call("_refresh", false)
    if not _all_batches_visible(stale_runtime, false):
        _fail("nested stale runtime kept old-zone OSM batches visible during null-current-scene transition")
        return

    # Positive control for existing headless harnesses: when no current_scene is
    # installed, only direct SceneTree-root runtime + Player siblings may use the
    # explicit fallback. This keeps test/dev use deterministic without reopening
    # cross-world authority for nested production scene nodes.
    replacement_player.remove_from_group("player")
    var harness_player := Node3D.new()
    harness_player.name = "HarnessPlayer"
    harness_player.add_to_group("player")
    harness_player.position = JETTE_SPAWN
    root.add_child(harness_player)

    var harness_runtime := RUNTIME_SCRIPT.new() as Node3D
    harness_runtime.name = "HarnessBrusselsOsmEnvironment"
    harness_runtime.set("data_path", JETTE_DATA)
    root.add_child(harness_runtime)
    for _frame: int in range(18):
        await process_frame

    if harness_runtime.call("_target") != harness_player:
        _fail("direct-root no-current-scene harness fallback was not preserved")
        return
    if not _all_batches_visible(harness_runtime, true):
        _fail("direct-root harness runtime did not materialize trusted OSM batches")
        return

    print("BRUSSELS_OSM_NULL_CURRENT_SCENE_AUTHORITY_OK: stale_nested_rejected=true root_harness_authorized=true source=%s license=%s" % [str(harness_runtime.get_meta("source", "")), str(harness_runtime.get_meta("license", ""))])
    quit(0)
