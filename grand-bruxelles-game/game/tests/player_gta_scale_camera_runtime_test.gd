extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const TARGET_PLAYER_HEIGHT_M := 1.78
const STANDARD_DISTANCE_M := 5.8
const CLOSE_DISTANCE_M := 3.4
const STANDARD_FOV_DEG := 72.0
const COMBAT_AIM_FOV_DEG := 61.0
const FIRST_PERSON_DISTANCE_M := 0.12
const FIRST_PERSON_FOV_DEG := 76.0
const THIRD_PERSON_SHOULDER_X_M := 0.34
const ATOMIUM_PRESENTATION_FOV_DEG := 48.0


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PLAYER_GTA_SCALE_CAMERA_FAIL: %s" % message)
    quit(1)


func _settle_camera_guard() -> void:
    # SceneTree.process_frame is emitted immediately before Node._process callbacks.
    # A direct method call from this probe therefore needs two frame boundaries:
    # one to enter the next process cycle and one to observe the late arbiter result.
    await process_frame
    await process_frame


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    await _settle_camera_guard()
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
    var visual_upgrade := player.get_node_or_null("VisualUpgrade") as Node3D
    if arm == null or camera == null or pivot == null or visual_upgrade == null:
        _fail("player camera or visual rig incomplete")
        return
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01:
        _fail("standard camera distance is not GTA-scale tuned: actual=%.3f expected=%.3f" % [arm.spring_length, STANDARD_DISTANCE_M])
        return
    if absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("standard camera FOV is not GTA-scale tuned: actual=%.3f expected=%.3f meta=%.3f" % [
            camera.fov,
            STANDARD_FOV_DEG,
            float(player.get_meta("gta_scale_camera_fov_deg", -1.0)),
        ])
        return
    if str(player.get_meta("gta_scale_camera_owner", "")) != "gta_gameplay":
        _fail("normal gameplay did not own the standard camera")
        return
    if absf(camera.position.x - THIRD_PERSON_SHOULDER_X_M) > 0.01:
        _fail("third-person camera lacks shoulder composition offset: actual=%.3f" % camera.position.x)
        return
    if pivot.rotation_degrees.x > -4.0 or pivot.rotation_degrees.x < -10.0:
        _fail("default camera pitch is not a bounded downward third-person angle: actual=%.3f" % pivot.rotation_degrees.x)
        return

    var projected_share := 2.0 * atan((TARGET_PLAYER_HEIGHT_M * 0.5) / STANDARD_DISTANCE_M) / deg_to_rad(STANDARD_FOV_DEG)
    if projected_share > 0.255 or projected_share < 0.20:
        _fail("standard camera keeps the player too large or too tiny in frame: projected_share=%.4f" % projected_share)
        return

    var normalized := bool(player.get_meta("gta_scale_player_visual_normalized", false))
    var visual_height := float(player.get_meta("gta_scale_player_visual_height_m", -1.0))
    var source_height := float(player.get_meta("gta_scale_player_visual_source_height_m", -1.0))
    var normalization_scale := float(player.get_meta("gta_scale_player_visual_scale", -1.0))
    if not normalized:
        _fail("authored player was not normalized: reason=%s source_height=%.3f scale=%.5f" % [
            str(player.get_meta("gta_scale_player_visual_reason", "missing")),
            source_height,
            normalization_scale,
        ])
        return
    if absf(visual_height - TARGET_PLAYER_HEIGHT_M) > 0.02:
        _fail("authored player visual is not normalized to human scale: actual=%.3f" % visual_height)
        return

    player.call("cycle_camera_view")
    await _settle_camera_guard()
    if absf(arm.spring_length - CLOSE_DISTANCE_M) > 0.01:
        _fail("close camera profile was not remapped from the legacy oversized view: actual=%.3f" % arm.spring_length)
        return

    if not bool(player.call("fast_travel_to", "midi")):
        _fail("Midi fast travel failed")
        return
    await _settle_camera_guard()
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01 or absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("fast travel restored the legacy camera instead of the GTA-scale standard: distance=%.3f fov=%.3f" % [arm.spring_length, camera.fov])
        return
    if pivot.rotation_degrees.x > -4.0 or pivot.rotation_degrees.x < -10.0:
        _fail("fast travel did not restore the bounded GTA-scale pitch: actual=%.3f" % pivot.rotation_degrees.x)
        return

    # Combat Arsenal writes a legacy default FOV every process cycle. Prove that
    # normal gameplay remains authoritative while idle, and that combat gets camera
    # ownership only for the active aim state.
    player.set_meta("combat_weapon_aiming", true)
    camera.fov = 69.0
    await _settle_camera_guard()
    if absf(camera.fov - COMBAT_AIM_FOV_DEG) > 0.01:
        _fail("combat aim did not receive its FOV authority: actual=%.3f" % camera.fov)
        return
    if str(player.get_meta("gta_scale_camera_owner", "")) != "combat_aim":
        _fail("combat aim owner metadata missing")
        return

    player.set_meta("combat_weapon_aiming", false)
    await _settle_camera_guard()
    if absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("normal GTA camera did not recover after combat aim: actual=%.3f" % camera.fov)
        return

    # Ixelles is a source-verified first-person presentation. Prove that the same
    # legacy combat writer cannot drift its locked FOV.
    player.set_meta("camera_view_locked_first_person", true)
    camera.fov = 69.0
    await _settle_camera_guard()
    if absf(arm.spring_length - FIRST_PERSON_DISTANCE_M) > 0.01 or absf(camera.fov - FIRST_PERSON_FOV_DEG) > 0.01:
        _fail("Ixelles first-person camera lock drifted: distance=%.3f fov=%.3f" % [arm.spring_length, camera.fov])
        return
    if str(player.get_meta("gta_scale_camera_owner", "")) != "special_presentation":
        _fail("Ixelles special presentation did not own camera")
        return
    player.remove_meta("camera_view_locked_first_person")
    if not bool(player.call("fast_travel_to", "midi")):
        _fail("Midi fast travel after Ixelles camera lock failed")
        return
    await _settle_camera_guard()
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01 or absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("normal gameplay did not recover after Ixelles lock: distance=%.3f fov=%.3f" % [arm.spring_length, camera.fov])
        return

    # DirectSpawnPresentation marks Atomium and hides the avatar while its exact
    # 48-degree witness is active. This must beat the combat runtime's per-frame
    # legacy FOV writer. Fast travel must then release ownership even if startup
    # metadata remains stale.
    player.set_meta("atomium_direct_presentation_fov_degrees", ATOMIUM_PRESENTATION_FOV_DEG)
    player.set_meta("atomium_direct_presentation_avatar_hidden", true)
    visual_upgrade.visible = false
    camera.fov = ATOMIUM_PRESENTATION_FOV_DEG
    await _settle_camera_guard()
    if absf(camera.fov - ATOMIUM_PRESENTATION_FOV_DEG) > 0.01:
        _fail("camera authority failed to preserve active Atomium presentation FOV: actual=%.3f" % camera.fov)
        return
    if str(player.get_meta("gta_scale_camera_owner", "")) != "special_presentation":
        _fail("Atomium special presentation did not own camera")
        return

    if not bool(player.call("fast_travel_to", "midi")):
        _fail("Midi fast travel from Atomium presentation failed")
        return
    await _settle_camera_guard()
    if not player.has_meta("atomium_direct_presentation_fov_degrees"):
        _fail("Atomium stale-metadata exit proof unexpectedly lost its marker")
        return
    if not visual_upgrade.visible:
        _fail("fast travel did not restore the authored player visual")
        return
    if absf(arm.spring_length - STANDARD_DISTANCE_M) > 0.01 or absf(camera.fov - STANDARD_FOV_DEG) > 0.01:
        _fail("normal gameplay did not retake camera authority after Atomium exit: distance=%.3f fov=%.3f" % [arm.spring_length, camera.fov])
        return
    if str(player.get_meta("gta_scale_camera_owner", "")) != "gta_gameplay":
        _fail("gameplay camera ownership did not recover after Atomium exit")
        return

    player.remove_meta("atomium_direct_presentation_fov_degrees")
    player.remove_meta("atomium_direct_presentation_avatar_hidden")

    print("PLAYER_GTA_SCALE_CAMERA_OK: capsule=1.80m source_visual=%.3fm visual=%.3fm scale=%.5f standard=%.2fm fov=%.1f close=%.2fm shoulder=%.2fm projected_share=%.4f combat_aim=%.1f ixelles_locked=true atomium_preserved=true special_exit_recovered=true" % [
        source_height,
        visual_height,
        normalization_scale,
        arm.spring_length,
        camera.fov,
        CLOSE_DISTANCE_M,
        camera.position.x,
        projected_share,
        COMBAT_AIM_FOV_DEG,
    ])
    quit(0)
