extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_TOP_LEVEL_CHILD_PLAYER_AUTHORITY_FAIL: %s" % message)
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
        _fail("witness requires no current_scene")
        return

    # A headless/dev world may itself be the OSM runtime root, with its canonical
    # Player parented beneath it. This is distinct from the existing direct-root
    # sibling harness and must not require borrowing authority from another world.
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "TopLevelBrusselsOsmEnvironment"
    runtime.set("data_path", JETTE_DATA)
    root.add_child(runtime)

    var player := Node3D.new()
    player.name = "Player"
    player.add_to_group("player")
    player.position = JETTE_SPAWN
    runtime.add_child(player)

    # Add an unrelated sibling world Player as a negative control: the runtime
    # must choose its own descendant rather than broadening authority globally.
    var sibling_world := Node3D.new()
    sibling_world.name = "SiblingWorld"
    root.add_child(sibling_world)
    var sibling_player := Node3D.new()
    sibling_player.name = "Player"
    sibling_player.add_to_group("player")
    sibling_player.position = JETTE_SPAWN + Vector3(500.0, 0.0, 500.0)
    sibling_world.add_child(sibling_player)

    for _frame: int in range(18):
        await process_frame

    if runtime.call("_target") != player:
        _fail("top-level runtime did not retain authority over its canonical child Player")
        return
    runtime.call("_refresh", true)
    if not _all_batches_visible(runtime, true):
        _fail("top-level runtime did not materialize trusted Jette batches for its child Player")
        return

    print("BRUSSELS_OSM_TOP_LEVEL_CHILD_PLAYER_AUTHORITY_OK: own_child_authorized=true sibling_world_rejected=true source=%s license=%s" % [str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
