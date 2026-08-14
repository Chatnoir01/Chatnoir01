extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_showcase_spawn.png"
const EXPECTED_CAMERA_OFFSET := Vector3(-185.0, 86.0, 235.0)
const EXPECTED_TARGET_OFFSET := Vector3(0.0, 50.0, 0.0)
const EXPECTED_FOV := 48.0
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_SHOWCASE_SPAWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player")
    if player == null:
        _fail("player missing")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=atomium-showcase"]))
    for _frame: int in range(12):
        await process_frame

    var terrain := main.get_node_or_null("AtomiumDirectTerrain")
    var hero := main.get_node_or_null("AtomiumDirectHero")
    var reflection := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
    var showcase_camera := main.get_node_or_null("AtomiumShowcaseCamera") as Camera3D
    if terrain == null or hero == null or reflection == null or showcase_camera == null:
        _fail("showcase runtime nodes missing")
        return
    if not bool(terrain.get("terrain_loaded")) or not bool(hero.get("hero_built")) or not bool(reflection.get("environment_built")):
        _fail("showcase runtime failed to build")
        return
    var anchor: Vector3 = terrain.get("atomium_game_position")
    var expected_position := anchor + EXPECTED_CAMERA_OFFSET
    if showcase_camera.global_position.distance_to(expected_position) > 0.01:
        _fail("showcase camera position drifted")
        return
    if absf(showcase_camera.fov - EXPECTED_FOV) > 0.01:
        _fail("showcase FOV drifted")
        return
    var expected_forward := (anchor + EXPECTED_TARGET_OFFSET - expected_position).normalized()
    var actual_forward := -showcase_camera.global_basis.z.normalized()
    if actual_forward.dot(expected_forward) < 0.9999:
        _fail("showcase camera aim drifted")
        return
    if not showcase_camera.current:
        _fail("showcase camera is not current")
        return
    if player.visible or player.is_physics_processing() or player.is_processing_unhandled_input():
        _fail("player should be hidden and frozen in showcase mode")
        return
    var location_label := main.get_node_or_null("LocationLabel") as Label
    if location_label == null or location_label.text != "ATOMIUM · HEYSEL / HEIZEL":
        _fail("Atomium showcase location label missing")
        return

    for _frame: int in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("showcase capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("showcase capture save failed")
        return
    print("ATOMIUM_SHOWCASE_SPAWN_OK: camera_offset=%s target_offset=%s fov=%.1f capture=%s size=%dx%d" % [EXPECTED_CAMERA_OFFSET, EXPECTED_TARGET_OFFSET, EXPECTED_FOV, OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
