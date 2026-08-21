extends SceneTree

const FLEET_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")
const OVERLAY_SCRIPT := preload("res://game/scripts/mmc_police_authored_lod_runtime.gd")
const OUTPUT_EXTERIOR := "res://artifacts/visual/mmc_police_v2_exterior_witness.png"
const OUTPUT_CABIN := "res://artifacts/visual/mmc_police_v2_cabin_witness.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_V2_VISUAL_FAIL: %s" % message)
    quit(1)

func _material(color: Color, roughness: float = 0.6) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    return mat

func _capture(path: String) -> bool:
    await process_frame
    await process_frame
    var image := get_root().get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() < 1000 or image.get_height() < 600:
        return false
    return image.save_png(path) == OK

func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    var world := Node3D.new()
    world.name = "MMCPoliceV2Witness"
    root.add_child(world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.10, 0.13, 0.17, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.78, 0.80, 0.84, 1.0)
    env.ambient_light_energy = 0.88
    environment.environment = env
    world.add_child(environment)
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(18.0, 14.0)
    ground.mesh = plane
    ground.material_override = _material(Color(0.22, 0.23, 0.25, 1.0), 0.82)
    world.add_child(ground)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
    key.light_energy = 1.35
    key.shadow_enabled = true
    world.add_child(key)
    var fill := OmniLight3D.new()
    fill.position = Vector3(0.0, 4.5, 1.0)
    fill.omni_range = 18.0
    fill.light_energy = 3.4
    world.add_child(fill)

    var overlay := OVERLAY_SCRIPT.new()
    world.add_child(overlay)
    var reference := Node3D.new()
    reference.name = "ParkedCar_00"
    reference.position = Vector3(-2.5, 0.46, 0.35)
    reference.rotation_degrees.y = 14.0
    world.add_child(reference)
    var sedan := overlay.call("spawn_driveable_sedan", world, reference) as RigidBody3D
    if sedan == null:
        _fail("driveable sedan witness spawn failed")
        return
    sedan.freeze = true
    var sedan_holder := sedan.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    if sedan_holder == null or not bool(overlay.call("install_on_holder", sedan_holder, overlay.call("config_at", 0))) or not bool(overlay.call("install_officers", sedan_holder, true)):
        _fail("sedan V2 witness setup failed")
        return

    var coupe := StaticBody3D.new()
    coupe.name = "AmbientTraffic_03"
    coupe.position = Vector3(2.6, 0.0, -0.30)
    coupe.rotation_degrees.y = -14.0
    world.add_child(coupe)
    var fleet := FLEET_SCRIPT.new()
    if not bool(fleet.call("apply_profile_to_vehicle", coupe, 4)):
        _fail("coupe witness police profile failed")
        return
    var coupe_holder := coupe.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    if coupe_holder == null or not bool(overlay.call("install_on_holder", coupe_holder, overlay.call("config_at", 1))) or not bool(overlay.call("install_officers", coupe_holder, false)):
        _fail("coupe V2 witness setup failed")
        return

    var camera := Camera3D.new()
    camera.position = Vector3(8.4, 3.4, 9.6)
    camera.fov = 52.0
    camera.look_at_from_position(camera.position, Vector3(0.0, 0.82, 0.0), Vector3.UP)
    camera.current = true
    world.add_child(camera)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
    await process_frame
    await process_frame
    await process_frame
    if not await _capture(OUTPUT_EXTERIOR):
        _fail("exterior witness capture failed")
        return

    camera.position = sedan.global_position + sedan.global_transform.basis * Vector3(2.05, 1.45, -2.25)
    camera.look_at_from_position(camera.position, sedan.global_position + Vector3(0.05, 1.02, -0.15), Vector3.UP)
    camera.fov = 46.0
    if not await _capture(OUTPUT_CABIN):
        _fail("cabin witness capture failed")
        return
    print("MMC_POLICE_V2_VISUAL_OK: exterior=%s cabin=%s project_cabins=2 officers=3 driveable_sedan=true" % [OUTPUT_EXTERIOR, OUTPUT_CABIN])
    quit(0)
