extends SceneTree

const COMBAT_SCRIPT := preload("res://game/scripts/player_melee_combat_runtime.gd")
const NPC_SCRIPT := preload("res://game/scripts/npc_agent.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_MELEE_COMBAT_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _npc_at(world: Node3D, position: Vector3, seed: int) -> CharacterBody3D:
    var npc := NPC_SCRIPT.new() as CharacterBody3D
    npc.name = "CombatNpc_%d" % seed
    npc.position = position
    world.add_child(npc)
    npc.call("set_spawn_context", NpcBehaviorModel.Role.CIVILIAN, seed, position)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.75
    shape.shape = capsule
    shape.position.y = 0.88
    npc.add_child(shape)
    return npc

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3.ZERO
    player.rotation.y = 0.0
    world.add_child(player)
    var player_shape := CollisionShape3D.new()
    var player_capsule := CapsuleShape3D.new()
    player_capsule.radius = 0.40
    player_capsule.height = 1.80
    player_shape.shape = player_capsule
    player_shape.position.y = 0.90
    player.add_child(player_shape)

    var front := _npc_at(world, Vector3(0.0, 0.0, -1.45), 17)
    var behind := _npc_at(world, Vector3(0.0, 0.0, 1.45), 23)

    var combat := COMBAT_SCRIPT.new()
    world.add_child(combat)
    await physics_frame
    await physics_frame

    var result: Dictionary = combat.call("perform_attack", player)
    if not _expect(bool(result.get("hit", false)), "forward melee swing did not hit the NPC inside the attack volume"):
        return
    if not _expect(result.get("target") == front, "attack selected a target outside the forward hitbox"):
        return
    if not _expect(is_equal_approx(float(front.get_meta("melee_health", 100.0)), 66.0), "first hit did not apply exactly 34 damage"):
        return
    if not _expect(is_equal_approx(float(behind.get_meta("melee_health", 100.0)), 100.0), "NPC behind the player was hit"):
        return
    var reaction := StringName(result.get("reaction", &""))
    if not _expect(reaction in [&"defend", &"fight", &"flee"], "NPC did not resolve a readable defend/fight/flee reaction"):
        return
    if not _expect(int(front.get_meta("melee_hit_count", 0)) == 1, "NPC melee hit accounting drifted"):
        return
    if not _expect(bool(front.get_meta("melee_hurt_feedback", false)), "NPC hurt feedback marker was not raised"):
        return
    if not _expect(int(player.get_meta("combat_health", 0)) == 100, "player combat health was not initialized"):
        return

    combat.call("set_guarding", player, true)
    if not _expect(bool(player.get_meta("combat_guarding", false)), "guard input did not set player guarding state"):
        return
    var blocked_damage := int(combat.call("resolve_counter_hit", player))
    if not _expect(blocked_damage == 2 and int(player.get_meta("combat_health", 0)) == 98, "guard did not reduce counter-hit damage from 8 to 2"):
        return
    var blocked_attack: Dictionary = combat.call("request_attack", player)
    if not _expect(String(blocked_attack.get("reason", "")) == "guarding", "player could attack while guard was held"):
        return

    combat.call("set_guarding", player, false)
    var open_damage := int(combat.call("resolve_counter_hit", player))
    if not _expect(open_damage == 8 and int(player.get_meta("combat_health", 0)) == 90, "unguarded counter-hit did not apply full damage"):
        return

    var second: Dictionary = combat.call("perform_attack", player)
    var third: Dictionary = combat.call("perform_attack", player)
    if not _expect(bool(second.get("hit", false)) and bool(third.get("hit", false)), "follow-up strikes did not land"):
        return
    if not _expect(StringName(third.get("reaction", &"")) == &"ko", "third 34-damage strike did not resolve a readable KO"):
        return
    if not _expect(is_equal_approx(float(front.get_meta("melee_health", 1.0)), 0.0), "KO target health did not clamp to zero"):
        return
    if not _expect(bool(front.get_meta("melee_knocked_out", false)), "KO target was not marked knocked out"):
        return
    if not _expect(not bool(front.get("active")), "KO target remained active in simulation"):
        return
    if not _expect(front.velocity.is_zero_approx(), "KO target retained movement velocity"):
        return
    if not _expect(int(front.get_meta("melee_hit_count", 0)) == 3, "KO hit accounting drifted"):
        return
    if not _expect(is_equal_approx(float(behind.get_meta("melee_health", 100.0)), 100.0), "rear NPC was affected during KO sequence"):
        return

    print("PLAYER_MELEE_COMBAT_OK: forward_hit=true guard_damage=2 open_damage=8 ko_after_hits=3 rear_untouched=true")
    world.queue_free()
    quit(0)
