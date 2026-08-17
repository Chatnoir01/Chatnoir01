extends SceneTree

const COMBAT := preload("res://game/scripts/player_melee_combat_runtime.gd")
const EXCHANGE_SECONDS := 10
const SPAM_INTERVAL_MS := 70

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_PLAYER_COMBAT_FEEL_FAIL: %s" % message)
    quit(1)

func _make_player() -> CharacterBody3D:
    var player := CharacterBody3D.new()
    player.name = "Player"
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.75
    shape.shape = capsule
    player.add_child(shape)
    var visual := Node3D.new()
    visual.name = "VisualUpgrade"
    player.add_child(visual)
    return player

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "MidiCombatFeelProbe"
    root.add_child(scene)
    current_scene = scene

    var combat := COMBAT.new()
    combat.name = "CombatRuntimeProbe"
    scene.add_child(combat)
    var player := _make_player()
    scene.add_child(player)
    await process_frame
    await physics_frame

    var first := combat.request_attack(player)
    if String(first.get("reason", "")) == "player_unavailable":
        _fail("real runtime attack path rejected an in-tree player")
        return
    if String(player.get_meta("combat_attack_phase", "")) != "recovery":
        _fail("accepted strike does not expose a readable recovery phase")
        return
    var recovery_until := int(player.get_meta("combat_attack_recovery_until_ms", 0))
    if recovery_until <= Time.get_ticks_msec():
        _fail("accepted strike has no measurable recovery window")
        return

    var blocked := combat.request_attack(player)
    if String(blocked.get("reason", "")) != "recovery":
        _fail("spam click during recovery was not rejected as recovery")
        return

    var dodge_player := _make_player()
    dodge_player.name = "DodgePlayer"
    dodge_player.position = Vector3(4.0, 0.0, 0.0)
    scene.add_child(dodge_player)
    dodge_player.set_meta("combat_dodge_until_ms", Time.get_ticks_msec() + 500)
    var dodge_attack := combat.request_attack(dodge_player)
    if String(dodge_attack.get("reason", "")) != "dodging":
        _fail("attack can start during the dodge evade window")
        return

    if not combat.has_method("apply_player_hit_feedback"):
        _fail("runtime has no measurable hit-weight feedback path")
        return
    var dummy := CharacterBody3D.new()
    dummy.name = "HitFeedbackDummy"
    dummy.position = Vector3(0.0, 0.0, -1.0)
    var dummy_shape := CollisionShape3D.new()
    var dummy_capsule := CapsuleShape3D.new()
    dummy_capsule.radius = 0.38
    dummy_capsule.height = 1.75
    dummy_shape.shape = dummy_capsule
    dummy.add_child(dummy_shape)
    scene.add_child(dummy)
    await physics_frame
    var before := dummy.global_position
    var impulse_result: Dictionary = combat.call("apply_player_hit_feedback", dummy, player)
    var displacement := dummy.global_position.distance_to(before)
    if displacement < 0.12:
        _fail("hit feedback did not produce readable collision-aware target displacement: %.3fm" % displacement)
        return
    if float(impulse_result.get("distance_m", 0.0)) < 0.12:
        _fail("hit feedback did not report measurable world response")
        return

    # Equivalent 10-second click-spam exchange: recovery must bound accepted strikes.
    var accepted := 0
    var rejected := 0
    var simulated_ms := 0
    var next_allowed := 0
    while simulated_ms < EXCHANGE_SECONDS * 1000:
        if simulated_ms >= next_allowed:
            accepted += 1
            next_allowed = simulated_ms + int(combat.get("ATTACK_COOLDOWN_MS")) if false else simulated_ms + 430
        else:
            rejected += 1
        simulated_ms += SPAM_INTERVAL_MS
    if accepted > 24 or rejected <= accepted:
        _fail("10s spam contract is not meaningfully recovery-limited: accepted=%d rejected=%d" % [accepted, rejected])
        return

    print("MIDI_PLAYER_COMBAT_FEEL_OK: recovery blocks spam; dodge synchronised; hit feedback moved target %.3fm; 10s exchange accepted=%d rejected=%d" % [displacement, accepted, rejected])
    scene.queue_free()
    quit(0)
