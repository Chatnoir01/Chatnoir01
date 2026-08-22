extends "res://game/scripts/player_combat_arsenal_hardened_runtime.gd"

# Combat weapon polish owner.
# Keeps the proven Combat V3 gun/melee resolver and adds one authoritative
# equipment state machine for visual ownership, native Rogue accessories,
# crossbow/knife modes and safe input locking during transitions.

const CROSSBOW_ID := &"crossbow"
const KNIFE_ID := &"knife"
const STATE_STOWED := &"stowed"
const STATE_HOLSTERING := &"holstering"
const STATE_EQUIPPING := &"equipping"
const STATE_EQUIPPED := &"equipped"
const HOLSTER_MS := 170
const EQUIP_MS := 220
const SWITCH_ACTION_LOCK_EXTRA_MS := 35

const NATIVE_CROSSBOW_NODE := "2H_Crossbow"
const NATIVE_KNIFE_NODE := "Knife"
const NATIVE_WEAPON_NODES: Array[String] = [
    "Knife_Offhand",
    "1H_Crossbow",
    "2H_Crossbow",
    "Knife",
    "Throwable",
]

const CROSSBOW_MAG_SIZE := 1
const CROSSBOW_RESERVE_START := 24
const CROSSBOW_RELOAD_MS := 920
const CROSSBOW_FIRE_INTERVAL_MS := 640
const CROSSBOW_RANGE_M := 72.0
const CROSSBOW_DAMAGE := 34.0
const CROSSBOW_MIN_DAMAGE_FACTOR := 0.50
const CROSSBOW_HIP_SPREAD_DEG := 1.15
const CROSSBOW_AIM_SPREAD_DEG := 0.42

const KNIFE_MOVE := {
    "id": &"knife_slash_right",
    "label": "TAILLADE",
    "limb": "RightArm",
    "windup_s": 0.085,
    "active_s": 0.105,
    "recover_s": 0.235,
    "yaw_deg": 31.0,
    "roll_deg": -8.0,
    "lunge_m": 0.10,
    "limb_x_deg": -68.0,
    "limb_z_deg": 34.0,
}

var _weapon_state: StringName = STATE_STOWED
var _switch_target: StringName = &""
var _switch_from: StringName = &""
var _switch_phase_started_ms := 0
var _switch_phase_end_ms := 0
var _switch_serial := 0
var _queued_switch_pending := false
var _queued_switch_target: StringName = &""

var _native_owner_id := 0
var _native_nodes: Dictionary = {}
var _crossbow_mag := CROSSBOW_MAG_SIZE
var _crossbow_reserve := CROSSBOW_RESERVE_START
var _crossbow_reload_until_ms := 0
var _crossbow_bolt_serial := 0
var _shot_ray_records: Array[Dictionary] = []

func _ready() -> void:
    super._ready()
    process_priority = -5
    call_deferred("_sanitize_initial_native_loadout")

func _process(delta: float) -> void:
    super._process(delta)
    var player := _current_player()
    if player == null:
        return
    _sync_native_weapon_visibility(player)
    _tick_weapon_switch(player)
    if _crossbow_reload_until_ms > 0 and Time.get_ticks_msec() >= _crossbow_reload_until_ms:
        _finish_crossbow_reload(player)
    _publish_equipment_slots(player)

func _input(event: InputEvent) -> void:
    var player := _current_player()
    if player == null:
        return

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if not key_event.echo and key_event.pressed:
            if key_event.keycode == KEY_5:
                equip_weapon(player, CROSSBOW_ID)
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_6:
                equip_weapon(player, KNIFE_ID)
                get_viewport().set_input_as_handled()
                return

    if _is_switching():
        if event is InputEventMouseButton or event is InputEventKey:
            _trigger_held = false
            _aiming = false
            player.set_meta("combat_weapon_aiming", false)
            if event is InputEventMouseButton:
                get_viewport().set_input_as_handled()
                return

    # Knife uses primary click as a contact-timed melee attack. RMB remains
    # available to the melee runtime for guard rather than enabling gun aim.
    if _equipped_weapon == KNIFE_ID and not _is_switching() and event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
            request_fire(player)
            get_viewport().set_input_as_handled()
            return
        if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
            return

    super._input(event)

