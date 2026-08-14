extends SceneTree

const DATA_PATH := "res://data/visual/grand_place_granite_paving.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_GRANITE_PAVING_FAIL: %s" % message)
    quit(1)

func _polygon_area(points: Array) -> float:
    var area := 0.0
    for index: int in range(points.size()):
        var a := points[index] as Array
        var b := points[(index + 1) % points.size()] as Array
        area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
    return absf(area) * 0.5

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("source-locked paving data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("paving data is not a dictionary")
        return
    var data := parsed as Dictionary
    var source := data.get("source", {}) as Dictionary
    var identity := data.get("material_identity", {}) as Dictionary
    var contract := data.get("presentation_contract", {}) as Dictionary
    var polygon := data.get("polygon_lambert72", []) as Array
    if str(source.get("feature_id", "")) != "https://databrussels.be/id/streetsurface/42405":
        _fail("wrong UrbIS StreetSurfaces feature")
        return
    if str(source.get("street_id", "")) != "https://databrussels.be/id/streetname/3281":
        _fail("wrong Grand-Place street identity")
        return
    if str(source.get("name_fr", "")) != "Grand-Place" or str(source.get("name_nl", "")) != "Grote Markt":
        _fail("bilingual source identity missing")
        return
    if polygon.size() < 80:
        _fail("official polygon unexpectedly simplified")
        return
    var area := _polygon_area(polygon)
    if absf(area - float(source.get("reported_area_m2", 0.0))) > 1.0:
        _fail("polygon area no longer matches official feature")
        return
    if str(identity.get("record", "")) != "Grand-Place, site 322":
        _fail("heritage granite identity source missing")
        return
    if not bool(contract.get("geometry_from_official_street_surface_only", false)) or bool(contract.get("geometry_authored", true)):
        _fail("geometry source contract invalid")
        return
    if bool(contract.get("exact_rgb_is_photometric_measurement", true)) or bool(contract.get("joint_pattern_authored", true)):
        _fail("presentation overclaims material evidence")
        return

    var paving := root.get_node_or_null("GrandPlaceGranitePaving")
    if paving == null:
        _fail("production autoload missing")
        return
    for method_name: String in ["set_presentation_enabled", "presentation_enabled", "source_feature_id", "source_polygon_area_m2"]:
        if not paving.has_method(method_name):
            _fail("runtime method missing: %s" % method_name)
            return
    await process_frame
    if str(paving.call("source_feature_id")) != str(source.get("feature_id", "")):
        _fail("runtime feature identity mismatch")
        return
    if absf(float(paving.call("source_polygon_area_m2")) - area) > 0.1:
        _fail("runtime polygon area mismatch")
        return
    paving.call("set_presentation_enabled", false)
    if bool(paving.call("presentation_enabled")):
        _fail("presentation toggle failed to disable")
        return
    paving.call("set_presentation_enabled", true)
    if not bool(paving.call("presentation_enabled")):
        _fail("presentation toggle failed to enable")
        return
    print("GRAND_PLACE_GRANITE_PAVING_OK: feature=%s points=%d area=%.3f" % [source.get("feature_id", ""), polygon.size(), area])
    quit(0)
