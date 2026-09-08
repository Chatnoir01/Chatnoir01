extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const MISSING_DATA := "res://data/osm/zones/__missing__/environment.game.json"
const RESTORED_SAME_PATH_DATA := "user://brussels_osm_same_path_recovery.environment.game.json"

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

    # Regression: exported runtime configuration may be temporarily invalid while
    # a zone is being mounted/configured. The renderer must fail closed without
    # permanently disabling its process loop, then recover once configuration is valid.
    var config_runtime := RUNTIME_SCRIPT.new() as Node3D
    config_runtime.name = "StartupConfigurationRecoveryRuntime"
    config_runtime.set("data_path", JETTE_DATA)
    config_runtime.set("render_radius_m", -1.0)
    root.add_child(config_runtime)
    await process_frame
    if config_runtime.is_processing() == false:
        _fail("initial invalid configuration disabled processing and made later configuration recovery unreachable")
        return
    if _count_points(config_runtime) != 0 or config_runtime.has_meta("render_counts"):
        _fail("initial invalid configuration did not remain fail-closed")
        return
    config_runtime.set("render_radius_m", 350.0)
    await process_frame
    if _count_points(config_runtime) <= 0:
        _fail("runtime did not recover after startup configuration became valid")
        return
    if str(config_runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(config_runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("startup-configuration recovery restored incorrect provenance")
        return
    config_runtime.queue_free()
    await process_frame

    # Regression: a source can be temporarily unavailable when the runtime first
    # enters the tree. The runtime must remain alive so a later data_path change
    # can use the same fail-closed reload path exercised below.
    var startup_runtime := RUNTIME_SCRIPT.new() as Node3D
    startup_runtime.name = "StartupRecoveryRuntime"
    startup_runtime.set("data_path", MISSING_DATA)
    root.add_child(startup_runtime)
    await process_frame
    if startup_runtime.is_processing() == false:
        _fail("initial missing source disabled processing and made later source recovery unreachable")
        return
    if _count_points(startup_runtime) != 0 or startup_runtime.has_meta("source") or startup_runtime.has_meta("license"):
        _fail("initial missing source did not remain fail-closed")
        return
    startup_runtime.set("data_path", JETTE_DATA)
    await process_frame
    if _count_points(startup_runtime) <= 0:
        _fail("runtime did not recover after initial missing source became valid")
        return
    if str(startup_runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(startup_runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("initial-source recovery restored incorrect provenance")
        return
    startup_runtime.queue_free()
    await process_frame

    # Regression: availability may recover at the configured path itself (for
    # example an artifact mounted after the scene). data_path then never changes,
    # so the renderer must notice missing -> present without busy-retrying a
    # still-missing source every frame.
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RESTORED_SAME_PATH_DATA))
    var same_path_runtime := RUNTIME_SCRIPT.new() as Node3D
    same_path_runtime.name = "SamePathSourceRecoveryRuntime"
    same_path_runtime.set("data_path", RESTORED_SAME_PATH_DATA)
    root.add_child(same_path_runtime)
    await process_frame
    if same_path_runtime.is_processing() == false:
        _fail("same-path missing source disabled processing")
        return
    if _count_points(same_path_runtime) != 0 or same_path_runtime.has_meta("source") or same_path_runtime.has_meta("license"):
        _fail("same-path missing source did not remain fail-closed")
        return
    var canonical_text := FileAccess.get_file_as_string(JETTE_DATA)
    if canonical_text.is_empty():
        _fail("canonical Jette source could not be read for same-path recovery witness")
        return
    var restored_file := FileAccess.open(RESTORED_SAME_PATH_DATA, FileAccess.WRITE)
    if restored_file == null:
        _fail("same-path recovery witness could not create restored artifact")
        return
    restored_file.store_string(canonical_text)
    restored_file.close()
    for _frame: int in range(4):
        await process_frame
    if _count_points(same_path_runtime) <= 0:
        _fail("runtime did not recover when a missing source appeared at the unchanged data_path")
        return
    if str(same_path_runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(same_path_runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("same-path recovery restored incorrect provenance")
        return
    same_path_runtime.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RESTORED_SAME_PATH_DATA))

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

    print("BRUSSELS_OSM_SOURCE_PATH_REFRESH_OK: config_recovery=true initial_recovery=true same_path_recovery=true initial_points=%d stale_points=0 restored_points=%d" % [initial_count, _count_points(runtime)])
    quit(0)
