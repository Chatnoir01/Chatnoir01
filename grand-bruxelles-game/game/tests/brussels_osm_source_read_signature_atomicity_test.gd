extends SceneTree

const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const LIVE_COPY := "user://brussels_osm_read_signature_atomicity.environment.game.json"

class RaceRuntime extends BrusselsOsmEnvironmentRuntime:
    var replacement_path := ""
    var replacement_text := ""
    var inject_replacement := false
    var replacement_injected := false

    func _source_content_signature(path: String) -> String:
        if inject_replacement and not replacement_injected and path == replacement_path:
            replacement_injected = true
            var replacement := FileAccess.open(path, FileAccess.WRITE)
            if replacement != null:
                replacement.store_string(replacement_text)
                replacement.close()
        return super._source_content_signature(path)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SOURCE_READ_SIGNATURE_ATOMICITY_FAIL: %s" % message)
    quit(1)

func _write(path: String, text: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    return true

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
    var invalid_variant: Variant = JSON.parse_string(canonical_text)
    if not invalid_variant is Dictionary:
        _fail("canonical Jette source is not a JSON object")
        return
    var invalid_document := (invalid_variant as Dictionary).duplicate(true)
    invalid_document["source"] = "TOCTOU replacement source"
    var invalid_text := JSON.stringify(invalid_document)
    if not _write(LIVE_COPY, canonical_text):
        _fail("failed to stage canonical source")
        return

    var runtime := RaceRuntime.new()
    runtime.data_path = LIVE_COPY
    runtime.replacement_path = LIVE_COPY
    runtime.replacement_text = invalid_text
    runtime.inject_replacement = true

    if not runtime._load_points():
        _fail("canonical source failed initial load")
        runtime.free()
        return
    if _point_count(runtime) <= 0 or str(runtime.get_meta("source", "")).is_empty():
        _fail("initial trusted source did not materialize trusted points/provenance")
        runtime.free()
        return

    # Old runtimes re-hash the path after parsing. The override replaces the
    # path exactly at that post-read hash, making the cached signature describe
    # B while the accepted points/provenance still came from A. A fixed runtime
    # records the bytes it actually parsed, so no post-read path hash occurs;
    # stage B explicitly in that case before probing.
    if not runtime.replacement_injected:
        if not _write(LIVE_COPY, invalid_text):
            _fail("failed to stage invalid replacement after atomic load")
            runtime.free()
            return

    if not runtime._loaded_source_should_reload(true):
        _fail("replacement bytes were aliased to the signature of previously parsed source")
        runtime.free()
        return
    if runtime._load_points():
        _fail("invalid replacement was accepted after source-change detection")
        runtime.free()
        return
    if _point_count(runtime) != 0:
        _fail("rejected replacement retained stale trusted points")
        runtime.free()
        return
    if runtime.has_meta("source") or runtime.has_meta("license"):
        _fail("rejected replacement retained stale trusted provenance")
        runtime.free()
        return

    runtime.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(LIVE_COPY))
    print("BRUSSELS_OSM_SOURCE_READ_SIGNATURE_ATOMICITY_OK: parsed_bytes_own_signature=true replacement_detected=true stale_points=false stale_provenance=false")
    quit(0)
