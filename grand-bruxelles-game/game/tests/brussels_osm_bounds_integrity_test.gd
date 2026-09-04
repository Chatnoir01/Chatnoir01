extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_BOUNDS_INTEGRITY_FAIL: %s" % message)
    quit(1)

func _measure_canonical_bounds() -> bool:
    var file := FileAccess.open(JETTE_DATA, FileAccess.READ)
    if file == null:
        _fail("canonical Jette artifact unreadable for bounds measurement")
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        _fail("canonical Jette artifact is not an object")
        return false
    var document := parsed as Dictionary
    var bounds_variant: Variant = document.get("bounds_m", null)
    var rows_variant: Variant = document.get("environment_points", null)
    if not bounds_variant is Array or bounds_variant.size() != 4 or not rows_variant is Array:
        _fail("canonical Jette artifact lacks measurable bounds/points")
        return false
    var bounds := bounds_variant as Array
    var min_x := INF
    var min_z := INF
    var max_x := -INF
    var max_z := -INF
    var outside_count := 0
    var max_left_excess := 0.0
    var max_right_excess := 0.0
    var max_top_excess := 0.0
    var max_bottom_excess := 0.0
    var first_outside := ""
    for row_variant in rows_variant as Array:
        if not row_variant is Dictionary:
            continue
        var row := row_variant as Dictionary
        var position: Variant = row.get("position", null)
        if not position is Array or position.size() != 2:
            continue
        var x := float(position[0])
        var z := float(position[1])
        min_x = min(min_x, x)
        min_z = min(min_z, z)
        max_x = max(max_x, x)
        max_z = max(max_z, z)
        var left_excess := float(bounds[0]) - x
        var top_excess := float(bounds[1]) - z
        var right_excess := x - float(bounds[2])
        var bottom_excess := z - float(bounds[3])
        if left_excess > 0.0 or top_excess > 0.0 or right_excess > 0.0 or bottom_excess > 0.0:
            outside_count += 1
            max_left_excess = max(max_left_excess, left_excess)
            max_top_excess = max(max_top_excess, top_excess)
            max_right_excess = max(max_right_excess, right_excess)
            max_bottom_excess = max(max_bottom_excess, bottom_excess)
            if first_outside.is_empty():
                first_outside = "kind=%s osm_id=%s position=[%.6f,%.6f]" % [str(row.get("kind", "")), str(row.get("osm_id", "")), x, z]
    print("BRUSSELS_OSM_BOUNDS_MEASURE: declared=%s point_extents=[%.6f,%.6f,%.6f,%.6f] outside_count=%d max_excess=[left=%.6f,top=%.6f,right=%.6f,bottom=%.6f] first_outside=%s" % [JSON.stringify(bounds), min_x, min_z, max_x, max_z, outside_count, max_left_excess, max_top_excess, max_right_excess, max_bottom_excess, first_outside])
    return true

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
    if not _measure_canonical_bounds():
        return

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
