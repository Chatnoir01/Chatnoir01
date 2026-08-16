extends SceneTree

const WIDTH := 1280
const HEIGHT := 960
const WARMUP_FRAMES := 90
const PRESENTATION_Y_OFFSET_M := 0.17
const EVIDENCE_PATH := "res://data/qa/bourse_parvis_proportions_evidence.json"
const CAMERA_PATH := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const TARGET_ID := "https://databrussels.be/id/streetsurface/22358"
const BEFORE_PATH := "res://artifacts/photo-match/bourse_parvis_proportions_before.png"
const CANDIDATE_PATH := "res://artifacts/photo-match/bourse_parvis_proportions_candidate_22358_plus_1_8m_camera_axis.png"
const SURFACE_PATHS := [
    "res://data/urbis/bourse_street_surfaces.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_22982.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_41098.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_41084.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_21944.game.json",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_PARVIS_PROPORTIONS_CAPTURE_FAIL: %s" % message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _vector2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY:
        return Vector2.ZERO
    var values := raw as Array
    if values.size() != 2:
        return Vector2.ZERO
    return Vector2(float(values[0]), float(values[1]))

func _vector3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY:
        return Vector3.ZERO
    var values := raw as Array
    if values.size() != 3:
        return Vector3.ZERO
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _horizontal_to_vertical_fov(horizontal_degrees: float, aspect: float) -> float:
    if horizontal_degrees <= 0.0 or horizontal_degrees >= 179.0 or aspect <= 0.0:
        return -1.0
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / aspect))

func _material(surface_type: String) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    match surface_type:
        "S":
            material.albedo_color = Color(0.105, 0.108, 0.112, 1.0)
            material.roughness = 0.98
        "SW":
            material.albedo_color = Color(0.48, 0.455, 0.415, 1.0)
            material.roughness = 0.95
        "I":
            material.albedo_color = Color(0.385, 0.37, 0.34, 1.0)
            material.roughness = 0.95
        "P":
            material.albedo_color = Color(0.43, 0.405, 0.365, 1.0)
            material.roughness = 0.96
        _:
            material.albedo_color = Color(0.4, 0.4, 0.4, 1.0)
            material.roughness = 0.96
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _polygon(raw_polygon: Array, shift: Vector2) -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for raw_point: Variant in raw_polygon:
        if typeof(raw_point) != TYPE_ARRAY:
            continue
        var point := raw_point as Array
        if point.size() < 2:
            continue
        polygon.append(Vector2(float(point[0]), float(point[1])) + shift)
    if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.remove_at(polygon.size() - 1)
    return polygon

func _mesh_for_polygon(polygon: PackedVector2Array, surface_type: String) -> ArrayMesh:
    if polygon.size() < 3:
        return null
    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        polygon.reverse()
        indices = Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        return null
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_material(surface_type))
    for raw_index: int in indices:
        var point := polygon[raw_index]
        tool.set_normal(Vector3.UP)
        tool.add_vertex(Vector3(point.x, PRESENTATION_Y_OFFSET_M, point.y))
    return tool.commit()

func _install_qa_surface_overlay(scene: Node, target_shift: Vector2) -> bool:
    var production_surface_context := scene.get_node_or_null("UrbISBourseSurfaceContext") as Node3D
    if production_surface_context == null:
        return false
    production_surface_context.visible = false

    var overlay := Node3D.new()
    overlay.name = "BourseParvisProportionsQAOverlay"
    scene.add_child(overlay)
    var found_target := false
    var count := 0

    for data_path: String in SURFACE_PATHS:
        var data := _json(data_path)
        if str(data.get("schema", "")) != "grand-bruxelles-urbis-bourse-surfaces-v1":
            return false
        for raw_surface: Variant in data.get("surfaces", []):
            if typeof(raw_surface) != TYPE_DICTIONARY:
                continue
            var surface := raw_surface as Dictionary
            if int(surface.get("level", 999)) != 0:
                continue
            var inspire_id := str(surface.get("inspire_id", ""))
            var shift := target_shift if inspire_id == TARGET_ID else Vector2.ZERO
            if inspire_id == TARGET_ID:
                found_target = true
            var rings: Array = surface.get("world_rings_xz", [])
            if rings.size() != 1:
                return false
            var polygon := _polygon(rings[0] as Array, shift)
            var mesh := _mesh_for_polygon(polygon, str(surface.get("type_uninterpreted", "")))
            if mesh == null:
                return false
            var instance := MeshInstance3D.new()
            instance.name = "QA_%s" % inspire_id.get_file()
            instance.mesh = mesh
            instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            overlay.add_child(instance)
            count += 1

    return found_target and count == 7

