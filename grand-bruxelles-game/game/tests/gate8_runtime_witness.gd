extends Node3D

const Gate8Loader := preload("res://game/scripts/gate8_visual_loader.gd")
const CAPTURE_SIZE := Vector2i(1280, 720)
const DISTANCES_M := [2.0, 5.0, 8.0]
const VARIANT_COUNT := 8
const FRAMES_TO_SETTLE := 4
const MODEL_VISUAL_FRONT_YAW_DEGREES := 0.0
const REVIEW_THREE_QUARTER_YAW_DEGREES := 30.0
const REVIEW_DETAIL_DISTANCE_M := 2.0
const MAX_GROUNDING_CORRECTION_M := 0.15
const CAMERA_EYE_HEIGHT_M := 1.62
const CAMERA_FOV_DEGREES := 68.0
const FRAME_MARGIN_PX := 20.0
const REVIEW_LABEL_PIXEL_SIZE := 0.004
const SCALE_LABEL_PIXEL_SIZE := 0.003
const MAX_ANNOTATION_PIXEL_SIZE := 0.004

var _shot_viewport: SubViewport
var _shot_root: Node3D
var _camera: Camera3D

func _ready() -> void:
    ProjectSettings.set_setting(Gate8Loader.ENABLE_SETTING, true)
    _build_isolated_viewport()
    var output_dir := OS.get_environment("GATE8_WITNESS_DIR")
    if output_dir.is_empty():
        output_dir = "user://gate8_runtime_witness"
    var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        push_error("Gate-8 witness failed to create output dir: %s" % error_string(mkdir_error))
        get_tree().quit(2)
        return

    var capture_count := 0
    for variant_index: int in range(1, VARIANT_COUNT + 1):
        for distance_m: float in DISTANCES_M:
            var result := await _capture_variant(variant_index, distance_m, MODEL_VISUAL_FRONT_YAW_DEGREES, "front", "", output_dir)
            if result != OK:
                get_tree().quit(3)
                return
            capture_count += 1
        # A frontal-only review can hide waist seams, clipping and shoe/leg fit.
        # Add one close three-quarter witness per candidate before any GARDER.
        var detail_result := await _capture_variant(
            variant_index,
            REVIEW_DETAIL_DISTANCE_M,
            REVIEW_THREE_QUARTER_YAW_DEGREES,
            "three_quarter",
            "-3q",
            output_dir
        )
        if detail_result != OK:
            get_tree().quit(3)
            return
        capture_count += 1

    print("GATE8_RUNTIME_WITNESS_OK captures=%d models=%d distances=2m,5m,8m views=front,three_quarter detail_distance_m=%.1f detail_yaw_deg=%.1f dynamic_grounding=true isolated_subviewport=true front_facing=true front_yaw_deg=%.1f full_body_framing=true camera_fov_deg=%.1f annotation_max_pixel_size=%.3f" % [capture_count, VARIANT_COUNT, REVIEW_DETAIL_DISTANCE_M, REVIEW_THREE_QUARTER_YAW_DEGREES, MODEL_VISUAL_FRONT_YAW_DEGREES, CAMERA_FOV_DEGREES, MAX_ANNOTATION_PIXEL_SIZE])
    get_tree().quit(0)

func _build_isolated_viewport() -> void:
    _shot_viewport = SubViewport.new()
    _shot_viewport.name = "Gate8ReviewViewport"
    _shot_viewport.size = CAPTURE_SIZE
    _shot_viewport.own_world_3d = true
    _shot_viewport.transparent_bg = false
    _shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(_shot_viewport)

    _shot_root = Node3D.new()
    _shot_root.name = "ReviewWorld"
    _shot_viewport.add_child(_shot_root)

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.08, 0.10, 0.14, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.72, 0.75, 0.82, 1.0)
    env.ambient_light_energy = 0.8
    environment.environment = env
    _shot_root.add_child(environment)

    var key_light := DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-48.0, -24.0, 0.0)
    key_light.light_energy = 1.4
    key_light.shadow_enabled = true
    _shot_root.add_child(key_light)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25.0, 155.0, 0.0)
    fill.light_energy = 0.55
    _shot_root.add_child(fill)

    var floor := MeshInstance3D.new()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(14.0, 20.0)
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.24, 0.26, 0.29, 1.0)
    floor_material.roughness = 0.96
    floor_mesh.material = floor_material
    floor.mesh = floor_mesh
    floor.position = Vector3(0.0, -0.005, -4.5)
    _shot_root.add_child(floor)

    _camera = Camera3D.new()
    _camera.name = "WitnessCamera"
    _camera.position = Vector3(0.0, CAMERA_EYE_HEIGHT_M, 0.0)
    _camera.fov = CAMERA_FOV_DEGREES
    _camera.near = 0.05
    _shot_root.add_child(_camera)
    _camera.look_at(Vector3(0.0, 1.0, -5.0), Vector3.UP)
    _camera.current = true

