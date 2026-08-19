extends Node

# Grand Bruxelles combat/arsenal layer.
# Original game code: fictional weapon profiles only; no real-world weapon blueprint data.

const COMBO_RESET_MS := 900
const WORLD_REACTION_RADIUS_M := 24.0
const WORLD_REACTION_THROTTLE_MS := 320
const DEFAULT_FOV := 69.0
const AIM_FOV := 61.0

const MELEE_MOVES: Array[Dictionary] = [
    {
        "id": &"jab_left",
        "label": "DIRECT GAUCHE",
        "limb": "LeftArm",
        "windup_s": 0.055,
        "active_s": 0.085,
        "recover_s": 0.19,
        "yaw_deg": -11.0,
        "roll_deg": 3.0,
        "lunge_m": 0.08,
        "limb_x_deg": -78.0,
        "limb_z_deg": -4.0,
    },
    {
        "id": &"cross_right",
        "label": "DIRECT DROIT",
        "limb": "RightArm",
        "windup_s": 0.070,
        "active_s": 0.090,
        "recover_s": 0.20,
        "yaw_deg": 18.0,
        "roll_deg": -5.0,
        "lunge_m": 0.12,
        "limb_x_deg": -92.0,
        "limb_z_deg": 5.0,
    },
    {
        "id": &"hook_left",
        "label": "CROCHET GAUCHE",
        "limb": "LeftArm",
        "windup_s": 0.085,
        "active_s": 0.105,
        "recover_s": 0.22,
        "yaw_deg": -28.0,
        "roll_deg": 8.0,
        "lunge_m": 0.07,
        "limb_x_deg": -63.0,
        "limb_z_deg": -36.0,
    },
    {
        "id": &"front_kick_right",
        "label": "COUP DE PIED",
        "limb": "RightLeg",
        "windup_s": 0.095,
        "active_s": 0.115,
        "recover_s": 0.25,
        "yaw_deg": 8.0,
        "roll_deg": -2.0,
        "lunge_m": 0.16,
        "limb_x_deg": -58.0,
        "limb_z_deg": 0.0,
    },
]

# Values are tuned for readable game feel, not copied from or intended to model a real firearm.
const WEAPON_PROFILES: Dictionary = {
    &"bx9": {
        "label": "BX-9",
        "class": "compact",
        "mag_size": 12,
        "reserve": 48,
        "reload_ms": 1120,
        "fire_interval_ms": 190,
        "automatic": false,
        "pellets": 1,
        "damage": 27.0,
        "range_m": 62.0,
        "min_damage_factor": 0.58,
        "hip_spread_deg": 1.75,
        "aim_spread_deg": 0.72,
        "move_spread_deg": 0.85,
        "recoil_pitch_deg": 1.10,
        "recoil_yaw_deg": 0.32,
        "visual_scale": Vector3(0.78, 0.82, 0.66),
    },
    &"cbr4": {
        "label": "CBR-4",
        "class": "carbine",
        "mag_size": 24,
        "reserve": 96,
        "reload_ms": 1420,
        "fire_interval_ms": 92,
        "automatic": true,
        "pellets": 1,
        "damage": 20.0,
        "range_m": 94.0,
        "min_damage_factor": 0.52,
        "hip_spread_deg": 2.20,
        "aim_spread_deg": 0.62,
        "move_spread_deg": 1.05,
        "recoil_pitch_deg": 0.72,
        "recoil_yaw_deg": 0.42,
        "visual_scale": Vector3(0.92, 0.90, 1.22),
    },
    &"sct8": {
        "label": "SCT-8",
        "class": "scatter",
        "mag_size": 6,
        "reserve": 30,
        "reload_ms": 1680,
        "fire_interval_ms": 610,
        "automatic": false,
        "pellets": 7,
        "damage": 11.5,
        "range_m": 38.0,
        "min_damage_factor": 0.38,
        "hip_spread_deg": 4.60,
        "aim_spread_deg": 3.05,
        "move_spread_deg": 1.10,
        "recoil_pitch_deg": 2.80,
        "recoil_yaw_deg": 0.58,
        "visual_scale": Vector3(0.86, 0.88, 1.54),
    },
}