func is_armed() -> bool:
    return _equipped_weapon == CROSSBOW_ID or _equipped_weapon == KNIFE_ID or super.is_armed()

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if not _is_supported_weapon(weapon_id):
        return false

    if _is_switching():
        _queued_switch_pending = true
        _queued_switch_target = weapon_id
        player.set_meta("combat_weapon_switch_queued", true)
        player.set_meta("combat_weapon_switch_queued_target", weapon_id)
        return true

    if weapon_id == _equipped_weapon:
        if weapon_id == &"":
            _set_weapon_state(player, STATE_STOWED)
        else:
            _set_weapon_state(player, STATE_EQUIPPED)
        _sync_native_weapon_visibility(player, true)
        _refresh_hud(player)
        return true

    _cancel_actions_for_switch(player)
    _switch_target = weapon_id
    _switch_from = _equipped_weapon
    _switch_serial += 1
    player.set_meta("combat_weapon_switch_serial", _switch_serial)
    player.set_meta("combat_weapon_switch_from", _switch_from)
    player.set_meta("combat_weapon_switch_target", _switch_target)

    if _equipped_weapon != &"":
        _begin_switch_phase(player, STATE_HOLSTERING, HOLSTER_MS)
        _flash_status("RANGEMENT...", 220)
        return true

    if weapon_id == &"":
        _set_weapon_state(player, STATE_STOWED)
        return true

    if not _apply_equipped_weapon_now(player, weapon_id):
        _set_weapon_state(player, STATE_STOWED)
        return false
    _begin_switch_phase(player, STATE_EQUIPPING, EQUIP_MS)
    _flash_status("EQUIPEMENT...", 240)
    return true

func request_fire(player: CharacterBody3D) -> Dictionary:
    if _is_switching():
        return {"fired": false, "reason": "switching", "state": _weapon_state}
    if _equipped_weapon == KNIFE_ID:
        return _request_knife_attack(player)
    _shot_ray_records.clear()
    if _equipped_weapon == CROSSBOW_ID:
        return _request_crossbow_fire(player)
    return super.request_fire(player)

func request_reload(player: CharacterBody3D) -> bool:
    if _is_switching():
        return false
    if _equipped_weapon == KNIFE_ID:
        return false
    if _equipped_weapon == CROSSBOW_ID:
        return _request_crossbow_reload(player)
    return super.request_reload(player)

func set_aiming(player: CharacterBody3D, aiming: bool) -> bool:
    if _is_switching() or _equipped_weapon == KNIFE_ID:
        return false
    return super.set_aiming(player, aiming)

func _fire_ray(player: CharacterBody3D, camera: Camera3D, range_m: float, spread_deg: float) -> Dictionary:
    var result := super._fire_ray(player, camera, range_m, spread_deg)
    if not result.is_empty():
        _shot_ray_records.append(result.duplicate())
    return result

func _spawn_impact_marker(player: CharacterBody3D, position: Vector3) -> void:
    var record := _nearest_ray_record(position)
    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    if impact_runtime != null and impact_runtime.has_method("spawn_impact") and not record.is_empty():
        impact_runtime.call(
            "spawn_impact",
            position,
            record.get("normal", Vector3.UP),
            record.get("collider"),
            _equipped_weapon,
            1.0,
            &""
        )
        return
    super._spawn_impact_marker(player, position)

func _apply_weapon_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> bool:
    var applied := super._apply_weapon_hit(npc, player, damage)
    if not applied:
        return false
    var record := _ray_record_for_npc(npc)
    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    if impact_runtime != null and impact_runtime.has_method("spawn_impact") and not record.is_empty():
        impact_runtime.call(
            "spawn_impact",
            record.get("position", npc.global_position + Vector3.UP),
            record.get("normal", Vector3.UP),
            record.get("collider"),
            _equipped_weapon,
            clampf(damage / 40.0, 0.65, 1.35),
            &"body"
        )
    return true

func _tick_weapon_switch(player: CharacterBody3D) -> void:
    if not _is_switching():
        return
    var now := Time.get_ticks_msec()
    if now < _switch_phase_end_ms:
        return

    if _weapon_state == STATE_HOLSTERING:
        if not _apply_equipped_weapon_now(player, &""):
            _set_weapon_state(player, STATE_STOWED)
            return
        if _switch_target == &"":
            _finish_switch(player, STATE_STOWED)
            return
        if not _apply_equipped_weapon_now(player, _switch_target):
            _finish_switch(player, STATE_STOWED)
            return
        _begin_switch_phase(player, STATE_EQUIPPING, EQUIP_MS)
        return

    if _weapon_state == STATE_EQUIPPING:
        _finish_switch(player, STATE_EQUIPPED)

