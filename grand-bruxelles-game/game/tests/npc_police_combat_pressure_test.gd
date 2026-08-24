extends SceneTree

const POLICE_COMBAT := preload("res://game/scripts/npc_police_combat_runtime.gd")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("POLICE_COMBAT_PRESSURE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var runtime := POLICE_COMBAT.new()
    runtime.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(runtime)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3.ZERO
    player.set_meta("combat_health", 100)
    root.add_child(player)

    var officer := NpcAgent.new()
    officer.name = "CombatOfficer"
    officer.role = NpcBehaviorModel.Role.POLICE
    officer.position = Vector3(0.0, 0.0, 10.0)
    root.add_child(officer)
    officer.set_spawn_context(NpcBehaviorModel.Role.POLICE, 17, officer.position)
    officer.report_police_incident(player.position, 1.0, 701)
    officer.update_police_threat(true, 1.0, 0.1)

    var ranged: Dictionary = runtime.combat_decision_for_test(officer, player, true)
    if StringName(ranged.get("action_name", &"")) != &"ranged_attack":
        _fail("10m visible pursuit must become ranged_attack, got %s" % ranged)
        return
    if float(ranged.get("pursuit_speed_mps", 0.0)) < 4.2:
        _fail("police pursuit is still jogging too slowly: %s" % ranged)
        return

    officer.position = Vector3(0.0, 0.0, 4.0)
    officer.police_response.incident_position = player.position
    var close: Dictionary = runtime.combat_decision_for_test(officer, player, true)
    if StringName(close.get("action_name", &"")) != &"tactical_reposition":
        _fail("4m pressure must reposition instead of standing still: %s" % close)
        return

    officer.position = Vector3(0.0, 0.0, 1.8)
    officer.police_response.incident_position = player.position
    var melee: Dictionary = runtime.combat_decision_for_test(officer, player, true)
    if StringName(melee.get("action_name", &"")) != &"melee_attack":
        _fail("1.8m pursuit must become melee_attack: %s" % melee)
        return

    var before_health := int(player.get_meta("combat_health", 100))
    var dealt := runtime.apply_attack_for_test(officer, player, &"melee_attack")
    var after_health := int(player.get_meta("combat_health", 100))
    if dealt <= 0 or after_health >= before_health:
        _fail("police attack did not damage player: dealt=%d health=%d->%d" % [dealt, before_health, after_health])
        return
    if int(player.get_meta("combat_police_hit_count", 0)) < 1:
        _fail("player hit feedback contract was not published")
        return

    # A decision is not permission to hit forever. Revalidate physical range at
    # application time so fast player movement cannot produce impossible late hits.
    player.set_meta("combat_health", 100)
    var hit_count_before := int(player.get_meta("combat_police_hit_count", 0))
    officer.position = Vector3(0.0, 0.0, 3.0)
    var late_melee := runtime.apply_attack_for_test(officer, player, &"melee_attack")
    if late_melee != 0 or int(player.get_meta("combat_health", 100)) != 100:
        _fail("late melee hit landed outside melee range: damage=%d" % late_melee)
        return
    officer.position = Vector3(0.0, 0.0, 19.0)
    var late_ranged := runtime.apply_attack_for_test(officer, player, &"ranged_attack")
    if late_ranged != 0 or int(player.get_meta("combat_health", 100)) != 100:
        _fail("late ranged hit landed outside ranged range: damage=%d" % late_ranged)
        return
    if int(player.get_meta("combat_police_hit_count", 0)) != hit_count_before:
        _fail("rejected late attacks still published player hit feedback")
        return

    officer.position = Vector3(0.0, 0.0, 1.8)
    officer.set_meta("melee_hit_count", 1)
    officer.set_meta("combat_last_weapon_damage", 28.0)
    var reaction: Dictionary = runtime.register_police_hit_for_test(officer, player, 1000)
    if not bool(reaction.get("engaged", false)):
        _fail("struck police officer did not immediately engage")
        return
    if int(reaction.get("stagger_ms", 0)) < 120:
        _fail("police hit reaction has no readable stagger: %s" % reaction)
        return
    if float(reaction.get("impact_intensity", 0.0)) < 1.2:
        _fail("body hit impact remains too weak: %s" % reaction)
        return
    if officer.police_response.phase != NpcPoliceResponse.Phase.PURSUIT:
        _fail("struck police officer did not enter PURSUIT")
        return

    print("POLICE_COMBAT_PRESSURE_OK: ranged/melee/reposition pressure, fast pursuit, physical late-hit rejection, player damage and strong police hit reaction")
    quit(0)