var _equipped_weapon: StringName = &""
var _ammo: Dictionary = {}
var _trigger_held := false
var _aiming := false
var _next_fire_ms := 0
var _reload_until_ms := 0
var _reload_weapon: StringName = &""
var _last_melee_ms := -100000
var _combo_index := 0
var _incident_serial := 0
var _next_world_reaction_ms := 0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _rng := RandomNumberGenerator.new()
var _hud_label: Label = null
var _crosshair: Label = null
var _weapon_visual: Node3D = null
var _weapon_visual_owner_id := 0

func _ready() -> void:
    _rng.randomize()
    _reset_ammo()
    set_process(true)
    set_process_input(true)

func _input(event: InputEvent) -> void:
    var player := _current_player()
    if player == null:
        return

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.echo:
            return
        if key_event.pressed:
            if key_event.keycode == KEY_1:
                equip_weapon(player, &"")
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_2:
                equip_weapon(player, &"bx9")
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_3:
                equip_weapon(player, &"cbr4")
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_4:
                equip_weapon(player, &"sct8")
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_R and is_armed():
                request_reload(player)
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_F and not is_armed():
                request_melee_combo(player)
                get_viewport().set_input_as_handled()
                return

    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT:
            if is_armed():
                _trigger_held = mouse_event.pressed
                if mouse_event.pressed:
                    request_fire(player)
                get_viewport().set_input_as_handled()
                return
            if mouse_event.pressed:
                request_melee_combo(player)
                get_viewport().set_input_as_handled()
                return
        if mouse_event.button_index == MOUSE_BUTTON_RIGHT and is_armed():
            _aiming = mouse_event.pressed
            player.set_meta("combat_weapon_aiming", _aiming)
            _refresh_hud(player)
            get_viewport().set_input_as_handled()
            return

func _process(delta: float) -> void:
    var player := _current_player()
    if player == null:
        return

    var now := Time.get_ticks_msec()
    if _reload_until_ms > 0 and now >= _reload_until_ms:
        _finish_reload(player)

    if is_armed() and _trigger_held:
        var profile := weapon_profile(_equipped_weapon)
        if bool(profile.get("automatic", false)):
            request_fire(player)

    _recoil_pitch = move_toward(_recoil_pitch, 0.0, delta * 7.6)
    _recoil_yaw = move_toward(_recoil_yaw, 0.0, delta * 8.8)
    var camera := _player_camera(player)
    if camera != null:
        camera.rotation.x = -deg_to_rad(_recoil_pitch)
        camera.rotation.y = deg_to_rad(_recoil_yaw)
        var target_fov := AIM_FOV if is_armed() and _aiming else DEFAULT_FOV
        camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 11.0, 0.0, 1.0))

func is_armed() -> bool:
    return _equipped_weapon != &"" and WEAPON_PROFILES.has(_equipped_weapon)

func equipped_weapon() -> StringName:
    return _equipped_weapon

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    if weapon_id != &"" and not WEAPON_PROFILES.has(weapon_id):
        return false
    _trigger_held = false
    _aiming = false
    _reload_until_ms = 0
    _reload_weapon = &""
    _equipped_weapon = weapon_id
    player.set_meta("combat_weapon_id", weapon_id)
    player.set_meta("combat_weapon_aiming", false)
    player.set_meta("combat_weapon_reloading", false)

    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime != null and melee_runtime.has_method("set_guarding"):
        melee_runtime.call("set_guarding", player, false)

    _rebuild_weapon_visual(player)
    _refresh_hud(player)
    if is_armed():
        _flash_status("%s EQUIPE" % String(weapon_profile(weapon_id).get("label", weapon_id)), 520)
    else:
        _flash_status("MAINS NUES", 420)
    return true