func _capture_variant(variant_index: int, distance_m: float, yaw_degrees: float, view_name: String, filename_suffix: String, output_dir: String) -> Error:
    var shot := Node3D.new()
    shot.name = "Shot_%02d_%dm_%s" % [variant_index, int(distance_m), view_name]
    _shot_root.add_child(shot)

    var path := Gate8Loader.path_for_index(variant_index)
    var packed := load(path) as PackedScene
    if packed == null:
        push_error("Gate-8 witness missing %s" % path)
        shot.queue_free()
        return ERR_FILE_NOT_FOUND

    var model := packed.instantiate() as Node3D
    if model == null:
        push_error("Gate-8 witness could not instantiate %s" % path)
        shot.queue_free()
        return ERR_CANT_CREATE

    model.name = "Gate8_%02d" % variant_index
    model.position = Vector3(0.0, 0.0, -distance_m)
    # Gate-8 MPFB exports visually face +Z at zero yaw. Front evidence stays at
    # zero; the bounded +30 degree detail view is witness-only and never runtime.
    model.rotation_degrees.y = yaw_degrees
    model.set_meta("gate8_external_visual", true)
    shot.add_child(model)

    var correction := Gate8Loader.ground_external_visual(model)
    if absf(correction) > MAX_GROUNDING_CORRECTION_M:
        push_error("Gate-8 witness grounding correction out of range model=%02d distance=%.1f view=%s correction=%.4f" % [variant_index, distance_m, view_name, correction])
        shot.queue_free()
        return ERR_INVALID_DATA

    var world_bounds := _rest_vertex_world_bounds(model)
    if not bool(world_bounds.get("valid", false)):
        push_error("Gate-8 witness has no rest vertices for framing model=%02d distance=%.1f view=%s" % [variant_index, distance_m, view_name])
        shot.queue_free()
        return ERR_INVALID_DATA
    var bounds_min: Vector3 = world_bounds["min"]
    var bounds_max: Vector3 = world_bounds["max"]
    var visual_center := (bounds_min + bounds_max) * 0.5
    _camera.position = Vector3(0.0, CAMERA_EYE_HEIGHT_M, 0.0)
    _camera.look_at(visual_center, Vector3.UP)

    _add_scale_marker(shot, Vector3(0.95, 0.0, -distance_m))
    _add_label(shot, "variant %02d | %d m | %s" % [variant_index, int(distance_m), view_name], Vector3(-0.95, 2.22, -distance_m), REVIEW_LABEL_PIXEL_SIZE)

    for _frame: int in range(FRAMES_TO_SETTLE):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw

    var screen_bounds := _rest_vertex_screen_bounds(model)
    if not bool(screen_bounds.get("valid", false)):
        push_error("Gate-8 witness could not project rest vertices model=%02d distance=%.1f view=%s" % [variant_index, distance_m, view_name])
        shot.queue_free()
        return ERR_INVALID_DATA
    var screen_min: Vector2 = screen_bounds["min"]
    var screen_max: Vector2 = screen_bounds["max"]
    var min_margin_px := minf(minf(screen_min.x, screen_min.y), minf(float(CAPTURE_SIZE.x) - screen_max.x, float(CAPTURE_SIZE.y) - screen_max.y))
    if min_margin_px < FRAME_MARGIN_PX:
        push_error("Gate-8 witness clips full body model=%02d distance=%.1f view=%s margin_px=%.2f screen_min=%s screen_max=%s" % [variant_index, distance_m, view_name, min_margin_px, screen_min, screen_max])
        shot.queue_free()
        return ERR_INVALID_DATA

    var image := _shot_viewport.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("Gate-8 witness screenshot image is empty model=%02d distance=%.1f view=%s" % [variant_index, distance_m, view_name])
        shot.queue_free()
        return ERR_CANT_ACQUIRE_RESOURCE
    if image.get_size() != CAPTURE_SIZE:
        push_error("Gate-8 witness wrong dimensions model=%02d distance=%.1f view=%s size=%s" % [variant_index, distance_m, view_name, image.get_size()])
        shot.queue_free()
        return ERR_INVALID_DATA

    var filename := "gate8-%02d-%dm%s.png" % [variant_index, int(distance_m), filename_suffix]
    var output_path := output_dir.path_join(filename)
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("Gate-8 witness failed to save %s: %s" % [output_path, error_string(save_error)])
        shot.queue_free()
        return save_error

    print("GATE8_RUNTIME_FRAME_OK model=%02d distance=%dm view=%s yaw_deg=%.1f correction=%.4f frame_margin_px=%.1f full_body=true screenshot=%s" % [variant_index, int(distance_m), view_name, yaw_degrees, correction, min_margin_px, output_path])
    shot.queue_free()
    await get_tree().process_frame
    return OK

