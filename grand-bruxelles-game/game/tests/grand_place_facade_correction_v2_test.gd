extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const CORRECTION_NAME := "GrandPlaceFacadePresentationCorrectionV2"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_CORRECTION_V2_FAIL: " + message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var facade := root.get_node_or_null(FACADE_NAME)
    var correction := root.get_node_or_null(CORRECTION_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1000):
        if facade != null and correction != null and contour != null and bool(facade.get("built")) and bool(correction.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        correction = root.get_node_or_null(CORRECTION_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or correction == null or contour == null:
        _fail("required runtimes missing")
        return
    if bool(correction.get("failed")) or not bool(correction.get("built")):
        _fail("correction runtime did not build")
        return
    if int(correction.get("correction_feature_count")) < 100:
        _fail("correction feature accounting too small")
        return
    if int(correction.call("collision_object_count")) != 0:
        _fail("correction created collision objects")
        return
    if int(contour.call("active_collision_count")) != 23:
        _fail("official contour collision count drifted")
        return
    if bool(correction.get_meta("source_geometry_changed", true)) or bool(correction.get_meta("source_collision_changed", true)):
        _fail("correction claims source/collision mutation")
        return
    if bool(correction.get_meta("camera_changed", true)) or bool(correction.get_meta("threshold_changed", true)):
        _fail("correction weakened frozen visual gate")
        return
    if not bool(correction.get_meta("legacy_maison_grid_hidden", false)) or not bool(correction.get_meta("maison_grouped_lancets", false)):
        _fail("Maison du Roi grouping correction missing")
        return
    if str(correction.get_meta("cornet_roof_identity", "")) != "slate_and_tile_documented":
        _fail("Cornet documented roof identity missing")
        return
    if bool(correction.get_meta("statuary_authored", true)) or bool(correction.get_meta("finished_perfect", true)):
        _fail("forbidden completion/statuary claim")
        return

    var legacy_maison := facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1654360_Maison_du_Roi") as Node3D
    if legacy_maison == null or legacy_maison.visible:
        _fail("legacy Maison du Roi needle grid was not suppressed")
        return
    var cornet_roof := contour.get_node_or_null("GrandPlaceContour_1608847_ROOFSURFACE") as MeshInstance3D
    if cornet_roof == null or cornet_roof.material_override == null:
        _fail("Cornet roof presentation did not bind")
        return
    if str(cornet_roof.get_meta("presentation_identity", "")) != "Le Cornet":
        _fail("Cornet roof identity not active")
        return

    facade.call("set_presentation_visible", false)
    for _frame: int in range(3):
        await process_frame
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed official collision count")
        return
    if str(cornet_roof.get_meta("presentation_identity", "")) != "neutral_unregistered":
        _fail("OFF toggle did not restore Cornet neutral identity")
        return
    if legacy_maison.visible:
        _fail("OFF toggle resurrected legacy Maison grid")
        return

    facade.call("set_presentation_visible", true)
    for _frame: int in range(3):
        await process_frame
    if str(cornet_roof.get_meta("presentation_identity", "")) != "Le Cornet":
        _fail("ON toggle did not restore Cornet roof presentation")
        return
    if int(contour.call("active_collision_count")) != 23:
        _fail("ON toggle changed official collision count")
        return
    print("GRAND_PLACE_FACADE_CORRECTION_V2_OK: grouped_maison=true cornet_roof=true features=%d collisions=23 camera_unchanged=true thresholds_unchanged=true" % int(correction.get("correction_feature_count")))
    quit(0)