func request_melee_combo(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"hit": false, "reason": "player_unavailable"}
    if is_armed():
        return {"hit": false, "reason": "weapon_equipped"}
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime == null or not melee_runtime.has_method("request_attack"):
        return {"hit": false, "reason": "melee_runtime_unavailable"}

    var result_variant: Variant = melee_runtime.call("request_attack", player)
    if not result_variant is Dictionary:
        return {"hit": false, "reason": "invalid_melee_result"}
    var result := result_variant as Dictionary
    if not result.has("recovery_ms"):
        return result

    var now := Time.get_ticks_msec()
    if now - _last_melee_ms > COMBO_RESET_MS:
        _combo_index = 0
    var move := melee_move(_combo_index)
    _combo_index = (_combo_index + 1) % MELEE_MOVES.size()
    _last_melee_ms = now
    player.set_meta("combat_move_id", move.get("id", &""))
    player.set_meta("combat_move_label", move.get("label", ""))
    player.set_meta("combat_combo_step", _combo_index)
    _animate_melee_move(player, move)
    result["move_id"] = move.get("id", &"")
    result["move_label"] = move.get("label", "")
    return result

func request_fire(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"fired": false, "reason": "player_unavailable"}
    if not is_armed():
        return {"fired": false, "reason": "unarmed"}
    var now := Time.get_ticks_msec()
    if _reload_until_ms > now:
        return {"fired": false, "reason": "reloading"}
    if now < _next_fire_ms:
        return {"fired": false, "reason": "cadence"}

    var profile := weapon_profile(_equipped_weapon)
    var state := ammo_state(_equipped_weapon)
    var mag := int(state.get("mag", 0))
    if mag <= 0:
        if int(state.get("reserve", 0)) > 0:
            request_reload(player)
        else:
            _flash_status("PLUS DE MUNITIONS", 360)
        return {"fired": false, "reason": "empty"}

    state["mag"] = mag - 1
    _ammo[_equipped_weapon] = state
    _next_fire_ms = now + int(profile.get("fire_interval_ms", 200))
    player.set_meta("combat_weapon_last_shot_ms", now)
    player.set_meta("combat_weapon_shot_count", int(player.get_meta("combat_weapon_shot_count", 0)) + 1)

    var camera := _player_camera(player)
    if camera == null:
        return {"fired": false, "reason": "camera_unavailable"}

    var spread_deg := current_spread_deg(player, profile, _aiming)
    var pellet_count := maxi(1, int(profile.get("pellets", 1)))
    var target_hits: Dictionary = {}
    var environment_impact := Vector3.INF
    for pellet_index: int in range(pellet_count):
        var ray_result := _fire_ray(player, camera, float(profile.get("range_m", 60.0)), spread_deg)
        if ray_result.is_empty():
            continue
        var hit_position: Vector3 = ray_result.get("position", Vector3.INF)
        var npc := _npc_from_collider(ray_result.get("collider"))
        if npc != null:
            var instance_id := npc.get_instance_id()
            var entry: Dictionary = target_hits.get(instance_id, {
                "npc": npc,
                "pellets": 0,
                "distance_m": camera.global_position.distance_to(hit_position),
            })
            entry["pellets"] = int(entry.get("pellets", 0)) + 1
            entry["distance_m"] = minf(float(entry.get("distance_m", 9999.0)), camera.global_position.distance_to(hit_position))
            target_hits[instance_id] = entry
        elif environment_impact == Vector3.INF:
            environment_impact = hit_position

    var total_damage := 0.0
    var hit_count := 0
    for raw_entry: Variant in target_hits.values():
        var entry := raw_entry as Dictionary
        var npc: NpcAgent = entry.get("npc") as NpcAgent
        if npc == null:
            continue
        var distance_m := float(entry.get("distance_m", 0.0))
        var per_pellet := damage_at_distance(
            float(profile.get("damage", 20.0)),
            distance_m,
            float(profile.get("range_m", 60.0)),
            float(profile.get("min_damage_factor", 0.5))
        )
        var damage := per_pellet * float(int(entry.get("pellets", 1)))
        if _apply_weapon_hit(npc, player, damage):
            total_damage += damage
            hit_count += 1

    if environment_impact != Vector3.INF:
        _spawn_impact_marker(player, environment_impact)
    _apply_recoil(profile)
    _spawn_muzzle_flash(player)
    _notify_weapon_incident(player, now)
    _refresh_hud(player)
    if hit_count > 0:
        _flash_status("IMPACT  -%d" % int(round(total_damage)), 220)
    return {
        "fired": true,
        "weapon": _equipped_weapon,
        "targets_hit": hit_count,
        "damage": total_damage,
        "spread_deg": spread_deg,
        "ammo": int(state.get("mag", 0)),
    }

