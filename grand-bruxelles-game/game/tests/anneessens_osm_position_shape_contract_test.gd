extends SceneTree

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_POSITION_SHAPE_FAIL: %s" % message)
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
        _fail("runtime rejected canonical two-coordinate source-backed positions")
        return

    var mutated := canonical.duplicate(true)
    var environment_points := mutated.get("environment_points", []) as Array
    if environment_points.is_empty() or not environment_points[0] is Dictionary:
        runtime.free()
        _fail("canonical environment point fixture missing")
        return
    var point := (environment_points[0] as Dictionary).duplicate(true)
    var position := point.get("position", []) as Array
    if position.size() != 2:
        runtime.free()
        _fail("canonical environment point position is not exactly [x,z]")
        return

    # Preserve the two source-backed coordinates byte-for-byte and append one
    # additional numeric ordinate. Rendering would still use only x/z, so an
    # intake validator that accepts size >= 2 silently broadens provenance.
    point["position"] = [position[0], position[1], 0.0]
    environment_points[0] = point
    mutated["environment_points"] = environment_points

    var ambiguous: Variant = runtime.call("_collect_validated_tree_points", mutated)
    runtime.free()
    if ambiguous != null:
        _fail("runtime accepted a three-coordinate position tuple while claiming source-backed [x,z] placement")
        return

    print("ANNEESSENS_OSM_POSITION_SHAPE_OK: canonical_exact_2d=true extra_ordinate_fail_closed=true")
    quit(0)
