extends SceneTree

const DATA_PATH := "res://data/osm/corridor_street_lamps.game.json"
const ASSET_PATH := "res://game/scripts/brussels_street_lamp_asset.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_street_lamp_runtime.gd"
const EXPECTED_COUNT := 8
const EXPECTED_FAMILY := "brussels_street_lamp_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_STREET_LAMP_FAIL: %s" % message)
    quit(1)

func _load_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _run() -> void:
    var data := _load_data()
    if data.is_empty():
        _fail("source-backed street lamp payload missing or invalid")
        return
    if str(data.get("format", "")) != "grand-bruxelles-osm-street-lamp-cluster-v1":
        _fail("unexpected payload format")
        return
    if str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API" or str(data.get("license", "")) != "ODbL-1.0":
        _fail("source/license provenance mismatch")
        return
    var source_evidence := data.get("source_evidence", {}) as Dictionary
    if int(source_evidence.get("merged_pr", 0)) != 568:
        _fail("merged source-evidence PR not locked")
        return
    if str(source_evidence.get("artifact_digest", "")) != "sha256:9c900c0f4d59e3daadb5505b7183203bd0f15ab96b2b3927518fd5a79f142234":
        _fail("source artifact digest mismatch")
        return
    var claims := data.get("claims", {}) as Dictionary
    if not bool(claims.get("position_source_backed", false)) or not bool(claims.get("street_lamp_presence_source_backed", false)):
        _fail("position/presence source truth missing")
        return
    for unsupported: String in ["style_source_backed", "dimensions_source_backed", "material_source_backed", "light_photometry_source_backed"]:
        if bool(claims.get(unsupported, true)):
            _fail("unsupported visual claim enabled: %s" % unsupported)
            return

    var points := data.get("points", []) as Array
    if points.size() != EXPECTED_COUNT:
        _fail("expected %d source points, got %d" % [EXPECTED_COUNT, points.size()])
        return
    var ids := {}
    for raw: Variant in points:
        if not raw is Dictionary:
            _fail("malformed point")
            return
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "street_lamp":
            _fail("non-street-lamp leaked into placement payload")
            return
        var osm_id := int(point.get("osm_id", 0))
        if osm_id <= 0 or ids.has(osm_id):
            _fail("invalid/duplicate OSM id")
            return
        ids[osm_id] = true
        var position := point.get("position", []) as Array
        if position.size() != 2:
            _fail("invalid source position")
            return
        if float(point.get("corridor_distance_m", 999.0)) > 130.0:
            _fail("point escaped source corridor gate")
            return

    if not FileAccess.file_exists(ASSET_PATH):
        _fail("red-first witness: reusable street lamp asset missing")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("red-first witness: source-backed street lamp runtime missing")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)
    var runtime := root.get_node_or_null("BrusselsStreetLampRuntime")
    if runtime == null:
        _fail("BrusselsStreetLampRuntime autoload missing")
        return
    runtime.call("bind_scene", scene)
    for _frame: int in range(12):
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime did not bind cleanly")
        return
    if int(runtime.call("point_count")) != EXPECTED_COUNT:
        _fail("runtime point count mismatch")
        return
    if int(runtime.call("visual_batch_count")) > 3:
        _fail("street lamp presentation is not efficiently batched")
        return
    if str(runtime.call("asset_family")) != EXPECTED_FAMILY:
        _fail("asset family mismatch")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("runtime moved source positions")
        return

    print("BRUSSELS_STREET_LAMP_OK: points=%d batches=%d family=%s source=OSM license=ODbL-1.0" % [EXPECTED_COUNT, int(runtime.call("visual_batch_count")), EXPECTED_FAMILY])
    quit(0)