func _rest_vertex_world_bounds(root: Node3D) -> Dictionary:
    var minimum := Vector3(INF, INF, INF)
    var maximum := Vector3(-INF, -INF, -INF)
    var vertex_count := 0
    for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
            if arrays.size() <= Mesh.ARRAY_VERTEX:
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            for vertex: Vector3 in vertices:
                var world_vertex := mesh_instance.global_transform * vertex
                minimum.x = minf(minimum.x, world_vertex.x)
                minimum.y = minf(minimum.y, world_vertex.y)
                minimum.z = minf(minimum.z, world_vertex.z)
                maximum.x = maxf(maximum.x, world_vertex.x)
                maximum.y = maxf(maximum.y, world_vertex.y)
                maximum.z = maxf(maximum.z, world_vertex.z)
                vertex_count += 1
    return {"valid": vertex_count > 0, "min": minimum, "max": maximum, "vertex_count": vertex_count}

func _rest_vertex_screen_bounds(root: Node3D) -> Dictionary:
    var minimum := Vector2(INF, INF)
    var maximum := Vector2(-INF, -INF)
    var vertex_count := 0
    for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
            if arrays.size() <= Mesh.ARRAY_VERTEX:
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            for vertex: Vector3 in vertices:
                var world_vertex := mesh_instance.global_transform * vertex
                var screen_vertex := _camera.unproject_position(world_vertex)
                minimum.x = minf(minimum.x, screen_vertex.x)
                minimum.y = minf(minimum.y, screen_vertex.y)
                maximum.x = maxf(maximum.x, screen_vertex.x)
                maximum.y = maxf(maximum.y, screen_vertex.y)
                vertex_count += 1
    return {"valid": vertex_count > 0, "min": minimum, "max": maximum, "vertex_count": vertex_count}

func _add_label(parent: Node3D, text_value: String, position_value: Vector3, pixel_size: float) -> void:
    if pixel_size <= 0.0 or pixel_size > MAX_ANNOTATION_PIXEL_SIZE:
        push_error("Gate-8 witness annotation pixel size out of range: %.4f" % pixel_size)
        return
    var label := Label3D.new()
    label.text = text_value
    label.position = position_value
    label.pixel_size = pixel_size
    label.font_size = 42
    label.outline_size = 8
    label.modulate = Color.WHITE
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    parent.add_child(label)

func _add_scale_marker(parent: Node3D, base_position: Vector3) -> void:
    var marker := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.045, 2.0, 0.045)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.96, 0.82, 0.20, 1.0)
    material.emission_enabled = true
    material.emission = Color(0.35, 0.22, 0.02, 1.0)
    mesh.material = material
    marker.mesh = mesh
    marker.position = base_position + Vector3(0.0, 1.0, 0.0)
    parent.add_child(marker)
    _add_label(parent, "2.0 m", base_position + Vector3(0.18, 2.05, 0.0), SCALE_LABEL_PIXEL_SIZE)