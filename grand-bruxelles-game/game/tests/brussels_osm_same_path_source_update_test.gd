extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const LIVE_COPY := "user://brussels_osm_same_path_success_reload.environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SAME_PATH_SOURCE_UPDATE_FAIL: %s" % message)
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

    DirAccess.remove_absolute(ProjectSettings.globalize_path(LIVE_COPY))
    var canonical_text := FileAccess.get_file_as_string(JETTE_DATA)
    if canonical_text.is_empty():
        _fail("canonical Jette source could not be read")
        return

    var initial_file := FileAccess.open(LIVE_COPY, FileAccess.WRITE)
    if initial_file == null:
        _fail("could not create mutable same-path source copy")
        return
    initial_file.store_string(canonical_text)
    initial_file.close()

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "SamePathSuccessfulSourceUpdateRuntime"
    runtime.set("data_path", LIVE_COPY)
    root.add_child(runtime)
    await process_frame

    var initial_count := _count_points(runtime)
    if initial_count <= 1:
        _fail("canonical source did not produce enough points for replacement witness")
        return
    if str(runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("initial mutable source copy loaded incorrect provenance")
        return

    var parsed: Variant = JSON.parse_string(canonical_text)
    if not parsed is Dictionary:
        _fail("canonical Jette source was not a JSON object")
        return
    var replacement := (parsed as Dictionary).duplicate(true)
    var points_variant: Variant = replacement.get("environment_points", null)
    if not points_variant is Array:
        _fail("canonical Jette source has no environment_points array")
        return
    var replacement_points := points_variant as Array
    if replacement_points.size() != initial_count:
        _fail("runtime/source point count mismatch before replacement")
        return
    replacement_points.remove_at(replacement_points.size() - 1)
    replacement["environment_points"] = replacement_points

    var replacement_text := JSON.stringify(replacement) + "\n"
    var replacement_file := FileAccess.open(LIVE_COPY, FileAccess.WRITE)
    if replacement_file == null:
        _fail("could not replace mutable source at unchanged path")
        return
    replacement_file.store_string(replacement_text)
    replacement_file.close()

    # Force a renderer refresh without changing data_path. Source authority must
    # follow the successfully replaced artifact rather than keep stale points.
    runtime.call("_refresh", true)
    var reloaded_count := _count_points(runtime)
    if reloaded_count != initial_count - 1:
        _fail("successful same-path source replacement retained stale points: before=%d after=%d expected=%d" % [initial_count, reloaded_count, initial_count - 1])
        return
    if str(runtime.get("_loaded_data_path")) != LIVE_COPY:
        _fail("successful same-path reload changed loaded_data_path identity")
        return
    if str(runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("successful same-path reload changed provenance")
        return

    runtime.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(LIVE_COPY))
    print("BRUSSELS_OSM_SAME_PATH_SOURCE_UPDATE_OK: path_unchanged=true before=%d after=%d provenance_preserved=true" % [initial_count, reloaded_count])
    quit(0)
