extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const LIVE_COPY := "user://brussels_osm_same_metadata_reload.environment.game.json"
const STAGED_COPY := "user://brussels_osm_same_metadata_reload.staged.environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SAME_METADATA_SOURCE_UPDATE_FAIL: %s" % message)
    quit(1)

func _count_points(runtime: Node3D) -> int:
    var points := runtime.get("_points") as Dictionary
    return (points["tree"] as Array).size() + (points["street_lamp"] as Array).size() + (points["bollard"] as Array).size()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var canonical_text := FileAccess.get_file_as_string(JETTE_DATA)
    var parsed: Variant = JSON.parse_string(canonical_text)
    if not parsed is Dictionary:
        _fail("canonical Jette source is not valid JSON")
        return
    var base := (parsed as Dictionary).duplicate(true)
    var rows := base.get("environment_points", []) as Array
    if rows.size() < 2:
        _fail("canonical source has too few points")
        return

    var used_ids: Dictionary = {}
    for row_variant in rows:
        used_ids[int((row_variant as Dictionary).get("osm_id", 0))] = true
    var original_id := int((rows[0] as Dictionary)["osm_id"])
    var replacement_id := -1
    for delta in range(1, 1000):
        var candidate := original_id + delta
        if str(candidate).length() == str(original_id).length() and not used_ids.has(candidate):
            replacement_id = candidate
            break
    if replacement_id <= 0:
        _fail("could not derive equal-width unique OSM id")
        return

    var initial_text := JSON.stringify(base) + "\n"
    var replacement := base.duplicate(true)
    ((replacement["environment_points"] as Array)[0] as Dictionary)["osm_id"] = replacement_id
    var replacement_text := JSON.stringify(replacement) + "\n"
    if replacement_text.length() != initial_text.length():
        _fail("replacement payload is not byte-length stable")
        return

    var live_absolute := ProjectSettings.globalize_path(LIVE_COPY)
    var staged_absolute := ProjectSettings.globalize_path(STAGED_COPY)
    DirAccess.remove_absolute(live_absolute)
    DirAccess.remove_absolute(staged_absolute)

    # Materialize both equal-size payloads in the same filesystem timestamp second
    # before runtime startup. The staged file keeps that mtime while the runtime
    # does arbitrary work, so the later atomic-style replacement is a real,
    # deterministic mtime:size collision rather than a race against CI speed.
    while fmod(Time.get_unix_time_from_system(), 1.0) > 0.20:
        await process_frame
    var f := FileAccess.open(LIVE_COPY, FileAccess.WRITE)
    if f == null:
        _fail("could not create initial live source")
        return
    f.store_string(initial_text)
    f.close()
    var staged := FileAccess.open(STAGED_COPY, FileAccess.WRITE)
    if staged == null:
        _fail("could not create staged replacement source")
        return
    staged.store_string(replacement_text)
    staged.close()

    var initial_metadata_signature := "%d:%d" % [FileAccess.get_modified_time(LIVE_COPY), FileAccess.get_size(LIVE_COPY)]
    var staged_metadata_signature := "%d:%d" % [FileAccess.get_modified_time(STAGED_COPY), FileAccess.get_size(STAGED_COPY)]
    if initial_metadata_signature != staged_metadata_signature:
        _fail("could not materialize deterministic metadata collision: initial=%s staged=%s" % [initial_metadata_signature, staged_metadata_signature])
        return

    var player := Node3D.new()
    player.name = "Player"
    root.add_child(player)
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.set("data_path", LIVE_COPY)
    root.add_child(runtime)
    await process_frame
    var before_count := _count_points(runtime)
    var before_signature := str(runtime.call("_source_availability_signature", LIVE_COPY))
    if before_signature != initial_metadata_signature:
        _fail("runtime metadata signature disagrees with fixture: runtime=%s fixture=%s" % [before_signature, initial_metadata_signature])
        return

    if DirAccess.remove_absolute(live_absolute) != OK:
        _fail("could not remove initial live source before staged replacement")
        return
    if DirAccess.rename_absolute(staged_absolute, live_absolute) != OK:
        _fail("could not promote staged replacement to live path")
        return
    var after_signature := str(runtime.call("_source_availability_signature", LIVE_COPY))
    if before_signature != after_signature:
        _fail("filesystem metadata collision was not preserved across replacement: before=%s after=%s" % [before_signature, after_signature])
        return

    runtime.call("_refresh", true)
    var loaded_rows := runtime.get("_points") as Dictionary
    var found_replacement := false
    for kind in ["tree", "street_lamp", "bollard"]:
        for row_variant in loaded_rows[kind] as Array:
            if int((row_variant as Dictionary)["osm_id"]) == replacement_id:
                found_replacement = true
    if not found_replacement:
        _fail("same-size same-mtime replacement retained stale source content")
        return
    if _count_points(runtime) != before_count:
        _fail("replacement unexpectedly changed point count")
        return
    print("BRUSSELS_OSM_SAME_METADATA_SOURCE_UPDATE_OK: signature_collision=%s replacement_id=%d" % [before_signature, replacement_id])
    quit(0)
