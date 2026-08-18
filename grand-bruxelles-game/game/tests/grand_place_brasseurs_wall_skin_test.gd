extends SceneTree

const SOURCE_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_source.json"
const RUNTIME_PATH := "res://game/scripts/grand_place_brasseurs_wall_skin_runtime.gd"
const WALL_NODE := "GrandPlaceBrasseursWall10945501"
const EXPECTED_VERTICES := [
    Vector3(317.9358, 0.0, -487.4869),
    Vector3(317.9358, 19.166, -487.4869),
    Vector3(321.6678, 24.746, -485.7699),
    Vector3(325.8848, 0.0, -483.8319),
    Vector3(325.8848, 18.966, -483.8319),
]
const EXPECTED_TRIANGLES := [
    [Vector3(317.9358, 19.166, -487.4869), Vector3(317.9358, 0.0, -487.4869), Vector3(325.8848, 0.0, -483.8319)],
    [Vector3(317.9358, 19.166, -487.4869), Vector3(325.8848, 0.0, -483.8319), Vector3(325.8848, 18.966, -483.8319)],
    [Vector3(325.8848, 18.966, -483.8319), Vector3(321.6678, 24.746, -485.7699), Vector3(317.9358, 19.166, -487.4869)],
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_WALL_SKIN_FAIL: " + message)
    quit(1)

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _same(a: Vector3, b: Vector3) -> bool:
    return a.distance_to(b) <= 0.0001

func _read_source() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _assert_source() -> Dictionary:
    var source := _read_source()
    if source.is_empty():
        _fail("source contract missing or invalid")
        return {}
    if str(source.get("schema", "")) != "grand-bruxelles-brasseurs-wall-skin-v2":
        _fail("source schema drifted")
        return {}
    if bool(source.get("runtime_approved", true)) or bool(source.get("realism_complete", true)):
        _fail("RED-first candidate must remain non-approved/incomplete")
        return {}
    var provenance: Dictionary = source.get("source", {})
    if str(provenance.get("license", "")) != "CC0-1.0":
        _fail("official license drifted")
        return {}
    if str(provenance.get("package_sha256", "")) != "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2":
        _fail("official package digest drifted")
        return {}
    if str(provenance.get("extracted_building_sha256", "")) != "7d5927902e43d74b62120436a4f928c56f33185c40428ff4c18aa15fa51b56e1":
        _fail("official building extraction digest drifted")
        return {}

    var target: Dictionary = source.get("target", {})
    if str(target.get("building_id", "")) != "1639974" or str(target.get("front_wall_id", "")) != "10945501":
        _fail("wrong official building/wall identity")
        return {}
    if int(target.get("source_triangle_count", -1)) != 3:
        _fail("official wall triangle count drifted")
        return {}
    if absf(float(target.get("horizontal_span_m", 0.0)) - 8.749036) > 0.0005:
        _fail("official wall span drifted")
        return {}
    if absf(float(target.get("world_y_max_m", 0.0)) - 24.746) > 0.0005:
        _fail("official wall vertical extent drifted")
        return {}

    var raw_vertices: Array = target.get("official_unique_vertices_world", [])
    if raw_vertices.size() != EXPECTED_VERTICES.size():
        _fail("official unique vertex count drifted")
        return {}
    for i: int in range(EXPECTED_VERTICES.size()):
        if not _same(_v3(raw_vertices[i]), EXPECTED_VERTICES[i]):
            _fail("official vertex %d drifted" % i)
            return {}

    var raw_triangles: Array = target.get("official_triangles_world", [])
    if raw_triangles.size() != EXPECTED_TRIANGLES.size():
        _fail("official triangle topology count drifted")
        return {}
    for ti: int in range(EXPECTED_TRIANGLES.size()):
        var tri: Variant = raw_triangles[ti]
        if typeof(tri) != TYPE_ARRAY or tri.size() != 3:
            _fail("official triangle %d malformed" % ti)
            return {}
        for vi: int in range(3):
            if not _same(_v3(tri[vi]), EXPECTED_TRIANGLES[ti][vi]):
                _fail("official triangle %d vertex %d drifted" % [ti, vi])
                return {}

    var presentation: Dictionary = source.get("presentation_contract", {})
    if int(presentation.get("details", -1)) != 0:
        _fail("base wall proof must remain details=0")
        return {}
    if absf(float(presentation.get("outward_offset_m", 999.0))) > 0.000001:
        _fail("outward displacement is forbidden")
        return {}
    if bool(presentation.get("hide_neighbor_geometry", true)):
        _fail("neighbor hiding is forbidden")
        return {}
    if bool(presentation.get("raw_commons_pixels_shipped", true)):
        _fail("raw Commons pixels are forbidden")
        return {}

    var gate: Dictionary = source.get("visual_gate", {})
    if str(gate.get("camera_contract_path", "")) != "res://data/qa/grand_place_clean_player_witness.json":
        _fail("candidate must consume shared #753 camera contract")
        return {}
    if absf(float(gate.get("min_ratio_gt3_rgb", 0.0)) - 0.02) > 0.000001 or absf(float(gate.get("min_ratio_gt8_rgb", 0.0)) - 0.01) > 0.000001:
        _fail("frozen pixel-ratio thresholds drifted")
        return {}
    if int(gate.get("min_bbox_width_px", 0)) != 300 or int(gate.get("min_bbox_height_px", 0)) != 260:
        _fail("frozen bbox thresholds drifted")
        return {}
    if not bool(gate.get("thresholds_frozen_before_first_candidate_render", false)):
        _fail("threshold-freeze invariant missing")
        return {}
    return source

func _run() -> void:
    var source := _assert_source()
    if source.is_empty():
        return

    # RED-first gate: source/topology/gates are valid before runtime exists.
    if not ResourceLoader.exists(RUNTIME_PATH):
        _fail("coherent exact-wall runtime missing (expected RED before implementation)")
        return
    var script: Script = load(RUNTIME_PATH)
    if script == null:
        _fail("cannot load coherent exact-wall runtime")
        return
    var runtime: Node = script.new()
    root.add_child(runtime)
    await process_frame
    await process_frame

    if not runtime.has_method("source_contract"):
        _fail("source_contract() missing")
        return
    var runtime_contract: Dictionary = runtime.call("source_contract")
    if str(runtime_contract.get("building_id", "")) != "1639974" or str(runtime_contract.get("front_wall_id", "")) != "10945501":
        _fail("runtime wall identity drifted")
        return
    if int(runtime_contract.get("unique_vertex_count", -1)) != 5 or int(runtime_contract.get("triangle_count", -1)) != 3:
        _fail("runtime must emit exactly five official vertices / three official triangles")
        return
    if int(runtime_contract.get("detail_count", -1)) != 0:
        _fail("runtime base skin must have details=0")
        return
    if bool(runtime_contract.get("outward_offset_used", true)) or bool(runtime_contract.get("neighbor_geometry_hidden", true)):
        _fail("runtime must not offset wall or hide neighbors")
        return

    var mesh_instance := runtime.get_node_or_null(WALL_NODE) as MeshInstance3D
    if mesh_instance == null or mesh_instance.mesh == null:
        _fail("continuous exact wall mesh missing")
        return
    var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
    var emitted: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if emitted.size() != 9:
        _fail("runtime must emit exactly three triangles / nine vertices")
        return
    for i: int in range(9):
        var expected: Vector3 = EXPECTED_TRIANGLES[int(i / 3)][i % 3]
        if not _same(emitted[i], expected):
            _fail("runtime official triangle topology/order drifted at emitted vertex %d" % i)
            return

    print("BRASSEURS_WALL_SKIN_OK: building=1639974 wall=10945501 official_vertices=5 official_triangles=3 details=0 offset=0 hide_neighbor=false")
    quit(0)
