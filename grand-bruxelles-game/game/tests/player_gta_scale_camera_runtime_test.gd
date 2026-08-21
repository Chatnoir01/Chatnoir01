extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const TARGET_PLAYER_HEIGHT_M := 1.78
const STANDARD_DISTANCE_M := 5.8
const CLOSE_DISTANCE_M := 3.4
const STANDARD_FOV_DEG := 72.0
const THIRD_PERSON_SHOULDER_X_M := 0.34


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PLAYER_GTA_SCALE_CAMERA_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    await process_frame
    await process_frame
    await physics_frame

    var runtime := root.get_node_or_null("GtaScaleCameraRuntime")
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if runtime == null or player == null:
        _fail("production GTA scale runtime or player missing")
        return

    var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision == null or not collision.shape is CapsuleShape3D:
        _fail("player capsule collision missing")
        return
    var capsule := collision.shape as CapsuleShape3D
    if absf(capsule.height - 1.8) > 0.001:
        _fail("player collision contract drifted away from 1.80 m")
        return

    var arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    if arm == null or camera == null or pivot == null:
        _fail("player camera rig incomplete")
        return
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01:
        _fail("standard camera distance is not GTA-scale tuned")
        return
    if absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("standard camera FOV is not GTA-scale tuned")
        return
    if absf(camera.position.x - THIRD_PERSON_SHOULDER_X_M) > 0.01:
        _fail("third-person camera lacks shoulder composition offset")
        return
    if pivot.rotation_degrees.x > -4.0 or pivot.rotation_degrees.x < -10.0:
        _fail("default camera pitch is not a bounded downward third-person angle")
        return

    var projected_share := 2.0 * atan((TARGET_PLAYER_HEIGHT_M * 0.5) / STANDARD_DISTANCE_M) / deg_to_rad(STANDARD_FOV_DEG)
    if projected_share > 0.255 or projected_share < 0.20:
        _fail("standard camera keeps the player too large or too tiny in frame")
        return

    var visual_height := float(player.get_meta("gta_scale_player_visual_height_m", -1.0))
    if visual_height > 0.0 and absf(visual_height - TARGET_PLAYER_HEIGHT_M) > 0.02:
        _fail("authored player visual is not normalized to human scale")
        return

    player.call("cycle_camera_view")
    await process_frame
    if absf(arm.spring_length - CLOSE_DISTANCE_M) > 0.01:
        _fail("close camera profile was not remapped from the legacy oversized view")
        return

    if not bool(player.call("fast_travel_to", "midi")):
        _fail("Midi fast travel failed")
        return
    await process_frame
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01 or absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("fast travel restored the legacy camera instead of the GTA-scale standard")
        return
    if pivot.rotation_degrees.x > -4.0 or pivot.rotation_degrees.x < -10.0:
        _fail("fast travel did not restore the bounded GTA-scale pitch")
        return

    print("PLAYER_GTA_SCALE_CAMERA_OK: capsule=1.80m visual=%.3fm standard=%.2fm fov=%.1f close=%.2fm shoulder=%.2fm" % [
        visual_height,
        arm.spring_length,
        camera.fov,
        CLOSE_DISTANCE_M,
        camera.position.x,
    ])
    quit(0)
