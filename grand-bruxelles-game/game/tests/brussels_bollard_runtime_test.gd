extends SceneTree

const DATA_PATH := "res://data/osm/fontainas_bollards.game.json"
const ASSET_PATH := "res://game/scripts/brussels_bollard_asset.gd"
const RUNTIME_PATH := "res://game/scripts/brussels_bollard_runtime.gd"
const EXPECTED_COUNT := 27
const EXPECTED_FAMILY := "brussels_bollard_v1"
const EXPECTED_PRESENTATION_REVISION := 2

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BOLLARD_FAIL: %s" % message)
    quit(1)

func _load_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _make_nested_viewport_decoy() -> Node3D:
    var wrapper := Node3D.new()
    wrapper.name = "ForeignOwner"
    var viewport := SubViewport.new()
    viewport.name = "ForeignViewport"
    var decoy := Node3D.new()
    decoy.name = "Main"
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    decoy.add_child(osm)
    decoy.add_child(urbis)
    viewport.add_child(decoy)
    wrapper.add_child(viewport)
    return wrapper

func _run() -> void:
    var data := _load_data()
    if data.is_empty():
        _fail("source-backed bollard payload missing or invalid")
        return
    if str(data.get("format", "")) != "grand-bruxelles-osm-bollard-cluster-v1":
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
    if not bool(claims.get("position_source_backed", false)) or not bool(claims.get("bollard_presence_source_backed", false)):
        _fail("position/presence source truth missing")
        return
    for unsupported: String in ["style_source_backed", "dimensions_source_backed", "material_source_backed", "color_source_backed"]:
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
        if str(point.get("kind", "")) != "bollard":
            _fail("non-bollard leaked into placement payload")
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
        if float(position[0]) < -160.0 or float(position[0]) > -90.0 or float(position[1]) < -450.0 or float(position[1]) > -340.0:
            _fail("point escaped declared Fontainas bounds")
            return

    if not FileAccess.file_exists(ASSET_PATH):
        _fail("red-first witness: reusable bollard asset missing")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("red-first witness: source-backed bollard runtime missing")
        return
    var asset_script := load(ASSET_PATH)
    if asset_script == null or not "PRESENTATION_REVISION" in asset_script:
        _fail("bollard presentation revision 2 missing")
        return
    if int(asset_script.PRESENTATION_REVISION) != EXPECTED_PRESENTATION_REVISION:
        _fail("bollard presentation revision mismatch")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    if current_scene != null:
        _fail("test harness unexpectedly has current_scene before production-style root instantiation")
        return
    var runtime := root.get_node_or_null("BrusselsBollardRuntime")
    if runtime == null:
        _fail("BrusselsBollardRuntime autoload missing")
        return

    var foreign_wrapper := _make_nested_viewport_decoy()
    root.add_child(foreign_wrapper)
    for _frame: int in range(8):
        await process_frame
    if bool(runtime.call("ready_complete")):
        _fail("nested foreign viewport Main captured bollard runtime before authoritative root scene")
        return

    var scene := packed.instantiate() as Node3D
    root.add_child(scene)
    if current_scene != null:
        _fail("root-instantiated production witness unexpectedly assigned current_scene")
        return
    for _frame: int in range(190):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime did not auto-discover root-instantiated production scene")
        return
    if scene.get_node_or_null("BrusselsSourceBackedBollards") == null:
        _fail("authoritative root scene did not receive owned bollard root")
        return
    var foreign_decoy := foreign_wrapper.get_node_or_null("ForeignViewport/Main")
    if foreign_decoy != null and foreign_decoy.get_node_or_null("BrusselsSourceBackedBollards") != null:
        _fail("foreign nested viewport scene received owned bollard root")
        return
    if int(runtime.call("point_count")) != EXPECTED_COUNT:
        _fail("runtime point count mismatch")
        return
    if int(runtime.call("collision_count")) != EXPECTED_COUNT:
        _fail("every source bollard must remain physically collidable")
        return
    if int(runtime.call("visual_batch_count")) > 2:
        _fail("bollard presentation is not efficiently batched")
        return
    if str(runtime.call("asset_family")) != EXPECTED_FAMILY:
        _fail("asset family mismatch")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("runtime moved source positions")
        return

    print("BRUSSELS_BOLLARD_OK: points=%d collisions=%d batches=%d family=%s revision=%d root_level_viewport_only=true source=OSM license=ODbL-1.0" % [EXPECTED_COUNT, int(runtime.call("collision_count")), int(runtime.call("visual_batch_count")), EXPECTED_FAMILY, EXPECTED_PRESENTATION_REVISION])
    quit(0)
