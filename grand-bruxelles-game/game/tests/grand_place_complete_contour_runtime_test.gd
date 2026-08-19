extends SceneTree

const MODULE_PATH := "res://data/runtime/modules/grand_place_complete_contour.json"
const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_witness_contract.json"
const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const EXPECTED_OWNER_IDS := [
    "1601883", "1601884", "1608847", "1608851", "1611166", "1613517",
    "1635455", "1635485", "1637695", "1637729", "1639974", "1639985",
    "1643344", "1645578", "1645580", "1646728", "1647834", "1647943",
    "1649069", "1653185", "1654360", "1661439", "1781508"
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_COMPLETE_CONTOUR_FAIL: %s" % message)
    quit(1)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _source_probe_position(data: Dictionary) -> Vector3:
    var sum := Vector3.ZERO
    var count := 0
    for raw_face: Variant in data.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                if typeof(raw_point) == TYPE_ARRAY and raw_point.size() == 3:
                    sum += Vector3(float(raw_point[0]), 0.0, float(raw_point[2]))
                    count += 1
    return sum / float(count) if count > 0 else Vector3.INF

func _run() -> void:
    var descriptor := _read_json(MODULE_PATH)
    if descriptor.is_empty():
        _fail("runtime descriptor missing")
        return
    if str(descriptor.get("schema", "")) != "grand-bruxelles-runtime-module-v1":
        _fail("runtime descriptor schema drifted")
        return
    if str(descriptor.get("name", "")) != "GrandPlaceCompleteContourRuntime":
        _fail("runtime descriptor name drifted")
        return
    if str(descriptor.get("path", "")) != "res://game/scripts/grand_place_complete_contour_runtime.gd" or not bool(descriptor.get("enabled", false)):
        _fail("runtime descriptor route disabled or drifted")
        return

    var contract := _read_json(CONTRACT_PATH)
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-grand-place-complete-contour-witness-v1":
        _fail("witness contract missing or invalid")
        return
    if str(contract.get("base_main", "")) != "1ef20f00a338a13f74a3a445d3fe4ebc0f35da11":
        _fail("witness base main drifted")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    if bool(hard.get("source_geometry_modified", true)) or bool(hard.get("semantic_guessing_allowed", true)):
        _fail("fail-closed source/semantic rules drifted")
        return
    if bool(hard.get("groundsurface_rendered", true)) or not bool(hard.get("owner_full_frame_review_required", false)):
        _fail("ground/review rules drifted")
        return
    if bool(hard.get("numeric_pass_authorizes_merge", true)):
        _fail("numeric gate may not authorize visual merge")
        return

    var source_faces := 0
    var source_triangles := 0
    var rendered_triangles_expected := 0
    var owners_with_walls := 0
    var first_data: Dictionary = {}
    for owner_id: String in EXPECTED_OWNER_IDS:
        var data := _read_json(SOURCE_DIR.path_join("%s.game.json" % owner_id))
        if data.is_empty():
            _fail("source owner missing: %s" % owner_id)
            return
        if bool(data.get("runtime_approved", true)):
            _fail("source owner unexpectedly runtime-approved: %s" % owner_id)
            return
        var source: Dictionary = data.get("source", {})
        if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id:
            _fail("source identity mismatch: %s" % owner_id)
            return
        if str(source.get("package_sha256", "")) != "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2":
            _fail("source package drifted: %s" % owner_id)
            return
        var evidence: Dictionary = data.get("evidence", {})
        source_faces += int(evidence.get("face_count", 0))
        source_triangles += int(evidence.get("triangle_count", 0))
        var has_wall := false
        for raw_face: Variant in data.get("faces", []):
            if typeof(raw_face) != TYPE_DICTIONARY:
                continue
            var face_type := str(raw_face.get("type", ""))
            var triangles: Array = raw_face.get("triangles", [])
            if face_type == "WALLSURFACE":
                has_wall = true
                rendered_triangles_expected += triangles.size()
            elif face_type == "ROOFSURFACE":
                rendered_triangles_expected += triangles.size()
        if has_wall:
            owners_with_walls += 1
        if owner_id == EXPECTED_OWNER_IDS[0]:
            first_data = data

    if source_faces != 551 or source_triangles != 1712:
        _fail("23-owner source totals drifted: faces=%d triangles=%d" % [source_faces, source_triangles])
        return
    if int(contract.get("expected_source_face_count", 0)) != source_faces or int(contract.get("expected_source_triangle_count", 0)) != source_triangles:
        _fail("contract/source aggregate mismatch")
        return

    var scene := Node3D.new()
    scene.name = "Main"
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    var generated := Node3D.new()
    generated.name = "GeneratedBuildings"
    osm.add_child(generated)
    scene.add_child(osm)

    var probe := Node3D.new()
    probe.name = "GenericOsmProbe"
    probe.position = _source_probe_position(first_data)
    if not probe.position.is_finite():
        _fail("could not derive source-backed OSM probe position")
        return
    generated.add_child(probe)
    root.add_child(scene)

    for _frame: int in range(8):
        await process_frame
    var runtime := root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if runtime == null:
        _fail("runtime registry did not mount GrandPlaceCompleteContourRuntime")
        return
    if runtime.has_method("bind_scene"):
        runtime.call("bind_scene", scene)

    for _frame: int in range(50):
        await process_frame
        if runtime.has_method("ready_complete") and bool(runtime.call("ready_complete")):
            break

    if not runtime.has_method("ready_complete") or not bool(runtime.call("ready_complete")):
        _fail("runtime did not complete")
        return
    if runtime.has_method("failed") and bool(runtime.call("failed")):
        _fail("runtime reported fail-closed source/build error")
        return
    if int(runtime.call("owner_count")) != 23:
        _fail("runtime owner count is not 23")
        return
    if int(runtime.get("source_face_count")) != 551 or int(runtime.get("source_triangle_count")) != 1712:
        _fail("runtime source totals drifted")
        return
    if int(runtime.get("render_triangle_count")) != rendered_triangles_expected:
        _fail("render triangle count does not equal WALL+ROOF source triangles")
        return
    if int(runtime.get("collision_body_count")) != owners_with_walls:
        _fail("wall collision count does not match owners with WALLSURFACE")
        return
    if int(runtime.call("active_collision_count")) != owners_with_walls:
        _fail("official wall collisions are not active")
        return
    if int(runtime.get("masked_osm_count")) < 1 or probe.visible:
        _fail("source contour did not mask overlapping generic OSM probe")
        return
    if str(probe.get_meta("replaced_by_urbis_building", "")) != EXPECTED_OWNER_IDS[0]:
        _fail("OSM replacement metadata does not carry exact UrbIS owner")
        return

    for child: Node in runtime.get_children():
        if child is MeshInstance3D and str(child.name).contains("GROUNDSURFACE"):
            _fail("GROUNDSURFACE must not be rendered by contour runtime")
            return

    runtime.call("set_official_visible", false)
    await process_frame
    if int(runtime.call("visible_surface_count")) != 0 or int(runtime.call("active_collision_count")) != 0:
        _fail("A/B disable did not remove contour surfaces/collisions")
        return
    if not probe.visible:
        _fail("A/B disable did not restore generic OSM witness")
        return

    runtime.call("set_official_visible", true)
    await process_frame
    if int(runtime.call("visible_surface_count")) <= 0 or int(runtime.call("active_collision_count")) != owners_with_walls:
        _fail("A/B re-enable did not restore official contour")
        return
    if probe.visible:
        _fail("A/B re-enable did not remask generic OSM witness")
        return

    print("GRAND_PLACE_COMPLETE_CONTOUR_OK: owners=23 source_faces=%d source_triangles=%d render_triangles=%d collisions=%d masked_osm=%d" % [source_faces, source_triangles, rendered_triangles_expected, owners_with_walls, int(runtime.get("masked_osm_count"))])
    quit(0)
