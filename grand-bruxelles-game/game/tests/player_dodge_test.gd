extends SceneTree

const DODGE_SCRIPT := preload("res://game/scripts/player_dodge_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_DODGE_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3.ZERO
    world.add_child(player)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.40
    capsule.height = 1.80
    shape.shape = capsule
    shape.position.y = 0.90
    player.add_child(shape)

    var dodge := DODGE_SCRIPT.new()
    world.add_child(dodge)
    await physics_frame

    var start := player.global_position
    var result: Dictionary = dodge.call("request_dodge", player, Vector3.RIGHT)
    if not _expect(bool(result.get("dodged", false)), "dodge request did not execute"):
        return
    var travelled := player.global_position.distance_to(start)
    if not _expect(travelled >= 1.50 and travelled <= 1.70, "dodge travel escaped the bounded quick-step distance"):
        return
    if not _expect(int(player.get_meta("combat_dodge_count", 0)) == 1, "dodge count did not increment"):
        return
    if not _expect(int(player.get_meta("combat_dodge_until_ms", 0)) > Time.get_ticks_msec(), "dodge evade window was not armed"):
        return

    var enemy_position := Vector3(0.0, 0.0, -1.45)
    if not _expect(player.global_position.distance_to(enemy_position) > 2.05, "lateral dodge did not clear the existing NPC counter-hit reach"):
        return

    var repeat: Dictionary = dodge.call("request_dodge", player, Vector3.RIGHT)
    if not _expect(not bool(repeat.get("dodged", false)) and String(repeat.get("reason", "")) == "cooldown", "dodge cooldown did not reject immediate spam"):
        return

    player.set_meta("combat_guarding", true)
    player.set_meta("combat_next_dodge_ms", 0)
    var guarded: Dictionary = dodge.call("request_dodge", player, Vector3.RIGHT)
    if not _expect(not bool(guarded.get("dodged", false)) and String(guarded.get("reason", "")) == "guarding", "dodge ignored active guard state"):
        return

    print("PLAYER_DODGE_OK: distance=%.2f counter_reach_cleared=true cooldown=true guard_exclusive=true" % travelled)
    world.queue_free()
    quit(0)
