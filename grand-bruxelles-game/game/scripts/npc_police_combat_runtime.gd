extends Node

const ACTION_REQUEST_SCRIPT := preload("res://game/scripts/npc_police_action_request.gd")

const POLICE_GROUPS: Array[StringName] = [&"police_officer", &"police_npc"]
const MIN_PURSUIT_SPEED_MPS := 4.6
const PURSUIT_SPEED_VARIATION_MPS := 0.48
const MELEE_DAMAGE := 13
const RANGED_DAMAGE := 8
const GUARDED_DAMAGE_FACTOR := 0.42
const MELEE_COOLDOWN_MS := 900
const RANGED_COOLDOWN_MS := 760
const HIT_STAGGER_MS := 170
const POLICE_HIT_IMPACT_INTENSITY := 1.45
const PLAYER_HIT_IMPACT_INTENSITY := 1.30
const COMBAT_INCIDENT_BASE := 910000

var _action_request := ACTION_REQUEST_SCRIPT.new()
var _states: Dictionary = {}
var _feedback_label: Label
var _feedback_hide_ms := 0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
    if _feedback_label != null and Time.get_ticks_msec() >= _feedback_hide_ms:
        _feedback_label.visible = false

    var player := _current_player()
    if player == null:
        return

    var seen: Dictionary = {}
    var now := Time.get_ticks_msec()
    for group_name: StringName in POLICE_GROUPS:
        for node: Node in get_tree().get_nodes_in_group(group_name):
            if not node is NpcAgent:
                continue
            var officer := node as NpcAgent
            if officer.role != NpcBehaviorModel.Role.POLICE:
                continue
            var instance_id := officer.get_instance_id()
            if seen.has(instance_id):
                continue
            seen[instance_id] = true
            _tick_officer(officer, player, delta, now)
    _prune_states(seen)


func combat_decision_for_test(officer: NpcAgent, player: CharacterBody3D, line_of_sight: bool) -> Dictionary:
    if officer == null or player == null:
        return {"action_name": &"none", "pursuit_speed_mps": 0.0, "distance_m": INF}
    officer.police_response.incident_position = player.global_position
    var request: Dictionary = _action_request.build(
        officer.police_response,
        officer.global_position,
        line_of_sight and officer.police_response.phase == NpcPoliceResponse.Phase.PURSUIT
    )
    request["pursuit_speed_mps"] = pursuit_speed_for(officer)
    return request


func apply_attack_for_test(officer: NpcAgent, player: CharacterBody3D, action_name: StringName) -> int:
    if not _attack_still_valid(officer, player, action_name):
        return 0
    return _apply_player_damage(officer, player, action_name, false)


func register_police_hit_for_test(officer: NpcAgent, player: CharacterBody3D, now_ms: int) -> Dictionary:
    return _register_police_hit(officer, player, now_ms, false)


func pursuit_speed_for(officer: NpcAgent) -> float:
    if officer == null:
        return MIN_PURSUIT_SPEED_MPS
    var bucket := posmod(officer.variation_seed * 37 + 11, 7)
    return MIN_PURSUIT_SPEED_MPS + float(bucket) / 6.0 * PURSUIT_SPEED_VARIATION_MPS


