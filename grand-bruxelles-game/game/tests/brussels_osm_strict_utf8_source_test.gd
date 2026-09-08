extends SceneTree

const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const INVALID_COPY := "user://brussels_osm_invalid_utf8.environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_STRICT_UTF8_SOURCE_FAIL: %s" % message)
    quit(1)

func _point_count(runtime: BrusselsOsmEnvironmentRuntime) -> int:
    var points := runtime.get("_points") as Dictionary
    return (points["tree"] as Array).size() + (points["street_lamp"] as Array).size() + (points["bollard"] as Array).size()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var canonical_text := FileAccess.get_file_as_string(JETTE_DATA)
    if canonical_text.is_empty():
        _fail("canonical Jette source is unavailable")
        return
    var parsed: Variant = JSON.parse_string(canonical_text)
    if not parsed is Dictionary:
        _fail("canonical Jette source is not a JSON object")
        return
    var document := (parsed as Dictionary).duplicate(true)
    document["utf8_probe"] = "source-safe"
    var staged_text := JSON.stringify(document)
    var staged_bytes := staged_text.to_utf8_buffer()
    var marker := "source-safe".to_utf8_buffer()
    var marker_index := -1
    for start in range(staged_bytes.size() - marker.size() + 1):
        var matches := true
        for offset in range(marker.size()):
            if staged_bytes[start + offset] != marker[offset]:
                matches = false
                break
        if matches:
            marker_index = start
            break
    if marker_index < 0:
        _fail("failed to locate UTF-8 probe marker")
        return
    staged_bytes[marker_index + 3] = 0xff
    var file := FileAccess.open(INVALID_COPY, FileAccess.WRITE)
    if file == null:
        _fail("failed to stage invalid UTF-8 source")
        return
    file.store_buffer(staged_bytes)
    file.close()

    var runtime := BrusselsOsmEnvironmentRuntime.new()
    runtime.data_path = INVALID_COPY
    var accepted := runtime._load_points()
    if accepted:
        _fail("source containing malformed UTF-8 bytes was accepted")
        runtime.free()
        return
    if _point_count(runtime) != 0:
        _fail("malformed UTF-8 rejection retained materialized points")
        runtime.free()
        return
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("malformed UTF-8 rejection retained trusted provenance")
        runtime.free()
        return
    if bool(runtime.get("_last_source_failure_retryable")):
        _fail("stable malformed UTF-8 source was classified retryable")
        runtime.free()
        return
    runtime._record_rejected_source_failure()
    if str(runtime.get("_last_rejected_source_signature")).is_empty():
        _fail("malformed UTF-8 rejection did not retain exact rejected-byte identity")
        runtime.free()
        return
    runtime.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(INVALID_COPY))
    print("BRUSSELS_OSM_STRICT_UTF8_SOURCE_OK: malformed_utf8_rejected=true points=0 provenance=false rejected_signature_bound=true")
    quit(0)