func request_reload(player: CharacterBody3D) -> bool:
    if not is_armed() or player == null:
        return false
    if _reload_until_ms > Time.get_ticks_msec():
        return false
    var profile := weapon_profile(_equipped_weapon)
    var state := ammo_state(_equipped_weapon)
    var mag_size := int(profile.get("mag_size", 0))
    if int(state.get("mag", 0)) >= mag_size or int(state.get("reserve", 0)) <= 0:
        return false
    _trigger_held = false
    _reload_weapon = _equipped_weapon
    _reload_until_ms = Time.get_ticks_msec() + int(profile.get("reload_ms", 1000))
    player.set_meta("combat_weapon_reloading", true)
    _flash_status("RECHARGEMENT...", 420)
    _refresh_hud(player)
    return true

func _finish_reload(player: CharacterBody3D) -> void:
    if _reload_weapon == &"" or not WEAPON_PROFILES.has(_reload_weapon):
        _reload_until_ms = 0
        return
    var profile := weapon_profile(_reload_weapon)
    var state := ammo_state(_reload_weapon)
    var mag_size := int(profile.get("mag_size", 0))
    var missing := maxi(0, mag_size - int(state.get("mag", 0)))
    var transfer := mini(missing, int(state.get("reserve", 0)))
    state["mag"] = int(state.get("mag", 0)) + transfer
    state["reserve"] = int(state.get("reserve", 0)) - transfer
    _ammo[_reload_weapon] = state
    _reload_until_ms = 0
    _reload_weapon = &""
    player.set_meta("combat_weapon_reloading", false)
    _flash_status("PRET", 180)
    _refresh_hud(player)

func _fire_ray(player: CharacterBody3D, camera: Camera3D, range_m: float, spread_deg: float) -> Dictionary:
    var direction := -camera.global_transform.basis.z.normalized()
    var spread := deg_to_rad(maxf(spread_deg, 0.0))
    if spread > 0.0:
        var yaw := _rng.randf_range(-spread, spread)
        var pitch := _rng.randf_range(-spread, spread)
        direction = direction.rotated(Vector3.UP, yaw)
        direction = direction.rotated(camera.global_transform.basis.x.normalized(), pitch)
        direction = direction.normalized()
    var origin := camera.global_position
    var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * maxf(range_m, 1.0))
    query.collision_mask = 0xFFFFFFFF
    query.collide_with_bodies = true
    query.collide_with_areas = true
    query.exclude = [player.get_rid()]
    return player.get_world_3d().direct_space_state.intersect_ray(query)

func _apply_weapon_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> bool:
    if npc == null or bool(npc.get_meta("melee_knocked_out", false)):
        return false
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime != null and melee_runtime.has_method("_apply_hit"):
        melee_runtime.call("_apply_hit", npc, player, maxf(damage, 0.0))
        npc.set_meta("combat_last_weapon_id", _equipped_weapon)
        npc.set_meta("combat_last_weapon_damage", damage)
        return true
    return false

func _notify_weapon_incident(player: CharacterBody3D, now: int) -> void:
    if now < _next_world_reaction_ms:
        return
    _next_world_reaction_ms = now + WORLD_REACTION_THROTTLE_MS
    _incident_serial += 1
    var scene := get_tree().current_scene
    if scene == null:
        return
    for node: Node in scene.find_children("*", "", true, false):
        if not node is NpcAgent:
            continue
        var npc := node as NpcAgent
        if npc.global_position.distance_to(player.global_position) > WORLD_REACTION_RADIUS_M:
            continue
        if npc.role == NpcBehaviorModel.Role.POLICE:
            npc.report_police_incident(player.global_position, 0.96, 100000 + _incident_serial)
            npc.update_police_threat(true, 0.96, 0.06)
        else:
            npc.apply_local_crowd_stimulus(player.global_position, 0.92, false)