func _tick_officer(officer: NpcAgent, player: CharacterBody3D, _delta: float, now: int) -> void:
    if officer == null or not is_instance_valid(officer):
        return
    var state := _state_for(officer)

    if not officer.active or bool(officer.get_meta("melee_knocked_out", false)):
        _restore_patrol_state(officer, state)
        return

    var hit_count := int(officer.get_meta("melee_hit_count", 0))
    if hit_count > int(state.get("last_hit_count", 0)):
        state["last_hit_count"] = hit_count
        _states[officer.get_instance_id()] = state
        _register_police_hit(officer, player, now, true)
        state = _state_for(officer)

    if officer.police_response.phase != NpcPoliceResponse.Phase.PURSUIT:
        _restore_patrol_state(officer, state)
        return

    officer.police_response.incident_position = player.global_position
    officer.behavior.target_position = player.global_position
    officer.behavior.state = NpcBehaviorModel.State.PURSUING
    officer.behavior.alert_level = 100.0
    officer.behavior.preferred_speed = pursuit_speed_for(officer)

    if now < int(state.get("stagger_until_ms", 0)):
        officer.movement_held = true
        officer.velocity.x = move_toward(officer.velocity.x, 0.0, officer.acceleration * 0.016)
        officer.velocity.z = move_toward(officer.velocity.z, 0.0, officer.acceleration * 0.016)
        officer.set_meta("police_combat_action", &"stagger")
        officer.set_meta("police_combat_visual_state", &"hurt")
        return

    var has_los := _has_line_of_sight(officer, player)
    var decision := combat_decision_for_test(officer, player, has_los)
    var action_name := StringName(decision.get("action_name", &"none"))
    officer.set_meta("police_combat_action", action_name)
    officer.set_meta("police_combat_distance_m", float(decision.get("distance_m", 0.0)))
    officer.set_meta("police_combat_has_los", has_los)
    officer.set_meta("police_combat_pressure_active", true)

    match action_name:
        &"melee_attack":
            _face_player(officer, player)
            officer.movement_held = true
            officer.set_meta("police_combat_visual_state", &"melee")
            if now >= int(state.get("next_attack_ms", 0)) and not bool(officer.get_meta("melee_hurt_feedback", false)):
                _perform_attack(officer, player, &"melee_attack", now)
        &"tactical_reposition":
            officer.movement_held = false
            officer.set_meta("police_combat_visual_state", &"chase")
            officer.behavior.set_destination(_reposition_target(officer, player, now))
        &"ranged_attack":
            _face_player(officer, player)
            officer.movement_held = true
            officer.set_meta("police_combat_visual_state", &"ranged")
            if now >= int(state.get("next_attack_ms", 0)):
                _perform_attack(officer, player, &"ranged_attack", now)
        &"foot_pursuit", &"request_vehicle_support":
            officer.movement_held = false
            officer.set_meta("police_combat_visual_state", &"chase")
            officer.behavior.set_destination(player.global_position)
        _:
            officer.movement_held = false
            officer.set_meta("police_combat_visual_state", &"")


func _perform_attack(officer: NpcAgent, player: CharacterBody3D, action_name: StringName, now: int) -> void:
    if not _attack_still_valid(officer, player, action_name):
        officer.set_meta("police_combat_last_attack_rejected", action_name)
        officer.set_meta("police_combat_last_attack_rejected_ms", now)
        return
    var dealt := _apply_player_damage(officer, player, action_name, true)
    var state := _state_for(officer)
    if action_name == &"melee_attack":
        state["next_attack_ms"] = now + MELEE_COOLDOWN_MS
        _animate_police_recoil(officer, true)
    else:
        var cadence_variation := posmod(officer.variation_seed * 13 + int(officer.get_meta("police_combat_attack_count", 0)) * 17, 140)
        state["next_attack_ms"] = now + RANGED_COOLDOWN_MS + cadence_variation
        _spawn_ranged_feedback(officer, player)
        _animate_police_recoil(officer, false)
    _states[officer.get_instance_id()] = state
    officer.set_meta("police_combat_last_attack", action_name)
    officer.set_meta("police_combat_last_attack_ms", now)
    officer.set_meta("police_combat_last_damage", dealt)
    officer.set_meta("police_combat_attack_count", int(officer.get_meta("police_combat_attack_count", 0)) + 1)


func _attack_still_valid(officer: NpcAgent, player: CharacterBody3D, action_name: StringName) -> bool:
    if officer == null or player == null or not is_instance_valid(officer) or not is_instance_valid(player):
        return false
    if bool(player.get_meta("combat_player_down", false)):
        return false
    var distance_m := officer.global_position.distance_to(player.global_position)
    match action_name:
        &"melee_attack":
            return distance_m <= float(ACTION_REQUEST_SCRIPT.MELEE_ATTACK_DISTANCE_M) and _has_line_of_sight(officer, player)
        &"ranged_attack":
            return distance_m <= float(ACTION_REQUEST_SCRIPT.RANGED_ATTACK_DISTANCE_M) and _has_line_of_sight(officer, player)
        _:
            return false


