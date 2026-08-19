extends SceneTree

const CONTRACT_PATH := "res://data/qa/grand_place_town_hall_tete_or_semantics.json"

func _fail(message: String) -> void:
    push_error("TOWN_HALL_TETE_OR_SEMANTICS_FAIL: %s" % message)
    quit(1)

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _initialize() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("missing contract")
        return
    var contract_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(contract_variant) != TYPE_DICTIONARY:
        _fail("invalid contract JSON")
        return
    var contract: Dictionary = contract_variant
    if str(contract.get("schema", "")) != "grand-bruxelles-town-hall-tete-or-semantics-v1":
        _fail("schema drift")
        return
    var target: Dictionary = contract.get("target", {})
    var geometry_path: String = str(target.get("geometry_path", ""))
    if not FileAccess.file_exists(geometry_path):
        _fail("missing UrbIS geometry")
        return
    var geometry_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(geometry_path))
    if typeof(geometry_variant) != TYPE_DICTIONARY:
        _fail("invalid UrbIS geometry JSON")
        return
    var geometry: Dictionary = geometry_variant
    var source: Dictionary = geometry.get("source", {})
    if str(source.get("building_2d_id", "")) != str(target.get("urbis_building_id", "")):
        _fail("building identity drift")
        return
    var wanted_face_id: String = str(target.get("urbis_face_id", ""))
    var found: Dictionary = {}
    for raw_face: Variant in geometry.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY and str(raw_face.get("id", "")) == wanted_face_id:
            found = raw_face
            break
    if found.is_empty():
        _fail("face 10796610 missing")
        return
    if str(found.get("type", "")) != "WALLSURFACE":
        _fail("target is not WALLSURFACE")
        return
    var triangles: Array = found.get("triangles", [])
    if triangles.size() != int(target.get("source_triangle_count", -1)):
        _fail("triangle count drift")
        return
    var expected_a := _point(target.get("ground_edge_a", []))
    var expected_b := _point(target.get("ground_edge_b", []))
    var has_a := false
    var has_b := false
    var unique: Dictionary = {}
    for raw_triangle: Variant in triangles:
        if typeof(raw_triangle) != TYPE_ARRAY:
            continue
        for raw_vertex: Variant in raw_triangle:
            var p := _point(raw_vertex)
            if not p.is_finite():
                _fail("invalid source vertex")
                return
            if p.is_equal_approx(expected_a):
                has_a = true
            if p.is_equal_approx(expected_b):
                has_b = true
            unique["%.4f|%.4f|%.4f" % [p.x, p.y, p.z]] = true
    if not has_a or not has_b:
        _fail("official ground-edge anchors drifted")
        return
    if unique.size() != int(target.get("source_vertex_count_unique", -1)):
        _fail("unique source vertex count drift")
        return
    var horizontal_length := Vector2(expected_a.x, expected_a.z).distance_to(Vector2(expected_b.x, expected_b.z))
    if absf(horizontal_length - float(target.get("ground_edge_length_m", -1.0))) > 0.00001:
        _fail("official ground-edge length drift")
        return
    var heritage: Dictionary = contract.get("heritage_source", {})
    if str(heritage.get("provider", "")) != "Urban Brussels" or str(heritage.get("inventory_id", "")) != "31125":
        _fail("heritage identity drift")
        return
    if int(heritage.get("documented_bays", 0)) != 3:
        _fail("Rue de la Tete d'Or three-bay semantic drift")
        return
    if str(heritage.get("semantic_registration", "")) != "west_gothic_wing_lateral_facade_toward_rue_de_la_tete_d_or":
        _fail("semantic registration drift")
        return
    var rules: Dictionary = contract.get("hard_rules", {})
    for key: String in ["runtime_changed", "geometry_changed", "source_vertices_changed", "implementation_authorized", "opening_coordinates_authorized", "statuary_positions_authorized", "exact_dimensions_authorized", "reuse_right_gallery_dimensions", "camera_rescue", "threshold_rescue"]:
        if bool(rules.get(key, true)):
            _fail("fail-closed rule drift: %s" % key)
            return
    print("TOWN_HALL_TETE_OR_SEMANTICS_OK: face=10796610 bays=3 ground_edge=%.6f exposure_gt8=%.4f%% implementation_authorized=false" % [horizontal_length, float(contract.get("screen_exposure", {}).get("full_frame_fraction_gt8", 0.0)) * 100.0])
    quit(0)
