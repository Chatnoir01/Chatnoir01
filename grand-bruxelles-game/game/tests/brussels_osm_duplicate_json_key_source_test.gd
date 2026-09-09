extends SceneTree

const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const DUPLICATE_COPY := "user://brussels_osm_duplicate_key.environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_DUPLICATE_JSON_KEY_SOURCE_FAIL: %s" % message)
    quit(1)

func _point_count(runtime: BrusselsOsmEnvironmentRuntime) -> int:
    var points := runtime.get("_points") as Dictionary
    return (points["tree"] as Array).size() + (points["street_lamp"] as Array).size() + (points["bollard"] as Array).size()

func _exercise_variant(staged_text: String, label: String) -> bool:
    var reparsed: Variant = JSON.parse_string(staged_text)
    if not reparsed is Dictionary or str((reparsed as Dictionary).get("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("%s witness did not preserve parser last-value acceptance precondition" % label)
        return false
    var file := FileAccess.open(DUPLICATE_COPY, FileAccess.WRITE)
    if file == null:
        _fail("failed to stage %s duplicate-key source" % label)
        return false
    file.store_string(staged_text)
    file.close()

    var runtime := BrusselsOsmEnvironmentRuntime.new()
    runtime.data_path = DUPLICATE_COPY
    var accepted := runtime._load_points()
    if accepted:
        _fail("%s JSON object containing duplicate provenance key was accepted" % label)
        runtime.free()
        return false
    if _point_count(runtime) != 0:
        _fail("%s duplicate-key rejection retained materialized points" % label)
        runtime.free()
        return false
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("%s duplicate-key rejection retained trusted provenance" % label)
        runtime.free()
        return false
    if bool(runtime.get("_last_source_failure_retryable")):
        _fail("%s stable duplicate-key source was classified retryable" % label)
        runtime.free()
        return false
    runtime._record_rejected_source_failure()
    if str(runtime.get("_last_rejected_source_signature")).is_empty():
        _fail("%s duplicate-key rejection did not retain exact rejected-byte identity" % label)
        runtime.free()
        return false
    runtime.free()
    return true

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

    var exact_duplicate := "\"source\":\"UNTRUSTED-DUPLICATE-PROVENANCE\"," + trusted_member
    if not _exercise_variant(staged_text.replace(trusted_member, exact_duplicate), "exact"):
        return

    var escaped_duplicate := "\"\\u0073ource\":\"UNTRUSTED-ESCAPED-DUPLICATE-PROVENANCE\"," + trusted_member
    if not _exercise_variant(staged_text.replace(trusted_member, escaped_duplicate), "escaped-semantic"):
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(DUPLICATE_COPY))
    print("BRUSSELS_OSM_DUPLICATE_JSON_KEY_SOURCE_OK: exact_and_escaped_duplicate_provenance_keys_rejected=true points=0 provenance=false rejected_signature_bound=true")
    quit(0)
