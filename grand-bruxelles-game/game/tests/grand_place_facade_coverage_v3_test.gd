extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V2_NAME := "GrandPlaceFacadePresentationCorrectionV2"
const V3_NAME := "GrandPlaceFacadePresentationCoverageV3"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_COVERAGE_V3_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var facade := root.get_node_or_null(FACADE_NAME)
    var v2 := root.get_node_or_null(V2_NAME)
    var v3 := root.get_node_or_null(V3_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1100):
        if facade != null and v2 != null and v3 != null and contour != null and bool(facade.get("built")) and bool(v2.get("built")) and bool(v3.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        v2 = root.get_node_or_null(V2_NAME)
        v3 = root.get_node_or_null(V3_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or v2 == null or v3 == null or contour == null:
        _fail("required runtimes missing"); return
    if bool(v3.get("failed")) or not bool(v3.get("built")):
        _fail("coverage runtime did not build"); return
    if int(v3.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    for key: String in ["source_geometry_changed","source_collision_changed","camera_changed","threshold_changed"]:
        if bool(v3.get_meta(key,true)):
            _fail("forbidden mutation flag: %s" % key); return
    if not bool(v3.get_meta("lateral_scale_rescue_removed",false)):
        _fail("human-failed lateral scale rescue is still active"); return
    if not bool(v3.get_meta("cornet_roof_covering_documented",false)) or bool(v3.get_meta("renard_roof_covering_material_claimed",true)):
        _fail("roof source-claim guard drifted"); return
    if bool(v3.get_meta("finished_perfect",true)):
        _fail("coverage V3 claimed finished_perfect"); return

    var balcony := facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard/ContinuousBalconyCue") as MeshInstance3D
    var cornice := v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/RenardCrownV2/ProfiledCorniceCue") as MeshInstance3D
    var rail := v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/CornetCrownV2/RoofBalustradeRail") as MeshInstance3D
    if balcony == null or cornice == null or rail == null:
        _fail("native facade cues missing"); return
    for node: MeshInstance3D in [balcony,cornice,rail]:
        if not node.scale.is_equal_approx(Vector3.ONE):
            _fail("human-rejected lateral stretch survived on %s" % node.name); return

    var cornet_roof := contour.get_node_or_null("GrandPlaceContour_1608847_ROOFSURFACE") as MeshInstance3D
    var renard_roof := contour.get_node_or_null("GrandPlaceContour_1608851_ROOFSURFACE") as MeshInstance3D
    if cornet_roof == null or renard_roof == null or cornet_roof.material_override == null or renard_roof.material_override == null:
        _fail("roof presentation did not bind"); return
    facade.call("set_presentation_visible",false)
    for _frame: int in range(4): await process_frame
    if cornet_roof.material_override != null or renard_roof.material_override != null:
        _fail("OFF toggle did not restore neutral roof overrides"); return
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed collisions"); return
    facade.call("set_presentation_visible",true)
    for _frame: int in range(4): await process_frame
    if cornet_roof.material_override == null or renard_roof.material_override == null:
        _fail("ON toggle did not restore roof presentation"); return
    print("GRAND_PLACE_FACADE_COVERAGE_V3_OK: lateral_stretch=false roofs_source_guarded=true collisions=23 camera_unchanged=true thresholds_unchanged=true")
    quit(0)
