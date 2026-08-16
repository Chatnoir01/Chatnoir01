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
    if not _expect(float(front.get_meta("melee_health", 100.0)) < 100.0, "hit did not reduce NPC combat health"):
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

    print("PLAYER_MELEE_COMBAT_OK: forward_hit=true damage_applied=true reaction=%s behind_untouched=true" % reaction)
    world.queue_free()
    quit(0)
