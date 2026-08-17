extends SceneTree

const AUTOLOAD := "GrandPlaceBrasseursSurfaceMeshRuntime"
const RUNTIME_PATH := "res://game/scripts/grand_place_brasseurs_surface_mesh_runtime.gd"
const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const FEATURES_PATH := "res://data/qa/grand_place_brasseurs_photo_features.json"
const VERTICAL_PATH := "res://data/qa/grand_place_brasseurs_wall_vertical.json"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const SOURCE_SHA := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"
const EXPECTED_SPAN := 8.7490357183

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_SURFACE_MESH_FAIL: " + message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _fail("missing source input: " + path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid json: " + path)
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
    if str(placement.get("building_id", "")) != "1639974" or str(placement.get("front_wall_id", "")) != "10945501":
        _fail("official Brasseurs identity drifted")
        return
    if absf(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN) > 0.000001:
        _fail("official wall span drifted")
        return
    if str(source.get("download_sha256", "")) != SOURCE_SHA:
        _fail("Commons source hash drifted")
        return
    if str(vertical.get("vertical_world_scale_source", "")) != "official_lod2_wall" or bool(vertical.get("photo_used_for_vertical_scale", true)):
        _fail("vertical world scale must remain independent official UrbIS LoD2")
        return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("red-first witness: non-primitive photo-constrained Brasseurs runtime missing")
        return
    var runtime_source := FileAccess.get_file_as_string(RUNTIME_PATH)
    for forbidden: String in ["BoxMesh", "CylinderMesh", "SphereMesh", "QuadMesh"]:
        if runtime_source.find(forbidden) >= 0:
            _fail("blocked primitive family returned: " + forbidden)
            return
    for required: String in ["SurfaceTool", "source_bounded_visualization_not_architectural_survey", "raw_photo_pixels_shipped", "geometry_claimed_surveyed"]:
        if runtime_source.find(required) < 0:
            _fail("required runtime contract token missing: " + required)
            return
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("runtime autoload missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("facade_ready")):
            break
    if not bool(runtime.get("facade_ready")):
        _fail("runtime did not become ready")
        return
    if str(runtime.get("building_id")) != BUILDING_ID or str(runtime.get("source_wall_id")) != WALL_ID:
        _fail("runtime source identity drifted")
        return
    if absf(float(runtime.get("source_facade_span_m")) - EXPECTED_SPAN) > 0.002:
        _fail("runtime span drifted")
        return
    if bool(runtime.get("raw_photo_pixels_shipped")) or bool(runtime.get("geometry_claimed_surveyed")):
        _fail("runtime overclaims photo geometry")
        return
    if str(runtime.get("vertical_world_scale_source")) != "official_lod2_wall":
        _fail("runtime vertical source drifted")
        return
    if int(runtime.get("bay_count")) != 3 or int(runtime.get("feature_mesh_count")) < 20:
        _fail("facade feature coverage too weak")
        return
    print("GRAND_PLACE_BRASSEURS_SURFACE_MESH_OK: building=1639974 wall=10945501 span=8.749036 primitive_family=false photo_pixels=false surveyed=false")
    quit(0)
