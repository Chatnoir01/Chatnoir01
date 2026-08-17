extends SceneTree

const RUNTIME_PATH := "res://game/scripts/grand_place_brasseurs_photo_facade_runtime.gd"
const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const FEATURES_PATH := "res://data/qa/grand_place_brasseurs_photo_features.json"
const VERTICAL_PATH := "res://data/qa/grand_place_brasseurs_wall_vertical.json"
const BUILDING_ID := "1639974"
const WALL_ID := "10945501"
const SOURCE_SHA := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"
const EXPECTED_SPAN_M := 8.7490357183

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_PHOTO_RUNTIME_FAIL: %s" % message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _fail("missing source input: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        _fail("invalid source JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _run() -> void:
    var plan := _json(PLAN_PATH)
    var features := _json(FEATURES_PATH)
    var vertical := _json(VERTICAL_PATH)
    if plan.is_empty() or features.is_empty() or vertical.is_empty():
        return
    var placement: Dictionary = plan.get("placement", {})
    var source: Dictionary = plan.get("source", {})
    var mapping: Dictionary = features.get("mapping", {})
    if str(placement.get("building_id", "")) != BUILDING_ID or str(placement.get("front_wall_id", "")) != WALL_ID:
        _fail("shipped photo plan identity drifted")
        return
    if absf(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.00001:
        _fail("official wall span drifted")
        return
    if str(source.get("download_sha256", "")) != SOURCE_SHA:
        _fail("photo source hash drifted")
        return
    if str(vertical.get("building_id", "")) != BUILDING_ID or str(vertical.get("front_wall_id", "")) != WALL_ID:
        _fail("UrbIS vertical identity drifted")
        return
    if absf(float(vertical.get("wall_vertical_extent_m", 0.0)) - 24.746) > 0.001:
        _fail("UrbIS vertical extent drifted")
        return
    if str(mapping.get("vertical_world_source", "")) != "official_lod2_wall_piecewise_anchors":
        _fail("vertical mapping must remain independently source-backed")
        return
    if bool(mapping.get("raw_photo_pixels_shipped", true)) or bool(mapping.get("photo_geometry_claimed_surveyed", true)):
        _fail("photo/source boundary violated")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("red-first witness: non-primitive photo-constrained Brasseurs runtime missing")
        return
    var runtime_source := FileAccess.get_file_as_string(RUNTIME_PATH)
    for forbidden: String in ["BoxMesh.new()", "CylinderMesh.new()", "SphereMesh.new()", "QuadMesh.new()"]:
        if runtime_source.find(forbidden) >= 0:
            _fail("blocked primitive proxy family returned: %s" % forbidden)
            return
    for required: String in ["SurfaceTool.new()", "source_bounded_visualization_not_architectural_survey", "raw_photo_pixels_shipped", "geometry_claimed_surveyed"]:
        if runtime_source.find(required) < 0:
            _fail("runtime contract token missing: %s" % required)
            return
    print("GRAND_PLACE_BRASSEURS_PHOTO_RUNTIME_OK: building=1639974 wall=10945501 span=8.749036 non_primitive=true photo_pixels=false surveyed=false")
    quit(0)
