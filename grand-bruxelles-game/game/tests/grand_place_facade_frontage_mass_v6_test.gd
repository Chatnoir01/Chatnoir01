extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V6_NAME := "GrandPlaceFacadeFrontageMassV6"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_FRONTAGE_MASS_V6_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var facade := root.get_node_or_null(FACADE_NAME)
    var v6 := root.get_node_or_null(V6_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1200):
        if facade != null and v6 != null and contour != null and bool(facade.get("built")) and bool(v6.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        v6 = root.get_node_or_null(V6_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or v6 == null or contour == null:
        _fail("required runtimes missing"); return
    if bool(v6.get("failed")) or not bool(v6.get("built")):
        _fail("V6 did not build"); return
    if int(v6.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    for key: String in ["source_geometry_changed","source_collision_changed","camera_changed","fov_changed","threshold_changed","lateral_endpoint_extension"]:
        if bool(v6.get_meta(key,true)):
            _fail("forbidden mutation: %s" % key); return
    if not bool(v6.get_meta("native_owner_span_only",false)):
        _fail("native owner span rail missing"); return
    if bool(v6.get_meta("dimensions_surveyed",true)) or bool(v6.get_meta("statuary_authored",true)) or bool(v6.get_meta("finished_perfect",true)):
        _fail("forbidden surveyed/statuary/completion claim"); return
    if int(v6.get("cornet_renard_mass_count")) != 8:
        _fail("Cornet/Renard mass accounting drifted"); return
    if int(v6.get("brasseurs_mass_count")) != 5 or int(v6.get("rose_mass_count")) != 6 or int(v6.get("mont_thabor_mass_count")) != 5:
        _fail("contiguous frontage mass accounting drifted"); return
    if int(v6.get("feature_count")) != 24:
        _fail("total feature accounting drifted"); return
    var details := v6.get_node_or_null("GrandPlaceFacadeFrontageMassV6Details") as Node3D
    if details == null:
        _fail("V6 details root missing"); return
    for required_name: String in ["CornetNativeFullWidthBand_0","RenardNativeCrownBand","BrasseursFullWidthEntablature","BrasseursPedimentCrown","RoseFullWidthOrderBand_2","RoseCentralOrderProjection_1","MontThaborFullGableMass_4"]:
        if details.get_node_or_null(required_name) == null:
            _fail("required full-mass node missing: %s" % required_name); return
    facade.call("set_presentation_visible",false)
    for _frame: int in range(4): await process_frame
    if details.visible:
        _fail("OFF toggle did not hide V6"); return
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed collisions"); return
    facade.call("set_presentation_visible",true)
    for _frame: int in range(4): await process_frame
    if not details.visible:
        _fail("ON toggle did not restore V6"); return
    print("GRAND_PLACE_FACADE_FRONTAGE_MASS_V6_OK: cornet_renard=8 brasseurs=5 rose=6 mont_thabor=5 features=24 collisions=23 native_owner_span_only=true")
    quit(0)