func _animate_melee_move(player: CharacterBody3D, move: Dictionary) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var windup := float(move.get("windup_s", 0.07))
    var active := float(move.get("active_s", 0.09))
    var recover := float(move.get("recover_s", 0.20))
    var yaw := deg_to_rad(float(move.get("yaw_deg", 0.0)))
    var roll := deg_to_rad(float(move.get("roll_deg", 0.0)))
    var lunge := float(move.get("lunge_m", 0.08))
    var base_y := visual.rotation.y
    var base_z := visual.rotation.z
    var base_pos_z := visual.position.z

    var tween := create_tween()
    tween.tween_property(visual, "rotation:y", base_y - yaw * 0.28, windup)
    tween.parallel().tween_property(visual, "position:z", base_pos_z + lunge * 0.24, windup)
    tween.tween_property(visual, "rotation:y", base_y + yaw, active)
    tween.parallel().tween_property(visual, "rotation:z", base_z + roll, active)
    tween.parallel().tween_property(visual, "position:z", base_pos_z - lunge, active)
    tween.tween_property(visual, "rotation:y", base_y, recover)
    tween.parallel().tween_property(visual, "rotation:z", base_z, recover)
    tween.parallel().tween_property(visual, "position:z", base_pos_z, recover)

    var limb_name := String(move.get("limb", ""))
    var limb := visual.get_node_or_null(limb_name) as Node3D
    if limb != null:
        _animate_procedural_limb(limb, move, windup, active, recover)
    else:
        _play_authored_attack_if_available(visual, move)

func _animate_procedural_limb(limb: Node3D, move: Dictionary, windup: float, active: float, recover: float) -> void:
    var base_rotation := limb.rotation
    var strike_x := base_rotation.x + deg_to_rad(float(move.get("limb_x_deg", -75.0)))
    var strike_z := base_rotation.z + deg_to_rad(float(move.get("limb_z_deg", 0.0)))
    var tween := create_tween()
    tween.tween_property(limb, "rotation:x", base_rotation.x + 0.20, windup)
    tween.tween_property(limb, "rotation:x", strike_x, active)
    tween.parallel().tween_property(limb, "rotation:z", strike_z, active)
    tween.tween_property(limb, "rotation", base_rotation, recover)

func _play_authored_attack_if_available(visual: Node3D, move: Dictionary) -> void:
    var players := visual.find_children("*", "AnimationPlayer", true, false)
    if players.is_empty():
        return
    var animation_player := players[0] as AnimationPlayer
    if animation_player == null:
        return
    var preferred_tokens: Array[String] = ["attack", "punch", "fight", "kick"]
    if String(move.get("id", "")).contains("kick"):
        preferred_tokens = ["kick", "attack", "fight"]
    for library_name: StringName in animation_player.get_animation_library_list():
        var library := animation_player.get_animation_library(library_name)
        if library == null:
            continue
        for animation_name: StringName in library.get_animation_list():
            var lowered := String(animation_name).to_lower()
            for token: String in preferred_tokens:
                if lowered.contains(token):
                    var qualified := animation_name if library_name == &"" else StringName("%s/%s" % [String(library_name), String(animation_name)])
                    animation_player.play(qualified, 0.06, 1.08)
                    return

func _apply_recoil(profile: Dictionary) -> void:
    _recoil_pitch = minf(_recoil_pitch + float(profile.get("recoil_pitch_deg", 1.0)), 6.5)
    var yaw_amount := float(profile.get("recoil_yaw_deg", 0.25))
    _recoil_yaw = clampf(_recoil_yaw + _rng.randf_range(-yaw_amount, yaw_amount), -3.0, 3.0)
    if _weapon_visual != null and is_instance_valid(_weapon_visual):
        var base_z := _weapon_visual.position.z
        var tween := create_tween()
        tween.tween_property(_weapon_visual, "position:z", base_z + 0.08, 0.035)
        tween.tween_property(_weapon_visual, "position:z", base_z, 0.09)

