extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_ID_TYPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("canonical Anneessens environment artifact missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        _fail("canonical Anneessens environment artifact invalid")
        return

    var runtime := RUNTIME_SCRIPT.new()
    var canonical := (parsed as Dictionary).duplicate(true)
    var canonical_points: Variant = runtime.call("_collect_validated_tree_points", canonical)
    if canonical_points == null:
        runtime.free()
        _fail("runtime rejected canonical integer OSM ids")
        return

    var point_mutated := canonical.duplicate(true)
    var environment_points := point_mutated.get("environment_points", []) as Array
    if environment_points.is_empty() or not environment_points[0] is Dictionary:
        runtime.free()
        _fail("canonical environment point fixture missing")
        return
    var point := (environment_points[0] as Dictionary).duplicate(true)
    var canonical_point_id: Variant = point.get("osm_id", null)
    if typeof(canonical_point_id) != TYPE_INT:
        runtime.free()
        _fail("canonical environment point osm_id is not JSON integer")
        return
    point["osm_id"] = float(canonical_point_id)
    environment_points[0] = point
    point_mutated["environment_points"] = environment_points

    # Preserve the exact numeric identity while changing only the JSON/Godot
    # type. A provenance key must not accept 4672009403.0 as equivalent to
    # the canonical integer 4672009403.
    var float_point_result: Variant = runtime.call("_collect_validated_tree_points", point_mutated)
    if float_point_result != null:
        runtime.free()
        _fail("runtime accepted float-typed environment point osm_id")
        return

    var selection_mutated := canonical.duplicate(true)
    var selection_value: Variant = selection_mutated.get("selection", null)
    if not selection_value is Dictionary:
        runtime.free()
        _fail("canonical selection fixture missing")
        return
    var selection := (selection_value as Dictionary).duplicate(true)
    var selected_ids := (selection.get("osm_ids", []) as Array).duplicate(true)
    if selected_ids.is_empty() or typeof(selected_ids[0]) != TYPE_INT:
        runtime.free()
        _fail("canonical selection osm_id is not JSON integer")
        return
    selected_ids[0] = float(selected_ids[0])
    selection["osm_ids"] = selected_ids
    selection_mutated["selection"] = selection

    var selection_result: Variant = runtime.call("_validate_selection_integrity", selection_mutated, canonical_points as Array)
    runtime.free()
    if selection_result != null:
        _fail("runtime accepted float-typed selection osm_id")
        return

    print("ANNEESSENS_OSM_ID_TYPE_OK: point_int_only=true selection_int_only=true")
    quit(0)
