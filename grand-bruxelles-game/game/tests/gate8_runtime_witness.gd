extends Node3D

const Gate8Loader := preload("res://game/scripts/gate8_visual_loader.gd")
const CAPTURE_SIZE := Vector2i(1280, 720)
const DISTANCES_M := [2.0, 5.0, 8.0]
const VARIANT_COUNT := 8
const FRAMES_TO_SETTLE := 4
const MODEL_VISUAL_FRONT_YAW_DEGREES := 0.0
const MAX_GROUNDING_CORRECTION_M := 0.15

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
            var result := await _capture_variant_distance(variant_index, distance_m, output_dir)
            if result != OK:
                get_tree().quit(3)
                return
            capture_count += 1

    print("GATE8_RUNTIME_WITNESS_OK captures=%d models=%d distances=2m,5m,8m dynamic_grounding=true isolated_subviewport=true front_facing=true front_yaw_deg=%.1f" % [capture_count, VARIANT_COUNT, MODEL_VISUAL_FRONT_YAW_DEGREES])
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
    _camera.position = Vector3(0.0, 1.62, 0.0)
    _camera.fov = 62.0
    _camera.near = 0.05
    _shot_root.add_child(_camera)
    _camera.look_at(Vector3(0.0, 1.0, -5.0), Vector3.UP)
    _camera.current = true

func _capture_variant_distance(variant_index: int, distance_m: float, output_dir: String) -> Error:
    var shot := Node3D.new()
    shot.name = "Shot_%02d_%dm" % [variant_index, int(distance_m)]
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
    # Gate-8 MPFB exports visually face +Z at zero yaw. The camera sits on +Z
    # looking toward -Z, so adding PI turns every witness away from the player.
    # Keep this witness-only correction explicit and gated; runtime activation stays OFF.
    model.rotation_degrees.y = MODEL_VISUAL_FRONT_YAW_DEGREES
    model.set_meta("gate8_external_visual", true)
    shot.add_child(model)

    var correction := Gate8Loader.ground_external_visual(model)
    # The grounding API returns a signed translation. Clean helper-free exports
    # can legitimately need a small negative move when their feet start above
    # the model origin. Gate the magnitude, matching the runtime contract.
    if absf(correction) > MAX_GROUNDING_CORRECTION_M:
        push_error("Gate-8 witness grounding correction out of range model=%02d distance=%.1f correction=%.4f" % [variant_index, distance_m, correction])
        shot.queue_free()
        return ERR_INVALID_DATA

    _add_scale_marker(shot, Vector3(0.95, 0.0, -distance_m))
    _add_label(shot, "variant %02d | %d m" % [variant_index, int(distance_m)], Vector3(-0.95, 2.22, -distance_m), 0.17)

    for _frame: int in range(FRAMES_TO_SETTLE):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw

    var image := _shot_viewport.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("Gate-8 witness screenshot image is empty model=%02d distance=%.1f" % [variant_index, distance_m])
        shot.queue_free()
        return ERR_CANT_ACQUIRE_RESOURCE
    if image.get_size() != CAPTURE_SIZE:
        push_error("Gate-8 witness wrong dimensions model=%02d distance=%.1f size=%s" % [variant_index, distance_m, image.get_size()])
        shot.queue_free()
        return ERR_INVALID_DATA

    var filename := "gate8-%02d-%dm.png" % [variant_index, int(distance_m)]
    var output_path := output_dir.path_join(filename)
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("Gate-8 witness failed to save %s: %s" % [output_path, error_string(save_error)])
        shot.queue_free()
        return save_error

    print("GATE8_RUNTIME_FRAME_OK model=%02d distance=%dm correction=%.4f front_yaw_deg=%.1f screenshot=%s" % [variant_index, int(distance_m), correction, MODEL_VISUAL_FRONT_YAW_DEGREES, output_path])
    shot.queue_free()
    await get_tree().process_frame
    return OK

func _add_label(parent: Node3D, text_value: String, position_value: Vector3, pixel_size: float) -> void:
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
    _add_label(parent, "2.0 m", base_position + Vector3(0.18, 2.05, 0.0), 0.13)
