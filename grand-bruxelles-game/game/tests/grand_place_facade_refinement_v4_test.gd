extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const V4_NAME := "GrandPlaceFacadePresentationRefinementV4"
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_REFINEMENT_V4_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var v4 := root.get_node_or_null(V4_NAME)
    var v5 := root.get_node_or_null(V5_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1200):
        if v4 != null and v5 != null and contour != null and bool(v4.get("built")) and bool(v5.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        v4 = root.get_node_or_null(V4_NAME)
        v5 = root.get_node_or_null(V5_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if v4 == null or v5 == null or contour == null or not bool(v4.get("built")) or not bool(v5.get("built")):
        _fail("V4 supersession/V5 readiness missing"); return
    if str(v4.get_meta("human_review_status","")) != "rejected" or str(v4.get_meta("superseded_by","")) != "V5":
        _fail("V4 rejection provenance missing"); return
    if int(v4.get_meta("visual_geometry_count",-1)) != 0 or v4.get_child_count() != 0:
        _fail("human-rejected V4 still creates visual geometry"); return
    if int(v4.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    if bool(v4.get_meta("finished_perfect",true)):
        _fail("V4 marker claimed completion"); return
    print("GRAND_PLACE_FACADE_REFINEMENT_V4_OK: rejected=true superseded_by=V5 visual_geometry=0 collisions=23")
    quit(0)
