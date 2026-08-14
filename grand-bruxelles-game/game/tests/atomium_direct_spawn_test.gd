extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const DIRECT_SPAWN_PRESENTATION_SCRIPT := preload("res://game/scripts/direct_spawn_presentation.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_direct_spawn.png"
const EXPECTED_HORIZONTAL_DISTANCE_M := 120.0
const MIN_STANDING_CLEARANCE_M := 0.75
const MAX_STANDING_CLEARANCE_M := 1.10
const EXPECTED_CAMERA_PITCH_DEGREES := 20.0
const EXPECTED_CAMERA_FOV_DEGREES := 48.0
# The playable project enforces its production viewport at 1280x720.
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame

    var player := main.get_node_or_null("Player")
    if player == null:
        _fail("player missing")
        return

    var presentation := root.get_node_or_null("DirectSpawnPresentation")
    if presentation == null:
        presentation = DIRECT_SPAWN_PRESENTATION_SCRIPT.new()
        presentation.name = "DirectSpawnPresentationTest"
        root.add_child(presentation)
    if not bool(presentation.call("apply_to_player", player, PackedStringArray(["spawn=atomium"]))):
        _fail("Atomium direct presentation framing did not apply")
        return

    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=atomium"]))
    for _frame: int in range(8):
        await process_frame

    var terrain := main.get_node_or_null("AtomiumDirectTerrain")
    var hero := main.get_node_or_null("AtomiumDirectHero")
    var reflection := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
    if terrain == null or hero == null or reflection == null:
        _fail("direct runtime nodes were not mounted")
        return
    if not bool(terrain.get("terrain_loaded")):
        _fail("official Atomium DTM did not load")
        return
    if not bool(hero.get("hero_built")):
        _fail("Atomium hero did not build")
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("Atomium topology drifted")
        return
    if not bool(reflection.get("environment_built")):
        _fail("reflection environment did not build")
        return

    var atomium_anchor: Vector3 = terrain.get("atomium_game_position")
    var player_position: Vector3 = player.global_position
    var horizontal_distance := Vector2(player_position.x - atomium_anchor.x, player_position.z - atomium_anchor.z).length()
    if absf(horizontal_distance - EXPECTED_HORIZONTAL_DISTANCE_M) > 0.05:
        _fail("visitor viewpoint horizontal distance drifted: %.3f" % horizontal_distance)
        return
    if not bool(terrain.call("contains_game_point", player_position.x, player_position.z)):
        _fail("visitor viewpoint left the official DTM")
        return
    var sampled_y := float(terrain.call("sample_height", player_position.x, player_position.z))
    var standing_clearance := player_position.y - sampled_y
    if standing_clearance < MIN_STANDING_CLEARANCE_M or standing_clearance > MAX_STANDING_CLEARANCE_M:
        _fail("visitor viewpoint is not safely terrain anchored: clearance=%.3f" % standing_clearance)
        return

    var camera_pivot := player.get_node_or_null("CameraPivot") as Node3D
    if camera_pivot == null or absf(camera_pivot.rotation_degrees.x - EXPECTED_CAMERA_PITCH_DEGREES) > 0.01:
        _fail("camera pitch drifted")
        return
    var direct_camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if direct_camera == null or absf(direct_camera.fov - EXPECTED_CAMERA_FOV_DEGREES) > 0.01:
        _fail("camera FOV drifted from accepted Atomium framing: %.3f" % [direct_camera.fov if direct_camera != null else -1.0])
        return
    var base_visual := player.get_node_or_null("MeshInstance3D") as Node3D
    if base_visual != null and base_visual.visible:
        _fail("fallback player avatar still occludes direct Atomium witness")
        return
    var upgrade_visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if upgrade_visual != null and upgrade_visual.visible:
        _fail("authored player avatar still occludes direct Atomium witness")
        return

    var location_label := main.get_node_or_null("LocationLabel") as Label
    if location_label == null or location_label.text != "ATOMIUM · HEYSEL / HEIZEL":
        _fail("Atomium location label missing")
        return
    var mission_label := main.get_node_or_null("MissionLabel") as CanvasItem
    if mission_label == null or mission_label.visible:
        _fail("mission HUD should be hidden in direct Atomium view")
        return

    var default_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
    if default_environment == null or default_environment.environment != null:
        _fail("default world environment still competes with Atomium environment")
        return
    var default_sun := main.get_node_or_null("Sun") as DirectionalLight3D
    if default_sun == null or default_sun.visible:
        _fail("default sun still competes with Atomium presentation sun")
        return

    for _frame: int in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("direct spawn capture invalid: %dx%d" % [image.get_width() if image != null else 0, image.get_height() if image != null else 0])
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("direct spawn capture save failed")
        return

    print("ATOMIUM_DIRECT_SPAWN_OK: distance=%.3f clearance=%.3f fov=%.1f avatar_hidden=true player=(%.3f, %.3f, %.3f) anchor=(%.3f, %.3f, %.3f) capture=%s size=%dx%d" % [horizontal_distance, standing_clearance, direct_camera.fov, player_position.x, player_position.y, player_position.z, atomium_anchor.x, atomium_anchor.y, atomium_anchor.z, OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
