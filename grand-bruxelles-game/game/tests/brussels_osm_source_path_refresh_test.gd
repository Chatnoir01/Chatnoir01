extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const MISSING_DATA := "res://data/osm/zones/__missing__/environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SOURCE_PATH_REFRESH_FAIL: %s" % message)
    quit(1)

func _count_points(runtime: Node3D) -> int:
    var points := runtime.get("_points") as Dictionary
    return (points["tree"] as Array).size() + (points["street_lamp"] as Array).size() + (points["bollard"] as Array).size()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var player := Node3D.new()
    player.name = "Player"
    root.add_child(player)
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "EnvironmentRuntime"
    runtime.set("data_path", JETTE_DATA)
    root.add_child(runtime)
    if not bool(runtime.call("_load_points")):
        _fail("canonical Jette source did not load")
        return
    var initial_count := _count_points(runtime)
    if initial_count <= 0:
        _fail("canonical Jette source unexpectedly empty")
        return

    runtime.set("data_path", MISSING_DATA)
    runtime.call("_refresh", true)
    if _count_points(runtime) != 0:
        _fail("changing data_path to an invalid source retained stale source points")
        return
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("invalid replacement source retained stale provenance")
        return

    runtime.set("data_path", JETTE_DATA)
    runtime.call("_refresh", true)
    if _count_points(runtime) != initial_count:
        _fail("restoring canonical data_path did not reload the source")
        return
    if str(runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("restored source provenance is incorrect")
        return

    print("BRUSSELS_OSM_SOURCE_PATH_REFRESH_OK: initial_points=%d stale_points=0 restored_points=%d" % [initial_count, _count_points(runtime)])
    quit(0)