func _rebuild_weapon_visual(player: CharacterBody3D) -> void:
    if _weapon_visual != null and is_instance_valid(_weapon_visual):
        _weapon_visual.queue_free()
    _weapon_visual = null
    _weapon_visual_owner_id = player.get_instance_id()
    if not is_armed():
        return

    var profile := weapon_profile(_equipped_weapon)
    var holder := Node3D.new()
    holder.name = "CombatWeaponVisual"
    holder.position = Vector3(0.31, 1.34, -0.28)
    holder.rotation_degrees = Vector3(-5.0, 0.0, -4.0)
    holder.scale = profile.get("visual_scale", Vector3.ONE)
    player.add_child(holder)
    _weapon_visual = holder

    var dark := StandardMaterial3D.new()
    dark.albedo_color = Color(0.055, 0.062, 0.070, 1.0)
    dark.metallic = 0.34
    dark.roughness = 0.38
    var grip_material := StandardMaterial3D.new()
    grip_material.albedo_color = Color(0.11, 0.105, 0.095, 1.0)
    grip_material.roughness = 0.72

    var weapon_class := String(profile.get("class", "compact"))
    var body_length := 0.42
    if weapon_class == "carbine":
        body_length = 0.72
    elif weapon_class == "scatter":
        body_length = 0.88
    _add_weapon_box(holder, "Receiver", Vector3(0.18, 0.16, body_length), Vector3(0.0, 0.0, -body_length * 0.38), dark)
    _add_weapon_box(holder, "Grip", Vector3(0.12, 0.29, 0.15), Vector3(0.0, -0.18, -0.05), grip_material, Vector3(-13.0, 0.0, 0.0))
    _add_weapon_box(holder, "TopRail", Vector3(0.10, 0.055, body_length * 0.58), Vector3(0.0, 0.105, -body_length * 0.34), dark)
    if weapon_class != "compact":
        _add_weapon_box(holder, "Front", Vector3(0.10, 0.10, body_length * 0.55), Vector3(0.0, 0.01, -body_length * 0.92), dark)
        _add_weapon_box(holder, "Stock", Vector3(0.16, 0.18, 0.30), Vector3(0.0, -0.01, 0.27), grip_material)

func _add_weapon_box(parent: Node3D, name_value: String, size: Vector3, pos: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.rotation_degrees = rotation_degrees_value
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance

func _spawn_muzzle_flash(player: CharacterBody3D) -> void:
    if _weapon_visual == null or not is_instance_valid(_weapon_visual) or _weapon_visual_owner_id != player.get_instance_id():
        return
    var flash := MeshInstance3D.new()
    flash.name = "MuzzleFlash"
    var mesh := SphereMesh.new()
    mesh.radius = 0.045
    mesh.height = 0.09
    mesh.radial_segments = 8
    mesh.rings = 4
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.72, 0.24, 1.0)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.36, 0.05, 1.0)
    material.emission_energy_multiplier = 2.5
    mesh.material = material
    flash.mesh = mesh
    flash.position = Vector3(0.0, 0.01, -0.92)
    _weapon_visual.add_child(flash)
    var tween := create_tween()
    tween.tween_property(flash, "scale", Vector3(1.7, 1.7, 1.7), 0.035)
    tween.tween_callback(flash.queue_free)

func _spawn_impact_marker(player: CharacterBody3D, position: Vector3) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var marker := MeshInstance3D.new()
    marker.name = "WeaponImpactMarker"
    var mesh := SphereMesh.new()
    mesh.radius = 0.028
    mesh.height = 0.056
    mesh.radial_segments = 6
    mesh.rings = 3
    marker.mesh = mesh
    marker.global_position = position
    scene.add_child(marker)
    var timer := get_tree().create_timer(0.16)
    timer.timeout.connect(marker.queue_free)

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _player_camera(player: CharacterBody3D) -> Camera3D:
    if player == null:
        return null
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera != null:
        return camera
    for node: Node in player.find_children("*", "Camera3D", true, false):
        if node is Camera3D:
            return node as Camera3D
    return null

func _npc_from_collider(value: Variant) -> NpcAgent:
    if not value is Node:
        return null
    var current := value as Node
    while current != null:
        if current is NpcAgent:
            return current as NpcAgent
        current = current.get_parent()
    return null

func _reset_ammo() -> void:
    _ammo.clear()
    for raw_id: Variant in WEAPON_PROFILES.keys():
        var weapon_id := StringName(raw_id)
        var profile := weapon_profile(weapon_id)
        _ammo[weapon_id] = {
            "mag": int(profile.get("mag_size", 0)),
            "reserve": int(profile.get("reserve", 0)),
        }

