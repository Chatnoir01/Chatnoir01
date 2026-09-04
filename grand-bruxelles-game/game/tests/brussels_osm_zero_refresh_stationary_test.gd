extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ZERO_REFRESH_STATIONARY_FAIL: %s" % message)
    quit(1)

func _first_batch_id(runtime: Node3D) -> int:
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            return child.get_instance_id()
    return 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)
    current_scene = world

    var player := Node3D.new()
    player.name = "Player"
    player.add_to_group("player")
    player.position = JETTE_SPAWN
    world.add_child(player)

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmZeroRefreshStationaryProbe"
    runtime.set("data_path", JETTE_DATA)
    runtime.set("refresh_distance_m", 0.0)
    world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var baseline_id := _first_batch_id(runtime)
    if baseline_id == 0:
        _fail("baseline did not materialize a source-backed Jette batch")
        return
    var baseline_anchor: Vector3 = runtime.get("_last_anchor")

    for _iteration: int in range(3):
        runtime.call("_refresh", false)
        if _first_batch_id(runtime) != baseline_id:
            _fail("stationary Player rebuilt OSM batches when refresh_distance_m == 0")
            return
        if runtime.get("_last_anchor") != baseline_anchor:
            _fail("stationary Player mutated OSM anchor when refresh_distance_m == 0")
            return

    player.position += Vector3(0.01, 0.0, 0.0)
    runtime.call("_refresh", false)
    if _first_batch_id(runtime) == baseline_id:
        _fail("non-zero horizontal movement did not rebuild with refresh_distance_m == 0")
        return

    print("BRUSSELS_OSM_ZERO_REFRESH_STATIONARY_OK: stationary_no_rebuild=true zero_threshold_motion_rebuild=true source=%s license=%s" % [str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