func _apply_player_damage(officer: NpcAgent, player: CharacterBody3D, action_name: StringName, spawn_feedback: bool) -> int:
    if officer == null or player == null or bool(player.get_meta("combat_player_down", false)):
        return 0
    if action_name != &"melee_attack" and action_name != &"ranged_attack":
        return 0
    var damage := MELEE_DAMAGE if action_name == &"melee_attack" else RANGED_DAMAGE
    if _player_is_guarding(player):
        damage = maxi(1, int(round(float(damage) * GUARDED_DAMAGE_FACTOR)))
    var health := maxi(0, int(player.get_meta("combat_health", 100)) - damage)
    player.set_meta("combat_health", health)
    player.set_meta("combat_police_hit_count", int(player.get_meta("combat_police_hit_count", 0)) + 1)
    player.set_meta("combat_last_police_damage", damage)
    player.set_meta("combat_last_police_attacker_id", officer.get_instance_id())
    player.set_meta("combat_last_police_attack", action_name)
    player.set_meta("combat_last_police_hit_ms", Time.get_ticks_msec())
    player.set_meta("combat_hit_flash_until_ms", Time.get_ticks_msec() + 130)
    if health <= 0:
        player.set_meta("combat_player_down", true)
        player.velocity = Vector3.ZERO
    if spawn_feedback:
        _spawn_player_hit_feedback(officer, player, action_name, damage, health)
    return damage


func _register_police_hit(officer: NpcAgent, player: CharacterBody3D, now_ms: int, spawn_feedback: bool) -> Dictionary:
    if officer == null or player == null:
        return {"engaged": false, "stagger_ms": 0, "impact_intensity": 0.0}
    var incident_id := COMBAT_INCIDENT_BASE + posmod(officer.get_instance_id(), 80000)
    officer.report_police_incident(player.global_position, 1.0, incident_id)
    officer.update_police_threat(true, 1.0, 0.0)
    officer.police_response.incident_position = player.global_position
    officer.behavior.target_position = player.global_position
    officer.movement_held = true
    var state := _state_for(officer)
    state["stagger_until_ms"] = now_ms + HIT_STAGGER_MS
    state["next_attack_ms"] = maxi(int(state.get("next_attack_ms", 0)), now_ms + HIT_STAGGER_MS + 120)
    state["last_hit_count"] = int(officer.get_meta("melee_hit_count", 0))
    _states[officer.get_instance_id()] = state
    officer.set_meta("police_combat_stagger_until_ms", now_ms + HIT_STAGGER_MS)
    officer.set_meta("police_combat_hit_reaction_intensity", POLICE_HIT_IMPACT_INTENSITY)
    officer.set_meta("police_combat_pressure_active", true)
    officer.set_meta("police_combat_visual_state", &"hurt")
    if spawn_feedback:
        _spawn_police_hit_feedback(officer, player)
    return {
        "engaged": officer.police_response.phase == NpcPoliceResponse.Phase.PURSUIT,
        "stagger_ms": HIT_STAGGER_MS,
        "impact_intensity": POLICE_HIT_IMPACT_INTENSITY,
        "pursuit_speed_mps": pursuit_speed_for(officer),
    }


func _state_for(officer: NpcAgent) -> Dictionary:
    var instance_id := officer.get_instance_id()
    if not _states.has(instance_id):
        _states[instance_id] = {
            "base_speed": officer.behavior.preferred_speed,
            "last_hit_count": 0,
            "next_attack_ms": 0,
            "stagger_until_ms": 0,
        }
    return _states[instance_id] as Dictionary


func _restore_patrol_state(officer: NpcAgent, state: Dictionary) -> void:
    if bool(officer.get_meta("police_combat_pressure_active", false)):
        officer.behavior.preferred_speed = float(state.get("base_speed", officer.behavior.preferred_speed))
        officer.movement_held = false
        officer.set_meta("police_combat_pressure_active", false)
        officer.set_meta("police_combat_action", &"none")
        officer.set_meta("police_combat_visual_state", &"")


