extends SceneTree

const AUTOLOAD := "GrandPlaceBrasseursPhotoFacadeRuntime"
const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const EXPECTED_SPAN_M := 8.7490357183
const EXPECTED_OFFSETS := [0.6872, 2.8278, 5.2337, 7.6396]
const EXPECTED_SOURCE_SHA256 := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_PHOTO_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
    if not (plan is Dictionary):
        _fail("shipped Brasseurs photo plan missing/invalid")
        return
    var placement: Dictionary = plan.get("placement", {})
    var source: Dictionary = plan.get("source", {})
    var derived: Dictionary = plan.get("derived_horizontal_world_constraints", {})
    if str(placement.get("building_id", "")) != "1639974": _fail("plan building identity drifted"); return
    if str(placement.get("front_wall_id", "")) != "10945501": _fail("plan wall identity drifted"); return
    if abs(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.000001: _fail("plan official wall span drifted"); return
    if str(placement.get("vertical_world_scale", "")) != "unresolved": _fail("photo plan must not claim vertical world scale"); return
    if str(source.get("download_sha256", "")) != EXPECTED_SOURCE_SHA256: _fail("photo source hash drifted"); return
    var stored_offsets: Array = derived.get("column_center_offsets_from_left_m", [])
    if stored_offsets.size() != 4: _fail("photo plan must expose four column offsets"); return
    for i: int in range(4):
        if abs(float(stored_offsets[i]) - float(EXPECTED_OFFSETS[i])) > 0.001: _fail("photo-plan column offset drifted"); return
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null: _fail("photo-constrained Brasseurs runtime missing"); return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("facade_ready")): break
    if not bool(runtime.get("facade_ready")): _fail("runtime did not become ready"); return
    if str(runtime.get("building_id")) != BUILDING_ID: _fail("runtime building identity drifted"); return
    if str(runtime.get("source_wall_id")) != WALL_ID: _fail("runtime wall identity drifted"); return
    if abs(float(runtime.get("source_facade_span_m")) - EXPECTED_SPAN_M) > 0.002: _fail("runtime facade span drifted"); return
    if int(runtime.get("bay_count")) != 3: _fail("runtime must preserve three bays"); return
    var runtime_offsets = runtime.get("column_offsets_m")
    if not (runtime_offsets is Array) or runtime_offsets.size() != 4: _fail("runtime must expose four column offsets"); return
    for i: int in range(4):
        if abs(float(runtime_offsets[i]) - float(EXPECTED_OFFSETS[i])) > 0.001: _fail("runtime column offset drifted"); return
    if str(runtime.get("photo_source_sha256")) != EXPECTED_SOURCE_SHA256: _fail("runtime photo provenance drifted"); return
    if bool(runtime.get("raw_photo_pixels_shipped")): _fail("raw photo pixels forbidden"); return
    if bool(runtime.get("geometry_claimed_surveyed")): _fail("photo geometry must not claim survey accuracy"); return
    if str(runtime.get("vertical_world_scale_source")) != "official_lod2_wall": _fail("runtime requires official LoD2 wall vertical source"); return
    print("GRAND_PLACE_BRASSEURS_PHOTO_RUNTIME_OK: building=1639974 wall=10945501 bays=3 span=8.749036 photo_pixels=false surveyed=false vertical_source=official_lod2_wall")
    quit(0)