func _hide_generated_labels(node: Node) -> void:
    if node is Label3D:
        (node as Label3D).visible = false
    for child: Node in node.get_children():
        _hide_generated_labels(child)

func _hide_capture_noise(scene: Node) -> void:
    for node_path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHud"]:
        var item := scene.get_node_or_null(node_path) as CanvasItem
        if item != null:
            item.visible = false
    for node_path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone"]:
        var spatial := scene.get_node_or_null(node_path) as Node3D
        if spatial != null:
            spatial.visible = false
    _hide_generated_labels(scene)

func _capture(output_path: String, target_shift: Vector2, camera_evidence: Dictionary) -> bool:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        return false
    var scene := packed.instantiate()
    if scene == null:
        return false

    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    _hide_capture_noise(scene)
    if not _install_qa_surface_overlay(scene, target_shift):
        scene.free()
        return false

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    viewport.add_child(scene)

    var existing_camera := scene.get_viewport().get_camera_3d()
    if existing_camera != null:
        existing_camera.current = false

    var candidate: Dictionary = camera_evidence.get("candidate_game_camera_transform", {})
    var position := _vector3(candidate.get("position", []))
    var rotation := _vector3(candidate.get("rotation_degrees", []))
    var horizontal_fov := float(candidate.get("horizontal_fov_degrees", 0.0))
    var vertical_fov := _horizontal_to_vertical_fov(horizontal_fov, float(WIDTH) / float(HEIGHT))
    if vertical_fov <= 0.0:
        viewport.queue_free()
        return false

    var camera := Camera3D.new()
    camera.position = position
    camera.rotation_degrees = rotation
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = vertical_fov
    camera.current = true
    scene.add_child(camera)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    _hide_capture_noise(scene)
    RenderingServer.force_draw()
    await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        viewport.queue_free()
        return false
    var absolute_output := ProjectSettings.globalize_path(output_path)
    var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        viewport.queue_free()
        return false
    if image.save_png(absolute_output) != OK:
        viewport.queue_free()
        return false
    viewport.queue_free()
    await process_frame
    return true

func _run() -> void:
    var evidence := _json(EVIDENCE_PATH)
    var camera := _json(CAMERA_PATH)
    if evidence.is_empty() or camera.is_empty():
        _fail("evidence/camera JSON missing")
        return
    if bool(evidence.get("runtime_approved", true)) or bool(evidence.get("realism_complete", true)):
        _fail("capture contract must remain unapproved")
        return
    var candidate: Dictionary = evidence.get("qa_candidate", {})
    var shift := _vector2(candidate.get("translation_xz_m", []))
    if abs(shift.length() - 1.8) > 0.000001:
        _fail("candidate shift is not 1.8 m")
        return

    if not await _capture(BEFORE_PATH, Vector2.ZERO, camera):
        _fail("baseline capture failed")
        return
    if not await _capture(CANDIDATE_PATH, shift, camera):
        _fail("candidate capture failed")
        return

    print("BOURSE_PARVIS_PROPORTIONS_CAPTURE_OK: %s %s" % [BEFORE_PATH, CANDIDATE_PATH])
    quit(0)
