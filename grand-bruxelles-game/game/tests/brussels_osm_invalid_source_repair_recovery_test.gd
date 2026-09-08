extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const LIVE_COPY := "user://brussels_osm_invalid_repair.environment.game.json"
const REQUIRED_SOURCE := "OpenStreetMap contributors via Overpass API"
const REQUIRED_LICENSE := "ODbL-1.0"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_INVALID_SOURCE_REPAIR_RECOVERY_FAIL: %s" % message)
    quit(1)

func _point_count(runtime: Node3D) -> int:
    var points := runtime.get("_points") as Dictionary
    return (points["tree"] as Array).size() + (points["street_lamp"] as Array).size() + (points["bollard"] as Array).size()

func _write(path: String, text: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    return true

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var canonical_text := FileAccess.get_file_as_string(JETTE_DATA)
    var canonical: Variant = JSON.parse_string(canonical_text)
    if not canonical is Dictionary:
        _fail("canonical Jette source is not valid JSON")
        return
    var canonical_rows := (canonical as Dictionary).get("environment_points", []) as Array
    if canonical_rows.is_empty():
        _fail("canonical Jette source has no environment points")
        return

    var live_absolute := ProjectSettings.globalize_path(LIVE_COPY)
    DirAccess.remove_absolute(live_absolute)
    if not _write(LIVE_COPY, canonical_text):
        _fail("could not stage canonical source")
        return

    var player := Node3D.new()
    player.name = "Player"
    root.add_child(player)
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.set("data_path", LIVE_COPY)
    root.add_child(runtime)
    await process_frame
    await process_frame

    var initial_count := _point_count(runtime)
    if initial_count != canonical_rows.size():
        _fail("initial canonical source did not load: expected=%d actual=%d" % [canonical_rows.size(), initial_count])
        return
    if str(runtime.get_meta("source", "")) != REQUIRED_SOURCE or str(runtime.get_meta("license", "")) != REQUIRED_LICENSE:
        _fail("initial canonical provenance was not accepted")
        return

    # Replace the already trusted source with a present/readable but permanently
    # invalid document. The renderer must fail closed immediately, but it must
    # keep a bounded content-change watch alive so a later source repair at the
    # same path can recover without an external data_path mutation or remount.
    var invalid_text := "{\"format\":\"grand-bruxelles-osm-zone-environment-v1\",\"source\":\"INVALID\",\"license\":\"ODbL-1.0\",\"bounds_m\":[0,0,0,0],\"environment_points\":[]}\n"
    if not _write(LIVE_COPY, invalid_text):
        _fail("could not replace source with invalid payload")
        return
    runtime.call("_refresh", true)

    if _point_count(runtime) != 0:
        _fail("invalid replacement retained stale environment points")
        return
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("invalid replacement retained stale provenance")
        return
    if not runtime.is_processing():
        _fail("non-retryable source rejection disabled bounded repair detection")
        return

    if not _write(LIVE_COPY, canonical_text):
        _fail("could not repair source at the same path")
        return

    # Loaded-source and rejected-source change probes are intentionally bounded.
    # Wait beyond the production 1000 ms content-probe interval and require the
    # normal SceneTree processing loop—not a manual _refresh—to recover.
    await create_timer(1.15).timeout
    await process_frame
    await process_frame

    if _point_count(runtime) != initial_count:
        _fail("same-path repaired source did not recover automatically: expected=%d actual=%d" % [initial_count, _point_count(runtime)])
        return
    if str(runtime.get_meta("source", "")) != REQUIRED_SOURCE or str(runtime.get_meta("license", "")) != REQUIRED_LICENSE:
        _fail("same-path repaired source did not restore canonical provenance")
        return
    if str(runtime.get("_loaded_data_path")) != LIVE_COPY:
        _fail("repaired source did not become authoritative at the original data_path")
        return

    print("BRUSSELS_OSM_INVALID_SOURCE_REPAIR_RECOVERY_OK: points=%d bounded_probe=true" % initial_count)
    quit(0)