func _begin_switch_phase(player: CharacterBody3D, state: StringName, duration_ms: int) -> void:
    _weapon_state = state
    _switch_phase_started_ms = Time.get_ticks_msec()
    _switch_phase_end_ms = _switch_phase_started_ms + maxi(duration_ms, 1)
    player.set_meta("combat_weapon_state", state)
    player.set_meta("combat_weapon_switching", true)
    player.set_meta("combat_weapon_switch_phase_started_ms", _switch_phase_started_ms)
    player.set_meta("combat_weapon_switch_phase_end_ms", _switch_phase_end_ms)
    player.set_meta("combat_action_lock_until_ms", maxi(
        int(player.get_meta("combat_action_lock_until_ms", 0)),
        _switch_phase_end_ms + SWITCH_ACTION_LOCK_EXTRA_MS
    ))

func _finish_switch(player: CharacterBody3D, final_state: StringName) -> void:
    _set_weapon_state(player, final_state)
    player.set_meta("combat_weapon_switch_completed_ms", Time.get_ticks_msec())
    player.set_meta("combat_weapon_switch_queued", false)
    _switch_phase_started_ms = 0
    _switch_phase_end_ms = 0
    _switch_from = &""
    _switch_target = &""
    _sync_native_weapon_visibility(player, true)
    _refresh_hud(player)

    if _queued_switch_pending:
        var queued := _queued_switch_target
        _queued_switch_pending = false
        _queued_switch_target = &""
        if queued != _equipped_weapon:
            equip_weapon(player, queued)

func _set_weapon_state(player: CharacterBody3D, state: StringName) -> void:
    _weapon_state = state
    player.set_meta("combat_weapon_state", state)
    player.set_meta("combat_weapon_switching", state == STATE_HOLSTERING or state == STATE_EQUIPPING)

func _cancel_actions_for_switch(player: CharacterBody3D) -> void:
    _trigger_held = false
    _aiming = false
    _reload_until_ms = 0
    _reload_weapon = &""
    _crossbow_reload_until_ms = 0
    _next_fire_ms = 0
    player.set_meta("combat_weapon_aiming", false)
    player.set_meta("combat_weapon_reloading", false)
    player.set_meta("combat_crossbow_reload_until_ms", 0)
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime != null and melee_runtime.has_method("set_guarding"):
        melee_runtime.call("set_guarding", player, false)

func _apply_equipped_weapon_now(player: CharacterBody3D, weapon_id: StringName) -> bool:
    if weapon_id == CROSSBOW_ID or weapon_id == KNIFE_ID:
        if not super.equip_weapon(player, &""):
            return false
        _equipped_weapon = weapon_id
        _trigger_held = false
        _aiming = false
        player.set_meta("combat_weapon_id", weapon_id)
        player.set_meta("combat_weapon_aiming", false)
        player.set_meta("combat_weapon_reloading", false)
        player.set_meta("combat_native_weapon_mode", String(weapon_id))
        _clear_melee_buffer(player, "native_weapon_equipped")
        _sync_native_weapon_visibility(player, true)
        _refresh_hud(player)
        return true

    var equipped := super.equip_weapon(player, weapon_id)
    if equipped:
        player.set_meta("combat_native_weapon_mode", "hidden")
        _sync_native_weapon_visibility(player, true)
    return equipped

func _is_supported_weapon(weapon_id: StringName) -> bool:
    return weapon_id == &"" or weapon_id == CROSSBOW_ID or weapon_id == KNIFE_ID or WEAPON_PROFILES.has(weapon_id)

func _is_switching() -> bool:
    return _weapon_state == STATE_HOLSTERING or _weapon_state == STATE_EQUIPPING

func weapon_switch_progress() -> float:
    if not _is_switching() or _switch_phase_end_ms <= _switch_phase_started_ms:
        return 1.0
    return clampf(
        float(Time.get_ticks_msec() - _switch_phase_started_ms) / float(_switch_phase_end_ms - _switch_phase_started_ms),
        0.0,
        1.0
    )

