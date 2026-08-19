extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OFFICIAL_NAME := "GrandPlaceMaisonDuRoiOfficialLod2"
const ARTICULATION_NAME := "GrandPlaceMaisonDuRoiFacadeArticulationRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MAISON_DU_ROI_FACADE_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var official := root.get_node_or_null(OFFICIAL_NAME)
    var articulation := root.get_node_or_null(ARTICULATION_NAME)
    if official == null or articulation == null:
        _fail("required autoload missing")
        return
    for _frame: int in range(600):
        if bool(official.get("geometry_loaded")) and bool(articulation.get("built")):
            break
        await process_frame
    if not bool(official.get("geometry_loaded")):
        _fail("official LoD2 did not load")
        return
    if not bool(articulation.get("built")):
        _fail("facade articulation did not build")
        return
    if str(official.get_meta("building_id", "")) != "https://databrussels.be/id/building/1654360":
        _fail("official building identity drifted")
        return
    if int(official.get("render_triangle_count")) != 213:
        _fail("official render triangle contract drifted")
        return
    if int(articulation.get_meta("lower_bays", 0)) != 9 or int(articulation.get_meta("upper_bays", 0)) != 17:
        _fail("heritage bay rhythm drifted")
        return
    if int(articulation.get_meta("ground_lancets", 0)) != 4 or int(articulation.get_meta("upper_lancets", 0)) != 2:
        _fail("lancet contract drifted")
        return
    if int(articulation.get_meta("gallery_levels", 0)) != 2 or not bool(articulation.get_meta("axial_bay_wider", false)):
        _fail("gallery/axial contract drifted")
        return
    if float(articulation.get("resolved_facade_width_m")) < 18.0 or float(articulation.get("resolved_facade_height_m")) < 15.0:
        _fail("resolved official facade is too small")
        return
    if int(articulation.get("feature_count")) < 70:
        _fail("architectural articulation unexpectedly sparse")
        return
    if bool(articulation.get_meta("source_geometry_changed", true)) or bool(articulation.get_meta("source_collision_changed", true)):
        _fail("source geometry/collision mutation is forbidden")
        return
    if bool(articulation.get_meta("survey_dimensions_claimed", true)) or bool(articulation.get_meta("exact_opening_coordinates_claimed", true)):
        _fail("presentation conventions must not claim survey coordinates")
        return
    if bool(articulation.get_meta("runtime_approved", true)) or bool(articulation.get_meta("realism_complete", true)):
        _fail("candidate must remain non-approved before human A/B")
        return
    print("MAISON_DU_ROI_FACADE_OK: width=%.3f height=%.3f features=%d bays=9/17 source_geometry_changed=false" % [float(articulation.get("resolved_facade_width_m")), float(articulation.get("resolved_facade_height_m")), int(articulation.get("feature_count"))])
    quit(0)
