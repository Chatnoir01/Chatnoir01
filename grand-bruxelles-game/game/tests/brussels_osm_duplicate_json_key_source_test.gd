extends SceneTree

const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const DUPLICATE_COPY := "user://brussels_osm_duplicate_key.environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_DUPLICATE_JSON_KEY_SOURCE_FAIL: %s" % message)
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
    var staged_text := JSON.stringify(parsed)
    var trusted_member := "\"source\":\"OpenStreetMap contributors via Overpass API\""
    if staged_text.count(trusted_member) != 1:
        _fail("canonical source member is not uniquely stageable")
        return
    var duplicate_member := "\"source\":\"UNTRUSTED-DUPLICATE-PROVENANCE\"," + trusted_member
    staged_text = staged_text.replace(trusted_member, duplicate_member)
    var reparsed: Variant = JSON.parse_string(staged_text)
    if not reparsed is Dictionary or str((reparsed as Dictionary).get("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("duplicate-key witness did not preserve parser last-value acceptance precondition")
        return
    var file := FileAccess.open(DUPLICATE_COPY, FileAccess.WRITE)
    if file == null:
        _fail("failed to stage duplicate-key source")
        return
    file.store_string(staged_text)
    file.close()

    var runtime := BrusselsOsmEnvironmentRuntime.new()
    runtime.data_path = DUPLICATE_COPY
    var accepted := runtime._load_points()
    if accepted:
        _fail("JSON object containing duplicate provenance key was accepted")
        runtime.free()
        return
    if _point_count(runtime) != 0:
        _fail("duplicate-key rejection retained materialized points")
        runtime.free()
        return
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("duplicate-key rejection retained trusted provenance")
        runtime.free()
        return
    if bool(runtime.get("_last_source_failure_retryable")):
        _fail("stable duplicate-key source was classified retryable")
        runtime.free()
        return
    runtime._record_rejected_source_failure()
    if str(runtime.get("_last_rejected_source_signature")).is_empty():
        _fail("duplicate-key rejection did not retain exact rejected-byte identity")
        runtime.free()
        return
    runtime.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(DUPLICATE_COPY))
    print("BRUSSELS_OSM_DUPLICATE_JSON_KEY_SOURCE_OK: duplicate_provenance_key_rejected=true points=0 provenance=false rejected_signature_bound=true")
    quit(0)