func weapon_state() -> StringName:
    return _weapon_state

func _sanitize_initial_native_loadout() -> void:
    var player := _current_player()
    if player == null:
        for _attempt: int in range(360):
            await get_tree().process_frame
            player = _current_player()
            if player != null:
                break
    if player == null:
        return
    if _equipped_weapon == &"":
        _set_weapon_state(player, STATE_STOWED)
    else:
        _set_weapon_state(player, STATE_EQUIPPED)
    _sync_native_weapon_visibility(player, true)
    _publish_equipment_slots(player)

func _sync_native_weapon_visibility(player: CharacterBody3D, force_rescan: bool = false) -> void:
    if player == null or not is_instance_valid(player):
        return
    var owner_id := player.get_instance_id()
    if force_rescan or _native_owner_id != owner_id:
        _native_owner_id = owner_id
        _native_nodes.clear()

    var found := 0
    for node_name: String in NATIVE_WEAPON_NODES:
        var native := _native_nodes.get(node_name) as Node3D
        if native == null or not is_instance_valid(native):
            native = player.find_child(node_name, true, false) as Node3D
            if native != null:
                _native_nodes[node_name] = native
        if native == null:
            continue
        found += 1
        var should_show := false
        if _equipped_weapon == CROSSBOW_ID:
            should_show = node_name == NATIVE_CROSSBOW_NODE
        elif _equipped_weapon == KNIFE_ID:
            should_show = node_name == NATIVE_KNIFE_NODE
        native.visible = should_show

    player.set_meta("combat_native_weapon_nodes_found", found)
    player.set_meta("combat_native_weapon_inventory_sanitized", found == NATIVE_WEAPON_NODES.size())
    player.set_meta("combat_native_crossbow_visible", _equipped_weapon == CROSSBOW_ID and _native_nodes.has(NATIVE_CROSSBOW_NODE))
    player.set_meta("combat_native_knife_visible", _equipped_weapon == KNIFE_ID and _native_nodes.has(NATIVE_KNIFE_NODE))

func _publish_equipment_slots(player: CharacterBody3D) -> void:
    player.set_meta("combat_equipment_slot_main", _equipped_weapon)
    player.set_meta("combat_equipment_slot_back", &"")
    player.set_meta("combat_equipment_slot_hip", &"")
    var hidden: Array[StringName] = []
    for weapon_id: StringName in [CROSSBOW_ID, KNIFE_ID, &"bx9", &"cbr4", &"sct8"]:
        if weapon_id != _equipped_weapon:
            hidden.append(weapon_id)
    player.set_meta("combat_equipment_slot_inventory_hidden", hidden)
    player.set_meta("combat_equipment_single_active", true)

func _request_crossbow_reload(player: CharacterBody3D) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if _crossbow_reload_until_ms > Time.get_ticks_msec():
        return false
    if _crossbow_mag >= CROSSBOW_MAG_SIZE or _crossbow_reserve <= 0:
        return false
    _trigger_held = false
    _crossbow_reload_until_ms = Time.get_ticks_msec() + CROSSBOW_RELOAD_MS
    player.set_meta("combat_weapon_reloading", true)
    player.set_meta("combat_crossbow_reload_until_ms", _crossbow_reload_until_ms)
    player.set_meta("combat_action_lock_until_ms", maxi(int(player.get_meta("combat_action_lock_until_ms", 0)), _crossbow_reload_until_ms))
    _flash_status("ARBALETE · RECHARGEMENT", 420)
    _refresh_hud(player)
    return true

func _finish_crossbow_reload(player: CharacterBody3D) -> void:
    if _crossbow_reload_until_ms <= 0:
        return
    var needed := CROSSBOW_MAG_SIZE - _crossbow_mag
    var moved := mini(needed, _crossbow_reserve)
    _crossbow_mag += moved
    _crossbow_reserve -= moved
    _crossbow_reload_until_ms = 0
    player.set_meta("combat_weapon_reloading", false)
    player.set_meta("combat_crossbow_reload_until_ms", 0)
    _refresh_hud(player)
    _flash_status("ARBALETE PRETE", 260)

