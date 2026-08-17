extends SceneTree

const RUNTIME_PATH := "res://game/scripts/grand_place_brasseurs_coherent_facade_runtime.gd"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const OFFICIAL_SPAN_M := 8.7490357183
const OFFICIAL_Y_MAX_M := 24.746

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_COHERENT_FACADE_CONTRACT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(RUNTIME_PATH):
        _fail("runtime missing: coherent official-wall facade has not been implemented")
        return
    var script := load(RUNTIME_PATH)
    if script == null:
        _fail("runtime script could not be loaded")
        return
    var runtime := script.new()
    if runtime == null:
        _fail("runtime could not be instantiated")
        return
    if String(runtime.get("building_id")) != BUILDING_ID:
        _fail("official UrbIS building identity mismatch")
        return
    if String(runtime.get("wall_id")) != WALL_ID:
        _fail("official UrbIS wall identity mismatch")
        return
    if absf(float(runtime.get("official_span_m")) - OFFICIAL_SPAN_M) > 0.0001:
        _fail("official wall span changed")
        return
    if absf(float(runtime.get("official_y_max_m")) - OFFICIAL_Y_MAX_M) > 0.001:
        _fail("official LoD2 vertical anchor changed")
        return
    if not bool(runtime.get("uses_official_wall_triangles")):
        _fail("facade must be constructed from official wall triangles")
        return
    if bool(runtime.get("uses_free_standing_grid")):
        _fail("rejected free-standing grid family must remain disabled")
        return
    if bool(runtime.get("uses_raw_photo_quad")):
        _fail("raw photo quad is forbidden")
        return
    if bool(runtime.get("claims_survey_accuracy")):
        _fail("photo-derived details must not claim survey accuracy")
        return
    print("BRASSEURS_COHERENT_FACADE_CONTRACT_OK")
    quit(0)
