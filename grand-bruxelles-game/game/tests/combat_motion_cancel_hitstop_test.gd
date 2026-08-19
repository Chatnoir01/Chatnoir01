extends SceneTree

const DODGE := preload("res://game/scripts/player_dodge_runtime.gd")
const MELEE_V4 := preload("res://game/scripts/player_melee_combat_motion_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_MOTION_CANCEL_HITSTOP_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var dodge_source := FileAccess.get_file_as_string("res://game/scripts/player_dodge_runtime.gd")
    var controller_source := FileAccess.get_file_as_string("res://game/scripts/player_controller.gd")
    var melee_source := FileAccess.get_file_as_string("res://game/scripts/player_melee_combat_motion_runtime.gd")
    var pose_source := FileAccess.get_file_as_string("res://game/scripts/combat_authored_pose_runtime.gd")
    var project_source := FileAccess.get_file_as_string("res://project.godot")
    if dodge_source.is_empty() or controller_source.is_empty() or melee_source.is_empty() or pose_source.is_empty() or project_source.is_empty():
        _fail("combat motion source fixture missing")
        return

    if DODGE.DODGE_KEY == KEY_Q:
        _fail("Belgian AZERTY Q is player-left and must not also trigger dodge")
        return
    if DODGE.DODGE_KEY != KEY_X:
        _fail("V4 dodge key drifted from the AZERTY-safe X binding")
        return
    if controller_source.find("Input.is_key_pressed(KEY_Q)") < 0:
        _fail("player controller no longer preserves Q as AZERTY left movement")
        return
    if DODGE.DODGE_DURATION_MS < 180 or DODGE.DODGE_DURATION_MS > 280:
        _fail("dodge motion duration escaped responsive temporal bounds")
        return
    var dodge_speed := DODGE.dodge_speed_mps()
    if dodge_speed < 5.0 or dodge_speed > 11.0:
        _fail("dodge speed escaped human-readable gameplay bounds")
        return
    if dodge_source.find("move_and_collide(direction * DODGE_DISTANCE_M)") >= 0:
        _fail("dodge still teleports its full distance in a single physics call")
        return

    var world := Node3D.new()
    world.name = "CombatMotionV4World"
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
        _fail("dodge did not publish an active time-based motion window")
        return

    dodge.call("_tick_dodge_motion", player, 1.0 / 60.0)
    var first_step := player.global_position.distance_to(before)
    if first_step <= 0.02 or first_step >= DODGE.DODGE_DISTANCE_M * 0.40:
        world.queue_free()
        _fail("first dodge physics tick must move a bounded fraction of the full dodge distance")
        return
    if not bool(player.get_meta("combat_dodge_motion_active", false)):
        world.queue_free()
        _fail("dodge motion ended after a single incremental physics tick")
        return
    world.queue_free()
    await process_frame

    for token: String in [
        "_tick_dodge_motion",
        "_tick_attack_footwork",
        "combat_attack_lunge_m",
        "combat_attack_footwork_travelled_m",
        "combat_attack_input_scale",
    ]:
        if dodge_source.find(token) < 0:
            _fail("physical combat motion runtime is missing token %s" % token)
            return

    var windup_scale := MELEE_V4.combat_attack_input_scale(&"windup")
    var active_scale := MELEE_V4.combat_attack_input_scale(&"active")
    var recovery_scale := MELEE_V4.combat_attack_input_scale(&"recovery")
    if active_scale <= 0.0 or active_scale >= windup_scale or windup_scale >= recovery_scale or recovery_scale >= 1.0:
        _fail("attack mobility scaling must commit hardest during active contact and recover progressively")
        return

    var dodge_hit_cancel := MELEE_V4.cancel_recovery_fraction(&"dodge", true)
    var dodge_whiff_cancel := MELEE_V4.cancel_recovery_fraction(&"dodge", false)
    var guard_hit_cancel := MELEE_V4.cancel_recovery_fraction(&"guard", true)
    var guard_whiff_cancel := MELEE_V4.cancel_recovery_fraction(&"guard", false)
    if dodge_hit_cancel < 0.25 or dodge_hit_cancel > 0.50 or dodge_whiff_cancel <= dodge_hit_cancel or dodge_whiff_cancel > 0.70:
        _fail("dodge cancel window must reward landed attacks without making whiffs free")
        return
    if guard_hit_cancel <= dodge_hit_cancel or guard_whiff_cancel <= guard_hit_cancel or guard_whiff_cancel > 0.80:
        _fail("guard cancel must remain later than dodge cancel and punish whiffs")
        return

    var hitstop_values: Array[int] = [
        MELEE_V4.melee_hitstop_ms(&"jab_left"),
        MELEE_V4.melee_hitstop_ms(&"cross_right"),
        MELEE_V4.melee_hitstop_ms(&"hook_left"),
        MELEE_V4.melee_hitstop_ms(&"front_kick_right"),
    ]
    for value: int in hitstop_values:
        if value < 30 or value > 70:
            _fail("local hit-stop escaped subtle modern combat bounds")
            return
    if hitstop_values[0] >= hitstop_values[1] or hitstop_values[1] >= hitstop_values[2] or hitstop_values[2] >= hitstop_values[3]:
        _fail("heavier strikes must receive progressively stronger local hit-stop")
        return

    for token: String in [
        "request_action_cancel",
        "combat_attack_cancel_ready_ms",
        "combat_attack_dodge_cancel_ready_ms",
        "combat_attack_guard_cancel_ready_ms",
        "melee_hitstop_ms",
        "combat_hitstop_until_ms",
        "combat_attack_lunge_m",
    ]:
        if melee_source.find(token) < 0:
            _fail("V4 melee runtime is missing modern cancel/hit-stop token %s" % token)
            return

    if pose_source.find("request_hitstop") < 0 or pose_source.find("speed_scale = 0.0") < 0:
        _fail("authored combat animation layer does not expose local animation hit-stop")
        return
    if pose_source.find("Engine.time_scale") >= 0:
        _fail("combat hit-stop must remain local and never freeze the whole world")
        return
    if project_source.find("PlayerMeleeCombatRuntime=\"*res://game/scripts/player_melee_combat_motion_runtime.gd\"") < 0:
        _fail("project is not running the V4 melee feel runtime")
        return

    print("COMBAT_MOTION_CANCEL_HITSTOP_OK: azerty_conflict=green dodge_key=X dodge_ms=%d dodge_speed=%.2f incremental_step=%.3f physical_footwork=green late_cancel=green hitstop=[%s] local_only=green" % [DODGE.DODGE_DURATION_MS, dodge_speed, first_step, hitstop_values])
    quit(0)