func ammo_state(weapon_id: StringName) -> Dictionary:
    if not _ammo.has(weapon_id) and WEAPON_PROFILES.has(weapon_id):
        var profile := weapon_profile(weapon_id)
        _ammo[weapon_id] = {
            "mag": int(profile.get("mag_size", 0)),
            "reserve": int(profile.get("reserve", 0)),
        }
    return (_ammo.get(weapon_id, {}) as Dictionary).duplicate()

func _refresh_hud(player: CharacterBody3D) -> void:
    _ensure_hud()
    if _hud_label == null:
        return
    if not is_armed():
        _hud_label.text = "1 MAINS NUES   |   CLIC/F: FRAPPER   |   CLIC DROIT/G: GARDE\n2 BX-9   3 CBR-4   4 SCT-8"
        if _crosshair != null:
            _crosshair.visible = false
        return
    var profile := weapon_profile(_equipped_weapon)
    var state := ammo_state(_equipped_weapon)
    var mode := "VISEE" if _aiming else "HANCHE"
    var reload_text := "   RECHARGEMENT" if _reload_until_ms > Time.get_ticks_msec() else ""
    _hud_label.text = "%s   %d/%d   %s%s\nCLIC: TIR   RMB: VISER   R: RECHARGER   1: RANGER" % [
        String(profile.get("label", _equipped_weapon)),
        int(state.get("mag", 0)),
        int(state.get("reserve", 0)),
        mode,
        reload_text,
    ]
    if _crosshair != null:
        _crosshair.visible = true
        _crosshair.text = "+" if _aiming else "·"
    player.set_meta("combat_weapon_mag", int(state.get("mag", 0)))
    player.set_meta("combat_weapon_reserve", int(state.get("reserve", 0)))

func _ensure_hud() -> void:
    if _hud_label != null and is_instance_valid(_hud_label):
        return
    var layer := CanvasLayer.new()
    layer.name = "CombatArsenalHUD"
    layer.layer = 20
    add_child(layer)
    _hud_label = Label.new()
    _hud_label.name = "CombatArsenalStatus"
    _hud_label.position = Vector2(26.0, 630.0)
    _hud_label.size = Vector2(930.0, 74.0)
    _hud_label.add_theme_font_size_override("font_size", 18)
    layer.add_child(_hud_label)
    _crosshair = Label.new()
    _crosshair.name = "CombatCrosshair"
    _crosshair.position = Vector2(630.0, 342.0)
    _crosshair.size = Vector2(28.0, 28.0)
    _crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _crosshair.add_theme_font_size_override("font_size", 25)
    _crosshair.visible = false
    layer.add_child(_crosshair)

func _flash_status(text: String, duration_ms: int) -> void:
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime != null and melee_runtime.has_method("_show_feedback"):
        melee_runtime.call("_show_feedback", text, duration_ms)

static func melee_move(index: int) -> Dictionary:
    if MELEE_MOVES.is_empty():
        return {}
    return MELEE_MOVES[posmod(index, MELEE_MOVES.size())].duplicate(true)

static func weapon_profile(weapon_id: StringName) -> Dictionary:
    if not WEAPON_PROFILES.has(weapon_id):
        return {}
    return (WEAPON_PROFILES[weapon_id] as Dictionary).duplicate(true)

static func damage_at_distance(base_damage: float, distance_m: float, range_m: float, min_factor: float) -> float:
    if base_damage <= 0.0:
        return 0.0
    var safe_range := maxf(range_m, 0.001)
    var t := clampf(maxf(distance_m, 0.0) / safe_range, 0.0, 1.0)
    var eased := t * t
    return base_damage * lerpf(1.0, clampf(min_factor, 0.0, 1.0), eased)

static func spread_for_state(profile: Dictionary, aiming: bool, speed_mps: float) -> float:
    var base := float(profile.get("aim_spread_deg", 1.0)) if aiming else float(profile.get("hip_spread_deg", 2.0))
    var movement_factor := clampf(maxf(speed_mps, 0.0) / 7.0, 0.0, 1.0)
    return maxf(0.0, base + float(profile.get("move_spread_deg", 0.0)) * movement_factor)

func current_spread_deg(player: CharacterBody3D, profile: Dictionary, aiming: bool) -> float:
    var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
    return spread_for_state(profile, aiming, horizontal_speed)
