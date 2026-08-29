extends SceneTree

const FLEET_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")
const AUTHORED_SCRIPT := preload("res://game/scripts/mmc_police_authored_lod_runtime.gd")
const V4_TUNER_SCRIPT := preload("res://game/scripts/mmc_police_v3_presentation_tuner.gd")
const V5_SCRIPT := preload("res://game/scripts/mmc_police_v5_silhouette_tuner.gd")
const V6_SCRIPT := preload("res://game/scripts/mmc_police_v6_source_profile_tuner.gd")
const OUTPUT_EXTERIOR := "res://artifacts/visual/mmc_police_v6_source_profile_exterior.png"
const OUTPUT_SIDE := "res://artifacts/visual/mmc_police_v6_source_profile_side.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_V6_VISUAL_FAIL: %s" % message)
    quit(1)

func _material(color: Color, roughness: float = 0.65) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _capture(path: String) -> bool:
    await process_frame
    await process_frame
    var image := get_root().get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() < 1000 or image.get_height() < 600:
        return false
    return image.save_png(path) == OK

func _run() -> void:
    DisplayServer.window_set_size(Vector2i(1280, 720))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
    var world := Node3D.new()
    world.name = "MMCPoliceV6Witness"
    root.add_child(world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.12, 0.15, 0.19, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.82, 0.84, 0.88, 1.0)
    env.ambient_light_energy = 0.90
    environment.environment = env
    world.add_child(environment)
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(20.0, 15.0)
    ground.mesh = plane
    ground.material_override = _material(Color(0.20, 0.21, 0.23, 1.0), 0.86)
    world.add_child(ground)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    key.light_energy = 1.45
    key.shadow_enabled = true
    world.add_child(key)
    var fill := OmniLight3D.new()
    fill.position = Vector3(0.0, 4.8, 1.5)
    fill.omni_range = 18.0
    fill.light_energy = 3.2
    world.add_child(fill)

    var authored := AUTHORED_SCRIPT.new()
    world.add_child(authored)
    var reference := Node3D.new()
    reference.name = "ParkedCar_00"
    reference.position = Vector3(-2.5, 0.46, 0.45)
    reference.rotation_degrees.y = 15.0
    world.add_child(reference)
    var sedan := authored.call("spawn_driveable_sedan", world, reference) as RigidBody3D
    if sedan == null:
        _fail("driveable sedan spawn failed")
        return
    sedan.freeze = true
    var sedan_holder := sedan.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    if sedan_holder == null or not bool(authored.call("install_on_holder", sedan_holder, authored.call("config_at", 0))) or not bool(authored.call("install_officers", sedan_holder, true)):
        _fail("sedan authored setup failed")
        return

    var coupe := StaticBody3D.new()
    coupe.name = "AmbientTraffic_03"
    coupe.position = Vector3(2.6, 0.0, -0.30)
    coupe.rotation_degrees.y = -15.0
    world.add_child(coupe)
    var fleet := FLEET_SCRIPT.new()
    if not bool(fleet.call("apply_profile_to_vehicle", coupe, 4)):
        _fail("coupe police profile failed")
        return
    var coupe_holder := coupe.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    if coupe_holder == null or not bool(authored.call("install_on_holder", coupe_holder, authored.call("config_at", 1))) or not bool(authored.call("install_officers", coupe_holder, false)):
        _fail("coupe authored setup failed")
        return

    await process_frame
    await process_frame
    await process_frame
    var v4 := V4_TUNER_SCRIPT.new()
    if not bool(v4.call("tune_holder", sedan_holder, "brussels_capitale_sedan")) or not bool(v4.call("tune_holder", coupe_holder, "brussels_rapid_response_coupe")):
        _fail("V4 presentation setup failed")
        return
    var v5 := V5_SCRIPT.new()
    if not bool(v5.call("install_silhouette", sedan_holder, "brussels_capitale_sedan")) or not bool(v5.call("install_silhouette", coupe_holder, "brussels_rapid_response_coupe")):
        _fail("V5 fallback silhouette setup failed")
        return
    var v6 := V6_SCRIPT.new()
    if not bool(v6.call("install_source_profile", sedan_holder, "brussels_capitale_sedan")) or not bool(v6.call("install_source_profile", coupe_holder, "brussels_rapid_response_coupe")):
        _fail("V6 source profile setup failed")
        return
    if not bool(sedan_holder.get_meta("v6_source_profile_authoritative", false)) or not bool(coupe_holder.get_meta("v6_source_profile_authoritative", false)):
        _fail("V6 witness metadata missing")
        return
    var sedan_v5 := sedan_holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
    var coupe_v5 := coupe_holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
    if sedan_v5 == null or coupe_v5 == null or sedan_v5.visible or coupe_v5.visible:
        _fail("V5 fallback remained visible")
        return

    var camera := Camera3D.new()
    camera.position = Vector3(7.6, 3.8, 7.6)
    camera.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
    camera.fov = 48.0
    world.add_child(camera)
    camera.current = true
    if not await _capture(OUTPUT_EXTERIOR):
        _fail("exterior 1280x720 capture failed")
        return
    camera.position = Vector3(7.8, 2.6, 0.5)
    camera.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)
    camera.fov = 44.0
    if not await _capture(OUTPUT_SIDE):
        _fail("side 1280x720 capture failed")
        return
    print("MMC_POLICE_V6_VISUAL_OK: captures=2 resolution=1280x720 profiles=2 source_profile_derived=true")
    quit(0)
