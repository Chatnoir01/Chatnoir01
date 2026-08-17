extends SceneTree

const AUTOLOAD := "GrandPlaceBrasseursArticulationRuntime"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const SOURCE_WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const EXPECTED_SPAN_M := 8.7490357183

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_ARTICULATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("red-first witness: Brasseurs articulation runtime missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("articulation_ready")):
            break
    if not bool(runtime.get("articulation_ready")):
        _fail("articulation did not become ready")
        return
    if str(runtime.get("building_id")) != BUILDING_ID:
        _fail("building identity drifted")
        return
    if str(runtime.get("source_wall_id")) != SOURCE_WALL_ID:
        _fail("front articulation must stay anchored to official wall 10945501")
        return
    if abs(float(runtime.get("source_facade_span_m")) - EXPECTED_SPAN_M) > 0.002:
        _fail("official facade span drifted")
        return
    if int(runtime.get("bay_count")) != 3:
        _fail("heritage record requires three bays")
        return
    if not bool(runtime.get("colossal_corinthian_half_columns")):
        _fail("heritage record requires colossal Corinthian half-column order")
        return
    if not bool(runtime.get("curved_pediment")):
        _fail("heritage record requires curved pediment")
        return
    if not bool(runtime.get("axial_bay_wider_and_projecting")):
        _fail("heritage record requires wider/projecting axial bay")
        return
    if str(runtime.get("placement_semantics")) != "official_lod2_wall_plus_heritage_large_form_visualization_convention_not_survey":
        _fail("placement provenance must remain explicit")
        return
    if bool(runtime.get("geometry_claimed_surveyed")):
        _fail("authored articulation must never claim survey geometry")
        return
    print("GRAND_PLACE_BRASSEURS_ARTICULATION_OK: building=1639974 wall=10945501 bays=3 span=8.749 surveyed=false")
    quit(0)
