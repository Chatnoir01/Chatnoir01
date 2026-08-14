extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_PATH := "res://artifacts/ixelles/ixelles_direct_player_1280x720.png"
const EXPECTED_CELL_ID := "bxl-e149000-n169000-s500"
const EXPECTED_CAMERA_AXIS := "https://databrussels.be/id/streetaxe/71374:1"
const EXPECTED_TARGET_AXIS := "https://databrussels.be/id/streetaxe/71306:2"
const EXPECTED_BUILDINGS := 260
const EXPECTED_SKIPPED_BUILDINGS := 460
const EXPECTED_STREET_SURFACES := 309
const EXPECTED_STREET_AXES := 277
const MIN_BODY_CLEARANCE_M := 0.75
const MAX_BODY_CLEARANCE_M := 1.05
const EXPECTED_CAMERA_EYE_HEIGHT_M := 1.72
const EYE_HEIGHT_TOLERANCE_M := 0.03
const MAX_SAMPLE_COLLISION_DELTA_M := 1.0
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return

    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(10):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if slice == null:
        _fail("Ixelles runtime node was not mounted")
        return
    if not bool(slice.get("runtime_loaded")):
        _fail("Ixelles runtime did not load")
        return
    if str(slice.get("cell_id")) != EXPECTED_CELL_ID:
        _fail("cell id drifted")
        return
    if int(slice.get("street_surface_count")) != EXPECTED_STREET_SURFACES or int(slice.get("street_segment_count")) != EXPECTED_STREET_AXES:
        _fail("official street counts drifted")
        return
    if int(slice.get("building_count")) != EXPECTED_BUILDINGS or int(slice.get("skipped_unapproved_height_buildings")) != EXPECTED_SKIPPED_BUILDINGS:
        _fail("strong-height/no-invention building contract drifted")
        return

    if str(player.get_meta("ixelles_direct_camera_axis", "")) != EXPECTED_CAMERA_AXIS:
        _fail("camera StreetAxis witness drifted")
        return
    if str(player.get_meta("ixelles_direct_target_axis", "")) != EXPECTED_TARGET_AXIS:
        _fail("target StreetAxis witness drifted")
        return

    var sampled_ground_y := float(player.get_meta("ixelles_direct_sampled_ground_y", NAN))
    var physical_ground_y := float(player.get_meta("ixelles_direct_physical_ground_y", NAN))
    if not is_finite(sampled_ground_y) or not is_finite(physical_ground_y):
        _fail("sampled/physical ground witness missing")
        return
    var sample_collision_delta := sampled_ground_y - physical_ground_y
    if absf(sample_collision_delta) > MAX_SAMPLE_COLLISION_DELTA_M:
        _fail("sample/collision terrain delta unexpectedly large: %.3f" % sample_collision_delta)
        return

    var body_clearance := player.global_position.y - physical_ground_y
    if body_clearance < MIN_BODY_CLEARANCE_M or body_clearance > MAX_BODY_CLEARANCE_M:
        _fail("player is not safely collision-anchored: clearance=%.3f" % body_clearance)
        return

    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null or not camera.current:
        _fail("player camera unavailable")
        return
    var camera_eye_height := camera.global_position.y - sampled_ground_y
    if absf(camera_eye_height - EXPECTED_CAMERA_EYE_HEIGHT_M) > EYE_HEIGHT_TOLERANCE_M:
        _fail("player camera eye height drifted: %.3f" % camera_eye_height)
        return

    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm == null or absf(spring_arm.spring_length) > 0.001:
        _fail("direct Ixelles witness must keep camera on accepted ground-level source point")
        return

    var location_label := main.get_node_or_null("LocationLabel") as Label
    if location_label == null or location_label.text != "IXELLES · PLACE STÉPHANIE / STEFANIA":
        _fail("Ixelles location label missing")
        return

    var mission_label := main.get_node_or_null("MissionLabel") as CanvasItem
    if mission_label == null or mission_label.visible:
        _fail("mission HUD should be hidden in direct Ixelles view")
        return

    for _frame: int in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("production-player capture invalid: %dx%d" % [image.get_width() if image != null else 0, image.get_height() if image != null else 0])
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("production-player capture save failed")
        return

    print("IXELLES_DIRECT_SPAWN_OK: cell=%s player=(%.3f,%.3f,%.3f) sampled_ground=%.3f physical_ground=%.3f sample_collision_delta=%.3f body_clearance=%.3f camera_eye=%.3f streets=%d axes=%d buildings=%d skipped=%d capture=%s size=%dx%d" % [str(slice.get("cell_id")), player.global_position.x, player.global_position.y, player.global_position.z, sampled_ground_y, physical_ground_y, sample_collision_delta, body_clearance, camera_eye_height, int(slice.get("street_surface_count")), int(slice.get("street_segment_count")), int(slice.get("building_count")), int(slice.get("skipped_unapproved_height_buildings")), OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
