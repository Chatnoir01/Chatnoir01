extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_BOUNDS_INTEGRITY_FAIL: %s" % message)
    quit(1)

func _write_fixture(path: String, bounds: Array, position: Array) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    var document := {
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "bounds_m": bounds,
        "environment_points": [
            {"kind": "tree", "osm_id": 900000000000001, "position": position},
        ],
    }
    file.store_string(JSON.stringify(document))
    file.close()
    return true

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var canonical := RUNTIME_SCRIPT.new() as Node3D
    canonical.data_path = JETTE_DATA
    if not canonical._load_points():
        _fail("canonical Jette source artifact no longer loads")
        return

    var valid_path := "user://osm_bounds_integrity_valid.json"
    if not _write_fixture(valid_path, [0.0, 0.0, 10.0, 10.0], [10.0, 10.0]):
        _fail("could not write valid bounds fixture")
        return
    var valid_runtime := RUNTIME_SCRIPT.new() as Node3D
    valid_runtime.data_path = valid_path
    if not valid_runtime._load_points():
        _fail("inclusive boundary point was rejected")
        return

    var outside_path := "user://osm_bounds_integrity_outside.json"
    if not _write_fixture(outside_path, [0.0, 0.0, 10.0, 10.0], [10.001, 5.0]):
        _fail("could not write out-of-bounds fixture")
        return
    var outside_runtime := RUNTIME_SCRIPT.new() as Node3D
    outside_runtime.data_path = outside_path
    if outside_runtime._load_points():
        _fail("source point outside declared bounds_m was accepted")
        return

    var malformed_path := "user://osm_bounds_integrity_malformed.json"
    if not _write_fixture(malformed_path, [0.0, 0.0, 10.0], [5.0, 5.0]):
        _fail("could not write malformed-bounds fixture")
        return
    var malformed_runtime := RUNTIME_SCRIPT.new() as Node3D
    malformed_runtime.data_path = malformed_path
    if malformed_runtime._load_points():
        _fail("malformed bounds_m was accepted")
        return

    print("BRUSSELS_OSM_BOUNDS_INTEGRITY_OK")
    quit(0)
