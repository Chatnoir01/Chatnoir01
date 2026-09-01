extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const STYLED := ["1608847", "1608851", "1635485", "1639974", "1646728", "1654360"]
const HOLD := ["1601883","1601884","1611166","1613517","1635455","1637695","1637729","1639985","1643344","1645578","1645580","1647834","1647943","1649069","1653185","1661439","1781508"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_PRESENTATION_FAIL: " + message)
    quit(1)

func _sorted_strings(raw: Variant) -> Array[String]:
    var out: Array[String] = []
    if typeof(raw) == TYPE_ARRAY:
        for value: Variant in raw:
            out.append(str(value))
    out.sort()
    return out

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var contour := root.get_node_or_null(CONTOUR_NAME)
    var facade := root.get_node_or_null(FACADE_NAME)
    for _frame: int in range(900):
        if contour != null and facade != null and bool(contour.get("geometry_loaded")) and bool(facade.get("built")):
            break
        await process_frame
        contour = root.get_node_or_null(CONTOUR_NAME)
        facade = root.get_node_or_null(FACADE_NAME)
    if contour == null or facade == null:
        _fail("required runtimes missing")
        return
    if not bool(contour.get("geometry_loaded")) or not bool(facade.get("built")) or bool(facade.get("failed")):
        _fail("candidate runtimes did not become ready")
        return
    if int(contour.call("owner_count")) != 23:
        _fail("contour owner count drifted")
        return
    if _sorted_strings(facade.call("get_styled_owner_ids")) != _sorted_strings(STYLED):
        _fail("styled owner set drifted")
        return
    if _sorted_strings(facade.call("get_hold_owner_ids")) != _sorted_strings(HOLD):
        _fail("HOLD owner set drifted")
        return
    if int(facade.call("collision_object_count")) != 0:
        _fail("facade presentation created collision objects")
        return
    if bool(facade.get_meta("source_geometry_changed", true)) or bool(facade.get_meta("source_collision_changed", true)):
        _fail("facade presentation claims source geometry/collision changes")
        return
    if bool(facade.get_meta("finished_perfect", true)):
        _fail("visual phase falsely declares finished_perfect")
        return
    var collision_before := int(contour.call("active_collision_count"))
    if collision_before != 23:
        _fail("official contour collision count drifted: %d" % collision_before)
        return
    var feature_counts: Dictionary = facade.call("get_owner_feature_counts")
    for owner_id: String in STYLED:
        if int(feature_counts.get(owner_id, 0)) < 8:
            _fail("styled owner has insufficient authored presentation features: %s" % owner_id)
            return
        var wall := contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % owner_id)
        if wall == null or not wall is MeshInstance3D:
            _fail("styled contour wall missing: %s" % owner_id)
            return
        if str(wall.get_meta("presentation_identity", "neutral_unregistered")) == "neutral_unregistered":
            _fail("styled owner remains neutral: %s" % owner_id)
            return
        if not bool(wall.get_meta("source_geometry_unchanged", false)):
            _fail("styled owner lost source geometry invariant: %s" % owner_id)
            return
    for owner_id: String in HOLD:
        var wall := contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % owner_id)
        if wall == null or not wall is MeshInstance3D:
            _fail("HOLD contour wall missing: %s" % owner_id)
            return
        if str(wall.get_meta("presentation_identity", "")) != "neutral_unregistered":
            _fail("HOLD owner received semantic presentation: %s" % owner_id)
            return
        if wall.material_override != null:
            _fail("HOLD owner received material override: %s" % owner_id)
            return
    facade.call("set_presentation_visible", false)
    await process_frame
    if int(contour.call("active_collision_count")) != collision_before:
        _fail("disabling facade changed official collisions")
        return
    for owner_id: String in STYLED:
        var wall := contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % owner_id)
        if str(wall.get_meta("presentation_identity", "")) != "neutral_unregistered":
            _fail("A/B disable did not restore neutral identity: %s" % owner_id)
            return
    facade.call("set_presentation_visible", true)
    await process_frame
    if int(contour.call("active_collision_count")) != collision_before:
        _fail("enabling facade changed official collisions")
        return
    print("GRAND_PLACE_FACADE_PRESENTATION_OK: styled=6 hold=17 features=%d collisions=%d source_geometry_changed=false finished_perfect=false" % [int(facade.get("feature_count")), collision_before])
    quit(0)
