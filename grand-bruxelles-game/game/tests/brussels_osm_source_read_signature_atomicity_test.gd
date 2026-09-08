extends SceneTree

const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const LIVE_COPY := "user://brussels_osm_read_signature_atomicity.environment.game.json"
const REJECTED_COPY := "user://brussels_osm_rejected_signature_atomicity.environment.game.json"

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

    # Case 1: a valid A is parsed, then B replaces the path before the old
    # runtime's post-read hash. The cached signature must remain owned by A.
    if not _write(LIVE_COPY, canonical_text):
        _fail("failed to stage canonical source")
        return
    var loaded_runtime := RaceRuntime.new()
    loaded_runtime.data_path = LIVE_COPY
    loaded_runtime.replacement_path = LIVE_COPY
    loaded_runtime.replacement_text = invalid_text
    loaded_runtime.inject_replacement = true
    if not loaded_runtime._load_points():
        _fail("canonical source failed initial load")
        loaded_runtime.free()
        return
    if _point_count(loaded_runtime) <= 0 or str(loaded_runtime.get_meta("source", "")).is_empty():
        _fail("initial trusted source did not materialize trusted points/provenance")
        loaded_runtime.free()
        return
    if not loaded_runtime.replacement_injected:
        if not _write(LIVE_COPY, invalid_text):
            _fail("failed to stage invalid replacement after atomic load")
            loaded_runtime.free()
            return
    if not loaded_runtime._loaded_source_should_reload(true):
        _fail("replacement bytes were aliased to the signature of previously parsed source")
        loaded_runtime.free()
        return
    if loaded_runtime._load_points():
        _fail("invalid replacement was accepted after source-change detection")
        loaded_runtime.free()
        return
    if _point_count(loaded_runtime) != 0:
        _fail("rejected replacement retained stale trusted points")
        loaded_runtime.free()
        return
    if loaded_runtime.has_meta("source") or loaded_runtime.has_meta("license"):
        _fail("rejected replacement retained stale trusted provenance")
        loaded_runtime.free()
        return
    loaded_runtime.free()

    # Case 2: invalid A is rejected, then valid B replaces the same path before
    # rejection state is recorded. The rejected signature must describe A, not
    # a later re-hash of B, otherwise the bounded repair watch aliases B and
    # never retries it.
    if not _write(REJECTED_COPY, invalid_text):
        _fail("failed to stage rejected source")
        return
    var rejected_runtime := RaceRuntime.new()
    rejected_runtime.data_path = REJECTED_COPY
    rejected_runtime.replacement_path = REJECTED_COPY
    rejected_runtime.replacement_text = canonical_text
    rejected_runtime.inject_replacement = true
    if rejected_runtime._load_points():
        _fail("invalid source unexpectedly loaded before rejection-race witness")
        rejected_runtime.free()
        return
    rejected_runtime._record_rejected_source_failure()
    if not rejected_runtime.replacement_injected:
        if not _write(REJECTED_COPY, canonical_text):
            _fail("failed to stage valid repair after atomic rejected-source record")
            rejected_runtime.free()
            return
    rejected_runtime.set("_last_rejected_source_probe_msec", Time.get_ticks_msec() - 1001)
    if not rejected_runtime._rejected_source_should_reload():
        _fail("valid repair bytes were aliased to the signature of previously rejected source")
        rejected_runtime.free()
        return
    if not rejected_runtime._load_points():
        _fail("valid same-path repair failed after rejection-race detection")
        rejected_runtime.free()
        return
    if _point_count(rejected_runtime) <= 0 or not rejected_runtime.has_meta("source") or not rejected_runtime.has_meta("license"):
        _fail("valid same-path repair did not restore trusted points/provenance")
        rejected_runtime.free()
        return
    rejected_runtime.free()

    DirAccess.remove_absolute(ProjectSettings.globalize_path(LIVE_COPY))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(REJECTED_COPY))
    print("BRUSSELS_OSM_SOURCE_READ_SIGNATURE_ATOMICITY_OK: loaded_bytes_own_signature=true rejected_bytes_own_signature=true replacement_detected=true repair_detected=true stale_points=false stale_provenance=false")
    quit(0)
