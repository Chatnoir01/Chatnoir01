extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const LOCOMOTION_RUNTIME := preload("res://game/scripts/authored_player_locomotion_runtime.gd")
const REAL_ASSET := "res://assets/characters/player_character.glb"

func _fail(message: String) -> void:
    push_error("AUTHORED_PLAYER_LOCOMOTION_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if not ResourceLoader.exists(REAL_ASSET):
        _fail("real authored player asset is unavailable")
        return

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)
    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("Player did not select authored character")
        return

    var runtime := LOCOMOTION_RUNTIME.new()
    runtime.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(runtime)
    if not runtime.bind_target(actor, visual):
        _fail("authored locomotion runtime could not bind to production Player")
        return

    var locomotion: Dictionary = runtime.resolved_locomotion_animations()
    for key: String in ["idle", "walk", "run"]:
        if String(locomotion.get(key, "")).is_empty():
            _fail("missing resolved %s animation" % key)
            return
    if String(locomotion["walk"]) == String(locomotion["run"]):
        _fail("walk and run resolved to the same animation")
        return

    actor.velocity = Vector3.ZERO
    runtime.update_from_speed()
    var idle_name := runtime.current_animation()
    if idle_name != String(locomotion["idle"]):
        _fail("zero speed did not select idle: %s" % idle_name)
        return

    actor.velocity = Vector3(2.5, 0.0, 0.0)
    runtime.update_from_speed()
    var walk_name := runtime.current_animation()
    if walk_name != String(locomotion["walk"]):
        _fail("walking speed did not select walk: %s" % walk_name)
        return
    var walk_scale_reference := runtime.current_playback_speed_scale()

    actor.velocity = Vector3(1.25, 0.0, 0.0)
    runtime.update_from_speed()
    var walk_scale_slow := runtime.current_playback_speed_scale()
    actor.velocity = Vector3(3.75, 0.0, 0.0)
    runtime.update_from_speed()
    var walk_scale_fast := runtime.current_playback_speed_scale()
    if not (walk_scale_slow < walk_scale_reference and walk_scale_reference < walk_scale_fast):
        _fail("walk animation playback is not synchronized to movement speed: slow=%.3f ref=%.3f fast=%.3f" % [walk_scale_slow, walk_scale_reference, walk_scale_fast])
        return

    # Near the run threshold, remain walking until the enter threshold is crossed.
    actor.velocity = Vector3(5.0, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != walk_name:
        _fail("walk/run boundary chatters before run enter threshold")
        return

    actor.velocity = Vector3(5.4, 0.0, 0.0)
    runtime.update_from_speed()
    var run_name := runtime.current_animation()
    if run_name != String(locomotion["run"]):
        _fail("running speed did not select run: %s" % run_name)
        return

    # Once running, small speed drops must not immediately flip back to walk.
    actor.velocity = Vector3(4.8, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != run_name:
        _fail("run/walk boundary has no hysteresis")
        return
    actor.velocity = Vector3(4.3, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != walk_name:
        _fail("run did not exit after crossing the lower hysteresis threshold")
        return

    # Walk/idle uses the same anti-chatter policy.
    actor.velocity = Vector3(0.30, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != walk_name:
        _fail("low walking speed should still select walk")
        return
    actor.velocity = Vector3(0.18, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != walk_name:
        _fail("walk/idle boundary has no hysteresis")
        return
    actor.velocity = Vector3(0.10, 0.0, 0.0)
    runtime.update_from_speed()
    if runtime.current_animation() != idle_name:
        _fail("idle did not engage after crossing the lower hysteresis threshold")
        return
    if absf(runtime.current_playback_speed_scale() - 1.0) > 0.001:
        _fail("idle playback speed must return to 1.0")
        return

    actor.velocity = Vector3(7.0, 0.0, 0.0)
    runtime.update_from_speed()
    run_name = runtime.current_animation()
    if run_name != String(locomotion["run"]):
        _fail("running speed did not reselect run: %s" % run_name)
        return
    var player := runtime.bound_animation_player()
    if player == null or player.current_animation != run_name or not player.is_playing():
        _fail("resolved running animation was not actually played")
        return

    # The authored mesh must visually face travel direction without rotating the gameplay body.
    if not runtime.has_method("current_visual_facing_offset_radians"):
        _fail("authored locomotion has no movement-facing visual contract")
        return
    var gameplay_yaw_before := actor.rotation.y
    actor.velocity = Vector3(3.0, 0.0, 0.0)
    for _step in range(8):
        runtime.update_from_speed(0.10)
    var strafe_offset := float(runtime.call("current_visual_facing_offset_radians"))
    if absf(strafe_offset) < deg_to_rad(70.0):
        _fail("authored mesh still faces forward while strafing: offset=%.2f deg" % rad_to_deg(strafe_offset))
        return
    if absf(actor.rotation.y - gameplay_yaw_before) > 0.0001:
        _fail("visual movement-facing changed gameplay body yaw")
        return

    # Stopping after lateral/backward travel must preserve the last facing direction instead of visibly swivelling to body-forward while idle.
    actor.velocity = Vector3.ZERO
    for _step in range(8):
        runtime.update_from_speed(0.10)
    var idle_hold_offset := float(runtime.call("current_visual_facing_offset_radians"))
    if absf(angle_difference(idle_hold_offset, strafe_offset)) > deg_to_rad(5.0):
        _fail("authored mesh rotates back toward body-forward while idle after strafe: strafe=%.2f idle=%.2f deg" % [rad_to_deg(strafe_offset), rad_to_deg(idle_hold_offset)])
        return
    if runtime.current_animation() != idle_name:
        _fail("stopping after strafe did not select idle animation")
        return
    if absf(actor.rotation.y - gameplay_yaw_before) > 0.0001:
        _fail("idle facing retention changed gameplay body yaw")
        return

    actor.velocity = Vector3(0.0, 0.0, -3.0)
    for _step in range(8):
        runtime.update_from_speed(0.10)
    var forward_offset := float(runtime.call("current_visual_facing_offset_radians"))
    if absf(forward_offset) > deg_to_rad(8.0):
        _fail("authored mesh did not return to forward travel facing: offset=%.2f deg" % rad_to_deg(forward_offset))
        return

    print("AUTHORED_PLAYER_LOCOMOTION_OK idle=%s walk=%s run=%s walk_scale=%.3f/%.3f/%.3f run_scale=%.3f strafe_facing=%.1fdeg idle_hold=%.1fdeg" % [idle_name, walk_name, run_name, walk_scale_slow, walk_scale_reference, walk_scale_fast, runtime.current_playback_speed_scale(), rad_to_deg(strafe_offset), rad_to_deg(idle_hold_offset)])
    quit(0)