func _reposition_target(officer: NpcAgent, player: CharacterBody3D, now: int) -> Vector3:
    var away := officer.global_position - player.global_position
    away.y = 0.0
    if away.length_squared() < 0.001:
        away = Vector3.FORWARD
    away = away.normalized()
    var lateral := Vector3(-away.z, 0.0, away.x)
    var sign := -1.0 if posmod(officer.variation_seed, 2) == 0 else 1.0
    var pulse := 1.0 + float(posmod(now / 500, 3)) * 0.18
    return player.global_position + away * 6.5 + lateral * sign * (2.1 * pulse)


func _face_player(officer: NpcAgent, player: CharacterBody3D) -> void:
    var offset := player.global_position - officer.global_position
    offset.y = 0.0
    if offset.length_squared() <= 0.001:
        return
    officer.rotation.y = atan2(-offset.x, -offset.z)


func _has_line_of_sight(officer: NpcAgent, player: CharacterBody3D) -> bool:
    if not officer.is_inside_tree() or not player.is_inside_tree():
        return true
    var origin := officer.global_position + Vector3.UP * 1.45
    var target := player.global_position + Vector3.UP * 1.05
    var query := PhysicsRayQueryParameters3D.create(origin, target)
    query.collision_mask = 0xFFFFFFFF
    query.collide_with_bodies = true
    query.collide_with_areas = true
    query.exclude = [officer.get_rid()]
    var hit := officer.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return true
    var collider: Variant = hit.get("collider")
    if collider == player:
        return true
    if collider is Node and player.is_ancestor_of(collider as Node):
        return true
    return false


func _player_is_guarding(player: CharacterBody3D) -> bool:
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime != null and melee_runtime.has_method("is_guarding"):
        return bool(melee_runtime.call("is_guarding", player))
    return bool(player.get_meta("combat_guarding", false))


func _spawn_ranged_feedback(officer: NpcAgent, player: CharacterBody3D) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        scene = officer.get_parent()
    if scene == null:
        return
    var origin := officer.global_position + Vector3.UP * 1.42 - officer.global_transform.basis.z.normalized() * 0.28 + officer.global_transform.basis.x.normalized() * 0.20
    var target := player.global_position + Vector3.UP * 1.02
    var delta := target - origin
    var distance := delta.length()
    if distance <= 0.05:
        return

    var tracer := MeshInstance3D.new()
    tracer.name = "PoliceCombatTracer"
    var tracer_mesh := BoxMesh.new()
    tracer_mesh.size = Vector3(0.025, 0.025, distance)
    var tracer_material := StandardMaterial3D.new()
    tracer_material.albedo_color = Color(1.0, 0.72, 0.22, 1.0)
    tracer_material.emission_enabled = true
    tracer_material.emission = Color(1.0, 0.30, 0.04, 1.0)
    tracer_material.emission_energy_multiplier = 3.0
    tracer_mesh.material = tracer_material
    tracer.mesh = tracer_mesh
    scene.add_child(tracer)
    tracer.global_position = origin.lerp(target, 0.5)
    tracer.look_at(target, Vector3.UP)
    var tracer_tween := create_tween()
    tracer_tween.tween_interval(0.055)
    tracer_tween.tween_callback(tracer.queue_free)

    var flash := MeshInstance3D.new()
    flash.name = "PoliceMuzzleFlash"
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.07
    flash_mesh.height = 0.14
    flash_mesh.radial_segments = 8
    flash_mesh.rings = 4
    flash_mesh.material = tracer_material
    flash.mesh = flash_mesh
    scene.add_child(flash)
    flash.global_position = origin
    var flash_tween := create_tween()
    flash_tween.tween_property(flash, "scale", Vector3(1.7, 1.7, 1.7), 0.035)
    flash_tween.tween_callback(flash.queue_free)


