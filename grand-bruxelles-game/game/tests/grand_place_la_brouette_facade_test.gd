extends SceneTree

const AUTOLOAD := "GrandPlaceLaBrouetteFacadeRuntime"
const BUILDING_ID := "https://databrussels.be/id/building/1607758"
const FRONTAGE_FACE_ID := "https://databrussels.be/id/buildingface/10897437"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LA_BROUETTE_FACADE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("runtime autoload missing")
        return
    for _frame: int in range(120):
        await process_frame
        if bool(runtime.get("articulation_ready")):
            break
    if not bool(runtime.get("articulation_ready")):
        _fail("articulation did not become ready")
        return
    if str(runtime.get_meta("building_id", "")) != BUILDING_ID:
        _fail("UrbIS building identity drifted")
        return
    if str(runtime.get_meta("frontage_face_id", "")) != FRONTAGE_FACE_ID:
        _fail("official frontage face identity drifted")
        return
    if str(runtime.get_meta("heritage_source", "")) != "urban.brussels/31120":
        _fail("heritage source drifted")
        return
    if int(runtime.get("level_count")) != 4 or int(runtime.get("bay_count")) != 4:
        _fail("documented four-level/four-bay rhythm missing")
        return
    if int(runtime.get("opening_proxy_count")) != 16:
        _fail("expected 16 bounded opening proxies")
        return
    if int(runtime.get("support_proxy_count")) != 20:
        _fail("expected 20 order-support proxies")
        return
    if int(runtime.get("facade_skin_triangle_count")) != 4:
        _fail("facade skin must preserve four official frontage triangles")
        return
    if not bool(runtime.get_meta("gable_from_official_frontage", false)):
        _fail("gable silhouette must come from official frontage")
        return
    if bool(runtime.get_meta("geometry_claimed_surveyed", true)):
        _fail("authored articulation must remain visualization convention")
        return
    if bool(runtime.get_meta("ornament_authored", true)):
        _fail("decorative sculpture/ornament must not be invented")
        return
    if bool(runtime.get_meta("runtime_approved", true)) or bool(runtime.get_meta("realism_complete", true)):
        _fail("candidate must remain visually gated")
        return
    print("GRAND_PLACE_LA_BROUETTE_FACADE_OK: levels=4 bays=4 openings=16 supports=20 frontage_triangles=4 surveyed=false ornament=false")
    quit(0)
