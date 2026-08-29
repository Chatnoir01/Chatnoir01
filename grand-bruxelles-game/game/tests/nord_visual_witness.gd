extends SceneTree

const OUTPUT_PATH := "/tmp/nord-city-machine-overview.png"
const TARGET := Vector3(1631.7, 18.0, -2711.4)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NORD_VISUAL_WITNESS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    root.size = Vector2i(1280, 720)

    var world := Node3D.new()
    world.name = "NordVisualWitnessWorld"
    root.add_child(world)

    var zone_script := load("res://game/zones/nord/nord_city_machine_zone.gd") as Script
    if zone_script == null:
        _fail("Nord City Machine runtime missing")
        return

    var zone := Node3D.new()
    zone.name = "NordVisualWitnessZone"
    zone.set_script(zone_script)
    world.add_child(zone)

    var environment_node := WorldEnvironment.new()
    environment_node.name = "NordVisualWitnessEnvironment"
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.07, 0.09, 0.12, 1.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.70, 0.74, 0.82, 1.0)
    environment.ambient_light_energy = 1.25
    environment_node.environment = environment
    world.add_child(environment_node)

    var sun := DirectionalLight3D.new()
    sun.name = "NordVisualWitnessSun"
    sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
    sun.light_energy = 1.45
    sun.shadow_enabled = true
    world.add_child(sun)

    var camera := Camera3D.new()
    camera.name = "NordVisualWitnessCamera"
    camera.position = Vector3(2090.0, 365.0, -2205.0)
    camera.fov = 56.0
    camera.near = 0.5
    camera.far = 5000.0
    world.add_child(camera)
    camera.look_at(TARGET, Vector3.UP)
    camera.current = true

    for _frame in range(12):
        await process_frame

    var stats = zone.get("last_stats")
    if not (stats is Dictionary) or int(stats.get("buildings", 0)) != 1015:
        _fail("Nord source geometry did not finish before capture")
        return

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport capture is empty")
        return
    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        _fail("save_png returned %s" % error_string(error))
        return

    print(
        "NORD_VISUAL_WITNESS_OK path=%s width=%d height=%d buildings=%d street_surfaces=%d promotion=false photo_match=false" % [
            OUTPUT_PATH,
            image.get_width(),
            image.get_height(),
            int(stats.get("buildings", 0)),
            int(stats.get("street_surfaces", 0)),
        ]
    )
    quit(0)
