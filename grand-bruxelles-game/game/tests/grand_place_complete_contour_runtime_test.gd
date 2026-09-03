extends SceneTree

const MODULE_PATH := "res://data/runtime/modules/grand_place_complete_contour.json"
const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_witness_contract.json"
const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const PACKAGE_SHA := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const TRIANGLE_CROSS_EPSILON_SQ := 1.0e-12
const EXPECTED_BASE_MAIN := "c3bbf44806da07ae5064fd89f48e52afb7ba1f6b"
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

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _is_renderable_triangle(raw: Variant) -> bool:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return false
    var a := _point(raw[0])
    var b := _point(raw[1])
    var c := _point(raw[2])
    if not a.is_finite() or not b.is_finite() or not c.is_finite():
        return false
    var cross := (b - a).cross(c - a)
    return cross.is_finite() and cross.length_squared() > TRIANGLE_CROSS_EPSILON_SQ

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
                var p := _point(raw_point)
                if p.is_finite():
                    sum += Vector3(p.x, 0.0, p.z)
                    count += 1
    return sum / float(count) if count > 0 else Vector3.INF

func _run() -> void:
    var descriptor := _read_json(MODULE_PATH)
    if descriptor.is_empty() or str(descriptor.get("schema", "")) != "grand-bruxelles-runtime-module-v1":
        _fail("runtime descriptor missing or invalid")
        return
    if str(descriptor.get("name", "")) != "GrandPlaceCompleteContourRuntime" or str(descriptor.get("path", "")) != "res://game/scripts/grand_place_complete_contour_runtime.gd" or not bool(descriptor.get("enabled", false)):
        _fail("runtime descriptor route disabled or drifted")
        return

    var contract := _read_json(CONTRACT_PATH)
    if contract.is_empty() or str(contract.get("schema", "")) != "grand-bruxelles-grand-place-complete-contour-witness-v2":
        _fail("witness v2 contract missing or invalid")
        return
    if str(contract.get("base_main", "")) != EXPECTED_BASE_MAIN:
        _fail("witness base main drifted")
        return
    var hard: Dictionary = contract.get("hard_rules", {})
    if bool(hard.get("source_geometry_modified", true)) or bool(hard.get("semantic_guessing_allowed", true)) or bool(hard.get("groundsurface_rendered", true)):
        _fail("source/semantic/ground fail-closed rules drifted")
        return
    if bool(hard.get("numeric_pass_authorizes_merge", true)) or not bool(hard.get("owner_full_frame_review_required", false)):
        _fail("visual owner-review rule drifted")
        return
    var accounting: Dictionary = contract.get("triangle_accounting", {})
    if absf(float(accounting.get("cross_length_squared_epsilon", -1.0)) - TRIANGLE_CROSS_EPSILON_SQ) > 1.0e-15:
        _fail("triangle degeneracy epsilon drifted")
        return
    if not bool(accounting.get("non_degenerate_wall_roof_triangles_must_render", false)) or not bool(accounting.get("render_plus_degenerate_must_equal_wall_roof_source_entries", false)):
        _fail("triangle accounting contract is not closed")
        return
    if bool(accounting.get("degenerate_geometry_repair_allowed", true)):
        _fail("degenerate source geometry may not be invented/repaired")
        return

    var source_faces := 0
    var source_triangles := 0
    var wall_roof_source := 0
    var renderable_wall_roof := 0
    var degenerate_wall_roof := 0
    var owners_with_renderable_walls := 0
    var first_data: Dictionary = {}
    for owner_id: String in EXPECTED_OWNER_IDS:
        var data := _read_json(SOURCE_DIR.path_join("%s.game.json" % owner_id))
        if data.is_empty() or bool(data.get("runtime_approved", true)):
            _fail("source owner missing/approval drift: %s" % owner_id)
            return
        var source: Dictionary = data.get("source", {})
        if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id or str(source.get("package_sha256", "")) != PACKAGE_SHA:
            _fail("source identity/package drift: %s" % owner_id)
            return
        var evidence: Dictionary = data.get("evidence", {})
        source_faces += int(evidence.get("face_count", 0))
        source_triangles += int(evidence.get("triangle_count", 0))
        var valid_wall_count := 0
        for raw_face: Variant in data.get("faces", []):
            if typeof(raw_face) != TYPE_DICTIONARY:
                continue
            var face_type := str(raw_face.get("type", ""))
            if face_type not in ["WALLSURFACE", "ROOFSURFACE"]:
                continue
            for raw_triangle: Variant in raw_face.get("triangles", []):
                wall_roof_source += 1
                if _is_renderable_triangle(raw_triangle):
                    renderable_wall_roof += 1
                    if face_type == "WALLSURFACE":
                        valid_wall_count += 1
                else:
                    degenerate_wall_roof += 1
        if valid_wall_count > 0:
            owners_with_renderable_walls += 1
        if owner_id == EXPECTED_OWNER_IDS[0]:
            first_data = data

    if source_faces != 551 or source_triangles != 1712:
        _fail("23-owner source totals drifted: faces=%d triangles=%d" % [source_faces, source_triangles])
        return
    if renderable_wall_roof + degenerate_wall_roof != wall_roof_source:
        _fail("pre-runtime triangle accounting does not close")
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

    var canonical_point: Vector3 = runtime.call("_point", [281.3858, 0.0, -472.4659])
    if not canonical_point.is_finite() or not canonical_point.is_equal_approx(Vector3(281.3858, 0.0, -472.4659)):
        _fail("runtime changed canonical numeric source point")
        return
    for rejected_point: Variant in [
        ["281.3858", 0.0, -472.4659],
        [true, 0.0, -472.4659],
        [NAN, 0.0, -472.4659],
        [INF, 0.0, -472.4659],
        [281.3858, -INF, -472.4659],
        [281.3858, 0.0],
        {"x": 281.3858, "y": 0.0, "z": -472.4659}
    ]:
        var rejected: Vector3 = runtime.call("_point", rejected_point)
        if rejected.is_finite():
            _fail("runtime coerced non-canonical source point: %s -> %s" % [rejected_point, rejected])
            return

    if runtime.has_method("bind_scene"):
        runtime.call("bind_scene", scene)
    for _frame: int in range(60):
        await process_frame
        if runtime.has_method("ready_complete") and bool(runtime.call("ready_complete")):
            break

    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime did not complete cleanly")
        return
    if int(runtime.call("owner_count")) != 23 or int(runtime.get("source_face_count")) != 551 or int(runtime.get("source_triangle_count")) != 1712:
        _fail("runtime owner/source totals drifted")
        return
    if int(runtime.get("wall_roof_source_triangle_count")) != wall_roof_source:
        _fail("runtime WALL+ROOF source entry count drifted")
        return
    if int(runtime.get("render_triangle_count")) != renderable_wall_roof:
        _fail("runtime dropped a non-degenerate WALL+ROOF triangle")
        return
    if int(runtime.get("degenerate_render_triangle_count")) != degenerate_wall_roof:
        _fail("runtime degenerate WALL+ROOF accounting drifted")
        return
    if int(runtime.get("render_triangle_count")) + int(runtime.get("degenerate_render_triangle_count")) != int(runtime.get("wall_roof_source_triangle_count")):
        _fail("runtime render+degenerate accounting does not close")
        return
    if int(runtime.get("collision_body_count")) != owners_with_renderable_walls or int(runtime.call("active_collision_count")) != owners_with_renderable_walls:
        _fail("official wall collision owner count drifted")
        return
    if int(runtime.get("masked_osm_count")) < 1 or probe.visible:
        _fail("source contour did not mask overlapping generic OSM probe")
        return

    for child: Node in runtime.get_children():
        if child is MeshInstance3D and str(child.name).contains("GROUNDSURFACE"):
            _fail("GROUNDSURFACE must not be rendered by contour runtime")
            return

    runtime.call("set_official_visible", false)
    await process_frame
    if int(runtime.call("visible_surface_count")) != 0 or int(runtime.call("active_collision_count")) != 0 or not probe.visible:
        _fail("A/B disable did not fully restore baseline state")
        return
    runtime.call("set_official_visible", true)
    await process_frame
    if int(runtime.call("visible_surface_count")) <= 0 or int(runtime.call("active_collision_count")) != owners_with_renderable_walls or probe.visible:
        _fail("A/B re-enable did not fully restore official state")
        return

    print("GRAND_PLACE_COMPLETE_CONTOUR_OK: owners=23 source_faces=%d source_triangles=%d wall_roof_source=%d renderable=%d degenerate=%d collisions=%d masked_osm=%d base=%s" % [source_faces, source_triangles, wall_roof_source, renderable_wall_roof, degenerate_wall_roof, owners_with_renderable_walls, int(runtime.get("masked_osm_count")), str(contract.get("base_main", ""))])
    quit(0)