func _spawn_player_hit_feedback(officer: NpcAgent, player: CharacterBody3D, action_name: StringName, damage: int, health: int) -> void:
    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    if impact_runtime != null and impact_runtime.has_method("spawn_impact"):
        var normal := player.global_position - officer.global_position
        normal.y = 0.0
        if normal.length_squared() <= 0.001:
            normal = Vector3.BACK
        impact_runtime.call(
            "spawn_impact",
            player.global_position + Vector3.UP * 1.05,
            normal.normalized(),
            player,
            &"police_sidearm" if action_name == &"ranged_attack" else &"police_melee",
            PLAYER_HIT_IMPACT_INTENSITY,
            &"body"
        )
    var label := "POLICE  -%d   PV %d" % [damage, health]
    if health <= 0:
        label = "AU SOL"
    _show_feedback(label, 330 if health > 0 else 700)


func _spawn_police_hit_feedback(officer: NpcAgent, player: CharacterBody3D) -> void:
    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    if impact_runtime != null and impact_runtime.has_method("spawn_impact"):
        var normal := officer.global_position - player.global_position
        normal.y = 0.0
        if normal.length_squared() <= 0.001:
            normal = Vector3.FORWARD
        impact_runtime.call(
            "spawn_impact",
            officer.global_position + Vector3.UP * 1.30,
            normal.normalized(),
            officer,
            &"police_hit_reaction",
            POLICE_HIT_IMPACT_INTENSITY,
            &"body"
        )
    _animate_hit_stagger(officer, player)


func _animate_hit_stagger(officer: NpcAgent, player: CharacterBody3D) -> void:
    var visual := officer.get_node_or_null("BelgianPoliceVisual") as Node3D
    if visual == null:
        visual = officer.get_node_or_null("ProfiledNpcProxy") as Node3D
    if visual == null:
        visual = officer.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var local_attacker := officer.to_local(player.global_position)
    var sign := -1.0 if local_attacker.x >= 0.0 else 1.0
    var base_rotation := visual.rotation
    var base_position := visual.position
    var stagger_rotation := base_rotation
    stagger_rotation.z += deg_to_rad(12.0 * sign)
    stagger_rotation.x += deg_to_rad(5.0)
    var stagger_position := base_position + Vector3(0.05 * sign, -0.035, 0.04)
    var tween := create_tween()
    tween.tween_property(visual, "rotation", stagger_rotation, 0.055)
    tween.parallel().tween_property(visual, "position", stagger_position, 0.055)
    tween.tween_property(visual, "rotation", base_rotation, 0.14)
    tween.parallel().tween_property(visual, "position", base_position, 0.14)


func _animate_police_recoil(officer: NpcAgent, melee: bool) -> void:
    var visual := officer.get_node_or_null("BelgianPoliceVisual") as Node3D
    if visual == null:
        return
    var base_rotation := visual.rotation
    var kick := base_rotation
    kick.x += deg_to_rad(-8.0 if melee else 3.5)
    kick.z += deg_to_rad(5.0 if melee else -2.0)
    var tween := create_tween()
    tween.tween_property(visual, "rotation", kick, 0.055)
    tween.tween_property(visual, "rotation", base_rotation, 0.14)


func _show_feedback(text: String, duration_ms: int) -> void:
    if _feedback_label == null:
        var layer := CanvasLayer.new()
        layer.name = "PoliceCombatFeedbackLayer"
        add_child(layer)
        _feedback_label = Label.new()
        _feedback_label.name = "PoliceCombatFeedback"
        _feedback_label.position = Vector2(485.0, 292.0)
        _feedback_label.size = Vector2(310.0, 54.0)
        _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _feedback_label.add_theme_font_size_override("font_size", 26)
        layer.add_child(_feedback_label)
    _feedback_label.text = text
    _feedback_label.visible = true
    _feedback_hide_ms = Time.get_ticks_msec() + duration_ms


func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    var direct := scene.get_node_or_null("Player") as CharacterBody3D
    if direct != null:
        return direct
    return scene.find_child("Player", true, false) as CharacterBody3D


func _prune_states(seen: Dictionary) -> void:
    var stale: Array[int] = []
    for raw_id: Variant in _states.keys():
        var instance_id := int(raw_id)
        if not seen.has(instance_id):
            stale.append(instance_id)
    for instance_id: int in stale:
        _states.erase(instance_id)