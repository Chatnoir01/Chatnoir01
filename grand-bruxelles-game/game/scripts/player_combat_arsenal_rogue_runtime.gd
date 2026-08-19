extends "res://game/scripts/player_combat_arsenal_hardened_runtime.gd"

# Rogue/KayKit native-loadout bridge.
# The imported Rogue GLB already contains weapon meshes under handslot.l/r.
# This runtime makes exactly one of them a real game weapon instead of layering
# procedural weapons on top of baked knives/crossbows.

const CROSSBOW_ID := &"crossbow"
const NATIVE_CROSSBOW_NODE := "1H_Crossbow"
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

var _crossbow_mag := CROSSBOW_MAG_SIZE
var _crossbow_reserve := CROSSBOW_RESERVE_START
var _crossbow_reload_until_ms := 0
var _crossbow_bolt_serial := 0
var _native_owner_id := 0
var _native_nodes: Dictionary = {}

func _ready() -> void:
    super._ready()
    process_priority = -5
    call_deferred("_sanitize_initial_native_loadout")

func _input(event: InputEvent) -> void:
    var player := _current_player()
    if player == null:
        return
    if event is InputEventKey:
        var key_event := event as InputEventKey
        if not key_event.echo and key_event.pressed:
            if key_event.keycode == KEY_1:
                equip_weapon(player, CROSSBOW_ID)
                get_viewport().set_input_as_handled()
                return
            if key_event.keycode == KEY_5:
                equip_weapon(player, &"")
                get_viewport().set_input_as_handled()
                return
    super._input(event)

func _process(delta: float) -> void:
    super._process(delta)
    var player := _current_player()
    if player == null:
        return
    _sync_native_weapon_visibility(player)
    if _crossbow_reload_until_ms > 0 and Time.get_ticks_msec() >= _crossbow_reload_until_ms:
        _finish_crossbow_reload(player)

func is_armed() -> bool:
    return _equipped_weapon == CROSSBOW_ID or super.is_armed()

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if weapon_id == CROSSBOW_ID:
        # Reuse the validated base holster path to remove any procedural holder,
        # then promote the imported handslot crossbow to the canonical weapon.
        super.equip_weapon(player, &"")
        _trigger_held = false
        _aiming = false
        _reload_until_ms = 0
        _reload_weapon = &""
        _crossbow_reload_until_ms = 0
        _equipped_weapon = CROSSBOW_ID
        player.set_meta("combat_weapon_id", CROSSBOW_ID)
        player.set_meta("combat_weapon_aiming", false)
        player.set_meta("combat_weapon_reloading", false)
        player.set_meta("combat_native_weapon_mode", "crossbow")
        _sync_native_weapon_visibility(player, true)
        _refresh_hud(player)
        _flash_status("ARBALETE EQUIPEE", 520)
        return true

    var equipped := super.equip_weapon(player, weapon_id)
    if equipped:
        _crossbow_reload_until_ms = 0
        player.set_meta("combat_native_weapon_mode", "hidden")
        _sync_native_weapon_visibility(player, true)
    return equipped

func ammo_state(weapon_id: StringName) -> Dictionary:
    if weapon_id == CROSSBOW_ID:
        return {"mag": _crossbow_mag, "reserve": _crossbow_reserve}
    return super.ammo_state(weapon_id)

func request_reload(player: CharacterBody3D) -> bool:
    if _equipped_weapon != CROSSBOW_ID:
        return super.request_reload(player)
    if player == null or not is_instance_valid(player):
        return false
    if _crossbow_reload_until_ms > Time.get_ticks_msec():
        return false
    if _crossbow_mag >= CROSSBOW_MAG_SIZE or _crossbow_reserve <= 0:
        return false
    _crossbow_reload_until_ms = Time.get_ticks_msec() + CROSSBOW_RELOAD_MS
    player.set_meta("combat_weapon_reloading", true)
    player.set_meta("combat_crossbow_reload_until_ms", _crossbow_reload_until_ms)
    _flash_status("ARBALETE · RECHARGEMENT", 420)
    _refresh_hud(player)
    return true

func request_fire(player: CharacterBody3D) -> Dictionary:
    if _equipped_weapon != CROSSBOW_ID:
        return super.request_fire(player)
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"fired": false, "reason": "player_unavailable"}
    var now := Time.get_ticks_msec()
    if _crossbow_reload_until_ms > now:
        return {"fired": false, "reason": "reloading"}
    if now < _next_fire_ms:
        return {"fired": false, "reason": "cadence"}
    if _crossbow_mag <= 0:
        if _crossbow_reserve > 0:
            request_reload(player)
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
            var factor := lerpf(1.0, CROSSBOW_MIN_DAMAGE_FACTOR, clampf(distance_m / CROSSBOW_RANGE_M, 0.0, 1.0))
            damage = CROSSBOW_DAMAGE * factor
            if _apply_weapon_hit(npc, player, damage):
                hit_count = 1
        else:
            _spawn_impact_marker(player, end)

    _spawn_crossbow_bolt(player, end)
    _notify_weapon_incident(player, now)
    _refresh_hud(player)
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
    _flash_status("ARBALETE PRETE", 300)

func _sanitize_initial_native_loadout() -> void:
    var player := _current_player()
    if player == null:
        for _attempt: int in range(240):
            await get_tree().process_frame
            player = _current_player()
            if player != null:
                break
    if player == null:
        return
    _sync_native_weapon_visibility(player, true)

func _sync_native_weapon_visibility(player: CharacterBody3D, force_rescan: bool = false) -> void:
    if player == null or not is_instance_valid(player):
        return
    var owner_id := player.get_instance_id()
    if force_rescan or _native_owner_id != owner_id:
        _native_owner_id = owner_id
        _native_nodes.clear()
    var found := 0
    var crossbow_active := _equipped_weapon == CROSSBOW_ID
    for node_name: String in NATIVE_WEAPON_NODES:
        var native: Node3D = _native_nodes.get(node_name) as Node3D
        if native == null or not is_instance_valid(native):
            native = player.find_child(node_name, true, false) as Node3D
            if native != null:
                _native_nodes[node_name] = native
        if native == null:
            continue
        found += 1
        native.visible = crossbow_active and node_name == NATIVE_CROSSBOW_NODE
    player.set_meta("combat_native_weapon_nodes_found", found)
    player.set_meta("combat_native_weapon_inventory_sanitized", found == NATIVE_WEAPON_NODES.size())
    player.set_meta("combat_native_crossbow_visible", crossbow_active and _native_nodes.has(NATIVE_CROSSBOW_NODE))

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

func _refresh_hud(player: CharacterBody3D) -> void:
    if _equipped_weapon == CROSSBOW_ID:
        _ensure_hud()
        if _hud_label != null:
            var reload_text := " · RECHARGEMENT" if _crossbow_reload_until_ms > Time.get_ticks_msec() else ""
            var mode := "VISEE" if _aiming else "HANCHE"
            _hud_label.text = "ARBALETE · %d/%d · %s%s\nCLIC: TIR · RMB: VISER · R: RECHARGER · 5: RANGER" % [_crossbow_mag, _crossbow_reserve, mode, reload_text]
        if _crosshair != null:
            _crosshair.visible = true
        return
    super._refresh_hud(player)
    if _hud_label != null:
        _hud_label.text = _hud_label.text.replace("1 MAINS NUES", "5 MAINS NUES")
        _hud_label.text = _hud_label.text.replace("2 BX-9", "1 ARBALETE   2 BX-9")
        _hud_label.text = _hud_label.text.replace("1: RANGER", "5: RANGER")
