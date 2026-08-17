extends SceneTree

const RUNTIME_PATH := "res://game/scripts/grand_place_maison_roi_articulation_runtime.gd"
const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const FRONT_FACE_ID := "https://databrussels.be/id/buildingface/10843911"
const PACKAGE_SHA := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_ROI_ARTICULATION_FAIL: " + message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("runtime missing")
        return
    if not FileAccess.file_exists(GEOMETRY_PATH):
        _fail("official 1654360 geometry missing")
        return
    var source := FileAccess.get_file_as_string(RUNTIME_PATH)
    for token: String in [
        "BUILDING_ID := \"https://databrussels.be/id/building/1654360\"",
        "FRONT_FACE_ID := \"https://databrussels.be/id/buildingface/10843911\"",
        "FACADE_BAYS := 9",
        "FACADE_LEVELS := 3",
        "EXPECTED_RENDER_TRIANGLES := 213",
        "_build_surface(faces, \"WALLSURFACE\", _wall_material(), center, true)",
        "render_triangle_count += _build_front_surface(faces, center)",
        "source_bounded_visualization_not_architectural_survey",
        "ornament_authored\", false",
        "openings_authored\", false",
        "geometry_rescaled\", false",
        "vertical_completeness\", false"
    ]:
        if source.find(token) < 0:
            _fail("runtime contract token missing: %s" % token)
            return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("geometry json invalid")
        return
    var data := parsed as Dictionary
    var src := data.get("source", {}) as Dictionary
    var evidence := data.get("evidence", {}) as Dictionary
    if str(src.get("building_2d_id", "")) != BUILDING_ID:
        _fail("building identity drifted")
        return
    if str(src.get("package_sha256", "")) != PACKAGE_SHA:
        _fail("package digest drifted")
        return
    if str(src.get("crs", "")) != "EPSG:31370" or str(src.get("license", "")) != "CC0-1.0":
        _fail("official source CRS/license drifted")
        return
    if int(evidence.get("face_count", 0)) != 71 or int(evidence.get("triangle_count", 0)) != 230:
        _fail("official LoD2 topology drifted")
        return
    if absf(float(evidence.get("height_m", 0.0)) - 30.387) > 0.001:
        _fail("LoD2 height drifted")
        return
    var front_faces := 0
    var front_triangles := 0
    for raw_face: Variant in data.get("faces", []):
        if typeof(raw_face) == TYPE_DICTIONARY and str(raw_face.get("id", "")) == FRONT_FACE_ID:
            front_faces += 1
            front_triangles += (raw_face.get("triangles", []) as Array).size()
    if front_faces != 1 or front_triangles != 11:
        _fail("official front face contract drifted: faces=%d triangles=%d" % [front_faces, front_triangles])
        return
    print("GRAND_PLACE_MAISON_ROI_ARTICULATION_OK front_faces=1 front_triangles=11 render_triangles=213")
    quit(0)
