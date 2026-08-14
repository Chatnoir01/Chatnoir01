extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_HORIZONTAL_DISTANCE_M := 71.06335
const MIN_STANDING_CLEARANCE_M := 0.75
const MAX_STANDING_CLEARANCE_M := 1.10
const EXPECTED_CAMERA_PITCH_DEGREES := -24.0

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

    print("ATOMIUM_DIRECT_SPAWN_OK: distance=%.3f clearance=%.3f player=(%.3f, %.3f, %.3f) anchor=(%.3f, %.3f, %.3f)" % [horizontal_distance, standing_clearance, player_position.x, player_position.y, player_position.z, atomium_anchor.x, atomium_anchor.y, atomium_anchor.z])
    quit(0)