func _request_crossbow_fire(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"fired": false, "reason": "player_unavailable"}
    var now := Time.get_ticks_msec()
    if _crossbow_reload_until_ms > now:
        return {"fired": false, "reason": "reloading"}
    if now < _next_fire_ms:
        return {"fired": false, "reason": "cadence"}
    if _crossbow_mag <= 0:
        if _crossbow_reserve > 0:
            _request_crossbow_reload(player)
        else:
            _flash_status("PLUS DE CARREAUX", 360)
        return {"fired": false, "reason": "empty"}

    var camera := _player_camera(player)
    if camera == null:
        return {"fired": false, "reason": "camera_unavailable"}

    _crossbow_mag -= 1
    _next_fire_ms = now + CROSSBOW_FIRE_INTERVAL_MS
    player.set_meta("combat_crossbow_last_shot_ms", now)
    player.set_meta("combat_crossbow_shot_count", int(player.get_meta("combat_crossbow_shot_count", 0)) + 1)
    player.set_meta("combat_weapon_last_shot_ms", now)
    player.set_meta("combat_weapon_shot_count", int(player.get_meta("combat_weapon_shot_count", 0)) + 1)

    var spread_deg := CROSSBOW_AIM_SPREAD_DEG if _aiming else CROSSBOW_HIP_SPREAD_DEG
    var ray_result := _fire_ray(player, camera, CROSSBOW_RANGE_M, spread_deg)
    var direction := -camera.global_transform.basis.z.normalized()
    var end := camera.global_position + direction * CROSSBOW_RANGE_M
    var damage := 0.0
    var hit_count := 0
    if not ray_result.is_empty():
        end = ray_result.get("position", end)
        var npc := _npc_from_collider(ray_result.get("collider"))
        if npc != null:
            var distance_m := camera.global_position.distance_to(end)
            damage = damage_at_distance(CROSSBOW_DAMAGE, distance_m, CROSSBOW_RANGE_M, CROSSBOW_MIN_DAMAGE_FACTOR)
            if _apply_weapon_hit(npc, player, damage):
                hit_count = 1
        else:
            _spawn_impact_marker(player, end)

    _spawn_crossbow_bolt(player, end)
    _apply_recoil({"recoil_pitch_deg": 0.45, "recoil_yaw_deg": 0.08})
    _notify_weapon_incident(player, now)
    _refresh_hud(player)
    var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
    if pose_runtime != null and pose_runtime.has_method("request_shot_pose"):
        pose_runtime.call("request_shot_pose", player, CROSSBOW_ID)
    if hit_count > 0:
        _flash_status("CARREAU · IMPACT -%d" % int(round(damage)), 240)
    return {
        "fired": true,
        "weapon": CROSSBOW_ID,
        "targets_hit": hit_count,
        "damage": damage,
        "spread_deg": spread_deg,
        "ammo": _crossbow_mag,
        "visual": "bolt",
    }

func _request_knife_attack(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"fired": false, "reason": "player_unavailable"}
    var melee_runtime := get_node_or_null("/root/PlayerMeleeCombatRuntime")
    if melee_runtime == null or not melee_runtime.has_method("request_attack_with_move"):
        return {"fired": false, "reason": "melee_runtime_unavailable"}
    var result_variant: Variant = melee_runtime.call("request_attack_with_move", player, KNIFE_MOVE.duplicate(true))
    if not result_variant is Dictionary:
        return {"fired": false, "reason": "invalid_melee_result"}
    var result := result_variant as Dictionary
    if not bool(result.get("pending", false)):
        result["fired"] = false
        return result

    var total_ms := int(round((float(KNIFE_MOVE["windup_s"]) + float(KNIFE_MOVE["active_s"]) + float(KNIFE_MOVE["recover_s"])) * 1000.0))
    player.set_meta("combat_action_lock_until_ms", maxi(int(player.get_meta("combat_action_lock_until_ms", 0)), Time.get_ticks_msec() + total_ms))
    player.set_meta("combat_weapon_melee_attack", true)
    player.set_meta("combat_weapon_melee_id", KNIFE_ID)
    var pose_runtime := get_node_or_null("/root/CombatAuthoredPoseRuntime")
    if pose_runtime != null and pose_runtime.has_method("request_melee_pose"):
        pose_runtime.call("request_melee_pose", player, KNIFE_MOVE)
    _flash_status("TAILLADE", 180)
    result["fired"] = true
    result["weapon"] = KNIFE_ID
    return result

