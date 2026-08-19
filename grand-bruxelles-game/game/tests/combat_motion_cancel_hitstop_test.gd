extends SceneTree

const DODGE := preload("res://game/scripts/player_dodge_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_MOTION_CANCEL_HITSTOP_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var dodge_source := FileAccess.get_file_as_string("res://game/scripts/player_dodge_runtime.gd")
    var controller_source := FileAccess.get_file_as_string("res://game/scripts/player_controller.gd")
    var melee_source := FileAccess.get_file_as_string("res://game/scripts/player_melee_combat_hardened_runtime.gd")
    var pose_source := FileAccess.get_file_as_string("res://game/scripts/combat_authored_pose_runtime.gd")
    if dodge_source.is_empty() or controller_source.is_empty() or melee_source.is_empty() or pose_source.is_empty():
        _fail("combat motion source fixture missing")
        return

    if dodge_source.find("key_event.keycode != KEY_Q") >= 0:
        _fail("Belgian AZERTY Q is player-left and must not also trigger dodge")
        return
    if dodge_source.find("move_and_collide(direction * DODGE_DISTANCE_M)") >= 0:
        _fail("dodge still teleports its full distance in a single physics call")
        return

    var world := Node3D.new()
    world.name = "CombatMotionRedWorld"
    root.add_child(world)
    var player := CharacterBody3D.new()
    player.name = "Player"
    world.add_child(player)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.40
    capsule.height = 1.80
    shape.shape = capsule
    shape.position.y = 0.90
    player.add_child(shape)

    var dodge := DODGE.new()
    world.add_child(dodge)
    await process_frame
    var before := player.global_position
    var result_variant: Variant = dodge.call("request_dodge", player, Vector3.RIGHT)
    if not result_variant is Dictionary:
        world.queue_free()
        _fail("dodge request did not return a Dictionary")
        return
    var result := result_variant as Dictionary
    if not bool(result.get("dodged", false)):
        world.queue_free()
        _fail("clear-space dodge request was unexpectedly rejected")
        return
    if player.global_position.distance_to(before) > 0.02:
        world.queue_free()
        _fail("dodge moved the body immediately instead of scheduling time-based motion")
        return
    if int(player.get_meta("combat_dodge_motion_until_ms", 0)) <= Time.get_ticks_msec():
        world.queue_free()
        _fail("dodge did not publish an active motion window for the player controller")
        return
    world.queue_free()
    await process_frame

    for token: String in [
        "combat_dodge_motion_until_ms",
        "combat_dodge_direction",
        "combat_attack_lunge_m",
        "combat_attack_input_scale",
    ]:
        if controller_source.find(token) < 0:
            _fail("player controller is missing physical combat motion token %s" % token)
            return

    for token: String in [
        "request_action_cancel",
        "combat_attack_cancel_ready_ms",
        "melee_hitstop_ms",
        "combat_hitstop_until_ms",
    ]:
        if melee_source.find(token) < 0:
            _fail("melee runtime is missing modern cancel/hit-stop token %s" % token)
            return

    if pose_source.find("request_hitstop") < 0:
        _fail("authored combat animation layer does not expose local hit-stop")
        return
    if pose_source.find("Engine.time_scale") >= 0:
        _fail("combat hit-stop must remain local and never freeze the whole world")
        return

    print("COMBAT_MOTION_CANCEL_HITSTOP_OK: azerty_conflict=green dodge_timeline=green physical_footwork=green late_cancel=green local_hitstop=green")
    quit(0)
