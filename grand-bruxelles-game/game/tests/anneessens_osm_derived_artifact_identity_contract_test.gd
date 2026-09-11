extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_DERIVED_ARTIFACT_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("canonical Anneessens derived artifact missing")
        return
    var canonical_bytes := FileAccess.get_file_as_bytes(DATA_PATH)
    if canonical_bytes.is_empty():
        _fail("canonical Anneessens derived artifact empty")
        return

    var runtime := RUNTIME_SCRIPT.new()
    if not runtime.has_method("_validate_data_artifact_identity"):
        runtime.free()
        _fail("runtime derived-artifact identity validator missing")
        return

    var canonical_identity: Variant = runtime.call("_validate_data_artifact_identity", DATA_PATH)
    if canonical_identity == null:
        runtime.free()
        _fail("canonical Anneessens derived artifact identity rejected")
        return

    var mutated_path := "user://anneessens_environment_one_byte_drift.game.json"
    var mutated := canonical_bytes.duplicate()
    var mutation_index := maxi(0, mutated.size() - 2)
    mutated[mutation_index] = mutated[mutation_index] ^ 1
    var out := FileAccess.open(mutated_path, FileAccess.WRITE)
    if out == null:
        runtime.free()
        _fail("unable to create one-byte drift witness")
        return
    out.store_buffer(mutated)
    out.close()

    var mutated_identity: Variant = runtime.call("_validate_data_artifact_identity", mutated_path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(mutated_path))
    runtime.free()
    if mutated_identity != null:
        _fail("one-byte derived artifact drift was accepted")
        return

    print("ANNEESSENS_OSM_DERIVED_ARTIFACT_IDENTITY_OK: canonical accepted; one-byte drift rejected before semantic consumption")
    quit(0)