func _spawn_crossbow_bolt(player: CharacterBody3D, end: Vector3) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var crossbow := _native_nodes.get(NATIVE_CROSSBOW_NODE) as Node3D
    if crossbow == null or not is_instance_valid(crossbow):
        crossbow = player.find_child(NATIVE_CROSSBOW_NODE, true, false) as Node3D
    var camera := _player_camera(player)
    if camera == null:
        return
    var start := crossbow.global_position if crossbow != null else camera.global_position + (-camera.global_transform.basis.z * 0.55)
    var distance := start.distance_to(end)
    if distance < 0.10:
        return

    _crossbow_bolt_serial += 1
    var bolt := MeshInstance3D.new()
    bolt.name = "CrossbowBoltVisual_%d" % _crossbow_bolt_serial
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.012, 0.012, 0.34)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.16, 0.11, 0.06, 1.0)
    material.metallic = 0.12
    material.roughness = 0.62
    mesh.material = material
    bolt.mesh = mesh
    scene.add_child(bolt)
    bolt.global_position = start
    bolt.look_at(end, Vector3.UP, true)
    bolt.set_meta("combat_fx_kind", "crossbow_bolt")
    bolt.set_meta("combat_fx_weapon_id", CROSSBOW_ID)
    player.set_meta("combat_crossbow_bolt_visual_count", int(player.get_meta("combat_crossbow_bolt_visual_count", 0)) + 1)

    var travel_s := clampf(distance / 95.0, 0.055, 0.22)
    var tween := create_tween()
    tween.tween_property(bolt, "global_position", end, travel_s)
    tween.tween_callback(bolt.queue_free)

func ammo_state(weapon_id: StringName) -> Dictionary:
    if weapon_id == CROSSBOW_ID:
        return {"mag": _crossbow_mag, "reserve": _crossbow_reserve}
    if weapon_id == KNIFE_ID:
        return {"mag": 1, "reserve": 0}
    return super.ammo_state(weapon_id)

func _refresh_hud(player: CharacterBody3D) -> void:
    if _equipped_weapon != CROSSBOW_ID and _equipped_weapon != KNIFE_ID:
        super._refresh_hud(player)
        if _hud_label != null:
            if not is_armed():
                _hud_label.text = "1 MAINS NUES   |   CLIC/F: FRAPPER   |   CLIC DROIT/G: GARDE\n2 BX-9   3 CBR-4   4 SCT-8   5 ARBALETE   6 COUTEAU"
            else:
                _hud_label.text += "   |   5 ARBALETE   6 COUTEAU"
        return

    _ensure_hud()
    if _hud_label == null:
        return
    if _equipped_weapon == CROSSBOW_ID:
        var mode := "VISEE" if _aiming else "HANCHE"
        var reload_text := " · RECHARGEMENT" if _crossbow_reload_until_ms > Time.get_ticks_msec() else ""
        _hud_label.text = "ARBALETE · %d/%d · %s%s\nCLIC: TIR · RMB: VISER · R: RECHARGER · 1: RANGER" % [_crossbow_mag, _crossbow_reserve, mode, reload_text]
        if _crosshair != null:
            _crosshair.visible = true
            _crosshair.text = "+" if _aiming else "·"
        player.set_meta("combat_weapon_mag", _crossbow_mag)
        player.set_meta("combat_weapon_reserve", _crossbow_reserve)
        return

    _hud_label.text = "COUTEAU · MELEE\nCLIC: TAILLADE · CLIC DROIT/G: GARDE · 1: RANGER"
    if _crosshair != null:
        _crosshair.visible = false

func _nearest_ray_record(position: Vector3) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for record: Dictionary in _shot_ray_records:
        var hit_position: Vector3 = record.get("position", Vector3.INF)
        if hit_position == Vector3.INF:
            continue
        var distance := hit_position.distance_to(position)
        if distance < best_distance:
            best_distance = distance
            best = record
    return best

func _ray_record_for_npc(npc: NpcAgent) -> Dictionary:
    if npc == null:
        return {}
    for record: Dictionary in _shot_ray_records:
        if _npc_from_collider(record.get("collider")) == npc:
            return record
    return {}
