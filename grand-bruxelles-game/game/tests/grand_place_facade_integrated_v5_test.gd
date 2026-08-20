extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V3_NAME := "GrandPlaceFacadePresentationCoverageV3"
const V4_NAME := "GrandPlaceFacadePresentationRefinementV4"
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_INTEGRATED_V5_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var facade := root.get_node_or_null(FACADE_NAME)
    var v3 := root.get_node_or_null(V3_NAME)
    var v4 := root.get_node_or_null(V4_NAME)
    var v5 := root.get_node_or_null(V5_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1200):
        if facade != null and v3 != null and v4 != null and v5 != null and contour != null and bool(facade.get("built")) and bool(v3.get("built")) and bool(v4.get("built")) and bool(v5.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        v3 = root.get_node_or_null(V3_NAME)
        v4 = root.get_node_or_null(V4_NAME)
        v5 = root.get_node_or_null(V5_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or v3 == null or v4 == null or v5 == null or contour == null:
        _fail("required runtimes missing"); return
    if bool(v5.get("failed")) or not bool(v5.get("built")):
        _fail("V5 did not build"); return
    if str(v4.get_meta("human_review_status","")) != "rejected" or int(v4.get_meta("visual_geometry_count",-1)) != 0:
        _fail("human-rejected V4 was not neutralized"); return
    if int(v5.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    for key: String in ["source_geometry_changed","source_collision_changed","camera_changed","threshold_changed"]:
        if bool(v5.get_meta(key,true)):
            _fail("forbidden mutation: %s" % key); return
    if bool(v5.get_meta("lateral_scale_rescue",true)):
        _fail("lateral scale rescue reintroduced"); return
    if int(v5.get("renard_baluster_count")) != 9:
        _fail("Renard baluster count drifted"); return
    if int(v5.get("maison_glazing_panel_count")) != 35 or int(v5.get("maison_structural_pier_count")) != 20:
        _fail("Maison integrated structure accounting drifted"); return
    if int(v5.get("brasseurs_signature_count")) != 11:
        _fail("Brasseurs sourced signature accounting drifted"); return
    if int(v5.get("rose_order_signature_count")) != 16:
        _fail("Rose sourced order accounting drifted"); return
    if int(v5.get("mont_thabor_signature_count")) != 5:
        _fail("Mont Thabor sourced gable accounting drifted"); return
    if int(v5.get_meta("signature_feature_count",-1)) != 32:
        _fail("frontage signature feature total drifted"); return
    for key: String in ["brasseurs_curved_pediment_cue","brasseurs_lower_doric_order_cue","rose_superposed_orders_cue","mont_thabor_gobertange_gable_cue"]:
        if not bool(v5.get_meta(key,false)):
            _fail("documented heritage cue missing: %s" % key); return
    if bool(v5.get_meta("signature_dimensions_surveyed",true)):
        _fail("authored signature dimensions mislabeled surveyed"); return
    if bool(v5.get_meta("renard_balcony_depth_surveyed",true)):
        _fail("authored balcony depth mislabeled surveyed"); return
    if bool(v5.get_meta("statuary_authored",true)) or bool(v5.get_meta("finished_perfect",true)):
        _fail("forbidden statuary/completion claim"); return
    var balcony := facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard/ContinuousBalconyCue") as MeshInstance3D
    if balcony == null or not balcony.scale.is_equal_approx(Vector3.ONE):
        _fail("native Renard balcony width was altered"); return
    var details := v5.get_node_or_null("GrandPlaceFacadeIntegratedRefinementV5Details") as Node3D
    if details == null or details.get_node_or_null("RenardBalconySlab") == null or details.get_node_or_null("RenardBalconyFrontRail") == null:
        _fail("integrated Renard balcony geometry missing"); return
    for required_name: String in ["BrasseursCurvedPediment_3","BrasseursLowerDoricPier_1","RoseDoricCapital_1","RoseIonicCapital_1","RoseCompositeCapital_1","MontThaborGobertangeGable_4"]:
        if details.get_node_or_null(required_name) == null:
            _fail("frontage signature node missing: %s" % required_name); return
    facade.call("set_presentation_visible",false)
    for _frame: int in range(4): await process_frame
    if details.visible:
        _fail("OFF toggle did not hide V5 details"); return
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed collisions"); return
    facade.call("set_presentation_visible",true)
    for _frame: int in range(4): await process_frame
    if not details.visible:
        _fail("ON toggle did not restore V5 details"); return
    print("GRAND_PLACE_FACADE_INTEGRATED_V5_OK: v4_rejected=true lateral_stretch=false renard_balusters=9 maison_glazing=35 maison_piers=20 brasseurs=11 rose_orders=16 mont_thabor=5 collisions=23")
    quit(0)
